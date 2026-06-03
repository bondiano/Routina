;; why_drawer_spec.fnl -- the why-drawer's PURE explainer view-model.
;;
;; Only M.view-model is exercised (no frames / slide animation): the score
;; breakdown (weight · chance, sorted), the weight explanation, and the loot
;; competition note. The singleton frame + slide-in are wowUnit-tier.

(local why (require :src.ui.widgets.why-drawer))

(fn item [label slot chance]
  {: label : slot : chance :runs 1})

(fn step [overrides]
  (collect [k v (pairs (or overrides {}))
            &into {:name :Karazhan
                   :id :karazhan
                   :score 0.7
                   :items [(item :boots :feet 0.2) (item :ring :ring1 0.5)]}]
    (values k v)))

(describe :why-drawer-view-model
          (fn []
            (it "titles the drawer with the step name"
                (fn []
                  (let [vm (why.view-model (step {}))]
                    (assert.are.equal :Karazhan vm.title))))
            (it "weights default to 1 and breakdown sorts by contribution"
                (fn []
                  (let [vm (why.view-model (step {}))]
                    ;; ring (0.5) outranks boots (0.2) at equal weight 1
                    (assert.are.equal :ring (. vm.score-breakdown 1 :label))
                    (assert.are.equal 1 (. vm.score-breakdown 1 :weight))
                    (assert.are.equal 0.5
                                      (. vm.score-breakdown 1 :contribution))
                    (assert.is_nil vm.weight-explanation))))
            (it "applies slot weights from ctx and re-sorts + explains"
                (fn []
                  (let [vm (why.view-model (step {}) {:weights {:feet 5}})]
                    ;; boots now 5·0.2 = 1.0, outranking ring's 0.5
                    (assert.are.equal :boots (. vm.score-breakdown 1 :label))
                    (assert.are.equal 1.0
                                      (. vm.score-breakdown 1 :contribution))
                    (assert.is_truthy vm.weight-explanation))))
            (it "notes loot competition from the global default"
                (fn []
                  (let [vm (why.view-model (step {}) {:default-competitors 3})]
                    (assert.is_truthy (string.find vm.competition-note :3 1
                                                   true)))))
            (it "notes per-activity competition over the global default"
                (fn []
                  (let [vm (why.view-model (step {})
                                           {:default-competitors 2
                                            :competitors {:karazhan 5}})]
                    (assert.is_truthy (string.find vm.competition-note :5 1
                                                   true)))))
            (it "has no competition note when solo"
                (fn []
                  (let [vm (why.view-model (step {}))]
                    (assert.is_nil vm.competition-note))))
            (it "handles a step with no items"
                (fn []
                  (let [vm (why.view-model (step {:items []}))]
                    (assert.are.equal 0 (length vm.score-breakdown))
                    (assert.is_nil vm.weight-explanation))))))
