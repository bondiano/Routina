;; ace_spec.fnl -- AceAddon entry, against the Ace3 mock (spec/mocks/ace3.fnl,
;; installed by spec/helper.lua). Confirms the lifecycle wires DB, slash
;; commands and events, and that the logger gates by level.

(local ace (require :src.core.ace))
(local ace-mock (require :spec.mocks.ace3))

(describe :ace
          (fn []
            (before_each (fn [] (ace-mock.reset!)))
            (describe :OnInitialize
                      (fn []
                        (it "creates the DB and a logger"
                            (fn []
                              (ace:OnInitialize)
                              (assert.is_truthy ace.db)
                              (assert.is_truthy ace.db.global)
                              (assert.are.equal 4 ace.db.global.version)
                              (assert.is_truthy ace.log)))
                        (it "registers the /routina and /rt commands"
                            (fn []
                              (ace:OnInitialize)
                              (let [cmds (ace-mock.registered-commands)]
                                (assert.is_truthy (. cmds :routina))
                                (assert.is_truthy (. cmds :rt)))))))
            (describe "slash subcommands"
                      (fn []
                        (fn rt [input]
                          "Invoke the registered /rt handler with one input."
                          (let [handler (. (ace-mock.registered-commands) :rt)]
                            (handler input)))

                        (before_each (fn []
                                       (ace:OnInitialize)
                                       (ace:OnEnable)))
                        (after_each (fn [] (ace:OnDisable)))
                        (it "plan prints a plan (or the input error) to chat"
                            (fn []
                              (rt :plan)
                              (let [lines (ace-mock.printed)]
                                (assert.is_true (>= (length lines) 1))
                                (assert.is_truthy (string.find (. lines 1)
                                                               :Routina 1 true)))))
                        (it "reset zeroes the persisted luck history"
                            (fn []
                              (set ace.db.char.history
                                   {:runs {:karazhan 5} :drops {:28545 2}})
                              (rt :reset)
                              (assert.are.same {:runs {} :drops {} :yields {}}
                                               ace.db.char.history)
                              (assert.are.equal "Routina: luck history reset."
                                                (. (ace-mock.printed) 1))))
                        (it "debug dumps db, tracking and plan diagnostics"
                            (fn []
                              (rt :debug)
                              (let [lines (ace-mock.printed)]
                                (assert.are.equal 3 (length lines))
                                (assert.is_truthy (string.find (. lines 1)
                                                               "Routina debug -- db v4"
                                                               1 true))
                                (assert.is_truthy (string.find (. lines 2)
                                                               "luck tracking: off"
                                                               1 true)))))
                        (it "is case-insensitive and trims surrounding noise"
                            (fn []
                              (rt " DEBUG ")
                              (assert.are.equal 3 (length (ace-mock.printed)))))
                        (it "unknown words print a usage line"
                            (fn []
                              (rt :bogus)
                              (assert.is_truthy (string.find (. (ace-mock.printed)
                                                                1)
                                                             :usage 1 true))))
                        (it "bare input still toggles without error"
                            (fn []
                              (assert.has_no.errors (fn [] (rt "")))))))
            (describe :OnEnable
                      (fn []
                        (it "stands up the event frame"
                            (fn []
                              (ace:OnInitialize)
                              (ace:OnEnable)
                              (assert.is_truthy ace.event-frame)
                              (assert.is_truthy (. ace.event-frame.registered
                                                   :UPDATE_INSTANCE_INFO))))
                        (it "OnDisable tears events down without error"
                            (fn []
                              (ace:OnInitialize)
                              (ace:OnEnable)
                              (assert.has_no.errors (fn [] (ace:OnDisable)))))))
            (describe :make-logger
                      (fn []
                        (it "suppresses calls below the current level"
                            (fn []
                              (let [printed []
                                    old _G.print]
                                (set _G.print #(table.insert printed $1))
                                (let [logger (ace.make-logger (fn [] :warn))]
                                  (logger:debug :hidden)
                                  (logger:info :hidden)
                                  (logger:warn :shown)
                                  (logger:error :shown))
                                (set _G.print old)
                                (assert.are.equal 2 (length printed)))))))))
