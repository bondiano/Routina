;; tabs/bis.fnl -- BiS tab placeholder.
;;
;; Will hold per-source-activity groups of bis-slot-row widgets. For the
;; v0 scaffold, shows a centered "Coming soon" string. Spec form per
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
     :text "BiS · coming soon"
     :anchors [[:CENTER :parent :CENTER 0 0]]}]])

(lambda M.build! [parent]
  "Build the BiS tab placeholder content frame.
   Domain:  parent : WoW Frame (the content area)
   Returns: the new content frame."
  (. (dom.render! parent (placeholder-spec)) :root))

(set _G.Routina Routina)
(set Routina.tab-bis M)

M
