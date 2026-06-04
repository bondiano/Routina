;; options.fnl -- the AceConfig options panel (the ONE place AceGUI is allowed).
;;
;; Split per UI.md: M.options-table is a PURE builder (busted-tested) that turns
;; a small api -- a route-options table to read/write plus the spec/attunement
;; choices -- into an AceConfig options spec; M.register!/M.open! are the impure
;; shell that resolves the Ace3 config libs and binds the panel to addon.db. Both
;; degrade to a no-op when the config libs aren't present (headless tests).
;;
;; Settings live in db.char.preferences.route, which src/core/planner.fnl already
;; feeds to the planner, so changing one and hitting `set` re-plans live via the
;; injected on-change (src/ui/root.fnl refresh!). See PRD §6.5, ROADMAP Phase 3.

(local Routina (or _G.Routina {}))
(local root (or Routina.root (require :src.ui.root)))
(local LibStub _G.LibStub)

(local M {})

;; --- Static choices (pure) -------------------------------------------------

;; Gear slots in BiS-catalog order (schemas.BisItem :slot enum); weight 1..5.
(local slots [:head
              :neck
              :shoulder
              :back
              :chest
              :wrist
              :hands
              :waist
              :legs
              :feet
              :ring1
              :ring2
              :trinket1
              :trinket2
              :main-hand
              :off-hand
              :ranged])

;; The five raid attunements with a verified quest (src/domain/ctx.fnl). Toggles
;; let a player force gating/advising on a pre-removal phase; defaults stay off.
(local attune-rows
       [{:slug :kara-key :label :Karazhan}
        {:slug :ssc-attune :label "Serpentshrine Cavern"}
        {:slug :tk-attune :label "Tempest Keep"}
        {:slug :hyjal-vials :label "Mount Hyjal"}
        {:slug :bt-medallion :label "Black Temple"}])

;; --- Pure helpers ----------------------------------------------------------

(fn ensure-sub! [db key]
  "Return db[key], creating an empty sub-table on first write."
  (when (= nil (. db key)) (tset db key {}))
  (. db key))

(fn spec-values [specs]
  "AceConfig select {key label} from the class's specs, plus an auto sentinel."
  (let [out {:auto "Auto-detect (talents)"}]
    (each [_ s (ipairs specs)]
      (tset out (tostring s.value) s.text))
    out))

(fn weights-group [db changed]
  "Inline group of one 1..5 weight slider per gear slot."
  {:type :group
   :name "Slot weights"
   :inline true
   :order 4
   :args (collect [i slot (ipairs slots)]
           (values (tostring slot)
                   {:type :range
                    :name (tostring slot)
                    :order i
                    :min 1
                    :max 5
                    :step 1
                    :get (fn [_] (or (?. db :weights slot) 1))
                    :set (fn [_ v]
                           (tset (ensure-sub! db :weights) slot v)
                           (changed))}))})

(fn attune-args [db changed]
  "Per-attunement gate?/advise? toggles, keyed <slug>-gate / <slug>-advise."
  (let [args {}]
    (each [i row (ipairs attune-rows)]
      (let [slug row.slug]
        (tset args (.. (tostring slug) :-advise)
              {:type :toggle
               :name (.. row.label ": advise if missing")
               :order (* i 2)
               :get (fn [_] (= true (?. db :attune slug :advise?)))
               :set (fn [_ v]
                      (tset (ensure-sub! (ensure-sub! db :attune) slug)
                            :advise? v)
                      (changed))})
        (tset args (.. (tostring slug) :-gate)
              {:type :toggle
               :name (.. row.label ": hide if not attuned")
               :order (+ 1 (* i 2))
               :get (fn [_] (= true (?. db :attune slug :gate?)))
               :set (fn [_ v]
                      (tset (ensure-sub! (ensure-sub! db :attune) slug) :gate?
                            v)
                      (changed))})))
    args))

;; --- Public API ------------------------------------------------------------

(lambda M.options-table [api]
  "Build the AceConfig options spec.
   Domain:  api : {:db {route-options table, mutated by :set closures}
                   :specs [{:value keyword :text string} ...]  -- spec choices
                   :on-change (fn []) | nil  -- fired after any :set (re-plan)}
   Returns: an AceConfig options group table."
  (let [db api.db
        changed (fn [] (when api.on-change (api.on-change)))]
    {:type :group
     :name :Routina
     :args {:spec {:type :select
                   :name :Specialization
                   :order 1
                   :values (spec-values (or api.specs []))
                   :get (fn [_] (or db.spec :auto))
                   :set (fn [_ v]
                          (tset db :spec (if (= v :auto) nil v))
                          (changed))}
            :phase {:type :range
                    :name "Content phase"
                    :order 2
                    :min 1
                    :max 5
                    :step 1
                    :get (fn [_] (or db.phase 3))
                    :set (fn [_ v] (tset db :phase v) (changed))}
            :competitors {:type :range
                          :name "Loot competitors (per drop)"
                          :order 3
                          :min 1
                          :max 8
                          :step 1
                          :get (fn [_] (or db.default-competitors 1))
                          :set (fn [_ v]
                                 (tset db :default-competitors v)
                                 (changed))}
            :seed {:type :range
                   :name "Projection seed"
                   :desc "Monte Carlo seed for the weekly fill projection. Change it to resample; the same seed always projects identically."
                   :order 6
                   :min 1
                   :max 9999
                   :step 1
                   :get (fn [_] (or db.seed 1))
                   :set (fn [_ v] (tset db :seed v) (changed))}
            :include-classic {:type :toggle
                              :name "Include pre-TBC (Classic) drops"
                              :desc "Show gear from vanilla content (Naxx40, AQ, Blackrock, etc.). Off by default. Atiesh is never suggested."
                              :order 8
                              :get (fn [_] (= true db.include-classic?))
                              :set (fn [_ v]
                                     (tset db :include-classic? v)
                                     (changed))}
            :track-luck {:type :toggle
                         :name "Track loot luck (experimental)"
                         :desc "Record boss kills and your loot to compute a Bayesian luck score. Off by default."
                         :order 7
                         :get (fn [_] (= true db.track-luck?))
                         :set (fn [_ v]
                                (tset db :track-luck? v)
                                (when (?. Routina :events
                                          :set-history-tracking!)
                                  (Routina.events.set-history-tracking! v))
                                (changed))}
            :weights (weights-group db changed)
            :attune {:type :group
                     :name "Attunement gating"
                     :inline true
                     :order 5
                     :args (attune-args db changed)}}}))

;; --- Impure registration (guarded: no-op without the config libs) ----------

(fn route-db [addon]
  "addon.db.char.preferences.route, created empty on first access."
  (let [prefs (?. addon :db :char :preferences)]
    (when prefs
      (when (= nil prefs.route) (set prefs.route {}))
      prefs.route)))

(fn class-specs [addon]
  "Spec choices for the current class, or [] when the catalog isn't reachable."
  (let [bis (or Routina.bis-catalog nil)
        wow (or Routina.wow nil)]
    (if (and bis wow)
        (let [class (?. (wow.player-info) :class)]
          (icollect [_ s (ipairs (bis.specs-for-class class))]
            {:value s :text (tostring s)}))
        [])))

(lambda M.register! [addon]
  "Register and bind the options panel to addon.db. No-op if the AceConfig libs
   or the DB aren't available (so headless tests stay quiet).
   Domain:  addon : the AceAddon object (has :db)
   Returns: true when registered, false otherwise."
  (let [AceConfig (and LibStub (LibStub :AceConfig-3.0 true))
        AceConfigDialog (and LibStub (LibStub :AceConfigDialog-3.0 true))
        db (route-db addon)]
    (if (and AceConfig AceConfigDialog db)
        (let [table (M.options-table {: db
                                      :specs (class-specs addon)
                                      :on-change root.refresh!})
              AceDBOptions (and LibStub (LibStub :AceDBOptions-3.0 true))]
          (when (and AceDBOptions addon.db)
            (tset table.args :profiles
                  (let [p (AceDBOptions:GetOptionsTable addon.db)]
                    (tset p :order 100)
                    p)))
          (AceConfig:RegisterOptionsTable :Routina table)
          (AceConfigDialog:AddToBlizOptions :Routina :Routina)
          true)
        false)))

(lambda M.open! []
  "Open the options panel, if the config dialog lib is present.
   Returns: true when opened, false otherwise."
  (let [AceConfigDialog (and LibStub (LibStub :AceConfigDialog-3.0 true))]
    (if AceConfigDialog
        (do
          (AceConfigDialog:Open :Routina) true)
        false)))

;; --- Register into the addon namespace -------------------------------------

(set _G.Routina Routina)
(set Routina.options M)

M
