;; circuit_spec.fnl -- the circuit runner (Phase 9 §4, OQ-14): arrivals are
;; SIMULATED by firing the distance callback the runner registered with the
;; fake TomTom -- the ROADMAP exit criterion ("a fixture daily circuit
;; advances through its loop on simulated arrivals").

(local circuit (require :src.core.circuit))
(local custom-chains (require :src.domain.custom-chains))

(local lap-chain ;; a three-point farm lap authored via the editor syntax
       (custom-chains.to-chain-def {:id :chain-1
                                    :name "Primal lap"
                                    :steps (custom-chains.parse-steps "West camps @ 1946 20 30
Lake motes @ 1946 50 60
Vendor stop @ 1946 80 40")}))

(local coordless
       (custom-chains.to-chain-def {:id :chain-2
                                    :name "No coords"
                                    :steps [{:label "Just a label"}]}))

(fn make-fake []
  "A recording TomTom: AddWaypoint returns a fresh uid and logs args."
  (let [log {:added [] :removed []}]
    {: log
     :AddWaypoint (fn [_self map-id x y opts]
                    (let [uid {:n (+ 1 (length log.added))}]
                      (table.insert log.added {: map-id : x : y : opts : uid})
                      uid))
     :RemoveWaypoint (fn [_self uid] (table.insert log.removed uid))}))

(fn arrive! [fake]
  "Simulate the player reaching the LAST waypoint set: fire the distance
   callback the runner registered on it."
  (let [call (. fake.log.added (length fake.log.added))
        handler (. call.opts.callbacks.distance 15)]
    (assert.is_not_nil handler)
    (handler)))

(fn with-tomtom [fake body]
  (let [saved _G.TomTom]
    (set _G.TomTom fake)
    (let [(ok err) (pcall body)]
      (circuit.stop!)
      (set _G.TomTom saved)
      (assert ok err))))

(describe :circuit
          (fn []
            (it "refuses to start without TomTom or without coords"
                (fn []
                  (with-tomtom nil
                    (fn []
                      (assert.is_false (circuit.start! lap-chain))
                      (assert.is_nil (circuit.active-chain))))
                  (with-tomtom (make-fake)
                    (fn []
                      (assert.is_false (circuit.start! coordless))
                      (assert.is_nil (circuit.active-chain))))))
            (it "starts at the first point with an arrival callback wired"
                (fn []
                  (let [fake (make-fake)]
                    (with-tomtom fake
                      (fn []
                        (assert.is_true (circuit.start! lap-chain))
                        (assert.are.equal :chain-1 (circuit.active-chain))
                        (let [[wp] fake.log.added]
                          (assert.are.equal 1946 wp.map-id)
                          (assert.are.equal 0.2 wp.x)
                          (assert.are.equal 0.3 wp.y)
                          (assert.are.equal "West camps" wp.opts.title)
                          (assert.is_not_nil (. wp.opts.callbacks.distance 15))))))))
            (it "advances through the loop on simulated arrivals, wrapping
                 past the last point (the Phase 9 exit criterion)"
                (fn []
                  (let [fake (make-fake)]
                    (with-tomtom fake
                      (fn []
                        (circuit.start! lap-chain)
                        (arrive! fake)
                        ;; -> Lake motes
                        (arrive! fake)
                        ;; -> Vendor stop
                        (arrive! fake)
                        ;; -> wraps to West camps
                        (assert.are.equal 4 (length fake.log.added))
                        (assert.are.equal 3 (length fake.log.removed))
                        (let [titles (icollect [_ c (ipairs fake.log.added)]
                                       c.opts.title)]
                          (assert.are.same ["West camps"
                                            "Lake motes"
                                            "Vendor stop"
                                            "West camps"]
                                           titles))
                        ;; each arrival removed the waypoint it hit
                        (assert.are.equal 1 (. fake.log.removed 1 :n)))))))
            (it "stop! drops the waypoint and goes idle; advance! then no-ops"
                (fn []
                  (let [fake (make-fake)]
                    (with-tomtom fake
                      (fn []
                        (circuit.start! lap-chain)
                        (circuit.stop!)
                        (assert.is_nil (circuit.active-chain))
                        (assert.are.equal 1 (length fake.log.removed))
                        (assert.has_no.errors circuit.advance!)
                        (assert.are.equal 1 (length fake.log.added)))))))
            (it "starting a second circuit replaces the first"
                (fn []
                  (let [fake (make-fake)
                        other (custom-chains.to-chain-def {:id :chain-9
                                                           :name :Other
                                                           :steps (custom-chains.parse-steps "Solo point @ 1944 10 10")})]
                    (with-tomtom fake
                      (fn []
                        (circuit.start! lap-chain)
                        (circuit.start! other)
                        (assert.are.equal :chain-9 (circuit.active-chain))
                        ;; the first circuit's waypoint was removed
                        (assert.are.equal 1 (. fake.log.removed 1 :n)))))))))
