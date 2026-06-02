;; drop_table_spec.fnl -- tests for the generated drop table.
;;
;; Data is generated (scripts/import-drops.lua) from the vendored nexus-devs
;; dataset, so the tests are structural: every entry conforms to schemas.DropEntry,
;; probabilities are well-formed, guaranteed sources read 1.0, and lookups behave.
;; No WoW API, no clock.

(local drop-table (require :src.domain.drop-table))
(local validate (require :src.domain.validate))
(local schemas (require :src.domain.schemas))

(fn count [seq] (length seq))

(describe :drop-table
          (fn []
            (describe "data integrity"
                      (fn []
                        (it "validates every entry against schemas.DropEntry"
                            (fn []
                              (each [_ e (ipairs (drop-table.all))]
                                (let [r (validate.check schemas.DropEntry e)]
                                  (assert.is_true r.ok
                                                  (.. "invalid entry "
                                                      (tostring e.item-id) ": "
                                                      (table.concat (or r.errors
                                                                        [])
                                                                    "; ")))))))
                        (it "is non-empty with all probabilities in [0, 1]"
                            (fn []
                              (assert.is_true (> (count (drop-table.all)) 0))
                              (each [_ e (ipairs (drop-table.all))]
                                (assert.is_true (and (>= e.base-drop-p 0)
                                                     (<= e.base-drop-p 1))
                                                (.. "p out of range for "
                                                    (tostring e.item-id))))))
                        (it "guaranteed sources (vendor/quest) read p = 1.0"
                            (fn []
                              (var n 0)
                              (each [_ e (ipairs (drop-table.all))]
                                (when (or (= e.source-activity :vendor)
                                          (= e.source-activity :quest))
                                  (set n (+ n 1))
                                  (assert.are.equal 1.0 e.base-drop-p)))
                              (assert.is_true (> n 0))))))
            (describe :lookups
                      (fn []
                        (it "for-item returns the entry for a known id, nil otherwise"
                            (fn []
                              (let [sample (. (drop-table.all) 1)]
                                (assert.is_true (not= nil sample))
                                (let [e (drop-table.for-item sample.item-id)]
                                  (assert.is_true (not= nil e))
                                  (assert.are.equal sample.item-id e.item-id)))
                              (assert.is_nil (drop-table.for-item 999999999))))
                        (it "drop-p returns the entry chance, 0 for an untracked id"
                            (fn []
                              (let [sample (. (drop-table.all) 1)]
                                (assert.are.equal sample.base-drop-p
                                                  (drop-table.drop-p sample.item-id)))
                              (assert.are.equal 0 (drop-table.drop-p 999999999))))
                        (it "source-activity returns a keyword or nil"
                            (fn []
                              (let [sample (. (drop-table.all) 1)]
                                (assert.are.equal sample.source-activity
                                                  (drop-table.source-activity sample.item-id)))
                              (assert.is_nil (drop-table.source-activity 999999999))))
                        (it "by-activity filters to the activity"
                            (fn []
                              (let [rows (drop-table.by-activity :vendor)]
                                (assert.is_true (> (count rows) 0))
                                (each [_ e (ipairs rows)]
                                  (assert.are.equal :vendor e.source-activity)))))))
            (describe :purity
                      (fn []
                        (it "all returns a fresh sequence each call"
                            (fn []
                              (assert.is_false (rawequal (drop-table.all)
                                                         (drop-table.all)))))))))
