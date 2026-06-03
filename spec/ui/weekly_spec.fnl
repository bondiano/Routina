;; weekly_spec.fnl -- the Plan tab's PURE card view-model (UI.md split rule).
;;
;; Only M.card-view-model is exercised here: data -> render spec, no frames.
;; Frame population + the pool are imperative (wowUnit territory); busted just
;; confirms requiring the module doesn't raise (root_spec covers build!).

(local weekly (require :src.ui.tabs.weekly))

(fn item [label chance runs ?id]
  {: label : chance : runs :item-id ?id})

(fn step [overrides]
  (collect [k v (pairs (or overrides {}))
            &into {:name :Karazhan
                   :type :Raid
                   :detail "weekly reset"
                   :minutes 95
                   :score 0.41
                   :items [(item :a 0.3 1 101)]}]
    (values k v)))

(describe :weekly-card-view-model
          (fn []
            (it "renders title, subtitle and summary from the step"
                (fn []
                  (let [vm (weekly.card-view-model (step {}) 1)]
                    (assert.are.equal "#1  Karazhan" vm.title)
                    (assert.are.equal "Raid · weekly reset" vm.subtitle)
                    (assert.is_truthy (string.find vm.summary "95 min" 1 true)))))
            (it "keeps only the top 3 items by chance, highest first"
                (fn []
                  (let [s (step {:items [(item :low 0.1 1 1)
                                         (item :high 0.9 1 2)
                                         (item :mid 0.5 1 3)
                                         (item :tiny 0.01 1 4)]})
                        vm (weekly.card-view-model s 2)]
                    (assert.are.equal 3 (length vm.items))
                    (assert.are.equal 2 (. vm.items 1 :item-id))
                    (assert.are.equal 3 (. vm.items 2 :item-id))
                    (assert.are.equal 1 (. vm.items 3 :item-id)))))
            (it "has no advisory when the activity needs no flagged attunement"
                (fn []
                  (let [vm (weekly.card-view-model (step {}) 1)]
                    (assert.is_nil vm.advisory))))
            (it "shows an advisory when the step's attunement is in advice"
                (fn []
                  (let [s (step {:attunement :kara-key})
                        vm (weekly.card-view-model s 1
                                                   {:kara-key "the Master's Key"})]
                    (assert.are.equal "Requires the Master's Key" vm.advisory))))
            (it "shows no advisory for an attunement absent from advice"
                (fn []
                  (let [s (step {:attunement :ssc-attune})
                        vm (weekly.card-view-model s 1
                                                   {:kara-key "the Master's Key"})]
                    (assert.is_nil vm.advisory))))
            (it "does not mutate the step's item order"
                (fn []
                  (let [items [(item :low 0.1 1 1) (item :high 0.9 1 2)]
                        s (step {: items})
                        _ (weekly.card-view-model s 1)]
                    (assert.are.equal 1 (. items 1 :item-id)))))))
