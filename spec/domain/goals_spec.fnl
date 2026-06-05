;; goals_spec.fnl -- tests for the goal engine: progress accounting,
;; deadline-aware urgency scoring, and the seeded P10/P50/P90 projection.
;; Pure fixtures only -- no WoW API, no clock, no math.random.

(local goals (require :src.domain.goals))

(local day 86400)
(local now 1717891200)

(fn ctx-of [over]
  "A minimal goal-facing RouteContext: a week to the reset unless overridden."
  (let [base {: now :reset-at (+ now (* 7 day)) :goal-progress {}}]
    (each [k v (pairs (or over {}))]
      (tset base k v))
    base))

(fn badge-goal [target]
  {:id :g-badges :kind :badges : target})

(fn gold-goal [target]
  {:id :g-gold :kind :gold : target})

(describe :goals
          (fn []
            (describe :normalize
                      (fn []
                        (it "returns [] for nil / non-table input"
                            (fn []
                              (assert.are.same [] (goals.normalize nil))
                              (assert.are.same [] (goals.normalize :junk))))
                        (it "keeps valid goals and drops corrupt rows"
                            (fn []
                              (let [out (goals.normalize [(badge-goal 150)
                                                          {:id :bad
                                                           :kind :nonesuch
                                                           :target 1}
                                                          :garbage
                                                          {:no :fields}])]
                                (assert.are.equal 1 (length out))
                                (assert.are.equal :g-badges (. out 1 :id)))))
                        (it "returns fresh copies, never aliasing the input"
                            (fn []
                              (let [g (badge-goal 150)
                                    out (goals.normalize [g])]
                                (assert.is_false (rawequal g (. out 1))))))))
            (describe :progress
                      (fn []
                        (it "reads each kind from its holding"
                            (fn []
                              (let [inputs {:money 42
                                            :badge-count 7
                                            :owned-items {29355 true}
                                            :standings {:ogrila :honored}
                                            :chain-fractions {:karazhan 0.5}}]
                                (assert.are.equal 42
                                                  (goals.progress (gold-goal 100)
                                                                  inputs))
                                (assert.are.equal 7
                                                  (goals.progress (badge-goal 150)
                                                                  inputs))
                                (assert.are.equal 1
                                                  (goals.progress {:id :i
                                                                   :kind :item
                                                                   :target 1
                                                                   :item-id 29355}
                                                                  inputs))
                                (assert.are.equal 6
                                                  (goals.progress {:id :r
                                                                   :kind :rep
                                                                   :target 8
                                                                   :faction :ogrila}
                                                                  inputs))
                                (assert.are.equal 0.5
                                                  (goals.progress {:id :c
                                                                   :kind :chain
                                                                   :target 1
                                                                   :chain-id :karazhan}
                                                                  inputs)))))
                        (it "defaults every missing holding to 0"
                            (fn []
                              (assert.are.equal 0
                                                (goals.progress (gold-goal 100)
                                                                {}))))))
            (describe :deficit
                      (fn []
                        (it "is target minus progress, clamped at 0"
                            (fn []
                              (assert.are.equal 100
                                                (goals.deficit (gold-goal 150)
                                                  50))
                              (assert.are.equal 0
                                                (goals.deficit (gold-goal 150)
                                                  999))
                              (assert.are.equal 150
                                                (goals.deficit (gold-goal 150)
                                                  nil))))))
            (describe :activity-yield
                      (fn []
                        (it "pays badges from the yield table"
                            (fn []
                              (assert.are.equal 5
                                                (goals.activity-yield (badge-goal 150)
                                                                      :heroic-mech))
                              (assert.are.equal 0
                                                (goals.activity-yield (badge-goal 150)
                                                                      :karazhan))))
                        (it "pays gold at the band midpoint, blended band winning"
                            (fn []
                              (assert.are.equal 175000
                                                (goals.activity-yield (gold-goal 1)
                                                                      :heroic-mech))
                              (assert.are.equal 50
                                                (goals.activity-yield (gold-goal 1)
                                                                      :heroic-mech
                                                                      {:heroic-mech {:min 0
                                                                                     :max 100}}))))
                        (it "pays rep only on the matching faction"
                            (fn []
                              (let [rep-goal {:id :r
                                              :kind :rep
                                              :target 8
                                              :faction :ogrila}]
                                (assert.is_true (> (goals.activity-yield rep-goal
                                                                         :ogrila-dailies)
                                                   0))
                                (assert.are.equal 0
                                                  (goals.activity-yield rep-goal
                                                                        :skettis-daily)))))
                        (it "chains never pay through activities"
                            (fn []
                              (assert.are.equal 0
                                                (goals.activity-yield {:id :c
                                                                       :kind :chain
                                                                       :target 1
                                                                       :chain-id :x}
                                                                      :karazhan))))))
            (describe :make-goal-scorer
                      (fn []
                        (it "is inert with no goals -- score 0 everywhere"
                            (fn []
                              (let [s (goals.make-goal-scorer nil (ctx-of {}))]
                                (assert.is_false s.active?)
                                (assert.are.equal 0 (s.score :heroic-mech))
                                (assert.is_false (s.relevant? :heroic-mech)))))
                        (it "is inert once the goal is already met"
                            (fn []
                              (let [ctx (ctx-of {:goal-progress {:g-badges 200}})
                                    s (goals.make-goal-scorer [(badge-goal 150)]
                                                              ctx)]
                                (assert.is_false s.active?)
                                (assert.are.equal 0 (s.score :heroic-mech)))))
                        (it "marks badge-paying activities relevant for a badge goal"
                            (fn []
                              (let [s (goals.make-goal-scorer [(badge-goal 150)]
                                                              (ctx-of {}))]
                                (assert.is_true s.active?)
                                (assert.is_true (s.relevant? :heroic-mech))
                                (assert.is_false (s.relevant? :karazhan)))))
                        (it "scores badge-dense heroics above badge-free raids"
                            (fn []
                              (let [s (goals.make-goal-scorer [(badge-goal 150)]
                                                              (ctx-of {}))]
                                (assert.is_true (> (s.score :heroic-mech)
                                                   (s.score :karazhan)))
                                (assert.is_true (> (s.score :heroic-mech)
                                                   (s.score :heroic-slabs))))))
                        (it "raises an at-risk goal's score as the deadline nears"
                            (fn []
                              ;; modest target: with a week left there is slack
                              ;; (low urgency); with one day left every badge
                              ;; run counts (urgency up, score up).
                              (let [week (goals.make-goal-scorer [(badge-goal 10)]
                                                                 (ctx-of {}))
                                    eve (goals.make-goal-scorer [(badge-goal 10)]
                                                                (ctx-of {:reset-at (+ now
                                                                                      day)}))]
                                (assert.is_true (> (eve.score :heroic-mech)
                                                   (week.score :heroic-mech))))))
                        (it "caps each goal's score term at its urgency"
                            (fn []
                              (let [s (goals.make-goal-scorer [(badge-goal 1)]
                                                              (ctx-of {}))]
                                ;; deficit 1: contribution clamps to 1, so the
                                ;; term is exactly the urgency, <= 1.
                                (assert.is_true (<= (s.score :heroic-mech) 1)))))))
            (describe :project
                      (fn []
                        (local steps [{:id :heroic-mech :minutes 35 :items []}])
                        (it "projects badges deterministically: bosses x runs"
                            (fn []
                              ;; 7 days -> 7 daily runs x 5 badges = 35 + 3 held
                              (let [ctx (ctx-of {:goal-progress {:g-badges 3}})
                                    [p] (goals.project [(badge-goal 150)] steps
                                                       ctx)]
                                (assert.are.equal 38 p.p10)
                                (assert.are.equal 38 p.p50)
                                (assert.are.equal 38 p.p90)
                                (assert.are.equal 3 p.progress)
                                (assert.are.equal 150 p.target))))
                        (it "projects gold as a seeded band inside run bounds"
                            (fn []
                              ;; 7 runs x band [100000, 250000]
                              (let [ctx (ctx-of {:seed 7})
                                    [p] (goals.project [(gold-goal 5000000)]
                                                       steps ctx)]
                                (assert.is_true (>= p.p10 700000))
                                (assert.is_true (<= p.p90 1750000))
                                (assert.is_true (<= p.p10 p.p50))
                                (assert.is_true (<= p.p50 p.p90)))))
                        (it "is reproducible for a seed and moves with it"
                            (fn []
                              (let [ctx (ctx-of {:seed 7})
                                    [a] (goals.project [(gold-goal 1)] steps
                                                       ctx)
                                    [b] (goals.project [(gold-goal 1)] steps
                                                       ctx)
                                    [c] (goals.project [(gold-goal 1)] steps
                                                       (ctx-of {:seed 8}))]
                                (assert.are.equal a.p50 b.p50)
                                (assert.is_false (= a.p50 c.p50)))))
                        (it "projects rep and chain progress flat (honest)"
                            (fn []
                              (let [ctx (ctx-of {:goal-progress {:c 0.5}})
                                    [p] (goals.project [{:id :c
                                                         :kind :chain
                                                         :target 1
                                                         :chain-id :x}]
                                                       steps ctx)]
                                (assert.are.equal 0.5 p.p10)
                                (assert.are.equal 0.5 p.p90))))))))
