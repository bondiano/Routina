-- spec/all_spec.lua : the only *_spec.lua busted discovers (see .busted).
--
-- busted's Lua loader cannot parse Fennel, so specs stay as *_spec.fnl and we
-- compile + run them here. busted exposes its DSL (describe/it/assert) through
-- this file's environment, so each compiled spec is loaded with that same _ENV;
-- every (describe ...) then registers with busted as a native spec would.

local fennel = require("fennel")

-- busted exposes its DSL through this file's environment. On Lua 5.1/luajit
-- (the WoW target) that's getfenv; on 5.2+ it's _ENV.
local env = getfenv and getfenv(1) or _ENV

local function run_in_env(lua, chunkname)
  if loadstring then -- Lua 5.1 / luajit
    local chunk = assert(loadstring(lua, chunkname))
    setfenv(chunk, env)
    return chunk()
  else -- Lua 5.2+
    return assert(load(lua, chunkname, "t", env))()
  end
end

local found = assert(io.popen("find spec -name '*_spec.fnl' | sort"))
for path in found:lines() do
  local f = assert(io.open(path))
  local src = f:read("*a")
  f:close()
  -- allowedGlobals=false: busted's DSL names aren't known to the compiler.
  local lua = fennel.compileString(src, { filename = path, allowedGlobals = false })
  run_in_env(lua, "@" .. path)
end
found:close()
