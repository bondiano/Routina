;; bis_spec.fnl -- the BiS tab's PURE view-model (UI.md split rule).
;;
;; Only M.list-view-model is exercised here: data -> render spec, no frames.
;; Frame population is imperative (wowUnit territory); busted just confirms
;; requiring the module doesn't raise (root_spec covers build!).

(local bis-tab (require :src.ui.tabs.bis))

(fn entry [slot id name phase]
  {: slot :item {: id : name} :phase (or phase 1)})

(describe :bis-list-view-model
          (fn []
            (it "emits one row per slot, in canonical slot order"
                (fn []
                  (let [items [(entry :feet 2 :Boots 1)
                               (entry :head 1 :Helm 1)]
                        vm (bis-tab.list-view-model items {})]
                    (assert.are.equal 2 (length vm.rows))
                    ;; head precedes feet regardless of input order
                    (assert.are.equal :Head (. vm.rows 1 :slot-label))
                    (assert.are.equal :Feet (. vm.rows 2 :slot-label)))))
            (it "carries the item name and id onto the row"
                (fn []
                  (let [vm (bis-tab.list-view-model [(entry :head 42 :Helm 1)]
                                                    {})
                        row (. vm.rows 1)]
                    (assert.are.equal :Helm row.name)
                    (assert.are.equal 42 row.item-id))))
            (it "marks a row owned when its id is in the owned set"
                (fn []
                  (let [items [(entry :head 1 :Helm 1)
                               (entry :feet 2 :Boots 1)]
                        vm (bis-tab.list-view-model items {1 true})]
                    (assert.is_true (. vm.rows 1 :owned?))
                    (assert.is_false (. vm.rows 2 :owned?)))))
            (it "picks the highest-phase item when a slot has several"
                (fn []
                  (let [items [(entry :head 1 :OldHelm 1)
                               (entry :head 2 :NewHelm 2)]
                        vm (bis-tab.list-view-model items {})]
                    (assert.are.equal 1 (length vm.rows))
                    (assert.are.equal :NewHelm (. vm.rows 1 :name))
                    (assert.are.equal 2 (. vm.rows 1 :phase)))))
            (it "summarizes owned vs total across the rows"
                (fn []
                  (let [items [(entry :head 1 :Helm 1)
                               (entry :feet 2 :Boots 1)
                               (entry :neck 3 :Amulet 1)]
                        vm (bis-tab.list-view-model items {1 true 3 true})]
                    (assert.are.equal 2 vm.owned)
                    (assert.are.equal 3 vm.total)
                    (assert.is_truthy (string.find vm.summary :2/3 1 true)))))
            (it "treats a nil owned set as nothing owned"
                (fn []
                  (let [vm (bis-tab.list-view-model [(entry :head 1 :Helm 1)]
                                                    nil)]
                    (assert.are.equal 0 vm.owned)
                    (assert.is_false (. vm.rows 1 :owned?)))))
            (it "returns an empty checklist for no items"
                (fn []
                  (let [vm (bis-tab.list-view-model [] {})]
                    (assert.are.equal 0 vm.total)
                    (assert.are.equal 0 (length vm.rows)))))))
