;; chains_spec.fnl (ui) -- the Chains tab's pure view-models: per-chain card
;; spec, faction filtering, and the in-progress-first ordering. The imperative
;; render! is wowUnit-tier (manual smoke), per UI.md.

(local tab (require :src.ui.tabs.chains))
(local chains (require :src.domain.chains))

(fn complete-progress [chain-id]
  (let [chain (chains.by-id chain-id)]
    {:completed (collect [_ s (ipairs chain.steps)] s.id true)}))

(describe :chains-tab
          (fn []
            (describe :chain-view-model
                      (fn []
                        (it "describes an unstarted chain"
                            (fn []
                              (let [kara (chains.by-id :karazhan)
                                    vm (tab.chain-view-model kara
                                                             (chains.empty-progress))]
                                (assert.are.equal :Karazhan vm.title)
                                (assert.is_truthy (string.find vm.progress-text
                                                               :0/ 1 true))
                                (assert.are.equal "Not started" vm.status)
                                (assert.is_false vm.started?)
                                (assert.is_false vm.complete?))))
                        (it "describes a started chain with its next step and estimate"
                            (fn []
                              (let [kara (chains.by-id :karazhan)
                                    vm (tab.chain-view-model kara
                                                             {:completed {:30 true}})]
                                (assert.is_true vm.started?)
                                (assert.is_false vm.complete?)
                                (assert.is_truthy (string.find vm.status
                                                               "Next: " 1 true))
                                (assert.is_truthy (string.find vm.status
                                                               "min left" 1 true)))))
                        (it "describes a complete chain"
                            (fn []
                              (let [kara (chains.by-id :karazhan)
                                    vm (tab.chain-view-model kara
                                                             (complete-progress :karazhan))]
                                (assert.is_true vm.complete?)
                                (assert.are.equal :Complete vm.status))))))
            (describe :list-view-model
                      (fn []
                        (it "filters to the player's faction plus Both"
                            (fn []
                              (let [horde (tab.list-view-model nil :Horde)
                                    titles (collect [_ vm (ipairs horde)]
                                             vm.title
                                             true)]
                                ;; faction-neutral chain present
                                (assert.is_true (. titles :Karazhan))
                                ;; the Alliance-only Honor Hold heroics chain is filtered
                                (each [_ vm (ipairs horde)]
                                  (assert.is_not.equal "Honor Hold Heroics"
                                                       vm.title)))))
                        (it "shows every chain when faction is unknown (headless)"
                            (fn []
                              (let [all (tab.list-view-model nil nil)]
                                (assert.are.equal (length (chains.all))
                                                  (length all)))))
                        (it "orders in-progress first, unstarted next, complete last"
                            (fn []
                              (let [progress {:karazhan {:completed {:30 true}}
                                              :shadow-labyrinth (complete-progress :shadow-labyrinth)}
                                    vms (tab.list-view-model progress :Horde)]
                                (assert.is_true (. vms 1 :started?))
                                (assert.are.equal :Karazhan (. vms 1 :title))
                                ;; complete chains sink to the bottom
                                (assert.is_true (. vms (length vms) :complete?))
                                (assert.are.equal "Shadow Labyrinth"
                                                  (. vms (length vms) :title)))))
                        (it "is deterministic: same input, same order"
                            (fn []
                              (let [a (tab.list-view-model nil :Alliance)
                                    b (tab.list-view-model nil :Alliance)]
                                (assert.are.equal (length a) (length b))
                                (for [i 1 (length a)]
                                  (assert.are.equal (. a i :title)
                                                    (. b i :title))))))))))
