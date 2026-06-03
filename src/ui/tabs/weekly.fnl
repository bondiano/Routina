;; tabs/weekly.fnl -- Plan tab content.
;;
;; END-TO-END SLICE: src/core/planner.fnl reads the live client (gear, spec,
;; phase, lockouts) into a (player, ctx) pair, src/domain/route.fnl scores it
;; against the real catalog (activities + bis-catalog + drop-table +
;; drop-chance), and the resulting steps render as a score-ordered stack of
;; activity cards. No scaffold inputs remain; an empty plan (loading screen or
;; nothing left to chase) shows a placeholder instead of cards.
;;
;; Card layout is data (dom.render!, docs/UI.md s15). Item rows are
;; hoverable buttons that show the standard game tooltip via
;; GameTooltip:SetItemByID (UI.md: no tooltip-text synthesis). The
;; activity-card widget pool (UI.md s6.1) replaces the inline spec later.

(local Routina (or _G.Routina {}))
(local theme (or Routina.theme (require :src.ui.theme)))
(local format (or Routina.format (require :src.ui.format)))
(local dom (or Routina.dom (require :src.ui.dom)))
(local route (or Routina.route (require :src.domain.route)))
(local planner (or Routina.planner (require :src.core.planner)))

(local M {})

;; --- Layout constants (card geometry; theme owns colours/fonts/sizes) ------

(local rows-top 54)
;; y of the first item row below the card's top edge
(local row-step 24)
;; vertical step between item rows
(local row-height 20)
;; height of each item cell (row-step leaves a gap between cell borders)
(local card-foot 28)
;; reserved below the last row for the "Why?" button

(fn card-height [n-items]
  "Card height that snugly fits a title block, n item rows, and the footer."
  (+ rows-top (* n-items row-step) card-foot))

;; --- Event handlers (imperative, per UI.md s15) ----------------------------

(fn item-tooltip-enter [item-id]
  "Build an OnEnter handler that shows the standard item tooltip.
   No tooltip text synthesis -- GameTooltip:SetItemByID owns the content.
   Item-id may be nil (scaffold gap); then the row is simply inert."
  (fn [self]
    (when item-id
      (_G.GameTooltip:SetOwner self :ANCHOR_RIGHT)
      (_G.GameTooltip:SetItemByID item-id)
      (_G.GameTooltip:Show))))

(fn item-tooltip-leave [_self]
  (_G.GameTooltip:Hide))

(fn open-why-drawer [_self]
  (_G.DEFAULT_CHAT_FRAME:AddMessage "|cffC9A24A[Routina]|r why-drawer not implemented yet."))

;; --- Layout spec -----------------------------------------------------------

(fn run-word [runs]
  (if (= runs 1) " run" " runs"))

(fn item-row-spec [id item card-id y]
  "One full-width, hoverable item row positioned at depth `y` in the card.
   Anchored to the card's top edge (not chained) so the hover area spans
   the card and every row shares a consistent baseline."
  (let [inset theme.spacing.inset
        text-pad theme.spacing.rhythm]
    [:Button
     {: id
      :height row-height
      ;; Each row is a soft DUI-style cell: the hand-painted hollow border
      ;; (:row-cell texture below) frames it; :row-highlight adds the
      ;; standard gold mouse-over glow.
      :highlight :row-highlight
      :anchors [[:TOPLEFT card-id :TOPLEFT inset (- y)]
                [:TOPRIGHT card-id :TOPRIGHT (- inset) (- y)]]
      :on-enter (item-tooltip-enter item.item-id)
      :on-leave item-tooltip-leave}
     [:Texture {:layer :BORDER :texture-token :row-cell :fill-parent? true}]
     [:FontString
      {:font :body
       :size :body
       :color :ink
       :text (.. item.label "   " (format.percent item.chance) " / " item.runs
                 (run-word item.runs))
       :anchors [[:LEFT :parent :LEFT text-pad 0]]}]]))

(fn card-spec [row rank top-anchor]
  "Spec for one ranked activity card. Ids are rank-suffixed so a stacked
   set of cards keeps unique :id keys in the shared refs table."
  (let [inset theme.spacing.inset
        rhythm theme.spacing.rhythm
        card-id (.. :card rank)
        title-id (.. :title rank)
        sub-id (.. :sub rank)
        node [:Frame
              {:id card-id
               :height (card-height (length row.items))
               :backdrop :parchment-2
               :anchors top-anchor}
              [:FontString
               {:id title-id
                :font :title
                :size :section
                :color :ink
                :text (.. "#" rank "  " row.name)
                :anchors [[:TOPLEFT card-id :TOPLEFT inset (- inset)]]}]
              [:FontString
               {:id sub-id
                :font :body
                :size :caption
                :color :ink-faint
                :text (.. row.type " · " row.detail)
                :anchors [[:TOPLEFT title-id :BOTTOMLEFT 0 (- rhythm)]]}]
              [:FontString
               {:font :body
                :size :body
                :color :ink-faint
                :text (.. "~" row.minutes " min · score "
                          (format.score-short row.score))
                :anchors [[:TOPRIGHT card-id :TOPRIGHT (- inset) (- inset)]]}]]]
    (each [i item (ipairs row.items)]
      (let [y (+ rows-top (* (- i 1) row-step))]
        (table.insert node (item-row-spec (.. :item rank "-" i) item card-id y))))
    (table.insert node
                  [:Button
                   {:size [140 16]
                    :anchors [[:BOTTOMLEFT card-id :BOTTOMLEFT inset rhythm]]
                    :on-click open-why-drawer}
                   [:FontString
                    {:font :title
                     :size :caption
                     :color :gold
                     :text (.. "[ Why is this #" rank "? ]")
                     :anchors [[:LEFT :parent :LEFT 0 0]]}]])
    node))

(fn stack-spec [rows]
  "Wrap the ranked cards in a fill frame: card N anchors below card N-1.
   Builds the node imperatively (UI shell, not domain) so the result is a
   single `[:Frame attrs & children]` node dom.render! can walk."
  (let [rhythm theme.spacing.rhythm
        node [:Frame {:fill true}]]
    (each [rank row (ipairs rows)]
      (let [anchor (if (= rank 1)
                       [[:TOPLEFT :parent :TOPLEFT 0 0]
                        [:TOPRIGHT :parent :TOPRIGHT 0 0]]
                       [[:TOPLEFT
                         (.. :card (- rank 1))
                         :BOTTOMLEFT
                         0
                         (- rhythm)]
                        [:TOPRIGHT
                         (.. :card (- rank 1))
                         :BOTTOMRIGHT
                         0
                         (- rhythm)]])]
        (table.insert node (card-spec row rank anchor))))
    node))

(fn empty-spec [message]
  "A centered note shown when the plan has no steps (loading, or done for the
   week) -- a blank card stack would read as broken."
  [:Frame
   {:fill true}
   [:FontString
    {:font :body
     :size :body
     :color :ink-faint
     :text message
     :anchors [[:CENTER :parent :CENTER 0 0]]}]])

;; --- Construction ----------------------------------------------------------

(lambda M.build! [parent]
  "Build the Plan tab content: the live, scored, ordered weekly plan.
   Reads the current character via src/core/planner.fnl and scores it through
   src/domain/route.fnl; falls back to a placeholder when no plan is available.
   Domain:  parent : WoW Frame (the content area)
   Returns: the new content frame."
  (let [input (planner.route-input)
        steps (if input.ok (. (route.plan-week input.player input.ctx) :steps)
                  [])
        spec (if (> (length steps) 0)
                 (stack-spec steps)
                 (empty-spec (if input.ok "Nothing left to chase this week."
                                 "Log in to a character to see your plan.")))]
    (. (dom.render! parent spec) :root)))

(set _G.Routina Routina)
(set Routina.tab-weekly M)

M
