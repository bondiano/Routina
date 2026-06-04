;; weekly_state_spec.fnl -- tests for the pure weekly-progress record.
;;
;; Pure module: no WoW API, no real clock. Every "now" is a fixed deterministic
;; timestamp. Covers immutability (inputs never mutated), idempotent re-entry,
;; reset pruning, and the defensive normalize over corrupt SavedVariables.

(local weekly-state (require :src.domain.weekly-state))

(local now 1000)
(local week (* 7 24 3600))

(describe :weekly-state
          (fn []
            (describe ":empty"
                      (fn []
                        (it "has no lockouts and an unknown reset"
                            (fn []
                              (let [s (weekly-state.empty)]
                                (assert.are.equal 0 s.reset-time)
                                (assert.are.same {} s.lockouts))))))
            (describe ":mark-in-progress"
                      (fn []
                        (it "records the lockout as in-progress"
                            (fn []
                              (let [s (weekly-state.mark-in-progress (weekly-state.empty)
                                                                     :kara now
                                                                     (+ now
                                                                        week))]
                                (assert.is_true (weekly-state.in-progress? s
                                                                           :kara))
                                (assert.are.equal now
                                                  (. s.lockouts :kara
                                                     :entered-at))
                                (assert.are.equal (+ now week)
                                                  (. s.lockouts :kara :reset-at)))))
                        (it "does not mutate the input state"
                            (fn []
                              (let [s0 (weekly-state.empty)]
                                (weekly-state.mark-in-progress s0 :kara now)
                                (assert.are.same {} s0.lockouts))))
                        (it "is idempotent on entered-at when re-entered"
                            (fn []
                              (let [s1 (weekly-state.mark-in-progress (weekly-state.empty)
                                                                      :kara now
                                                                      0)
                                    s2 (weekly-state.mark-in-progress s1 :kara
                                                                      (+ now
                                                                         500)
                                                                      (+ now
                                                                         week))]
                                ;; first entry time kept, newly-known reset folded in
                                (assert.are.equal now
                                                  (. s2.lockouts :kara
                                                     :entered-at))
                                (assert.are.equal (+ now week)
                                                  (. s2.lockouts :kara
                                                     :reset-at)))))
                        (it "derives reset-time as the earliest known reset"
                            (fn []
                              (let [s (-> (weekly-state.empty)
                                          (weekly-state.mark-in-progress :kara
                                                                         now
                                                                         (+ now
                                                                            week))
                                          (weekly-state.mark-in-progress :gruul
                                                                         now
                                                                         (+ now
                                                                            3600)))]
                                (assert.are.equal (+ now 3600) s.reset-time))))))
            (describe ":in-progress?"
                      (fn []
                        (it "is false for an unknown lockout"
                            (fn []
                              (assert.is_false (weekly-state.in-progress? (weekly-state.empty)
                                                                          :nope))))))
            (describe ":prune"
                      (fn []
                        (it "drops lockouts whose reset has passed"
                            (fn []
                              (let [s (-> (weekly-state.empty)
                                          (weekly-state.mark-in-progress :old
                                                                         now
                                                                         (- now
                                                                            1))
                                          (weekly-state.mark-in-progress :live
                                                                         now
                                                                         (+ now
                                                                            week)))
                                    pruned (weekly-state.prune s now)]
                                (assert.is_false (weekly-state.in-progress? pruned
                                                                            :old))
                                (assert.is_true (weekly-state.in-progress? pruned
                                                                           :live)))))
                        (it "keeps lockouts with an unknown reset"
                            (fn []
                              (let [s (weekly-state.mark-in-progress (weekly-state.empty)
                                                                     :kara now 0)]
                                (assert.is_true (weekly-state.in-progress? (weekly-state.prune s
                                                                                               (+ now
                                                                                                  week))
                                                                           :kara)))))))
            (describe ":normalize"
                      (fn []
                        (it "returns empty for a nil persisted table"
                            (fn []
                              (assert.are.same {}
                                               (. (weekly-state.normalize nil
                                                                          now)
                                                  :lockouts))))
                        (it "round-trips a live persisted record"
                            (fn []
                              (let [persisted (weekly-state.to-db (weekly-state.mark-in-progress (weekly-state.empty)
                                                                                                 :kara
                                                                                                 now
                                                                                                 (+ now
                                                                                                    week)))
                                    back (weekly-state.normalize persisted now)]
                                (assert.is_true (weekly-state.in-progress? back
                                                                           :kara)))))
                        (it "prunes expired entries on load"
                            (fn []
                              (let [persisted (weekly-state.to-db (weekly-state.mark-in-progress (weekly-state.empty)
                                                                                                 :kara
                                                                                                 now
                                                                                                 (+ now
                                                                                                    10)))
                                    back (weekly-state.normalize persisted
                                                                 (+ now 20))]
                                (assert.are.same {} back.lockouts))))
                        (it "drops malformed entries without crashing"
                            (fn []
                              (let [corrupt {:lockouts {:kara {:in-progress? :yes}
                                                        :good {:in-progress? true
                                                               :entered-at now
                                                               :reset-at 0}}}
                                    back (weekly-state.normalize corrupt now)]
                                (assert.is_false (weekly-state.in-progress? back
                                                                            :kara))
                                (assert.is_true (weekly-state.in-progress? back
                                                                           :good)))))))
            (describe ":to-db"
                      (fn []
                        (it "returns a copy that does not alias the session"
                            (fn []
                              (let [s (weekly-state.mark-in-progress (weekly-state.empty)
                                                                     :kara now 0)
                                    db (weekly-state.to-db s)]
                                (tset db.lockouts :kara nil)
                                (assert.is_true (weekly-state.in-progress? s
                                                                           :kara)))))))))
