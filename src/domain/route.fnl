;; route.fnl -- pure weekly-route planner: the last Phase-2 domain piece.
;;
;; Ties the domain together. Given a player and a RouteContext, it asks
;; src/domain/activities.fnl what the player can run this week, src/domain/
;; bis-catalog.fnl which items they still want, src/domain/drop-table.fnl where
;; (and how often) those items drop, and src/domain/drop-chance.fnl for the
;; probability math -- then hands a real catalog to src/domain/plan.fnl, which
;; keeps sole ownership of per-item :chance annotation and deterministic
;; ordering (route only injects a slot-weighted scorer).
;;
;; PURE domain module:
;;   - No WoW API, no mutation of inputs, no I/O, no time, no random. `now`
;;     arrives inside the RouteContext (GetServerTime() seconds), assembled by
;;     the imperative shell; this module never reads a clock.
;;   - Deterministic: same (player, ctx) -> same plan.
;;
;; Greedy scoring v1 (PRD §6.4, ROADMAP Phase 2 §5):
;;   score(activity) = Σ weight(slot) · at-least-one(p, planned-runs)
;; over the player's UNOWNED BiS items (phase <= ctx.phase) that drop from the
;; activity, where p = effective-rate(base-drop-p, competitors). Decisions baked
;; in for v1 and revisited later: BoEs are included (OQ-2), lockout decay is flat
;; (OQ-7), heroics rank by this same BiS-per-week score (OQ-6). No new math.
;; See docs/PRD.md §13 and .claude/examples/01-pure-module/.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))
(local chance (or Routina.drop-chance (require :src.domain.drop-chance)))
(local plan (or Routina.plan (require :src.domain.plan)))
(local activities (or Routina.activities (require :src.domain.activities)))
(local bis-catalog (or Routina.bis-catalog (require :src.domain.bis-catalog)))
(local drop-table (or Routina.drop-table (require :src.domain.drop-table)))

(local M {})

;; --- Constants -------------------------------------------------------------

(local default-slot-weight 1)
(local default-competitors 1)

;; Items never recommended, regardless of settings: the four Atiesh variants are
;; vanilla legendaries whose quest line was removed with Naxxramas-40 in TBC, so
;; they are unobtainable on TBC Anniversary. (The BiS import lists them and the
;; drop import mislabelled them as guaranteed quest rewards.)
(local excluded-item-ids {22589 true 22630 true 22631 true 22632 true})

;; Pre-TBC ("classic") gear is hidden unless ctx.include-classic? opts it back in.
;; The imported dataset's classic items top out at id 23207 (Atiesh / AQ40 / Naxx40)
;; and the lowest TBC item is 24116, so anything below this cutoff is pre-TBC.
(local classic-item-id-cutoff 23500)

;; Monte Carlo projection defaults (PRD §6.5 / ROADMAP Phase 4 §3). 1000 sims
;; keeps the run well under the 50 ms budget; the seed is fixed so a plan
;; projects identically until the options panel exposes a user seed.
(local default-sims 1000)
(local default-seed 1)

;; Planned clears per reset cadence over one week (greedy v1; no multi-week
;; "score per hour" warp yet -- OQ-6). A weekly raid is one clear; a daily
;; instance is capped at a casual "nights per week" estimate; :none is one-shot.
(local runs-by-reset {:weekly 1 :daily 4 :none 1})

;; Presentation labels for the renderable Activity (schemas.Activity :type /
;; :detail are display strings). Plain English placeholders pending AceLocale
;; (PRD §6.7); the previous src/ui/tabs/weekly.fnl scaffold inlined the same.
(local type-label {:raid :Raid
                   :heroic :Heroic
                   :dungeon :Dungeon
                   :daily :Daily
                   :weekly-quest :Quest
                   :rep-hub :Reputation
                   :vendor :Vendor
                   :world-boss "World Boss"})

(local reset-label {:weekly "weekly reset"
                    :daily "daily reset"
                    :none "no reset"})

;; --- Helpers (private) -----------------------------------------------------

(fn planned-runs [adef]
  "Planned clears of an activity over the week, from its reset cadence."
  (or (. runs-by-reset adef.reset) 1))

(fn weight-for [ctx slot]
  "The player's tuning weight for a gear slot (default 1 when unset)."
  (or (and ctx.weights (. ctx.weights slot)) default-slot-weight))

(fn competitors-for [ctx activity-id]
  "The competition pool for an activity's loot: a per-activity override, else the
   context-wide :default-competitors (the options panel's global slider), else 1."
  (or (and ctx.competitors (. ctx.competitors activity-id))
      ctx.default-competitors default-competitors))

(fn owned? [ctx item-id]
  "True iff the player already holds this item-id."
  (and ctx.owned-items (not= nil (. ctx.owned-items item-id))))

(fn show-item? [ctx item-id]
  "Whether an item may be recommended: never if hard-excluded (Atiesh), and
   pre-TBC gear only when ctx.include-classic? opts it in."
  (and (not (. excluded-item-ids item-id))
       (or ctx.include-classic? (>= item-id classic-item-id-cutoff))))

(fn target-item [ctx adef bis-entry]
  "A scored TargetItem for one BiS entry IF its item drops from this activity.
   Returns nil when the item is untracked or sourced elsewhere, so the activity
   only carries the gap items it can actually award.
   Returns: {:label :item-id :slot :runs :p} | nil."
  (let [item-id bis-entry.item.id
        entry (drop-table.for-item item-id)]
    (when (and entry (= entry.source-activity adef.id))
      {:label bis-entry.item.name
       : item-id
       :slot bis-entry.slot
       :runs (planned-runs adef)
       :p (chance.effective-rate entry.base-drop-p
                                 (competitors-for ctx adef.id))})))

(fn gap-items [ctx adef]
  "TargetItems for the player's UNOWNED BiS items (phase <= ctx.phase) that drop
   from this activity, in catalog order. Untracked / owned / off-source items
   fall away, so an empty result means 'nothing here for this player'."
  (let [bis (bis-catalog.by-class-spec ctx.class ctx.spec)]
    (icollect [_ e (ipairs bis)]
      (when (and (<= e.phase ctx.phase) (not (owned? ctx e.item.id))
                 (show-item? ctx e.item.id))
        (target-item ctx adef e)))))

(fn candidate-activity [player ctx adef]
  "A plan-ready Activity for one content def, or nil to drop it from the plan.
   Kept only when the player can run it this week (activities.available?) AND it
   drops at least one wanted item."
  (when (activities.available? adef player
                               (and ctx.lockouts (. ctx.lockouts adef.id))
                               ctx.now)
    (let [items (gap-items ctx adef)]
      (when (> (length items) 0)
        {:id adef.id
         :name adef.name
         :type (or (. type-label adef.type) (tostring adef.type))
         :detail (or (. reset-label adef.reset) (tostring adef.reset))
         :minutes adef.length-estimate
         :attunement (?. adef :requirements :attunement)
         : items}))))

(fn make-scorer [ctx]
  "A slot-weighted composite scorer to inject into plan.plan-week.
   score(activity) = Σ weight(slot) · at-least-one(p, runs); reduces to the
   plan default when every weight is 1."
  (fn [activity]
    (accumulate [total 0 _ item (ipairs activity.items)]
      (+ total (* (weight-for ctx item.slot)
                  (chance.at-least-one item.p item.runs))))))

(fn slot-fill-probs [steps]
  "Map gear-slot -> P(at least one upgrade for that slot by reset), folding every
   target item across all plan steps. Each item's week-probability is
   at-least-one(p, runs); items sharing a slot combine via the complement product
   (the slot is filled if ANY of its candidates drops). Items without a :slot are
   skipped -- their fill is unobservable."
  (let [probs {}]
    (each [_ step (ipairs steps)]
      (each [_ item (ipairs step.items)]
        (when item.slot
          (let [p-week (chance.at-least-one item.p item.runs)
                prior (or (. probs item.slot) 0)]
            (tset probs item.slot (- 1 (* (- 1 prior) (- 1 p-week))))))))
    probs))

;; --- Public API ------------------------------------------------------------

(lambda M.project-week [plan ?opts]
  "Monte Carlo projection of how many BiS slots this week's plan fills by reset.
   Pure + deterministic for a given seed -- no clock, no math.random (a seeded
   MINSTD generator is built internally). Collapses each target item into a
   per-slot 'any upgrade this week' Bernoulli (slot-fill-probs), then samples it
   via drop-chance.coupon-collector-mc.
   Domain:  plan  : {:steps [plan-row ...]} -- the M.plan-week result
            ?opts : {:sims ?integer >0 :seed ?integer} (defaults 1000 / 1)
   Returns: {:p10 :p50 :p90 :slots integer} -- p10/p50/p90 are fractions in
            [0,1] of distinct target slots filled by reset; :slots is that slot
            count. {:p10 0 :p50 0 :p90 0 :slots 0} when the plan targets none."
  (let [sims (or (and ?opts ?opts.sims) default-sims)
        seed (or (and ?opts ?opts.seed) default-seed)
        probs (slot-fill-probs (or (and plan plan.steps) []))
        items (icollect [slot p (pairs probs)] {: slot : p})]
    (if (= 0 (length items))
        {:p10 0 :p50 0 :p90 0 :slots 0}
        (let [rng (chance.make-rng seed)
              mc (chance.coupon-collector-mc items 1 sims rng)]
          {:p10 mc.p10 :p50 mc.p50 :p90 mc.p90 :slots (length items)}))))

(lambda M.plan-week [player ctx]
  "Build this week's recommended route for a player.
   Pure and deterministic -- same (player, ctx) always yields the same plan.
   Each step is a plan.plan-week row (so the Plan tab renders it directly);
   :score sums the steps' slot-weighted scores and :est-minutes their lengths.
   Domain:  player : schemas.Player -- level + attunements + reputations, for the
                     activity requirement / availability gate
            ctx    : schemas.RouteContext -- {:class :spec :phase :now
                     :owned-items :lockouts :weights? :competitors?
                     :default-competitors? :seed? :include-classic?}
   Returns: {:steps [plan-row ...]  -- available, item-bearing activities,
                                       score desc (ties: minutes asc, name, id);
                                       each row carries its :attunement slug (or
                                       nil) so the UI can attach an advisory
             :score number          -- Σ step :score
             :est-minutes number}   -- Σ step :minutes
   Errors:  if player or ctx fails its schema at the boundary."
  (validate.assert! schemas.Player player :route/player)
  (validate.assert! schemas.RouteContext ctx :route/ctx)
  (let [catalog (icollect [_ adef (ipairs (activities.all))]
                  (candidate-activity player ctx adef))
        attune-by-id (collect [_ a (ipairs catalog)]
                       (values a.id a.attunement))
        steps (plan.plan-week catalog (make-scorer ctx))
        score (accumulate [s 0 _ row (ipairs steps)] (+ s row.score))
        est-minutes (accumulate [m 0 _ row (ipairs steps)] (+ m row.minutes))]
    ;; plan.plan-week rebuilds rows with its own field set, so re-attach the
    ;; activity's attunement slug (the UI keys the "not attuned" advisory on it).
    (each [_ s (ipairs steps)]
      (tset s :attunement (. attune-by-id s.id)))
    {: steps : score : est-minutes}))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.route` after plan
;; and the data modules it reads. In tests, consumers fall through to
;; `(require :src.domain.route)` which returns the same M.

(set _G.Routina Routina)
(set Routina.route M)

M
