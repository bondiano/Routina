;; ctx_spec.fnl -- tests for the pure raw-snapshot -> (player, ctx) assembler.
;;
;; Pure module: no WoW API, no mocks. The two impure lookups are injected as
;; plain closures, so every mapping (spec detection, owned set, attunement /
;; reputation resolution, lockout projection, options pass-through) is exercised
;; with fakes and the schema-validated output is asserted directly.

(local ctx (require :src.domain.ctx))
(local chains (require :src.domain.chains))

(fn complete-progress [chain-id]
  "A ChainProgress with every step of the registry chain marked complete."
  (let [chain (chains.by-id chain-id)]
    {:completed (collect [_ s (ipairs chain.steps)] s.id true)}))

(fn snapshot [overrides]
  "A valid raw snapshot fixture (feral druid, nothing owned), overridable."
  (collect [k v (pairs (or overrides {}))
            &into {:class :druid
                   :level 70
                   :now 1000
                   :talent-points [0 61 0]
                   :owned-item-ids []
                   :raw-lockouts []
                   :owner :Main-Realm
                   :quest-completed? #false
                   :faction-standing (fn [_] nil)
                   :options {}}]
    (values k v)))

(fn kara-lockout [overrides]
  (collect [k v (pairs (or overrides {}))
            &into {:name :Karazhan
                   :instance-id 1
                   :reset-at 5000
                   :difficulty :normal
                   :is-raid? true
                   :encounters [{:name :Attumen :killed? true}
                                {:name :Moroes :killed? false}]}]
    (values k v)))

(describe :ctx (fn []
                 (describe "spec detection"
                           (fn []
                             (it "maps the dominant talent tree to a catalog spec"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:talent-points [0
                                                                                 61
                                                                                 0]}))]
                                     (assert.are.equal :feral-dps r.ctx.spec))))
                             (it "breaks talent ties toward the lower tab"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:talent-points [30
                                                                                 30
                                                                                 0]}))]
                                     ;; druid tab 1 = balance
                                     (assert.are.equal :balance r.ctx.spec))))
                             (it "defaults an untalented character to the first tab"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:talent-points [0
                                                                                 0
                                                                                 0]}))]
                                     (assert.are.equal :balance r.ctx.spec))))
                             (it "lets options.spec override the detected spec"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:talent-points [0
                                                                                 61
                                                                                 0]
                                                                 :options {:spec :restoration}}))]
                                     (assert.are.equal :restoration r.ctx.spec))))))
                 (describe :owned-items
                           (fn []
                             (it "builds a set, deduping and dropping nil/empty slots"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:owned-item-ids [100
                                                                                  100
                                                                                  0
                                                                                  200]}))]
                                     (assert.is_true (. r.ctx.owned-items 100))
                                     (assert.is_true (. r.ctx.owned-items 200))
                                     (assert.is_nil (. r.ctx.owned-items 0)))))))
                 (describe :attunements
                           (fn []
                             (it "assumes held while gating is disabled (removed-in-TBC)"
                                 (fn []
                                   ;; every attune-quests entry is :gate? false
                                   ;; (raid entry reqs were removed in 2.3/2.4),
                                   ;; so the quest predicate is never consulted --
                                   ;; even a never-completed one yields attuned
                                   (let [r (ctx.build (snapshot {:quest-completed? #false}))]
                                     (assert.is_true (. r.player.attunements
                                                        :kara-key))
                                     (assert.is_true (. r.player.attunements
                                                        :ssc-attune))
                                     (assert.is_true (. r.player.attunements
                                                        :bt-medallion)))))
                             (it "gate flips from chain completion (quest flag never set)"
                                 (fn []
                                   (let [opts {:attune {:kara-key {:gate? true}}}
                                         held (ctx.build (snapshot {:quest-completed? #false
                                                                    :options opts
                                                                    :chain-progress {:karazhan (complete-progress :karazhan)}}))
                                         missing (ctx.build (snapshot {:quest-completed? #false
                                                                       :options opts}))]
                                     (assert.is_true (. held.player.attunements
                                                        :kara-key))
                                     (assert.is_nil (. missing.player.attunements
                                                       :kara-key)))))
                             (it "legacy proof-quest flag still attunes without chain progress"
                                 (fn []
                                   (let [opts {:attune {:kara-key {:gate? true}}}
                                         r (ctx.build (snapshot {:quest-completed? #(= $
                                                                                       9837)
                                                                 :options opts}))]
                                     (assert.is_true (. r.player.attunements
                                                        :kara-key)))))
                             (it "incomplete chain progress alone does not attune a gated slug"
                                 (fn []
                                   (let [opts {:attune {:kara-key {:gate? true}}}
                                         halfway {:karazhan {:completed {:10 true}}}
                                         r (ctx.build (snapshot {:quest-completed? #false
                                                                 :options opts
                                                                 :chain-progress halfway}))]
                                     (assert.is_nil (. r.player.attunements
                                                       :kara-key)))))
                             (it "manual gate?-off override wins over everything"
                                 (fn []
                                   ;; gating disabled -> held, regardless of
                                   ;; chain progress or quest flags
                                   (let [r (ctx.build (snapshot {:quest-completed? #false
                                                                 :options {:attune {:kara-key {:gate? false}}}
                                                                 :chain-progress {}}))]
                                     (assert.is_true (. r.player.attunements
                                                        :kara-key)))))))
                 (describe :advice
                           (fn []
                             (it "advises the Karazhan key when not completed"
                                 (fn []
                                   ;; kara-key :advise? true, quest 9837 not done
                                   (let [r (ctx.build (snapshot {:quest-completed? #false}))]
                                     (assert.is_not_nil (. r.advice :kara-key))
                                     ;; removed attunements never advise
                                     (assert.is_nil (. r.advice :ssc-attune)))))
                             (it "drops the advisory once the key quest is done"
                                 (fn []
                                   (let [done #(= $ 9837)
                                         r (ctx.build (snapshot {:quest-completed? done}))]
                                     (assert.is_nil (. r.advice :kara-key)))))
                             (it "honors an options override that disables advising"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:quest-completed? #false
                                                                 :options {:attune {:kara-key {:advise? false}}}}))]
                                     (assert.is_nil (. r.advice :kara-key)))))
                             (it "drops the advisory once the chain is complete"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:quest-completed? #false
                                                                 :chain-progress {:karazhan (complete-progress :karazhan)}}))]
                                     (assert.is_nil (. r.advice :kara-key)))))))
                 (describe :chain-advice
                           (fn []
                             (it "lists a started, incomplete chain with its next step"
                                 (fn []
                                   ;; kara step "30" (quest 9824) done -> the
                                   ;; chain is mid-way; the frontier moves on
                                   (let [started {:karazhan {:completed {:30 true}}}
                                         r (ctx.build (snapshot {:chain-progress started}))
                                         rows r.chain-advice]
                                     (assert.are.equal 1 (length rows))
                                     (let [row (. rows 1)]
                                       (assert.are.equal :karazhan row.chain-id)
                                       (assert.are.equal :Karazhan row.name)
                                       (assert.is_truthy row.next-step-label)
                                       (assert.is_true (> row.done 0))
                                       (assert.is_true (< row.done row.total))
                                       (assert.is_true (> row.est-minutes 0))))))
                             (it "stays silent for unstarted, complete and absent progress"
                                 (fn []
                                   (let [none (ctx.build (snapshot {}))
                                         empty (ctx.build (snapshot {:chain-progress {}}))
                                         finished (ctx.build (snapshot {:chain-progress {:karazhan (complete-progress :karazhan)}}))]
                                     (assert.are.same [] none.chain-advice)
                                     (assert.are.same [] empty.chain-advice)
                                     (assert.are.same [] finished.chain-advice))))
                             (it "orders multiple chains closest-to-done first (deterministic)"
                                 (fn []
                                   ;; shadow-labyrinth has 3 steps, so one
                                   ;; completed step (1/3) outranks karazhan's
                                   ;; single step out of twelve
                                   (let [progress {:karazhan {:completed {:30 true}}
                                                   :shadow-labyrinth {:completed {:10 true}}}
                                         r (ctx.build (snapshot {:chain-progress progress}))
                                         rows r.chain-advice]
                                     (assert.are.equal 2 (length rows))
                                     (assert.is_true (>= (. rows 1 :fraction)
                                                         (. rows 2 :fraction))))))))
                 (describe :reputations
                           (fn []
                             (it "resolves a tracked faction's standing"
                                 (fn []
                                   (let [standing #(if (= $ 1038) 6 nil)
                                         r (ctx.build (snapshot {:faction-standing standing}))]
                                     (assert.are.equal :honored
                                                       r.player.reputations.ogrila))))
                             (it "omits a faction the lookup cannot resolve"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:faction-standing (fn [_]
                                                                                     nil)}))]
                                     (assert.is_nil r.player.reputations.ogrila))))))
                 (describe :lockouts
                           (fn []
                             (it "projects a raw lockout onto its activity id"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:raw-lockouts [(kara-lockout {})]}))
                                         lv (. r.ctx.lockouts :karazhan)]
                                     (assert.is_not_nil lv)
                                     (assert.are.equal 5000 lv.expiry)
                                     (assert.are.equal 1 lv.bosses-killed)
                                     (assert.are.equal 2 lv.bosses-total)
                                     (assert.are.equal :Main-Realm lv.owner))))
                             (it "drops an unmapped instance"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:raw-lockouts [(kara-lockout {:name "Some Heroic"})]}))]
                                     (assert.is_nil (next r.ctx.lockouts)))))))
                 (describe "options pass-through + validation"
                           (fn []
                             (it "carries phase, weights and competitors from options"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:options {:phase 2
                                                                           :weights {:feet 5}
                                                                           :competitors {:karazhan 3}}}))]
                                     (assert.are.equal 2 r.ctx.phase)
                                     (assert.are.equal 5
                                                       (. r.ctx.weights :feet))
                                     (assert.are.equal 3
                                                       (. r.ctx.competitors
                                                          :karazhan)))))
                             (it "carries the global default-competitors"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:options {:default-competitors 4}}))]
                                     (assert.are.equal 4
                                                       r.ctx.default-competitors))))
                             (it "carries the raid composition from options"
                                 (fn []
                                   (let [comp {:tank 3
                                               :healer 6
                                               :melee 7
                                               :ranged 4
                                               :caster 5}
                                         r (ctx.build (snapshot {:options {:composition comp}}))]
                                     (assert.are.same comp r.ctx.composition))))
                             (it "carries the projection seed from options"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:options {:seed 1234}}))]
                                     (assert.are.equal 1234 r.ctx.seed))))
                             (it "carries the include-classic flag from options"
                                 (fn []
                                   (let [r (ctx.build (snapshot {:options {:include-classic? true}}))]
                                     (assert.is_true r.ctx.include-classic?))))
                             (it "defaults the phase when options omit it"
                                 (fn []
                                   (let [r (ctx.build (snapshot {}))]
                                     (assert.are.equal 2 r.ctx.phase))))
                             (it "rejects a snapshot that yields an invalid player"
                                 (fn []
                                   (assert.has_error #(ctx.build (snapshot {:level :seventy})))))
                             (it "does not mutate the snapshot"
                                 (fn []
                                   (let [s (snapshot {})
                                         _ (ctx.build s)]
                                     (assert.is_nil s.player)
                                     (assert.is_nil s.ctx))))))))
