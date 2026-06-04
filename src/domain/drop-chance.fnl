;; drop-chance.fnl — probability math for loot drops.
;;
;; CANONICAL EXAMPLE of a pure domain module:
;;   - No WoW API imports.
;;   - No mutation, no I/O. Functions touch no globals besides math; the
;;     module-load footer registers M into the Routina namespace (the
;;     established dual-mode pattern, same as format.fnl) so in-game
;;     consumers can reach it without `require`.
;;   - Every public fn has a docstring.
;;   - Module exports a single table M.
;;   - All exported fns are individually testable.

(local M {})

;; --- Constants ---

(local default-prior-alpha 1)

; Beta(1,1) = uniform prior
(local default-prior-beta 1)

;; --- Helpers (private) ---

(fn binomial-coefficient [n k]
  "Compute C(n, k) without overflow for small n typical of drop math.
   Uses multiplicative formula. Returns 0 if k > n or k < 0."
  (if (or (< k 0) (> k n))
      0
      (let [k (math.min k (- n k))]
        (var result 1)
        (for [i 1 k]
          (set result (/ (* result (+ (- n i) 1)) i)))
        result)))

;; --- Public API ---

(fn M.at-least-one [p n]
  "Probability of at least one drop in n runs given per-run probability p.
   Domain: 0 <= p <= 1, n >= 0.
   Returns: P in [0, 1]."
  (assert (and (>= p 0) (<= p 1)) (.. "p out of range: " (tostring p)))
  (assert (>= n 0) (.. "n must be non-negative: " (tostring n)))
  (- 1 (^ (- 1 p) n)))

(fn M.exactly-k [n k p]
  "Binomial probability: exactly k drops in n runs at rate p.
   Domain: 0 <= p <= 1, 0 <= k <= n, n >= 0.
   Returns: P in [0, 1]."
  (assert (and (>= p 0) (<= p 1)) "p out of range")
  (assert (and (>= k 0) (<= k n)) "k out of range")
  (* (binomial-coefficient n k) (^ p k) (^ (- 1 p) (- n k))))

(fn M.expected-runs [p]
  "Expected number of runs until first drop (geometric distribution).
   Returns: math.huge if p = 0, otherwise 1/p."
  (assert (and (>= p 0) (<= p 1)) "p out of range")
  (if (= p 0) math.huge (/ 1 p)))

(fn M.effective-rate [p competitors]
  "Adjust drop rate p for ML competition. competitors >= 1 includes self.
   E.g. 4 casters compete on a caster trinket -> effective = p/4."
  (assert (and (>= p 0) (<= p 1)) "p out of range")
  (assert (>= competitors 1) "competitors must be >= 1")
  (/ p competitors))

(fn M.bayesian-luck [observed-drops observed-runs base-p ?prior]
  "Bayesian posterior given observed history.
   Prior: Beta(alpha, beta), default (1, 1) = uniform.
   Returns table {:posterior-mean :posterior-variance :luck-z :n}.
   :luck-z is a z-like score: (posterior-mean - base-p) / sqrt(variance).
   Positive z = luckier than expected, negative = unluckier."
  (assert (>= observed-drops 0) "observed-drops >= 0")
  (assert (>= observed-runs observed-drops) "runs >= drops")
  (let [{: alpha : beta} (or ?prior
                             {:alpha default-prior-alpha
                              :beta default-prior-beta})
        a (+ alpha observed-drops)
        b (+ beta (- observed-runs observed-drops))
        mean (/ a (+ a b)) ;; Var of Beta(a, b) = ab / ((a+b)^2 (a+b+1))
        variance (/ (* a b) (* (^ (+ a b) 2) (+ a b 1)))
        std (math.sqrt variance)
        z (if (= std 0) 0 (/ (- mean base-p) std))]
    {:posterior-mean mean
     :posterior-variance variance
     :luck-z z
     :n observed-runs}))

(fn M.make-rng [seed]
  "Deterministic [0,1) generator from an integer seed (Park-Miller MINSTD).
   Domain code never calls math.random -- a caller seeds this so a Monte Carlo
   projection is reproducible (same seed -> same stream). Overflow-safe in WoW's
   Lua 5.1 doubles: state*16807 < 2^53, so the modulus is exact.
   Domain:  seed : integer (any; normalised into the MINSTD range [1, m-1]).
   Returns: fn [] -> number in [0, 1)."
  (let [m 2147483647
        a 16807]
    (var state (let [s (% (math.floor (math.abs seed)) m)]
                 (if (= s 0) 1 s)))
    (fn []
      (set state (% (* state a) m))
      (/ state m))))

(fn M.coupon-collector-mc [items n-runs n-sims rng]
  "Monte Carlo simulation of coupon collector: how many slots filled after n-runs.
   items: sequence of {:slot kw :p number} entries.
   rng: deterministic RNG seeded by caller (do NOT use math.random directly here;
        purity requires injected randomness).
   Returns: {:p10 :p50 :p90} as fractions of items filled."
  (assert (> n-sims 0) "n-sims > 0")
  (assert (> n-runs 0) "n-runs > 0")
  (let [results []]
    (for [_sim 1 n-sims]
      (let [filled {}]
        (for [_run 1 n-runs]
          (each [_ item (ipairs items)]
            (when (< (rng) item.p)
              (tset filled item.slot true))))
        (var count 0)
        (each [_ _ (pairs filled)]
          (set count (+ count 1)))
        (table.insert results (/ count (length items)))))
    (table.sort results)
    (let [n (length results)
          p10-idx (math.max 1 (math.floor (* n 0.1)))
          p50-idx (math.max 1 (math.floor (* n 0.5)))
          p90-idx (math.max 1 (math.floor (* n 0.9)))]
      {:p10 (. results p10-idx)
       :p50 (. results p50-idx)
       :p90 (. results p90-idx)})))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, the .toc load order populates `_G.Routina.drop-chance`
;; before src/domain/plan.fnl runs. In tests, consumers fall through to
;; `(require :src.domain.drop-chance)` which returns the same M.

(local Routina (or _G.Routina {}))
(set _G.Routina Routina)
(set Routina.drop-chance M)

M
