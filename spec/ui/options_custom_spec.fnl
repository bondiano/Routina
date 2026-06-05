;; options_custom_spec.fnl -- the PURE Custom-activities AceConfig builder
;; (Phase 8 §1). Same harness as options_goals_spec: drive the group's
;; get/set/func closures directly, assert the persisted list and the form
;; lifecycle. No Ace3 libs touched.

(local options-custom (require :src.ui.options-custom))

(fn arg [group key]
  (. group.args key))

(fn set-value! [group key v]
  ((. (arg group key) :set) nil v))

(fn get-value [group key]
  ((. (arg group key) :get) nil))

(fn run! [group key]
  ((. (arg group key) :func)))

(fn build [customs ?goals ?on-change]
  (options-custom.custom-group {:custom-activities customs
                                :goals (or ?goals [])
                                :on-change ?on-change}))

(fn fill-valid! [group]
  (set-value! group :name "Primal farm lap")
  (set-value! group :minutes :45)
  (set-value! group :reset :daily))

(describe :options-custom
          (fn []
            (describe :next-custom-id
                      (fn []
                        (it "starts at custom-1 and climbs past the top id"
                            (fn []
                              (assert.are.equal :custom-1
                                                (options-custom.next-custom-id []))
                              (assert.are.equal :custom-4
                                                (options-custom.next-custom-id [{:id :custom-3}
                                                                                {:id :custom-1}]))))))
            (describe :custom-label
                      (fn []
                        (it "describes the entry with its authored yields"
                            (fn []
                              (let [label (options-custom.custom-label {:id :custom-1
                                                                        :name :Lap
                                                                        :est-minutes 45
                                                                        :reset :daily
                                                                        :badges 3})]
                                (assert.is_truthy (string.find label
                                                               "Lap (45 min, daily)"
                                                               1 true))
                                (assert.is_truthy (string.find label "3 badges"
                                                               1 true)))))))
            (describe :add
                      (fn []
                        (it "adds a valid activity and clears the form"
                            (fn []
                              (var fired false)
                              (let [customs []
                                    group (build customs [] #(set fired true))]
                                (fill-valid! group)
                                (run! group :add)
                                (assert.are.equal 1 (length customs))
                                (assert.are.equal :custom-1 (. customs 1 :id))
                                (assert.are.equal 45 (. customs 1 :est-minutes))
                                (assert.are.equal :daily (. customs 1 :reset))
                                (assert.is_true fired)
                                (assert.are.equal "" (get-value group :name))
                                (assert.are.equal "" (get-value group :minutes)))))
                        (it "stores the gold band in copper"
                            (fn []
                              (let [customs []
                                    group (build customs)]
                                (fill-valid! group)
                                (set-value! group :gold-min :20)
                                (set-value! group :gold-max :60)
                                (run! group :add)
                                (assert.are.equal 200000
                                                  (. customs 1 :gold-min))
                                (assert.are.equal 600000
                                                  (. customs 1 :gold-max)))))
                        (it "links the selected goal, omitting the none sentinel"
                            (fn []
                              (let [customs []
                                    goals [{:id :g1 :kind :gold :target 1}]
                                    group (build customs goals)]
                                (fill-valid! group)
                                (set-value! group :goal-link :g1)
                                (run! group :add)
                                (assert.are.equal :g1 (. customs 1 :goal-id))
                                (fill-valid! group)
                                (set-value! group :goal-link :none)
                                (run! group :add)
                                (assert.is_nil (. customs 2 :goal-id)))))
                        (it "rejects a blank name or missing length"
                            (fn []
                              (let [customs []
                                    group (build customs)]
                                (set-value! group :minutes :45)
                                (run! group :add)
                                (set-value! group :name "Named, no length")
                                (set-value! group :minutes "")
                                (run! group :add)
                                (assert.are.equal 0 (length customs)))))
                        (it "rejects an inverted gold band, keeping the form"
                            (fn []
                              (let [customs []
                                    group (build customs)]
                                (fill-valid! group)
                                (set-value! group :gold-min :60)
                                (set-value! group :gold-max :20)
                                (run! group :add)
                                (assert.are.equal 0 (length customs))
                                ;; the half-filled form survives for fixing
                                (assert.are.equal "Primal farm lap"
                                                  (get-value group :name)))))
                        (it "rejects a rep faction without an amount"
                            (fn []
                              (let [customs []
                                    group (build customs)]
                                (fill-valid! group)
                                (set-value! group :rep-faction :ogrila)
                                (run! group :add)
                                (assert.are.equal 0 (length customs))
                                (set-value! group :rep-amount :250)
                                (run! group :add)
                                (assert.are.equal 1 (length customs))
                                (assert.are.equal :ogrila
                                                  (. customs 1 :rep-faction))
                                (assert.are.equal 250 (. customs 1 :rep-amount)))))))
            (describe :remove
                      (fn []
                        (it "removes the picked entry and fires on-change"
                            (fn []
                              (var fired 0)
                              (let [customs []
                                    group (build customs []
                                                 #(set fired (+ fired 1)))]
                                (fill-valid! group)
                                (run! group :add)
                                (fill-valid! group)
                                (run! group :add)
                                (set-value! group :remove-pick :1)
                                (run! group :remove)
                                (assert.are.equal 1 (length customs))
                                (assert.are.equal :custom-2 (. customs 1 :id))
                                (assert.are.equal 3 fired))))
                        (it "is a no-op without a valid pick"
                            (fn []
                              (let [customs []
                                    group (build customs)]
                                (fill-valid! group)
                                (run! group :add)
                                (run! group :remove)
                                (assert.are.equal 1 (length customs)))))))))
