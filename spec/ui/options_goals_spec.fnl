;; options_goals_spec.fnl -- the Goals editor's PURE surface: target parsing,
;; id generation, labels, and the add/remove closures of the AceConfig group
;; builder driven against a plain list (no Ace libs touched).

(local options-goals (require :src.ui.options-goals))

(fn arg [group key]
  (. group.args key))

(fn set-value! [group key v]
  ((. (arg group key) :set) nil v))

(fn run! [group key]
  ((. (arg group key) :func)))

(describe :options-goals
          (fn []
            (describe :parse-target
                      (fn []
                        (it "parses counts, flooring fractions"
                            (fn []
                              (assert.are.equal 150
                                                (options-goals.parse-target :badges
                                                                            :150))
                              (assert.are.equal 150
                                                (options-goals.parse-target :badges
                                                                            :150.9))))
                        (it "converts gold input to copper"
                            (fn []
                              (assert.are.equal 50000000
                                                (options-goals.parse-target :gold
                                                                            :5000))))
                        (it "clamps a rep standing to 8"
                            (fn []
                              (assert.are.equal 8
                                                (options-goals.parse-target :rep
                                                                            :12))))
                        (it "fixes item and chain targets at 1"
                            (fn []
                              (assert.are.equal 1
                                                (options-goals.parse-target :item
                                                                            nil))
                              (assert.are.equal 1
                                                (options-goals.parse-target :chain
                                                                            :junk))))
                        (it "rejects junk and non-positive amounts"
                            (fn []
                              (assert.is_nil (options-goals.parse-target :gold
                                                                         :abc))
                              (assert.is_nil (options-goals.parse-target :badges
                                                                         :0))
                              (assert.is_nil (options-goals.parse-target :badges
                                                                         :-3))))))
            (describe :next-goal-id
                      (fn []
                        (it "starts at g1 and climbs past the highest"
                            (fn []
                              (assert.are.equal :g1
                                                (options-goals.next-goal-id []))
                              (assert.are.equal :g7
                                                (options-goals.next-goal-id [{:id :g2}
                                                                             {:id :g6}
                                                                             {:id :custom}]))))))
            (describe :goal-label
                      (fn []
                        (it "labels each kind readably"
                            (fn []
                              (assert.are.equal "Gold: 5000g"
                                                (options-goals.goal-label {:kind :gold
                                                                           :target 50000000}))
                              (assert.are.equal "Badges: 150"
                                                (options-goals.goal-label {:kind :badges
                                                                           :target 150}))
                              (assert.are.equal "Item #29355"
                                                (options-goals.goal-label {:kind :item
                                                                           :target 1
                                                                           :item-id 29355}))
                              (assert.are.equal "Reputation: ogrila to Revered"
                                                (options-goals.goal-label {:kind :rep
                                                                           :target 7
                                                                           :faction :ogrila}))))))
            (describe :goals-group
                      (fn []
                        (it "adds a valid badge goal to the list and clears the form"
                            (fn []
                              (let [goal-list []
                                    hits {:n 0}
                                    group (options-goals.goals-group {:db {}
                                                                      :goals goal-list
                                                                      :on-change (fn []
                                                                                   (set hits.n
                                                                                        (+ hits.n
                                                                                           1)))})]
                                (set-value! group :kind :badges)
                                (set-value! group :target :150)
                                (run! group :add)
                                (assert.are.equal 1 (length goal-list))
                                (let [g (. goal-list 1)]
                                  (assert.are.equal :badges g.kind)
                                  (assert.are.equal 150 g.target)
                                  (assert.are.equal :g1 g.id))
                                (assert.are.equal 1 hits.n))))
                        (it "refuses to add an invalid draft"
                            (fn []
                              (let [goal-list []
                                    group (options-goals.goals-group {:db {}
                                                                      :goals goal-list})]
                                (set-value! group :kind :gold)
                                (set-value! group :target :nonsense)
                                (run! group :add)
                                (assert.are.equal 0 (length goal-list)))))
                        (it "removes the picked goal"
                            (fn []
                              (let [goal-list [{:id :g1
                                                :kind :badges
                                                :target 10}
                                               {:id :g2
                                                :kind :badges
                                                :target 20}]
                                    group (options-goals.goals-group {:db {}
                                                                      :goals goal-list})]
                                (set-value! group :remove-pick :1)
                                (run! group :remove)
                                (assert.are.equal 1 (length goal-list))
                                (assert.are.equal :g2 (. goal-list 1 :id)))))
                        (it "hides the form fields that do not apply to the kind"
                            (fn []
                              (let [group (options-goals.goals-group {:db {}
                                                                      :goals []})]
                                (set-value! group :kind :item)
                                (assert.is_true ((. (arg group :target) :hidden)))
                                (assert.is_false ((. (arg group :item-id)
                                                     :hidden)))
                                (set-value! group :kind :gold)
                                (assert.is_false ((. (arg group :target)
                                                     :hidden)))
                                (assert.is_true ((. (arg group :item-id)
                                                    :hidden))))))
                        (it "persists the yields toggle and fires on-change"
                            (fn []
                              ;; the live events wiring mirrors the proven
                              ;; track-luck toggle (options_spec) -- busted
                              ;; asserts the persisted flag + change ping.
                              (let [db {}
                                    hits {:n 0}
                                    group (options-goals.goals-group {: db
                                                                      :goals []
                                                                      :on-change (fn []
                                                                                   (set hits.n
                                                                                        (+ hits.n
                                                                                           1)))})]
                                (assert.is_false ((. (arg group :track-yields)
                                                     :get) nil))
                                (set-value! group :track-yields true)
                                (assert.is_true db.track-yields?)
                                (assert.are.equal 1 hits.n))))))))
