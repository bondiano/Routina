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
(local chains (or Routina.chains (require :src.domain.chains)))
(local goals (or Routina.goals (require :src.domain.goals)))
(local yields (or Routina.yields (require :src.domain.yields)))
(local history (or Routina.history (require :src.domain.history)))
(local activities (or Routina.activities (require :src.domain.activities)))
(local custom-activities
       (or Routina.custom-activities (require :src.domain.custom-activities)))

(local plan-edits (or Routina.plan-edits (require :src.domain.plan-edits)))

(local M {})

;; --- Static data (pure) ----------------------------------------------------

;; Content phase the catalog is scored against when options carry no override.
;; Bump per TBC Anniversary content phase, in step with the .toc Interface
;; number (CLAUDE.md). Drives route's `phase <= ctx.phase` BiS gate, so an item
;; (and the raid that drops it) only appears once its phase is live -- keep this
;; at the latest OPEN tier, else unreleased raids surface. Currently Phase 2
;; (T5: SSC + Tempest Keep open; Black Temple / Hyjal are Phase 3).
(local default-phase 2)

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

;; Attunement slug (as used by src/domain/activities.fnl :requirements) -> its
;; proof quest and whether to actually GATE on it. :quest-id values are verified
;; (sources below); :gate? is intentionally false everywhere because TBC removed
;; these raid entry requirements -- gating on a no-longer-required quest flag
;; would wrongly HIDE a raid from the planner. Flip a :gate? to true only for a
;; pre-removal phase where the attunement is genuinely enforced.
;;   kara-key     9837  Return to Khadgar (Master's Key). 2.4: key opens the
;;                      gate (one per raid), not required to enter -> don't gate.
;;   ssc-attune  10901  The Cudgel of Kar'desh. Entry req removed in 2.3.0.
;;   tk-attune   10888  Trial of the Naaru: Magtheridon. Removed in 2.4.0.
;;   hyjal-vials 10445  The Vials of Eternity. Removed in 2.4.0.
;;   bt-medallion 10985 A Distraction for Akama (Medallion of Karabor). Removed
;;                      in 2.4.0. NOTE: id is low-confidence (forum, not Wowhead)
;;                      -- reconfirm before ever gating on it.
;; Heroic keys (Flamewrought / Auchindoun) are reputation-granted items, never
;; removed, but are not a quest flag -- detection would be item/rep based, TODO.
;; :gate? hard-filters the raid (all false -- removed reqs); :advise? shows a
;; soft "not attuned" badge without hiding. Only Karazhan advises by default:
;; its key still opens the gate, so it is genuinely worth flagging. The removed
;; SSC/TK/Hyjal/BT attunements neither gate nor advise (a badge there would lie).
;; Both flags are options-overridable per attunement (see effective-attune).
(local attune-quests
       {:kara-key {:quest-id 9837
                   :gate? false
                   :advise? true
                   :advice-text "the Master's Key"}
        :ssc-attune {:quest-id 10901 :gate? false :advise? false}
        :tk-attune {:quest-id 10888 :gate? false :advise? false}
        :hyjal-vials {:quest-id 10445 :gate? false :advise? false}
        :bt-medallion {:quest-id 10985 :gate? false :advise? false}
        :heroic-flamewrought {:gate? false :advise? false}
        :heroic-auchindoun {:gate? false :advise? false}})

;; Attunement slug -> the chain id(s) in src/domain/chains that prove it.
;; Faction-variant chains (the importer suffixes -horde/-alliance) both map to
;; one slug: a character can only progress its own faction's chain, so "any
;; listed chain complete" is the held test. Precedence when deriving "held":
;; per-attunement options override (gate?/advise? flips, the manual escape
;; hatch) > chain completion > the legacy single proof-quest flag -- an alt
;; attuned before install still resolves via quest-completed?.
(local attune-chains
       {:kara-key [:karazhan]
        :ssc-attune [:serpentshrine-cavern]
        :tk-attune [:the-eye-horde :the-eye-alliance]
        :hyjal-vials [:mount-hyjal-horde :mount-hyjal-alliance]
        :bt-medallion [:black-temple-horde :black-temple-alliance]
        :heroic-flamewrought [:thrallmar-heroics-horde
                              :honor-hold-heroics-alliance]
        :heroic-auchindoun [:lower-city-heroics]})

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

;; Instance name -> activity id for the HEROIC-difficulty 5-mans the yield
;; tracker attributes visits to (Phase 7). Separate from instance->activity:
;; a 5-man only maps to a tracked activity on heroic difficulty (the normal
;; clear is neither a lockout nor a badge source); the two level-60 dungeons
;; below count on any difficulty.
(local heroic-instance->activity
       {"The Mechanar" :heroic-mech
        "Auchenai Crypts" :heroic-slabs
        "The Slave Pens" :the-slave-pens
        "The Shattered Halls" :the-shattered-halls
        "The Blood Furnace" :the-blood-furnace
        "Shadow Labyrinth" :shadow-labyrinth
        :Mana-Tombs :mana-tombs})

(local dungeon-instance->activity
       {"Dire Maul" :dire-maul "Blackrock Depths" :blackrock-depths})

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

(fn effective-attune [opts]
  "attune-quests merged with per-attunement option overrides. opts.attune is
   {slug {:gate? bool :advise? bool}}; an absent flag keeps the default."
  (let [ov (or (?. opts :attune) {})]
    (collect [slug base (pairs attune-quests)]
      (let [o (or (. ov slug) {})]
        (values slug
                {:quest-id base.quest-id
                 :advice-text base.advice-text
                 :gate? (if (= nil o.gate?) base.gate? o.gate?)
                 :advise? (if (= nil o.advise?) base.advise? o.advise?)})))))

(fn chain-attuned? [slug ?chain-progress]
  "Whether any chain proving this attunement slug is complete in the supplied
   {chain-id ChainProgress} map (nil map -> false, the pre-Phase-6 behaviour)."
  (let [chain-ids (. attune-chains slug)]
    (and (not= nil ?chain-progress) (not= nil chain-ids)
         (accumulate [hit false _ cid (ipairs chain-ids)]
           (or hit (let [chain (chains.by-id cid)
                         p (. ?chain-progress (tostring cid))]
                     (and (not= nil chain) (not= nil p)
                          (chains.chain-complete? chain p))))))))

(fn attunement-set [eff quest-completed? ?chain-progress]
  "Set {slug true} of attunements the player holds. A slug that opts into gating
   (:gate? true) is held when its chain is complete (chain-attuned?) or, as the
   legacy floor, when its proof quest is flagged done; every other slug is
   assumed held, so a removed-from-the-game attunement never hides a raid (see
   attune-quests / attune-chains for the per-attunement rationale)."
  (collect [slug entry (pairs eff)]
    (if entry.gate?
        (when (or (chain-attuned? slug ?chain-progress)
                  (and entry.quest-id (quest-completed? entry.quest-id)))
          (values slug true))
        (values slug true))))

(fn attunement-advice [eff quest-completed? ?chain-progress]
  "Soft advisory {slug advice-text} for still-relevant attunements the player
   lacks: :advise? true, a :quest-id, the quest not completed, and no complete
   chain proving it. Used for a UI badge -- it never filters, so it is safe
   even when gating is off."
  (collect [slug entry (pairs eff)]
    (when (and entry.advise? entry.quest-id
               (not (quest-completed? entry.quest-id))
               (not (chain-attuned? slug ?chain-progress)))
      (values slug entry.advice-text))))

(fn by-closest-then-name [a b]
  (if (not= a.fraction b.fraction) (> a.fraction b.fraction)
      (< (tostring a.name) (tostring b.name))))

(fn chain-advice [?chain-progress]
  "Plan advisories for STARTED-but-incomplete chains: one row per chain the
   player is mid-way through, carrying its next actionable step. Unstarted
   chains are deliberately silent (UX §9: quiet) -- the attunement advice
   badge already nudges toward the ones worth starting. Sorted closest-to-
   done first, then by name, so the plan stays deterministic (G5)."
  (if (= nil ?chain-progress)
      []
      (let [rows (icollect [_ chain (ipairs (chains.all))]
                   (let [p (. ?chain-progress (tostring chain.id))]
                     (when (and (not= nil p) (not= nil (next p.completed))
                                (not (chains.chain-complete? chain p)))
                       (let [step (chains.current-step chain p)
                             summary (chains.progress chain p)]
                         (when step
                           {:chain-id chain.id
                            :name chain.name
                            :next-step-label step.label
                            :done summary.done
                            :total summary.total
                            :fraction summary.fraction
                            :est-minutes (chains.est-minutes-remaining chain p)})))))]
        (table.sort rows by-closest-then-name)
        rows)))

(fn reputation-map [faction-standing]
  "Map {faction standing-keyword} for every tracked faction the player has a
   standing with; factions the lookup can't resolve are omitted (route's
   requirement check defaults a missing faction to :neutral)."
  (collect [faction fid (pairs faction-ids)]
    (let [sid (faction-standing fid)
          standing (and sid (. standing-by-id sid))]
      (when standing (values faction standing)))))

(fn chain-fractions [?chain-progress]
  "Map {chain-id-string fraction} of every chain in the live progress map --
   the :chain goal-progress source."
  (if (= nil ?chain-progress) {}
      (collect [cid p (pairs ?chain-progress)]
        (let [chain (chains.by-id cid)]
          (when chain
            (values (tostring cid) (. (chains.progress chain p) :fraction)))))))

(fn gold-band-overrides [?yield-history]
  "Map {activity-id-string {:min :max}} of history-blended gold bands, only for
   activities the player has recorded visits to -- absent entries fall back to
   the curated band downstream (goals.activity-yield)."
  (if (= nil ?yield-history) {}
      (collect [_ e (ipairs (yields.all))]
        (let [tally (history.yields-for ?yield-history e.activity-id)]
          (when (> tally.runs 0)
            (values (tostring e.activity-id)
                    (yields.blended-band {:min e.gold-min :max e.gold-max}
                                         tally.gold tally.runs)))))))

(fn live-customs [?persisted]
  "Authored entries that survive normalize and don't shadow a registry id --
   a custom named :karazhan must never replace the real raid."
  (icollect [_ c (ipairs (custom-activities.normalize ?persisted))]
    (when (= nil (activities.by-id c.id)) c)))

(fn custom-yield-map [customs]
  "Map {custom-id-string ActivityYield} of the authored payouts (entries that
   claim nothing are absent -- an honest zero, not a fabricated row)."
  (collect [_ c (ipairs customs)]
    (let [y (custom-activities.to-yield c)]
      (when y (values (tostring c.id) y)))))

(fn merge-custom-bands! [bands custom-yields]
  "Fold the authored custom gold bands into the (fresh) gold-band override map
   so goals' gold path needs no second lookup. No precedence conflict: a
   custom id never has a curated band or recorded history."
  (each [id y (pairs custom-yields)]
    (when (> y.gold-max 0)
      (tset bands id {:min y.gold-min :max y.gold-max})))
  bands)

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
                        :chain-progress ?{chain-id ChainProgress} -- live map
                          from src/core/events.fnl; nil keeps quest-flag-only
                          attunement resolution (pre-Phase-6 behaviour)
                        :goals ?[GoalDef]      -- db.char.goals (invalid rows drop)
                        :custom-activities ?[CustomActivity] -- db.profile
                          .custom-activities (invalid rows and ids shadowing
                          the registry drop)
                        :plan-edits ?PlanEdits -- db.char.plan-edits (pins /
                          skips; invalid entries drop)
                        :money ?int            -- GetMoney copper
                        :badge-count ?int      -- GetItemCount Badge of Justice
                        :reset-at ?int         -- next weekly reset timestamp
                        :yield-history ?History -- live history (gold-band blend)
                        :options {:spec ?kw :phase ?int :weights ?{}
                                  :competitors ?{} :composition ?{role int}
                                  :default-competitors ?int
                                  :seed ?int :include-classic? ?bool
                                  :attune ?{slug {:gate? ?bool :advise? ?bool}}}}
   Returns: {:player schemas.Player :ctx schemas.RouteContext
             :advice {attune-slug advice-text}  -- soft 'not attuned' notes
             :chain-advice [{:chain-id :name :next-step-label :done :total
                             :fraction :est-minutes} ...]}  -- started chains
   Errors:  if the assembled player or ctx fails its schema."
  (let [opts (or snapshot.options {})
        eff (effective-attune opts)
        owned (owned-set snapshot.owned-item-ids)
        player {:level snapshot.level
                :attunements (attunement-set eff snapshot.quest-completed?
                                             snapshot.chain-progress)
                :reputations (reputation-map snapshot.faction-standing)}
        goal-list (goals.normalize snapshot.goals)
        goal-inputs {:money snapshot.money
                     :badge-count snapshot.badge-count
                     :owned-items owned
                     :standings player.reputations
                     :chain-fractions (chain-fractions snapshot.chain-progress)}
        customs (live-customs snapshot.custom-activities)
        custom-yields (custom-yield-map customs)
        ctx {:class snapshot.class
             :spec (detect-spec snapshot.class snapshot.talent-points opts.spec)
             :phase (or opts.phase default-phase)
             :now snapshot.now
             :owned-items owned
             :lockouts (lockout-views snapshot.raw-lockouts snapshot.owner)
             :weights opts.weights
             :competitors opts.competitors
             :composition opts.composition
             :default-competitors opts.default-competitors
             :seed opts.seed
             :include-classic? opts.include-classic?
             :goals goal-list
             :goal-progress (collect [_ g (ipairs goal-list)]
                              (values g.id (goals.progress g goal-inputs)))
             :gold-bands (merge-custom-bands! (gold-band-overrides snapshot.yield-history)
                                              custom-yields)
             :reset-at snapshot.reset-at
             :custom-activities (icollect [_ c (ipairs customs)]
                                  (custom-activities.to-activity-def c))
             : custom-yields
             :plan-edits (plan-edits.normalize snapshot.plan-edits)}]
    (validate.assert! schemas.Player player :ctx/player)
    (validate.assert! schemas.RouteContext ctx :ctx/ctx)
    {: player
     : ctx
     :advice (attunement-advice eff snapshot.quest-completed?
                                snapshot.chain-progress)
     :chain-advice (chain-advice snapshot.chain-progress)}))

(lambda M.activity-for-instance [?name ?heroic?]
  "The tracked activity a live instance visit belongs to, for yield
   attribution (Phase 7). Raids map on any difficulty; the badge 5-mans only
   on heroic (a normal clear is neither a lockout nor a badge source); the
   two level-60 farm dungeons on any difficulty. nil when untracked.
   Domain:  ?name : string | nil -- GetInstanceInfo name
            ?heroic? : boolean | nil -- heroic difficulty
   Returns: activity id keyword | nil."
  (when (= (type ?name) :string)
    (or (. instance->activity ?name)
        (and ?heroic? (. heroic-instance->activity ?name))
        (. dungeon-instance->activity ?name))))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.ctx` after schemas
;; and validate. In tests, consumers fall through to `(require :src.domain.ctx)`.

(set _G.Routina Routina)
(set Routina.ctx M)

M
