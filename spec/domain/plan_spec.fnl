;; plan_spec.fnl -- tests for the pure weekly-plan view-model builder.
;;
;; Pure module: no WoW API, no mocks. Deterministic ordering is the
;; headline contract, so it gets a property check alongside the unit cases.

(local plan (require :src.domain.plan))
(local chance (require :src.domain.drop-chance))

(fn activity [id name minutes items]
  "Build a catalog activity fixture."
  {: id : name :type :raid :detail :10-man : minutes : items})

(fn item [label p runs ?item-id]
  {: label : p : runs :item-id ?item-id})

(describe :plan
          (fn []
            (describe ":score-activity"
                      (fn []
                        (it "sums at-least-one across target items"
                            (fn []
                              (let [a (activity :kara :Karazhan 95
                                                [(item :shoulders 0.2 3)
                                                 (item :ring 0.1 1)])
                                    expected (+ (chance.at-least-one 0.2 3)
                                                (chance.at-least-one 0.1 1))]
                                (assert.are.equal expected
                                                  (plan.score-activity a)))))
                        (it "is 0 for an activity with no items"
                            (fn []
                              (assert.are.equal 0
                                                (plan.score-activity (activity :x
                                                                               :Empty
                                                                               30
                                                                               [])))))
                        (it "never exceeds the item count (property)"
                            (fn []
                              (let [a (activity :kara :Karazhan 95
                                                [(item :a 0.9 5)
                                                 (item :b 0.8 5)
                                                 (item :c 0.7 5)])]
                                (assert.is_true (<= (plan.score-activity a)
                                                    (length a.items))))))))
            (describe ":plan-week"
                      (fn []
                        (it "orders activities by score descending"
                            (fn []
                              (let [weak (activity :heroic :Heroic 30
                                                   [(item :badge 0.05 1)])
                                    strong (activity :kara :Karazhan 95
                                                     [(item :sh 0.25 3)
                                                      (item :rg 0.2 3)])
                                    rows (plan.plan-week [weak strong])]
                                (assert.are.equal :kara (. rows 1 :id))
                                (assert.are.equal :heroic (. rows 2 :id)))))
                        (it "annotates each item with chance and carries item-id"
                            (fn []
                              (let [rows (plan.plan-week [(activity :kara
                                                                    :Karazhan 95
                                                                    [(item :sh
                                                                           0.2 3
                                                                           29760)])])
                                    row1item1 (. rows 1 :items 1)]
                                (assert.are.equal (chance.at-least-one 0.2 3)
                                                  row1item1.chance)
                                (assert.are.equal :sh row1item1.label)
                                (assert.are.equal 29760 row1item1.item-id))))
                        (it "breaks score ties by fewer minutes first"
                            (fn []
                              (let [slow (activity :slow :Slow 120
                                                   [(item :x 0.2 2)])
                                    fast (activity :fast :Fast 40
                                                   [(item :y 0.2 2)])
                                    rows (plan.plan-week [slow fast])]
                                (assert.are.equal :fast (. rows 1 :id)))))
                        (it "is deterministic regardless of input order (property)"
                            (fn []
                              (let [a (activity :a :Alpha 60 [(item :i 0.3 2)])
                                    b (activity :b :Bravo 60 [(item :j 0.1 2)])
                                    c (activity :c :Charlie 90
                                                [(item :k 0.5 4)])
                                    ids #(icollect [_ r (ipairs $)] r.id)
                                    o1 (ids (plan.plan-week [a b c]))
                                    o2 (ids (plan.plan-week [c a b]))
                                    o3 (ids (plan.plan-week [b c a]))]
                                (assert.are.same o1 o2)
                                (assert.are.same o2 o3))))
                        (it "carries :slot through to the rendered item rows"
                            (fn []
                              (let [a {:id :kara
                                       :name :Karazhan
                                       :type :raid
                                       :detail :10-man
                                       :minutes 95
                                       :items [{:label :sh
                                                :p 0.2
                                                :runs 3
                                                :slot :shoulder}]}
                                    rows (plan.plan-week [a])]
                                (assert.are.equal :shoulder
                                                  (. rows 1 :items 1 :slot)))))
                        (it "uses an injected ?score-fn for score and ordering"
                            (fn []
                              (let [a (activity :a :Alpha 60 [(item :i 0.2 2)])
                                    b (activity :b :Bravo 60 [(item :j 0.9 2)])
                                    ;; invert the natural order: rank by minutes,
                                    ;; ignoring drop chance entirely
                                    by-minutes #(- $.minutes)
                                    rows (plan.plan-week [a b] by-minutes)]
                                (assert.are.equal (- 60) (. rows 1 :score))
                                ;; chance is still annotated by plan, not the scorer
                                (assert.are.equal (chance.at-least-one 0.2 2)
                                                  (. rows 1 :items 1 :chance)))))
                        (it "does not mutate the input catalog"
                            (fn []
                              (let [a (activity :kara :Karazhan 95
                                                [(item :sh 0.2 3)])
                                    catalog [a]
                                    _ (plan.plan-week catalog)]
                                (assert.is_nil a.score)
                                (assert.is_nil (. a.items 1 :chance)))))))))
