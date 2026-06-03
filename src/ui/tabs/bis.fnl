;; tabs/bis.fnl -- BiS tab placeholder (AceGUI).
;;
;; Will hold per-source-activity groups of bis-slot-row widgets. For the v0
;; scaffold, shows a centered "coming soon" label. render! follows the tab
;; contract in src/ui/root.fnl: idempotent populate of the AceGUI container.

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))

(local M {})

(lambda M.render! [container]
  "Populate the BiS tab placeholder into an AceGUI container. No-op headless
   (no AceGUI).
   Domain:  container : an AceGUI container widget
   Returns: nil."
  (let [label (acegui.create! :Label)]
    (when (and label container)
      (container:SetLayout :List)
      (label:SetText "BiS · coming soon")
      (label:SetFullWidth true)
      (acegui.themed-label! label :ink-faint :title :section)
      (container:AddChild label)))
  nil)

(set _G.Routina Routina)
(set Routina.tab-bis M)

M
