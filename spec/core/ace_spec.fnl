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
                              (assert.are.equal 1 ace.db.global.version)
                              (assert.is_truthy ace.log)))
                        (it "registers the /routina and /rt commands"
                            (fn []
                              (ace:OnInitialize)
                              (let [cmds (ace-mock.registered-commands)]
                                (assert.is_truthy (. cmds :routina))
                                (assert.is_truthy (. cmds :rt)))))))
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
