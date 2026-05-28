;; tabs/lockouts.fnl -- Lockouts tab placeholder.
;;
;; Will hold a stack of lockout-timer rows. For the v0 scaffold, shows a
;; centered "Coming soon" string in ink-faint serif. Spec form per
;; docs/UI.md §15.

(local Routina (or _G.Routina {}))
(local dom (or Routina.dom (require :src.ui.dom)))

(local M {})

(fn placeholder-spec []
  [:Frame
   {:fill true}
   [:FontString
    {:font :title
     :size :section
     :color :ink-faint
     :text "Lockouts · coming soon"
     :anchors [[:CENTER :parent :CENTER 0 0]]}]])

(lambda M.build! [parent]
  "Build the Lockouts tab placeholder content frame.
   Domain:  parent : WoW Frame (the content area)
   Returns: the new content frame."
  (. (dom.render! parent (placeholder-spec)) :root))

(set _G.Routina Routina)
(set Routina.tab-lockouts M)

M
