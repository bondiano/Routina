;; ctx.fnl -- pure assembler: raw client snapshot -> (player, RouteContext).
;;
;; The seam between the imperative shell (src/core/wow.fnl scans the live client)
;; and src/domain/route.fnl. Given an already-gathered raw snapshot plus two
;; injected lookup closures for the genuinely impure bits, it produces the
;; schemas.Player + schemas.RouteContext that route.plan-week consumes.
;;
;; PURE domain module:
;;   - No WoW API, no mutation of inputs, no I/O, no time, no random. `now`
;;     arrives in the snapshot; impurity is confined to the injected
;;     `quest-completed?` / `faction-standing` closures (the shell wraps the WoW
;;     globals; tests pass fakes). Same snapshot + same closures -> same output.
;;   - Validates both outputs against their schemas at this WoW->domain boundary.
;;
;; The data tables below (class talent-tree -> spec slug, attunement -> quest id,
;; faction -> id, instance name -> activity id) are plain data, so the mapping
;; logic stays reflectable and busted-testable. See docs/ROADMAP.md Phase 2 §5
;; and .claude/examples/01-pure-module/.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; --- Static data (pure) ----------------------------------------------------

;; Content phase the catalog is scored against when options carry no override.
;; Bump per TBC Anniversary content phase, in step with the .toc Interface
;; number (CLAUDE.md). Drives route's `phase <= ctx.phase` BiS gate.
(local default-phase 3)

;; Class -> spec slug per talent tab (TBC tab order 1,2,3). Slugs MUST match the
;; :spec field in the BiS catalog (src/domain/bis/*). Ambiguous trees resolve to
;; a documented DEFAULT (feral -> dps, warrior Protection -> threat, paladin
;; Protection -> the single :protection list, priest Disc+Holy -> :holy); the
;; player overrides via options.spec when the guess is wrong.
(local class-spec-trees
       {:warrior [:arms :fury :protection-threat]
        :paladin [:holy :protection :retribution]
        :hunter [:beast-mastery :marksmanship :survival]
        :rogue [:any :any :any]
        :priest [:holy :holy :shadow]
        :shaman [:elemental :enhancement :restoration]
        :mage [:arcane :fire :frost]
        :warlock [:affliction :demonology :destruction]
        :druid [:balance :feral-dps :restoration]})

;; Attunement slug (as used by src/domain/activities.fnl :requirements) -> the
;; quest id whose completion proves attunement. IDs are TODO VERIFY: until a
;; verified id lands, the slug maps to `false` (NOT nil -- a nil value would drop
;; the key from this table entirely) and attunement-set assumes attuned, so the
;; planner never wrongly HIDES a raid. Replace a `false` with the real quest id
;; from warcraft.wiki.gg / Wowhead Classic and detection turns on, no other
;; code change.
(local attune-quests {:kara-key false
                      ;; TODO verify: Karazhan "The Master's Key" chain
                      :ssc-attune false
                      ;; TODO verify: Serpentshrine Cavern attunement
                      :tk-attune false
                      ;; TODO verify: Tempest Keep / The Eye attunement
                      :bt-medallion false
                      ;; TODO verify: Black Temple "Medallion of Karabor"
                      :hyjal-vials false
                      ;; TODO verify: Hyjal "The Vials of Eternity"
                      :heroic-flamewrought false
                      ;; TODO verify: Flamewrought Key
                      :heroic-auchindoun false})

;; TODO verify: Auchindoun heroic key

;; Reputation faction slug (as used by activities :rep gates) -> WoW faction id.
;; :ogrila = 1038 (verified: wowhead.com/tbc/faction=1038/ogrila).
(local faction-ids {:ogrila 1038})

;; WoW GetFactionInfoByID standingId (1..8) -> our standing keyword.
(local standing-by-id [:hated
                       :hostile
                       :unfriendly
                       :neutral
                       :friendly
                       :honored
                       :revered
                       :exalted])

;; Saved-instance name (enUS; v1 ships enUS only, PRD §6.7) -> activity id, so a
;; raw lockout reconciles to the ActivityDef it belongs to. Unmapped instances
;; (heroics, untracked raids) carry no lockout -> route treats them as open.
(local instance->activity
       {:Karazhan :karazhan
        "Serpentshrine Cavern" :serpentshrine-cavern
        "The Eye" :tempest-keep
        "Tempest Keep" :tempest-keep
        "Black Temple" :black-temple
        "The Battle for Mount Hyjal" :hyjal-summit
        "Hyjal Summit" :hyjal-summit
        "Gruul's Lair" :gruuls-lair
        "Magtheridon's Lair" :magtheridons-lair})

;; --- Helpers (private) -----------------------------------------------------

(fn dominant-tree [talent-points]
  "Index (1..3) of the talent tab with the most points; ties to the lower tab,
   and an untalented character to tab 1."
  (var best 1)
  (var best-pts (or (. talent-points 1) 0))
  (for [i 2 3]
    (let [pts (or (. talent-points i) 0)]
      (when (> pts best-pts)
        (set best i)
        (set best-pts pts))))
  best)

(fn detect-spec [class talent-points ?override]
  "The catalog spec slug for a class: an explicit override wins, else the
   dominant talent tree mapped through class-spec-trees (with documented
   defaults for ambiguous trees)."
  (or ?override
      (let [trees (. class-spec-trees class)]
        (and trees (. trees (dominant-tree talent-points))))))

(fn owned-set [item-ids]
  "Set {item-id true} from a raw id list, dropping nils and empty (0) slots."
  (collect [_ id (ipairs (or item-ids []))]
    (when (and id (> id 0)) (values id true))))

(fn attunement-set [quest-completed?]
  "Set {slug true} of attunements the player holds. A slug with a verified quest
   id is gated on (quest-completed? id); a TODO-verify slug (nil id) is assumed
   held, so missing data never hides a raid."
  (collect [slug qid (pairs attune-quests)]
    (if qid
        (when (quest-completed? qid) (values slug true))
        (values slug true))))

(fn reputation-map [faction-standing]
  "Map {faction standing-keyword} for every tracked faction the player has a
   standing with; factions the lookup can't resolve are omitted (route's
   requirement check defaults a missing faction to :neutral)."
  (collect [faction fid (pairs faction-ids)]
    (let [sid (faction-standing fid)
          standing (and sid (. standing-by-id sid))]
      (when standing (values faction standing)))))

(fn killed-count [encounters]
  "How many of a lockout's encounters are already down."
  (accumulate [n 0 _ e (ipairs (or encounters []))]
    (if e.killed? (+ n 1) n)))

(fn lockout-views [raw-lockouts owner]
  "Map {activity-id-string LockoutView} from raw schemas.Lockout records, keyed
   by the activity each instance name reconciles to. Unmapped instances drop."
  (collect [_ lk (ipairs (or raw-lockouts []))]
    (let [activity (. instance->activity lk.name)]
      (when activity
        (values activity {:id activity
                          :expiry lk.reset-at
                          :bosses-killed (killed-count lk.encounters)
                          :bosses-total (length (or lk.encounters []))
                          : owner})))))

;; --- Public API ------------------------------------------------------------

(lambda M.build [snapshot]
  "Assemble (player, RouteContext) from a raw client snapshot.
   Pure aside from the two injected lookup closures; validates both outputs at
   this WoW->domain boundary.
   Domain:  snapshot : {:class string  -- lowercased class token (UnitClass)
                        :level integer  -- UnitLevel
                        :now integer    -- GetServerTime seconds
                        :talent-points [int int int]   -- points per talent tab
                        :owned-item-ids [int ...]      -- equipped+bags+bank ids
                        :raw-lockouts [Lockout ...]    -- wow.saved-instances
                        :owner string                  -- char key for lockouts
                        :quest-completed? (fn [qid] -> bool)
                        :faction-standing (fn [fid] -> standingId|nil)
                        :options {:spec ?kw :phase ?int
                                  :weights ?{} :competitors ?{}}}
   Returns: {:player schemas.Player :ctx schemas.RouteContext}
   Errors:  if the assembled player or ctx fails its schema."
  (let [opts (or snapshot.options {})
        player {:level snapshot.level
                :attunements (attunement-set snapshot.quest-completed?)
                :reputations (reputation-map snapshot.faction-standing)}
        ctx {:class snapshot.class
             :spec (detect-spec snapshot.class snapshot.talent-points opts.spec)
             :phase (or opts.phase default-phase)
             :now snapshot.now
             :owned-items (owned-set snapshot.owned-item-ids)
             :lockouts (lockout-views snapshot.raw-lockouts snapshot.owner)
             :weights opts.weights
             :competitors opts.competitors}]
    (validate.assert! schemas.Player player :ctx/player)
    (validate.assert! schemas.RouteContext ctx :ctx/ctx)
    {: player : ctx}))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.ctx` after schemas
;; and validate. In tests, consumers fall through to `(require :src.domain.ctx)`.

(set _G.Routina Routina)
(set Routina.ctx M)

M
