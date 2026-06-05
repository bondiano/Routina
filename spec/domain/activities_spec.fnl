;; activities_spec.fnl -- tests for the pure activity registry + availability.
;;
;; Pure module: no WoW API, no mocks, no real clock. Every "now" is a fixed
;; deterministic timestamp so the suite is reproducible. The registry is
;; cross-checked against schemas.ActivityDef, the requirement predicate covers
;; the level/attunement/rep gates, and the lockout matrix is exercised against a
;; LockoutView fixture (same shape as lockouts_spec).

(local activities (require :src.domain.activities))
(local schemas (require :src.domain.schemas))
(local validate (require :src.domain.validate))

;; A fixed server-time anchor so every case reads against a known instant.
(local now 1000)

(fn player [overrides]
  "Build a valid Player fixture, base fields overridden by `overrides`.
   Returns a fresh table so cases never share state."
  (collect [k v (pairs (or overrides {}))
            &into {:level 70 :attunements {:kara-key true} :reputations {}}]
    (values k v)))

(fn lockout [overrides]
  "Build a valid LockoutView fixture, base fields overridden by `overrides`.
   Default expiry is in the future (active). Fresh table per case."
  (collect [k v (pairs (or overrides {}))
            &into {:id :kara
                   :expiry (+ now 3600)
                   :bosses-killed 0
                   :bosses-total 11
                   :owner :Mainchar}]
    (values k v)))

;; Convenience handles on real registry entries.
(local kara (activities.by-id :karazhan))
(local skettis (activities.by-id :skettis-daily))
(local ogrila (activities.by-id :ogrila-dailies))

(describe :activities
          (fn []
            (describe :registry
                      (fn []
                        (it "every entry conforms to schemas.ActivityDef"
                            (fn []
                              (each [_ a (ipairs (activities.all))]
                                (let [r (validate.check schemas.ActivityDef a)]
                                  (assert.is_true r.ok
                                                  (.. (tostring a.id) ": "
                                                      (table.concat r.errors
                                                                    "; ")))))))
                        (it "every entry has a positive length-estimate"
                            (fn []
                              (each [_ a (ipairs (activities.all))]
                                (assert.is_true (> a.length-estimate 0)))))
                        (it "hands back a fresh sequence callers can't share"
                            (fn []
                              (assert.is_false (rawequal (activities.all)
                                                         (activities.all)))))
                        (it "carries a sane curated entrance per located entry (Phase 9)"
                            (fn []
                              (each [_ a (ipairs (activities.all))]
                                ;; location-free token sinks carry none; every
                                ;; instanced / outdoor entry points somewhere
                                (if (or (= a.id :vendor) (= a.id :quest))
                                    (assert.is_nil a.entrance)
                                    (do
                                      (assert.is_not_nil a.entrance
                                                         (tostring a.id))
                                      (assert.is_true (> a.entrance.map-id 0))
                                      (assert.is_true (and (>= a.entrance.x 0)
                                                           (<= a.entrance.x 1)))
                                      (assert.is_true (and (>= a.entrance.y 0)
                                                           (<= a.entrance.y 1))))))))))
            (describe ":by-id"
                      (fn []
                        (it "returns the matching ActivityDef"
                            (fn []
                              (assert.are.equal :karazhan
                                                (. (activities.by-id :karazhan)
                                                   :id))))
                        (it "returns nil on a miss"
                            (fn []
                              (assert.is_nil (activities.by-id :nonesuch))))))
            (describe ":by-type"
                      (fn []
                        (it "finds every heroic 5-man"
                            (fn []
                              ;; Mechanar + Auchenai Crypts placeholders + the
                              ;; five heroics that drop tracked BiS.
                              (assert.are.equal 7
                                                (length (activities.by-type :heroic)))))
                        (it "finds the full raid tier"
                            (fn []
                              ;; Kara + Gruul + Mag + SSC + TK + BT + Hyjal + Naxx
                              (assert.are.equal 8
                                                (length (activities.by-type :raid)))))
                        (it "finds both outdoor world bosses"
                            (fn []
                              (assert.are.equal 2
                                                (length (activities.by-type :world-boss)))))
                        (it "models the Badge of Justice vendor"
                            (fn []
                              (let [v (activities.by-id :vendor)]
                                (assert.are.equal :vendor v.type)
                                (assert.are.equal :none v.reset))))
                        (it "returns an empty sequence for an unknown type"
                            (fn []
                              (assert.are.equal 0
                                                (length (activities.by-type :pvp)))))))
            (describe ":requirements-met?"
                      (fn []
                        (it "is true at exactly min-level with the attunement"
                            (fn []
                              (assert.is_true (activities.requirements-met? kara
                                                                            (player {:level 70})))))
                        (it "is false below min-level"
                            (fn []
                              (assert.is_false (activities.requirements-met? kara
                                                                             (player {:level 69})))))
                        (it "is false when the required attunement is missing"
                            (fn []
                              (assert.is_false (activities.requirements-met? kara
                                                                             (player {:attunements {}})))))
                        (it "is true for an activity with no attunement"
                            (fn []
                              (assert.is_true (activities.requirements-met? skettis
                                                                            (player {:attunements {}})))))
                        (it "honors the rep gate when standing is high enough"
                            (fn []
                              (let [a (activities.by-id :ogrila-dailies)
                                    p (player {:reputations {:ogrila :honored}})]
                                ;; required standing is :neutral, honored >= neutral
                                (assert.is_true (activities.requirements-met? a
                                                                              p)))))
                        (it "honored player clears an honored-gated activity"
                            (fn []
                              ;; synthesize a stricter gate via the predicate's
                              ;; standing-rank comparison: honored vs honored.
                              (let [a (activities.by-id :ogrila-dailies)
                                    strict {:id a.id
                                            :name a.name
                                            :type a.type
                                            :reset a.reset
                                            :length-estimate a.length-estimate
                                            :requirements {:min-level 70
                                                           :rep {:faction :ogrila
                                                                 :standing :honored}}}
                                    p (player {:reputations {:ogrila :honored}})]
                                (assert.is_true (activities.requirements-met? strict
                                                                              p)))))
                        (it "neutral player fails an honored-gated activity"
                            (fn []
                              (let [a (activities.by-id :ogrila-dailies)
                                    strict {:id a.id
                                            :name a.name
                                            :type a.type
                                            :reset a.reset
                                            :length-estimate a.length-estimate
                                            :requirements {:min-level 70
                                                           :rep {:faction :ogrila
                                                                 :standing :honored}}}
                                    p (player {:reputations {:ogrila :neutral}})]
                                (assert.is_false (activities.requirements-met? strict
                                                                               p)))))
                        (it "missing faction defaults to neutral and fails honored gate"
                            (fn []
                              (let [a (activities.by-id :ogrila-dailies)
                                    strict {:id a.id
                                            :name a.name
                                            :type a.type
                                            :reset a.reset
                                            :length-estimate a.length-estimate
                                            :requirements {:min-level 70
                                                           :rep {:faction :ogrila
                                                                 :standing :honored}}}
                                    p (player {:reputations {}})]
                                (assert.is_false (activities.requirements-met? strict
                                                                               p)))))))
            (describe ":available?"
                      (fn []
                        (it "is true with no saved lockout and met requirements"
                            (fn []
                              (assert.is_true (activities.available? kara
                                                                     (player {})
                                                                     nil now))))
                        (it "is false when requirements are unmet, lockout or not"
                            (fn []
                              (assert.is_false (activities.available? kara
                                                                      (player {:level 1})
                                                                      nil now))
                              (assert.is_false (activities.available? kara
                                                                      (player {:level 1})
                                                                      (lockout {:bosses-killed 0})
                                                                      now))))
                        (it "is true on an active weekly lockout with bosses left (3/11)"
                            (fn []
                              (assert.is_true (activities.available? kara
                                                                     (player {})
                                                                     (lockout {:bosses-killed 3
                                                                               :bosses-total 11})
                                                                     now))))
                        (it "is false on a fully cleared active weekly lockout (11/11)"
                            (fn []
                              (assert.is_false (activities.available? kara
                                                                      (player {})
                                                                      (lockout {:bosses-killed 11
                                                                                :bosses-total 11})
                                                                      now))))
                        (it "is true on an expired lockout even if it was full"
                            (fn []
                              (assert.is_true (activities.available? kara
                                                                     (player {})
                                                                     (lockout {:expiry (- now
                                                                                          1)
                                                                               :bosses-killed 11
                                                                               :bosses-total 11})
                                                                     now))))
                        (it "is true for a :none-reset activity with an active lockout"
                            (fn []
                              (let [a (activities.by-id :karazhan)
                                    none {:id a.id
                                          :name a.name
                                          :type a.type
                                          :reset :none
                                          :length-estimate a.length-estimate
                                          :requirements a.requirements}]
                                (assert.is_true (activities.available? none
                                                                       (player {})
                                                                       (lockout {:bosses-killed 11
                                                                                 :bosses-total 11})
                                                                       now)))))))
            (describe :properties
                      (fn []
                        (it "requirements-met? returns a real boolean"
                            (fn []
                              (each [_ a (ipairs (activities.all))]
                                (let [r (activities.requirements-met? a
                                                                      (player {}))]
                                  (assert.are.equal :boolean (type r))))))
                        (it "available? returns a real boolean"
                            (fn []
                              (each [_ a (ipairs (activities.all))]
                                (let [r1 (activities.available? a (player {})
                                                                nil now)
                                      r2 (activities.available? a (player {})
                                                                (lockout {}) now)]
                                  (assert.are.equal :boolean (type r1))
                                  (assert.are.equal :boolean (type r2))))))))))
