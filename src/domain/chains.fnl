;; chains.fnl -- pure quest/attunement chain engine.
;;
;; PURE domain module: no WoW API, no time, no random, no mutation of inputs.
;; The static registry lives in the generated src/domain/chains/data.fnl (see
;; scripts/import-chains.lua, vendor/chain-source/README.md); this module reads
;; it, validates every ChainDef once against schemas.ChainDef at load, and
;; exposes read-only queries plus pure ChainProgress transforms.
;;
;; Progress model: ChainProgress persists ONLY the completed step-id set;
;; "current step", "fraction done" and "complete?" are derived here, never
;; stored. The shell (src/core/events.fnl) keeps a live {chain-id -> progress}
;; map seeded from db.char.chains and flushed back on logout.
;;
;; Seeding inference (see seed-from-completed): quest-flagged steps
;; (:quest/:pickup/:turnin) complete iff their quest-id is in the completed
;; set WoW reports; other step kinds carry no completed flag, so they
;; BACKFILL -- a non-quest step is inferred complete when some completed step
;; sits at a strictly higher :stage, and an :end step completes when its
;; prerequisites are met. At a genuine branch this can over-mark a sibling;
;; accepted for near-linear TBC chains, with the options-panel manual
;; attunement override as the escape hatch.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; Dual-mode: in-game the .toc loads chains/data before this module (populating
;; Routina.chain-data); under busted we require it directly.
(local chain-data (or Routina.chain-data (require :src.domain.chains.data)))

;; Load-time boundary check: every registry entry conforms to schemas.ChainDef.
;; Once at load, never in a query, mirroring drop-table.fnl / bis-catalog.fnl.
(each [id chain (pairs chain-data)]
  (let [r (validate.check schemas.ChainDef chain)]
    (assert r.ok (.. "chains: invalid ChainDef " (tostring id) ": "
                     (table.concat (or r.errors []) "; ")))))

;; Fallback estimate for a single remaining step, in minutes. Deliberately
;; coarse -- real per-step estimates are a Phase 7 yields concern.
(local default-step-minutes 15)

;; --- Helpers (private) -----------------------------------------------------

(fn assert-chain [chain]
  "Cheap structural check at a public-fn boundary. Full schema validation runs
   once at load for the registry; player-authored chains (Phase 8) validate at
   their own input boundary, so queries only guard the shape they walk."
  (assert (and (= (type chain) :table) (= (type chain.steps) :table))
          "chain must be a ChainDef with a :steps list")
  chain)

(fn assert-progress [progress]
  "Cheap structural check for a ChainProgress."
  (assert (and (= (type progress) :table) (= (type progress.completed) :table))
          "progress must be a ChainProgress with a :completed set")
  progress)

(fn copy-set [ids]
  "A fresh shallow copy of a string->true set."
  (collect [k v (pairs ids)] k v))

(fn done? [completed step]
  (= true (. completed step.id)))

(fn prereqs-met? [completed step]
  "Whether a step's :follows prerequisites are satisfied by the completed set
   (:all -> every id present; :any -> at least one; empty list -> met)."
  (if (= 0 (length step.follows))
      true
      (= step.follows-mode :any)
      (accumulate [met false _ fid (ipairs step.follows)]
        (or met (= true (. completed fid))))
      (accumulate [met true _ fid (ipairs step.follows)]
        (and met (= true (. completed fid))))))

(fn quest-step? [step]
  (and step.quest-id (or (= step.type :quest) (= step.type :pickup)
                         (= step.type :turnin))))

(fn backfill [chain completed]
  "Infer completion for steps WoW exposes no flag for, returning a NEW set.
   Pass 1: a non-quest, non-:end step is complete when some completed step has
   a strictly higher :stage (a later quest implies the road to it was walked).
   Pass 2: an :end step is complete when its prerequisites are met. Quest
   steps are never inferred -- their flag is authoritative."
  (let [next (copy-set completed)
        max-done-stage (accumulate [top nil _ s (ipairs chain.steps)]
                         (if (and (done? next s) s.stage
                                  (or (= top nil) (> s.stage top)))
                             s.stage
                             top))]
    (each [_ s (ipairs chain.steps)]
      (when (and (not (done? next s)) (not (quest-step? s)) (not= s.type :end)
                 s.stage max-done-stage (< s.stage max-done-stage))
        (tset next s.id true)))
    (each [_ s (ipairs chain.steps)]
      (when (and (not (done? next s)) (= s.type :end) (prereqs-met? next s))
        (tset next s.id true)))
    next))

(fn frontier [chain completed]
  "Steps not yet complete whose prerequisites are met, in :steps order."
  (icollect [_ s (ipairs chain.steps)]
    (when (and (not (done? completed s)) (prereqs-met? completed s))
      s)))

(fn valid-progress-entry? [k v]
  "Whether a persisted completed-set pair is well-formed (string -> true)."
  (and (= (type k) :string) (= v true)))

(fn normalize-one [raw]
  "Coerce one possibly-corrupt persisted ChainProgress, dropping bad entries."
  (let [completed (if (= (type raw) :table) (or raw.completed nil) nil)]
    {:completed (if (= (type completed) :table)
                    (collect [k v (pairs completed)]
                      (if (valid-progress-entry? k v) (values k v)
                          (values nil nil)))
                    {})}))

;; --- Registry queries --------------------------------------------------------

(lambda M.all []
  "Every ChainDef as a fresh sequence (unordered).
   Domain:  (none)
   Returns: [ChainDef] -- a new sequence; callers may not mutate the data."
  (icollect [_ c (pairs chain-data)] c))

(lambda M.by-id [id]
  "The ChainDef for a chain id, or nil if unknown.
   Domain:  id : string|keyword -- chain id (:karazhan ...)
   Returns: ChainDef or nil."
  (. chain-data (tostring id)))

(lambda M.by-kind [kind]
  "Every ChainDef of a kind, as a fresh sequence.
   Domain:  kind : [:enum :attunement :quest-line :daily-circuit :custom]
   Returns: [ChainDef] -- fresh sequence, possibly empty."
  (icollect [_ c (pairs chain-data)]
    (when (= c.kind kind) c)))

(lambda M.tracked-quest-ids []
  "Every quest-id any registry chain step carries, as a fresh set. The shell
   sweeps wow.quest-completed? over exactly this set on login.
   Domain:  (none)
   Returns: {integer -> true} -- fresh set, possibly empty."
  (let [ids {}]
    (each [_ c (pairs chain-data)]
      (each [_ s (ipairs c.steps)]
        (when s.quest-id (tset ids s.quest-id true))))
    ids))

(lambda M.chains-with-quest [quest-id]
  "Every ChainDef containing a step with this quest-id, as a fresh sequence.
   Domain:  quest-id : integer
   Returns: [ChainDef] -- fresh sequence, possibly empty."
  (icollect [_ c (pairs chain-data)]
    (when (accumulate [hit false _ s (ipairs c.steps)]
            (or hit (= s.quest-id quest-id)))
      c)))

;; --- Progress queries (pure reads) ------------------------------------------

(lambda M.empty-progress []
  "A fresh, empty ChainProgress.
   Domain:  (none)
   Returns: ChainProgress -- {:completed {}}"
  {:completed {}})

(lambda M.step-completed? [progress step-id]
  "Whether a step is recorded complete.
   Domain:  progress : ChainProgress ; step-id : string|keyword
   Returns: boolean"
  (assert-progress progress)
  (= true (. progress.completed (tostring step-id))))

(lambda M.next-steps [chain progress]
  "The actionable frontier: steps not yet complete whose prerequisites are
   satisfied (usually one for a linear chain, several at a branch).
   Domain:  chain : ChainDef ; progress : ChainProgress
   Returns: [ChainStep] -- fresh sequence in :steps order, empty when done."
  (assert-chain chain)
  (assert-progress progress)
  (frontier chain progress.completed))

(lambda M.current-step [chain progress]
  "The single best next step (lowest :stage, then :steps order), for UI rows.
   Domain:  chain : ChainDef ; progress : ChainProgress
   Returns: ChainStep or nil when the chain is complete."
  (let [steps (M.next-steps chain progress)]
    (accumulate [best nil _ s (ipairs steps)]
      (if (or (= best nil) (and s.stage best.stage (< s.stage best.stage)))
          s
          best))))

(lambda M.progress [chain progress]
  "Completion summary for a chain.
   Domain:  chain : ChainDef ; progress : ChainProgress
   Returns: {:done integer :total integer :fraction number in [0,1]}"
  (assert-chain chain)
  (assert-progress progress)
  (let [total (length chain.steps)
        done (accumulate [n 0 _ s (ipairs chain.steps)]
               (if (done? progress.completed s) (+ n 1) n))]
    {: done : total :fraction (if (= total 0) 0 (/ done total))}))

(lambda M.chain-complete? [chain progress]
  "Whether the chain is finished: a completed :end step, or every step done.
   Domain:  chain : ChainDef ; progress : ChainProgress
   Returns: boolean"
  (assert-chain chain)
  (assert-progress progress)
  (let [end-done (accumulate [hit false _ s (ipairs chain.steps)]
                   (or hit (and (= s.type :end) (done? progress.completed s))))
        summary (M.progress chain progress)]
    (or end-done (and (> summary.total 0) (= summary.done summary.total)))))

(lambda M.steps-remaining [chain progress]
  "How many steps are still incomplete.
   Domain:  chain : ChainDef ; progress : ChainProgress
   Returns: integer >= 0"
  (let [summary (M.progress chain progress)]
    (- summary.total summary.done)))

(lambda M.est-minutes-remaining [chain progress ?per-step-minutes]
  "Coarse time estimate to finish the chain.
   Domain:  chain : ChainDef ; progress : ChainProgress
            ?per-step-minutes : number > 0 | nil (default 15)
   Returns: number >= 0 -- steps-remaining x per-step estimate."
  (* (M.steps-remaining chain progress)
     (or ?per-step-minutes default-step-minutes)))

;; --- Progress transforms (pure; always return a NEW ChainProgress) ----------

(lambda M.mark-step [progress step-id]
  "Record one step complete, returning a NEW ChainProgress (no inference).
   Domain:  progress : ChainProgress ; step-id : string|keyword
   Returns: ChainProgress"
  (assert-progress progress)
  (let [next (copy-set progress.completed)]
    (tset next (tostring step-id) true)
    {:completed next}))

(lambda M.record-quest [chain progress quest-id]
  "Record a quest turn-in: every step carrying this quest-id completes, then
   non-quest predecessors backfill. Returns a NEW ChainProgress (unchanged
   copy when the quest is not part of the chain).
   Domain:  chain : ChainDef ; progress : ChainProgress ; quest-id : integer
   Returns: ChainProgress"
  (assert-chain chain)
  (assert-progress progress)
  (let [marked (copy-set progress.completed)]
    (each [_ s (ipairs chain.steps)]
      (when (= s.quest-id quest-id)
        (tset marked s.id true)))
    {:completed (backfill chain marked)}))

(lambda M.merge-progress [chain a b]
  "Union two ChainProgress records for one chain (persisted progress merged
   with a fresh quest-log seed), re-running backfill over the union so the
   combined evidence can infer steps neither side held alone. Returns a NEW
   ChainProgress.
   Domain:  chain : ChainDef ; a, b : ChainProgress
   Returns: ChainProgress"
  (assert-chain chain)
  (assert-progress a)
  (assert-progress b)
  (let [union (copy-set a.completed)]
    (each [k v (pairs b.completed)]
      (when (= v true) (tset union k true)))
    {:completed (backfill chain union)}))

(lambda M.seed-from-completed [chain completed-quest-ids]
  "Build a ChainProgress from WoW's completed-quest flags (a {quest-id true}
   set, pure data -- the shell sweeps wow.quest-completed? into it on login).
   Quest steps complete iff flagged; the rest backfill (see module header).
   Domain:  chain : ChainDef
            completed-quest-ids : {integer -> true} -- completed-quest set
   Returns: ChainProgress"
  (assert-chain chain)
  (assert (= (type completed-quest-ids) :table)
          "completed-quest-ids must be a set table")
  (let [marked {}]
    (each [_ s (ipairs chain.steps)]
      (when (and (quest-step? s) (= true (. completed-quest-ids s.quest-id)))
        (tset marked s.id true)))
    {:completed (backfill chain marked)}))

;; --- Persistence (outer {chain-id -> ChainProgress} map) --------------------

(lambda M.normalize [?persisted]
  "Coerce a possibly-nil / possibly-corrupt persisted table into a valid
   {chain-id -> ChainProgress} map, dropping malformed entries. Used by the
   shell when seeding from SavedVariables (db.char.chains).
   Domain:  ?persisted : table | nil
   Returns: {string -> ChainProgress}"
  (if (not= (type ?persisted) :table)
      {}
      (collect [k raw (pairs ?persisted)]
        (if (= (type k) :string)
            (values k (normalize-one raw))
            (values nil nil)))))

(lambda M.to-db [progress-map]
  "A fresh plain copy of the progress map for writing to SavedVariables, so
   the persisted table never aliases the live session copy.
   Domain:  progress-map : {string -> ChainProgress}
   Returns: {string -> ChainProgress} (plain data)"
  (collect [id p (pairs progress-map)]
    (values id {:completed (copy-set p.completed)})))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.chains` before
;; src/core/events.fnl feeds it. In tests, consumers fall through to
;; `(require :src.domain.chains)` -> the same M.

(set _G.Routina Routina)
(set Routina.chains M)

M
