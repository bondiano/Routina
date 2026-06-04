;; drop_chance_spec.fnl — canonical spec layout for pure modules.
;;
;; CANONICAL EXAMPLE of a busted spec for a pure module:
;;   - describe/it nesting mirrors the public API
;;   - each fn gets: happy path, boundary, error cases, property-based check
;;   - no WoW API, no mocks (pure module shouldn't need them)
;;   - deterministic — no math.random, inject rng

(local chance (require :src.domain.drop-chance))

;; Simple deterministic RNG for tests
(fn make-rng [seed]
  "Linear congruential generator, deterministic."
  (var state seed)
  (fn []
    (set state (% (+ (* state 1103515245) 12345) 2147483648))
    (/ state 2147483648)))

(describe :drop-chance
          (fn []
            (describe ":at-least-one"
                      (fn []
                        (it "returns 0 when p=0"
                            (fn []
                              (assert.are.equal 0 (chance.at-least-one 0 10))))
                        (it "returns 1 when p=1 and n>=1"
                            (fn []
                              (assert.are.equal 1 (chance.at-least-one 1 1))
                              (assert.are.equal 1 (chance.at-least-one 1 100))))
                        (it "matches closed form 1 - (1-p)^n"
                            (fn []
                              (let [p 0.15
                                    n 10
                                    expected (- 1 (^ (- 1 p) n))]
                                (assert.are.equal expected
                                                  (chance.at-least-one p n)))))
                        (it "monotonically increases in n (property)"
                            (fn []
                              (let [p 0.15]
                                (for [n 1 99]
                                  (let [a (chance.at-least-one p n)
                                        b (chance.at-least-one p (+ n 1))]
                                    (assert.is_true (<= a b)))))))
                        (it "always returns value in [0, 1] (property)"
                            (fn []
                              (let [rng (make-rng 42)]
                                (for [_ 1 200]
                                  (let [p (rng)
                                        n (math.floor (* (rng) 100))
                                        r (chance.at-least-one p n)]
                                    (assert.is_true (and (>= r 0) (<= r 1))))))))
                        (it "rejects p outside [0, 1]"
                            (fn []
                              (assert.has_error (fn []
                                                  (chance.at-least-one -0.1 10)))
                              (assert.has_error (fn []
                                                  (chance.at-least-one 1.5 10)))))))
            (describe ":exactly-k"
                      (fn []
                        (it "P(k=0, n=10, p=0) = 1"
                            (fn []
                              (assert.are.equal 1 (chance.exactly-k 10 0 0))))
                        (it "P(k=n, n=10, p=1) = 1"
                            (fn []
                              (assert.are.equal 1 (chance.exactly-k 10 10 1))))
                        (it "binomial PMF sums to 1 over all k (property)"
                            (fn []
                              (let [n 10
                                    p 0.3]
                                (var total 0)
                                (for [k 0 n]
                                  (set total (+ total (chance.exactly-k n k p))))
                                (assert.is_true (< (math.abs (- total 1)) 1e-09)))))))
            (describe ":expected-runs"
                      (fn []
                        (it "returns infinity when p=0"
                            (fn []
                              (assert.are.equal math.huge
                                                (chance.expected-runs 0))))
                        (it "returns 1/p"
                            (fn []
                              (assert.are.equal 10 (chance.expected-runs 0.1))
                              (assert.are.equal 4 (chance.expected-runs 0.25))))))
            (describe ":effective-rate"
                      (fn []
                        (it "divides p by competitor count"
                            (fn []
                              (assert.are.equal 0.05
                                                (chance.effective-rate 0.2 4))))
                        (it "no change with single competitor (self)"
                            (fn []
                              (assert.are.equal 0.15
                                                (chance.effective-rate 0.15 1))))))
            (describe ":bayesian-luck"
                      (fn []
                        (it "with no observations returns prior mean = 0.5"
                            (fn []
                              (let [r (chance.bayesian-luck 0 0 0.15)]
                                (assert.are.equal 0.5 r.posterior-mean))))
                        (it "with all-drop observations, posterior > base-p"
                            (fn []
                              (let [r (chance.bayesian-luck 10 10 0.15)]
                                (assert.is_true (> r.posterior-mean 0.15))
                                (assert.is_true (> r.luck-z 0)))))
                        (it "with no drops observed, posterior < base-p"
                            (fn []
                              (let [r (chance.bayesian-luck 0 20 0.15)]
                                (assert.is_true (< r.posterior-mean 0.15))
                                (assert.is_true (< r.luck-z 0)))))))
            (describe ":make-rng"
                      (fn []
                        (it "is deterministic for a given seed"
                            (fn []
                              (let [a (chance.make-rng 42)
                                    b (chance.make-rng 42)]
                                (for [_ 1 5]
                                  (assert.are.equal (a) (b))))))
                        (it "stays in [0, 1)"
                            (fn []
                              (let [rng (chance.make-rng 7)]
                                (for [_ 1 100]
                                  (let [x (rng)]
                                    (assert.is_true (and (>= x 0) (< x 1))))))))
                        (it "different seeds yield different streams"
                            (fn []
                              (assert.are_not.equal ((chance.make-rng 1))
                                                    ((chance.make-rng 2)))))
                        (it "normalises a zero seed to a non-degenerate stream"
                            (fn []
                              (let [rng (chance.make-rng 0)]
                                ;; MINSTD fixed point at 0 would freeze the stream
                                (assert.are_not.equal (rng) (rng)))))))
            (describe ":coupon-collector-mc"
                      (fn []
                        (it "p10 <= p50 <= p90 (property of order statistics)"
                            (fn []
                              (let [items [{:slot :head :p 0.15}
                                           {:slot :chest :p 0.12}
                                           {:slot :legs :p 0.1}]
                                    r (chance.coupon-collector-mc items 20 500
                                                                  (make-rng 1))]
                                (assert.is_true (<= r.p10 r.p50))
                                (assert.is_true (<= r.p50 r.p90)))))
                        (it "more runs -> higher completion (property)"
                            (fn []
                              (let [items [{:slot :head :p 0.1}
                                           {:slot :chest :p 0.1}]
                                    short (chance.coupon-collector-mc items 5
                                                                      500
                                                                      (make-rng 1))
                                    long (chance.coupon-collector-mc items 50
                                                                     500
                                                                     (make-rng 1))]
                                (assert.is_true (<= short.p50 long.p50)))))))))
