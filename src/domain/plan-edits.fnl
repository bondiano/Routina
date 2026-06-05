;; plan-edits.fnl -- the player's plan-shaping state: pins and skips
;; (ROADMAP Phase 8 §2).
;;
;; Pins are an ORDERED activity-id list placed at the head of the weekly plan
;; (plan.fnl owns the actual partition); skips are the set of activity ids
;; excluded from the candidate set until restored. Both are expressed as pure
;; constraints in RouteContext (:plan-edits), so route.plan-week stays
;; deterministic given the same edits. A skip means "not my routine", not
;; "not this week" -- it persists until the player restores it.
;;
;; PURE domain module: no WoW API, no I/O, no time; every transform returns a
;; FRESH PlanEdits, inputs untouched. The pin/skip conflict is resolved here:
;; skipping an activity unpins it, pinning one unskips it -- the two states
;; are mutually exclusive per id. Persisted at db.char.plan-edits; being
;; user-shaped data, invalid persisted entries are dropped on load
;; (M.normalize), never an error.

(local Routina (or _G.Routina {}))

(local M {})

;; --- Helpers (private) -------------------------------------------------------

(fn copy-edits [edits]
  "A fresh deep-enough copy of one PlanEdits (pins list + skips set)."
  {:pins (icollect [_ id (ipairs edits.pins)] id)
   :skips (collect [id v (pairs edits.skips)] (values id v))})

(fn index-of [pins id]
  "Position of an id in the pin list, or nil."
  (accumulate [found nil i pin (ipairs pins) &until found]
    (when (= pin id) i)))

;; --- Public API --------------------------------------------------------------

(lambda M.empty []
  "A fresh, empty PlanEdits.
   Domain:  (none)
   Returns: {:pins [] :skips {}}"
  {:pins [] :skips {}})

(lambda M.normalize [?persisted]
  "Coerce a possibly-nil / possibly-corrupt persisted table into a valid
   PlanEdits. User-shaped data: non-string ids and duplicate pins are DROPPED,
   never an error -- a corrupt SavedVariables row must not take the planner
   down (the goals.normalize pattern). An id present in both lists keeps the
   skip (the more conservative read) and loses the pin.
   Domain:  ?persisted : table | nil -- db.char.plan-edits
   Returns: PlanEdits -- fresh, possibly empty."
  (if (not= (type ?persisted) :table) (M.empty)
      (let [skips (collect [id v (pairs (or ?persisted.skips {}))]
                    (when (and (= (type id) :string) (= v true))
                      (values id true)))
            seen {}
            pins (icollect [_ id (ipairs (or ?persisted.pins []))]
                   (when (and (= (type id) :string) (= nil (. seen id))
                              (= nil (. skips id)))
                     (tset seen id true)
                     id))]
        {: pins : skips})))

(lambda M.to-db [edits]
  "A fresh plain copy of the edits for SavedVariables, so the persisted table
   never aliases the live copy.
   Domain:  edits : PlanEdits
   Returns: PlanEdits (plain data)"
  (copy-edits edits))

(lambda M.pinned? [edits id]
  "Whether this activity is pinned.
   Domain:  edits : PlanEdits ; id : string|keyword
   Returns: boolean"
  (not= nil (index-of edits.pins (tostring id))))

(lambda M.skipped? [edits id]
  "Whether this activity is skipped.
   Domain:  edits : PlanEdits ; id : string|keyword
   Returns: boolean"
  (= true (. edits.skips (tostring id))))

(lambda M.pin-rank [edits id]
  "The 1-based position of an activity in the pin order, or nil when unpinned.
   Domain:  edits : PlanEdits ; id : string|keyword
   Returns: integer >= 1 | nil"
  (index-of edits.pins (tostring id)))

(lambda M.pin [edits id]
  "Pin an activity: append to the pin order (no-op when already pinned) and
   clear any skip -- the two states are mutually exclusive. Returns a NEW
   PlanEdits.
   Domain:  edits : PlanEdits ; id : string|keyword
   Returns: PlanEdits"
  (let [next (copy-edits edits)
        key (tostring id)]
    (tset next.skips key nil)
    (when (= nil (index-of next.pins key))
      (table.insert next.pins key))
    next))

(lambda M.unpin [edits id]
  "Remove an activity from the pin order (no-op when unpinned). Returns a NEW
   PlanEdits.
   Domain:  edits : PlanEdits ; id : string|keyword
   Returns: PlanEdits"
  (let [next (copy-edits edits)
        idx (index-of next.pins (tostring id))]
    (when idx (table.remove next.pins idx))
    next))

(lambda M.move-pin [edits id delta]
  "Move a pinned activity within the pin order by delta places (negative =
   toward the head), clamped at the ends; no-op when unpinned. Returns a NEW
   PlanEdits.
   Domain:  edits : PlanEdits ; id : string|keyword ; delta : integer
   Returns: PlanEdits"
  (let [next (copy-edits edits)
        key (tostring id)
        idx (index-of next.pins key)]
    (when idx
      (let [target (math.max 1 (math.min (length next.pins) (+ idx delta)))]
        (table.remove next.pins idx)
        (table.insert next.pins target key)))
    next))

(lambda M.skip [edits id]
  "Skip an activity: exclude it from the plan until restored. Skipping unpins
   (mutually exclusive states). Returns a NEW PlanEdits.
   Domain:  edits : PlanEdits ; id : string|keyword
   Returns: PlanEdits"
  (let [next (M.unpin edits id)]
    (tset next.skips (tostring id) true)
    next))

(lambda M.unskip [edits id]
  "Restore a skipped activity to the candidate set. Returns a NEW PlanEdits.
   Domain:  edits : PlanEdits ; id : string|keyword
   Returns: PlanEdits"
  (let [next (copy-edits edits)]
    (tset next.skips (tostring id) nil)
    next))

;; --- Register into the addon namespace ---------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.plan-edits` after
;; schemas/validate. In tests, consumers fall through to
;; `(require :src.domain.plan-edits)` -> the same M.

(set _G.Routina Routina)
(set Routina.plan-edits M)

M
