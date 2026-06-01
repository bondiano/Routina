;; bis-catalog.fnl -- aggregate the generated per-spec BiS modules into queries.
;;
;; PURE domain module: no WoW API, no time, no random, no mutation of inputs.
;; The data lives in the generated src/domain/bis/<class>-<spec>.fnl modules
;; (see scripts/import-bis.lua, vendor/bis-source/README.md). Each registers its
;; entries into Routina.bis-by-spec; this module flattens them, validates the
;; whole set once against schemas.BisItem at load, and exposes read-only queries.
;;
;; Aggregation respects the addon's no-require-in-scope rule: in-game the .toc
;; loads every per-spec module (and manifest) BEFORE this one, so the accumulator
;; is already populated. Under busted we require each manifest entry on demand
;; (the same dual-mode `(or Routina.x (require ...))` idiom the other modules use).

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; --- Load + flatten (private) ----------------------------------------------

(fn ensure-loaded []
  "Guarantee every per-spec module has registered into Routina.bis-by-spec.
   Returns {:manifest [class-spec ...] :by-spec {class-spec [BisItem ...]}}."
  (let [manifest (or Routina.bis-manifest (require :src.domain.bis.manifest))]
    (each [_ name (ipairs manifest)]
      (when (= nil (?. Routina.bis-by-spec name))
        (require (.. :src.domain.bis. name))))
    {: manifest :by-spec (or Routina.bis-by-spec {})}))

(fn build-registry []
  "Flatten the per-spec accumulator into one immutable sequence, in manifest
   order (class order, then spec alpha, then each spec's phase/slot/priority)."
  (let [{: manifest : by-spec} (ensure-loaded)
        registry []]
    (each [_ name (ipairs manifest)]
      (each [_ e (ipairs (or (. by-spec name) []))]
        (table.insert registry e)))
    registry))

(local registry (build-registry))

;; Load-time boundary check: every entry conforms to schemas.BisItem. Runs once
;; at module load (never in a query / hot loop), mirroring activities.fnl.
(each [_ e (ipairs registry)]
  (let [r (validate.check schemas.BisItem e)]
    (assert r.ok
            (.. "bis-catalog: invalid entry " (tostring (?. e :item :id)) ": "
                (table.concat (or r.errors []) "; ")))))

;; --- Public API ------------------------------------------------------------

(lambda M.all []
  "Every BisItem in the catalog as a fresh shallow-copied sequence.
   Domain:  (none)
   Returns: [BisItem] -- a new sequence; callers may not mutate the registry."
  (icollect [_ e (ipairs registry)] e))

(lambda M.by-class-spec [class spec]
  "Every BisItem for a (class, spec) pair.
   Domain:  class : class keyword (:warrior ..); spec : spec keyword (:shadow ..)
   Returns: [BisItem] -- fresh sequence, possibly empty."
  (icollect [_ e (ipairs registry)]
    (when (and (= e.class class) (= e.spec spec)) e)))

(lambda M.by-class-spec-phase [class spec phase]
  "BisItem entries for (class, spec) at a given content phase.
   Domain:  class, spec : keywords; phase : integer >= 1
   Returns: [BisItem] -- fresh sequence, possibly empty."
  (icollect [_ e (ipairs registry)]
    (when (and (= e.class class) (= e.spec spec) (= e.phase phase)) e)))

(lambda M.by-slot [class spec slot]
  "BisItem entries for (class, spec) in one gear slot, in source-Priority order.
   Domain:  class, spec : keywords; slot : slot keyword (:head .. :ranged)
   Returns: [BisItem] -- fresh sequence, possibly empty."
  (icollect [_ e (ipairs registry)]
    (when (and (= e.class class) (= e.spec spec) (= e.slot slot)) e)))

(lambda M.primary-for-slot [class spec phase slot]
  "The primary (first-Priority) BisItem for (class, spec, phase, slot).
   Domain:  class, spec, slot : keywords; phase : integer >= 1
   Returns: BisItem, or nil if the slot has no entry for that phase."
  (var found nil)
  (each [_ e (ipairs registry)]
    (when (and (= nil found) (= e.class class) (= e.spec spec)
               (= e.phase phase) (= e.slot slot))
      (set found e)))
  found)

(lambda M.specs-for-class [class]
  "Distinct spec keywords present for a class, in catalog order.
   Domain:  class : class keyword (:warrior ..)
   Returns: [spec-keyword] -- fresh sequence, possibly empty."
  (let [seen {}
        out []]
    (each [_ e (ipairs registry)]
      (when (and (= e.class class) (not (. seen e.spec)))
        (tset seen e.spec true)
        (table.insert out e.spec)))
    out))

;; --- Register into the addon namespace -------------------------------------

(set _G.Routina Routina)
(set Routina.bis-catalog M)

M
