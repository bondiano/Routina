;; lockouts_spec.fnl -- tests for the pure lockout model.
;;
;; Pure module: no WoW API, no mocks, no real clock. Every "now" is a fixed
;; deterministic timestamp so the suite is reproducible. The killed <= total
;; invariant and the time clamp at reset get explicit coverage.

(local lockouts (require :src.domain.lockouts))

;; A fixed server-time anchor so every case reads against a known instant.
(local now 1000)

(fn lockout [overrides]
  "Build a valid Lockout fixture, base fields overridden by `overrides`.
   Returns a fresh table so cases never share state."
  (collect [k v (pairs (or overrides {}))
            &into {:id :kara
                   :expiry (+ now 3600)
                   :bosses-killed 0
                   :bosses-total 11
                   :owner :Mainchar}]
    (values k v)))

(describe :lockouts
          (fn []
            (describe ":bosses-remaining"
                      (fn []
                        (it "is total minus killed"
                            (fn []
                              (assert.are.equal 8
                                                (lockouts.bosses-remaining (lockout {:bosses-killed 3
                                                                                     :bosses-total 11})))))
                        (it "is 0 on a fully cleared lockout"
                            (fn []
                              (assert.are.equal 0
                                                (lockouts.bosses-remaining (lockout {:bosses-killed 11
                                                                                     :bosses-total 11})))))
                        (it "equals total on a fresh lockout"
                            (fn []
                              (assert.are.equal 11
                                                (lockouts.bosses-remaining (lockout {:bosses-killed 0})))))
                        (it "rejects killed > total"
                            (fn []
                              (assert.has_error (fn []
                                                  (lockouts.bosses-remaining (lockout {:bosses-killed 5
                                                                                       :bosses-total 4}))))))
                        (it "rejects a missing owner"
                            (fn []
                              (assert.has_error (fn []
                                                  (lockouts.bosses-remaining {:id :x
                                                                              :expiry now
                                                                              :bosses-killed 0
                                                                              :bosses-total 3})))))))
            (describe ":time-until-reset"
                      (fn []
                        (it "is the gap to a future expiry"
                            (fn []
                              (assert.are.equal 600
                                                (lockouts.time-until-reset (lockout {:expiry (+ now
                                                                                                600)})
                                                                           now))))
                        (it "clamps to 0 when expiry is in the past"
                            (fn []
                              (assert.are.equal 0
                                                (lockouts.time-until-reset (lockout {:expiry (- now
                                                                                                50)})
                                                                           now))))
                        (it "is 0 exactly at expiry"
                            (fn []
                              (assert.are.equal 0
                                                (lockouts.time-until-reset (lockout {:expiry now})
                                                                           now))))
                        (it "rejects a non-numeric now"
                            (fn []
                              (assert.has_error (fn []
                                                  (lockouts.time-until-reset (lockout {})
                                                                             :soon)))))))
            (describe ":lockout-active?"
                      (fn []
                        (it "is true before expiry"
                            (fn []
                              (assert.is_true (lockouts.lockout-active? (lockout {:expiry (+ now
                                                                                             1)})
                                                                        now))))
                        (it "is false at expiry"
                            (fn []
                              (assert.is_false (lockouts.lockout-active? (lockout {:expiry now})
                                                                         now))))
                        (it "is false after expiry"
                            (fn []
                              (assert.is_false (lockouts.lockout-active? (lockout {:expiry (- now
                                                                                              1)})
                                                                         now))))
                        (it "returns a boolean, not a truthy value (property)"
                            (fn []
                              (each [_ e (ipairs [(- now 100) now (+ now 100)])]
                                (let [r (lockouts.lockout-active? (lockout {:expiry e})
                                                                  now)]
                                  (assert.are.equal :boolean (type r))))))))
            (describe ":lockout-shareable?"
                      (fn []
                        (it "is true when active and zero bosses killed"
                            (fn []
                              (assert.is_true (lockouts.lockout-shareable? (lockout {:expiry (+ now
                                                                                                3600)
                                                                                     :bosses-killed 0})
                                                                           now))))
                        (it "is false once any boss is killed"
                            (fn []
                              (assert.is_false (lockouts.lockout-shareable? (lockout {:expiry (+ now
                                                                                                 3600)
                                                                                      :bosses-killed 1})
                                                                            now))))
                        (it "is false when expired even if fresh"
                            (fn []
                              (assert.is_false (lockouts.lockout-shareable? (lockout {:expiry (- now
                                                                                                 1)
                                                                                      :bosses-killed 0})
                                                                            now))))
                        (it "returns a boolean (property)"
                            (fn []
                              (let [r (lockouts.lockout-shareable? (lockout {})
                                                                   now)]
                                (assert.are.equal :boolean (type r)))))))))
