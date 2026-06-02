;; drop-table.fnl -- item-id -> drop probability + source, for route scoring.
;;
;; PURE domain module: no WoW API, no time, no random, no mutation of inputs.
;; The data lives in the generated src/domain/drops/data.fnl (see
;; scripts/import-drops.lua, vendor/bis-source/README.md); this module reads it,
;; validates every entry once against schemas.DropEntry at load, and exposes
;; read-only lookups. Consumed by src/domain/route.fnl together with
;; src/domain/drop-chance.fnl (base-drop-p feeds at-least-one / effective-rate).
;;
;; Coverage is scoped to the BiS catalog's items. A missing item-id means "not a
;; tracked drop" -- `drop-p` returns 0 so route weights it as no contribution.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; Dual-mode: in-game the .toc loads drops/data before this module (populating
;; Routina.drop-data); under busted we require it directly.
(local drop-data (or Routina.drop-data (require :src.domain.drops.data)))

;; Load-time boundary check: every entry conforms to schemas.DropEntry. Once at
;; load, never in a lookup, mirroring bis-catalog.fnl / activities.fnl.
(each [_ e (pairs drop-data)]
  (let [r (validate.check schemas.DropEntry e)]
    (assert r.ok (.. "drop-table: invalid entry " (tostring e.item-id) ": "
                     (table.concat (or r.errors []) "; ")))))

;; --- Public API ------------------------------------------------------------

(lambda M.for-item [item-id]
  "The DropEntry for an item, or nil if untracked.
   Domain:  item-id : integer
   Returns: DropEntry {:item-id :source-activity :base-drop-p ...} or nil."
  (. drop-data item-id))

(lambda M.drop-p [item-id]
  "Base drop probability for an item; 0 when the item is untracked.
   Domain:  item-id : integer
   Returns: number in [0, 1]."
  (let [e (. drop-data item-id)]
    (if e e.base-drop-p 0)))

(lambda M.source-activity [item-id]
  "The source-activity keyword for an item, or nil if untracked.
   Domain:  item-id : integer
   Returns: activity keyword (:karazhan :vendor :quest :unknown ...) or nil."
  (let [e (. drop-data item-id)]
    (and e e.source-activity)))

(lambda M.all []
  "Every DropEntry as a fresh sequence (unordered).
   Domain:  (none)
   Returns: [DropEntry] -- a new sequence; callers may not mutate the data."
  (icollect [_ e (pairs drop-data)] e))

(lambda M.by-activity [activity]
  "Every DropEntry whose source-activity matches, as a fresh sequence.
   Domain:  activity : activity keyword (:karazhan :vendor ...)
   Returns: [DropEntry] -- fresh sequence, possibly empty."
  (icollect [_ e (pairs drop-data)]
    (when (= e.source-activity activity) e)))

;; --- Register into the addon namespace -------------------------------------

(set _G.Routina Routina)
(set Routina.drop-table M)

M
