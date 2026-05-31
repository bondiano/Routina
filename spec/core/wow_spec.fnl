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
