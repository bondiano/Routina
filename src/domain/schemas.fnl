;; schemas.fnl -- declarative domain type definitions (single source of truth).
;;
;; PURE data module. No WoW API, no functions, no I/O -- just the shapes that
;; every other layer agrees on. One schema serves three masters:
;;   - src/domain/validate.fnl   -> runtime validation at module boundaries
;;   - /docgen                    -> docs/api.md type tables
;;   - spec/helpers/gen.fnl       -> test-fixture generators
;;
;; Field-type DSL (see .claude/examples/07-type-contracts.fnl PART 3):
;;   :string :number :integer :boolean   -- scalars (keywords are :string)
;;   {:field <ftype> ...}                 -- inline record schema
;;   [:enum :a :b :c]                     -- one of these literal keywords
;;   [:list <ftype>]                      -- sequence of items matching ftype
;;   [:map <key-ftype> <val-ftype>]       -- table with typed keys and values
;;   [:ref :OtherSchema]                  -- reference to a schema in this table
;;   [:optional <ftype>]                  -- field may be nil
;;
;; Keep this file pure data: validation logic lives in validate.fnl so the
;; schemas stay reflectable (iterate fields, derive docs, build fixtures).

(local M {})

;; Reputation ladder, low -> high (full TBC standing set). Held as a plain
;; local, not a registered schema: a bare [:enum ...] vector is not a record,
;; and schemas_spec asserts every entry in M is a non-empty record. Inlined
;; into Player.reputations and RepRequirement.standing below.
(local standing-enum [:enum
                      :hated
                      :hostile
                      :unfriendly
                      :neutral
                      :friendly
                      :honored
                      :revered
                      :exalted])

;; --- Leaf shapes -----------------------------------------------------------

(set M.Item {:id :integer :name :string})

(set M.Encounter {:name :string :killed? :boolean})

;; --- Lockouts (fed by src/core/events.fnl in Phase 2) ----------------------

;; Two lockout shapes, on purpose:
;;   Lockout      -- the RAW record as WoW's RequestRaidInfo reports it. The
;;                   imperative shell (src/core/events.fnl) receives this.
;;   LockoutView  -- the PLANNER-facing projection src/domain/lockouts.fnl
;;                   operates on. The shell maps raw -> view on ingest and
;;                   validates the result with `(validate.assert! LockoutView v)`.
;; :id is normalised to a string key at the boundary (owner+instance), so a
;; lockout is addressable regardless of whether WoW gave a numeric instance id.

(set M.Lockout {:name :string
                :instance-id :integer
                :reset-at :integer
                :difficulty [:enum :normal :heroic]
                :is-raid? :boolean
                :encounters [:list [:ref :Encounter]]})

(set M.LockoutView {:id :string
                    :expiry :integer
                    :bosses-killed :integer
                    :bosses-total :integer
                    :owner :string})

;; --- Planner inputs (consumed by src/domain/plan.fnl) ----------------------
;;
;; TargetItem mirrors the per-item shape plan.fnl scores; :item-id is carried
;; through verbatim so the UI can drive GameTooltip:SetItemByID.

(set M.TargetItem {:label :string
                   :p :number
                   :runs :integer
                   :item-id [:optional :integer]})

(set M.Activity {:id :string
                 :name :string
                 :type :string
                 :detail :string
                 :minutes :number
                 :items [:list [:ref :TargetItem]]})

;; --- Player (consumed by activities/route requirement checks) --------------
;;
;; The character state a requirement check reads. :attunements is a set
;; ({:kara-key true}); :reputations maps a faction key to a standing.

(set M.Player {:level :integer
               :attunements [:map :string :boolean]
               :reputations [:map :string standing-enum]})

;; --- Activity registry (consumed by src/domain/activities.fnl) -------------
;;
;; ActivityDef is the STATIC content registry: what weekly content exists, its
;; reset cadence, and prerequisites. Distinct from the scored, plan-facing
;; `Activity` above (which plan.fnl renders); the two share ids (:karazhan ...)
;; so a scored row can be traced back to its definition. Reputation hubs are
;; modelled as activities (PRD OQ-4 resolved): :rep-hub is a live type and
;; :requirements carries an optional :rep gate.

(set M.ActivityDef
     {:id :string
      :name :string
      :type [:enum :raid :heroic :daily :weekly-quest :rep-hub]
      :reset [:enum :weekly :daily :none]
      :length-estimate :integer
      :requirements [:ref :ActivityRequirements]})

(set M.ActivityRequirements
     {:min-level :integer
      :attunement [:optional :string]
      :rep [:optional [:ref :RepRequirement]]})

(set M.RepRequirement {:faction :string :standing standing-enum})

;; --- BiS catalog -----------------------------------------------------------

(set M.BisItem {:class [:enum
                        :warrior
                        :paladin
                        :priest
                        :mage
                        :warlock
                        :druid
                        :rogue
                        :hunter
                        :shaman]
                :spec :string
                :phase :integer
                :slot [:enum
                       :head
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
                       :ranged]
                :item [:ref :Item]
                :sources [:list
                          {:instance :string
                           :boss [:optional :string]
                           :drop-rate [:optional :number]}]})

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, the .toc load order populates `_G.Routina.schemas`
;; before validate.fnl and the domain modules that read it. In tests,
;; consumers fall through to `(require :src.domain.schemas)` -> the same M.

(local Routina (or _G.Routina {}))
(set _G.Routina Routina)
(set Routina.schemas M)

M
