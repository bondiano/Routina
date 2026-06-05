;; events.fnl -- the single entry point for WoW events into Routina.
;;
;; Every WoW event the addon reacts to is registered on ONE AceEvent frame and
;; routed through `dispatch`'s `case` table -- domain modules will later subscribe
;; to this dispatcher, never to WoW directly. The pure parts (`dispatch`,
;; `event-list`) are busted-testable with an injected fake logger; only `init!`
;; and `cleanup!` touch AceEvent, and they take the lib as a parameter so the
;; single LibStub lookup stays in src/core/ace.fnl.
;;
;; See .claude/examples/03-event-dispatcher.fnl. RAID_INSTANCE_WELCOME and
;; PLAYER_LOGOUT drive the per-character weekly-state (src/domain/weekly-state.fnl):
;; entering a saved raid marks it in-progress, logout flushes the session to
;; db.char. The DB slot is injected via set-store! (src/core/ace.fnl OnEnable).

(local Routina (or _G.Routina {}))
(local wow (or Routina.wow (require :src.core.wow)))
(local weekly-state
       (or Routina.weekly-state (require :src.domain.weekly-state)))

(local history (or Routina.history (require :src.domain.history)))
(local drop-table (or Routina.drop-table (require :src.domain.drop-table)))
(local chains (or Routina.chains (require :src.domain.chains)))

(local M {})

;; --- Logger + refresh (injected by init!/ace, or directly in tests) --------

(var log nil)

(var on-refresh nil)

;; Per-character SavedVariables accessor + the live weekly-state for this
;; session. `get-char` is injected by src/core/ace.fnl (set-store!); `session`
;; is lazily seeded from db.char.weekly-state on first use and flushed back on
;; PLAYER_LOGOUT. Both stay nil under tests that never wire a store.
(var get-char nil)

(var session nil)

;; Cumulative luck history (src/domain/history.fnl): a live session copy seeded
;; from db.char.history and flushed on PLAYER_LOGOUT, gated by `history-tracking?`.
;; Tracking is OFF by default (experimental opt-in via the options toggle): when
;; on, ENCOUNTER_END / CHAT_MSG_LOOT feed record-run! / record-drop!. record-*!
;; no-op until set-history-tracking! turns it on.
(var history-session nil)

(var history-tracking? false)

;; Quest/attunement chain progress (src/domain/chains.fnl): a live
;; {chain-id -> ChainProgress} map seeded from db.char.chains, refreshed from
;; the quest log on PLAYER_ENTERING_WORLD, advanced by QUEST_TURNED_IN, and
;; flushed on PLAYER_LOGOUT. ON by default -- chains are a core feature, not
;; an experimental opt-in like the luck history.
(var chain-session nil)

(fn request-refresh []
  "Notify the UI that the plan inputs changed (gear, talents, bags, lockouts).
   No-op until a callback is injected via set-refresh!."
  (when on-refresh (on-refresh))
  nil)

(fn ensure-session [now]
  "Lazily seed the in-memory weekly-state from the persisted DB (normalising +
   pruning lockouts whose reset has passed), returning the live WeeklyState, or
   nil when no store is wired (e.g. before OnEnable, or in pure-dispatch tests)."
  (when (and (not session) get-char)
    (let [char (get-char)]
      (set session (weekly-state.normalize (and char char.weekly-state) now))))
  session)

(fn ensure-history []
  "Lazily seed the in-memory luck history from the persisted DB, returning the
   live History, or nil when tracking is off or no store is wired."
  (when (and history-tracking? (not history-session) get-char)
    (let [char (get-char)]
      (set history-session (history.normalize (and char char.history)))))
  history-session)

(fn ensure-chains []
  "Lazily seed the in-memory chain progress from the persisted DB, returning
   the live {chain-id -> ChainProgress} map, or nil when no store is wired."
  (when (and (not chain-session) get-char)
    (let [char (get-char)]
      (set chain-session (chains.normalize (and char char.chains)))))
  chain-session)

(fn seed-chains-from-quest-log []
  "Sweep wow.quest-completed? over every tracked quest-id and merge the result
   into each chain's persisted progress (union + backfill, idempotent), so an
   alt that finished steps before installing Routina starts honest. No-op when
   no store is wired."
  (let [progress-map (ensure-chains)]
    (when progress-map
      (let [flags (collect [qid (pairs (chains.tracked-quest-ids))]
                    (if (wow.quest-completed? qid) (values qid true)
                        (values nil nil)))]
        (each [_ chain (ipairs (chains.all))]
          (let [prior (or (. progress-map chain.id) (chains.empty-progress))
                seeded (chains.seed-from-completed chain flags)]
            (tset progress-map chain.id
                  (chains.merge-progress chain prior seeded)))))))
  nil)

;; --- Events we consume -----------------------------------------------------
;;
;; All TBC Classic 2.5.5 (BCC Anniversary) valid -- signatures verified against
;; warcraft.wiki.gg. ENCOUNTER_END / CHAT_MSG_LOOT feed the luck history but only
;; act while set-history-tracking! is on (off by default), so they are always
;; registered yet inert until the player opts in.

(local event-list [;; login / zone-in: kick off a raid-info request
                   :PLAYER_ENTERING_WORLD
                   ;; saved-instance data became available -> re-plan lockouts
                   :UPDATE_INSTANCE_INFO
                   ;; stepped into a raid we are already saved to
                   :RAID_INSTANCE_WELCOME
                   ;; route inputs changed -> re-plan: gear, bags, talents
                   :PLAYER_EQUIPMENT_CHANGED
                   :BAG_UPDATE_DELAYED
                   :CHARACTER_POINTS_CHANGED
                   ;; boss kill -> tally a luck-history trial (gated)
                   :ENCOUNTER_END
                   ;; loot received -> tally a luck-history drop (gated)
                   :CHAT_MSG_LOOT
                   ;; quest turned in -> advance any chain carrying it
                   :QUEST_TURNED_IN
                   ;; fires before the SavedVariables disk write -> flush state
                   :PLAYER_LOGOUT])

(set M.event-list event-list)

;; --- Handlers (private, thin) ----------------------------------------------

(fn on-player-entering-world []
  (log:debug :PLAYER_ENTERING_WORLD)
  ;; Kick a saved-instance refresh; the server replies via UPDATE_INSTANCE_INFO,
  ;; after which wow.saved-instances has live data for the route planner.
  (wow.request-raid-info!)
  ;; Refresh chain progress from the quest log (idempotent union, so the
  ;; re-fires on /reload and instance transitions are harmless).
  (seed-chains-from-quest-log)
  (request-refresh)
  nil)

(fn on-update-instance-info []
  (log:debug :UPDATE_INSTANCE_INFO)
  ;; Lockout data is now available; the Plan tab reads it on demand via
  ;; src/core/planner.fnl (wow.saved-instances). Re-plan to reflect it.
  (request-refresh)
  nil)

(fn on-inputs-changed [event]
  "Gear / bag / talent change -> the plan's gap, owned-items or spec may shift."
  (log:debug event)
  (request-refresh)
  nil)

(fn on-raid-instance-welcome [instance-name ?time-until-reset]
  "Stepping into a raid we are saved to -> record it in-progress for this week.
   WoW payload: instanceName, timeUntilReset (seconds). The reset is folded into
   server-time so weekly-state can prune it once the week rolls over."
  (log:debug :RAID_INSTANCE_WELCOME)
  (let [now (wow.now)
        state (ensure-session now)]
    (when state
      (let [reset-at (if (= (type ?time-until-reset) :number)
                         (+ now ?time-until-reset)
                         0)]
        (set session
             (weekly-state.mark-in-progress state (tostring instance-name) now
                                            reset-at)))))
  nil)

(fn on-encounter-end [_encounter-id
                      encounter-name
                      _difficulty
                      _group-size
                      success]
  "ENCOUNTER_END (TBC 2.5.5): encounterID, encounterName, difficultyID, groupSize,
   success (1 = kill). On a kill, tally one trial for the boss (encounterName)
   into the luck history -- the per-kill denominator bayesian-luck needs. No-op
   unless luck tracking is on. (The boss-name -> drop-table :boss match is the
   open validation item; see ROADMAP Phase 4 §1.)"
  (log:debug :ENCOUNTER_END)
  (when (and history-tracking? encounter-name
             (or (= success 1) (= success true)))
    (M.record-run! encounter-name))
  nil)

(fn on-chat-msg-loot [text]
  "CHAT_MSG_LOOT (TBC 2.5.5): the message text first. Tally a drop only for the
   player's OWN loot (wow.self-loot?) of a tracked item (one in the drop-table) --
   group-mates' loot and untracked junk are ignored. No-op unless tracking is on."
  (log:debug :CHAT_MSG_LOOT)
  (when history-tracking?
    (let [item-id (wow.loot-item-id text)]
      (when (and item-id (wow.self-loot? text) (drop-table.for-item item-id))
        (M.record-drop! item-id))))
  nil)

(fn on-quest-turned-in [quest-id]
  "QUEST_TURNED_IN (TBC 2.5.5): questID, xpReward, moneyReward. Advance every
   chain carrying this quest (record-quest marks the step and backfills its
   non-quest predecessors), then re-plan -- a finished attunement step can
   change both the Chains tab and the weekly plan's gates."
  (log:debug :QUEST_TURNED_IN)
  (when (= (type quest-id) :number)
    (let [affected (chains.chains-with-quest quest-id)
          progress-map (and (> (length affected) 0) (ensure-chains))]
      (when progress-map
        (each [_ chain (ipairs affected)]
          (let [prior (or (. progress-map chain.id) (chains.empty-progress))]
            (tset progress-map chain.id
                  (chains.record-quest chain prior quest-id))))
        (request-refresh))))
  nil)

(fn on-player-logout []
  "Fires before the SavedVariables disk write -> flush the session's accumulated
   weekly-state into db.char so this week's progress survives the logout."
  (log:debug :PLAYER_LOGOUT)
  (when (and get-char (or session history-session chain-session))
    (let [char (get-char)]
      (when char
        (when session (set char.weekly-state (weekly-state.to-db session)))
        (when history-session
          (set char.history (history.to-db history-session)))
        (when chain-session
          (set char.chains (chains.to-db chain-session))))))
  nil)

;; --- Public API ------------------------------------------------------------

(lambda M.set-logger! [logger]
  "Inject the logger handlers and the dispatcher log through.
   Domain:  logger : table with :debug/:info/:warn/:error methods
   Returns: nil."
  (set log logger)
  nil)

(lambda M.set-refresh! [?callback]
  "Inject (or clear, with nil) the UI-refresh callback fired when plan inputs
   change.
   Domain:  ?callback : fn [] | nil -- e.g. a debounced src/ui/root.fnl refresh!
   Returns: nil."
  (set on-refresh ?callback)
  nil)

(lambda M.set-store! [?char-getter]
  "Inject (or clear, with nil) the accessor for the per-character SavedVariables
   table the weekly-state persists under, and drop any live session so it
   re-seeds from the (possibly new) store on next use.
   Domain:  ?char-getter : fn [] -> db.char table | nil
   Returns: nil."
  (set get-char ?char-getter)
  (set session nil)
  (set history-session nil)
  (set chain-session nil)
  nil)

(lambda M.set-history-tracking! [?on]
  "Enable (or disable) cumulative luck-history recording. OFF by default
   (experimental): when on, the always-registered ENCOUNTER_END / CHAT_MSG_LOOT
   handlers feed record-run! / record-drop!. Disabling drops the live session (it
   re-seeds on the next record once re-enabled).
   Domain:  ?on : boolean | nil (nil reads as off)
   Returns: nil."
  (set history-tracking? (and ?on true))
  (when (not history-tracking?) (set history-session nil))
  nil)

(lambda M.record-run! [activity-id]
  "Record one completed run of an activity into the live luck history. No-op
   unless history tracking is on and a store is wired. Intended to be called from
   a confirmed boss-kill / encounter-end event handler.
   Domain:  activity-id : string|keyword -- the ActivityDef id that was cleared
   Returns: nil."
  (let [hist (ensure-history)]
    (when hist (set history-session (history.record-run hist activity-id))))
  nil)

(lambda M.reset-history! []
  "Reset the cumulative luck history (/rt reset): drop the live session and
   overwrite the persisted db.char.history with an empty record, so both the
   running session and the next login start from zero. Safe with no store wired.
   Domain:  (none)
   Returns: nil."
  (set history-session nil)
  (when get-char
    (let [char (get-char)]
      (when char
        (set char.history (history.to-db (history.empty))))))
  nil)

(lambda M.record-drop! [item-id]
  "Record one observed item drop into the live luck history. No-op unless history
   tracking is on and a store is wired. Intended to be called from a confirmed
   loot event handler.
   Domain:  item-id : integer|string -- the item that dropped
   Returns: nil."
  (let [hist (ensure-history)]
    (when hist (set history-session (history.record-drop hist item-id))))
  nil)

(lambda M.dispatch [event ...]
  "Route one WoW event to its handler. Pure aside from logging.
   Domain:  event : string -- the WoW event name; ... : the event payload
   Returns: nil. Unknown events are logged at :warn and otherwise ignored."
  (case event
    :PLAYER_ENTERING_WORLD (on-player-entering-world)
    :UPDATE_INSTANCE_INFO (on-update-instance-info)
    :RAID_INSTANCE_WELCOME (on-raid-instance-welcome ...)
    :ENCOUNTER_END (on-encounter-end ...)
    :CHAT_MSG_LOOT (on-chat-msg-loot ...)
    :QUEST_TURNED_IN (on-quest-turned-in ...)
    :PLAYER_EQUIPMENT_CHANGED (on-inputs-changed :PLAYER_EQUIPMENT_CHANGED)
    :BAG_UPDATE_DELAYED (on-inputs-changed :BAG_UPDATE_DELAYED)
    :CHARACTER_POINTS_CHANGED (on-inputs-changed :CHARACTER_POINTS_CHANGED)
    :PLAYER_LOGOUT (on-player-logout)
    _ (log:warn (.. "Unhandled event: " (tostring event))))
  nil)

(lambda M.init! [ace-event logger]
  "Embed an AceEvent frame and subscribe every event in event-list.
   Domain:  ace-event : the AceEvent-3.0 library; logger : a logger table
   Returns: the event frame (pass to cleanup! on disable)."
  (M.set-logger! logger)
  (let [frame {}]
    (ace-event:Embed frame)
    (each [_ event (ipairs event-list)]
      (frame:RegisterEvent event
                           (fn [_ event-name ...] (M.dispatch event-name ...))))
    (log:debug "Event dispatcher initialized")
    frame))

(lambda M.cleanup! [?frame]
  "Unregister all events on the frame. Safe to call with nil.
   Domain:  ?frame : an embedded AceEvent frame, or nil
   Returns: nil."
  (when ?frame (?frame:UnregisterAllEvents))
  nil)

;; --- Register into the addon namespace -------------------------------------

(set _G.Routina Routina)
(set Routina.events M)

M
