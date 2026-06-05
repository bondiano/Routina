;; tomtom_spec.fnl -- the TomTom soft-dep facade (Phase 9). The prices_spec
;; harness: inject a fake _G.TomTom per test, restore after, and assert the
;; absent case is a silent no-op (the exit criterion: zero errors without
;; TomTom).

(local tomtom (require :src.core.tomtom))

(local kara-gate {:map-id 1430 :x 0.47 :y 0.75})

(fn with-tomtom [fake body]
  "Run body with _G.TomTom swapped for a fake (nil clears it), restoring the
   prior global even when the body throws."
  (let [saved _G.TomTom]
    (set _G.TomTom fake)
    (let [(ok err) (pcall body)]
      (set _G.TomTom saved)
      (assert ok err))))

(fn make-fake []
  "A recording TomTom stand-in: AddWaypoint logs its args and returns a uid
   table; RemoveWaypoint logs the uid."
  (let [log {:added [] :removed []}]
    {: log
     :AddWaypoint (fn [_self map-id x y opts]
                    (let [uid {: map-id : x : y :title opts.title}]
                      (table.insert log.added {: map-id : x : y : opts})
                      uid))
     :RemoveWaypoint (fn [_self uid] (table.insert log.removed uid))}))

(describe :tomtom
          (fn []
            (describe "TomTom absent"
                      (fn []
                        (it "reports unavailable and no-ops every call"
                            (fn []
                              (with-tomtom nil
                                (fn []
                                  (assert.is_false (tomtom.available?))
                                  (assert.has_no.errors (fn []
                                                          (assert.is_nil (tomtom.set-waypoint! kara-gate))
                                                          (tomtom.remove-waypoint! {:x 1})
                                                          (tomtom.remove-waypoint! nil)))))))))
            (describe "TomTom present"
                      (fn []
                        (it "is available and forwards the coord + labels"
                            (fn []
                              (let [fake (make-fake)]
                                (with-tomtom fake
                                  (fn []
                                    (assert.is_true (tomtom.available?))
                                    (let [uid (tomtom.set-waypoint! kara-gate
                                                                    :Karazhan)]
                                      (assert.is_not_nil uid)
                                      (let [[call] fake.log.added]
                                        (assert.are.equal 1430 call.map-id)
                                        (assert.are.equal 0.47 call.x)
                                        (assert.are.equal 0.75 call.y)
                                        (assert.are.equal :Karazhan
                                                          call.opts.title)
                                        (assert.are.equal :Routina
                                                          call.opts.from))
                                      (tomtom.remove-waypoint! uid)
                                      (assert.are.equal uid
                                                        (. fake.log.removed 1))))))))
                        (it "merges extra options (circuit callbacks) over ours"
                            (fn []
                              (let [fake (make-fake)
                                    callbacks {:distance {15 (fn [])}}]
                                (with-tomtom fake
                                  (fn []
                                    (tomtom.set-waypoint! kara-gate :Lap
                                                          {: callbacks
                                                           :crazy true})
                                    (let [[call] fake.log.added]
                                      (assert.are.equal callbacks
                                                        call.opts.callbacks)
                                      (assert.is_true call.opts.crazy)
                                      (assert.are.equal :Routina call.opts.from)))))))
                        (it "survives a throwing TomTom (API drift -> nil)"
                            (fn []
                              (with-tomtom {:AddWaypoint (fn []
                                                           (error :drifted))
                                            :RemoveWaypoint (fn []
                                                              (error :drifted))}
                                (fn []
                                  (assert.has_no.errors (fn []
                                                          (assert.is_nil (tomtom.set-waypoint! kara-gate))
                                                          (tomtom.remove-waypoint! {:x 1})))))))
                        (it "rejects a non-table uid from a drifted API"
                            (fn []
                              (with-tomtom {:AddWaypoint (fn [] :not-a-uid)}
                                (fn []
                                  (assert.is_nil (tomtom.set-waypoint! kara-gate))))))))))
