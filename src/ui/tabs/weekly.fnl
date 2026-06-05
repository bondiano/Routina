;; tabs/weekly.fnl -- Plan tab content: a live, score-ordered card stack on
;; AceGUI-3.0.
;;
;; END-TO-END SLICE: src/core/planner.fnl reads the live client into a
;; (player, ctx, advice) triple, src/domain/route.fnl scores it against the real
;; catalog, and the steps render as a score-ordered stack of InlineGroup cards.
;;
;; UI.md split: the data->render-spec view-models are PURE and live in
;; tabs/weekly-vm.fnl (busted-tested; re-exported here for compatibility);
;; building the AceGUI widgets from them is imperative. AceGUI pools its own
;; widgets, so render! just ReleaseChildren-then-rebuild -- there is no bespoke
;; frame pool any more. render! is driven by src/ui/root.fnl (OnGroupSelected +
;; refresh!), itself fed by src/core/events.fnl.
;;
;; NOTE: the chance is shown as text + item-quality colour AND a proportional
;; chance-meter bar (src/ui/widgets/chance-meter.fnl) anchored to the right edge
;; of each item row. The meter is fixed-width, so it sidesteps AceGUI's deferred
;; layout (the reason it was originally deferred): a RIGHT-anchored 80px bar
;; resolves at draw time regardless of DoLayout. Meters are pooled by the widget;
;; this tab tracks the ones it acquired and releases them at the top of every
;; repaint (AceGUI recycles its own rows, but the custom child frames are ours).

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))
(local vm (or Routina.tab-weekly-vm (require :src.ui.tabs.weekly-vm)))
(local route (or Routina.route (require :src.domain.route)))
(local goals (or Routina.goals (require :src.domain.goals)))
(local planner (or Routina.planner (require :src.core.planner)))
(local plan-edits (or Routina.plan-edits (require :src.domain.plan-edits)))
(local activities (or Routina.activities (require :src.domain.activities)))
(local chance-meter
       (or Routina.chance-meter (require :src.ui.widgets.chance-meter)))

(local GetItemInfo _G.GetItemInfo)
(local GetItemIcon _G.GetItemIcon)
(local GetItemQualityColor _G.GetItemQualityColor)
(local GameTooltip _G.GameTooltip)

(local M {})

;; --- Layout constants ------------------------------------------------------

(local epic-quality 4)

;; Right inset of the chance-meter from the item row's right edge.
(local meter-inset -8)

;; Chance-meters acquired during the current paint, drained on the next one.
(var live-meters [])

(fn release-meters! []
  "Return every meter from the last paint to the pool. Called at the top of
   render! before AceGUI rebuilds the rows the meters were anchored to."
  (each [_ m (ipairs live-meters)] (chance-meter.release! m))
  (set live-meters []))

;; --- Pure view-models (tabs/weekly-vm.fnl; re-exported for compatibility) --

(set M.card-view-model vm.card-view-model)
(set M.chain-advice-view-model vm.chain-advice-view-model)
(set M.projection-view-model vm.projection-view-model)
(set M.goals-view-model vm.goals-view-model)
(set M.skipped-view-model vm.skipped-view-model)

;; --- Item-quality helpers (imperative, WoW API) ----------------------------

(fn item-quality [item-id]
  "WoW item quality (0..7) for an id, falling back to epic.
   GetItemInfo returns nil for an uncached id; since the plan only ever lists
   BiS gear (overwhelmingly epic), epic is the right default so the colour still
   reads sensibly before the client caches the item."
  (or (and item-id GetItemInfo (select 3 (GetItemInfo item-id))) epic-quality))

(fn quality-color [item-id]
  "r, g, b for an item's quality, or nil when the client lacks the API."
  (when GetItemQualityColor
    (GetItemQualityColor (item-quality item-id))))

;; --- Item row (AceGUI InteractiveLabel + native tooltip) -------------------

(fn make-tooltip-enter [item-id]
  "OnEnter handler closing over the item id. AceGUI passes (widget, event); the
   WoW frame is widget.frame (verified: AceGUIWidget-InteractiveLabel.lua)."
  (fn [widget]
    (when (and item-id GameTooltip)
      (GameTooltip:SetOwner widget.frame :ANCHOR_RIGHT)
      (GameTooltip:SetItemByID item-id)
      (GameTooltip:Show))))

(fn on-row-leave []
  (when GameTooltip (GameTooltip:Hide)))

(fn attach-meter! [row chance]
  "Anchor a fixed-width chance-meter to the right edge of an item row's frame
   and remember it for the next release-meters! sweep. Skips a nil/out-of-range
   chance (the text column still carries the number, UI.md §11)."
  (when (and row row.frame chance (>= chance 0) (<= chance 1))
    (let [meter (chance-meter.acquire! row.frame)]
      (when meter
        (chance-meter.set! meter (chance-meter.view-model chance))
        (meter:ClearAllPoints)
        (meter:SetPoint :RIGHT row.frame :RIGHT meter-inset 0)
        (table.insert live-meters meter)))))

(fn build-row! [item]
  "One hoverable item row: an InteractiveLabel showing icon + name, quality
   coloured, with chance text, a right-anchored chance-meter, and the native
   item tooltip on hover."
  (let [row (acegui.create! :InteractiveLabel)]
    (when row
      (row:SetFullWidth true)
      (row:SetText (.. item.name "   " item.chance-text))
      (acegui.themed-label! row :ink :body :body)
      (let [(r g b) (quality-color item.item-id)]
        (when r (row:SetColor r g b)))
      (when (and GetItemIcon item.item-id)
        (let [icon (GetItemIcon item.item-id)]
          (when icon
            (row:SetImage icon)
            (row:SetImageSize 18 18))))
      (row:SetCallback :OnEnter (make-tooltip-enter item.item-id))
      (row:SetCallback :OnLeave on-row-leave)
      (attach-meter! row item.chance))
    row))

;; --- Plan edits (pin / skip / move; Phase 8 §2) ------------------------------
;;
;; The card buttons mutate db.char.plan-edits through the PURE plan-edits
;; transforms (the options.fnl precedent: UI :set closures may write the DB
;; directly), then repaint via root.refresh!. The route re-reads the edits on
;; the next plan, so the reorder is the planner's own deterministic output --
;; the tab never shuffles cards by hand.

(fn apply-edit! [transform id]
  "Normalize the persisted edits, apply one pure transform, persist the fresh
   copy, and repaint."
  (let [char (?. Routina :addon :db :char)]
    (when char
      (let [next (transform (plan-edits.normalize char.plan-edits) id)]
        (set char.plan-edits (plan-edits.to-db next)))
      (when Routina.root (Routina.root.refresh!)))))

(fn add-action! [bar text width handler]
  "One small action button on a card's action bar."
  (let [btn (acegui.create! :Button)]
    (when btn
      (btn:SetText text)
      (btn:SetWidth width)
      (btn:SetCallback :OnClick handler)
      (bar:AddChild btn))
    btn))

(fn build-actions! [card step pinned?]
  "The pin/skip/move action bar of one card (SimpleGroup in Flow layout)."
  (let [bar (acegui.create! :SimpleGroup)]
    (when bar
      (bar:SetFullWidth true)
      (bar:SetLayout :Flow)
      (if pinned?
          (do
            (add-action! bar :Unpin 80 #(apply-edit! plan-edits.unpin step.id))
            (add-action! bar "^" 44
                         #(apply-edit! (fn [e id] (plan-edits.move-pin e id -1))
                                       step.id))
            (add-action! bar :v 44
                         #(apply-edit! (fn [e id] (plan-edits.move-pin e id 1))
                                       step.id)))
          (add-action! bar :Pin 80 #(apply-edit! plan-edits.pin step.id)))
      (add-action! bar :Skip 80 #(apply-edit! plan-edits.skip step.id))
      (card:AddChild bar))
    bar))

(fn resolve-skip-name [ctx id]
  "Display name for a skipped activity id: the registry first, then the
   player's custom entries, else the raw id."
  (or (?. (activities.by-id id) :name)
      (accumulate [found nil _ adef (ipairs (or (?. ctx :custom-activities) []))
                   &until found]
        (when (= (tostring adef.id) (tostring id)) adef.name))
      (tostring id)))

(fn build-skipped! [container ctx]
  "Tail card listing skipped activities, one Restore button each. Quiet when
   nothing is skipped."
  (let [skips (or (?. ctx :plan-edits :skips) {})
        rows (icollect [id v (pairs skips)]
               (when (= v true) {: id :name (resolve-skip-name ctx id)}))
        svm (vm.skipped-view-model rows)]
    (when svm
      (let [card (acegui.create! :InlineGroup)]
        (when card
          (card:SetTitle svm.headline)
          (card:SetFullWidth true)
          (card:SetLayout :List)
          (each [_ row (ipairs svm.rows)]
            (let [btn (acegui.create! :Button)]
              (when btn
                (btn:SetText row.label)
                (btn:SetWidth 240)
                (btn:SetCallback :OnClick
                                 #(apply-edit! plan-edits.unskip row.id))
                (card:AddChild btn))))
          (container:AddChild card))
        card))))

;; --- Card (AceGUI InlineGroup) ---------------------------------------------

(fn build-card! [vm rank step ctx ?next]
  "Build one activity card as an InlineGroup from a pure view-model. The raw
   step + ctx (+ the next-ranked step it out-scores) are closed over by the Why?
   button so it can open the drawer with the recommendation diff."
  (let [card (acegui.create! :InlineGroup)]
    (when card
      (card:SetTitle vm.title)
      (card:SetFullWidth true)
      (card:SetLayout :List)
      (let [sub (acegui.create! :Label)]
        (when sub
          (sub:SetText vm.subtitle)
          (sub:SetFullWidth true)
          (acegui.themed-label! sub :ink-faint :body :caption)
          (card:AddChild sub)))
      (let [summary (acegui.create! :Label)]
        (when summary
          (summary:SetText vm.summary)
          (summary:SetFullWidth true)
          (acegui.themed-label! summary :ink-faint :body :body)
          (card:AddChild summary)))
      (when vm.advisory
        (let [adv (acegui.create! :Label)]
          (when adv
            (adv:SetText vm.advisory)
            (adv:SetFullWidth true)
            (acegui.themed-label! adv :warn :body :caption)
            (card:AddChild adv))))
      (each [_ item (ipairs vm.items)]
        (let [row (build-row! item)]
          (when row (card:AddChild row))))
      (build-actions! card step vm.pinned?)
      (let [why (acegui.create! :Button)]
        (when why
          (why:SetText (.. "Why is this #" rank "?"))
          (why:SetWidth 160)
          (why:SetCallback :OnClick
                           (fn []
                             (when Routina.root
                               (Routina.root.show-why! step ctx ?next))))
          (card:AddChild why))))
    card))

;; --- Public API ------------------------------------------------------------

(fn build-projection! [container vm]
  "Tail summary card showing the Monte Carlo fill projection for the week."
  (let [card (acegui.create! :InlineGroup)]
    (when card
      (card:SetTitle vm.headline)
      (card:SetFullWidth true)
      (card:SetLayout :List)
      (let [label (acegui.create! :Label)]
        (when label
          (label:SetText vm.detail)
          (label:SetFullWidth true)
          (acegui.themed-label! label :ink :body :body)
          (card:AddChild label)))
      (container:AddChild card))
    card))

(fn build-lines-card! [container spec]
  "A titled card of plain text lines -- the shared shape of the weekly-goals
   and chain-advisory head cards."
  (let [card (acegui.create! :InlineGroup)]
    (when card
      (card:SetTitle spec.headline)
      (card:SetFullWidth true)
      (card:SetLayout :List)
      (each [_ line (ipairs spec.lines)]
        (let [label (acegui.create! :Label)]
          (when label
            (label:SetText line)
            (label:SetFullWidth true)
            (acegui.themed-label! label :ink :body :body)
            (card:AddChild label))))
      (container:AddChild card))
    card))

(fn add-spacer! [container]
  "A thin full-width blank row, so the score-ordered cards breathe instead of
   stacking flush against each other (UI.md spacing rhythm)."
  (let [s (acegui.create! :Label)]
    (when s
      (s:SetText " ")
      (s:SetFullWidth true)
      (acegui.themed-label! s :ink-faint :body :caption)
      (container:AddChild s))))

(fn add-empty! [container message]
  (let [label (acegui.create! :Label)]
    (when label
      (label:SetText message)
      (label:SetFullWidth true)
      (acegui.themed-label! label :ink-faint :body :body)
      (container:AddChild label))))

(lambda M.render! [container]
  "Repaint the Plan tab into an AceGUI container (the TabGroup). Recomputes the
   plan from the live client and adds a ScrollFrame of activity cards. Idempotent
   -- the caller (src/ui/root.fnl) ReleaseChildren's the container first. No-op
   headless (no AceGUI).
   Domain:  container : an AceGUI container widget
   Returns: nil."
  (release-meters!)
  (let [scroll (acegui.create! :ScrollFrame)]
    (when (and scroll container)
      ;; Fill so the single ScrollFrame spans the whole tab; the scroll's own
      ;; List layout then stacks the cards inside it.
      (container:SetLayout :Fill)
      (scroll:SetLayout :List)
      (scroll:SetFullWidth true)
      (scroll:SetFullHeight true)
      (container:AddChild scroll)
      (let [input (planner.route-input)
            ok? (and input input.ok)
            plan (and ok? (route.plan-week input.player input.ctx))
            steps (if plan plan.steps [])
            advice (and input input.advice)
            ctx (and input input.ctx)
            n (length steps)]
        ;; Head: weekly-goals progress card (Phase 7 §6 -- goals live in the
        ;; Plan tab), then the in-progress attunement advisory; both render
        ;; even when the plan itself is empty.
        (when (and ctx ctx.goals (> (length ctx.goals) 0))
          (let [gvm (vm.goals-view-model (goals.project ctx.goals steps ctx
                                                        {:seed ctx.seed}))]
            (when gvm
              (build-lines-card! scroll gvm)
              (add-spacer! scroll))))
        (let [cvm (vm.chain-advice-view-model (and input input.chain-advice))]
          (when cvm
            (build-lines-card! scroll cvm)
            (add-spacer! scroll)))
        (if (= 0 n)
            (add-empty! scroll
                        (if ok? "Nothing left to chase this week."
                            "Log in to a character to see your plan."))
            (do
              (for [rank 1 n]
                (let [step (. steps rank)
                      next-step (. steps (+ rank 1))
                      card (build-card! (vm.card-view-model step rank advice
                                                            (and ctx
                                                                 ctx.plan-edits))
                                        rank step ctx next-step)]
                  (when card (scroll:AddChild card))
                  (add-spacer! scroll)))
              ;; Tail summary: Monte Carlo projection of slots filled by reset,
              ;; seeded from options (route.project-week defaults the seed).
              (let [projection (route.project-week plan
                                                   {:seed (and ctx ctx.seed)})
                    pvm (vm.projection-view-model projection)]
                (when pvm (build-projection! scroll pvm)))))
        ;; Skipped activities (Phase 8 §2): the restore affordances render
        ;; even when the remaining plan is empty -- a skip must never strand.
        (when ctx
          (build-skipped! scroll ctx)))))
  nil)

(set _G.Routina Routina)
(set Routina.tab-weekly M)

M
