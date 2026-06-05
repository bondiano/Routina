;; tabs/weekly-vm.fnl -- the Plan tab's PURE view-models (UI.md split rule).
;;
;; Extracted from tabs/weekly.fnl when the Phase 7 goal cards pushed that file
;; past the size rule: every data -> render-spec function lives here, busted-
;; tested, no frames, no WoW API; building AceGUI widgets from these specs
;; stays in tabs/weekly.fnl (imperative, wowUnit territory). weekly.fnl
;; re-exports them, so callers and specs may read either module.

(local Routina (or _G.Routina {}))
(local format (or Routina.format (require :src.ui.format)))

(local M {})

;; top-N target items per card (PRD §6.1 G2: "top 3 target items")
(local max-rows 3)

(set M.max-rows max-rows)

;; --- Helpers (private) -------------------------------------------------------

(fn run-word [runs]
  (if (= runs 1) " run" " runs"))

(fn chance-text [item]
  "The chance column: 'NN% · K run(s)'."
  (.. (format.percent item.chance) " · " item.runs (run-word item.runs)))

(fn by-chance-desc [a b]
  (> a.chance b.chance))

(fn top-items [items]
  "The max-rows highest-chance items, as a fresh sorted copy (input untouched)."
  (let [sorted (icollect [_ it (ipairs items)] it)]
    (table.sort sorted by-chance-desc)
    (fcollect [i 1 (math.min max-rows (length sorted))]
      (. sorted i))))

;; Display names per goal kind (plain English placeholders pending AceLocale).
(local goal-kind-labels {:badges :Badges
                         :gold :Gold
                         :item :Item
                         :rep :Reputation
                         :chain :Chain})

(fn goal-value [kind v]
  "One goal amount in its kind's display unit: gold formatted from copper,
   chain fractions as a percent, everything else a rounded count."
  (case kind
    :gold (format.gold v)
    :chain (format.percent v)
    _ (tostring (math.floor (+ 0.5 v)))))

(fn goal-line [p]
  "One goal projection as a plan line: progress/target, then the honest
   by-reset band (collapsed to a single number when deterministic)."
  (let [name (or (. goal-kind-labels p.kind) (tostring p.kind))
        head (.. (tostring name) " " (goal-value p.kind p.progress) " / "
                 (goal-value p.kind p.target))
        outlook (if (= p.p10 p.p90)
                    (.. (goal-value p.kind p.p50) " by reset")
                    (.. "P10 " (goal-value p.kind p.p10) " · P50 "
                        (goal-value p.kind p.p50) " · P90 "
                        (goal-value p.kind p.p90) " by reset"))]
    (.. head " · " outlook)))

;; --- Public view-models ------------------------------------------------------

(lambda M.card-view-model [step rank ?advice ?edits]
  "Pure render spec for one activity card.
   Domain:  step   : a route.plan-week step {:name :type :detail :minutes :score
                     :attunement? :items [{:label :chance :runs :item-id} ...]}
            rank   : integer >= 1 (display rank)
            ?advice: {attune-slug text} -- soft 'not attuned' notes, or nil
            ?edits : schemas.PlanEdits (RouteContext :plan-edits), or nil --
                     drives the :pinned? affordance (Phase 8 §2)
   Returns: {:title :subtitle :summary :advisory? string :pinned? boolean
             :items [{:name string :chance-text string :chance number
                      :item-id ?integer} ...<= max-rows]}"
  (let [pinned? (= true
                   (accumulate [hit false _ id (ipairs (or (?. ?edits :pins) []))
                                &until hit]
                     (= (tostring id) (tostring step.id))))]
    {:title (.. "#" rank "  " (tostring step.name))
     :subtitle (.. (tostring step.type) " · " (tostring step.detail)
                   (if pinned? " · pinned" ""))
     :summary (.. "~" step.minutes " min · score "
                  (format.score-short step.score))
     :advisory (let [text (and step.attunement ?advice
                               (. ?advice step.attunement))]
                 (and text (.. "Requires " text)))
     : pinned?
     :items (icollect [_ it (ipairs (top-items step.items))]
              {:name it.label
               :chance-text (chance-text it)
               :chance it.chance
               :item-id it.item-id})}))

(lambda M.skipped-view-model [rows]
  "Pure render spec for the skipped-activities tail row (Phase 8 §2): one
   restore affordance per skipped activity, sorted by name for a stable
   paint. nil when nothing is skipped -- the quiet default (UX §9).
   Domain:  rows : [{:id string :name string} ...] -- resolved skip entries
   Returns: {:headline string :rows [{:id string :label string} ...]} | nil"
  (when (> (length rows) 0)
    (let [sorted (icollect [_ r (ipairs rows)] r)]
      (table.sort sorted (fn [a b] (< (tostring a.name) (tostring b.name))))
      {:headline "Skipped activities"
       :rows (icollect [_ r (ipairs sorted)]
               {:id (tostring r.id) :label (.. "Restore " (tostring r.name))})})))

(lambda M.chain-advice-view-model [?rows]
  "Pure render spec for the 'attunements in progress' advisory card at the
   head of the plan, or nil when no chain is mid-way (unstarted and finished
   chains stay quiet -- UX §9).
   Domain:  ?rows : ctx.build's :chain-advice list, or nil
                    [{:name :next-step-label :done :total :est-minutes} ...]
   Returns: {:headline string :lines [string]} | nil"
  (when (and ?rows (> (length ?rows) 0))
    {:headline "Attunements in progress"
     :lines (icollect [_ r (ipairs ?rows)]
              (.. (tostring r.name) "  " r.done "/" r.total " · next: "
                  (tostring r.next-step-label) " · ~" r.est-minutes " min left"))}))

(lambda M.projection-view-model [?projection]
  "Pure render spec for the weekly Monte Carlo fill projection (the tail summary
   row), or nil when there is no projection / the plan targets no slots.
   Domain:  ?projection : a route.project-week result, or nil
                          {:p10 :p50 :p90 number (fractions) :slots integer}
   Returns: {:headline string :detail string} | nil"
  (when (and ?projection (> (or ?projection.slots 0) 0))
    {:headline "Projected fill by reset"
     :detail (.. "P10 " (format.percent ?projection.p10) " · P50 "
                 (format.percent ?projection.p50) " · P90 "
                 (format.percent ?projection.p90) " of " ?projection.slots
                 (if (= ?projection.slots 1) " target slot" " target slots"))}))

(lambda M.goals-view-model [?projections]
  "Pure render spec for the weekly-goals card at the head of the plan (Phase 7
   §6, OQ-13: goals live IN the Plan tab), or nil with no active goals -- the
   quiet default (UX §9).
   Domain:  ?projections : goals.project result, or nil
                           [{:id :kind :target :progress :p10 :p50 :p90} ...]
   Returns: {:headline string :lines [string]} | nil"
  (when (and ?projections (> (length ?projections) 0))
    {:headline "Weekly goals"
     :lines (icollect [_ p (ipairs ?projections)]
              (goal-line p))}))

;; --- Register into the addon namespace ---------------------------------------

(set _G.Routina Routina)
(set Routina.tab-weekly-vm M)

M
