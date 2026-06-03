;; events.fnl -- the single entry point for WoW events into Routina.
;;
;; Every WoW event the addon reacts to is registered on ONE AceEvent frame and
;; routed through `dispatch`'s `case` table -- domain modules will later subscribe
;; to this dispatcher, never to WoW directly. The pure parts (`dispatch`,
;; `event-list`) are busted-testable with an injected fake logger; only `init!`
;; and `cleanup!` touch AceEvent, and they take the lib as a parameter so the
;; single LibStub lookup stays in src/core/ace.fnl.
;;
;; See .claude/examples/03-event-dispatcher.fnl. Phase 1 handlers are
;; intentionally thin (log + TODO) -- the lockouts/history domain they will call
;; lands in Phase 2.

(local Routina (or _G.Routina {}))
(local wow (or Routina.wow (require :src.core.wow)))

(local M {})

;; --- Logger + refresh (injected by init!/ace, or directly in tests) --------

(var log nil)

(var on-refresh nil)

(fn request-refresh []
  "Notify the UI that the plan inputs changed (gear, talents, bags, lockouts).
   No-op until a callback is injected via set-refresh!."
  (when on-refresh (on-refresh))
  nil)

;; --- Events we consume -----------------------------------------------------
;;
;; Conservative, TBC Classic 2.5.x-valid set. ENCOUNTER_END/BOSS_KILL are
;; deferred (no kill-tracking domain consumer yet) and need wiki confirmation
;; before use (CLAUDE.md: never invent WoW API signatures).

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
                   ;; fires before the SavedVariables disk write -> flush state
                   :PLAYER_LOGOUT])

(set M.event-list event-list)

;; --- Handlers (private, thin) ----------------------------------------------

(fn on-player-entering-world []
  (log:debug :PLAYER_ENTERING_WORLD)
  ;; Kick a saved-instance refresh; the server replies via UPDATE_INSTANCE_INFO,
  ;; after which wow.saved-instances has live data for the route planner.
  (wow.request-raid-info!)
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

(fn on-raid-instance-welcome [...]
  (log:debug :RAID_INSTANCE_WELCOME)
  ;; TODO Phase 2: mark the entered raid as in-progress.
  nil)

(fn on-player-logout []
  (log:debug :PLAYER_LOGOUT)
  ;; TODO Phase 2: flush in-memory weekly-state to the DB.
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

(lambda M.dispatch [event ...]
  "Route one WoW event to its handler. Pure aside from logging.
   Domain:  event : string -- the WoW event name; ... : the event payload
   Returns: nil. Unknown events are logged at :warn and otherwise ignored."
  (case event
    :PLAYER_ENTERING_WORLD (on-player-entering-world)
    :UPDATE_INSTANCE_INFO (on-update-instance-info)
    :RAID_INSTANCE_WELCOME (on-raid-instance-welcome ...)
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
