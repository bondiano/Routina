;; yields_spec.fnl -- tests for the generated yield table + band blending.
;;
;; Data is generated (scripts/import-yields.lua) from the curated band table +
;; derived boss rosters, so the data tests are structural: every entry conforms
;; to schemas.ActivityYield, bands are ordered, badges are non-negative, and
;; lookups behave. blended-band gets behavioural tests: untouched at n=0, only
;; ever narrowing, converging on the observed mean. No WoW API, no clock.

(local yields (require :src.domain.yields))
(local validate (require :src.domain.validate))
(local schemas (require :src.domain.schemas))

(describe :yields
          (fn []
            (describe "data integrity"
                      (fn []
                        (it "validates every entry against schemas.ActivityYield"
                            (fn []
                              (each [_ e (ipairs (yields.all))]
                                (let [r (validate.check schemas.ActivityYield e)]
                                  (assert.is_true r.ok
                                                  (.. "invalid entry "
                                                      (tostring e.activity-id)
                                                      ": "
                                                      (table.concat (or r.errors
                                                                        [])
                                                                    "; ")))))))
                        (it "is non-empty with ordered gold bands and badges >= 0"
                            (fn []
                              (assert.is_true (> (length (yields.all)) 0))
                              (each [_ e (ipairs (yields.all))]
                                (assert.is_true (<= e.gold-min e.gold-max)
                                                (tostring e.activity-id))
                                (assert.is_true (>= e.badges 0)
                                                (tostring e.activity-id)))))
                        (it "pays badges on heroics and none at the badge vendor"
                            (fn []
                              (assert.is_true (> (yields.badges-for :heroic-mech)
                                                 0))
                              (assert.are.equal 0 (yields.badges-for :vendor))))))
            (describe :lookups
                      (fn []
                        (it "for-activity returns the entry or nil"
                            (fn []
                              (let [e (yields.for-activity :karazhan)]
                                (assert.are.equal :karazhan e.activity-id))
                              (assert.is_nil (yields.for-activity :nonesuch))))
                        (it "badges-for and gold-band-for zero out untracked ids"
                            (fn []
                              (assert.are.equal 0 (yields.badges-for :nonesuch))
                              (assert.is_nil (yields.gold-band-for :nonesuch))))
                        (it "gold-band-for returns a fresh ordered band"
                            (fn []
                              (let [a (yields.gold-band-for :karazhan)
                                    b (yields.gold-band-for :karazhan)]
                                (assert.is_true (<= a.min a.max))
                                (assert.is_false (rawequal a b)))))
                        (it "rep-for surfaces the rep hub payout only"
                            (fn []
                              (let [rep (yields.rep-for :ogrila-dailies)]
                                (assert.are.equal :ogrila rep.faction)
                                (assert.is_true (> rep.amount 0)))
                              (assert.is_nil (yields.rep-for :karazhan))))))
            (describe :blended-band
                      (fn []
                        (local curated {:min 100000 :max 300000})
                        (it "returns the curated band untouched at zero runs"
                            (fn []
                              (let [b (yields.blended-band curated 0 0)]
                                (assert.are.equal curated.min b.min)
                                (assert.are.equal curated.max b.max)
                                (assert.is_false (rawequal curated b)))))
                        (it "narrows monotonically as runs accumulate"
                            (fn []
                              ;; observed mean 200000 (inside the band)
                              (var prev-width (- curated.max curated.min))
                              (for [n 1 50]
                                (let [b (yields.blended-band curated
                                                             (* n 200000) n)
                                      width (- b.max b.min)]
                                  (assert.is_true (< width prev-width))
                                  (assert.is_true (<= b.min b.max))
                                  (set prev-width width)))))
                        (it "converges on the observed mean, even outside the band"
                            (fn []
                              (let [b (yields.blended-band curated
                                                           (* 1000 500000) 1000)]
                                ;; w = 1000/1005 -- both edges within 1% of mean
                                (assert.is_true (> b.min 490000))
                                (assert.is_true (< b.max 510000)))))
                        (it "rejects an inverted band at the boundary"
                            (fn []
                              (assert.has_error #(yields.blended-band {:min 2
                                                                       :max 1}
                                                                      0 0))))))))
