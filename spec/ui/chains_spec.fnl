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
                                                    (. b i :title))))))))
            (describe "custom chains (Phase 8 §3)"
                      (fn []
                        (local custom-chains
                               (require :src.domain.custom-chains))
                        (local farm-def
                               (custom-chains.to-chain-def {:id :chain-1
                                                            :name "Primal farm circuit"
                                                            :steps [{:label "Clear the camps"}
                                                                    {:label "Sell and restock"}]}))
                        (it "appends custom defs with checklist rows, any faction"
                            (fn []
                              (let [progress {:chain-1 {:completed {:s1 true}}}
                                    vms (tab.list-view-model progress :Horde
                                                             [farm-def])
                                    custom (accumulate [found nil _ v (ipairs vms)
                                                        &until found]
                                             (when v.custom? v))]
                                (assert.is_not_nil custom)
                                (assert.are.equal :chain-1 custom.chain-id)
                                (assert.are.equal "Primal farm circuit"
                                                  custom.title)
                                (assert.are.equal 2 (length custom.steps))
                                (assert.is_true (. custom.steps 1 :done?))
                                (assert.is_false (. custom.steps 2 :done?))
                                (assert.are.equal "Sell and restock"
                                                  (. custom.steps 2 :label)))))
                        (it "registry rows never carry the checklist fields"
                            (fn []
                              (each [_ v (ipairs (tab.list-view-model nil
                                                                      :Horde
                                                                      [farm-def]))]
                                (when (not v.custom?)
                                  (assert.is_nil v.steps)
                                  (assert.is_nil v.chain-id)))))
                        (it "flags coord-carrying chains as circuits with a
                             pointable next step (Phase 9)"
                            (fn []
                              (let [lap (custom-chains.to-chain-def {:id :chain-3
                                                                     :name "Coord lap"
                                                                     :steps (custom-chains.parse-steps "A @ 1946 20 30
B @ 1946 50 60")})
                                    vms (tab.list-view-model nil nil
                                                             [lap farm-def])
                                    by-id (collect [_ v (ipairs vms)]
                                            (when v.custom?
                                              (values v.chain-id v)))
                                    coord-vm (. by-id :chain-3)
                                    plain-vm (. by-id :chain-1)]
                                (assert.is_true coord-vm.circuit?)
                                (assert.are.equal lap coord-vm.def)
                                ;; the unstarted chain points at its FIRST step
                                (assert.are.same {:map-id 1946 :x 0.2 :y 0.3}
                                                 coord-vm.next-coord)
                                (assert.are.equal :A coord-vm.next-label)
                                (assert.is_false plain-vm.circuit?)
                                (assert.is_nil plain-vm.next-coord))))))))
