;; tabs/chains.fnl -- Chains tab content: attunement chain progress as a card
;; stack on AceGUI-3.0 (PRD §6.8; OQ-13 resolved as the fourth tab).
;;
;; END-TO-END SLICE: src/core/events.fnl keeps the live {chain-id ->
;; ChainProgress} session (seeded from the quest log + SavedVariables);
;; src/domain/chains.fnl derives the per-chain facts (progress fraction, next
;; step, complete?); this tab renders one card per chain relevant to the
;; player's faction, in-progress first.
;;
;; Phase 8 §3: the tab also hosts the route CONSTRUCTOR -- a "New chain"
;; inline editor (name + one-step-per-line text) writing
;; db.profile.custom-chains, and per-custom-chain cards carrying a CheckBox
;; step checklist (events.mark-chain-step!) plus a Delete button. Custom
;; ChainDefs come from custom-chains.to-chain-def, so the progress queries
;; treat both provenances identically.
;;
;; UI.md split: the data->render-spec is PURE (M.chain-view-model /
;; M.list-view-model, busted-tested); building the AceGUI widgets from it is
;; imperative. render! follows the tab contract in src/ui/root.fnl: idempotent
;; populate of the AceGUI container (the caller ReleaseChildren's it first).

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))
(local format (or Routina.format (require :src.ui.format)))
(local chains (or Routina.chains (require :src.domain.chains)))
(local custom-chains
       (or Routina.custom-chains (require :src.domain.custom-chains)))

(local editor (or Routina.tab-chains-editor
                  (require :src.ui.tabs.chains-editor)))

(local events (or Routina.events (require :src.core.events)))
(local tomtom (or Routina.tomtom (require :src.core.tomtom)))
(local circuit (or Routina.circuit (require :src.core.circuit)))

(local UnitFactionGroup _G.UnitFactionGroup)

(local M {})

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn step-word [n]
  (if (= n 1) " step" " steps"))

(fn faction-match? [chain ?faction]
  "Whether a chain applies to the player's faction. A nil faction (headless,
   loading) shows everything rather than guessing; a chain WITHOUT a faction
   (custom chains, faction-free registry entries) applies to everyone."
  (or (= nil ?faction) (= nil chain.faction) (= chain.faction :Both)
      (= chain.faction ?faction)))

(lambda M.chain-view-model [chain progress]
  "Pure render spec for one chain card. :next-coord/:next-label (Phase 9)
   carry the current step's waypoint when it has one -- the unstarted chain's
   first step counts, so 'point me there' can start a journey too.
   Domain:  chain : ChainDef ; progress : ChainProgress
   Returns: {:title string :progress-text string :status string
             :complete? boolean :started? boolean :fraction number
             :next-coord {:map-id :x :y}|nil :next-label string|nil}"
  (let [summary (chains.progress chain progress)
        complete? (chains.chain-complete? chain progress)
        started? (not= nil (next progress.completed))
        step (if complete? nil (chains.current-step chain progress))]
    {:title (tostring chain.name)
     :progress-text (.. summary.done "/" summary.total
                        (step-word summary.total) " · "
                        (format.percent summary.fraction))
     :status (if complete?
                 :Complete
                 (and started? step)
                 (.. "Next: " (tostring step.label) " · ~"
                     (chains.est-minutes-remaining chain progress) " min left")
                 "Not started")
     : complete?
     : started?
     :next-coord (?. step :coord)
     :next-label (and step (tostring step.label))
     :fraction summary.fraction}))

(fn by-activity-then-name [a b]
  "In-progress first (closest to done on top), then unstarted, then complete;
   ties broken by title so the order is deterministic."
  (let [rank-a (if a.complete? 3
                   a.started? 1
                   2)
        rank-b (if b.complete? 3
                   b.started? 1
                   2)]
    (if (not= rank-a rank-b) (< rank-a rank-b)
        (not= a.fraction b.fraction) (> a.fraction b.fraction)
        (< a.title b.title))))

(lambda M.list-view-model [?progress-map ?faction ?custom-defs]
  "Every registry chain for the player's faction -- plus the player's
   constructed chains (Phase 8 §3) -- as ordered card view-models: in-progress
   first (closest to done on top), then unstarted, complete last. A custom
   chain's view-model additionally carries :custom? true, its :chain-id, and
   per-step checklist rows so the tab can render CheckBoxes.
   Domain:  ?progress-map : {chain-id ChainProgress} | nil -- live session map
            ?faction : string | nil -- UnitFactionGroup token (Horde/Alliance);
                       nil shows all factions (headless)
            ?custom-defs : [ChainDef] | nil -- constructed defs
                           (custom-chains.to-chain-def)
   Returns: [chain-view-model ...] -- custom rows += {:custom? true :chain-id
            string :steps [{:id :label :done? boolean} ...]}"
  (fn progress-of [chain]
    (or (and ?progress-map (. ?progress-map (tostring chain.id)))
        (chains.empty-progress)))

  (let [rows (icollect [_ chain (ipairs (chains.all))]
               (when (faction-match? chain ?faction)
                 (M.chain-view-model chain (progress-of chain))))]
    (each [_ chain (ipairs (or ?custom-defs []))]
      (let [progress (progress-of chain)
            vm (M.chain-view-model chain progress)]
        (set vm.custom? true)
        (set vm.chain-id (tostring chain.id))
        ;; Phase 9: a coord-carrying custom chain is a walkable circuit; the
        ;; def rides along so the Start-circuit button can hand it to the
        ;; runner (plain data, still a pure spec).
        (set vm.circuit? (> (length (chains.circuit-steps chain)) 0))
        (set vm.def chain)
        (set vm.steps
             (icollect [_ s (ipairs chain.steps)]
               {:id s.id
                :label s.label
                :done? (chains.step-completed? progress s.id)}))
        (table.insert rows vm)))
    (table.sort rows by-activity-then-name)
    rows))

;; --- Card (AceGUI InlineGroup) ---------------------------------------------

(fn add-line! [card text ?color ?size]
  "Append one themed, full-width label line to a card."
  (let [label (acegui.create! :Label)]
    (when label
      (label:SetText text)
      (label:SetFullWidth true)
      (acegui.themed-label! label (or ?color :ink) :body (or ?size :body))
      (card:AddChild label))))

(fn build-checklist! [card vm]
  "The step checklist of one custom-chain card: a CheckBox per step, toggling
   through events.mark-chain-step! (which repaints via the debounced refresh)."
  (each [_ step (ipairs vm.steps)]
    (let [box (acegui.create! :CheckBox)]
      (when box
        (box:SetLabel step.label)
        (box:SetValue (= true step.done?))
        (box:SetFullWidth true)
        ;; verified: AceGUIWidget-CheckBox fires OnValueChanged with the
        ;; checked state
        (box:SetCallback :OnValueChanged
                         (fn [_ _ checked]
                           (events.mark-chain-step! vm.chain-id step.id
                                                    (= checked true))))
        (card:AddChild box)))))

(fn add-button! [card text width handler]
  "One action button on a chain card."
  (let [btn (acegui.create! :Button)]
    (when btn
      (btn:SetText text)
      (btn:SetWidth width)
      (btn:SetCallback :OnClick handler)
      (card:AddChild btn))
    btn))

(fn build-waypoints! [card vm]
  "The Phase 9 waypoint affordances of one card -- HIDDEN entirely without
   TomTom (exit criterion): 'Point me there' when the current step carries a
   coord, Start/Stop circuit on coord-carrying custom chains."
  (when (tomtom.available?)
    (when vm.next-coord
      (add-button! card "Point me there" 140
                   #(tomtom.set-waypoint! vm.next-coord vm.next-label)))
    (when (and vm.custom? vm.circuit?)
      (if (= (circuit.active-chain) vm.chain-id)
          (add-button! card "Stop circuit" 140
                       (fn []
                         (circuit.stop!)
                         (when Routina.root
                           (Routina.root.refresh!))))
          (add-button! card "Start circuit" 140
                       (fn []
                         (circuit.start! vm.def)
                         (when Routina.root (Routina.root.refresh!))))))))

(fn build-card! [vm]
  "Build one chain card as an InlineGroup from a pure view-model. Custom
   chains (Phase 8 §3) additionally carry their step checklist and a Delete;
   waypoint affordances (Phase 9) render only with TomTom loaded."
  (let [card (acegui.create! :InlineGroup)]
    (when card
      (card:SetTitle vm.title)
      (card:SetFullWidth true)
      (card:SetLayout :List)
      (add-line! card vm.progress-text :ink :body)
      (add-line! card vm.status (if vm.complete? :gold
                                    vm.started? :ink
                                    :ink-faint)
                 :caption)
      (when vm.custom?
        (build-checklist! card vm))
      (build-waypoints! card vm)
      (when vm.custom?
        (add-button! card "Delete chain" 140
                     #(editor.delete-custom! vm.chain-id))))
    card))

;; --- Public API ------------------------------------------------------------

(fn add-empty! [container message]
  (let [label (acegui.create! :Label)]
    (when label
      (label:SetText message)
      (label:SetFullWidth true)
      (acegui.themed-label! label :ink-faint :body :body)
      (container:AddChild label))))

(lambda M.render! [container]
  "Repaint the Chains tab into an AceGUI container (the TabGroup). Reads the
   live chain session plus the persisted custom chains and adds the New-chain
   constructor followed by a ScrollFrame of progress cards. Idempotent -- the
   caller (src/ui/root.fnl) ReleaseChildren's the container first. No-op
   headless (no AceGUI).
   Domain:  container : an AceGUI container widget
   Returns: nil."
  (let [scroll (acegui.create! :ScrollFrame)]
    (when (and scroll container)
      (container:SetLayout :Fill)
      (scroll:SetLayout :List)
      (scroll:SetFullWidth true)
      (scroll:SetFullHeight true)
      (container:AddChild scroll)
      (editor.build-editor! scroll)
      (let [faction (and UnitFactionGroup (UnitFactionGroup :player))
            custom-defs (icollect [_ c (ipairs (custom-chains.normalize (editor.custom-db)))]
                          (when (= nil (chains.by-id c.id))
                            (custom-chains.to-chain-def c)))
            vms (M.list-view-model (events.chain-progress) faction custom-defs)]
        (if (= 0 (length vms))
            (add-empty! scroll "No chains tracked for this client phase.")
            (each [_ vm (ipairs vms)]
              (let [card (build-card! vm)]
                (when card (scroll:AddChild card))))))))
  nil)

(set _G.Routina Routina)
(set Routina.tab-chains M)

M
