;; fennel-ls project configuration. See https://git.sr.ht/~xerool/fennel-ls/#default-settings
;; WoW runs Lua 5.1; list the WoW API globals we touch so they aren't reported
;; as "unknown identifier" (mirrors diagnostics.globals in .luarc.json).
{:lua-version "lua5.1"
 :extra-globals "DEFAULT_CHAT_FRAME SlashCmdList UnitName"}
