;; wow_spec.fnl -- the WoW->domain boundary, exercised against the WoW mock.
;;
;; No Ace3 needed: wow.fnl touches only plain WoW globals, all stubbed in
;; spec/mocks/wow-api.fnl. We assert the translation (tuples/bitmask -> domain
;; tables) and that output validates against schemas.Lockout.

(local wow (require :src.core.wow))
(local validate (require :src.domain.validate))
(local schemas (require :src.domain.schemas))
(local mock (require :spec.mocks.wow-api))

(describe :wow
          (fn []
            (before_each (fn [] (mock.reset!)))
            (describe ":now"
                      (fn []
                        (it "returns the current server time"
                            (fn []
                              (mock.set-current-time! 1700000000)
                              (assert.are.equal 1700000000 (wow.now))))))
            (describe ":player-info"
                      (fn []
                        (it "returns name, realm and a lower-cased class token"
                            (fn []
                              (mock.set-player! :Routina :Firemaw)
                              (let [info (wow.player-info)]
                                (assert.are.equal :Routina info.name)
                                (assert.are.equal :Firemaw info.realm)
                                ;; mock UnitClass -> (values :Priest :PRIEST 5)
                                (assert.are.equal :priest info.class))))))
            (describe ":saved-instances"
                      (fn []
                        (it "returns an empty list when nothing is saved"
                            (fn []
                              (let [result (wow.saved-instances)]
                                (assert.is_true result.ok)
                                (assert.are.equal 0 (length result.lockouts)))))
                        (it "parses a live lockout into a valid Lockout"
                            (fn []
                              (mock.set-current-time! 1000)
                              (mock.set-saved-instances! [{:name :Karazhan
                                                           :lockout-id 532
                                                           :reset 604800
                                                           :difficulty-name :Normal
                                                           :is-raid true
                                                           :n-encounters 2
                                                           ;; bit 0 set -> encounter 1 killed, 2 not
                                                           :encounter-progress 1
                                                           :encounters [{:name :Attumen}
                                                                        {:name :Moroes}]}])
                              (let [result (wow.saved-instances)]
                                (assert.is_true result.ok)
                                (assert.are.equal 1 (length result.lockouts))
                                (let [lk (. result.lockouts 1)]
                                  (assert.are.equal :Karazhan lk.name)
                                  (assert.are.equal 532 lk.instance-id)
                                  ;; reset-at = now + reset, server time not os.time
                                  (assert.are.equal (+ 1000 604800) lk.reset-at)
                                  (assert.are.equal :normal lk.difficulty)
                                  (assert.is_true lk.is-raid?)
                                  (assert.is_true (. lk.encounters 1 :killed?))
                                  (assert.is_false (. lk.encounters 2 :killed?))
                                  ;; the whole point: it satisfies the schema
                                  (assert.is_true (. (validate.check schemas.Lockout
                                                                     lk)
                                                     :ok))))))
                        (it "maps Heroic difficulty to :heroic"
                            (fn []
                              (mock.set-saved-instances! [{:name :Mechanar
                                                           :lockout-id 555
                                                           :reset 86400
                                                           :difficulty-name :Heroic
                                                           :is-raid false
                                                           :n-encounters 0
                                                           :encounter-progress 0
                                                           :encounters []}])
                              (let [lk (. (wow.saved-instances) :lockouts 1)]
                                (assert.are.equal :heroic lk.difficulty)
                                (assert.is_false lk.is-raid?))))
                        (it "skips extended (no longer counting down) lockouts"
                            (fn []
                              (mock.set-saved-instances! [{:name :Gruul
                                                           :lockout-id 565
                                                           :reset 604800
                                                           :extended 1
                                                           :n-encounters 0
                                                           :encounter-progress 0
                                                           :encounters []}])
                              (let [result (wow.saved-instances)]
                                (assert.are.equal 0 (length result.lockouts)))))))))

;; --- Route-input gatherers (Phase 2) ---------------------------------------

(describe :wow-route-input
          (fn []
            (before_each (fn [] (mock.reset!)))
            (describe ":player-level"
                      (fn []
                        (it "returns the player's level"
                            (fn []
                              (mock.set-player-level! 64)
                              (assert.are.equal 64 (wow.player-level))))))
            (describe ":talent-points"
                      (fn []
                        (it "returns points spent per talent tab"
                            (fn []
                              (mock.set-talent-points! [5 41 15])
                              (assert.are.same [5 41 15] (wow.talent-points))))))
            (describe ":owned-item-ids"
                      (fn []
                        (it "is empty with nothing equipped or bagged"
                            (fn []
                              (assert.are.equal 0 (length (wow.owned-item-ids)))))
                        (it "collects equipped and bagged item ids"
                            (fn []
                              (mock.set-equipped! {1 28745 5 28746})
                              ;; 16-slot bag with two occupied slots (1 and 3)
                              (mock.set-bags! {0 {:size 16
                                                  :items {1 29434 3 30627}}})
                              (let [ids (wow.owned-item-ids)
                                    seen {}]
                                (each [_ id (ipairs ids)] (tset seen id true))
                                (assert.is_true (. seen 28745))
                                (assert.is_true (. seen 28746))
                                (assert.is_true (. seen 29434))
                                (assert.is_true (. seen 30627)))))))
            (describe ":quest-completed?"
                      (fn []
                        (it "reflects the quest flag"
                            (fn []
                              (mock.set-quest-completed! 9999 true)
                              (assert.is_true (wow.quest-completed? 9999))
                              (assert.is_false (wow.quest-completed? 8888))))))
            (describe ":faction-standing"
                      (fn []
                        (it "returns the standing id for a known faction"
                            (fn []
                              (mock.set-faction-standing! 1038 6)
                              (assert.are.equal 6 (wow.faction-standing 1038))))
                        (it "returns nil for an unknown faction"
                            (fn []
                              (assert.is_nil (wow.faction-standing 1234))))))
            (describe ":request-raid-info!"
                      (fn []
                        (it "is a safe no-op call"
                            (fn []
                              (assert.is_nil (wow.request-raid-info!))))))
            (describe ":loot-item-id"
                      (fn []
                        (it "parses the itemID from a loot hyperlink"
                            (fn []
                              (assert.are.equal 28545
                                                (wow.loot-item-id "You receive loot: |cffa335ee|Hitem:28545::::::::70:::::|h[Boots]|h|r."))))
                        (it "is nil when there is no item link"
                            (fn []
                              (assert.is_nil (wow.loot-item-id "You receive coin"))
                              (assert.is_nil (wow.loot-item-id nil))))))
            (describe ":self-loot?"
                      (fn []
                        (it "is true for the player's own loot line"
                            (fn []
                              (assert.is_true (wow.self-loot? "You receive loot: |Hitem:28545:|h[Boots]|h|r."))))
                        (it "is false for a group member's loot line"
                            (fn []
                              (assert.is_false (wow.self-loot? "Bob receives loot: |Hitem:28545:|h[Boots]|h|r."))))
                        (it "is false for a nil message"
                            (fn []
                              (assert.is_false (wow.self-loot? nil))))))))
