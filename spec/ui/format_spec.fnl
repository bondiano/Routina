;; spec/ui/format_spec.fnl -- pure tests for percent / duration / score.

(local format (require :src.ui.format))

(describe :format
          (fn []
            (describe ":percent"
                      (fn []
                        (it "formats 0 as 0%"
                            (fn []
                              (assert.are.equal "0%" (format.percent 0))))
                        (it "formats 0.5 as 50%"
                            (fn []
                              (assert.are.equal "50%" (format.percent 0.5))))
                        (it "formats 1 as 100%"
                            (fn []
                              (assert.are.equal "100%" (format.percent 1))))
                        (it "rounds 0.625 to 63%"
                            (fn []
                              (assert.are.equal "63%" (format.percent 0.625))))
                        (it "rounds 0.624 to 62%"
                            (fn []
                              (assert.are.equal "62%" (format.percent 0.624))))
                        (it "guards against nil"
                            (fn []
                              (assert.are.equal "--" (format.percent nil))))
                        (it "guards against NaN"
                            (fn []
                              (assert.are.equal "--" (format.percent (/ 0 0)))))))
            (describe ":duration-short"
                      (fn []
                        (it "uses d/h for >= 1 day"
                            (fn []
                              (assert.are.equal "2d 4h"
                                                (format.duration-short (+ (* 2
                                                                             86400)
                                                                          (* 4
                                                                             3600))))))
                        (it "uses h/m for >= 1 hour"
                            (fn []
                              (assert.are.equal "8h 21m"
                                                (format.duration-short (+ (* 8
                                                                             3600)
                                                                          (* 21
                                                                             60))))))
                        (it "uses m:ss for sub-hour"
                            (fn []
                              (assert.are.equal "0:42"
                                                (format.duration-short 42))))
                        (it "guards against nil"
                            (fn []
                              (assert.are.equal "--"
                                                (format.duration-short nil))))
                        (it "guards against negative"
                            (fn []
                              (assert.are.equal "--" (format.duration-short -1))))))
            (describe ":score-short"
                      (fn []
                        (it "formats 0.83 as 0.83"
                            (fn []
                              (assert.are.equal :0.83 (format.score-short 0.83))))
                        (it "guards against nil"
                            (fn []
                              (assert.are.equal "--" (format.score-short nil))))))
            (describe ":gold"
                      (fn []
                        (it "formats gold and silver, dropping copper at >= 1g"
                            (fn []
                              (assert.are.equal "12g 34s" (format.gold 123456))))
                        (it "collapses to bare gold with no silver"
                            (fn []
                              (assert.are.equal :120g (format.gold 1200000))))
                        (it "formats sub-gold as silver and copper"
                            (fn []
                              (assert.are.equal "34s 56c" (format.gold 3456))
                              (assert.are.equal :99c (format.gold 99))))
                        (it "renders zero and guards nil/negative"
                            (fn []
                              (assert.are.equal :0c (format.gold 0))
                              (assert.are.equal "--" (format.gold nil))
                              (assert.are.equal "--" (format.gold -5))))))
            (describe ":gold-band"
                      (fn []
                        (it "renders the honest range"
                            (fn []
                              (assert.are.equal "10g–25g"
                                                (format.gold-band {:min 100000
                                                                   :max 250000}))))
                        (it "collapses a degenerate band to one amount"
                            (fn []
                              (assert.are.equal :10g
                                                (format.gold-band {:min 100000
                                                                   :max 100000}))))
                        (it "guards nil"
                            (fn []
                              (assert.are.equal "--" (format.gold-band nil))))))
            (describe ":plan-lines"
                      (fn []
                        (local plan
                               {:score 1.25
                                :est-minutes 140
                                :steps [{:name :Karazhan
                                         :type :Raid
                                         :minutes 95
                                         :score 0.83
                                         :items [{:label :Boots
                                                  :item-id 1
                                                  :chance 0.16}
                                                 {:label :Greaves
                                                  :item-id 2
                                                  :chance 0.31}
                                                 {:label :Cloak
                                                  :item-id 3
                                                  :chance 0.05}
                                                 {:label :Ring
                                                  :item-id 4
                                                  :chance 0.21}]}
                                        {:name "Badge vendor"
                                         :type :Vendor
                                         :minutes 45
                                         :score 0.42
                                         :items [{:label :Idol
                                                  :item-id 5
                                                  :chance 1}]}]})
                        (it "emits a header plus one line per step"
                            (fn []
                              (let [lines (format.plan-lines plan)]
                                (assert.are.equal 3 (length lines))
                                (assert.are.equal "Routina weekly plan -- score 1.25, ~140 min:"
                                                  (. lines 1)))))
                        (it "caps each step at its top 3 items, likeliest first"
                            (fn []
                              (let [lines (format.plan-lines plan)]
                                (assert.are.equal "1. Karazhan (Raid, ~95m, score 0.83): Greaves 31%, Ring 21%, Boots 16%"
                                                  (. lines 2))
                                (assert.are.equal "2. Badge vendor (Vendor, ~45m, score 0.42): Idol 100%"
                                                  (. lines 3)))))
                        (it "reports an empty plan in one line"
                            (fn []
                              (let [lines (format.plan-lines {:steps []})]
                                (assert.are.equal 1 (length lines))
                                (assert.is_truthy (string.find (. lines 1)
                                                               "nothing to plan"
                                                               1 true)))))
                        (it "treats nil as an empty plan"
                            (fn []
                              (assert.are.equal 1
                                                (length (format.plan-lines nil)))))))
            (describe ":debug-lines"
                      (fn []
                        (it "renders db, tracking and plan summaries"
                            (fn []
                              (let [lines (format.debug-lines {:version 1
                                                               :log-level :info
                                                               :tracking? true
                                                               :runs 4
                                                               :drops 1
                                                               :steps 3
                                                               :score 2.31
                                                               :est-minutes 180})]
                                (assert.are.equal "Routina debug -- db v1, log info"
                                                  (. lines 1))
                                (assert.are.equal "luck tracking: on (runs 4, drops 1)"
                                                  (. lines 2))
                                (assert.are.equal "plan: 3 steps, score 2.31, ~180 min"
                                                  (. lines 3)))))
                        (it "surfaces a route-input failure instead of the plan"
                            (fn []
                              (let [lines (format.debug-lines {:err :loading})]
                                (assert.are.equal "luck tracking: off (runs 0, drops 0)"
                                                  (. lines 2))
                                (assert.are.equal "route input: unavailable -- loading"
                                                  (. lines 3)))))))))
