-- spec/helper.lua -- busted setup, loaded once before any spec (see .busted).
--
-- Three jobs:
--   1. Resolve `(require :src.domain.x)` to the COMPILED Lua at build/domain/x.lua
--      so luacov measures real Lua line coverage of what we ship in-game.
--      `task test` / `task coverage` depend on `task build`, so build/ is fresh.
--   2. Keep the Fennel searcher as a fallback so specs/mocks/helpers (.fnl)
--      can still `require` each other -- those aren't shipped, so they need no
--      precompile step.
--   3. Install WoW API stubs (spec/mocks/wow-api.fnl) before any production
--      module that touches a WoW global is required.

-- Run interpreted rather than JIT-compiled: WoW ships PUC Lua 5.1, so the
-- plain interpreter is the closest match to how this code actually runs.
if jit then
  jit.off()
  jit.flush()
end

local fennel = dofile("vendor/fennel.lua")
package.loaded.fennel = fennel

-- Fennel searcher for the non-shipped .fnl modules (specs, mocks, helpers).
-- Module names like `spec.mocks.wow-api` resolve to ./spec/mocks/wow-api.fnl.
fennel.path = "./?.fnl;./?/init.fnl;" .. fennel.path
table.insert(package.loaders, fennel.searcher)

-- Lua searcher for `src.*` modules: load the compiled Lua from build/ so luacov
-- attributes hits to real, shippable Lua lines (the .fnl/compiled-Lua line
-- correspondence is approximate, and luacov line hooks are unreliable on .fnl).
-- Inserted at position 1 so it wins over the Fennel searcher for `src.*`.
local function build_lua_searcher(modname)
  local rel = modname:match("^src%.(.+)$")
  if not rel then return nil end
  local path = "./build/" .. rel:gsub("%.", "/") .. ".lua"
  local f = io.open(path, "r")
  if not f then
    return "\n\tno file '" .. path .. "' (run `task build`)"
  end
  f:close()
  return assert(loadfile(path))
end
table.insert(package.loaders, 1, build_lua_searcher)

-- Stub WoW globals up front. install! is a Fennel name -> "install!" key in Lua.
require("spec.mocks.wow-api")["install!"]()

-- Stub LibStub + Ace3 so src/core/ace.fnl can be required (its load-time
-- NewAddon needs LibStub). Ace3 is a .pkgmeta external, absent under busted.
require("spec.mocks.ace3")["install!"]()
