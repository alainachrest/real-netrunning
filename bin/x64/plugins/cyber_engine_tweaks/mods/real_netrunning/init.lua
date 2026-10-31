--[[
Real Netrunning
Grey Hack-style netrunning for Cyberpunk 2077, built from Night City's own lore.

Press the "Open cyberdeck" hotkey (set it in CET's Hotkeys tab) to open the deck in
the game's own UI. That needs Codeware 1.21+ and the r6/scripts/RealNetrunning files.
The deck is also in the CET overlay as a fallback. Type 'help' in the deck.

Requires CyberScript with the shared core (API 2), which holds the organisations,
stock market, news feed and heat this mod shares with the others.

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
local Native = require("modules/native")
local Market = require("modules/market")
local Web = require("modules/web")
local NetWatch = require("modules/netwatch")
local Cyber = require("modules/cyberspace")
local Core = require("modules/core")
local Territory = require("modules/territory")

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
Native.log = log
Network.bus = Bus
Shell.bus = Bus
NetWatch.bus = Bus
NetWatch.print = Shell.print
NetWatch.addTrace = function(amount) Shell.addTrace(amount) end
Bridge.bus = Bus
Cyber.bus = Bus
Cyber.print = Shell.print
Cyber.run = function(command) Shell.run(command) end
Cyber.addTrace = function(amount) Shell.addTrace(amount) end
Cyber.connected = function() return Shell.connected end
NetWatch.inPerson = function(addr) return Cyber.active and Cyber.phase == "in" and Cyber.addr == addr end
Cyber.setCwd = function(path) Shell.setCwd(path) end
Cyber.openDeck = function() if not Native.isOpen() then Native.open() end end
Cyber.closeDeck = function() if Native.isOpen() then Native.close() end end
Shell.cyber = Cyber
Territory.print = Shell.print
Territory.bus = Bus
-- factions don't start a takeover of the network V is in the middle of hacking
Territory.busy = function(addr) return Shell.connected == addr or (Cyber.active and Cyber.addr == addr) end

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

-- The world runs on CyberScript's shared core, which loads its own part of the
-- save at the same moment; so Real Netrunning waits a moment for it.
RealNetrunning.coreWait = nil

local function startWorld()
	migrate(Persisted)
	Network.state = Persisted
	Network.build()
	Shell.reset()
	NetWatch.reset()
	Territory.reset()
	Cyber.onSessionStart()
	Bridge.onWorldRebuilt()
	Native.onWorldRebuilt()
	RealNetrunning.ready = false
	RealNetrunning.coreWait = 2.0
end

-- Called once the wait is over: finds the core and goes online (or explains why not).
local function attachCore()
	RealNetrunning.coreWait = nil
	if Core.get() == nil then
		RealNetrunning.ready = false
		log(Core.missing)
		Shell.print(Core.missing, "err")
		World.warn("Real Netrunning needs CyberScript")
		return
	end
	Network.attachCore()
	Market.attach(Bus)
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
	do local CyberKit = require("modules/cyberkit") World.watchParticleBlocks(CyberKit.particleKind, CyberKit.roomParticles) end

	GameSession.StoreInDir("sessions")
	GameSession.Persist(Persisted, true)
	GameSession.OnStart(startWorld)
	GameSession.OnEnd(function()
		RealNetrunning.ready = false
		Cyber.active = false
		Native.close()
		Shell.reset()
	end)

	Bus.on("*", newsFromEvents)
	Bus.on("network.breached", Native.onBreached)
	Bus.on("network.breached", Territory.onBreached)
	Bus.on("network.floor", Native.onBreached)
	Bus.on("hack.disconnected", Cyber.onDisconnected)
	Market.attach(Bus)

	-- Mod reloaded while already in game
	if GameSession.IsLoaded() then startWorld() end

	Bridge.connect()
	log("v" .. RealNetrunning.version .. " loaded")
end)

registerForEvent("onUpdate", function(dt)
	if RealNetrunning.coreWait then
		RealNetrunning.coreWait = RealNetrunning.coreWait - dt
		if RealNetrunning.coreWait <= 0 then attachCore() end
	end
	Bridge.update(dt)
	if RealNetrunning.ready then
		Native.update(dt)
		-- nothing moves on while the game is paused (CET keeps updating in menus)
		if not World.isPaused() then
			Shell.update(dt)
			NetWatch.update(dt, Shell.connected)
			Market.update(dt)
			Territory.update(dt)
			Cyber.update(dt)
		end
	end
end)

registerForEvent("onOverlayOpen", function() RealNetrunning.overlayOpen = true end)
registerForEvent("onOverlayClose", function() RealNetrunning.overlayOpen = false end)

registerForEvent("onDraw", function()
	if RealNetrunning.overlayOpen and RealNetrunning.ready then
		Terminal.draw()
	end
end)

registerHotkey("rn_open_deck", "Open cyberdeck", function()
	if not RealNetrunning.ready then return end
	if Native.isOpen() then
		Native.close()
	elseif not Native.open() then
		-- no native deck available: fall back to the CET overlay window
		Terminal.visible = true
		World.notify("Open the CET overlay to use the cyberdeck")
	end
end)

registerHotkey("rn_cyber_use", "Cyberspace: use", function()
	if RealNetrunning.ready then Cyber.use() end
end)

registerHotkey("rn_cyber_scan", "Cyberspace: scan nearby rooms", function()
	if RealNetrunning.ready and Cyber.active then Shell.run("cyber scan") Cyber.openDeck() end
end)

registerHotkey("rn_cyber_out", "Cyberspace: jack out", function()
	if RealNetrunning.ready and Cyber.active then Cyber.jackOut("user") end
end)

registerHotkey("rn_toggle_overlay_deck", "Show or hide the overlay cyberdeck", function()
	Terminal.visible = not Terminal.visible
end)

---------------------------------------------------------------------------
-- API for other mods
---------------------------------------------------------------------------

RealNetrunning.api = {
	apiVersion = 1,
	-- Events: "hack.breach", "hack.download", "hack.connected", "hack.disconnected",
	-- "netwatch.traced", "netwatch.heat", "network.revealed", "network.breached",
	-- "device.action", "world.faction_score", "cyberscript.variable",
	-- "cyber.jackin", "cyber.jackout", "cyber.floor", "cyber.ice", "cyber.use", or "*" for all.
	on = Bus.on,
	off = Bus.off,
	emit = Bus.emit,
	getHeat = function() return Network.heat() end,
	addHeat = function(amount, why) if Network.state then Network.addHeat(amount, why) end end,
	isOwned = function(addr) return Network.state ~= nil and Network.isOwned(addr) end,
	reveal = function(addr) return Network.state ~= nil and Network.reveal(addr, "api") end,
	-- def = { addr, name, org, tier, ice, reveals, known, files = { ["path"] = { text, paydata } } }
	registerNetwork = function(def) return Network.registerExternal(def) ~= nil end,
	-- Add a store to the desktop Browser: { id, name, items = { { id = "Items.X", price = 100 } } }
	registerStore = function(def) return require("modules/stores").register(def) end,
	unregisterStore = function(id) require("modules/stores").unregister(id) end,
	run = function(command) Shell.run(command) end,
	isJackedIn = function() return Cyber.active end,
	openDeck = function() return Native.open() end,
}

return RealNetrunning
