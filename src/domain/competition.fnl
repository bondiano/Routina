;; competition.fnl -- by-role loot-competition model (resolves PRD OQ-3).
;;
;; PURE domain module: no WoW API, no time, no random, no mutation of inputs.
;; Models "how many people roll on this drop" from two ingredients:
;;   1. A static spec -> role table (the only hand-authored mapping here).
;;   2. The BiS catalog itself: an item is contended by every role whose
;;      (class, spec) catalog lists it. Derived, never curated.
;; The player needs no "my role" input -- scored items come from their own
;; catalog, so their role always contends and is already counted inside the
;; composition's headcount for that role.
;;
;; Known bias: cross-role items (e.g. spell-hit rings wanted by both healers
;; and casters) accumulate every contending role's headcount, over-counting
;; competitors slightly. That errs conservative -- the planner under-promises,
;; never over-promises. Per-item overrides (the bis-curator overlay path) stay
;; open if live data shows it matters.
;;
;; Consumed by src/domain/route.fnl (per-item competitors feed
;; drop-chance.effective-rate) and src/ui/options.fnl (role list + default
;; composition for the "Raid composition" sliders).

(local Routina (or _G.Routina {}))
(local bis-catalog (or Routina.bis-catalog (require :src.domain.bis-catalog)))

(local M {})

;; --- Static data ------------------------------------------------------------

;; Loot-competition roles, in display order. Exported (read-only by
;; convention) so the options UI iterates the same taxonomy.
(local roles [:tank :healer :melee :ranged :caster])

;; A plausible 25-man TBC raid (sums to 25). Canonical default for the
;; options sliders; route only ever sees what the player actually stored.
(local default-composition {:tank 3 :healer 6 :melee 7 :ranged 4 :caster 5})

;; class-spec slug -> role. One row per bis/manifest.fnl entry (27); the
;; competition_spec drift-guard fails if the manifest grows past this table.
(local spec-role {:warrior-arms :melee
                  :warrior-fury :melee
                  :warrior-protection-mitigation :tank
                  :warrior-protection-threat :tank
                  :paladin-holy :healer
                  :paladin-protection :tank
                  :paladin-retribution :melee
                  :hunter-beast-mastery :ranged
                  :hunter-marksmanship :ranged
                  :hunter-survival :ranged
                  :rogue-any :melee
                  :priest-holy :healer
                  :priest-shadow :caster
                  :shaman-elemental :caster
                  :shaman-enhancement :melee
                  :shaman-restoration :healer
                  :mage-arcane :caster
                  :mage-fire :caster
                  :mage-frost :caster
                  :warlock-affliction :caster
                  :warlock-demonology :caster
                  :warlock-destruction :caster
                  :druid-balance :caster
                  :druid-feral-dps :melee
                  :druid-feral-tank-mitigation :tank
                  :druid-feral-tank-threat :tank
                  :druid-restoration :healer})

;; --- item-id -> contending-roles index (lazily memoized) --------------------

(fn slug-of [class spec]
  "Reconstruct the manifest slug from a catalog entry's split class/spec."
  (.. (tostring class) "-" (tostring spec)))

(fn build-role-index []
  "Fold the whole catalog (~5k entries) into {item-id {role true ...}}.
   Runs once per session (see `index`), never inside the scoring loop."
  (let [idx {}]
    (each [_ e (ipairs (bis-catalog.all))]
      (case (. spec-role (slug-of e.class e.spec))
        role (let [contending (or (. idx e.item.id) {})]
               (tset contending role true)
               (tset idx e.item.id contending))))
    idx))

;; Memo of a pure function over static generated data -- same cost class as
;; bis-catalog's own load-time flatten. Lazy (first call, not module load) so
;; it is safe under any .toc / busted load order and stays off the render
;; frame until the first plan is built.
(var role-index nil)

(fn index []
  (when (= role-index nil)
    (set role-index (build-role-index)))
  role-index)

;; --- Public API -------------------------------------------------------------

(lambda M.role-for-spec [class spec]
  "Contending role for a catalog (class, spec) pair.
   Domain:  class : keyword (:mage :druid ...); spec : keyword (:fire ...)
   Returns: role keyword (:tank :healer :melee :ranged :caster), or nil for
            a pair outside the catalog taxonomy."
  (. spec-role (slug-of class spec)))

(lambda M.contending-roles [item-id]
  "Roles whose BiS catalog lists this item.
   Domain:  item-id : integer
   Returns: {role true ...} -- fresh table; {} when no tracked spec wants it."
  (collect [r _ (pairs (or (. (index) item-id) {}))]
    (values r true)))

(lambda M.competitors-for-item [item-id composition]
  "Expected loot-competition pool for one item under a raid composition:
   the summed headcount of every contending role, floored at 1 (you alone).
   Domain:  item-id     : integer
            composition : {role -> headcount >= 0} (roles per M.roles;
                          fractional headcounts allowed -- group-size-scaled
                          compositions pass through unrounded)
   Returns: number >= 1 (satisfies drop-chance.effective-rate's contract)."
  (var sum 0)
  (each [r _ (pairs (or (. (index) item-id) {}))]
    (set sum (+ sum (or (. composition r) 0))))
  (math.max 1 sum))

;; Data exports (treat as read-only).
(set M.roles roles)
(set M.default-composition default-composition)

;; --- Register into the addon namespace -------------------------------------

(set _G.Routina Routina)
(set Routina.competition M)

M
