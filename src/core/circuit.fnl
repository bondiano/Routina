;; circuit.fnl -- the circuit runner: walk a chain's waypoint loop with the
;; player (ROADMAP Phase 9 §4; resolves OQ-14).
;;
;; OQ-14 RESOLVED (2026-06-06): auto-advance rides TomTom's own
;; `callbacks.distance[yards]` waypoint callbacks (verified against the
;; TomTom source -- see src/core/tomtom.fnl header) instead of polling player
;; position from an OnUpdate. TomTom already watches the distance for its
;; arrow, so arrival costs us nothing per frame and the no-OnUpdate UI rule
;; needs no new exception.
;;
;; Imperative shell, SESSION-ONLY state (a /reload stops the circuit -- v1):
;; one circuit at a time; arrival removes the current waypoint and sets the
;; next, wrapping past the last step for repeatable farm laps. Headless-safe:
;; everything funnels through the tomtom facade, so without TomTom start!
;; reports false and nothing else happens.

(local Routina (or _G.Routina {}))
(local chains (or Routina.chains (require :src.domain.chains)))
(local tomtom (or Routina.tomtom (require :src.core.tomtom)))

(local M {})

;; Yards from the waypoint that count as "arrived" -- one value for the whole
;; loop; generous enough to fire while mounted past the point.
(local arrive-yards 15)

;; --- Session state -----------------------------------------------------------

(var active nil)

;; {chain-id steps idx uid} | nil

(fn set-current! []
  "Place the waypoint for the active step, wiring the arrival callback that
   advances the loop."
  (let [step (. active.steps active.idx)
        on-arrive (fn [] (M.advance!))]
    (set active.uid
         (tomtom.set-waypoint! step.coord step.label
                               {:crazy true
                                :callbacks {:distance {arrive-yards on-arrive}}}))))

;; --- Public API --------------------------------------------------------------

(lambda M.active-chain []
  "The chain id the circuit is currently walking, or nil.
   Domain:  (none)
   Returns: string | nil."
  (and active active.chain-id))

(lambda M.advance! []
  "Move the circuit to its next point: drop the current waypoint, wrap past
   the last step (a farm lap loops), set the next. Fired by TomTom's arrival
   callback; safe to call by hand (a manual skip-ahead). No-op when no
   circuit runs.
   Domain:  (none)
   Returns: nil."
  (when active
    (tomtom.remove-waypoint! active.uid)
    (set active.idx (+ (% active.idx (length active.steps)) 1))
    (set-current!))
  nil)

(lambda M.start! [chain]
  "Start walking a chain's waypoint loop from its first coordinate-carrying
   step, replacing any running circuit. Reports false -- and changes nothing
   -- when the chain has no coordinates or TomTom is absent.
   Domain:  chain : ChainDef
   Returns: boolean -- whether the circuit started."
  (let [steps (chains.circuit-steps chain)]
    (if (or (= 0 (length steps)) (not (tomtom.available?)))
        false
        (do
          (M.stop!)
          (set active {:chain-id (tostring chain.id) : steps :idx 1 :uid nil})
          (set-current!)
          true))))

(lambda M.stop! []
  "Stop the running circuit and drop its waypoint. No-op when idle.
   Domain:  (none)
   Returns: nil."
  (when active
    (tomtom.remove-waypoint! active.uid)
    (set active nil))
  nil)

;; --- Register into the addon namespace ---------------------------------------

(set _G.Routina Routina)
(set Routina.circuit M)

M
