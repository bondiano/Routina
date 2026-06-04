;; weekly-state.fnl -- pure model of the per-character weekly progress record.
;;
;; PURE domain module:
;;   - No WoW API, no I/O, no random, no time source of its own. Every fn that
;;     needs "now" takes it as an argument (server-time seconds); the imperative
;;     shell (src/core/events.fnl) feeds it GetServerTime().
;;   - Inputs are never mutated: every transform returns a NEW table, so the live
;;     session copy and the persisted DB table never alias.
;;
;; This is the in-memory record src/core/events.fnl accumulates across a play
;; session -- which saved raids the player has stepped into this week -- and
;; flushes to addon.db.char.weekly-state on PLAYER_LOGOUT. On the next login the
;; shell seeds the session back from the DB via `normalize`, which drops any
;; lockout whose reset has already passed (a new week wipes last week's progress).
;;
;; Shape (DB-compatible with saved-vars.fnl :char.weekly-state defaults):
;;   WeeklyState   = {:reset-time integer            -- earliest known reset (0 = unknown)
;;                    :lockouts {id -> WeeklyLockout}}
;;   WeeklyLockout = {:in-progress? boolean
;;                    :entered-at integer            -- server-time first entered
;;                    :reset-at integer}             -- when it resets (0 = unknown)
;; :reset-time is DERIVED (earliest positive :reset-at), never stored independently,
;; so it cannot drift from the entries. See schemas.fnl :WeeklyState /
;; :WeeklyLockout and docs/ROADMAP.md Phase 2.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; --- Helpers (private) -----------------------------------------------------

(fn copy-lockout [entry]
  "A fresh shallow copy of a WeeklyLockout (inputs are never mutated)."
  {:in-progress? entry.in-progress?
   :entered-at entry.entered-at
   :reset-at entry.reset-at})

(fn copy-lockouts [lockouts]
  "Fresh map of id -> fresh WeeklyLockout."
  (collect [id entry (pairs lockouts)]
    id
    (copy-lockout entry)))

(fn earliest-reset [lockouts]
  "The soonest positive :reset-at across the entries, or 0 when none is known."
  (accumulate [acc 0 _ entry (pairs lockouts)]
    (if (<= entry.reset-at 0) acc
        (= acc 0) entry.reset-at
        (math.min acc entry.reset-at))))

(fn make [lockouts]
  "Assemble a WeeklyState from a (already-fresh) lockouts map, deriving
   :reset-time so it can never drift from the entries."
  {:reset-time (earliest-reset lockouts) : lockouts})

(fn valid-entry? [entry]
  "Whether a persisted value is a well-formed WeeklyLockout. Defensive: corrupt
   SavedVariables must be dropped on load, not crash it."
  (and (= (type entry) :table) (. (validate.check schemas.WeeklyLockout entry)
                                  :ok)))

(fn expired? [entry now]
  "True if the lockout has a known reset that is at or before now (a new week)."
  (and (> entry.reset-at 0) (<= entry.reset-at now)))

;; --- Public API ------------------------------------------------------------

(lambda M.empty []
  "A fresh, empty weekly-state record.
   Domain:  (none)
   Returns: WeeklyState -- {:reset-time 0 :lockouts {}}"
  (make {}))

(lambda M.in-progress? [state id]
  "Whether the player has stepped into lockout `id` this week.
   Domain:  state : WeeklyState ; id : string -- lockout key
   Returns: boolean"
  (let [entry (. state.lockouts id)]
    (if (and entry entry.in-progress?) true false)))

(lambda M.mark-in-progress [state id now ?reset-at]
  "Record that the player entered saved lockout `id`, returning a NEW state.
   Idempotent on :entered-at -- re-entering keeps the first entry time but
   refreshes the (possibly newly-known) reset.
   Domain:  state : WeeklyState ; id : string ; now : integer
            ?reset-at : integer -- server-time the lockout resets (default 0/unknown)
   Returns: WeeklyState with lockouts[id] marked in-progress"
  (let [reset-at (or ?reset-at 0)
        prior (. state.lockouts id)
        lockouts (copy-lockouts state.lockouts)]
    (tset lockouts id
          {:in-progress? true
           :entered-at (if prior prior.entered-at now)
           :reset-at (math.max reset-at (if prior prior.reset-at 0))})
    (make lockouts)))

(lambda M.prune [state now]
  "Drop lockouts whose reset has passed, returning a NEW state. Entries with an
   unknown reset (:reset-at 0) are kept.
   Domain:  state : WeeklyState ; now : integer
   Returns: WeeklyState"
  (make (collect [id entry (pairs state.lockouts)]
          (if (expired? entry now) (values nil nil)
              (values id (copy-lockout entry))))))

(lambda M.normalize [?persisted now]
  "Coerce a possibly-nil / possibly-corrupt persisted table into a valid
   WeeklyState and prune expired lockouts. Used by the shell when seeding the
   session from SavedVariables on login; malformed entries are silently dropped.
   Domain:  ?persisted : table | nil -- db.char.weekly-state ; now : integer
   Returns: WeeklyState"
  (if (not= (type ?persisted) :table)
      (M.empty)
      (let [raw (if (= (type ?persisted.lockouts) :table) ?persisted.lockouts
                    {})]
        (make (collect [id entry (pairs raw)]
                (if (and (= (type id) :string) (valid-entry? entry)
                         (not (expired? entry now)))
                    (values id (copy-lockout entry))
                    (values nil nil)))))))

(lambda M.to-db [state]
  "A fresh plain copy of the weekly-state for writing to SavedVariables, so the
   persisted table never aliases the live session copy.
   Domain:  state : WeeklyState
   Returns: WeeklyState (plain data)"
  (make (copy-lockouts state.lockouts)))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.weekly-state`
;; before src/core/events.fnl feeds it. In tests, consumers fall through to
;; `(require :src.domain.weekly-state)` -> the same M.

(set _G.Routina Routina)
(set Routina.weekly-state M)

M
