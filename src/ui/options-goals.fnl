;; options-goals.fnl -- the Goals editor: an AceConfig sub-panel (Phase 7 §6).
;;
;; Split out of src/ui/options.fnl (size rule). Same contract: M.goals-group
;; is a PURE builder (busted-tested) from a small api to an AceConfig group
;; spec; the :set closures mutate the persisted goal list IN PLACE (it is the
;; AceDB char.goals table) and fire api.on-change to re-plan. Goal PROGRESS is
;; not here -- it renders in the Plan tab head (OQ-13 for goals, resolved
;; 2026-06-05); this panel only authors the GoalDef list.
;;
;; The pending new-goal fields live in builder closures, not the DB -- nothing
;; persists until Add validates the assembled GoalDef via goals.normalize, so
;; a half-filled form can never write a corrupt row.

(local Routina (or _G.Routina {}))
(local goals (or Routina.goals (require :src.domain.goals)))
(local chains (or Routina.chains (require :src.domain.chains)))
(local custom-chains
       (or Routina.custom-chains (require :src.domain.custom-chains)))

(local format (or Routina.format (require :src.ui.format)))

(local M {})

;; --- Static choices (pure) ---------------------------------------------------

(local kind-values {:badges "Badges of Justice"
                    :gold :Gold
                    :item "Specific item"
                    :rep "Reputation standing"
                    :chain "Finish a chain"})

;; Reputation ladder index, mirroring goals.fnl (rep targets are 1..8).
(local standing-names [:Hated
                       :Hostile
                       :Unfriendly
                       :Neutral
                       :Friendly
                       :Honored
                       :Revered
                       :Exalted])

;; Factions with modelled rep yields (src/domain/ctx.fnl faction-ids).
(local faction-values {:ogrila "Ogri'la"})

;; --- Pure helpers ------------------------------------------------------------

(lambda M.parse-target [kind ?text]
  "The numeric target a form entry means for a goal kind, or nil when invalid.
   Gold is entered in GOLD and stored in copper; item and chain goals have a
   fixed target (own it / finish it); rep is the standing index 1..8.
   Domain:  kind : GoalDef :kind ; ?text : string | number | nil
   Returns: number > 0 | nil."
  (case kind
    :item 1
    :chain 1
    _ (let [n (tonumber ?text)]
        (when (and n (> n 0))
          (case kind
            :gold (* n 10000)
            :rep (math.min 8 (math.floor n))
            _ (math.floor n))))))

(lambda M.next-goal-id [goal-list]
  "A fresh goal id ('g<N>', N above every existing one). Deterministic --
   derived from the list, no clock.
   Domain:  goal-list : [GoalDef]
   Returns: string."
  (let [top (accumulate [top 0 _ g (ipairs goal-list)]
              (let [n (tonumber (or (string.match (tostring g.id) "^g(%d+)$")
                                    ""))]
                (if (and n (> n top)) n top)))]
    (.. :g (+ top 1))))

(lambda M.goal-label [goal]
  "One goal as a list line for the editor and the remove picker.
   Domain:  goal : GoalDef
   Returns: string."
  (case goal.kind
    :gold (.. "Gold: " (format.gold goal.target))
    :badges (.. "Badges: " (math.floor goal.target))
    :item (.. "Item #" (tostring goal.item-id))
    :rep (.. "Reputation: " (tostring goal.faction) " to "
             (tostring (or (. standing-names (math.floor goal.target))
                           goal.target)))
    :chain (let [chain (and goal.chain-id (chains.by-id goal.chain-id))]
             (.. "Chain: " (tostring (if chain chain.name goal.chain-id))))
    _ (tostring goal.kind)))

(fn chain-values [?custom-list]
  "AceConfig select values of every registry chain (id -> name), plus the
   player's constructed chains (Phase 8 §3) so a :chain goal can target one.
   Re-derived lazily per dropdown open -- the constructor mutates the
   persisted list in place."
  (let [out (collect [_ chain (ipairs (chains.all))]
              (values (tostring chain.id) (tostring chain.name)))]
    (each [_ c (ipairs (custom-chains.normalize ?custom-list))]
      (when (= nil (. out (tostring c.id)))
        (tset out (tostring c.id) (tostring c.name))))
    out))

(fn goal-lines [goal-list]
  "The current-goals description text."
  (if (= 0 (length goal-list))
      "No goals yet -- add one below and the Plan tab tracks it to the reset."
      (table.concat (icollect [i g (ipairs goal-list)]
                      (.. i ". " (M.goal-label g))) "\n")))

;; --- Public API ----------------------------------------------------------------

(lambda M.goals-group [api]
  "Build the Goals AceConfig group: current list, add-goal form, remove
   picker, and the yield-tracking toggle.
   Domain:  api : {:db    route-preferences table (the track-yields? flag)
                   :goals the persisted [GoalDef] list, mutated in place
                   :custom-chains ?[CustomChain] -- the LIVE persisted
                     authored-chain list (db.profile.custom-chains), for the
                     chain-goal choices
                   :on-change (fn []) | nil  -- fired after any mutation
                   :notify (fn []) | nil} -- AceConfigRegistry refresh
   Returns: an AceConfig group table."
  (var pending-kind :badges)
  (var pending-target "")
  (var pending-item "")
  (var pending-faction :ogrila)
  (var pending-chain nil)
  (var pending-remove nil)
  (let [goal-list api.goals
        changed (fn []
                  (when api.on-change (api.on-change))
                  (when api.notify (api.notify)))
        add! (fn []
               (let [target (M.parse-target pending-kind pending-target)]
                 (when target
                   (let [draft {:id (M.next-goal-id goal-list)
                                :kind pending-kind
                                : target
                                :item-id (when (= pending-kind :item)
                                           (tonumber pending-item))
                                :faction (when (= pending-kind :rep)
                                           (tostring pending-faction))
                                :chain-id (when (= pending-kind :chain)
                                            pending-chain)}
                         valid (goals.normalize [draft])]
                     (when (= 1 (length valid))
                       (table.insert goal-list (. valid 1))
                       (set pending-target "")
                       (set pending-item "")
                       (changed))))))
        remove! (fn []
                  (let [idx (tonumber pending-remove)]
                    (when (and idx (. goal-list idx))
                      (table.remove goal-list idx)
                      (set pending-remove nil)
                      (changed))))]
    {:type :group
     :name :Goals
     :order 5
     :args {:about {:type :description
                    :order 0
                    :name (.. "State a weekly goal and the plan bends toward it: "
                              "goal-paying activities gain score as the reset "
                              "nears (deadline-aware), and the Plan tab shows "
                              "honest P10/P50/P90 progress per goal.")}
            :current {:type :description
                      :order 1
                      :name (fn [] (goal-lines goal-list))}
            :kind {:type :select
                   :name "New goal"
                   :order 2
                   :values kind-values
                   :get (fn [_] pending-kind)
                   :set (fn [_ v] (set pending-kind v))}
            :target {:type :input
                     :name :Target
                     :desc "Badges: a count. Gold: an amount in gold. Reputation: the standing to reach (1 Hated .. 8 Exalted)."
                     :order 3
                     :hidden (fn []
                               (or (= pending-kind :item)
                                   (= pending-kind :chain)))
                     :get (fn [_] pending-target)
                     :set (fn [_ v] (set pending-target v))}
            :item-id {:type :input
                      :name "Item ID"
                      :order 4
                      :hidden (fn [] (not= pending-kind :item))
                      :get (fn [_] pending-item)
                      :set (fn [_ v] (set pending-item v))}
            :faction {:type :select
                      :name :Faction
                      :order 5
                      :values faction-values
                      :hidden (fn [] (not= pending-kind :rep))
                      :get (fn [_] pending-faction)
                      :set (fn [_ v] (set pending-faction v))}
            :chain-id {:type :select
                       :name :Chain
                       :order 6
                       :values (fn [] (chain-values api.custom-chains))
                       :hidden (fn [] (not= pending-kind :chain))
                       :get (fn [_]
                              (and pending-chain (tostring pending-chain)))
                       :set (fn [_ v] (set pending-chain v))}
            :add {:type :execute :name "Add goal" :order 7 :func add!}
            :remove-pick {:type :select
                          :name "Goal to remove"
                          :order 8
                          :values (fn []
                                    (collect [i g (ipairs goal-list)]
                                      (values (tostring i) (M.goal-label g))))
                          :get (fn [_] pending-remove)
                          :set (fn [_ v] (set pending-remove v))}
            :remove {:type :execute
                     :name "Remove selected"
                     :order 9
                     :func remove!}
            :track-yields {:type :toggle
                           :name "Track yields (experimental)"
                           :desc "Record each tracked instance visit's gold and badge take to tighten the curated gold/h bands toward your own results. Off by default."
                           :order 10
                           :width :full
                           :get (fn [_] (= true (?. api :db :track-yields?)))
                           :set (fn [_ v]
                                  (tset api.db :track-yields? v)
                                  (when (?. Routina :events
                                            :set-yields-tracking!)
                                    (Routina.events.set-yields-tracking! v))
                                  (changed))}}}))

;; --- Register into the addon namespace ---------------------------------------

(set _G.Routina Routina)
(set Routina.options-goals M)

M
