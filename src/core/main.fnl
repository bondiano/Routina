;; main.fnl -- Routina addon entry point.
;;
;; PRE-ACE3 scaffold. Wires `/routina` and `/rt` slash commands to toggle
;; the custom-skinned root panel (src/ui/root.fnl) via raw SLASH_*
;; globals. The full AceAddon lifecycle (OnInitialize, AceDB, options,
;; AceEvent) lands later -- see .claude/examples/04-ace-addon-module.fnl
;; and docs/ROADMAP.md Phase 1.

(local Routina (or _G.Routina {}))
(local root (or Routina.root (require :src.ui.root)))
(local CHAT _G.DEFAULT_CHAT_FRAME)
(local TITLE :|cffC9A24A)
(local RESET :|r)

(fn emit [text]
  (CHAT:AddMessage text))

(fn handle-slash []
  (root.toggle!))

(global SLASH_ROUTINA1 :/routina)
(global SLASH_ROUTINA2 :/rt)
(set _G.SlashCmdList.ROUTINA handle-slash)

(emit (.. TITLE :Routina RESET " loaded. Type " TITLE :/routina RESET
          " to open the planner."))

(set _G.Routina Routina)
