;; bis_spec.fnl -- the BiS tab's PURE view-model (UI.md split rule).
;;
;; Only M.list-view-model is exercised here: data -> render spec, no frames.
;; Frame population is imperative (wowUnit territory); busted just confirms
;; requiring the module doesn't raise (root_spec covers build!).

(local bis-tab (require :src.ui.tabs.bis))

(fn entry [slot id name phase kind rank]
  {: slot
   :item {: id : name}
   :phase (or phase 1)
   :kind (or kind :bis)
   :rank (or rank 1)})

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
                    (assert.are.equal 0 (length vm.rows)))))
            (it "lists ranked alternatives under the primary, best rank first"
                (fn []
                  (let [items [(entry :head 1 :Best 1 :bis 1)
                               (entry :head 2 :Second 1 :bis 2)
                               (entry :head 3 :Third 1 :bis 3)]
                        vm (bis-tab.list-view-model items {})
                        row (. vm.rows 1)]
                    (assert.are.equal :Best row.name)
                    (assert.are.equal 2 (length row.alts))
                    (assert.are.equal :Second (. row.alts 1 :name))
                    (assert.are.equal :Third (. row.alts 2 :name)))))
            (it "caps the alternatives at three per slot"
                (fn []
                  (let [items [(entry :head 1 :R1 1 :bis 1)
                               (entry :head 2 :R2 1 :bis 2)
                               (entry :head 3 :R3 1 :bis 3)
                               (entry :head 4 :R4 1 :bis 4)
                               (entry :head 5 :R5 1 :bis 5)]
                        vm (bis-tab.list-view-model items {})]
                    (assert.are.equal 3 (length (. vm.rows 1 :alts))))))
            (it "filters by kind, defaulting to :bis"
                (fn []
                  (let [items [(entry :head 1 :RaidHelm 1 :bis 1)
                               (entry :head 2 :DungeonHelm 1 :pre-raid 1)]
                        bis-vm (bis-tab.list-view-model items {})
                        pre-vm (bis-tab.list-view-model items {} :pre-raid)]
                    (assert.are.equal :RaidHelm (. bis-vm.rows 1 :name))
                    (assert.are.equal :bis bis-vm.kind)
                    (assert.are.equal :DungeonHelm (. pre-vm.rows 1 :name))
                    (assert.are.equal :pre-raid pre-vm.kind))))
            (it "marks an alternative owned from the owned set"
                (fn []
                  (let [items [(entry :head 1 :Best 1 :bis 1)
                               (entry :head 2 :Alt 1 :bis 2)]
                        vm (bis-tab.list-view-model items {2 true})
                        row (. vm.rows 1)]
                    (assert.is_false row.owned?)
                    (assert.is_true (. row.alts 1 :owned?)))))))
