;; saved_vars_spec.fnl -- pure: defaults shape + migration runner.
;; No WoW or Ace3 surface touched.

(local saved-vars (require :src.core.saved-vars))

(describe :saved-vars
          (fn []
            (describe :defaults
                      (fn []
                        (it "carries an integer global version"
                            (fn []
                              (assert.are.equal :number
                                                (type saved-vars.defaults.global.version))))
                        (it "declares a default log level and char namespace"
                            (fn []
                              (assert.are.equal :info
                                                saved-vars.defaults.global.options.log-level)
                              (assert.is_truthy saved-vars.defaults.char.weekly-state)))
                        (it "ships the v5 plan-edits migration and matching defaults"
                            (fn []
                              (assert.are.equal 5
                                                saved-vars.defaults.global.version)
                              (assert.is_truthy saved-vars.defaults.char.chains)
                              (assert.is_truthy saved-vars.defaults.char.goals)
                              (assert.is_truthy (. saved-vars.defaults.char
                                                   :history :yields))
                              (assert.is_truthy saved-vars.defaults.profile.custom-activities)
                              (assert.is_truthy saved-vars.defaults.char.plan-edits)
                              (assert.are.equal 4
                                                (length saved-vars.migrations))
                              (assert.are.equal 2
                                                (. saved-vars.migrations 1 :to))
                              (assert.are.equal 3
                                                (. saved-vars.migrations 2 :to))
                              (assert.are.equal 4
                                                (. saved-vars.migrations 3 :to))
                              (assert.are.equal 5
                                                (. saved-vars.migrations 4 :to))))
                        (it "fast-forwards a v3 DB to the latest idempotently"
                            (fn []
                              (let [out (saved-vars.migrate {:version 3}
                                                            saved-vars.migrations)
                                    again (saved-vars.migrate out
                                                              saved-vars.migrations)]
                                (assert.are.equal 5 out.version)
                                (assert.are.equal 5 again.version))))))
            (describe :migrate
                      (fn []
                        (it "is a no-op with no migrations"
                            (fn []
                              (let [g {:version 1 :options {}}
                                    out (saved-vars.migrate g [])]
                                (assert.are.equal 1 out.version))))
                        (it "applies a newer migration and bumps version"
                            (fn []
                              (let [g {:version 1 :flag false}
                                    ms [{:to 2
                                         :apply (fn [db]
                                                  (set db.flag true)
                                                  db)}]
                                    out (saved-vars.migrate g ms)]
                                (assert.are.equal 2 out.version)
                                (assert.is_true out.flag))))
                        (it "skips migrations not newer than the stored version"
                            (fn []
                              (var applied 0)
                              (let [g {:version 2}
                                    ms [{:to 2
                                         :apply (fn [db]
                                                  (set applied (+ applied 1))
                                                  db)}]
                                    out (saved-vars.migrate g ms)]
                                (assert.are.equal 0 applied)
                                (assert.are.equal 2 out.version))))
                        (it "is idempotent across repeated runs"
                            (fn []
                              (var applied 0)
                              (let [ms [{:to 2
                                         :apply (fn [db]
                                                  (set applied (+ applied 1))
                                                  db)}]
                                    once (saved-vars.migrate {:version 1} ms)
                                    twice (saved-vars.migrate once ms)]
                                (assert.are.equal 1 applied)
                                (assert.are.equal 2 twice.version))))
                        (it "applies a chain of migrations in order"
                            (fn []
                              (let [g {:version 0 :steps []}
                                    mk (fn [n]
                                         {:to n
                                          :apply (fn [db]
                                                   (table.insert db.steps n)
                                                   db)})
                                    out (saved-vars.migrate g
                                                            [(mk 1)
                                                             (mk 2)
                                                             (mk 3)])]
                                (assert.are.equal 3 out.version)
                                (assert.are.same [1 2 3] out.steps))))))))
