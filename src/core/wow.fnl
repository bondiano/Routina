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

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game the .toc loads build/core/wow.lua after the domain
;; modules, populating _G.Routina.wow. In tests, consumers fall through to
;; (require :src.core.wow) -> the same M.

(set _G.Routina Routina)
(set Routina.wow M)

M
