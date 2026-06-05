;; yields.fnl -- activity-id -> per-clear yields (badges, gold band, rep).
;;
;; PURE domain module: no WoW API, no time, no random, no mutation of inputs.
;; The data lives in the generated src/domain/yields/data.fnl (see
;; scripts/import-yields.lua, scripts/yields-curated.lua); this module reads
;; it, validates every entry once against schemas.ActivityYield at load, and
;; exposes read-only lookups plus the band-blending math that tightens the
;; curated gold band toward the player's own recorded history (the same
;; shrinkage idea as drop-chance.bayesian-luck). Consumed by
;; src/domain/goals.fnl and src/domain/route.fnl.
;;
;; A missing activity-id means "no tracked yield" -- badge/gold queries return
;; zero-yield values so the planner weights it as no contribution.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; Dual-mode: in-game the .toc loads yields/data before this module (populating
;; Routina.yields-data); under busted we require it directly.
(local yields-data (or Routina.yields-data (require :src.domain.yields.data)))

;; Shrinkage constant for blended-band: w = n/(n+k). After k observed runs the
;; band has moved halfway onto the player's own mean.
(local shrink-k 5)

;; Load-time boundary check: every entry conforms to schemas.ActivityYield.
;; Once at load, never in a lookup, mirroring drop-table.fnl.
(each [_ e (pairs yields-data)]
  (let [r (validate.check schemas.ActivityYield e)]
    (assert r.ok (.. "yields: invalid entry " (tostring e.activity-id) ": "
                     (table.concat (or r.errors []) "; ")))))

;; --- Public API ------------------------------------------------------------

(lambda M.for-activity [activity-id]
  "The ActivityYield for an activity, or nil if untracked.
   Domain:  activity-id : activity keyword (:karazhan :heroic-mech ...)
   Returns: ActivityYield {:activity-id :badges :gold-min :gold-max :rep?} or nil."
  (. yields-data activity-id))

(lambda M.badges-for [activity-id]
  "Badges of Justice one clear of the activity pays; 0 when untracked.
   Domain:  activity-id : activity keyword
   Returns: integer >= 0."
  (let [e (. yields-data activity-id)]
    (if e e.badges 0)))

(lambda M.gold-band-for [activity-id]
  "The honest curated gold band for one clear, or nil if untracked.
   Domain:  activity-id : activity keyword
   Returns: fresh {:min number :max number} (copper) or nil."
  (let [e (. yields-data activity-id)]
    (when e {:min e.gold-min :max e.gold-max})))

(lambda M.rep-for [activity-id]
  "The reputation payout of one clear, or nil when the activity grants none.
   Domain:  activity-id : activity keyword
   Returns: {:faction keyword :amount integer} or nil."
  (let [e (. yields-data activity-id)]
    (and e e.rep)))

(lambda M.all []
  "Every ActivityYield as a fresh sequence (unordered).
   Domain:  (none)
   Returns: [ActivityYield] -- a new sequence; callers may not mutate the data."
  (icollect [_ e (pairs yields-data)] e))

(lambda M.blended-band [curated observed-gold observed-runs]
  "Tighten a curated gold band toward the player's own observed per-run mean.
   Shrinkage weight w = n/(n+5): zero runs returns the curated band untouched;
   as runs accumulate both edges move linearly onto the observed mean, so the
   band only ever narrows (width scales by 1-w) and converges on the evidence
   -- honest at both ends of the data regime.
   Domain:  curated       : {:min number :max number} -- copper, min <= max
            observed-gold : number >= 0 -- total copper recorded for the activity
            observed-runs : integer >= 0 -- runs that total spans
   Returns: fresh {:min number :max number}, min <= max preserved.
   Errors:  if curated.min > curated.max."
  (assert (<= curated.min curated.max) "blended-band: band min > max")
  (if (= observed-runs 0)
      {:min curated.min :max curated.max}
      (let [w (/ observed-runs (+ observed-runs shrink-k))
            mean (/ observed-gold observed-runs)]
        {:min (+ (* (- 1 w) curated.min) (* w mean))
         :max (+ (* (- 1 w) curated.max) (* w mean))})))

;; --- Register into the addon namespace -------------------------------------

(set _G.Routina Routina)
(set Routina.yields M)

M
