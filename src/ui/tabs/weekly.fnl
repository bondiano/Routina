;; tabs/weekly.fnl -- Plan tab content.
;;
;; v0 SCAFFOLD: a single dummy card so the parchment + serif + gold
;; aesthetic is visible in-game without the data layer. Replace
;; `sample-card-spec` with a real activity-card spec + pool once the
;; widget lands (docs/UI.md §6.1). Layout via dom renderer (§15).

(local Routina (or _G.Routina {}))
(local theme (or Routina.theme (require :src.ui.theme)))
(local format (or Routina.format (require :src.ui.format)))
(local dom (or Routina.dom (require :src.ui.dom)))

(local M {})

(fn open-why-drawer []
  (_G.DEFAULT_CHAT_FRAME:AddMessage "|cffC9A24A[Routina]|r why-drawer not implemented yet."))

(fn sample-card-spec []
  ;; TEMP: replace with activity-card widget pool. See docs/UI.md §6.1.
  (let [inset theme.spacing.inset
        rhythm theme.spacing.rhythm]
    [:Frame
     {:id :card
      :height 160
      :anchors [[:TOPLEFT :parent :TOPLEFT 0 0]
                [:TOPRIGHT :parent :TOPRIGHT 0 0]]}
     [:FontString
      {:id :title
       :font :title
       :size :section
       :color :ink
       :text :Karazhan
       :anchors [[:TOPLEFT :card :TOPLEFT inset (- inset)]]}]
     [:FontString
      {:id :sub
       :font :body
       :size :caption
       :color :ink-faint
       :text "Raid · 10-man"
       :anchors [[:TOPLEFT :title :BOTTOMLEFT 0 (- rhythm)]]}]
     [:FontString
      {:font :body
       :size :body
       :color :ink-faint
       :text (.. "~95 min · score " (format.score-short 0.83))
       :anchors [[:TOPRIGHT :card :TOPRIGHT (- inset) (- inset)]]}]
     [:FontString
      {:id :line1
       :font :body
       :size :body
       :color :ink
       :text (.. "T4 Shoulders   " (format.percent 0.62) " / 3 runs")
       :anchors [[:TOPLEFT :sub :BOTTOMLEFT 0 (- (* 2 rhythm))]]}]
     [:FontString
      {:id :line2
       :font :body
       :size :body
       :color :ink
       :text (.. "Ring of a Thousand Marks   " (format.percent 0.28) " / 1 run")
       :anchors [[:TOPLEFT :line1 :BOTTOMLEFT 0 (- rhythm)]]}]
     [:FontString
      {:font :body
       :size :body
       :color :ink
       :text (.. "Aran's Staff   " (format.percent 0.18) " / 1 run")
       :anchors [[:TOPLEFT :line2 :BOTTOMLEFT 0 (- rhythm)]]}]
     [:Button
      {:size [140 18]
       :anchors [[:BOTTOMLEFT :card :BOTTOMLEFT inset inset]]
       :on-click open-why-drawer}
      [:FontString
       {:font :title
        :size :caption
        :color :gold
        :text "[ Why is this #1? ]"
        :anchors [[:LEFT :parent :LEFT 0 0]]}]]]))

(lambda M.build! [parent]
  "Build the Plan tab content frame inside the panel's content area.
   Domain:  parent : WoW Frame (the content area)
   Returns: the new content frame."
  (. (dom.render! parent [:Frame {:fill true} (sample-card-spec)]) :root))

(set _G.Routina Routina)
(set Routina.tab-weekly M)

M
