;; why-drawer.fnl -- the in-panel "Why is this here?" explainer (UI.md §6.6).
;;
;; Replaces a modal popup with a slide-in from the right half of the root frame.
;; UI.md split: M.view-model is a PURE explainer spec (busted-tested); the
;; singleton frame, its slide-in OnUpdate (the only animation that runs to
;; completion), and open!/close! are imperative shell (wowUnit-tier).
;;
;; Singleton, NOT pooled: built once on first open, repopulated each open. The
;; breakdown rows are pre-created (max-rows) and shown/hidden, so a repaint
;; allocates no frames.

(local Routina (or _G.Routina {}))
(local theme (or Routina.theme (require :src.ui.theme)))
(local format (or Routina.format (require :src.ui.format)))
(local dom (or Routina.dom (require :src.ui.dom)))
(local CreateFrame _G.CreateFrame)

(local M {})

;; --- Constants -------------------------------------------------------------

(local drawer-width 260)
;; ~right half of the 520-wide root
(local max-rows 8)
;; pre-created breakdown lines (an activity rarely lists more)
(local rows-top 52)
(local row-step 22)
(local slide-seconds (/ theme.motion.slide-ms 1000))

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn weight-of [ctx slot]
  (or (and ctx ctx.weights slot (. ctx.weights slot)) 1))

(fn competitors-of [ctx id]
  (or (and ctx ctx.competitors id (. ctx.competitors id))
      (and ctx ctx.default-competitors) 1))

(fn by-contribution-desc [a b]
  (> a.contribution b.contribution))

(lambda M.view-model [step ?ctx]
  "Pure explainer spec for one plan step (UI.md §6.6 inputs).
   Domain:  step : a route step {:name :id :score :attunement?
                   :items [{:label :slot :chance :runs} ...]}
            ?ctx : the RouteContext (for slot weights + competitors), optional
   Returns: {:title string
             :score-breakdown [{:label :slot :weight :chance :contribution} ...]
                              -- contribution desc (weight · chance)
             :weight-explanation string|nil
             :competition-note string|nil}"
  (let [rows (icollect [_ it (ipairs (or step.items []))]
               (let [w (weight-of ?ctx it.slot)]
                 {:label it.label
                  :slot it.slot
                  :weight w
                  :chance it.chance
                  :contribution (* w it.chance)}))
        weighted (icollect [_ r (ipairs rows)] (when (not= r.weight 1) r))
        competitors (competitors-of ?ctx step.id)]
    (table.sort rows by-contribution-desc)
    {:title (tostring step.name)
     :score-breakdown rows
     :weight-explanation (when (> (length weighted) 0)
                           (.. (length weighted)
                               " slot(s) weighted above default"))
     :competition-note (when (> competitors 1)
                         (.. "Drop chance split among " competitors
                             " in the loot pool"))}))

;; --- Singleton frame (imperative; built once, repopulated per open) --------

(var frame nil)

(var refs nil)

(var anchor-parent nil)

(fn row-line [r]
  (.. r.label "   ×" r.weight "   " (format.percent r.chance)))

(fn drawer-spec []
  (let [inset theme.spacing.inset
        rhythm theme.spacing.rhythm
        node [:Frame
              {:id :drawer
               :name :RoutinaWhyDrawer
               :strata :DIALOG
               :width drawer-width
               :backdrop :parchment
               :border? true
               :anchors [[:TOPRIGHT :parent :TOPRIGHT 0 (- (* 3 inset))]
                         [:BOTTOMRIGHT :parent :BOTTOMRIGHT 0 inset]]}
              [:FontString
               {:id :title
                :font :title
                :size :section
                :color :ink
                :anchors [[:TOPLEFT :drawer :TOPLEFT inset (- inset)]]}]
              [:Texture
               {:id :sep
                :layer :ARTWORK
                :fill-color :gold
                :alpha 0.6
                :height 1
                :anchors [[:TOPLEFT :title :BOTTOMLEFT 0 (- rhythm)]
                          [:TOPRIGHT
                           :drawer
                           :TOPRIGHT
                           (- inset)
                           (- (+ inset 24))]]}]
              [:FontString
               {:id :notes
                :font :body
                :size :caption
                :color :ink-faint
                :anchors [[:BOTTOMLEFT :drawer :BOTTOMLEFT inset (+ inset 22)]
                          [:BOTTOMRIGHT
                           :drawer
                           :BOTTOMRIGHT
                           (- inset)
                           (+ inset 22)]]}]
              [:Button
               {:id :close
                :size [60 18]
                :anchors [[:BOTTOMRIGHT :drawer :BOTTOMRIGHT (- inset) inset]]
                :on-click #(M.close!)}
               [:FontString
                {:font :title
                 :size :caption
                 :color :gold
                 :text "[ Close ]"
                 :anchors [[:CENTER :parent :CENTER 0 0]]}]]]]
    (for [i 1 max-rows]
      (let [y (+ rows-top (* (- i 1) row-step))]
        (table.insert node [:FontString
                            {:id (.. :wrow i)
                             :font :body
                             :size :body
                             :color :ink
                             :anchors [[:TOPLEFT
                                        :drawer
                                        :TOPLEFT
                                        theme.spacing.inset
                                        (- y)]]}])))
    node))

(fn build! [parent]
  (let [rendered (dom.render! parent (drawer-spec))]
    (set frame rendered.root)
    (set refs rendered.refs)
    (when (and _G.UISpecialFrames frame.GetName (frame:GetName))
      (table.insert _G.UISpecialFrames (frame:GetName)))
    frame))

(fn place! [x]
  "Pin the drawer to the parent's right edge, offset by x (slide axis)."
  (let [inset theme.spacing.inset]
    (frame:ClearAllPoints)
    (frame:SetPoint :TOPRIGHT anchor-parent :TOPRIGHT x (- (* 3 inset)))
    (frame:SetPoint :BOTTOMRIGHT anchor-parent :BOTTOMRIGHT x inset)))

(fn start-slide! []
  "Tween the drawer in from off the right edge; self-disabling at 200 ms."
  (var elapsed 0)
  (place! drawer-width)
  (frame:Show)
  (frame:SetScript :OnUpdate
                   (fn [self dt]
                     (set elapsed (+ elapsed dt))
                     (let [frac (math.min 1 (/ elapsed slide-seconds))]
                       (place! (* drawer-width (- 1 frac)))
                       (when (>= frac 1) (self:SetScript :OnUpdate nil))))))

(fn populate! [vm]
  (refs.title:SetText vm.title)
  (for [i 1 max-rows]
    (let [fs (. refs (.. :wrow i))
          row (. vm.score-breakdown i)]
      (if row
          (do
            (fs:SetText (row-line row))
            (fs:Show))
          (fs:Hide))))
  (let [notes (or vm.weight-explanation vm.competition-note)
        both (if (and vm.weight-explanation vm.competition-note)
                 (.. vm.weight-explanation " · " vm.competition-note)
                 notes)]
    (refs.notes:SetText (or both ""))))

;; --- Public API ------------------------------------------------------------

(lambda M.open! [parent step ?ctx]
  "Open (or re-open) the drawer for a plan step, sliding in over the right half
   of `parent` (the root frame). Builds the singleton on first call.
   Domain:  parent : WoW Frame (root); step : a route step; ?ctx : RouteContext
   Returns: nil."
  (set anchor-parent parent)
  (when (not frame) (build! parent))
  (populate! (M.view-model step ?ctx))
  (start-slide!)
  nil)

(lambda M.close! []
  "Hide the drawer if it exists. Returns: nil."
  (when frame
    (frame:SetScript :OnUpdate nil)
    (frame:Hide))
  nil)

;; --- Register --------------------------------------------------------------

(set _G.Routina Routina)
(set Routina.why-drawer M)

M
