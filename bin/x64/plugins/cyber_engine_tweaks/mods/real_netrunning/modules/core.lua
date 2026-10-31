-- The CyberScript shared core (organisations, stock market, news, heat and
-- standing), which Real Netrunning runs on. It lives in CyberScript (API 2+,
-- the api-hooks-and-2.5 branch of alainachrest/cyberscript-cp2077-fork) so the
-- other mods and CyberScript's datapacks share the same world.

local Core = { api = nil }

-- The core, or nil if CyberScript (with the core) isn't installed.
function Core.get()
	if Core.api then return Core.api end
	local ok, mod = pcall(GetMod, "cyberscript")
	if not ok or mod == nil or mod.api == nil then return nil end
	if (mod.api.apiVersion or 0) < 2 or mod.api.core == nil then return nil end
	Core.api = mod.api.core
	return Core.api
end

Core.missing = "Real Netrunning needs CyberScript with the shared core (API 2): the api-hooks-and-2.5 build of CyberScript."

return Core
