;; goals.fnl -- player-stated weekly goals: progress, deadline-aware urgency,
;; and the honest P10/P50/P90 projection (ROADMAP Phase 7, resolves OQ-6).
;;
;; PURE domain module: no WoW API, no I/O, no time source, no math.random --
;; the gold projection samples a caller-seeded MINSTD stream
;; (drop-chance.make-rng). Inputs are never mutated.
;;
;; Goal progress is CURRENT HOLDINGS at plan time (money, badge count, owned
;; items, standing, chain fraction) -- resolved by src/domain/ctx.fnl into
;; RouteContext :goal-progress; nothing is accumulated week over week.
;;
;; Deadline-aware arbitration (OQ-11 resolved 2026-06-05):
;;   deficit(g)    = max(0, target - progress)
;;   achievable(g) = sum over activities of yield(a, g) x runs(a) before reset
;;   urgency(g)    = min(1, deficit / achievable)   (1 when nothing achievable)
;;   score(a)     += sum_g urgency(g) x min(1, yield(a,g) x runs(a) / deficit(g))
;; Runs before the reset shrink for daily activities as :reset-at approaches,
;; so a goal that is behind schedule pulls its activities up the plan -- and a
;; plan with no goals scores exactly as before (the scorer adds zero).

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))
(local chance (or Routina.drop-chance (require :src.domain.drop-chance)))
(local yields (or Routina.yields (require :src.domain.yields)))
(local drop-table (or Routina.drop-table (require :src.domain.drop-table)))
(local activities (or Routina.activities (require :src.domain.activities)))

(local M {})

;; Reputation ladder index (schemas standing-enum order): rep goal targets and
;; progress are this 1..8 index, so "reach revered" is target 7.
(local standing-index {:hated 1
                       :hostile 2
                       :unfriendly 3
                       :neutral 4
                       :friendly 5
                       :honored 6
                       :revered 7
                       :exalted 8})

(local seconds-per-day 86400)
(local default-daily-runs 4)
(local default-sims 1000)
(local default-seed 1)

;; --- Helpers (private) -----------------------------------------------------

(fn copy-goal [g]
  "A fresh shallow copy of one GoalDef."
  (collect [k v (pairs g)] k v))

(fn band-for [activity-id ?gold-bands]
  "The gold band route scoring uses: the history-blended override from
   RouteContext :gold-bands when present, else the curated band, else nil."
  (or (and ?gold-bands (. ?gold-bands (tostring activity-id)))
      (yields.gold-band-for activity-id)))

(fn band-mid [range]
  "Midpoint of a gold band -- the expected-value stand-in for scoring; the
   projection keeps the full band."
  (/ (+ range.min range.max) 2))

(fn percentile [sorted q]
  "The q-quantile of an ascending-sorted sample (coupon-collector-mc indexing)."
  (. sorted (math.max 1 (math.floor (* (length sorted) q)))))

(fn goal-runs [adef ?now ?reset-at]
  "Runs of one activity left before the weekly reset (deadline-aware)."
  (case adef.reset
    :daily (if (and ?now ?reset-at (> ?reset-at ?now))
               (math.min 7
                         (math.max 1
                                   (math.ceil (/ (- ?reset-at ?now)
                                                 seconds-per-day))))
               default-daily-runs)
    _ 1))

(fn item-week-p [goal steps ctx]
  "P(the goal item drops by reset) folded over the plan steps that source it."
  (let [entry (and goal.item-id (drop-table.for-item goal.item-id))]
    (if (not entry)
        0
        (accumulate [p 0 _ step (ipairs steps)]
          (if (= (tostring step.id) (tostring entry.source-activity))
              (let [adef (activities.by-id step.id)
                    runs (if adef (goal-runs adef ctx.now ctx.reset-at) 1)
                    p-week (chance.at-least-one entry.base-drop-p runs)]
                (- 1 (* (- 1 p) (- 1 p-week))))
              p)))))

(fn gold-projection [goal steps progress ctx ?opts]
  "Seeded MC of total gold by reset: each planned run pays uniform inside its
   activity's band (max-entropy on a bounded interval -- the band IS the claim)."
  (let [sims (or (and ?opts ?opts.sims) default-sims)
        seed (or (and ?opts ?opts.seed) ctx.seed default-seed)
        rng (chance.make-rng seed)
        run-bands []]
    (each [_ step (ipairs steps)]
      (let [adef (activities.by-id step.id)
            range (band-for step.id ctx.gold-bands)]
        (when (and adef range (> range.max 0))
          (for [_ 1 (goal-runs adef ctx.now ctx.reset-at)]
            (table.insert run-bands range)))))
    (if (= 0 (length run-bands))
        {:p10 progress :p50 progress :p90 progress}
        (let [totals []]
          (for [_ 1 sims]
            (var total progress)
            (each [_ range (ipairs run-bands)]
              (set total (+ total range.min (* (rng) (- range.max range.min)))))
            (table.insert totals total))
          (table.sort totals)
          {:p10 (percentile totals 0.1)
           :p50 (percentile totals 0.5)
           :p90 (percentile totals 0.9)}))))

;; --- Public API ------------------------------------------------------------

(lambda M.normalize [?persisted]
  "Coerce a possibly-nil / possibly-corrupt persisted list into valid GoalDefs.
   User-authored data: invalid entries are DROPPED, never an error -- a corrupt
   SavedVariables row must not take the planner down.
   Domain:  ?persisted : table | nil -- db.char.goals
   Returns: [GoalDef] -- fresh, possibly empty."
  (if (not= (type ?persisted) :table) []
      (icollect [_ g (ipairs ?persisted)]
        (when (and (= (type g) :table)
                   (let [r (validate.check schemas.GoalDef g)] r.ok))
          (copy-goal g)))))

(lambda M.to-db [goals]
  "A fresh plain copy of the goal list for SavedVariables, so the persisted
   table never aliases the live session copy.
   Domain:  goals : [GoalDef]
   Returns: [GoalDef] (plain data)"
  (icollect [_ g (ipairs goals)] (copy-goal g)))

(lambda M.progress [goal inputs]
  "Current progress toward a goal, read from plan-time holdings.
   Domain:  goal   : GoalDef
            inputs : {:money ?int :badge-count ?int :owned-items ?{id true}
                      :standings ?{faction-kw standing-kw}
                      :chain-fractions ?{chain-id number}}
   Returns: number >= 0 in the goal's own unit (copper / badges / 0|1 owned /
            standing index 1..8 / chain fraction 0..1)."
  (case goal.kind
    :gold (or inputs.money 0)
    :badges (or inputs.badge-count 0)
    :item (if (and goal.item-id inputs.owned-items
                   (. inputs.owned-items goal.item-id))
              1
              0)
    :rep (or (. standing-index
                (and inputs.standings goal.faction
                     (. inputs.standings goal.faction))) 0)
    :chain (or (and inputs.chain-fractions goal.chain-id
                    (. inputs.chain-fractions goal.chain-id)) 0)
    _ 0))

(lambda M.deficit [goal ?progress]
  "What is still missing toward the target.
   Domain:  goal : GoalDef ; ?progress : number | nil (nil reads as 0)
   Returns: number >= 0."
  (math.max 0 (- goal.target (or ?progress 0))))

(lambda M.activity-yield [goal activity-id ?gold-bands]
  "Expected per-run payout of one activity toward one goal.
   Gold uses the band midpoint (the projection keeps the full band); items pay
   their per-run drop chance (expected drops); chains never pay through
   activities -- their path is the chain advisory, not the route.
   Domain:  goal : GoalDef ; activity-id : keyword|string
            ?gold-bands : {activity-id {:min :max}} | nil -- blended overrides
   Returns: number >= 0 in the goal's own unit."
  (case goal.kind
    :badges (yields.badges-for activity-id)
    :gold (let [range (band-for activity-id ?gold-bands)]
            (if range (band-mid range) 0))
    :rep (let [rep (yields.rep-for activity-id)]
           (if (and rep goal.faction
                    (= (tostring rep.faction) (tostring goal.faction)))
               rep.amount
               0))
    :item (let [entry (and goal.item-id (drop-table.for-item goal.item-id))]
            (if (and entry
                     (= (tostring entry.source-activity) (tostring activity-id)))
                entry.base-drop-p
                0))
    _ 0))

(lambda M.make-goal-scorer [?goals ctx]
  "Build the per-activity goal scorer route.plan-week folds into its score.
   Precomputes each goal's deficit, achievable-by-reset (over the full
   activity registry -- an optimistic ceiling; lockouts shave it implicitly by
   shaving the plan) and urgency once; the returned closures are O(goals).
   Domain:  ?goals : [GoalDef] | nil -- RouteContext :goals
            ctx    : RouteContext (reads :goal-progress :gold-bands :now
                     :reset-at)
   Returns: {:active?   boolean -- any goal still has a deficit
             :relevant? (fn [activity-id] -> boolean) -- pays toward some goal
             :score     (fn [activity-id] -> number >= 0)} -- the score term;
            a no-goal scorer is inert (active? false, score 0), so plans
            without goals are byte-identical to pre-goal plans."
  (let [adefs (activities.all)
        live (icollect [_ g (ipairs (or ?goals []))]
               (let [progress (or (and ctx.goal-progress
                                       (. ctx.goal-progress g.id))
                                  0)
                     deficit (M.deficit g progress)
                     achievable (accumulate [total 0 _ adef (ipairs adefs)]
                                  (+ total
                                     (* (M.activity-yield g adef.id
                                                          ctx.gold-bands)
                                        (goal-runs adef ctx.now ctx.reset-at))))]
                 (when (> deficit 0)
                   {:goal g
                    : deficit
                    :urgency (if (= achievable 0) 1
                                 (math.min 1 (/ deficit achievable)))})))]
    {:active? (> (length live) 0)
     :relevant? (fn [activity-id]
                  (accumulate [hit false _ row (ipairs live) &until hit]
                    (> (M.activity-yield row.goal activity-id ctx.gold-bands) 0)))
     :score (fn [activity-id]
              (let [adef (activities.by-id activity-id)
                    runs (if adef (goal-runs adef ctx.now ctx.reset-at) 1)]
                (accumulate [total 0 _ row (ipairs live)]
                  (let [yield (M.activity-yield row.goal activity-id
                                                ctx.gold-bands)]
                    (+ total
                       (* row.urgency
                          (math.min 1 (/ (* yield runs) row.deficit))))))))}))

(lambda M.project [goals steps ctx ?opts]
  "Per-goal P10/P50/P90 projection of where the player lands by reset, given
   the planned steps -- 'P50: 130 of your 150 badges'. Deterministic kinds
   (badges, rep) are arithmetic so all three percentiles agree; gold samples
   each run uniformly inside its activity's band (seeded MC); items are the
   at-least-one Bernoulli; rep standing and chain fractions project flat (a
   plan does not advance them mechanically -- honest, not optimistic).
   Domain:  goals : [GoalDef] ; steps : route.plan-week :steps
            ctx   : RouteContext ; ?opts : {:sims ?int>0 :seed ?int}
   Returns: [{:id :kind :target number :progress number
              :p10 :p50 :p90 number} ...] -- absolute, goal units."
  (icollect [_ g (ipairs goals)]
    (let [progress (or (and ctx.goal-progress (. ctx.goal-progress g.id)) 0)
          det (fn [total]
                {:p10 total :p50 total :p90 total})
          range (case g.kind
                  :badges (det (accumulate [total progress _ step (ipairs steps)]
                                 (let [adef (activities.by-id step.id)]
                                   (+ total
                                      (* (yields.badges-for step.id)
                                         (if adef
                                             (goal-runs adef ctx.now
                                                        ctx.reset-at)
                                             1))))))
                  :gold (gold-projection g steps progress ctx ?opts)
                  :item (let [p (item-week-p g steps ctx)]
                          {:p10 (+ progress (if (>= p 0.9) 1 0))
                           :p50 (+ progress (if (>= p 0.5) 1 0))
                           :p90 (+ progress (if (>= p 0.1) 1 0))})
                  _ (det progress))]
      {:id g.id
       :kind g.kind
       :target g.target
       : progress
       :p10 range.p10
       :p50 range.p50
       :p90 range.p90})))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.goals` after
;; yields/drop-table/activities. In tests, consumers fall through to
;; `(require :src.domain.goals)` -> the same M.

(set _G.Routina Routina)
(set Routina.goals M)

M
