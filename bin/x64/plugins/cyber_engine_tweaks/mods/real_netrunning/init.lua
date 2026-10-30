--[[
Real Netrunning
Grey Hack-style netrunning for Cyberpunk 2077, built from Night City's own lore.

Open the CET overlay to use the cyberdeck (CET only gives ImGui input while the
overlay is open). Type 'help' in the deck.

Other mods: local rn = GetMod("real_netrunning") -- see rn.api below.
]]

local GameSession = require("lib/GameSession")
local GameHUD = require("lib/GameHUD")

local Bus = require("modules/bus")
local Network = require("modules/network")
local World = require("modules/world")
local Shell = require("modules/shell")
local Terminal = require("modules/terminal")
local Bridge = require("modules/cyberscript")

local RealNetrunning = {
	version = "0.1.0",
	ready = false,
	overlayOpen = false,
}

local function log(msg)
	print("[Real Netrunning] " .. tostring(msg))
end

-- Everything that must survive saving and loading. GameSession writes this table
-- per save slot into the sessions folder.
local Persisted = Network.newState()

Bus.log = log
World.log = log
Bridge.log = log
Network.bus = Bus
Shell.bus = Bus
Bridge.bus = Bus

---------------------------------------------------------------------------
-- Session handling
---------------------------------------------------------------------------

local function migrate(state)
	local fresh = Network.newState()
	for k, v in pairs(fresh) do
		if state[k] == nil then state[k] = v end
	end
	if state.seed == nil then
		state.seed = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
	end
end

local function startWorld()
	migrate(Persisted)
	Network.state = Persisted
	Network.build()
	Shell.reset()
	Bridge.onWorldRebuilt()
	RealNetrunning.ready = true
	Shell.print("Cyberdeck online. Type 'help' to start, 'scan' to find networks.", "ok")
end

-- Turns bus events into news lines, so world reactions are visible in 'news'.
local function newsFromEvents(e, event)
	if Network.state == nil then return end
	local net = e.addr and Network.get(e.addr)
	local name = net and net.name or e.addr
	if event == "hack.breach" and e.success then
		Network.addNews("Unknown netrunner breached " .. tostring(name))
	elseif event == "netwatch.traced" then
		Network.addNews("NetWatch traced an intrusion into " .. tostring(name))
	elseif event == "hack.download" then
		Network.addNews(tostring(name) .. " reports a data leak")
	end
end

---------------------------------------------------------------------------
-- CET events
---------------------------------------------------------------------------

registerForEvent("onInit", function()
	math.randomseed(os.time())
	pcall(GameHUD.Initialize)
	World.hud = GameHUD

	GameSession.StoreInDir("sessions")
	GameSession.Persist(Persisted, true)
	GameSession.OnStart(startWorld)
	GameSession.OnEnd(function()
		RealNetrunning.ready = false
		Shell.reset()
	end)

	Bus.on("*", newsFromEvents)

	-- Mod reloaded while already in game
	if GameSession.IsLoaded() then startWorld() end

	Bridge.connect()
	log("v" .. RealNetrunning.version .. " loaded")
end)

registerForEvent("onUpdate", function(dt)
	Bridge.update(dt)
	if RealNetrunning.ready then
		Shell.update(dt)
	end
end)

registerForEvent("onOverlayOpen", function() RealNetrunning.overlayOpen = true end)
registerForEvent("onOverlayClose", function() RealNetrunning.overlayOpen = false end)

registerForEvent("onDraw", function()
	if RealNetrunning.overlayOpen and RealNetrunning.ready then
		Terminal.draw()
	end
end)

registerHotkey("rn_toggle_deck", "Show or hide the cyberdeck", function()
	Terminal.visible = not Terminal.visible
end)

---------------------------------------------------------------------------
-- API for other mods
---------------------------------------------------------------------------

RealNetrunning.api = {
	apiVersion = 1,
	-- Events: "hack.breach", "hack.download", "hack.connected", "hack.disconnected",
	-- "netwatch.traced", "netwatch.heat", "network.revealed", "network.breached",
	-- "device.action", "world.faction_score", "cyberscript.variable", or "*" for all.
	on = Bus.on,
	off = Bus.off,
	emit = Bus.emit,
	getHeat = function() return Network.state and Network.state.heat or 0 end,
	addHeat = function(amount, why) if Network.state then Network.addHeat(amount, why) end end,
	isOwned = function(addr) return Network.state ~= nil and Network.isOwned(addr) end,
	reveal = function(addr) return Network.state ~= nil and Network.reveal(addr, "api") end,
	-- def = { addr, name, org, tier, ice, reveals, known, files = { ["path"] = { text, paydata } } }
	registerNetwork = function(def) return Network.registerExternal(def) ~= nil end,
	run = function(command) Shell.run(command) end,
}

return RealNetrunning
