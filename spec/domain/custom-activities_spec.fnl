;; custom-activities_spec.fnl -- tests for the player-authored activity model:
;; defensive normalize, SavedVariables round-trip, and the projections into
;; ActivityDef / ActivityYield. Pure fixtures only.

(local custom-activities (require :src.domain.custom-activities))
(local schemas (require :src.domain.schemas))
(local validate (require :src.domain.validate))

(fn lap [over]
  "A valid authored entry (a gold farm lap), shallow-overridable."
  (let [base {:id :custom-1
              :name "Primal farm lap"
              :est-minutes 45
              :reset :daily
              :gold-min 200000
              :gold-max 600000}]
    (each [k v (pairs (or over {}))]
      (tset base k v))
    base))

(fn errand [over]
  "A valid authored entry with no yields (a weekly errand) -- the fixture for
   nil-field cases a table-literal override cannot express."
  (let [base {:id :custom-2
              :name "Weekly errand"
              :est-minutes 20
              :reset :weekly}]
    (each [k v (pairs (or over {}))]
      (tset base k v))
    base))

(describe :custom-activities
          (fn []
            (describe :normalize
                      (fn []
                        (it "returns [] for nil / non-table input"
                            (fn []
                              (assert.are.same []
                                               (custom-activities.normalize nil))
                              (assert.are.same []
                                               (custom-activities.normalize :junk))))
                        (it "keeps valid entries and drops corrupt rows"
                            (fn []
                              (let [out (custom-activities.normalize [(lap {})
                                                                      {:id :bad
                                                                       :name "No length"
                                                                       :reset :weekly}
                                                                      :garbage
                                                                      {:no :fields}])]
                                (assert.are.equal 1 (length out))
                                (assert.are.equal :custom-1 (. out 1 :id)))))
                        (it "drops a non-positive length estimate"
                            (fn []
                              (assert.are.same []
                                               (custom-activities.normalize [(lap {:est-minutes 0})]))))
                        (it "drops a half-authored or inverted gold band"
                            (fn []
                              (assert.are.same []
                                               (custom-activities.normalize [(errand {:gold-min 100})]))
                              (assert.are.same []
                                               (custom-activities.normalize [(lap {:gold-min 500
                                                                                   :gold-max 100})]))))
                        (it "drops a half-authored rep pair"
                            (fn []
                              (assert.are.same []
                                               (custom-activities.normalize [(errand {:rep-faction :ogrila})]))
                              (assert.are.same []
                                               (custom-activities.normalize [(errand {:rep-amount 250})]))))
                        (it "returns fresh copies, never aliasing the input"
                            (fn []
                              (let [c (lap {})
                                    out (custom-activities.normalize [c])]
                                (assert.is_false (rawequal c (. out 1))))))))
            (describe :to-db
                      (fn []
                        (it "round-trips through normalize unchanged"
                            (fn []
                              (let [live (custom-activities.normalize [(lap {})])
                                    persisted (custom-activities.to-db live)
                                    again (custom-activities.normalize persisted)]
                                (assert.are.same live again)
                                (assert.is_false (rawequal (. live 1)
                                                           (. persisted 1))))))))
            (describe :to-activity-def
                      (fn []
                        (it "produces a schema-valid :custom ActivityDef"
                            (fn []
                              (let [adef (custom-activities.to-activity-def (lap {:goal-id :g1}))
                                    r (validate.check schemas.ActivityDef adef)]
                                (assert.is_true r.ok)
                                (assert.are.equal :custom adef.type)
                                (assert.are.equal :custom-1 adef.id)
                                (assert.are.equal 45 adef.length-estimate)
                                (assert.are.equal :daily adef.reset)
                                (assert.are.equal :g1 adef.goal-id)
                                (assert.are.equal 1 adef.requirements.min-level)
                                (assert.is_nil adef.group-size))))))
            (describe :to-yield
                      (fn []
                        (it "is nil when the entry claims nothing"
                            (fn []
                              (assert.is_nil (custom-activities.to-yield (errand {})))))
                        (it "produces a schema-valid ActivityYield"
                            (fn []
                              (let [y (custom-activities.to-yield (lap {:badges 3
                                                                        :rep-faction :ogrila
                                                                        :rep-amount 250}))
                                    r (validate.check schemas.ActivityYield y)]
                                (assert.is_true r.ok)
                                (assert.are.equal :custom-1 y.activity-id)
                                (assert.are.equal 3 y.badges)
                                (assert.are.equal 200000 y.gold-min)
                                (assert.are.equal 600000 y.gold-max)
                                (assert.are.equal :ogrila y.rep.faction)
                                (assert.are.equal 250 y.rep.amount))))
                        (it "zero-fills the unauthored halves"
                            (fn []
                              (let [y (custom-activities.to-yield (errand {:badges 2}))]
                                (assert.are.equal 0 y.gold-min)
                                (assert.are.equal 0 y.gold-max)
                                (assert.is_nil y.rep))))))))
