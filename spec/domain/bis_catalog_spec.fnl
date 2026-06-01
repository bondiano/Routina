;; bis_catalog_spec.fnl -- tests for the aggregated BiS catalog.
;;
;; The catalog data is generated (scripts/import-bis.lua) from the vendored GPL
;; source, so these tests are structural: every entry conforms to schemas.BisItem,
;; the per-spec modules all aggregate, queries filter correctly, and the join did
;; not produce duplicates. No WoW API, no clock.

(local catalog (require :src.domain.bis-catalog))
(local validate (require :src.domain.validate))
(local schemas (require :src.domain.schemas))

(local all-classes [:warrior
                    :paladin
                    :hunter
                    :rogue
                    :priest
                    :shaman
                    :mage
                    :warlock
                    :druid])

(fn count [seq] (length seq))

(describe :bis-catalog
          (fn []
            (describe "registry integrity"
                      (fn []
                        (it "validates every entry against schemas.BisItem"
                            (fn []
                              (each [_ e (ipairs (catalog.all))]
                                (let [r (validate.check schemas.BisItem e)]
                                  (assert.is_true r.ok
                                                  (.. "invalid entry "
                                                      (tostring (?. e :item :id))
                                                      ": "
                                                      (table.concat (or r.errors
                                                                        [])
                                                                    "; ")))))))
                        (it "is non-empty and covers all nine classes"
                            (fn []
                              (let [seen {}]
                                (each [_ e (ipairs (catalog.all))]
                                  (tset seen e.class true))
                                (assert.is_true (> (count (catalog.all)) 700))
                                (each [_ c (ipairs all-classes)]
                                  (assert.is_true (. seen c)
                                                  (.. "missing class "
                                                      (tostring c)))))))
                        (it "flattens losslessly: all == sum of per-spec slices"
                            (fn []
                              (let [pairs-seen {}]
                                (each [_ e (ipairs (catalog.all))]
                                  (let [k (.. (tostring e.class) "/"
                                              (tostring e.spec))]
                                    (when (not (. pairs-seen k))
                                      (tset pairs-seen k [e.class e.spec]))))
                                (var sum 0)
                                (each [_ pair (pairs pairs-seen)]
                                  (set sum
                                       (+ sum
                                          (count (catalog.by-class-spec (. pair
                                                                           1)
                                                                        (. pair
                                                                           2))))))
                                (assert.are.equal (count (catalog.all)) sum))))
                        (it "has no duplicate item per (class spec phase slot)"
                            (fn []
                              (let [seen {}]
                                (each [_ e (ipairs (catalog.all))]
                                  (let [k (table.concat [(tostring e.class)
                                                         (tostring e.spec)
                                                         (tostring e.phase)
                                                         (tostring e.slot)
                                                         (tostring e.item.id)]
                                                        "|")]
                                    (assert.is_nil (. seen k)
                                                   (.. "duplicate " k))
                                    (tset seen k true))))))))
            (describe :queries
                      (fn []
                        (it "by-class-spec filters to the pair"
                            (fn []
                              (let [rows (catalog.by-class-spec :priest :shadow)]
                                (assert.is_true (> (count rows) 0))
                                (each [_ e (ipairs rows)]
                                  (assert.are.equal :priest e.class)
                                  (assert.are.equal :shadow e.spec)))))
                        (it "by-class-spec-phase filters to the phase"
                            (fn []
                              (each [_ e (ipairs (catalog.by-class-spec-phase :priest
                                                                              :shadow
                                                                              1))]
                                (assert.are.equal 1 e.phase))))
                        (it "by-slot filters to the slot"
                            (fn []
                              (each [_ e (ipairs (catalog.by-slot :priest
                                                                  :shadow
                                                                  :main-hand))]
                                (assert.are.equal :main-hand e.slot))))
                        (it "primary-for-slot returns the first entry, or nil on a miss"
                            (fn []
                              (let [sample (. (catalog.by-class-spec :priest
                                                                     :shadow)
                                              1)]
                                (assert.is_true (not= nil sample))
                                (let [p (catalog.primary-for-slot :priest
                                                                  :shadow
                                                                  sample.phase
                                                                  sample.slot)]
                                  (assert.is_true (not= nil p))
                                  (assert.are.equal sample.slot p.slot)
                                  (assert.are.equal sample.phase p.phase)
                                  (assert.are.equal :priest p.class)))
                              (assert.is_nil (catalog.primary-for-slot :priest
                                                                       :shadow
                                                                       99 :head))))
                        (it "specs-for-class lists the druid feral split"
                            (fn []
                              (let [specs (catalog.specs-for-class :druid)
                                    present {}]
                                (each [_ s (ipairs specs)]
                                  (tset present s true))
                                (assert.is_true (. present :feral-dps))
                                (assert.is_true (. present
                                                   :feral-tank-mitigation))
                                (assert.is_true (. present :balance)))))))
            (describe :purity
                      (fn []
                        (it "all returns a fresh sequence each call"
                            (fn []
                              (assert.is_false (rawequal (catalog.all)
                                                         (catalog.all)))))))))
