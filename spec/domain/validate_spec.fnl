;; validate_spec.fnl -- runtime contract checks for the schema validator.
;;
;; Pure module, no WoW mocks needed. We pass schemas explicitly as the
;; ?registry arg so the tests don't depend on _G.Routina load order.

(local validate (require :src.domain.validate))
(local schemas (require :src.domain.schemas))

(fn check [schema value]
  (validate.check schema value schemas))

(fn valid-lockout []
  {:name :Karazhan
   :instance-id 532
   :reset-at 1735000000
   :difficulty :normal
   :is-raid? true
   :encounters [{:name :Attumen :killed? true} {:name :Moroes :killed? false}]})

(describe :validate
          (fn []
            (describe ":check scalars"
                      (fn []
                        (it "accepts a well-formed value"
                            (fn []
                              (let [r (check schemas.Item
                                             {:id 19019 :name :Thunderfury})]
                                (assert.is_true r.ok)
                                (assert.are.equal 0 (length r.errors)))))
                        (it "rejects a wrong scalar type with a path"
                            (fn []
                              (let [r (check schemas.Item {:id :nope :name :x})]
                                (assert.is_false r.ok)
                                (assert.are.equal 1 (length r.errors))
                                (assert.is_truthy (string.find (. r.errors 1)
                                                               :id 1 true)))))
                        (it "treats a non-integral number as not an integer"
                            (fn []
                              (let [r (check schemas.Item {:id 3.5 :name :x})]
                                (assert.is_false r.ok))))
                        (it "accepts an integral float for :integer"
                            (fn []
                              (let [r (check schemas.Item {:id 12.0 :name :x})]
                                (assert.is_true r.ok))))
                        (it "flags a missing required field"
                            (fn []
                              (let [r (check schemas.Item {:id 5})]
                                (assert.is_false r.ok)
                                (assert.is_truthy (string.find (. r.errors 1)
                                                               :missing 1 true)))))))
            (describe ":check composites"
                      (fn []
                        (it "validates a nested record with refs and lists"
                            (fn []
                              (let [r (check schemas.Lockout (valid-lockout))]
                                (assert.is_true r.ok))))
                        (it "reports a dotted path into a list element"
                            (fn []
                              (let [bad (valid-lockout)]
                                (tset (. bad.encounters 2) :killed? :yes)
                                (let [r (check schemas.Lockout bad)]
                                  (assert.is_false r.ok)
                                  (assert.is_truthy (string.find (. r.errors 1)
                                                                 "encounters[2].killed?"
                                                                 1 true))))))
                        (it "rejects an out-of-enum value"
                            (fn []
                              (let [bad (valid-lockout)]
                                (tset bad :difficulty :mythic)
                                (let [r (check schemas.Lockout bad)]
                                  (assert.is_false r.ok)
                                  (assert.is_truthy (string.find (. r.errors 1)
                                                                 :enum 1 true))))))
                        (it "accepts an absent optional field"
                            (fn []
                              (let [r (check schemas.TargetItem
                                             {:label :Tier :p 0.2 :runs 4})]
                                (assert.is_true r.ok))))
                        (it "checks a present optional field"
                            (fn []
                              (let [r (check schemas.TargetItem
                                             {:label :Tier
                                              :p 0.2
                                              :runs 4
                                              :item-id :no})]
                                (assert.is_false r.ok))))))
            (describe ":assert!"
                      (fn []
                        (it "returns the value unchanged when valid"
                            (fn []
                              (let [v {:id 1 :name :x}]
                                (assert.are.equal v
                                                  (validate.assert! schemas.Item
                                                                    v :Item
                                                                    schemas)))))
                        (it "throws a joined message when invalid"
                            (fn []
                              (assert.has_error (fn []
                                                  (validate.assert! schemas.Item
                                                                    {:id :x}
                                                                    :Item
                                                                    schemas)))))))
            (describe ":coerce"
                      (fn []
                        (it "turns a numeric string into an integer"
                            (fn []
                              (let [r (validate.coerce schemas.Item
                                                       {:id :42 :name :x}
                                                       schemas)]
                                (assert.is_true r.ok)
                                (assert.are.equal 42 r.value.id))))
                        (it "floors a non-integral number for :integer"
                            (fn []
                              (let [r (validate.coerce schemas.Item
                                                       {:id 3.9 :name :x}
                                                       schemas)]
                                (assert.is_true r.ok)
                                (assert.are.equal 3 r.value.id))))
                        (it "coerces nested list elements"
                            (fn []
                              (let [raw (valid-lockout)]
                                (tset raw :instance-id :532)
                                (let [r (validate.coerce schemas.Lockout raw
                                                         schemas)]
                                  (assert.is_true r.ok)
                                  (assert.are.equal 532 r.value.instance-id)))))
                        (it "leaves the original value unmutated"
                            (fn []
                              (let [raw {:id :7 :name :x}
                                    _ (validate.coerce schemas.Item raw schemas)]
                                (assert.are.equal :7 raw.id))))
                        (it "still reports errors it cannot coerce away"
                            (fn []
                              (let [r (validate.coerce schemas.Item
                                                       {:id :abc :name :x}
                                                       schemas)]
                                (assert.is_false r.ok))))))))
