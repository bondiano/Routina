;; plan.fnl -- pure weekly-plan view-model builder.
;;
;; The vertical slice's brain: given a catalog of candidate activities,
;; score each by expected BiS slots filled this week and return an
;; ordered view-model the Plan tab renders directly (src/ui/tabs/weekly.fnl).
;;
;; PURE domain module:
;;   - No WoW API, no mutation of inputs, no I/O, no time, no random.
;;   - Drop math is delegated to src/domain/drop-chance.fnl.
;;   - Deterministic: same catalog in -> same ordered plan out.
;; See docs/PRD.md s6.1 and .claude/examples/01-pure-module/.

(local Routina (or _G.Routina {}))
(local chance (or Routina.drop-chance (require :src.domain.drop-chance)))

(local M {})

;; --- Helpers (private) -----------------------------------------------------

(fn item-row [item]
  "Annotate one target item with its at-least-one chance this week.
   item : {:label string :p number :runs number :item-id ?number}
   Returns: {:label :p :runs :item-id :chance} (inputs preserved, :chance added).
   :item-id is carried through verbatim so the UI can show the standard
   game tooltip (GameTooltip:SetItemByID); nil is fine."
  {:label item.label
   :p item.p
   :runs item.runs
   :item-id item.item-id
   :chance (chance.at-least-one item.p item.runs)})

(fn by-score-then-time [a b]
  "Total-order comparator for stable, deterministic plan ordering.
   Higher score first; ties broken by fewer minutes, then name, then id.
   Lua's table.sort is not stable, so the comparator must be total."
  (if (not= a.score b.score) (> a.score b.score)
      (not= a.minutes b.minutes) (< a.minutes b.minutes)
      (not= a.name b.name) (< a.name b.name)
      (< (tostring a.id) (tostring b.id))))

;; --- Public API ------------------------------------------------------------

(lambda M.score-activity [activity]
  "Composite score for one activity: expected BiS slots filled this week.
   Sum of at-least-one(p, runs) across the activity's target items, so the
   score is in [0, #items] and reads as 'slots likely filled'.
   Domain:  activity : {:items [{:p number :runs number} ...]}
   Returns: number in [0, #items]."
  (accumulate [total 0 _ item (ipairs activity.items)]
    (+ total (chance.at-least-one item.p item.runs))))

(lambda M.plan-week [catalog ?score-fn]
  "Build the ordered weekly-plan view-model from a catalog of activities.
   Pure and deterministic -- same catalog always yields the same plan.
   Domain:  catalog   : sequence of activities, each
             {:id keyword :name string :type string :detail string
              :minutes number
              :items [{:label string :p number :runs number :item-id ?number} ...]}
            ?score-fn : optional (fn [activity] -> number) overriding the default
             composite scorer (M.score-activity). Lets a caller inject a
             slot-weighted score (src/domain/route.fnl) while plan retains sole
             ownership of per-item :chance annotation and deterministic ordering.
   Returns: sequence of rows ordered by score desc (ties: minutes asc, name,
            id), each row = the activity plus :score and per-item :chance:
            {:id :name :type :detail :minutes :score
             :items [{:label :p :runs :item-id :chance} ...]}."
  (let [score (or ?score-fn M.score-activity)
        rows (icollect [_ activity (ipairs catalog)]
               {:id activity.id
                :name activity.name
                :type activity.type
                :detail activity.detail
                :minutes activity.minutes
                :score (score activity)
                :items (icollect [_ item (ipairs activity.items)]
                         (item-row item))})]
    (table.sort rows by-score-then-time)
    rows))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, the .toc load order populates `_G.Routina.plan`
;; before the Plan tab runs. In tests, consumers fall through to
;; `(require :src.domain.plan)` which returns the same M.

(set _G.Routina Routina)
(set Routina.plan M)

M
