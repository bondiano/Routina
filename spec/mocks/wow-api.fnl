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
;;   - NEVER mock domain modules — only WoW globals.

(local M {})

;; --- Configurable state (set by tests) ---

(local state {:saved-instances []
              :current-time 1717891200
              ; 2024-06-09 Sunday 00:00 UTC, example fixture
              :player-name :TestPriest
              :player-realm :TestRealm
              :inventory {}
              :quest-completed {}})

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

(fn stub-GetRealmName [] state.player-realm)

(fn stub-C_QuestLog-IsQuestFlaggedCompleted [quest-id]
  (= true (. state.quest-completed quest-id)))

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
  (set _G.GetRealmName stub-GetRealmName)
  (set _G.C_QuestLog
       {:IsQuestFlaggedCompleted stub-C_QuestLog-IsQuestFlaggedCompleted})
  (set _G.bit bit)
  (set _G.print (fn [...] nil)) ; silence WoW print in tests
  nil)

;; --- Per-test configuration helpers ---

(fn M.reset! []
  "Reset all state to defaults. Call in beforeEach."
  (set state.saved-instances [])
  (set state.current-time 1717891200)
  (set state.player-name :TestPriest)
  (set state.player-realm :TestRealm)
  (set state.inventory {})
  (set state.quest-completed {}))

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
