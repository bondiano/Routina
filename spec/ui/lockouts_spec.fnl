;; lockouts_spec.fnl -- the Lockouts tab's PURE view-models (UI.md split rule).
;;
;; Only M.lockout-view-model / M.list-view-model are exercised here: data ->
;; render spec, no frames. Frame population is imperative (wowUnit territory);
;; busted just confirms requiring the module doesn't raise (root_spec covers
;; build!).

(local lockouts-tab (require :src.ui.tabs.lockouts))

(fn lockout [overrides]
  (collect [k v (pairs (or overrides {}))
            &into {:id :karazhan
                   :expiry 1000
                   :bosses-killed 2
                   :bosses-total 4
                   :owner :Hero-Realm}]
    (values k v)))

(fn names [tbl]
  (fn [id] (. tbl id)))

(describe :lockouts-view-model
          (fn []
            (it "renders title, progress and reset text from the lockout"
                (fn []
                  (let [vm (lockouts-tab.lockout-view-model (lockout {:expiry 1000})
                                                            :Karazhan 0)]
                    (assert.are.equal :Karazhan vm.title)
                    (assert.are.equal "2/4 bosses cleared" vm.progress)
                    (assert.is_truthy (string.find vm.reset-text "Resets in" 1
                                                   true)))))
            (it "reports remaining bosses, singular when one is left"
                (fn []
                  (let [vm (lockouts-tab.lockout-view-model (lockout {:bosses-killed 3
                                                                      :bosses-total 4})
                                                            :K 0)]
                    (assert.are.equal "1 boss remaining" vm.status))))
            (it "says fully cleared when no bosses remain"
                (fn []
                  (let [vm (lockouts-tab.lockout-view-model (lockout {:bosses-killed 4
                                                                      :bosses-total 4})
                                                            :K 0)]
                    (assert.are.equal "Fully cleared" vm.status))))
            (it "flags urgency when the reset is within a day"
                (fn []
                  (let [soon (lockouts-tab.lockout-view-model (lockout {:expiry 100})
                                                              :K 0)
                        far (lockouts-tab.lockout-view-model (lockout {:expiry 200000})
                                                             :K 0)]
                    (assert.is_true soon.urgent?)
                    (assert.is_false far.urgent?))))
            (it "is shareable only while active and untouched"
                (fn []
                  (let [fresh (lockouts-tab.lockout-view-model (lockout {:bosses-killed 0
                                                                         :expiry 1000})
                                                               :K 0)
                        started (lockouts-tab.lockout-view-model (lockout {:bosses-killed 1
                                                                           :expiry 1000})
                                                                 :K 0)]
                    (assert.is_true fresh.shareable?)
                    (assert.is_false started.shareable?))))))

(describe :lockouts-list-view-model
          (fn []
            (it "drops lockouts that have already reset"
                (fn []
                  (let [data {:karazhan (lockout {:id :karazhan :expiry 500})
                              :gruuls-lair (lockout {:id :gruuls-lair
                                                     :expiry 50})}
                        vms (lockouts-tab.list-view-model data (names {}) 100)]
                    ;; now=100: karazhan (500) active, gruuls (50) reset -> gone
                    (assert.are.equal 1 (length vms))
                    (assert.are.equal :karazhan (. vms 1 :title)))))
            (it "orders the soonest reset first"
                (fn []
                  (let [data {:karazhan (lockout {:id :karazhan :expiry 5000})
                              :gruuls-lair (lockout {:id :gruuls-lair
                                                     :expiry 2000})}
                        named (names {:karazhan :Karazhan
                                      :gruuls-lair "Gruul's Lair"})
                        vms (lockouts-tab.list-view-model data named 0)]
                    (assert.are.equal 2 (length vms))
                    (assert.are.equal "Gruul's Lair" (. vms 1 :title))
                    (assert.are.equal :Karazhan (. vms 2 :title)))))
            (it "falls back to the activity id when no name resolves"
                (fn []
                  (let [data {:karazhan (lockout {:id :karazhan :expiry 1000})}
                        vms (lockouts-tab.list-view-model data (names {}) 0)]
                    (assert.are.equal :karazhan (. vms 1 :title)))))
            (it "returns an empty list when there are no lockouts"
                (fn []
                  (let [vms (lockouts-tab.list-view-model {} (names {}) 0)]
                    (assert.are.equal 0 (length vms)))))))
