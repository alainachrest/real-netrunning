-- Bridge to CyberScript (optional). Uses the extension API added in the
-- api-hooks-and-2.5 branch (cyberscript.api.apiVersion >= 1).
--
-- CyberScript -> Real Netrunning
--   * gang and faction variable changes become bus events and news
--   * datapack webpages become sites on the network
-- Real Netrunning -> CyberScript
--   * actions:  realnetrunning:add_heat, realnetrunning:reveal_network
--   * triggers: realnetrunning:network_owned, realnetrunning:heat_above
--   * variables under tag "realnetrunning": heat, breaches, last_breached

local Network = require("modules/network")

local Bridge = {
	api = nil,
	connected = false,
	retryTimer = 0,
	retryUntil = 120,  -- seconds to keep looking for CyberScript after load
	elapsed = 0,
	siteTimer = 0,
	sites = {},        -- webpage tag -> addr
	lastNews = {},     -- "tag:key" -> time
	bus = nil,
	log = print,
}

local VAR_TAG = "realnetrunning"

local function findApi()
	local ok, mod = pcall(GetMod, "cyberscript")
	if not ok or mod == nil or mod.api == nil then return nil end
	if (mod.api.apiVersion or 0) < 1 then return nil end
	return mod.api
end

local function prettyFaction(tag)
	local name = tostring(tag):gsub("^faction_", ""):gsub("_", " ")
	return name:sub(1, 1):upper() .. name:sub(2)
end

local function onVariable(e)
	if Bridge.bus == nil then return end
	Bridge.bus.emit("cyberscript.variable", e)
	local tag = tostring(e.tag)
	if Network.state and tag:find("^faction_") and type(e.new) == "number" then
		Bridge.bus.emit("world.faction_score", { faction = tag, key = e.key, old = e.old, new = e.new })
		-- one news line per faction/key per 30 seconds, so busy scores don't flood it
		local k = tag .. ":" .. tostring(e.key)
		if (Bridge.lastNews[k] or -1000) + 30 <= Bridge.elapsed then
			Bridge.lastNews[k] = Bridge.elapsed
			local dir = (type(e.old) == "number" and e.new < e.old) and "down" or "up"
			Network.addNews(string.format("%s standing (%s) %s to %s", prettyFaction(tag), tostring(e.key), dir, tostring(e.new)))
		end
	end
end

local function registerSites()
	local ok, list = pcall(Bridge.api.listContent, "webpage")
	if not ok or type(list) ~= "table" then return end
	for _, item in ipairs(list) do
		local addr = "web." .. tostring(item.tag):gsub("[^%w_%-]", "_")
		-- check the network itself, not just our list, in case the world was rebuilt
		if Network.get(addr) == nil then
			local content = Bridge.api.getContent("webpage", item.tag) or {}
			local data = content.data or {}
			local title = data.title or data.name or tostring(item.tag)
			-- use whatever readable text the datapack page has
			local parts = {}
			for _, field in ipairs({ "description", "desc", "text", "body", "content", "summary" }) do
				if type(data[field]) == "string" and data[field] ~= "" then table.insert(parts, data[field]) end
			end
			Network.register({
				addr = addr, name = tostring(title), org = "unregistered", tier = 1, ice = 0,
				kind = "site", known = true,
				site = { text = tostring(title) .. "\n\n" .. (#parts > 0 and table.concat(parts, "\n\n") .. "\n\n" or "") ..
					"CyberScript site from datapack: " .. tostring(item.datapack or "unknown") },
			})
			Bridge.sites[item.tag] = addr
		end
	end
end

local function registerExtensions()
	local api = Bridge.api
	api.registerAction(VAR_TAG .. ":add_heat", function(action)
		Network.addHeat(tonumber(action.value) or 0, "cyberscript datapack")
	end, "Real Netrunning")
	api.registerAction(VAR_TAG .. ":reveal_network", function(action)
		Network.reveal(tostring(action.address or action.value), "cyberscript datapack")
	end, "Real Netrunning")
	api.registerTrigger(VAR_TAG .. ":network_owned", function(trigger)
		return Network.isOwned(tostring(trigger.address or trigger.value))
	end, "Real Netrunning")
	api.registerTrigger(VAR_TAG .. ":heat_above", function(trigger)
		return Network.state.heat > (tonumber(trigger.value) or 0)
	end, "Real Netrunning")
end

local function pushVariables()
	if not Bridge.connected or Network.state == nil then return end
	pcall(Bridge.api.setVariable, VAR_TAG, "heat", Network.state.heat)
	local count = 0
	for _ in pairs(Network.state.owned) do count = count + 1 end
	pcall(Bridge.api.setVariable, VAR_TAG, "breaches", count)
end

function Bridge.connect()
	if Bridge.connected then return true end
	local api = findApi()
	if api == nil then return false end
	Bridge.api = api
	api.on("variable", onVariable)
	registerExtensions()
	Bridge.connected = true
	Bridge.log("connected to CyberScript")
	if Bridge.bus then
		Bridge.bus.on("hack.breach", function(e)
			if e.success then
				pcall(Bridge.api.setVariable, VAR_TAG, "last_breached", e.addr)
				pushVariables()
			end
		end)
		Bridge.bus.on("netwatch.heat", function() pushVariables() end)
	end
	return true
end

function Bridge.update(dt)
	Bridge.elapsed = Bridge.elapsed + dt
	if not Bridge.connected then
		if Bridge.elapsed > Bridge.retryUntil then return end
		Bridge.retryTimer = Bridge.retryTimer + dt
		if Bridge.retryTimer < 2 then return end
		Bridge.retryTimer = 0
		Bridge.connect()
		return
	end
	-- datapacks finish loading after the game starts; pick up new sites every 10 seconds
	Bridge.siteTimer = Bridge.siteTimer + dt
	if Bridge.siteTimer >= 10 then
		Bridge.siteTimer = 0
		registerSites()
	end
end

-- After a save loads the network is rebuilt, so re-add the sites.
function Bridge.onWorldRebuilt()
	Bridge.sites = {}
	if Bridge.connected then
		registerSites()
		pushVariables()
	end
end

return Bridge
