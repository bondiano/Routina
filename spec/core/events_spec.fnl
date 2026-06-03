;; events_spec.fnl -- pure dispatch + a lightweight init!/cleanup! smoke.
;; A fake logger is injected via set-logger!; a fake AceEvent lib is passed to
;; init!, so this spec needs no real Ace3.

(local events (require :src.core.events))

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
