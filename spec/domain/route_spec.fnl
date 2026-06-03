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
(local kara-feet-p 0.1606)
(local kara-legs-p 0.155)
(local kara-minutes 95)

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
                        (it "plans Karazhan with both unowned feral drops"
                            (fn []
                              (let [step (kara-step (route.plan-week (player)
                                                                     (ctx)))]
                                (assert.is_not_nil step)
                                (assert.are.equal 2 (length step.items))
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
                                                                     (ctx {:owned-items {kara-feet true}})))]
                                (assert.are.equal 1 (length step.items))
                                (assert.are.equal kara-legs
                                                  (. step.items 1 :item-id)))))
                        (it "omits an activity with nothing left to want"
                            (fn []
                              (let [plan (route.plan-week (player)
                                                          (ctx {:owned-items {kara-feet true
                                                                              kara-legs true}}))]
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
                                    kara-expected (+ (chance.at-least-one kara-feet-p
                                                                          1)
                                                     (chance.at-least-one kara-legs-p
                                                                          1))
                                    summed (accumulate [s 0 _ r (ipairs plan.steps)]
                                             (+ s r.score))]
                                ;; the Karazhan step scores its two feral drops
                                ;; under default weights...
                                (assert.are.equal kara-expected kara.score)
                                ;; ...and the plan score sums every planned step.
                                (assert.are.equal summed plan.score))))
                        (it "scales a slot's contribution by its weight"
                            (fn []
                              (let [base (route.plan-week (player) (ctx))
                                    heavy (route.plan-week (player)
                                                           (ctx {:weights {:feet 5}}))
                                    feet (chance.at-least-one kara-feet-p 1)]
                                ;; +4× the feet item's contribution (weight 5 vs 1)
                                (assert.are.equal (+ base.score (* 4 feet))
                                                  heavy.score))))
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
                        (it "sums est-minutes over the planned steps"
                            (fn []
                              (let [plan (route.plan-week (player) (ctx))
                                    summed (accumulate [m 0 _ r (ipairs plan.steps)]
                                             (+ m r.minutes))]
                                (assert.are.equal summed plan.est-minutes)
                                ;; Karazhan contributes its length estimate
                                (assert.are.equal kara-minutes
                                                  (. (kara-step plan) :minutes)))))))
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
