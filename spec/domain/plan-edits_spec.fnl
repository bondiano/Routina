;; plan-edits_spec.fnl -- tests for the pin/skip plan-shaping state:
;; defensive normalize, SavedVariables round-trip, and the pure transforms
;; (including the pin/skip mutual exclusion). Pure fixtures only.

(local plan-edits (require :src.domain.plan-edits))

(describe :plan-edits
          (fn []
            (describe :normalize
                      (fn []
                        (it "returns empty edits for nil / non-table input"
                            (fn []
                              (assert.are.same {:pins [] :skips {}}
                                               (plan-edits.normalize nil))
                              (assert.are.same {:pins [] :skips {}}
                                               (plan-edits.normalize :junk))))
                        (it "keeps valid ids, dropping garbage and dup pins"
                            (fn []
                              (let [out (plan-edits.normalize {:pins [:karazhan
                                                                      42
                                                                      :karazhan
                                                                      :vendor]
                                                               :skips {:gruuls-lair true
                                                                       :bad 1
                                                                       5 true}})]
                                (assert.are.same [:karazhan :vendor] out.pins)
                                (assert.are.same {:gruuls-lair true} out.skips))))
                        (it "resolves a pinned-and-skipped id toward the skip"
                            (fn []
                              (let [out (plan-edits.normalize {:pins [:karazhan]
                                                               :skips {:karazhan true}})]
                                (assert.are.same [] out.pins)
                                (assert.is_true (plan-edits.skipped? out
                                                                     :karazhan)))))
                        (it "round-trips through to-db without aliasing"
                            (fn []
                              (let [live (plan-edits.normalize {:pins [:vendor]
                                                                :skips {:quest true}})
                                    persisted (plan-edits.to-db live)]
                                (assert.are.same live persisted)
                                (assert.is_false (rawequal live.pins
                                                           persisted.pins)))))))
            (describe "pin / unpin / move-pin"
                      (fn []
                        (it "pins append in order and never duplicate"
                            (fn []
                              (let [e (-> (plan-edits.empty)
                                          (plan-edits.pin :karazhan)
                                          (plan-edits.pin :vendor)
                                          (plan-edits.pin :karazhan))]
                                (assert.are.same [:karazhan :vendor] e.pins)
                                (assert.are.equal 1
                                                  (plan-edits.pin-rank e
                                                                       :karazhan))
                                (assert.are.equal 2
                                                  (plan-edits.pin-rank e
                                                                       :vendor)))))
                        (it "pinning clears a skip (mutually exclusive)"
                            (fn []
                              (let [e (-> (plan-edits.empty)
                                          (plan-edits.skip :karazhan)
                                          (plan-edits.pin :karazhan))]
                                (assert.is_true (plan-edits.pinned? e :karazhan))
                                (assert.is_false (plan-edits.skipped? e
                                                                      :karazhan)))))
                        (it "unpin removes only the named id"
                            (fn []
                              (let [e (-> (plan-edits.empty)
                                          (plan-edits.pin :a)
                                          (plan-edits.pin :b)
                                          (plan-edits.unpin :a))]
                                (assert.are.same [:b] e.pins))))
                        (it "move-pin swaps within the order and clamps at ends"
                            (fn []
                              (let [base (-> (plan-edits.empty)
                                             (plan-edits.pin :a)
                                             (plan-edits.pin :b)
                                             (plan-edits.pin :c))
                                    up (plan-edits.move-pin base :c -1)
                                    top (plan-edits.move-pin base :a -1)
                                    bottom (plan-edits.move-pin base :c 1)]
                                (assert.are.same [:a :c :b] up.pins)
                                (assert.are.same [:a :b :c] top.pins)
                                (assert.are.same [:a :b :c] bottom.pins))))
                        (it "transforms never mutate their input"
                            (fn []
                              (let [base (plan-edits.pin (plan-edits.empty) :a)
                                    _ (plan-edits.pin base :b)
                                    _ (plan-edits.skip base :a)
                                    _ (plan-edits.move-pin base :a 1)]
                                (assert.are.same [:a] base.pins)
                                (assert.are.same {} base.skips))))))
            (describe "skip / unskip"
                      (fn []
                        (it "skip excludes and unpins; unskip restores"
                            (fn []
                              (let [pinned (plan-edits.pin (plan-edits.empty)
                                                           :karazhan)
                                    skipped (plan-edits.skip pinned :karazhan)
                                    restored (plan-edits.unskip skipped
                                                                :karazhan)]
                                (assert.is_true (plan-edits.skipped? skipped
                                                                     :karazhan))
                                (assert.is_false (plan-edits.pinned? skipped
                                                                     :karazhan))
                                (assert.is_false (plan-edits.skipped? restored
                                                                      :karazhan))
                                (assert.is_false (plan-edits.pinned? restored
                                                                     :karazhan)))))))))
