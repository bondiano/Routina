;; custom-activities.fnl -- player-authored activities (ROADMAP Phase 8 §1).
;;
;; The player adds what the catalog doesn't know: a farm lap, a fishing hour,
;; a weekly errand. This module owns the persisted authoring shape
;; (schemas.CustomActivity, stored at db.profile.custom-activities) and its
;; two pure projections into the planner's native types:
;;   to-activity-def -> a plain schemas.ActivityDef (:type :custom) that
;;                      route/goals fold into the registry list as an equal;
;;   to-yield        -> the authored schemas.ActivityYield override (badges /
;;                      honest gold band / rep), or nil when nothing is claimed.
;; ctx.build performs the mapping and threads the results through RouteContext
;; (:custom-activities / :custom-yields) -- the domain never reads the DB.
;;
;; PURE domain module: no WoW API, no I/O, no time, no random; inputs are
;; never mutated. Being user-authored data, invalid persisted entries are
;; DROPPED on load instead of erroring (the goals.normalize pattern) -- a
;; corrupt SavedVariables row must not take the planner down.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; Custom content carries no prerequisites: the author IS the player, so a
;; gate they cannot pass would only hide their own routine from them.
(local custom-min-level 1)

;; --- Helpers (private) -------------------------------------------------------

(fn copy-custom [c]
  "A fresh shallow copy of one CustomActivity."
  (collect [k v (pairs c)] k v))

(fn invariants-ok? [c]
  "Cross-field invariants the field schema cannot express: a positive length,
   the gold band authored as an ordered non-negative pair (both halves or
   neither), the rep pair (faction, amount) authored together, and counts
   that never go negative."
  (and (> c.est-minutes 0) (= (= nil c.gold-min) (= nil c.gold-max))
       (or (= nil c.gold-min)
           (and (>= c.gold-min 0) (<= c.gold-min c.gold-max)))
       (= (= nil c.rep-faction) (= nil c.rep-amount))
       (or (= nil c.rep-amount) (> c.rep-amount 0))
       (or (= nil c.badges) (>= c.badges 0))))

;; --- Public API --------------------------------------------------------------

(lambda M.normalize [?persisted]
  "Coerce a possibly-nil / possibly-corrupt persisted list into valid
   CustomActivity records. User-authored data: invalid entries are DROPPED,
   never an error (the goals.normalize pattern).
   Domain:  ?persisted : table | nil -- db.profile.custom-activities
   Returns: [CustomActivity] -- fresh, possibly empty."
  (if (not= (type ?persisted) :table) []
      (icollect [_ c (ipairs ?persisted)]
        (when (and (= (type c) :table)
                   (let [r (validate.check schemas.CustomActivity c)] r.ok)
                   (invariants-ok? c))
          (copy-custom c)))))

(lambda M.to-db [customs]
  "A fresh plain copy of the custom-activity list for SavedVariables, so the
   persisted table never aliases the live session copy.
   Domain:  customs : [CustomActivity]
   Returns: [CustomActivity] (plain data)"
  (icollect [_ c (ipairs customs)] (copy-custom c)))

(lambda M.to-activity-def [custom]
  "Project one authored entry into the planner's registry shape. Always a
   plan candidate (route admits :type :custom unconditionally), uncontested
   (no :group-size -- nobody rolls against you on your own routine), and
   ungated (min-level 1; see custom-min-level).
   Domain:  custom : CustomActivity (already normalized)
   Returns: schemas.ActivityDef with :type :custom."
  {:id custom.id
   :name custom.name
   :type :custom
   :reset custom.reset
   :length-estimate custom.est-minutes
   :goal-id custom.goal-id
   :requirements {:min-level custom-min-level}})

(lambda M.to-yield [custom]
  "The authored per-clear payout as a planner-native ActivityYield, or nil
   when the entry claims nothing (no badges, no gold, no rep) -- an honest
   zero, not a fabricated band.
   Domain:  custom : CustomActivity (already normalized)
   Returns: schemas.ActivityYield | nil."
  (when (or (and custom.badges (> custom.badges 0))
            (and custom.gold-max (> custom.gold-max 0))
            (not= nil custom.rep-faction))
    {:activity-id custom.id
     :badges (or custom.badges 0)
     :gold-min (or custom.gold-min 0)
     :gold-max (or custom.gold-max 0)
     :rep (when custom.rep-faction
            {:faction custom.rep-faction :amount custom.rep-amount})}))

;; --- Register into the addon namespace ---------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.custom-activities`
;; after schemas/validate. In tests, consumers fall through to
;; `(require :src.domain.custom-activities)` -> the same M.

(set _G.Routina Routina)
(set Routina.custom-activities M)

M
