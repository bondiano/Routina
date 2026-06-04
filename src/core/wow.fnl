;; wow.fnl -- the one boundary between WoW's impure world and our pure domain.
;;
;; Captures the WoW globals we read at module top (fast locals + test-overridable
;; via spec/mocks/wow-api.fnl). Every public fn translates WoW's tuple/bitmask
;; returns into kebab-keyed domain tables (validated against src/domain/schemas)
;; and NEVER throws -- WoW APIs return nil during loading screens and zone
;; transitions, so failures come back as {:ok false :err ...}.
;;
;; See .claude/examples/02-wow-api-wrapper.fnl. Two deliberate deviations from
;; that example, both forced by project rules:
;;   - :reset-at uses GetServerTime (via M.now), not os.time (CLAUDE.md: no
;;     os.time for game time).
;;   - the "is this lockout live?" guard treats WoW's numeric 0/1 returns
;;     explicitly: Lua counts 0 as truthy, so a naive (not extended) would drop
;;     every lockout when the API hands back 0.

(local GetServerTime _G.GetServerTime)
(local UnitName _G.UnitName)
(local UnitClass _G.UnitClass)
(local GetRealmName _G.GetRealmName)
(local GetNumSavedInstances _G.GetNumSavedInstances)
(local GetSavedInstanceInfo _G.GetSavedInstanceInfo)
(local GetSavedInstanceEncounterInfo _G.GetSavedInstanceEncounterInfo)
(local bit _G.bit)

;; Route-input reads (Phase 2). Captured at load like the rest; the container /
;; quest APIs are resolved defensively at call time because TBC Anniversary may
;; expose either the legacy globals or the newer C_* namespaces.
(local UnitLevel _G.UnitLevel)
(local GetInventoryItemID _G.GetInventoryItemID)
(local GetNumTalentTabs _G.GetNumTalentTabs)
(local GetTalentTabInfo _G.GetTalentTabInfo)
(local GetFactionInfoByID _G.GetFactionInfoByID)
(local RequestRaidInfo _G.RequestRaidInfo)
(local C_QuestLog _G.C_QuestLog)
(local IsQuestFlaggedCompleted _G.IsQuestFlaggedCompleted)
(local C_Container _G.C_Container)
(local GetContainerItemID _G.GetContainerItemID)
(local GetContainerNumSlots _G.GetContainerNumSlots)

;; Equipment slots 1..19 (head..tabard) and the containers we scan for owned
;; gear: backpack (0), bags (1-4), main bank (-1) and bank bags (5-11). Bank
;; containers report 0 slots away from a banker, so scanning them is harmless.
(local last-equipped-slot 19)
(local scan-bags [0 1 2 3 4 -1 5 6 7 8 9 10 11])

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; --- Helpers (private) -----------------------------------------------------

(fn wow-true? [v]
  "Coerce a WoW boolean-ish return to a real boolean.
   WoW hands back booleans live but the test mock uses 0/1, and Lua treats 0 as
   truthy -- so nil, false and 0 must all read as false here."
  (and (not= v nil) (not= v false) (not= v 0)))

(fn parse-encounter-progress [progress-bitmask n-encounters encounter-names]
  "Translate WoW's progress bitmask into a sequence of Encounter tables.
   Bit i set => encounter i+1 killed."
  (let [out []]
    (for [i 1 n-encounters]
      (let [mask (bit.lshift 1 (- i 1))
            killed? (not= 0 (bit.band progress-bitmask mask))]
        (table.insert out {:name (. encounter-names i) : killed?})))
    out))

(fn fetch-encounter-names [instance-index n-encounters]
  "Pull encounter names via the per-encounter API. Returns a sequence of strings."
  (let [names []]
    (for [i 1 n-encounters]
      (let [(name) (GetSavedInstanceEncounterInfo instance-index i)]
        (table.insert names (or name (.. "Encounter " i)))))
    names))

(fn read-lockout [index now]
  "Read one saved instance into a Lockout table, or nil if it is not live.
   `now` is passed in so a whole fetch shares a single server-time read."
  (let [(name lockout-id reset locked extended _max-players difficulty-name
              n-encounters encounter-progress _ _ is-raid) (GetSavedInstanceInfo index)]
    (when (and name (wow-true? locked) (not (wow-true? extended)))
      (let [encounter-names (fetch-encounter-names index n-encounters)]
        {: name
         :instance-id lockout-id
         :reset-at (+ now reset)
         :difficulty (if (= difficulty-name :Heroic) :heroic :normal)
         :is-raid? (wow-true? is-raid)
         :encounters (parse-encounter-progress encounter-progress n-encounters
                                               encounter-names)}))))

(fn container-num-slots [bag]
  "Slot count of a container via whichever container API the client exposes; 0
   when neither is present (so the bag scan simply contributes nothing)."
  (if (and C_Container C_Container.GetContainerNumSlots)
      (or (C_Container.GetContainerNumSlots bag) 0)
      GetContainerNumSlots
      (or (GetContainerNumSlots bag) 0)
      0))

(fn container-item-id [bag slot]
  "Item id in a container slot via whichever container API exists, or nil."
  (if (and C_Container C_Container.GetContainerItemID)
      (C_Container.GetContainerItemID bag slot)
      GetContainerItemID
      (GetContainerItemID bag slot)
      nil))

;; --- Public API ------------------------------------------------------------

(lambda M.now []
  "Current server epoch time in seconds.
   Domain:  (none)
   Returns: integer epoch seconds (GetServerTime -- never os.time)."
  (GetServerTime))

(lambda M.player-info []
  "Identify the current player as a domain table.
   Domain:  (none)
   Returns: {:name string :class string :realm string}, where :class is the
            stable English class token lower-cased (e.g. :priest)."
  (let [(_localized class-token) (UnitClass :player)]
    {:name (UnitName :player)
     :class (string.lower (or class-token :unknown))
     :realm (GetRealmName)}))

(lambda M.saved-instances []
  "Read all live saved-instance lockouts, parsed into Lockout domain tables.
   Never throws; WoW returns nil from these APIs mid-load.
   Domain:  (none)
   Returns: {:ok true :lockouts [Lockout]} with :err appended when some entries
            failed schema validation, or {:ok false :err string} when the API
            itself was unavailable.
   See:     src/domain/schemas.fnl :Lockout."
  (let [n (GetNumSavedInstances)]
    (if (not n)
        {:ok false :err "GetNumSavedInstances returned nil -- UI not loaded?"}
        (let [now (M.now)
              lockouts []
              errs []]
          (for [i 1 n]
            (let [lk (read-lockout i now)]
              (when lk
                (let [result (validate.check schemas.Lockout lk)]
                  (if result.ok
                      (table.insert lockouts lk)
                      (table.insert errs
                                    (.. "instance " i ": "
                                        (table.concat result.errors "; "))))))))
          (if (= 0 (length errs))
              {:ok true : lockouts}
              {:ok true : lockouts :err (table.concat errs " | ")})))))

(lambda M.player-level []
  "The player's character level, or nil mid-load.
   Domain:  (none)
   Returns: integer | nil (UnitLevel 'player')."
  (and UnitLevel (UnitLevel :player)))

(lambda M.talent-points []
  "Points spent in each talent tab, in tab order (1..3 in TBC).
   Domain:  (none)
   Returns: [integer ...] -- one entry per talent tab; [] mid-load. Used by
            src/domain/ctx.fnl to infer the active spec."
  (if (not (and GetNumTalentTabs GetTalentTabInfo))
      []
      (let [n (or (GetNumTalentTabs) 0)]
        (fcollect [i 1 n]
          (let [(_name _icon points-spent) (GetTalentTabInfo i)]
            (or points-spent 0))))))

(lambda M.owned-item-ids []
  "Every item id the player currently holds: equipped slots plus bag and bank
   containers. May contain duplicates (an item in two places) -- the domain
   layer dedupes into a set.
   Domain:  (none)
   Returns: [integer ...] -- possibly empty (loading screen / empty bags)."
  (let [ids []]
    (when GetInventoryItemID
      (for [slot 1 last-equipped-slot]
        (let [id (GetInventoryItemID :player slot)]
          (when id (table.insert ids id)))))
    (each [_ bag (ipairs scan-bags)]
      (for [slot 1 (container-num-slots bag)]
        (let [id (container-item-id bag slot)]
          (when id (table.insert ids id)))))
    ids))

(lambda M.quest-completed? [quest-id]
  "Whether a quest is flagged complete, via whichever quest API exists.
   Domain:  quest-id : integer
   Returns: boolean (false when no quest API is available)."
  (if (and C_QuestLog C_QuestLog.IsQuestFlaggedCompleted)
      (wow-true? (C_QuestLog.IsQuestFlaggedCompleted quest-id))
      IsQuestFlaggedCompleted
      (wow-true? (IsQuestFlaggedCompleted quest-id))
      false))

(lambda M.faction-standing [faction-id]
  "The player's standing id (1=Hated .. 8=Exalted) with a faction, or nil if
   unknown / unavailable.
   Domain:  faction-id : integer
   Returns: integer in [1, 8] | nil (GetFactionInfoByID standingId)."
  (when GetFactionInfoByID
    (let [(_name _desc standing-id) (GetFactionInfoByID faction-id)]
      standing-id)))

(lambda M.request-raid-info! []
  "Ask the server to refresh saved-instance data (fires UPDATE_INSTANCE_INFO).
   Domain:  (none)
   Returns: nil. No-op if the API is unavailable."
  (when RequestRaidInfo (RequestRaidInfo))
  nil)

(lambda M.loot-item-id [?text]
  "Extract the itemID from a CHAT_MSG_LOOT message's item hyperlink, or nil.
   WoW embeds it as |Hitem:<id>:...|h[Name]|h|r. Pure string parse, no API.
   Domain:  ?text : string | nil
   Returns: integer | nil"
  (when (= (type ?text) :string)
    (let [id (string.match ?text "|?Hitem:(%d+)")]
      (and id (tonumber id)))))

(lambda M.self-loot? [?text]
  "Whether a CHAT_MSG_LOOT message is the player's OWN loot (vs a group member's).
   Matched against the client's LOOT_ITEM_SELF / LOOT_ITEM_PUSHED_SELF format
   prefixes, so it stays locale-correct in game and falls back to enUS under
   tests. Pure -- reads only the global string constants, never a WoW API.
   Domain:  ?text : string | nil
   Returns: boolean"
  (let [formats [(or _G.LOOT_ITEM_SELF "You receive loot: %s")
                 (or _G.LOOT_ITEM_PUSHED_SELF "You receive item: %s")]]
    (and (= (type ?text) :string)
         (accumulate [hit false _ fmt (ipairs formats) &until hit]
           (let [prefix (string.match fmt "^(.-)%%")]
             (and prefix (> (length prefix) 0)
                  (= 1 (string.find ?text prefix 1 true))))))))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game the .toc loads build/core/wow.lua after the domain
;; modules, populating _G.Routina.wow. In tests, consumers fall through to
;; (require :src.core.wow) -> the same M.

(set _G.Routina Routina)
(set Routina.wow M)

M
