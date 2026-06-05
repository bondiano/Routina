;; history.fnl -- pure cumulative observation log feeding the Bayesian luck score.
;;
;; PURE domain module:
;;   - No WoW API, no I/O, no random, no time source. Unlike weekly-state
;;     (per-week, pruned at reset), history is CUMULATIVE across the character's
;;     lifetime, so it needs no `now`.
;;   - Inputs are never mutated: every transform returns a NEW table, so the live
;;     session copy and the persisted DB table never alias.
;;
;; It records how many times each activity was run and how many times each item
;; actually dropped; drop-chance.bayesian-luck turns those counts into a posterior
;; luck score (luckier / unluckier than the base rate). The imperative shell
;; (src/core/events.fnl) accumulates a live copy from confirmed loot/kill events
;; and flushes it to addon.db.char.history on PLAYER_LOGOUT. That event wiring is
;; gated OFF by default until the WoW loot/kill API signatures are wiki-confirmed
;; (ROADMAP Phase 4 §1 / the deferred RAID_BOSS_KILLED work) -- this module is the
;; finished, testable core regardless.
;;
;; Shape (DB-compatible with saved-vars.fnl :char.history defaults):
;;   History = {:runs   {activity-id-string -> integer >= 0}
;;              :drops  {item-id-string     -> integer >= 0}
;;              :yields {activity-id-string -> {:runs int :gold number
;;                                              :badges int}}}
;; Keys are stringified on ingest (SavedVariables-safe, like the other persisted
;; maps). See schemas.fnl :History. NOTE the two run counters serve different
;; masters: :runs is keyed by ENCOUNTER_END boss name (the per-boss luck
;; denominator); :yields is keyed by activity id and tallies whole visits with
;; their gold/badge take (Phase 7), feeding yields.blended-band.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))
(local chance (or Routina.drop-chance (require :src.domain.drop-chance)))

(local M {})

;; --- Helpers (private) -----------------------------------------------------

(fn copy-counts [counts]
  "A fresh shallow copy of a string->integer count map."
  (collect [k v (pairs counts)] k v))

(fn count-valid? [k v]
  "Whether a persisted (key value) pair is a well-formed count entry. Defensive:
   corrupt SavedVariables must be dropped on load, not crash it."
  (and (= (type k) :string) (= (type v) :number) (>= v 0) (= v (math.floor v))))

(fn normalize-counts [raw]
  "Keep only well-formed string->non-negative-integer entries from a raw table."
  (if (not= (type raw) :table) {}
      (collect [k v (pairs raw)]
        (if (count-valid? k v) (values k v) (values nil nil)))))

(fn bump [counts key]
  "Return a fresh count map with `key` (stringified) incremented by one."
  (let [k (tostring key)
        next (collect [ck cv (pairs counts)] ck cv)]
    (tset next k (+ 1 (or (. counts k) 0)))
    next))

(fn copy-yields [yields]
  "A fresh deep copy of the per-activity yield tally map."
  (collect [k v (pairs yields)]
    k
    {:runs v.runs :gold v.gold :badges v.badges}))

(fn yield-valid? [k v]
  "Whether a persisted (key value) pair is a well-formed yield tally. Defensive:
   corrupt SavedVariables must be dropped on load, not crash it."
  (and (= (type k) :string) (= (type v) :table) (= (type v.runs) :number)
       (>= v.runs 0) (= v.runs (math.floor v.runs)) (= (type v.gold) :number)
       (>= v.gold 0) (= (type v.badges) :number) (>= v.badges 0)
       (= v.badges (math.floor v.badges))))

(fn normalize-yields [raw]
  "Keep only well-formed yield tallies from a raw persisted table."
  (if (not= (type raw) :table) {}
      (collect [k v (pairs raw)]
        (if (yield-valid? k v)
            (values k {:runs v.runs :gold v.gold :badges v.badges})
            (values nil nil)))))

;; --- Public API ------------------------------------------------------------

(lambda M.empty []
  "A fresh, empty history record.
   Domain:  (none)
   Returns: History -- {:runs {} :drops {} :yields {}}"
  {:runs {} :drops {} :yields {}})

(lambda M.runs-for [hist activity-id]
  "How many times the activity has been run.
   Domain:  hist : History ; activity-id : string|keyword
   Returns: integer >= 0 (0 when unseen)"
  (or (. hist.runs (tostring activity-id)) 0))

(lambda M.drops-for [hist item-id]
  "How many times the item has dropped.
   Domain:  hist : History ; item-id : integer|string
   Returns: integer >= 0 (0 when unseen)"
  (or (. hist.drops (tostring item-id)) 0))

(lambda M.record-run [hist activity-id]
  "Record one completed run of an activity, returning a NEW history.
   Domain:  hist : History ; activity-id : string|keyword
   Returns: History with runs[activity-id] incremented"
  {:runs (bump hist.runs activity-id)
   :drops (copy-counts hist.drops)
   :yields (copy-yields (or hist.yields {}))})

(lambda M.record-drop [hist item-id]
  "Record one observed drop of an item, returning a NEW history.
   Domain:  hist : History ; item-id : integer|string
   Returns: History with drops[item-id] incremented"
  {:runs (copy-counts hist.runs)
   :drops (bump hist.drops item-id)
   :yields (copy-yields (or hist.yields {}))})

(lambda M.record-yield [hist activity-id outcome]
  "Record one finished visit's take for an activity, returning a NEW history.
   The shell (src/core/events.fnl) calls this when a tracked instance visit
   ends: one run, its accumulated gold (copper) and badge count.
   Domain:  hist : History ; activity-id : string|keyword
            outcome : {:gold ?number >= 0 :badges ?integer >= 0} (nil reads 0)
   Returns: History with yields[activity-id] runs+1, gold/badges accumulated"
  (let [k (tostring activity-id)
        next (copy-yields (or hist.yields {}))
        prior (or (. next k) {:runs 0 :gold 0 :badges 0})]
    (tset next k
          {:runs (+ prior.runs 1)
           :gold (+ prior.gold (math.max 0 (or outcome.gold 0)))
           :badges (+ prior.badges (math.max 0 (or outcome.badges 0)))})
    {:runs (copy-counts hist.runs)
     :drops (copy-counts hist.drops)
     :yields next}))

(lambda M.yields-for [hist activity-id]
  "The accumulated visit tally for an activity (fresh copy).
   Domain:  hist : History ; activity-id : string|keyword
   Returns: {:runs int :gold number :badges int} -- zeros when unseen."
  (let [v (and hist.yields (. hist.yields (tostring activity-id)))]
    (if v {:runs v.runs :gold v.gold :badges v.badges}
        {:runs 0 :gold 0 :badges 0})))

(lambda M.luck [hist item-id activity-id base-p ?prior]
  "Bayesian luck score for an item, fed by this history's observed counts.
   Drops are clamped to runs so a noisy log can't violate the runs>=drops
   invariant drop-chance.bayesian-luck asserts.
   Domain:  hist : History ; item-id : integer|string
            activity-id : string|keyword -- the source whose runs count as trials
            base-p : number in [0,1] -- the catalog drop rate ; ?prior : Beta prior
   Returns: drop-chance.bayesian-luck result
            {:posterior-mean :posterior-variance :luck-z :n}"
  (let [runs (M.runs-for hist activity-id)
        drops (math.min (M.drops-for hist item-id) runs)]
    (chance.bayesian-luck drops runs base-p ?prior)))

(lambda M.normalize [?persisted]
  "Coerce a possibly-nil / possibly-corrupt persisted table into a valid History,
   dropping malformed entries. Used by the shell when seeding from SavedVariables.
   Domain:  ?persisted : table | nil -- db.char.history
   Returns: History"
  (if (not= (type ?persisted) :table)
      (M.empty)
      {:runs (normalize-counts ?persisted.runs)
       :drops (normalize-counts ?persisted.drops)
       :yields (normalize-yields ?persisted.yields)}))

(lambda M.to-db [hist]
  "A fresh plain copy of the history for writing to SavedVariables, so the
   persisted table never aliases the live session copy.
   Domain:  hist : History
   Returns: History (plain data)"
  {:runs (copy-counts hist.runs)
   :drops (copy-counts hist.drops)
   :yields (copy-yields (or hist.yields {}))})

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.history` before
;; src/core/events.fnl feeds it. In tests, consumers fall through to
;; `(require :src.domain.history)` -> the same M.

(set _G.Routina Routina)
(set Routina.history M)

M
