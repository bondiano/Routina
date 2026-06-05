;; custom-chains_spec.fnl -- tests for the player-authored chain constructor:
;; defensive normalize, editor parsing, the ChainDef projection, and the
;; Phase 8 exit criterion -- a custom chain advances through chains.fnl
;; IDENTICALLY to an imported one (shared, parametric spec).

(local custom-chains (require :src.domain.custom-chains))
(local chains (require :src.domain.chains))
(local schemas (require :src.domain.schemas))
(local validate (require :src.domain.validate))

(fn farm-chain [over]
  "A valid authored chain fixture, shallow-overridable."
  (let [base {:id :chain-1
              :name "Primal farm circuit"
              :steps [{:label "Clear the western camps"}
                      {:label "Loop the lake motes"}
                      {:label "Sell and restock"}]}]
    (each [k v (pairs (or over {}))]
      (tset base k v))
    base))

(describe :custom-chains
          (fn []
            (describe :normalize
                      (fn []
                        (it "returns [] for nil / non-table input"
                            (fn []
                              (assert.are.same [] (custom-chains.normalize nil))
                              (assert.are.same []
                                               (custom-chains.normalize :junk))))
                        (it "keeps valid chains and drops corrupt rows"
                            (fn []
                              (let [out (custom-chains.normalize [(farm-chain {})
                                                                  {:id :bad
                                                                   :name "No steps"
                                                                   :steps []}
                                                                  {:id :blank
                                                                   :name "  "
                                                                   :steps [{:label :x}]}
                                                                  :garbage])]
                                (assert.are.equal 1 (length out))
                                (assert.are.equal :chain-1 (. out 1 :id)))))
                        (it "drops a chain with a blank step label"
                            (fn []
                              (assert.are.same []
                                               (custom-chains.normalize [(farm-chain {:steps [{:label :ok}
                                                                                              {:label "  "}]})]))))
                        (it "round-trips through to-db without aliasing"
                            (fn []
                              (let [live (custom-chains.normalize [(farm-chain {})])
                                    persisted (custom-chains.to-db live)]
                                (assert.are.same live
                                                 (custom-chains.normalize persisted))
                                (assert.is_false (rawequal (. live 1)
                                                           (. persisted 1))))))))
            (describe :parse-steps
                      (fn []
                        (it "parses one trimmed step per non-blank line" (fn []
                                                                           (assert.are.same [{:label "Kill the boss"}
                                                                                             {:label "Loot the chest"}]
                                                                                            (custom-chains.parse-steps "  Kill the boss  

   
Loot the chest
"))))
                        (it "is empty for nil / blank text" (fn []
                                                              (assert.are.same []
                                                                               (custom-chains.parse-steps nil))
                                                              (assert.are.same []
                                                                               (custom-chains.parse-steps "
  "))))
                        (it "parses the optional `@ map x y` waypoint tail (Phase 9)"
                            (fn []
                              (let [[a b] (custom-chains.parse-steps "Lake motes @ 1946 52.5 64
No waypoint here")]
                                (assert.are.equal "Lake motes" a.label)
                                (assert.are.same {:map-id 1946
                                                  :x 0.525
                                                  :y 0.64}
                                                 a.coord)
                                (assert.are.equal "No waypoint here" b.label)
                                (assert.is_nil b.coord))))
                        (it "accepts the 0 and 100 percent edges"
                            (fn []
                              (let [[s] (custom-chains.parse-steps "Corner @ 1944 0 100")]
                                (assert.are.equal 0 s.coord.x)
                                (assert.are.equal 1 s.coord.y))))
                        (it "keeps a malformed @-tail as part of the label"
                            (fn []
                              (let [steps (custom-chains.parse-steps "Meet @ the inn
Out of range @ 1946 250 50
Bare tail @ 1946 12")]
                                (assert.are.equal 3 (length steps))
                                (each [_ s (ipairs steps)]
                                  (assert.is_nil s.coord))
                                (assert.are.equal "Meet @ the inn"
                                                  (. steps 1 :label)))))
                        (it "round-trips coords through normalize and to-chain-def"
                            (fn []
                              (let [draft {:id :chain-7
                                           :name "Coord lap"
                                           :steps (custom-chains.parse-steps "A @ 1946 20 30
B")}
                                    [live] (custom-chains.normalize [draft])
                                    def (custom-chains.to-chain-def live)]
                                (assert.are.same {:map-id 1946 :x 0.2 :y 0.3}
                                                 (. def.steps 1 :coord))
                                (assert.is_nil (. def.steps 2 :coord)))))))
            (describe :next-id
                      (fn []
                        (it "starts at chain-1 and climbs past the top id"
                            (fn []
                              (assert.are.equal :chain-1
                                                (custom-chains.next-id []))
                              (assert.are.equal :chain-5
                                                (custom-chains.next-id [{:id :chain-4}
                                                                        {:id :chain-2}]))))))
            (describe :to-chain-def
                      (fn []
                        (it "produces a schema-valid linear :custom ChainDef"
                            (fn []
                              (let [def (custom-chains.to-chain-def (farm-chain {}))
                                    r (validate.check schemas.ChainDef def)]
                                (assert.is_true r.ok)
                                (assert.are.equal :custom def.kind)
                                (assert.are.equal 3 (length def.steps))
                                (assert.are.equal :manual (. def.steps 2 :type))
                                (assert.are.same [] (. def.steps 1 :follows))
                                (assert.are.same [:s1] (. def.steps 2 :follows))
                                (assert.are.equal 2 (. def.steps 2 :stage))
                                (assert.is_nil (. def.steps 1 :quest-id)))))
                        (it "is never seeded by the quest log (no quest-ids)"
                            (fn []
                              (let [def (custom-chains.to-chain-def (farm-chain {}))
                                    seeded (chains.seed-from-completed def
                                                                       {9837 true
                                                                        10901 true})]
                                (assert.is_nil (next seeded.completed)))))))
            ;; --- Phase 8 §3 exit criterion: shared advancement spec ----------
            ;;
            ;; The same assertions run over an IMPORTED registry chain and a
            ;; CONSTRUCTED custom one: chains.fnl must not care about
            ;; provenance.
            (describe "shared advancement (imported vs constructed)"
                      (fn []
                        (local imported (chains.by-id :karazhan))
                        (local constructed
                               (custom-chains.to-chain-def (farm-chain {})))

                        (fn mark-all [chain]
                          (accumulate [p (chains.empty-progress) _ s (ipairs chain.steps)]
                            (chains.mark-step p s.id)))

                        (each [_ [label chain] (ipairs [[:imported imported]
                                                        [:constructed
                                                         constructed]])]
                          (it (.. "advances the " (tostring label)
                                  " chain step by step")
                              (fn []
                                (assert.is_not_nil chain)
                                (let [fresh (chains.empty-progress)
                                      first-step (chains.current-step chain
                                                                      fresh)
                                      after (chains.mark-step fresh
                                                              first-step.id)
                                      second-step (chains.current-step chain
                                                                       after)]
                                  ;; a fresh chain starts incomplete at a
                                  ;; real frontier step
                                  (assert.is_false (chains.chain-complete? chain
                                                                           fresh))
                                  (assert.are.equal (length chain.steps)
                                                    (chains.steps-remaining chain
                                                                            fresh))
                                  (assert.is_not_nil first-step)
                                  ;; marking the frontier advances it
                                  (assert.is_true (chains.step-completed? after
                                                                          first-step.id))
                                  (assert.is_not_nil second-step)
                                  (assert.is_false (= first-step.id
                                                      second-step.id))
                                  (assert.is_true (> (. (chains.progress chain
                                                                         after)
                                                        :fraction)
                                                     0))
                                  ;; unmark restores the original frontier
                                  (let [back (chains.unmark-step after
                                                                 first-step.id)]
                                    (assert.are.equal first-step.id
                                                      (. (chains.current-step chain
                                                                              back)
                                                         :id))))))
                          (it (.. "completes the " (tostring label)
                                  " chain when every step is marked")
                              (fn []
                                (let [done (mark-all chain)]
                                  (assert.is_true (chains.chain-complete? chain
                                                                          done))
                                  (assert.are.equal 0
                                                    (chains.steps-remaining chain
                                                                            done))
                                  (assert.is_nil (chains.current-step chain
                                                                      done))
                                  (assert.are.equal 1
                                                    (. (chains.progress chain
                                                                        done)
                                                       :fraction))))))))))
