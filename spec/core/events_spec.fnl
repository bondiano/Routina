;; events_spec.fnl -- pure dispatch + a lightweight init!/cleanup! smoke.
;; A fake logger is injected via set-logger!; a fake AceEvent lib is passed to
;; init!, so this spec needs no real Ace3.

(local events (require :src.core.events))
(local mock (require :spec.mocks.wow-api))

(fn make-log []
  (let [calls {:debug [] :info [] :warn [] :error []}]
    {: calls
     :debug (fn [_ m] (table.insert calls.debug m))
     :info (fn [_ m] (table.insert calls.info m))
     :warn (fn [_ m] (table.insert calls.warn m))
     :error (fn [_ m] (table.insert calls.error m))}))

(fn make-ace-event []
  "Minimal AceEvent-3.0 stand-in: Embed adds a recording RegisterEvent."
  {:Embed (fn [_ frame]
            (set frame.registered {})
            (set frame.RegisterEvent
                 (fn [self ev h] (tset self.registered ev h)))
            (set frame.UnregisterAllEvents (fn [self] (set self.registered {})))
            frame)})

(describe :events
          (fn []
            (describe :event-list
                      (fn []
                        (it "consumes the expected event set"
                            (fn []
                              (assert.are.same [:PLAYER_ENTERING_WORLD
                                                :UPDATE_INSTANCE_INFO
                                                :RAID_INSTANCE_WELCOME
                                                :PLAYER_EQUIPMENT_CHANGED
                                                :BAG_UPDATE_DELAYED
                                                :CHARACTER_POINTS_CHANGED
                                                :ENCOUNTER_END
                                                :CHAT_MSG_LOOT
                                                :QUEST_TURNED_IN
                                                :PLAYER_LOGOUT]
                                               events.event-list)))))
            (describe :dispatch
                      (fn []
                        (it "routes every known event without error, logging debug"
                            (fn []
                              (let [log (make-log)]
                                (events.set-logger! log)
                                (each [_ ev (ipairs events.event-list)]
                                  (events.dispatch ev))
                                (assert.are.equal (length events.event-list)
                                                  (length log.calls.debug))
                                (assert.are.equal 0 (length log.calls.warn)))))
                        (it "logs unknown events at warn"
                            (fn []
                              (let [log (make-log)]
                                (events.set-logger! log)
                                (events.dispatch :SOME_NONSENSE_EVENT)
                                (assert.are.equal 1 (length log.calls.warn)))))
                        (it "fires the injected refresh on an input-change event"
                            (fn []
                              (let [log (make-log)
                                    hits {:n 0}]
                                (events.set-logger! log)
                                (events.set-refresh! (fn []
                                                       (set hits.n (+ hits.n 1))))
                                (events.dispatch :PLAYER_EQUIPMENT_CHANGED)
                                (events.dispatch :CHARACTER_POINTS_CHANGED)
                                (assert.are.equal 2 hits.n)
                                ;; reset so the injected callback can't leak
                                (events.set-refresh! nil))))
                        (it "tolerates payload args on routed events"
                            (fn []
                              (let [log (make-log)]
                                (events.set-logger! log)
                                (assert.has_no.errors (fn []
                                                        (events.dispatch :RAID_INSTANCE_WELCOME
                                                                         :Karazhan
                                                                         3600))))))))
            (describe :weekly-state
                      (fn []
                        (it "marks an entered raid in-progress and flushes it on logout"
                            (fn []
                              (let [log (make-log)
                                    char {:weekly-state nil}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (events.dispatch :RAID_INSTANCE_WELCOME
                                                 :Karazhan 3600)
                                (events.dispatch :PLAYER_LOGOUT)
                                ;; flushed to the injected db.char slot
                                (assert.is_truthy char.weekly-state)
                                (assert.is_true (. char.weekly-state :lockouts
                                                   :Karazhan :in-progress?))
                                (events.set-store! nil))))
                        (it "no-ops the weekly handlers when no store is wired"
                            (fn []
                              (let [log (make-log)]
                                (events.set-logger! log)
                                (events.set-store! nil)
                                (assert.has_no.errors (fn []
                                                        (events.dispatch :RAID_INSTANCE_WELCOME
                                                                         :Karazhan
                                                                         3600)
                                                        (events.dispatch :PLAYER_LOGOUT))))))))
            (describe :luck-history
                      (fn []
                        (it "does not record while tracking is off (default)"
                            (fn []
                              (let [log (make-log)
                                    char {}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (events.record-run! :karazhan)
                                (events.record-drop! 28545)
                                (events.dispatch :PLAYER_LOGOUT)
                                (assert.is_nil char.history)
                                (events.set-store! nil))))
                        (it "records runs/drops and flushes on logout when on"
                            (fn []
                              (let [log (make-log)
                                    char {}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (events.set-history-tracking! true)
                                (events.record-run! :karazhan)
                                (events.record-run! :karazhan)
                                (events.record-drop! 28545)
                                (events.dispatch :PLAYER_LOGOUT)
                                (assert.are.equal 2
                                                  (. char.history :runs
                                                     :karazhan))
                                (assert.are.equal 1
                                                  (. char.history :drops :28545))
                                ;; clean up module state for later specs
                                (events.set-history-tracking! false)
                                (events.set-store! nil))))
                        (it "tallies a boss kill and self-loot from live events"
                            (fn []
                              (let [log (make-log)
                                    char {}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (events.set-history-tracking! true)
                                (events.dispatch :ENCOUNTER_END 652 :Attumen 3
                                                 10 1)
                                (events.dispatch :CHAT_MSG_LOOT
                                                 "You receive loot: |cffa335ee|Hitem:28545::::::::70:::::|h[Edgewalker Longboots]|h|r.")
                                (events.dispatch :PLAYER_LOGOUT)
                                (assert.are.equal 1
                                                  (. char.history :runs
                                                     :Attumen))
                                (assert.are.equal 1
                                                  (. char.history :drops :28545))
                                (events.set-history-tracking! false)
                                (events.set-store! nil))))
                        (it "ignores wipes, others' loot and untracked drops"
                            (fn []
                              (let [log (make-log)
                                    char {}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (events.set-history-tracking! true)
                                ;; a wipe (success 0) is not a trial
                                (events.dispatch :ENCOUNTER_END 652 :Attumen 3
                                                 10 0)
                                ;; a group member's loot is not the player's
                                (events.dispatch :CHAT_MSG_LOOT
                                                 "Bob receives loot: |Hitem:28545::::::::70:::::|h[Edgewalker Longboots]|h|r.")
                                ;; self-loot of an item we do not track
                                (events.dispatch :CHAT_MSG_LOOT
                                                 "You receive loot: |Hitem:2589::::::::70:::::|h[Linen Cloth]|h|r.")
                                (events.dispatch :PLAYER_LOGOUT)
                                (assert.is_nil char.history)
                                (events.set-history-tracking! false)
                                (events.set-store! nil))))
                        (it "reset-history! zeroes the session and the store"
                            (fn []
                              (let [log (make-log)
                                    char {:history {:runs {:karazhan 5}
                                                    :drops {:28545 2}}}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (events.set-history-tracking! true)
                                (events.record-run! :karazhan)
                                (events.reset-history!)
                                ;; persisted copy is emptied immediately ...
                                (assert.are.same {:runs {}
                                                  :drops {}
                                                  :yields {}}
                                                 char.history)
                                ;; ... and the next record re-seeds from it,
                                ;; so the pre-reset tallies are gone for good.
                                (events.record-run! :karazhan)
                                (events.dispatch :PLAYER_LOGOUT)
                                (assert.are.equal 1
                                                  (. char.history :runs
                                                     :karazhan))
                                (events.set-history-tracking! false)
                                (events.set-store! nil))))
                        (it "reset-history! is safe with no store wired"
                            (fn []
                              (events.set-store! nil)
                              (assert.has_no.errors events.reset-history!)))))
            (describe :chains
                      (fn []
                        (before_each (fn [] (mock.reset!)))
                        ;; Karazhan chain (generated data): step "30" is quest
                        ;; 9824 at stage 30; "10" (level) and "20" (interact)
                        ;; sit below it and backfill once it completes.
                        (it "QUEST_TURNED_IN advances the chain and flushes on logout"
                            (fn []
                              (let [log (make-log)
                                    char {}
                                    hits {:n 0}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (events.set-refresh! (fn []
                                                       (set hits.n (+ hits.n 1))))
                                (events.dispatch :QUEST_TURNED_IN 9824 11000 0)
                                (events.dispatch :PLAYER_LOGOUT)
                                (assert.is_true (. char.chains :karazhan
                                                   :completed :30))
                                ;; non-quest predecessors backfilled
                                (assert.is_true (. char.chains :karazhan
                                                   :completed :10))
                                (assert.is_true (. char.chains :karazhan
                                                   :completed :20))
                                (assert.are.equal 1 hits.n)
                                (events.set-refresh! nil)
                                (events.set-store! nil))))
                        (it "an untracked quest neither records nor refreshes"
                            (fn []
                              (let [log (make-log)
                                    char {}
                                    hits {:n 0}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (events.set-refresh! (fn []
                                                       (set hits.n (+ hits.n 1))))
                                (events.dispatch :QUEST_TURNED_IN 99999999 0 0)
                                (events.dispatch :PLAYER_LOGOUT)
                                (assert.is_nil char.chains)
                                (assert.are.equal 0 hits.n)
                                (events.set-refresh! nil)
                                (events.set-store! nil))))
                        (it "PLAYER_ENTERING_WORLD seeds progress from quest flags"
                            (fn []
                              (let [log (make-log)
                                    char {}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (mock.set-quest-completed! 9824 true)
                                (events.dispatch :PLAYER_ENTERING_WORLD)
                                (events.dispatch :PLAYER_LOGOUT)
                                (assert.is_true (. char.chains :karazhan
                                                   :completed :30))
                                (events.set-store! nil))))
                        (it "login seed merges with persisted progress instead of clobbering"
                            (fn []
                              (let [log (make-log)
                                    char {:chains {:karazhan {:completed {:20 true}}}}]
                                (events.set-logger! log)
                                (events.set-store! (fn [] char))
                                (mock.set-quest-completed! 9824 true)
                                (events.dispatch :PLAYER_ENTERING_WORLD)
                                (events.dispatch :PLAYER_LOGOUT)
                                ;; both the persisted step and the freshly
                                ;; seeded quest step survive the merge
                                (assert.is_true (. char.chains :karazhan
                                                   :completed :20))
                                (assert.is_true (. char.chains :karazhan
                                                   :completed :30))
                                (events.set-store! nil))))
                        (it "no-ops when no store is wired"
                            (fn []
                              (let [log (make-log)]
                                (events.set-logger! log)
                                (events.set-store! nil)
                                (assert.has_no.errors (fn []
                                                        (events.dispatch :QUEST_TURNED_IN
                                                                         9824 0
                                                                         0)
                                                        (events.dispatch :PLAYER_ENTERING_WORLD)
                                                        (events.dispatch :PLAYER_LOGOUT))))))))
            (describe :init!
                      (fn []
                        (it "embeds a frame and registers every event"
                            (fn []
                              (let [log (make-log)
                                    frame (events.init! (make-ace-event) log)]
                                (each [_ ev (ipairs events.event-list)]
                                  (assert.is_truthy (. frame.registered ev))))))
                        (it "cleanup! unregisters everything"
                            (fn []
                              (let [log (make-log)
                                    frame (events.init! (make-ace-event) log)]
                                (events.cleanup! frame)
                                (assert.is_nil (. frame.registered
                                                  :PLAYER_LOGOUT)))))
                        (it "cleanup! tolerates a nil frame"
                            (fn []
                              (assert.has_no.errors (fn []
                                                      (events.cleanup! nil)))))))))
