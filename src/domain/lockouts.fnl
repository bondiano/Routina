;; lockouts.fnl -- pure model of raid/dungeon lockouts.
;;
;; PURE domain module:
;;   - No WoW API, no mutation of inputs, no I/O, no random.
;;   - CRUCIALLY no time source of its own: every fn that needs "now" takes a
;;     `now` argument (server-time seconds). The imperative shell
;;     (src/core/events.fnl) feeds it GetServerTime(); this module never calls
;;     GetServerTime / os.time / os.date. Deterministic: same inputs -> same out.
;;
;; The shape this module operates on is the planner-facing projection
;; schemas.LockoutView -- NOT the raw WoW RequestRaidInfo record modelled by
;; schemas.Lockout. The imperative shell (src/core/events.fnl) maps raw -> view
;; on ingest. Fields (single source of truth: schemas.LockoutView):
;;   {:id          string   -- stable lockout key (owner+instance, stringified)
;;    :expiry      integer  -- server-time seconds when the ID resets
;;    :bosses-killed integer >= 0  -- encounters already cleared
;;    :bosses-total  integer >= 0  -- encounters in the instance (>= killed)
;;    :owner       string}  -- character key the lockout belongs to
;; bosses-remaining is derived, never stored, so the two counts cannot drift.
;; See docs/ROADMAP.md Phase 2 s1 and .claude/examples/01-pure-module/.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; --- Helpers (private) -----------------------------------------------------

(fn assert-lockout [lockout]
  "Validate the LockoutView shape at a public-fn boundary.
   Field presence and types are delegated to schemas.LockoutView via
   validate.assert!; the cross-field `killed <= total` invariant (which the
   schema DSL cannot express) is checked here, and is what makes
   bosses-remaining safe to derive."
  (validate.assert! schemas.LockoutView lockout :lockout)
  (assert (<= lockout.bosses-killed lockout.bosses-total)
          "lockout.bosses-killed must be <= bosses-total")
  lockout)

;; --- Public API ------------------------------------------------------------

(lambda M.bosses-remaining [lockout]
  "Encounters still alive in this lockout (derived, never stored).
   Domain:  lockout : LockoutView (schemas.LockoutView; see module header)
   Returns: integer >= 0 -- bosses-total minus bosses-killed
   Errors:  if the LockoutView shape is invalid (e.g. killed > total)."
  (assert-lockout lockout)
  (- lockout.bosses-total lockout.bosses-killed))

(lambda M.time-until-reset [lockout now]
  "Seconds until the lockout's instance ID resets, clamped at 0.
   Domain:  lockout : LockoutView (schemas.LockoutView; see module header)
            now     : integer -- current server time in seconds
   Returns: integer >= 0 -- max(0, expiry - now); 0 once expiry has passed
   Errors:  if the LockoutView shape is invalid, or now is not a number."
  (assert-lockout lockout)
  (assert (= (type now) :number) "now must be a number")
  (math.max 0 (- lockout.expiry now)))

(lambda M.lockout-active? [lockout now]
  "True while the lockout still holds -- its reset is in the future.
   A lockout is active iff now < expiry; at or past expiry it has reset and is
   no longer binding.
   Domain:  lockout : LockoutView (schemas.LockoutView; see module header)
            now     : integer -- current server time in seconds
   Returns: boolean
   Errors:  if the LockoutView shape is invalid, or now is not a number."
  (assert-lockout lockout)
  (assert (= (type now) :number) "now must be a number")
  (< now lockout.expiry))

(lambda M.lockout-shareable? [lockout now]
  "True if this lockout's instance ID can be shared/extended to group members.
   TBC interpretation (documented assumption): an ID is shareable only while it
   is still active AND completely fresh -- zero bosses killed. Once any boss is
   down the saved progress can no longer be handed to a new group member.
   Domain:  lockout : LockoutView (schemas.LockoutView; see module header)
            now     : integer -- current server time in seconds
   Returns: boolean
   Errors:  if the LockoutView shape is invalid, or now is not a number."
  (assert-lockout lockout)
  (assert (= (type now) :number) "now must be a number")
  (and (M.lockout-active? lockout now) (= lockout.bosses-killed 0)))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.lockouts` before
;; src/core/events.fnl feeds it. In tests, consumers fall through to
;; `(require :src.domain.lockouts)` which returns the same M.

(set _G.Routina Routina)
(set Routina.lockouts M)

M
