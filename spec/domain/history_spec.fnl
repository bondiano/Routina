;; history_spec.fnl -- tests for the pure cumulative luck-history model.
;;
;; Pure module: no WoW API, no clock. Covers immutability (inputs never mutated),
;; key stringification, the runs>=drops clamp in luck, and the defensive
;; normalize over corrupt SavedVariables.

(local history (require :src.domain.history))
(local chance (require :src.domain.drop-chance))

(describe :history
          (fn []
            (describe ":empty"
                      (fn []
                        (it "has empty runs and drops"
                            (fn []
                              (let [h (history.empty)]
                                (assert.are.same {} h.runs)
                                (assert.are.same {} h.drops))))))
            (describe ":record-run / :runs-for"
                      (fn []
                        (it "accumulates runs and stringifies the key"
                            (fn []
                              (let [h (-> (history.empty)
                                          (history.record-run :karazhan)
                                          (history.record-run :karazhan))]
                                (assert.are.equal 2
                                                  (history.runs-for h :karazhan))
                                ;; stored under the stringified id
                                (assert.are.equal 2 (. h.runs :karazhan)))))
                        (it "is 0 for an unseen activity"
                            (fn []
                              (assert.are.equal 0
                                                (history.runs-for (history.empty)
                                                                  :gruul))))
                        (it "does not mutate the input"
                            (fn []
                              (let [h0 (history.empty)]
                                (history.record-run h0 :karazhan)
                                (assert.are.same {} h0.runs))))))
            (describe ":record-drop / :drops-for"
                      (fn []
                        (it "accumulates drops, stringifying a numeric item id"
                            (fn []
                              (let [h (-> (history.empty)
                                          (history.record-drop 28545)
                                          (history.record-drop 28545)
                                          (history.record-drop 28545))]
                                (assert.are.equal 3 (history.drops-for h 28545))
                                (assert.are.equal 3 (. h.drops :28545)))))
                        (it "leaves runs untouched when recording a drop"
                            (fn []
                              (let [h (-> (history.empty)
                                          (history.record-run :karazhan)
                                          (history.record-drop 28545))]
                                (assert.are.equal 1
                                                  (history.runs-for h :karazhan))
                                (assert.are.equal 1 (history.drops-for h 28545)))))))
            (describe ":luck"
                      (fn []
                        (it "feeds observed counts into bayesian-luck"
                            (fn []
                              (let [h (-> (history.empty)
                                          (history.record-run :karazhan)
                                          (history.record-run :karazhan)
                                          (history.record-drop 28545))
                                    r (history.luck h 28545 :karazhan 0.16)
                                    expect (chance.bayesian-luck 1 2 0.16)]
                                (assert.are.equal expect.posterior-mean
                                                  r.posterior-mean)
                                (assert.are.equal 2 r.n))))
                        (it "clamps drops to runs so runs>=drops holds"
                            (fn []
                              ;; a drop logged with no recorded run must not throw
                              (let [h (history.record-drop (history.empty)
                                                           28545)]
                                (assert.has_no.errors #(history.luck h 28545
                                                                     :karazhan
                                                                     0.16)))))))
            (describe ":normalize"
                      (fn []
                        (it "returns empty for a nil persisted table"
                            (fn []
                              (let [h (history.normalize nil)]
                                (assert.are.same {} h.runs)
                                (assert.are.same {} h.drops))))
                        (it "drops malformed entries without crashing"
                            (fn []
                              (let [h (history.normalize {:runs {:karazhan 3
                                                                 :bad -1
                                                                 :frac 2.5}
                                                          :drops {:28545 :lots}})]
                                (assert.are.equal 3 (. h.runs :karazhan))
                                (assert.is_nil (. h.runs :bad))
                                (assert.is_nil (. h.runs :frac))
                                (assert.is_nil (. h.drops :28545)))))))
            (describe ":to-db"
                      (fn []
                        (it "returns a copy that does not alias the session"
                            (fn []
                              (let [h (history.record-run (history.empty)
                                                          :karazhan)
                                    db (history.to-db h)]
                                (tset db.runs :karazhan nil)
                                (assert.are.equal 1
                                                  (history.runs-for h :karazhan)))))))))
