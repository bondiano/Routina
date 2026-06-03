;; tabs/weekly.fnl -- Plan tab content: a pooled, live-refreshing card stack.
;;
;; END-TO-END SLICE: src/core/planner.fnl reads the live client into a
;; (player, ctx, advice) triple, src/domain/route.fnl scores it against the real
;; catalog, and the steps render as a score-ordered stack of activity cards.
;;
;; UI.md split: the data->render-spec is a PURE view-model (M.card-view-model,
;; busted-tested); applying it to frames is imperative. Cards are POOLED -- built
;; once, reused across refreshes -- so a gear/talent/options change re-renders
;; with no per-refresh CreateFrame (UI.md: frame pools, never per-refresh frames).
;; refresh! is driven by src/core/events.fnl via src/ui/root.fnl.

(local Routina (or _G.Routina {}))
(local theme (or Routina.theme (require :src.ui.theme)))
(local format (or Routina.format (require :src.ui.format)))
(local dom (or Routina.dom (require :src.ui.dom)))
(local route (or Routina.route (require :src.domain.route)))
(local planner (or Routina.planner (require :src.core.planner)))

(local M {})

;; --- Layout constants ------------------------------------------------------

(local max-cards 4)
;; cards shown before an overflow note (no scroll frame yet)
(local max-rows 3)
;; top-N target items per card (PRD §6.1 G2: "top 3 target items")
(local rows-top 64)
(local row-step 24)
(local row-height 20)
(local card-foot 28)
(local card-gap 8)

(fn card-height []
  (+ rows-top (* max-rows row-step) card-foot))

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn run-word [runs]
  (if (= runs 1) " run" " runs"))

(fn item-line [item]
  (.. item.label "   " (format.percent item.chance) " / " item.runs
      (run-word item.runs)))

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
             :items [{:text string :item-id ?integer} ...<= max-rows]}"
  {:title (.. "#" rank "  " (tostring step.name))
   :subtitle (.. (tostring step.type) " · " (tostring step.detail))
   :summary (.. "~" step.minutes " min · score "
                (format.score-short step.score))
   :advisory (let [text (and step.attunement ?advice
                             (. ?advice step.attunement))]
               (and text (.. "Requires " text)))
   :items (icollect [_ it (ipairs (top-items step.items))]
            {:text (item-line it) :item-id it.item-id})})

;; --- Event handlers (imperative, per UI.md §15) ----------------------------

(fn item-row-enter [self]
  "Show the standard item tooltip for the id stashed on the row by populate!."
  (when self.tooltip-item-id
    (_G.GameTooltip:SetOwner self :ANCHOR_RIGHT)
    (_G.GameTooltip:SetItemByID self.tooltip-item-id)
    (_G.GameTooltip:Show)))

(fn item-row-leave [_self]
  (_G.GameTooltip:Hide))

(fn open-why-drawer [_self]
  (_G.DEFAULT_CHAT_FRAME:AddMessage "|cffC9A24A[Routina]|r why-drawer not implemented yet."))

;; --- Card frame spec (built once per pool slot, then populated) ------------

(fn row-spec [rank i]
  "One hoverable, full-width item row at a fixed depth in card `rank`."
  (let [inset theme.spacing.inset
        text-pad theme.spacing.rhythm
        card-id (.. :card rank)
        y (+ rows-top (* (- i 1) row-step))]
    [:Button
     {:id (.. :rowbtn rank "-" i)
      :height row-height
      :highlight :row-highlight
      :anchors [[:TOPLEFT card-id :TOPLEFT inset (- y)]
                [:TOPRIGHT card-id :TOPRIGHT (- inset) (- y)]]
      :on-enter item-row-enter
      :on-leave item-row-leave}
     [:Texture {:layer :BORDER :texture-token :row-cell :fill-parent? true}]
     [:FontString
      {:id (.. :rowfs rank "-" i)
       :font :body
       :size :body
       :color :ink
       :anchors [[:LEFT :parent :LEFT text-pad 0]]}]]))

(fn card-spec [rank anchor]
  "Fixed card structure (placeholder text); populate-card! fills it per refresh."
  (let [inset theme.spacing.inset
        rhythm theme.spacing.rhythm
        card-id (.. :card rank)
        node [:Frame
              {:id card-id
               :height (card-height)
               :backdrop :parchment-2
               :anchors anchor}
              [:FontString
               {:id (.. :title rank)
                :font :title
                :size :section
                :color :ink
                :anchors [[:TOPLEFT card-id :TOPLEFT inset (- inset)]]}]
              [:FontString
               {:id (.. :sub rank)
                :font :body
                :size :caption
                :color :ink-faint
                :anchors [[:TOPLEFT (.. :title rank) :BOTTOMLEFT 0 (- rhythm)]]}]
              [:FontString
               {:id (.. :summary rank)
                :font :body
                :size :body
                :color :ink-faint
                :anchors [[:TOPRIGHT card-id :TOPRIGHT (- inset) (- inset)]]}]
              [:FontString
               {:id (.. :advisory rank)
                :font :body
                :size :caption
                :color :warn
                :anchors [[:TOPLEFT (.. :sub rank) :BOTTOMLEFT 0 (- rhythm)]]}]
              [:Button
               {:id (.. :why rank)
                :size [140 16]
                :anchors [[:BOTTOMLEFT card-id :BOTTOMLEFT inset rhythm]]
                :on-click open-why-drawer}
               [:FontString
                {:font :title
                 :size :caption
                 :color :gold
                 :text (.. "[ Why is this #" rank "? ]")
                 :anchors [[:LEFT :parent :LEFT 0 0]]}]]]]
    (for [i 1 max-rows]
      (table.insert node (row-spec rank i)))
    node))

;; --- Pool + refresh (imperative singleton state) ---------------------------

(var container nil)

(local cards [])

(var empty-fs nil)

(var overflow-fs nil)

(fn card-top [rank]
  "Y-offset (negative, from the container top) of card `rank`."
  (- (* (- rank 1) (+ (card-height) card-gap))))

(fn card-anchor [rank]
  ;; Each card is positioned by index against the container, NOT chained to the
  ;; previous card: every card is a separate dom.render! with its own refs, so a
  ;; cross-card ref-key wouldn't resolve.
  (let [y (card-top rank)]
    [[:TOPLEFT :parent :TOPLEFT 0 y] [:TOPRIGHT :parent :TOPRIGHT 0 y]]))

(fn build-card! [rank]
  "Render card `rank` once and capture the frame handles populate-card! sets."
  (let [{: refs} (dom.render! container (card-spec rank (card-anchor rank)))
        rows (fcollect [i 1 max-rows]
               {:button (. refs (.. :rowbtn rank "-" i))
                :fs (. refs (.. :rowfs rank "-" i))})]
    {:frame (. refs (.. :card rank))
     :title (. refs (.. :title rank))
     :sub (. refs (.. :sub rank))
     :summary (. refs (.. :summary rank))
     :advisory (. refs (.. :advisory rank))
     : rows}))

(fn ensure-card! [rank]
  "The pooled card for `rank`, built on first use."
  (or (. cards rank) (let [c (build-card! rank)]
                       (tset cards rank c)
                       c)))

(fn populate-card! [c vm]
  "Apply a pure view-model to a pooled card's frames."
  (c.title:SetText vm.title)
  (c.sub:SetText vm.subtitle)
  (c.summary:SetText vm.summary)
  (if vm.advisory
      (do
        (c.advisory:SetText vm.advisory)
        (c.advisory:Show))
      (c.advisory:Hide))
  (each [i row (ipairs c.rows)]
    (let [item (. vm.items i)]
      (if item
          (do
            (row.fs:SetText item.text)
            (set row.button.tooltip-item-id item.item-id)
            (row.button:Show))
          (row.button:Hide))))
  (c.frame:Show))

(fn release-all! []
  (each [_ c (ipairs cards)]
    (c.frame:Hide)))

(fn ensure-empty-fs! []
  (when (not empty-fs)
    (set empty-fs (. (dom.render! container
                                  [:FontString
                                   {:font :body
                                    :size :body
                                    :color :ink-faint
                                    :anchors [[:CENTER :parent :CENTER 0 0]]}])
                     :root)))
  empty-fs)

(fn ensure-overflow-fs! []
  (when (not overflow-fs)
    ;; just below the last possible card; anchored to the container, since this
    ;; is its own dom.render! and can't reference a card frame's ref-key.
    (let [y (- (* max-cards (+ (card-height) card-gap)))]
      (set overflow-fs (. (dom.render! container
                                       [:FontString
                                        {:font :body
                                         :size :caption
                                         :color :ink-faint
                                         :anchors [[:TOPLEFT
                                                    :parent
                                                    :TOPLEFT
                                                    0
                                                    y]]}])
                          :root))))
  overflow-fs)

(fn show-empty! [message]
  (let [fs (ensure-empty-fs!)]
    (fs:SetText message)
    (fs:Show)))

(fn hide-empty! []
  (when empty-fs (empty-fs:Hide)))

(fn show-overflow! [n]
  (let [fs (ensure-overflow-fs!)]
    (fs:SetText (.. "+ " n " more this week"))
    (fs:Show)))

(fn hide-overflow! []
  (when overflow-fs (overflow-fs:Hide)))

;; --- Public API ------------------------------------------------------------

(lambda M.refresh! []
  "Recompute the plan from the live client and repaint the pooled cards.
   Safe to call before build! (no-op) and repeatedly (pool is reused).
   Returns: nil."
  (when container
    (release-all!)
    (hide-overflow!)
    (let [input (planner.route-input)
          ok? (and input input.ok)
          steps (if ok? (. (route.plan-week input.player input.ctx) :steps) [])
          advice (and input input.advice)
          shown (math.min (length steps) max-cards)]
      (if (= 0 (length steps))
          (show-empty! (if ok? "Nothing left to chase this week."
                           "Log in to a character to see your plan."))
          (do
            (hide-empty!)
            (for [rank 1 shown]
              (populate-card! (ensure-card! rank)
                              (M.card-view-model (. steps rank) rank advice)))
            (when (> (length steps) max-cards)
              (show-overflow! (- (length steps) max-cards)))))))
  nil)

(lambda M.build! [parent]
  "Build the Plan tab container and do the first paint.
   Domain:  parent : WoW Frame (the content area)
   Returns: the content frame."
  (set container (. (dom.render! parent [:Frame {:fill true}]) :root))
  (M.refresh!)
  container)

(set _G.Routina Routina)
(set Routina.tab-weekly M)

M
