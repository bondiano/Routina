;; gen.fnl -- deterministic generators for property-based tests.
;;
;; Purity rule: domain code never calls `math.random`; tests inject randomness.
;; These generators are seeded so a failing property is always reproducible.
;; Used by property tests in spec/domain/* (drop-chance, routing, ...).

(local M {})

(fn M.make-rng [seed]
  "Deterministic linear congruential generator.
   Domain:  seed :: integer
   Returns: fn [] -> number in [0, 1)"
  (var state seed)
  (fn []
    (set state (% (+ (* state 1103515245) 12345) 2147483648))
    (/ state 2147483648)))

(fn M.prob [rng]
  "Draw a probability.
   Domain:  rng :: fn [] -> [0,1)
   Returns: number in [0, 1]"
  (rng))

(fn M.int-in [rng lo hi]
  "Draw an integer in the inclusive range [lo, hi].
   Domain:  rng :: fn [] -> [0,1); lo,hi :: integers, lo <= hi
   Returns: integer in [lo, hi]"
  (assert (<= lo hi) "lo must be <= hi")
  (+ lo (math.floor (* (rng) (+ 1 (- hi lo))))))

(fn M.sample [rng xs]
  "Pick one element of a non-empty sequence.
   Domain:  rng :: fn [] -> [0,1); xs :: non-empty sequence
   Returns: an element of xs"
  (let [n (length xs)]
    (assert (> n 0) "cannot sample from an empty sequence")
    (. xs (M.int-in rng 1 n))))

M
