;; chains_spec.fnl -- the pure chain engine: frontier advance, follows gating,
;; quest seeding + backfill inference, persistence round-trip, immutability.

(local chains (require :src.domain.chains))
(local schemas (require :src.domain.schemas))
(local validate (require :src.domain.validate))

(fn step [overrides]
  "Build a valid ChainStep fixture; base fields overridden by `overrides`.
   Returns a fresh table so cases never share state."
  (collect [k v (pairs (or overrides {}))
            &into {:id :10
                   :type :quest
                   :label :step
                   :stage 10
                   :follows []
                   :follows-mode :all}]
    (values k v)))

(fn chain [steps overrides]
  "Build a valid ChainDef fixture around `steps`."
  (collect [k v (pairs (or overrides {}))
            &into {:id :test-chain
                   :name "Test Chain"
                   :kind :attunement
                   :expac "The Burning Crusade"
                   :faction :Both
                   : steps}]
    (values k v)))

;; Linear: quest 100 -> kill -> quest 200 -> end.
(fn linear-chain []
  (chain [(step {:id :10 :type :quest :quest-id 100 :stage 10})
          (step {:id :20 :type :kill :stage 20 :follows [:10]})
          (step {:id :30 :type :quest :quest-id 200 :stage 30 :follows [:20]})
          (step {:id :40 :type :end :stage 40 :follows [:30]})]))

;; Branch: a -> (b1 | b2 quests in parallel) -> c needs BOTH (:all).
(fn branch-chain [mode]
  (chain [(step {:id :a :type :quest :quest-id 1 :stage 10})
          (step {:id :b1 :type :quest :quest-id 2 :stage 20 :follows [:a]})
          (step {:id :b2 :type :quest :quest-id 3 :stage 20 :follows [:a]})
          (step {:id :c
                 :type :quest
                 :quest-id 4
                 :stage 30
                 :follows [:b1 :b2]
                 :follows-mode (or mode :all)})]))

(describe :chains
          (fn []
            (describe :registry
                      (fn []
                        (it "every generated ChainDef conforms to schemas.ChainDef"
                            (fn []
                              (each [_ c (ipairs (chains.all))]
                                (let [r (validate.check schemas.ChainDef c)]
                                  (assert.is_true r.ok
                                                  (.. c.id ": "
                                                      (table.concat (or r.errors
                                                                        [])
                                                                    "; ")))))))
                        (it "imports the TBC attunement set (karazhan present, all :attunement)"
                            (fn []
                              (let [kara (chains.by-id :karazhan)]
                                (assert.is_true (not= nil kara))
                                (assert.are.equal :Karazhan kara.name))
                              (each [_ c (ipairs (chains.all))]
                                (assert.are.equal :attunement c.kind))))
                        (it "by-id misses return nil; by-kind filters"
                            (fn []
                              (assert.is_nil (chains.by-id :no-such-chain))
                              (assert.are.equal 0
                                                (length (chains.by-kind :daily-circuit)))
                              (assert.is_true (> (length (chains.by-kind :attunement))
                                                 0))))))
            (describe :next-steps
                      (fn []
                        (it "advances deterministically as the completed set grows"
                            (fn []
                              (let [c (linear-chain)]
                                (var p (chains.empty-progress))
                                (assert.are.same [:10]
                                                 (icollect [_ s (ipairs (chains.next-steps c
                                                                                           p))]
                                                   s.id))
                                (set p (chains.mark-step p :10))
                                (assert.are.same [:20]
                                                 (icollect [_ s (ipairs (chains.next-steps c
                                                                                           p))]
                                                   s.id))
                                (set p (chains.mark-step p :20))
                                (assert.are.same [:30]
                                                 (icollect [_ s (ipairs (chains.next-steps c
                                                                                           p))]
                                                   s.id)))))
                        (it "circuit-steps keeps coord-carrying steps in stage order (Phase 9)"
                            (fn []
                              (let [chain {:id :lap
                                           :name :Lap
                                           :kind :custom
                                           :expac "The Burning Crusade"
                                           :steps [{:id :s2
                                                    :type :manual
                                                    :label :Second
                                                    :stage 2
                                                    :follows [:s1]
                                                    :follows-mode :all
                                                    :coord {:map-id 1946
                                                            :x 0.5
                                                            :y 0.6}}
                                                   {:id :s1
                                                    :type :manual
                                                    :label :First
                                                    :stage 1
                                                    :follows []
                                                    :follows-mode :all
                                                    :coord {:map-id 1946
                                                            :x 0.2
                                                            :y 0.3}}
                                                   {:id :s3
                                                    :type :manual
                                                    :label :Coordless
                                                    :stage 3
                                                    :follows [:s2]
                                                    :follows-mode :all}]}
                                    steps (chains.circuit-steps chain)]
                                (assert.are.equal 2 (length steps))
                                (assert.are.same [:s1 :s2]
                                                 (icollect [_ s (ipairs steps)]
                                                   s.id))
                                (assert.are.equal 0.2 (. steps 1 :coord :x)))))
                        (it "circuit-steps is empty for a coordless chain"
                            (fn []
                              (assert.are.same []
                                               (chains.circuit-steps (linear-chain)))))
                        (it "unmark-step clears exactly one id, fresh copy"
                            (fn []
                              (let [marked (chains.mark-step (chains.mark-step (chains.empty-progress)
                                                                               :10)
                                                             :20)
                                    cleared (chains.unmark-step marked :10)]
                                (assert.is_false (chains.step-completed? cleared
                                                                         :10))
                                (assert.is_true (chains.step-completed? cleared
                                                                        :20))
                                ;; the input progress is untouched
                                (assert.is_true (chains.step-completed? marked
                                                                        :10)))))
                        (it "exposes both branch arms at a branch"
                            (fn []
                              (let [c (branch-chain :all)
                                    p (chains.mark-step (chains.empty-progress)
                                                        :a)]
                                (assert.are.same [:b1 :b2]
                                                 (icollect [_ s (ipairs (chains.next-steps c
                                                                                           p))]
                                                   s.id)))))
                        (it ":all gating holds c back until both arms are done"
                            (fn []
                              (let [c (branch-chain :all)
                                    p (chains.mark-step (chains.mark-step (chains.empty-progress)
                                                                          :a)
                                                        :b1)]
                                (assert.are.same [:b2]
                                                 (icollect [_ s (ipairs (chains.next-steps c
                                                                                           p))]
                                                   s.id)))))
                        (it ":any gating opens c after one arm"
                            (fn []
                              (let [c (branch-chain :any)
                                    p (chains.mark-step (chains.mark-step (chains.empty-progress)
                                                                          :a)
                                                        :b1)]
                                (assert.are.same [:b2 :c]
                                                 (icollect [_ s (ipairs (chains.next-steps c
                                                                                           p))]
                                                   s.id)))))))
            (describe :current-step
                      (fn []
                        (it "picks the lowest-stage frontier step, nil when complete"
                            (fn []
                              (let [c (linear-chain)]
                                (assert.are.equal :10
                                                  (. (chains.current-step c
                                                                          (chains.empty-progress))
                                                     :id))
                                (var p (chains.empty-progress))
                                (each [_ id (ipairs [:10 :20 :30 :40])]
                                  (set p (chains.mark-step p id)))
                                (assert.is_nil (chains.current-step c p)))))))
            (describe :progress
                      (fn []
                        (it "counts done/total and a fraction in [0,1]"
                            (fn []
                              (let [c (linear-chain)
                                    p (chains.mark-step (chains.mark-step (chains.empty-progress)
                                                                          :10)
                                                        :20)
                                    s (chains.progress c p)]
                                (assert.are.equal 2 s.done)
                                (assert.are.equal 4 s.total)
                                (assert.are.equal 0.5 s.fraction))))
                        (it "steps-remaining and est-minutes-remaining derive from it"
                            (fn []
                              (let [c (linear-chain)
                                    p (chains.mark-step (chains.empty-progress)
                                                        :10)]
                                (assert.are.equal 3
                                                  (chains.steps-remaining c p))
                                (assert.are.equal 30
                                                  (chains.est-minutes-remaining c
                                                                                p
                                                                                10)))))))
            (describe :chain-complete?
                      (fn []
                        (it "is true once the :end step is recorded, false before"
                            (fn []
                              (let [c (linear-chain)]
                                (var p (chains.empty-progress))
                                (assert.is_false (chains.chain-complete? c p))
                                (each [_ id (ipairs [:10 :20 :30])]
                                  (set p (chains.mark-step p id)))
                                (assert.is_false (chains.chain-complete? c p))
                                (set p (chains.mark-step p :40))
                                (assert.is_true (chains.chain-complete? c p)))))))
            (describe :record-quest
                      (fn []
                        (it "marks the matching quest step"
                            (fn []
                              (let [c (linear-chain)
                                    p (chains.record-quest c
                                                           (chains.empty-progress)
                                                           100)]
                                (assert.is_true (chains.step-completed? p :10))
                                (assert.is_false (chains.step-completed? p :30)))))
                        (it "leaves progress unchanged for an untracked quest"
                            (fn []
                              (let [c (linear-chain)
                                    p (chains.record-quest c
                                                           (chains.empty-progress)
                                                           999)]
                                (assert.are.same {} p.completed))))
                        (it "kill + end steps infer from a later quest turn-in"
                            (fn []
                              (let [c (linear-chain)
                                    p (chains.record-quest c
                                                           (chains.record-quest c
                                                                                (chains.empty-progress)
                                                                                100)
                                                           200)]
                                (assert.is_true (chains.step-completed? p :20))
                                (assert.is_true (chains.step-completed? p :40))
                                (assert.is_true (chains.chain-complete? c p)))))
                        (it "does not mutate the input progress"
                            (fn []
                              (let [c (linear-chain)
                                    p0 (chains.empty-progress)]
                                (chains.record-quest c p0 100)
                                (assert.are.same {} p0.completed)))))))
          (describe :seed-from-completed
                    (fn []
                      (it "lights quest steps from the completed-quest set"
                          (fn []
                            (let [c (linear-chain)
                                  p (chains.seed-from-completed c {100 true})]
                              (assert.is_true (chains.step-completed? p :10))
                              (assert.is_false (chains.step-completed? p :30)))))
                      (it "backfills non-quest steps below the highest completed stage"
                          (fn []
                            (let [c (linear-chain)
                                  p (chains.seed-from-completed c
                                                                {100 true
                                                                 200 true})]
                              (assert.is_true (chains.step-completed? p :20))
                              (assert.is_true (chains.step-completed? p :40))
                              (assert.is_true (chains.chain-complete? c p)))))
                      (it "documents branch over-marking: a sibling arm backfills too"
                          (fn []
                            ;; b2 is a quest step, so it is NOT inferred -- but a non-quest
                            ;; sibling at a lower stage than a completed step would be. This
                            ;; is the accepted near-linear trade-off (module header).
                            (let [c (chain [(step {:id :a
                                                   :type :kill
                                                   :stage 10})
                                            (step {:id :b
                                                   :type :quest
                                                   :quest-id 7
                                                   :stage 20
                                                   :follows [:a]})])
                                  p (chains.seed-from-completed c {7 true})]
                              (assert.is_true (chains.step-completed? p :a)))))
                      (it "yields empty progress from an empty set"
                          (fn []
                            (let [c (linear-chain)
                                  p (chains.seed-from-completed c {})]
                              (assert.are.same {} p.completed))))))
          (describe :persistence
                    (fn []
                      (it "normalize drops malformed entries and survives nil"
                          (fn []
                            (assert.are.same {} (chains.normalize nil))
                            (assert.are.same {} (chains.normalize 42))
                            (let [m (chains.normalize {:karazhan {:completed {:10 true
                                                                              :20 1
                                                                              3 true}}
                                                       :bad :nope
                                                       5 {:completed {}}})]
                              (assert.are.same {:10 true}
                                               (. m :karazhan :completed))
                              (assert.are.same {:completed {}} m.bad)
                              (assert.is_nil (. m 5)))))
                      (it "to-db round-trips through normalize"
                          (fn []
                            (let [m {:karazhan {:completed {:10 true :20 true}}}
                                  db (chains.to-db m)]
                              (assert.are.same m (chains.normalize db)))))
                      (it "to-db copies never alias the live session"
                          (fn []
                            (let [m {:karazhan {:completed {:10 true}}}
                                  db (chains.to-db m)]
                              (tset (. db :karazhan :completed) :10 nil)
                              (assert.are.same {:10 true}
                                               (. m :karazhan :completed)))))))
          (describe :properties
                    (fn []
                      (it "frontier steps always have satisfied prerequisites (generated data)"
                          (fn []
                            (each [_ c (ipairs (chains.all))]
                              (var p (chains.empty-progress))
                              ;; walk every chain to completion via its frontier; this also
                              ;; proves no generated chain deadlocks (a follows-id pointing
                              ;; at a missing step would stall the frontier).
                              (var guard 0)
                              (while (and (not (chains.chain-complete? c p))
                                          (< guard 200))
                                (let [steps (chains.next-steps c p)]
                                  (assert.is_true (> (length steps) 0)
                                                  (.. c.id " deadlocked"))
                                  (each [_ s (ipairs steps)]
                                    (set p (chains.mark-step p s.id)))
                                  (set guard (+ guard 1))))
                              (assert.is_true (chains.chain-complete? c p)
                                              (.. c.id " did not complete"))))))))
