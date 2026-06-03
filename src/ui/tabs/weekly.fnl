;; tabs/weekly.fnl -- Plan tab content: a live, score-ordered card stack on
;; AceGUI-3.0.
;;
;; END-TO-END SLICE: src/core/planner.fnl reads the live client into a
;; (player, ctx, advice) triple, src/domain/route.fnl scores it against the real
;; catalog, and the steps render as a score-ordered stack of InlineGroup cards.
;;
;; UI.md split: the data->render-spec is a PURE view-model (M.card-view-model,
;; busted-tested); building the AceGUI widgets from it is imperative. AceGUI
;; pools its own widgets, so render! just ReleaseChildren-then-rebuild -- there
;; is no bespoke frame pool any more. render! is driven by src/ui/root.fnl
;; (OnGroupSelected + refresh!), itself fed by src/core/events.fnl.
;;
;; NOTE: the chance is shown as text + item-quality colour. The proportional
;; chance-meter bar from the old custom UI is deferred -- a per-pixel fill
;; fights AceGUI's deferred layout (card width is unknown until DoLayout) and is
;; better reintroduced later as a small standalone meter widget.

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))
(local format (or Routina.format (require :src.ui.format)))
(local route (or Routina.route (require :src.domain.route)))
(local planner (or Routina.planner (require :src.core.planner)))
(local GetItemInfo _G.GetItemInfo)
(local GetItemIcon _G.GetItemIcon)
(local GetItemQualityColor _G.GetItemQualityColor)
(local GameTooltip _G.GameTooltip)

(local M {})

;; --- Layout constants ------------------------------------------------------

;; top-N target items per card (PRD §6.1 G2: "top 3 target items")
(local max-rows 3)
(local epic-quality 4)

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn run-word [runs]
  (if (= runs 1) " run" " runs"))

(fn chance-text [item]
  "The chance column: 'NN% · K run(s)'."
  (.. (format.percent item.chance) " · " item.runs (run-word item.runs)))

(fn by-chance-desc [a b]
  (> a.chance b.chance))

(fn top-items [items]
  "The max-rows highest-chance items, as a fresh sorted copy (input untouched)."
  (let [sorted (icollect [_ it (ipairs items)] it)]
    (table.sort sorted by-chance-desc)
    (fcollect [i 1 (math.min max-rows (length sorted))]
      (. sorted i))))

(lambda M.card-view-model [step rank ?advice]
  "Pure render spec for one activity card.
   Domain:  step   : a route.plan-week step {:name :type :detail :minutes :score
                     :attunement? :items [{:label :chance :runs :item-id} ...]}
            rank   : integer >= 1 (display rank)
            ?advice: {attune-slug text} -- soft 'not attuned' notes, or nil
   Returns: {:title :subtitle :summary :advisory? string
             :items [{:name string :chance-text string :item-id ?integer}
                     ...<= max-rows]}"
  {:title (.. "#" rank "  " (tostring step.name))
   :subtitle (.. (tostring step.type) " · " (tostring step.detail))
   :summary (.. "~" step.minutes " min · score "
                (format.score-short step.score))
   :advisory (let [text (and step.attunement ?advice
                             (. ?advice step.attunement))]
               (and text (.. "Requires " text)))
   :items (icollect [_ it (ipairs (top-items step.items))]
            {:name it.label :chance-text (chance-text it) :item-id it.item-id})})

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

(fn build-row! [item]
  "One hoverable item row: an InteractiveLabel showing icon + name, quality
   coloured, with chance text and the native item tooltip on hover."
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
      (row:SetCallback :OnLeave on-row-leave))
    row))

;; --- Card (AceGUI InlineGroup) ---------------------------------------------

(fn build-card! [vm rank step ctx]
  "Build one activity card as an InlineGroup from a pure view-model. The raw
   step + ctx are closed over by the Why? button so it can open the drawer."
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
      (let [why (acegui.create! :Button)]
        (when why
          (why:SetText (.. "Why is this #" rank "?"))
          (why:SetWidth 160)
          (why:SetCallback :OnClick
                           (fn []
                             (when Routina.root
                               (Routina.root.show-why! step ctx))))
          (card:AddChild why))))
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
  "Repaint the Plan tab into an AceGUI container (the TabGroup). Recomputes the
   plan from the live client and adds a ScrollFrame of activity cards. Idempotent
   -- the caller (src/ui/root.fnl) ReleaseChildren's the container first. No-op
   headless (no AceGUI).
   Domain:  container : an AceGUI container widget
   Returns: nil."
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
            steps (if ok? (. (route.plan-week input.player input.ctx) :steps)
                      [])
            advice (and input input.advice)
            ctx (and input input.ctx)
            n (length steps)]
        (if (= 0 n)
            (add-empty! scroll
                        (if ok? "Nothing left to chase this week."
                            "Log in to a character to see your plan."))
            (for [rank 1 n]
              (let [step (. steps rank)
                    card (build-card! (M.card-view-model step rank advice) rank
                                      step ctx)]
                (when card (scroll:AddChild card))))))))
  nil)

(set _G.Routina Routina)
(set Routina.tab-weekly M)

M
