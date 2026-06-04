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
                    (assert.is_nil vm.weight-explanation))))
            (it "has no diff without a comparison step"
                (fn []
                  (assert.is_nil (. (why.view-model (step {})) :diff))))
            (it "diffs against the alternative it out-scores"
                (fn []
                  (let [a (step {:name :Karazhan :score 0.7 :minutes 95})
                        b (step {:name :Gruul :score 0.5 :minutes 60})
                        diff (. (why.view-model a nil b) :diff)]
                    (assert.are.equal :Gruul diff.vs)
                    (assert.is_true diff.leads?)
                    ;; 0.7 - 0.5, within float tolerance
                    (assert.is_true (< (math.abs (- 0.2 diff.delta)) 1e-09))
                    ;; the score line is always the first reason
                    (assert.is_truthy (string.find (. diff.reasons 1) :0.70 1
                                                   true))
                    (assert.is_truthy (string.find (. diff.reasons 1) :0.50 1
                                                   true)))))
            (it "ranks top contributors (<=3) and names the strongest"
                (fn []
                  (let [a (step {:name :Karazhan
                                 :score 0.7
                                 :items [(item :boots :feet 0.2)
                                         (item :ring :ring1 0.5)
                                         (item :cloak :back 0.1)
                                         (item :belt :waist 0.05)]})
                        b (step {:name :Gruul :score 0.3})
                        diff (. (why.view-model a nil b) :diff)]
                    (assert.are.equal 3 (length diff.top-items))
                    (assert.are.equal :ring (. diff.top-items 1 :label))
                    ;; "Most of the edge: ring ..." is among the reasons
                    (assert.is_truthy (string.find (. diff.reasons 2) :ring 1
                                                   true)))))
            (it "explains a weighted slot and a shorter run in the diff"
                (fn []
                  (let [a (step {:name :Karazhan :score 1.2 :minutes 60})
                        b (step {:name :Gruul :score 0.5 :minutes 95})
                        diff (. (why.view-model a {:weights {:feet 5}} b) :diff)
                        joined (table.concat diff.reasons " | ")]
                    (assert.is_truthy (string.find joined "×5" 1 true))
                    (assert.is_truthy (string.find joined "min shorter" 1 true)))))))
