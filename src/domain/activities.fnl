;; activities.fnl -- pure static registry of weekly content + availability.
;;
;; PURE domain module:
;;   - No WoW API, no mutation of inputs, no I/O, no random.
;;   - No time source of its own: every fn that needs "now" takes a `now`
;;     argument (server-time seconds). The imperative shell
;;     (src/core/events.fnl) feeds it GetServerTime(); this module never calls
;;     GetServerTime / os.time / os.date. Deterministic: same inputs -> same out.
;;
;; This module owns the STATIC content definition -- what weekly content exists,
;; its reset cadence (:weekly/:daily/:none), length estimate, and prerequisites
;; (level, attunement, reputation). Shape: schemas.ActivityDef. It is distinct
;; from the scored, plan-facing schemas.Activity that src/domain/plan.fnl
;; renders; the two share ids (:karazhan ...) so a scored row traces back to its
;; definition.
;;
;; Per-period AVAILABILITY couples to src/domain/lockouts.fnl: the module never
;; fetches a lockout itself (purity). The caller (route/events shell) pairs the
;; right schemas.LockoutView by id and feeds it together with GetServerTime() as
;; `now`. See docs/ROADMAP.md Phase 2 s2 and .claude/examples/01-pure-module/.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))
(local lockouts (or Routina.lockouts (require :src.domain.lockouts)))

(local M {})

;; --- Reputation ranks (private) --------------------------------------------
;;
;; Numeric rank for the full TBC standing ladder (low -> high), so a rep gate is
;; a single `>=` comparison. Mirrors schemas' inlined standing-enum ordering.

(local standing-rank {:hated 0
                      :hostile 1
                      :unfriendly 2
                      :neutral 3
                      :friendly 4
                      :honored 5
                      :revered 6
                      :exalted 7})

;; --- Helpers (private) -----------------------------------------------------

(fn assert-activity [activity]
  "Validate the ActivityDef shape at a public-fn boundary.
   Field presence and types are delegated to schemas.ActivityDef via
   validate.assert!; the `length-estimate > 0` invariant (which the schema DSL
   cannot express) is checked here so callers can trust the estimate."
  (validate.assert! schemas.ActivityDef activity :activity)
  (assert (> activity.length-estimate 0) "activity.length-estimate must be > 0")
  activity)

;; --- Seed registry (clearly-marked scaffold) -------------------------------
;;
;; A representative slice of TBC weekly content so the availability engine has
;; live data to chew on. Each :id is kept IDENTICAL to the matching
;; src/domain/drops/data.fnl :source-activity slug (e.g. :serpentshrine-cavern),
;; so src/domain/route.fnl can link a BiS drop back to the activity that awards
;; it -- a mismatched id silently drops the item from the plan.
;;
;; The T4-T6 raid tier (Karazhan + SSC/TK/BT/Hyjal) is present so the planner
;; spans a real progression path; heroics/dailies/rep hubs remain a thin sample.
;; Attunement keys are PLACEHOLDER slugs (real key items / quest chains are
;; refined with verified data later); :ogrila-dailies is gated on a reputation
;; purely to exercise the :rep path. The full content list is follow-up work.

(local registry
       [{:id :karazhan
         :name :Karazhan
         :type :raid
         :reset :weekly
         :length-estimate 95
         :requirements {:min-level 70 :attunement :kara-key}}
        {:id :serpentshrine-cavern
         :name "Serpentshrine Cavern"
         :type :raid
         :reset :weekly
         :length-estimate 150
         :requirements {:min-level 70 :attunement :ssc-attune}}
        {:id :tempest-keep
         :name "Tempest Keep: The Eye"
         :type :raid
         :reset :weekly
         :length-estimate 135
         :requirements {:min-level 70 :attunement :tk-attune}}
        {:id :black-temple
         :name "Black Temple"
         :type :raid
         :reset :weekly
         :length-estimate 180
         :requirements {:min-level 70 :attunement :bt-medallion}}
        {:id :hyjal-summit
         :name "Hyjal Summit"
         :type :raid
         :reset :weekly
         :length-estimate 130
         :requirements {:min-level 70 :attunement :hyjal-vials}}
        {:id :heroic-mech
         :name "Heroic Mechanar"
         :type :heroic
         :reset :daily
         :length-estimate 35
         :requirements {:min-level 70 :attunement :heroic-flamewrought}}
        {:id :heroic-slabs
         :name "Heroic Auchenai Crypts"
         :type :heroic
         :reset :daily
         :length-estimate 40
         :requirements {:min-level 70 :attunement :heroic-auchindoun}}
        {:id :skettis-daily
         :name "Skettis Dailies"
         :type :daily
         :reset :daily
         :length-estimate 10
         :requirements {:min-level 70}}
        {:id :ogrila-dailies
         :name "Ogri'la Dailies"
         :type :rep-hub
         :reset :daily
         :length-estimate 20
         :requirements {:min-level 70
                        :rep {:faction :ogrila :standing :neutral}}}])

;; Load-time self-check: every seed entry through the boundary validator once,
;; so a typo'd registry row fails at `require` time, not at first call site.
(each [_ activity (ipairs registry)]
  (assert-activity activity))

;; --- Public API ------------------------------------------------------------

(lambda M.all []
  "The full content registry as a fresh shallow-copied sequence.
   Domain:  (none)
   Returns: [ActivityDef] -- a new sequence so callers cannot mutate the
            module's registry (entries are shared by reference, read-only).
   Errors:  (none)."
  (icollect [_ activity (ipairs registry)] activity))

(lambda M.by-id [id]
  "The ActivityDef whose :id matches, or nil.
   Domain:  id : string -- the stable activity key (e.g. :karazhan)
   Returns: ActivityDef | nil
   Errors:  (none)."
  (accumulate [found nil _ activity (ipairs registry) &until found]
    (when (= activity.id id) activity)))

(lambda M.by-type [type]
  "Every ActivityDef of the given content type, as a fresh sequence.
   Domain:  type : enum -- :raid :heroic :daily :weekly-quest :rep-hub
   Returns: [ActivityDef] -- a new sequence (possibly empty)
   Errors:  (none)."
  (icollect [_ activity (ipairs registry)]
    (when (= activity.type type) activity)))

(lambda M.requirements-met? [activity player]
  "True iff the player meets every prerequisite of the activity.
   Checks, in order: level >= min-level, the optional attunement is owned, and
   the optional reputation gate is satisfied (a missing faction counts as
   :neutral). Pure predicate -- reads player state, mutates nothing.
   Domain:  activity : ActivityDef (schemas.ActivityDef; validated)
            player   : Player (schemas.Player); :level integer,
                       :attunements set {key true}, :reputations {faction std}
   Returns: boolean
   Errors:  if the ActivityDef shape is invalid, or player.level is not a number."
  (assert-activity activity)
  (assert (= (type player.level) :number) "player.level must be a number")
  (let [req activity.requirements
        level-ok? (>= player.level req.min-level)
        attune-ok? (or (= nil req.attunement)
                       (not= nil (. player.attunements req.attunement)))
        rep-ok? (or (= nil req.rep)
                    (>= (. standing-rank
                           (or (. player.reputations req.rep.faction) :neutral))
                        (. standing-rank req.rep.standing)))]
    (and level-ok? attune-ok? rep-ok?)))

(lambda M.available? [activity player ?lockout now]
  "True iff the activity is doable right now for this player.
   Gates first on prerequisites (requirements-met?); then on the lockout: no
   saved lockout or an already-reset one means open, otherwise availability
   depends on the reset cadence -- a :weekly/:daily instance is open only while
   bosses remain, a :none-reset activity is never locked out. The module never
   fetches a lockout (purity); the caller pairs the right LockoutView by id.
   Domain:  activity : ActivityDef (schemas.ActivityDef; validated)
            player   : Player (schemas.Player)
            ?lockout : LockoutView | nil -- the matching saved lockout, if any
            now      : integer -- current server time in seconds
   Returns: boolean
   Errors:  if the ActivityDef shape is invalid, or now is not a number."
  (assert-activity activity)
  (assert (= (type now) :number) "now must be a number")
  (if (not (M.requirements-met? activity player))
      false
      (= nil ?lockout)
      true
      (not (lockouts.lockout-active? ?lockout now))
      true
      (case activity.reset
        :weekly (> (lockouts.bosses-remaining ?lockout) 0)
        :daily (> (lockouts.bosses-remaining ?lockout) 0)
        :none true
        _ true)))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.activities` after
;; lockouts. In tests, consumers fall through to
;; `(require :src.domain.activities)` which returns the same M.

(set _G.Routina Routina)
(set Routina.activities M)

M
