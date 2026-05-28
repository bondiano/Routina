;; main.fnl -- Routina addon entry point.
;;
;; PLACEHOLDER entry. It registers the `/routina` slash command and announces
;; load, so the build pipeline (Fennel -> build/core/main.lua) and an in-game
;; smoke test have something real to exercise.
;;
;; The full AceAddon lifecycle (OnInitialize/OnEnable, AceDB, options, frames)
;; follows the canonical pattern in `.claude/examples/04-ace-addon-module.fnl`.
;; That step pulls in Ace3 from Libs/ and wires the domain (src/domain/*),
;; event shell (src/core/*) and UI (src/ui/*) submodules; do it then, not here.

(local CHAT _G.DEFAULT_CHAT_FRAME)
(local TITLE :|cff7fbfff)

; addon name highlight
(local RESET :|r)

(fn emit [text]
  (CHAT:AddMessage text))

(fn show-status []
  (emit (.. TITLE :Routina RESET " ready.")))

(global SLASH_ROUTINA1 :/routina)
(global SLASH_ROUTINA2 :/rt)
(set _G.SlashCmdList.ROUTINA show-status)

(emit (.. TITLE :Routina RESET " loaded. Type " TITLE :/routina RESET
          " for status."))
