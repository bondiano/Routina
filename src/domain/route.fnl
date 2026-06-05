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
;; activity, where p = effective-rate(base-drop-p, competitors). Competitors are
;; per-item when ctx.composition is set (PRD OQ-3 resolved: roles contending for
;; the item per src/domain/competition.fnl, headcount from the player's raid
;; composition scaled to the activity's group size). Decisions baked
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
(local competition (or Routina.competition (require :src.domain.competition)))
(local goals (or Routina.goals (require :src.domain.goals)))

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

;; Planned clears per reset cadence live in goals.runs-before-reset (Phase 7):
;; a weekly raid is one clear; a daily instance offers one run per day left
;; before ctx.reset-at (deadline-aware, OQ-11) or the casual 4-nights default
;; when the reset is unknown; :none is one-shot.

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
                   :world-boss "World Boss"
                   :custom :Custom})

(local reset-label {:weekly "weekly reset"
                    :daily "daily reset"
                    :none "no reset"})

;; --- Helpers (private) -----------------------------------------------------

(fn planned-runs [adef ctx]
  "Planned clears of an activity over the week, deadline-aware when the
   RouteContext knows the next reset (goals.runs-before-reset)."
  (goals.runs-before-reset adef ctx.now ctx.reset-at))

(fn weight-for [ctx slot]
  "The player's tuning weight for a gear slot (default 1 when unset)."
  (or (and ctx.weights (. ctx.weights slot)) default-slot-weight))

;; Non-instanced content (guaranteed pickups: badge vendor, quest rewards,
;; dailies, rep hubs) is uncontested -- nobody rolls against you on a vendor
;; purchase. Exempt from the composition / global-slider paths below; only an
;; explicit per-activity override (the user's own statement) still applies.
(local uncontested-types {:vendor true
                          :weekly-quest true
                          :daily true
                          :rep-hub true})

(fn scaled-composition [composition group-size]
  "The player's raid composition rescaled to an activity's group size, so a
   25-man composition contests a 10-man Kara drop with ~0.4x the headcount.
   Fractional counts are intentional (competition.competitors-for-item floors
   the final pool at 1). nil group-size returns the composition unchanged."
  (if (= group-size nil)
      composition
      (let [total (accumulate [sum 0 _ n (pairs composition)] (+ sum n))
            factor (/ group-size (math.max 1 total))]
        (collect [role n (pairs composition)]
          (values role (* n factor))))))

(fn competitors-for [ctx adef item-id]
  "The competition pool for one drop. Precedence (most specific wins):
   an explicit per-activity override; 1 for uncontested content types; the
   by-role composition model (contending roles from the BiS catalog, headcount
   from ctx.composition scaled to adef.group-size); the options panel's global
   :default-competitors slider; 1."
  (or (and ctx.competitors (. ctx.competitors adef.id))
      (and (. uncontested-types adef.type) 1)
      (and ctx.composition
           (competition.competitors-for-item item-id
                                             (scaled-composition ctx.composition
                                                                 adef.group-size)))
      ctx.default-competitors default-competitors))

(fn owned? [ctx item-id]
  "True iff the player already holds this item-id."
  (and ctx.owned-items (not= nil (. ctx.owned-items item-id))))

(fn show-item? [ctx item-id]
  "Whether an item may be recommended: never if hard-excluded (Atiesh), and
   pre-TBC gear only when ctx.include-classic? opts it in."
  (and (not (. excluded-item-ids item-id))
       (or ctx.include-classic? (>= item-id classic-item-id-cutoff))))

;; Gearing-up threshold (ROADMAP Phase 4b): below this fraction of endgame :bis
;; slots filled, the player is still "on the road" and pre-raid catch-up gear is
;; worth surfacing in the weekly plan alongside raid BiS. At or above it, the
;; pre-raid tail is dropped -- a near-BiS player has no use for dungeon blues.
(local gearing-up-bis-fraction 0.5)

(fn gearing-up? [ctx]
  "True when the player still lacks most of their endgame BiS for this phase, so
   the plan should also point at the dungeons / heroics / rep that move a
   fresh-70 forward. Derived from owned-set, not a manual toggle (UX §9)."
  (let [bis (bis-catalog.by-class-spec ctx.class ctx.spec)
        counts (accumulate [acc {:total 0 :owned 0} _ e (ipairs bis)]
                 (if (and (= e.kind :bis) (<= e.phase ctx.phase))
                     {:total (+ acc.total 1)
                      :owned (+ acc.owned (if (owned? ctx e.item.id) 1 0))}
                     acc))]
    (or (= counts.total 0)
        (< counts.owned (* gearing-up-bis-fraction counts.total)))))

(fn want-kind? [gearing? kind]
  "Whether a BiS entry of this provenance belongs in the plan's candidate set:
   endgame :bis always; :pre-raid catch-up only while gearing up."
  (or (= kind :bis) (and gearing? (= kind :pre-raid))))

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
       :runs (planned-runs adef ctx)
       :p (chance.effective-rate entry.base-drop-p
                                 (competitors-for ctx adef item-id))})))

(fn gap-items [ctx adef gearing?]
  "TargetItems for the player's UNOWNED, wanted BiS items (phase <= ctx.phase)
   that drop from this activity, in catalog order. Untracked / owned / off-source
   / off-kind items fall away, so an empty result means 'nothing here for this
   player'. :pre-raid catch-up gear is admitted only while `gearing?` (see
   gearing-up?); endgame :bis always. Multiple ranked items may share a slot --
   make-scorer combines them so alternatives back each other up without
   double-counting the slot."
  (let [bis (bis-catalog.by-class-spec ctx.class ctx.spec)]
    (icollect [_ e (ipairs bis)]
      (when (and (<= e.phase ctx.phase) (want-kind? gearing? e.kind)
                 (not (owned? ctx e.item.id)) (show-item? ctx e.item.id))
        (target-item ctx adef e)))))

(fn candidate-activity [player ctx adef gearing? goal-scorer]
  "A plan-ready Activity for one content def, or nil to drop it from the plan.
   Kept only when the player can run it this week (activities.available?) AND
   it either drops a wanted item or pays toward an active goal (Phase 7) --
   a badge-dense heroic with no BiS left still belongs in a badge-goal week.
   A player-authored :custom entry (Phase 8) is ALWAYS kept: the author put it
   in their routine; with no yields toward an active goal it honestly scores 0
   and sinks to the tail."
  (when (activities.available? adef player
                               (and ctx.lockouts (. ctx.lockouts adef.id))
                               ctx.now)
    (let [items (gap-items ctx adef gearing?)]
      (when (or (> (length items) 0) (goal-scorer.relevant? adef.id)
                (= adef.type :custom))
        {:id adef.id
         :name adef.name
         :type (or (. type-label adef.type) (tostring adef.type))
         :detail (or (. reset-label adef.reset) (tostring adef.reset))
         :minutes adef.length-estimate
         :attunement (?. adef :requirements :attunement)
         : items}))))

(fn make-scorer [ctx goal-scorer]
  "A slot-weighted composite scorer to inject into plan.plan-week.
   score(activity) = Σ_slot weight(slot) · P(any candidate for that slot drops
   this week) + the deadline-aware goal term (goals.make-goal-scorer, Phase 7).
   Ranked alternatives sharing a slot combine via the complement product (slot
   filled if ANY of its items drops), so a slot is worth at most its single
   weighted contribution -- alternatives back each other up without
   double-counting the slot. Reduces to the per-item sum when every slot is
   unique and every weight is 1; with no active goals the goal term is zero,
   so goal-free plans are unchanged."
  (fn [activity]
    (let [by-slot {}]
      (each [_ item (ipairs activity.items)]
        (let [slot (or item.slot :_noslot)
              p-week (chance.at-least-one item.p item.runs)
              prior (or (. by-slot slot) 0)]
          (tset by-slot slot (- 1 (* (- 1 prior) (- 1 p-week))))))
      (+ (accumulate [total 0 slot p (pairs by-slot)]
           (+ total (* (weight-for ctx slot) p)))
         (goal-scorer.score activity.id)))))

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
                     :composition? :default-competitors? :seed?
                     :include-classic? :goals? :goal-progress? :gold-bands?
                     :reset-at? :custom-activities? :custom-yields?
                     :plan-edits?}
   Returns: {:steps [plan-row ...]  -- available, item-bearing activities,
                                       pinned ids first (pin order), then
                                       score desc (ties: minutes asc, name, id);
                                       each row carries its :attunement slug (or
                                       nil) so the UI can attach an advisory
             :score number          -- Σ step :score
             :est-minutes number}   -- Σ step :minutes
   Errors:  if player or ctx fails its schema at the boundary."
  (validate.assert! schemas.Player player :route/player)
  (validate.assert! schemas.RouteContext ctx :route/ctx)
  (let [gearing? (gearing-up? ctx)
        goal-scorer (goals.make-goal-scorer ctx.goals ctx)
        ;; The candidate universe: the static registry plus the player's
        ;; custom entries (Phase 8), competing as equals. Skipped activities
        ;; (PlanEdits :skips, Phase 8 §2) never enter it.
        adefs (activities.all)
        _ (each [_ adef (ipairs (or ctx.custom-activities []))]
            (table.insert adefs adef))
        skips (or (?. ctx :plan-edits :skips) {})
        catalog (icollect [_ adef (ipairs adefs)]
                  (when (not= true (. skips (tostring adef.id)))
                    (candidate-activity player ctx adef gearing? goal-scorer)))
        attune-by-id (collect [_ a (ipairs catalog)]
                       (values a.id a.attunement))
        steps (plan.plan-week catalog (make-scorer ctx goal-scorer)
                              (?. ctx :plan-edits :pins))
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
