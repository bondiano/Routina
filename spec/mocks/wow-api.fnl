;; 06-mock-wow-api.fnl
;;
;; CANONICAL EXAMPLE for spec/mocks/wow-api.fnl
;;
;; This file installs stubs for WoW globals BEFORE any production module
;; is loaded by tests. Required by spec/helper.lua.
;;
;; Rules:
;;   - Always return realistic shapes (matches what real WoW returns).
;;   - Provide :set! helpers so tests can configure return values per-test.
;;   - Reset state in beforeEach to avoid bleed across tests.
;;   - NEVER mock domain modules -- only WoW globals.

(local M {})

;; --- Configurable state (set by tests) ---

(local state {:saved-instances []
              :current-time 1717891200
              ; 2024-06-09 Sunday 00:00 UTC, example fixture
              :player-name :TestPriest
              :player-realm :TestRealm
              :player-level 70
              :inventory {}
              :equipped {}
              ; slot -> item-id
              :bags {}
              ; bag-id -> [item-id ...]
              :talent-points [0 0 0]
              ; points per talent tab
              :faction-standings {}
              ; faction-id -> standing-id (1..8)
              :quest-completed {}
              :item-qualities {}
              :money 0
              ; copper (GetMoney)
              :item-counts {}
              ; item-id -> count (GetItemCount)
              :instance nil})

; {:name :instance-type :difficulty-id} | nil (GetInstanceInfo)

; item-id -> quality (0..7); default epic

;; Standard WoW item-quality colours (r g b), keyed by quality 0..7.
(local quality-colors {0 [0.62 0.62 0.62]
                       1 [1 1 1]
                       2 [0.12 1 0]
                       3 [0 0.44 0.87]
                       4 [0.64 0.21 0.93]
                       5 [1 0.5 0]
                       6 [0.9 0.8 0.5]
                       7 [0 0.8 1]})

;; --- Stub implementations ---

(fn stub-GetNumSavedInstances []
  (length state.saved-instances))

(fn stub-GetSavedInstanceInfo [index]
  (let [inst (. state.saved-instances index)]
    (when inst
      ;; Real WoW returns 13 values; we return the ones we use.
      (values inst.name ; name
              inst.lockout-id ; lockoutId
              (or inst.reset 604800) ; reset seconds
              (or inst.locked 1) ; locked
              (or inst.extended 0) ; extended
              (or inst.max-players 25) ; maxPlayers
              (or inst.difficulty-name :Normal) ; difficultyName
              (or inst.n-encounters 0) ; numEncounters
              (or inst.encounter-progress 0) ; encounterProgress bitmask
              nil nil ; extendDisabled, isLockoutShared (unused)
              (if inst.is-raid 1 0)))))

; isRaid

(fn stub-GetSavedInstanceEncounterInfo [instance-index encounter-index]
  (let [inst (. state.saved-instances instance-index)]
    (when inst
      (let [enc (. inst.encounters encounter-index)]
        (when enc
          (values enc.name nil enc.killed))))))

(fn stub-GetServerTime [] state.current-time)
(fn stub-time [] state.current-time)

(fn stub-UnitName [unit]
  (if (= unit :player) state.player-name nil))

(fn stub-UnitClass [unit]
  (if (= unit :player) (values :Priest :PRIEST 5) nil))

(fn stub-GetRealmName [] state.player-realm)

(fn stub-C_QuestLog-IsQuestFlaggedCompleted [quest-id]
  (= true (. state.quest-completed quest-id)))

(fn stub-UnitLevel [unit]
  (if (= unit :player) state.player-level nil))

(fn stub-GetInventoryItemID [unit slot]
  (if (= unit :player) (. state.equipped slot) nil))

(fn stub-GetContainerNumSlots [bag]
  ;; Real WoW: total capacity of the container (empty slots included).
  (let [b (. state.bags bag)]
    (if b (or b.size 0) 0)))

(fn stub-GetContainerItemID [bag slot]
  ;; nil for an empty slot, mirroring WoW; gaps don't affect the slot count.
  (let [b (. state.bags bag)]
    (and b b.items (. b.items slot))))

(fn stub-GetNumTalentTabs []
  (length state.talent-points))

(fn stub-GetTalentTabInfo [tab]
  ;; Real WoW: name, iconTexture, pointsSpent, background, previewPoints, unlocked
  (values (.. :Tab tab) "Interface\\Icons\\Spell" (. state.talent-points tab) 0
          0 true))

(fn stub-GetFactionInfoByID [faction-id]
  ;; Real WoW: name, description, standingId, bottom, top, earned, ...
  (let [sid (. state.faction-standings faction-id)]
    (when sid (values :Faction :desc sid 0 1000 500))))

(fn stub-RequestRaidInfo [] nil)

(fn stub-GetMoney [] state.money)

(fn stub-GetItemCount [item _include-bank]
  ;; Real WoW: count across bags (+bank when flagged); the mock keeps one
  ;; number per id and ignores the flag.
  (let [id (if (= :number (type item)) item (tonumber item))]
    (or (and id (. state.item-counts id)) 0)))

(fn stub-GetInstanceInfo []
  ;; Real WoW returns 9+ values; we return the three wow.instance-info reads.
  (if state.instance
      (values state.instance.name (or state.instance.instance-type :party)
              (or state.instance.difficulty-id 1))
      (values :Azeroth :none 0)))

(fn stub-GetItemInfo [item]
  ;; Real WoW returns 17 values; we return the few callers read (name, link,
  ;; quality, itemLevel). Quality is looked up per-id (default epic 4), so the
  ;; Plan tab's quality dots resolve deterministically in tests.
  (let [id (if (= :number (type item)) item (tonumber item))
        quality (or (and id (. state.item-qualities id)) 4)]
    (values (.. "Item " (tostring item)) nil quality 70)))

(fn stub-GetItemQualityColor [quality]
  ;; Real WoW: r, g, b, hex. We mirror the standard quality palette.
  (let [c (or (. quality-colors quality) (. quality-colors 1))]
    (values (. c 1) (. c 2) (. c 3) :ffffffff)))

;; --- Frame stubs (CreateFrame and the surface src/ui/* touches) ---
;;
;; Every method is a chainable no-op returning the frame, except for the
;; few we need real semantics on (Show/Hide/IsShown, CreateTexture,
;; CreateFontString, SetScript/GetScript). Pixel-correctness stays
;; wowUnit territory; busted only asserts that requiring a UI module
;; doesn't raise. See docs/TESTING.md "UI widgets".

(local frame-noop (fn [self ...] self))

(fn make-frame-stub []
  (let [f {:shown? true :script-handlers {}}]
    (setmetatable f {:__index (fn [_t k]
                                (if (or (= k :Show) (= k :Hide))
                                    (fn [self]
                                      (set self.shown? (= k :Show))
                                      self)
                                    (= k :IsShown)
                                    (fn [self] self.shown?)
                                    (= k :SetScript)
                                    (fn [self name h]
                                      (tset self.script-handlers name h)
                                      self)
                                    (= k :GetScript)
                                    (fn [self name]
                                      (. self.script-handlers name))
                                    (or (= k :CreateTexture)
                                        (= k :CreateFontString))
                                    (fn [_self ...] (make-frame-stub))
                                    ;; Real WoW asserts these args are numbers
                                    ;; -- mirror that so the in-game class of
                                    ;; bug (passing a keyword to SetSize)
                                    ;; surfaces in busted, not in /reload.
                                    (= k :SetSize)
                                    (fn [self w h]
                                      (assert (= :number (type w))
                                              (.. "SetSize w must be number, got "
                                                  (type w)))
                                      (assert (= :number (type h))
                                              (.. "SetSize h must be number, got "
                                                  (type h)))
                                      self)
                                    (or (= k :SetWidth) (= k :SetHeight))
                                    (fn [self n]
                                      (assert (= :number (type n))
                                              (.. (tostring k)
                                                  " arg must be number, got "
                                                  (type n)))
                                      self)
                                    frame-noop))})
    f))

(fn stub-CreateFrame [...]
  (make-frame-stub))

;; --- Bit library (Lua 5.1 doesn't have native bitwise) ---
;; WoW provides bit lib globally; we replicate it for tests.

(local bit {:band (fn [a b]
                    (var result 0)
                    (var bit-val 1)
                    (var aa a)
                    (var bb b)
                    (while (and (> aa 0) (> bb 0))
                      (when (and (= 1 (% aa 2)) (= 1 (% bb 2)))
                        (set result (+ result bit-val)))
                      (set aa (math.floor (/ aa 2)))
                      (set bb (math.floor (/ bb 2)))
                      (set bit-val (* bit-val 2)))
                    result)
            :lshift (fn [a n] (* a (^ 2 n)))})

;; --- Install all stubs into _G ---

(fn M.install! []
  "Install all stubs. Call once from spec/helper.lua."
  (set _G.GetNumSavedInstances stub-GetNumSavedInstances)
  (set _G.GetSavedInstanceInfo stub-GetSavedInstanceInfo)
  (set _G.GetSavedInstanceEncounterInfo stub-GetSavedInstanceEncounterInfo)
  (set _G.GetServerTime stub-GetServerTime)
  (set _G.time stub-time)
  (set _G.UnitName stub-UnitName)
  (set _G.UnitClass stub-UnitClass)
  (set _G.GetRealmName stub-GetRealmName)
  (set _G.C_QuestLog
       {:IsQuestFlaggedCompleted stub-C_QuestLog-IsQuestFlaggedCompleted})
  (set _G.UnitLevel stub-UnitLevel)
  (set _G.GetInventoryItemID stub-GetInventoryItemID)
  ;; legacy container globals (TBC 2.5.x); wow.fnl also probes C_Container
  (set _G.GetContainerNumSlots stub-GetContainerNumSlots)
  (set _G.GetContainerItemID stub-GetContainerItemID)
  (set _G.GetNumTalentTabs stub-GetNumTalentTabs)
  (set _G.GetTalentTabInfo stub-GetTalentTabInfo)
  (set _G.GetFactionInfoByID stub-GetFactionInfoByID)
  (set _G.RequestRaidInfo stub-RequestRaidInfo)
  (set _G.GetMoney stub-GetMoney)
  (set _G.GetItemCount stub-GetItemCount)
  (set _G.GetInstanceInfo stub-GetInstanceInfo)
  (set _G.GetItemInfo stub-GetItemInfo)
  (set _G.GetItemQualityColor stub-GetItemQualityColor)
  (set _G.bit bit)
  ;; UI globals (see docs/UI.md for what each is used for):
  (set _G.CreateFrame stub-CreateFrame)
  (set _G.UIParent (make-frame-stub))
  (set _G.UISpecialFrames [])
  (set _G.GameTooltip (make-frame-stub))
  (set _G.DEFAULT_CHAT_FRAME (make-frame-stub))
  (when (not _G.SlashCmdList) (set _G.SlashCmdList {}))
  (set _G.print (fn [...] nil)) ; silence WoW print in tests
  nil)

;; --- Per-test configuration helpers ---

(fn M.reset! []
  "Reset all state to defaults. Call in beforeEach."
  (set state.saved-instances [])
  (set state.current-time 1717891200)
  (set state.player-name :TestPriest)
  (set state.player-realm :TestRealm)
  (set state.player-level 70)
  (set state.inventory {})
  (set state.equipped {})
  (set state.bags {})
  (set state.talent-points [0 0 0])
  (set state.faction-standings {})
  (set state.quest-completed {})
  (set state.item-qualities {})
  (set state.money 0)
  (set state.item-counts {})
  (set state.instance nil))

(fn M.set-saved-instances! [instances]
  "Set the list of saved instances. Each instance is a table:
   {:name :lockout-id :reset :difficulty-name :n-encounters
    :encounter-progress :is-raid :encounters [{:name :killed}]}."
  (set state.saved-instances instances))

(fn M.set-current-time! [t]
  (set state.current-time t))

(fn M.set-quest-completed! [quest-id done?]
  (tset state.quest-completed quest-id done?))

(fn M.set-player! [name realm]
  (set state.player-name name)
  (set state.player-realm realm))

(fn M.set-player-level! [level]
  (set state.player-level level))

(fn M.set-equipped! [slot->id]
  "Set equipped gear as a {slot item-id} table."
  (set state.equipped slot->id))

(fn M.set-bags! [bags]
  "Set bag/bank contents as {bag-id {:size N :items {slot item-id}}} -- :size is
   the container capacity (empty slots allowed), :items the occupied slots."
  (set state.bags bags))

(fn M.set-talent-points! [points]
  "Set points spent per talent tab, e.g. [0 61 0]."
  (set state.talent-points points))

(fn M.set-faction-standing! [faction-id standing-id]
  "Set a faction's standing id (1=Hated .. 8=Exalted)."
  (tset state.faction-standings faction-id standing-id))

(fn M.set-item-quality! [item-id quality]
  "Set an item's quality (0=Poor .. 7=Heirloom); GetItemInfo defaults to epic."
  (tset state.item-qualities item-id quality))

(fn M.set-money! [copper]
  "Set the player's money (GetMoney return) in copper."
  (set state.money copper))

(fn M.set-item-count! [item-id count]
  "Set GetItemCount's reading for one item id."
  (tset state.item-counts item-id count))

(fn M.set-instance! [?instance]
  "Put the player inside an instance (or outside, with nil):
   {:name string :instance-type ?string :difficulty-id ?integer} --
   instance-type defaults :party, difficulty-id 1 (2 = heroic)."
  (set state.instance ?instance))

M

;; --- Notes ---
;;
;; 1. Why a single big mock file instead of per-module?
;;    - WoW globals are global. One install! is simpler than juggling
;;      requires per spec.
;;    - Per-test config is fine-grained enough (set-*!) without splitting files.
;;
;; 2. Why values returned via (values ...) and not table?
;;    - Real WoW APIs use multiple return values; consumers destructure them.
;;    - If we returned a table, production code wouldn't match real WoW.
;;
;; 3. How to add a new mock?
;;    - Add stub-NewApi function.
;;    - Install it in install!.
;;    - Add set-* helpers if behavior should vary per test.
;;    - Add to this file's docstring at top so others know it's available.
