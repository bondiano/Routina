;; route_spec.fnl -- tests for the pure weekly-route planner.
;;
;; route ties the real domain together, so these tests run it against the
;; ACTUAL generated catalog/drops (deterministic, like bis_catalog_spec) and
;; assert on contracts that hold regardless of the exact data: the output shape,
;; gap/availability filtering, slot-weight and competition scaling, the
;; :score / :est-minutes aggregates, purity, and determinism (the property).
;;
;; The fixture is a feral druid attuned to (and not locked out of) Karazhan,
;; owning nothing. Karazhan awards Edgewalker Longboots (28545) and Skulker's
;; Greaves (28741), both phase-1 feral BiS; the plan also picks up a Badge of
;; Justice vendor step (Everbloom Idol, p=1) now that the vendor is in the
;; registry -- so aggregate assertions sum over steps rather than assuming a
;; single Karazhan step.

(local route (require :src.domain.route))
(local chance (require :src.domain.drop-chance))
(local gen (require :spec.helpers.gen))
(local bis-catalog (require :src.domain.bis-catalog))
(local drop-table (require :src.domain.drop-table))
(local activities (require :src.domain.activities))

(local kara-feet 28545)
(local kara-legs 28741)
(local kara-back 28672)
(local kara-caster-back 28766)
(local kara-feet-p 0.1606)
(local kara-legs-p 0.155)
(local kara-minutes 95)

(fn near [a b]
  "Float near-equality. The per-slot scorer combines candidates via a complement
   product (1 - Π(1 - p)); for a single-item slot this is 1-(1-p), which differs
   from a raw at-least-one(p) by a rounding epsilon -- semantically identical."
  (< (math.abs (- a b)) 1e-09))

(fn id-set [step]
  "Set of item-ids carried by one plan step."
  (collect [_ it (ipairs step.items)] (values it.item-id true)))

(fn player [?overrides]
  (let [base {:level 70 :attunements {:kara-key true} :reputations {}}]
    (collect [k v (pairs (or ?overrides {})) &into base]
      k
      v)))

(fn ctx [?overrides]
  (let [base {:class :druid
              :spec :feral-dps
              :phase 1
              :now 0
              :owned-items {}
              :lockouts {}}]
    (collect [k v (pairs (or ?overrides {})) &into base]
      k
      v)))

(fn kara-step [plan]
  "The Karazhan step of a plan, or nil."
  (accumulate [found nil _ s (ipairs plan.steps) &until found]
    (when (= s.id :karazhan) s)))

(fn all-item-ids [plan]
  "Set of every item-id recommended anywhere in the plan."
  (let [ids {}]
    (each [_ s (ipairs plan.steps)]
      (each [_ it (ipairs s.items)]
        (tset ids it.item-id true)))
    ids))

(fn warlock-ctx [?overrides]
  (ctx (collect [k v (pairs (or ?overrides {}))
                 &into {:class :warlock :spec :affliction :phase 1}]
         k
         v)))

(describe :route
          (fn []
            (describe ":plan-week shape"
                      (fn []
                        (it "returns {:steps :score :est-minutes}"
                            (fn []
                              (let [plan (route.plan-week (player) (ctx))]
                                (assert.are.equal :table (type plan.steps))
                                (assert.are.equal :number (type plan.score))
                                (assert.are.equal :number
                                                  (type plan.est-minutes)))))
                        (it "rejects a malformed context at the boundary"
                            (fn []
                              (assert.has_error #(route.plan-week (player)
                                                                  {:class :druid}))))))
            (describe "gap + availability filtering"
                      (fn []
                        (it "plans Karazhan with the unowned feral drops"
                            (fn []
                              (let [step (kara-step (route.plan-week (player)
                                                                     (ctx)))
                                    ids (id-set step)]
                                (assert.is_not_nil step)
                                ;; both signature feral drops present (alongside
                                ;; any ranked alternative Karazhan also awards)
                                (assert.is_true (. ids kara-feet))
                                (assert.is_true (. ids kara-legs))
                                (assert.are.equal kara-minutes step.minutes)
                                ;; the step carries its attunement slug for the
                                ;; UI advisory badge
                                (assert.are.equal :kara-key step.attunement)
                                ;; items carry :slot through plan for the
                                ;; why-drawer's weighted breakdown
                                (each [_ it (ipairs step.items)]
                                  (assert.is_not_nil it.slot)))))
                        (it "drops an item once it is owned"
                            (fn []
                              (let [step (kara-step (route.plan-week (player)
                                                                     (ctx {:owned-items {kara-feet true}})))
                                    ids (id-set step)]
                                ;; the owned boots fall away; other drops remain
                                (assert.is_nil (. ids kara-feet))
                                (assert.is_true (. ids kara-legs)))))
                        (it "omits an activity with nothing left to want"
                            (fn []
                              (let [plan (route.plan-week (player)
                                                          (ctx {:owned-items {kara-feet true
                                                                              kara-legs true
                                                                              kara-back true}}))]
                                (assert.is_nil (kara-step plan)))))
                        (it "omits an activity the player cannot enter"
                            (fn []
                              (let [plan (route.plan-week (player {:attunements {}})
                                                          (ctx))]
                                (assert.is_nil (kara-step plan)))))
                        (it "omits a fully-cleared weekly lockout"
                            (fn []
                              (let [locked {:id :karazhan
                                            :expiry 1000
                                            :bosses-killed 11
                                            :bosses-total 11
                                            :owner :Fixture}
                                    plan (route.plan-week (player)
                                                          (ctx {:now 0
                                                                :lockouts {:karazhan locked}}))]
                                (assert.is_nil (kara-step plan)))))
                        (it "excludes BiS items past the player's phase"
                            (fn []
                              ;; phase 0 admits no entries, so Karazhan has nothing to award.
                              (let [plan (route.plan-week (player)
                                                          (ctx {:phase 0}))]
                                (assert.is_nil (kara-step plan)))))))
            (describe :scoring
                      (fn []
                        (it "annotates each item with its at-least-one chance"
                            (fn []
                              (let [step (kara-step (route.plan-week (player)
                                                                     (ctx)))
                                    feet (accumulate [f nil _ i (ipairs step.items)
                                                      &until f]
                                           (when (= i.item-id kara-feet) i))]
                                (assert.are.equal (chance.at-least-one kara-feet-p
                                                                       1)
                                                  feet.chance))))
                        (it "scores the slot-weighted sum of step chances"
                            (fn []
                              (let [plan (route.plan-week (player) (ctx))
                                    kara (kara-step plan)
                                    ;; each feral drop sits in a distinct slot, so
                                    ;; the per-slot combination reduces to the sum
                                    ;; of the step's per-item week-chances
                                    kara-expected (accumulate [s 0 _ it (ipairs kara.items)]
                                                    (+ s
                                                       (chance.at-least-one it.p
                                                                            it.runs)))
                                    summed (accumulate [s 0 _ r (ipairs plan.steps)]
                                             (+ s r.score))]
                                ;; the Karazhan step scores its feral drops under
                                ;; default weights...
                                (assert.is_true (near kara-expected kara.score))
                                ;; ...and the plan score sums every planned step.
                                (assert.are.equal summed plan.score))))
                        (it "scales a slot's contribution by its weight"
                            (fn []
                              (let [base (route.plan-week (player) (ctx))
                                    heavy (route.plan-week (player)
                                                           (ctx {:weights {:feet 5}}))
                                    feet (chance.at-least-one kara-feet-p 1)]
                                ;; +4× the feet slot's contribution (weight 5 vs 1)
                                (assert.is_true (near (+ base.score (* 4 feet))
                                                      heavy.score)))))
                        (it "lowers a chance under loot competition"
                            (fn []
                              (let [solo (kara-step (route.plan-week (player)
                                                                     (ctx)))
                                    contested (kara-step (route.plan-week (player)
                                                                          (ctx {:competitors {:karazhan 4}})))
                                    chance-of #(accumulate [c nil _ i (ipairs $.items)
                                                            &until c]
                                                 (when (= i.item-id kara-feet)
                                                   i.chance))]
                                (assert.is_true (< (chance-of contested)
                                                   (chance-of solo))))))
                        (it "falls back to the global default-competitors"
                            (fn []
                              (let [solo (kara-step (route.plan-week (player)
                                                                     (ctx)))
                                    pooled (kara-step (route.plan-week (player)
                                                                       (ctx {:default-competitors 4})))
                                    chance-of #(accumulate [c nil _ i (ipairs $.items)
                                                            &until c]
                                                 (when (= i.item-id kara-feet)
                                                   i.chance))]
                                (assert.is_true (< (chance-of pooled)
                                                   (chance-of solo))))))
                        ;; By-role composition (PRD OQ-3 resolved). The fixture
                        ;; item is Ruby Drape (28766): a Kara caster cloak
                        ;; contended by :caster specs and :tank (prot paladins
                        ;; are spell-power tanks) -- NOT by melee/ranged/healer.
                        (it "lowers a caster item's chance under a caster-heavy
                             composition"
                            (fn []
                              (let [chance-of #(accumulate [c nil _ i (ipairs (. (kara-step $)
                                                                                 :items))
                                                            &until c]
                                                 (when (= i.item-id
                                                          kara-caster-back)
                                                   i.chance))
                                    solo (route.plan-week (player)
                                                          (warlock-ctx))
                                    pooled (route.plan-week (player)
                                                            (warlock-ctx {:composition {:caster 10
                                                                                        :tank 0
                                                                                        :healer 0
                                                                                        :melee 0
                                                                                        :ranged 0}}))]
                                (assert.is_true (< (chance-of pooled)
                                                   (chance-of solo))))))
                        (it "more casters in the same-size raid -> caster item
                             chance drops (the Phase 4 exit criterion)"
                            (fn []
                              (let [chance-of #(accumulate [c nil _ i (ipairs (. (kara-step $)
                                                                                 :items))
                                                            &until c]
                                                 (when (= i.item-id
                                                          kara-caster-back)
                                                   i.chance))
                                    few (route.plan-week (player)
                                                         (warlock-ctx {:composition {:caster 4
                                                                                     :melee 11
                                                                                     :tank 2
                                                                                     :healer 8
                                                                                     :ranged 0}}))
                                    many (route.plan-week (player)
                                                          (warlock-ctx {:composition {:caster 12
                                                                                      :melee 3
                                                                                      :tank 2
                                                                                      :healer 8
                                                                                      :ranged 0}}))]
                                (assert.is_true (< (chance-of many)
                                                   (chance-of few))))))
                        (it "swapping non-contending roles at equal raid size
                             leaves a caster item's chance unchanged"
                            (fn []
                              (let [chance-of #(accumulate [c nil _ i (ipairs (. (kara-step $)
                                                                                 :items))
                                                            &until c]
                                                 (when (= i.item-id
                                                          kara-caster-back)
                                                   i.chance))
                                    melee-heavy (route.plan-week (player)
                                                                 (warlock-ctx {:composition {:caster 5
                                                                                             :tank 2
                                                                                             :healer 8
                                                                                             :melee 10
                                                                                             :ranged 0}}))
                                    ranged-heavy (route.plan-week (player)
                                                                  (warlock-ctx {:composition {:caster 5
                                                                                              :tank 2
                                                                                              :healer 8
                                                                                              :melee 0
                                                                                              :ranged 10}}))]
                                (assert.are.equal (chance-of melee-heavy)
                                                  (chance-of ranged-heavy)))))
                        (it "an explicit per-activity override beats the composition"
                            (fn []
                              (let [chance-of #(accumulate [c nil _ i (ipairs (. (kara-step $)
                                                                                 :items))
                                                            &until c]
                                                 (when (= i.item-id
                                                          kara-caster-back)
                                                   i.chance))
                                    flat-only (route.plan-week (player)
                                                               (warlock-ctx {:competitors {:karazhan 4}}))
                                    both (route.plan-week (player)
                                                          (warlock-ctx {:competitors {:karazhan 4}
                                                                        :composition {:caster 25
                                                                                      :tank 0
                                                                                      :healer 0
                                                                                      :melee 0
                                                                                      :ranged 0}}))]
                                (assert.are.equal (chance-of flat-only)
                                                  (chance-of both)))))
                        (it "uncontested content (vendor) ignores the global slider"
                            (fn []
                              (let [vendor-step #(accumulate [found nil _ s (ipairs $.steps)
                                                              &until found]
                                                   (when (= s.id :vendor) s))
                                    solo (vendor-step (route.plan-week (player)
                                                                       (ctx)))
                                    pooled (vendor-step (route.plan-week (player)
                                                                         (ctx {:default-competitors 4})))]
                                (assert.is_not_nil solo)
                                (assert.are.equal solo.score pooled.score))))
                        (it "sums est-minutes over the planned steps"
                            (fn []
                              (let [plan (route.plan-week (player) (ctx))
                                    summed (accumulate [m 0 _ r (ipairs plan.steps)]
                                             (+ m r.minutes))]
                                (assert.are.equal summed plan.est-minutes)
                                ;; Karazhan contributes its length estimate
                                (assert.are.equal kara-minutes
                                                  (. (kara-step plan) :minutes)))))))
            (describe "goal scoring (Phase 7 exit criteria)"
                      (fn []
                        (local badge-goal
                               {:id :g-badges :kind :badges :target 150})
                        (local gold-goal ;; 5000g in copper
                               {:id :g-gold :kind :gold :target 50000000})

                        (fn step-of [plan id]
                          (accumulate [found nil _ s (ipairs plan.steps)
                                       &until found]
                            (when (= s.id id) s)))

                        (fn ids-of [plan]
                          (icollect [_ s (ipairs plan.steps)] s.id))

                        (it "a 150-badge goal surfaces badge-dense heroics"
                            (fn []
                              (let [base (route.plan-week (player) (ctx))
                                    goal (route.plan-week (player)
                                                          (ctx {:goals [badge-goal]
                                                                :goal-progress {:g-badges 0}}))
                                    sh-base (step-of base :the-shattered-halls)
                                    sh-goal (step-of goal :the-shattered-halls)
                                    sp-base (step-of base :the-slave-pens)
                                    sp-goal (step-of goal :the-slave-pens)]
                                ;; badge payers gain score; the denser source
                                ;; (5 badges vs 3) gains strictly more
                                (assert.is_not_nil sh-goal)
                                (assert.is_not_nil sp-goal)
                                (let [sh-delta (- sh-goal.score
                                                  (if sh-base sh-base.score 0))
                                      sp-delta (- sp-goal.score
                                                  (if sp-base sp-base.score 0))]
                                  (assert.is_true (> sh-delta 0))
                                  (assert.is_true (> sh-delta sp-delta)))
                                ;; a badge-free raid is untouched by the goal
                                (assert.are.equal (. (step-of base :karazhan)
                                                     :score)
                                                  (. (step-of goal :karazhan)
                                                     :score)))))
                        (it "a met goal changes nothing"
                            (fn []
                              (let [base (route.plan-week (player) (ctx))
                                    met (route.plan-week (player)
                                                         (ctx {:goals [badge-goal]
                                                               :goal-progress {:g-badges 200}}))]
                                (assert.are.same (ids-of base) (ids-of met))
                                (assert.are.equal base.score met.score))))
                        (it "a gold goal pulls in and ranks the densest gold/h
                             source; removing it restores the BiS-first order"
                            (fn []
                              (let [base (route.plan-week (player) (ctx))
                                    goal (route.plan-week (player)
                                                          (ctx {:goals [gold-goal]
                                                                :goal-progress {:g-gold 0}}))
                                    again (route.plan-week (player) (ctx))]
                                ;; Ogri'la dailies pay gold but award no BiS:
                                ;; absent from the BiS-first plan, present and
                                ;; reordered-in under a gold goal
                                (assert.is_nil (step-of base :ogrila-dailies))
                                (assert.is_not_nil (step-of goal
                                                            :ogrila-dailies))
                                (assert.is_false (= (table.concat (ids-of base)
                                                                  ",")
                                                    (table.concat (ids-of goal)
                                                                  ",")))
                                ;; same goal-free context -> byte-identical plan
                                (assert.are.same (ids-of base) (ids-of again))
                                (assert.are.equal base.score again.score))))
                        (it "is deterministic with goals active"
                            (fn []
                              (let [c (ctx {:goals [badge-goal gold-goal]
                                            :goal-progress {:g-badges 40
                                                            :g-gold 1000000}})
                                    a (route.plan-week (player) c)
                                    b (route.plan-week (player) c)]
                                (assert.are.same (ids-of a) (ids-of b))
                                (assert.are.equal a.score b.score))))
                        (it "re-scores a daily badge source as the reset nears
                             (deadline-aware runs)"
                            (fn []
                              ;; the same goal scored a week out vs on reset
                              ;; eve: Slave Pens' planned runs shrink 7 -> 1,
                              ;; so its take, its share of the best source,
                              ;; and hence its goal score all move.
                              (let [day 86400
                                    score-of (fn [plan]
                                               (let [s (step-of plan
                                                                :the-slave-pens)]
                                                 (and s s.score)))
                                    week-out (score-of (route.plan-week (player)
                                                                        (ctx {:goals [badge-goal]
                                                                              :goal-progress {:g-badges 100}
                                                                              :now 1000
                                                                              :reset-at (+ 1000
                                                                                           (* 7
                                                                                              day))})))
                                    eve (score-of (route.plan-week (player)
                                                                   (ctx {:goals [badge-goal]
                                                                         :goal-progress {:g-badges 100}
                                                                         :now 1000
                                                                         :reset-at (+ 1000
                                                                                      day)})))]
                                (assert.is_not_nil week-out)
                                (assert.is_not_nil eve)
                                (assert.is_true (not= week-out eve)))))))
            (describe "custom activities (Phase 8 exit criteria)"
                      (fn []
                        (local gold-goal ;; 5000g in copper
                               {:id :g-gold :kind :gold :target 50000000})
                        ;; A player-authored daily farm lap, as ctx.build
                        ;; threads it: the ActivityDef plus its authored yield
                        ;; (gold band merged into :gold-bands).
                        (local farm
                               {:id :custom-farm
                                :name "Primal farm lap"
                                :type :custom
                                :reset :daily
                                :length-estimate 30
                                :requirements {:min-level 1}})
                        (local farm-yield
                               {:activity-id :custom-farm
                                :badges 0
                                :gold-min 5000000
                                :gold-max 9000000})

                        (fn step-of [plan id]
                          (accumulate [found nil _ s (ipairs plan.steps)
                                       &until found]
                            (when (= s.id id) s)))

                        (fn ids-of [plan]
                          (icollect [_ s (ipairs plan.steps)] s.id))

                        (it "a strong custom yield outranks a weak catalog
                             source under a gold goal"
                            (fn []
                              ;; ~700g/lap vs Ogri'la's ~45g/visit: the custom
                              ;; lap is the densest gold source, so it earns
                              ;; the goal's full urgency and outscores it.
                              (let [plan (route.plan-week (player)
                                                          (ctx {:goals [gold-goal]
                                                                :goal-progress {:g-gold 0}
                                                                :custom-activities [farm]
                                                                :custom-yields {:custom-farm farm-yield}
                                                                :gold-bands {:custom-farm {:min 5000000
                                                                                           :max 9000000}}}))
                                    custom (step-of plan :custom-farm)
                                    ogrila (step-of plan :ogrila-dailies)]
                                (assert.is_not_nil custom)
                                (assert.is_not_nil ogrila)
                                (assert.are.equal :Custom custom.type)
                                (assert.is_true (> custom.score ogrila.score)))))
                        (it "a yield-less custom entry stays in the plan,
                             honestly scored 0 at the tail"
                            (fn []
                              (let [plan (route.plan-week (player)
                                                          (ctx {:custom-activities [farm]}))
                                    custom (step-of plan :custom-farm)
                                    last-step (. plan.steps (length plan.steps))]
                                (assert.is_not_nil custom)
                                (assert.are.equal 0 custom.score)
                                (assert.are.equal 30 custom.minutes)
                                (assert.are.equal :custom-farm last-step.id))))
                        (it "no custom entries -> the plan is byte-identical"
                            (fn []
                              (let [base (route.plan-week (player) (ctx))
                                    empty (route.plan-week (player)
                                                           (ctx {:custom-activities []}))]
                                (assert.are.same (ids-of base) (ids-of empty))
                                (assert.are.equal base.score empty.score))))))
            (describe "plan edits (Phase 8 §2 exit criteria)"
                      (fn []
                        (fn ids-of [plan]
                          (icollect [_ s (ipairs plan.steps)] s.id))

                        (fn step-of [plan id]
                          (accumulate [found nil _ s (ipairs plan.steps)
                                       &until found]
                            (when (= s.id id) s)))

                        (it "a skipped activity never enters the plan"
                            (fn []
                              (let [plan (route.plan-week (player)
                                                          (ctx {:plan-edits {:pins []
                                                                             :skips {:karazhan true}}}))]
                                (assert.is_nil (step-of plan :karazhan)))))
                        (it "pinned activities order first, in pin order,
                             scores untouched"
                            (fn []
                              (let [base (route.plan-week (player) (ctx))
                                    pinned (route.plan-week (player)
                                                            (ctx {:plan-edits {:pins [:vendor
                                                                                      :karazhan]
                                                                               :skips {}}}))]
                                (assert.are.equal :vendor
                                                  (. pinned.steps 1 :id))
                                (assert.are.equal :karazhan
                                                  (. pinned.steps 2 :id))
                                ;; reordering, never re-scoring
                                (assert.are.equal (. (step-of base :karazhan)
                                                     :score)
                                                  (. (step-of pinned :karazhan)
                                                     :score))
                                (assert.are.equal base.score pinned.score))))
                        (it "is deterministic given the same edits"
                            (fn []
                              (let [edits {:pins [:vendor]
                                           :skips {:karazhan true}}
                                    a (route.plan-week (player)
                                                       (ctx {:plan-edits edits}))
                                    b (route.plan-week (player)
                                                       (ctx {:plan-edits edits}))]
                                (assert.are.same (ids-of a) (ids-of b))
                                (assert.are.equal a.score b.score))))
                        (it "no edits -> the plan is byte-identical"
                            (fn []
                              (let [base (route.plan-week (player) (ctx))
                                    empty (route.plan-week (player)
                                                           (ctx {:plan-edits {:pins []
                                                                              :skips {}}}))]
                                (assert.are.same (ids-of base) (ids-of empty))
                                (assert.are.equal base.score empty.score))))))
            (describe "content coverage"
                      (fn []
                        ;; Regression guard for the silent-drop bug: route only
                        ;; surfaces a BiS item when its drop-table source slug
                        ;; matches an activity :id. Every tracked source (bar the
                        ;; honest :unknown) must therefore have a registry entry.
                        (it "every tracked BiS drop source maps to a known activity"
                            (fn []
                              (let [known (collect [_ a (ipairs (activities.all))]
                                            (values a.id true))
                                    misses {}]
                                (each [_ e (ipairs (bis-catalog.all))]
                                  (let [src (drop-table.source-activity (?. e
                                                                            :item
                                                                            :id))]
                                    (when (and src (not= src :unknown)
                                               (not (. known src)))
                                      (tset misses src true))))
                                (let [unmapped (icollect [k _ (pairs misses)] k)]
                                  (assert.are.equal 0 (length unmapped)
                                                    (.. "unmapped drop sources: "
                                                        (table.concat unmapped
                                                                      ", ")))))))))
            (describe ":project-week"
                      (fn []
                        ;; head: filled w.p 1 (a guaranteed drop); neck: never;
                        ;; ring1: filled w.p 1. So exactly 2 of 3 slots always
                        ;; fill -> every percentile is 2/3, deterministically.
                        (let [mixed {:steps [{:items [{:slot :head
                                                       :p 1.0
                                                       :runs 1}
                                                      {:slot :neck
                                                       :p 0.0
                                                       :runs 1}]}
                                             {:items [{:slot :head
                                                       :p 0.5
                                                       :runs 2}
                                                      {:slot :ring1
                                                       :p 1.0
                                                       :runs 1}]}]}]
                          (it "returns zeros for a plan that targets no slots"
                              (fn []
                                (assert.are.same {:p10 0
                                                  :p50 0
                                                  :p90 0
                                                  :slots 0}
                                                 (route.project-week {:steps []}))))
                          (it "counts distinct target slots, deded across steps"
                              (fn []
                                (assert.are.equal 3
                                                  (. (route.project-week mixed)
                                                     :slots))))
                          (it "projects guaranteed/never slots exactly"
                              (fn []
                                (let [r (route.project-week mixed)]
                                  (assert.are.equal (/ 2 3) r.p10)
                                  (assert.are.equal (/ 2 3) r.p50)
                                  (assert.are.equal (/ 2 3) r.p90))))
                          (it "is deterministic for a given seed"
                              (fn []
                                (assert.are.same (route.project-week mixed
                                                                     {:seed 99})
                                                 (route.project-week mixed
                                                                     {:seed 99}))))
                          (it "keeps p10 <= p50 <= p90 (order statistics)"
                              (fn []
                                (let [r (route.project-week {:steps [{:items [{:slot :head
                                                                               :p 0.5
                                                                               :runs 1}]}]}
                                                            {:sims 2000})]
                                  (assert.is_true (<= r.p10 r.p50))
                                  (assert.is_true (<= r.p50 r.p90))))))
                        (it "projects a real route.plan-week result"
                            (fn []
                              (let [r (route.project-week (route.plan-week (player)
                                                                           (ctx)))]
                                (assert.is_true (> r.slots 0))
                                (assert.is_true (and (>= r.p50 0) (<= r.p50 1))))))))
            (describe "classic + excluded filtering"
                      (fn []
                        ;; warlock affliction phase 1 lists Atiesh (22630, a
                        ;; removed vanilla legendary) and Mark of the Champion
                        ;; (23207, pre-TBC) -- both source-activity :quest.
                        (it "never suggests Atiesh, even with classic on"
                            (fn []
                              (let [off (all-item-ids (route.plan-week (player)
                                                                       (warlock-ctx)))
                                    on (all-item-ids (route.plan-week (player)
                                                                      (warlock-ctx {:include-classic? true})))]
                                (assert.is_nil (. off 22630))
                                (assert.is_nil (. on 22630)))))
                        (it "hides pre-TBC drops by default, shows them when opted in"
                            (fn []
                              (let [off (all-item-ids (route.plan-week (player)
                                                                       (warlock-ctx)))
                                    on (all-item-ids (route.plan-week (player)
                                                                      (warlock-ctx {:include-classic? true})))]
                                (assert.is_nil (. off 23207))
                                (assert.is_true (. on 23207)))))))
            (describe "purity + determinism"
                      (fn []
                        (it "does not mutate player or context"
                            (fn []
                              (let [p (player)
                                    c (ctx)
                                    _ (route.plan-week p c)]
                                (assert.is_nil p.class)
                                (assert.is_nil c.steps)
                                (assert.are.same {} c.owned-items))))
                        (it "is deterministic over random weights/competitors (property)"
                            (fn []
                              (let [rng (gen.make-rng 4242)
                                    ids #(icollect [_ s (ipairs $.steps)] s.id)]
                                (for [_ 1 24]
                                  (let [c (ctx {:weights {:feet (gen.int-in rng
                                                                            1 5)
                                                          :legs (gen.int-in rng
                                                                            1 5)}
                                                :competitors {:karazhan (gen.int-in rng
                                                                                    1
                                                                                    6)}})
                                        a (route.plan-week (player) c)
                                        b (route.plan-week (player) c)]
                                    ;; same inputs -> identical plan, and the
                                    ;; reported score always equals Σ step scores
                                    (assert.are.same (ids a) (ids b))
                                    (assert.are.equal a.score b.score)
                                    (let [summed (accumulate [s 0 _ r (ipairs a.steps)]
                                                   (+ s r.score))]
                                      (assert.are.equal summed a.score)))))))))))
