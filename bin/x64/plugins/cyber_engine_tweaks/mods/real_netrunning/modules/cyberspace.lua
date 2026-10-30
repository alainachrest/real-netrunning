-- Cyberspace: jack in and walk through a network.
--
-- The network you're connected to is built as a stack of platforms high above
-- Night City, one per floor of its architecture, out of the game's own
-- cyberspace assets (see modules/cyberkit.lua). V's body stays where they
-- jacked in; V is moved up into cyberspace and back again on jack-out.
--
-- It is the same network the terminal sees, so the two are interchangeable:
--   * floors you open in the deck open here, and the other way round
--   * ICE stands guard as the owner's own netrunners; take them down and the
--     floor behind them opens (or 'breach' it from the deck as usual)
--   * data objects are the floor's files: use one to download or read it
--   * NetWatch agents who trace into the network turn up in person
--
-- No guns in cyberspace: quickhacks only. Saving is blocked while jacked in.
-- Jack out any time; a dangerous jack-out (trace, low health, something
-- finding V's body) hurts.

local Network = require("modules/network")
local Lore = require("modules/lore")
local World = require("modules/world")
local Kit = require("modules/cyberkit")
local NetWatch = require("modules/netwatch")

local Cyber = {
	active = false,
	phase = nil,        -- "entering" while the platforms spawn, "moving" until V arrives, then "in"
	target = nil,       -- where V was last sent: { x, y, z, yaw }
	arrived = false,    -- V has been seen at the target
	moveTimer = 0,
	toldToStepAway = false,
	enterTimer = 0,
	addr = nil,
	floor = 1,
	floors = {},        -- index -> { z, tiles = {}, props = {}, ice = {}, gate = id, objects = {} }
	objects = {},       -- every usable object: { floor, kind, x, y, z, label, path, node }
	props = {},         -- network-wide props
	body = nil,         -- { x, y, z, yaw } where V jacked in
	bodySafe = false,
	danger = nil,       -- seconds before something reaches V's body
	dangerTimer = 0,
	tickTimer = 0,
	falls = {},
	agentNPC = nil,
	prompt = nil,
	pendingRecover = nil,
	-- set by init
	bus = nil,
	print = function() end,
	run = function() end,      -- Shell.run
	addTrace = function() end, -- Shell.addTrace
	connected = function() return nil end,
	setCwd = function() end,
	openDeck = function() end,
	closeDeck = function() end,
	random = nil,
}

local function roll() return Cyber.random and Cyber.random() or math.random() end
local function emit(event, data) if Cyber.bus then Cyber.bus.emit(event, data) end end
local function say(text, kind) Cyber.print(text, kind or "out") end

local function state()
	local s = Network.state
	if s.cyber == nil then s.cyber = { active = false } end
	return s.cyber
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function centre(i)
	return Kit.origin.x, Kit.origin.y, Kit.origin.z - (i - 1) * Kit.floorGap
end

function Cyber.arrivalPoint(i)
	local x, y, z = centre(i)
	return x + Kit.arrival.x, y + Kit.arrival.y, z
end

local function descentPoint(i)
	local x, y, z = centre(i)
	return x + Kit.descent.x, y + Kit.descent.y, z
end

-- Files on one floor, flattened: { path, node }
local function floorFiles(net, i, f)
	local list = {}
	local folder = Network.floorFolder(i, f)
	local root = Network.fs(net).children[folder]
	local function walk(node, path)
		local names = {}
		for name in pairs(node.children) do table.insert(names, name) end
		table.sort(names)
		for _, name in ipairs(names) do
			local child = node.children[name]
			if child.dir then walk(child, path .. "/" .. name)
			elseif #list < 10 then table.insert(list, { path = path .. "/" .. name, node = child }) end
		end
	end
	if root then walk(root, "/" .. folder) end
	return list
end

-- Positions on the left and right of a floor, clear of the way up and down.
local function ringPositions(n)
	local points = {}
	for k = 1, n do
		local side = (k % 2 == 1) and 0 or math.pi
		local slot = math.floor((k - 1) / 2)
		local per = math.ceil(n / 2)
		local spread = math.rad(110)
		local angle = side - spread / 2 + (per > 1 and spread * slot / (per - 1) or spread / 2)
		table.insert(points, { math.cos(angle) * Kit.ringRadius, math.sin(angle) * Kit.ringRadius })
	end
	return points
end

local function addObject(i, kind, x, y, z, label, extra)
	local o = { floor = i, kind = kind, x = x, y = y, z = z, label = label }
	if extra then for k, v in pairs(extra) do o[k] = v end end
	table.insert(Cyber.objects, o)
	table.insert(Cyber.floors[i].objects, o)
	return o
end

local function prop(list, path, x, y, z, yaw)
	local id = World.spawnProp(path, x, y, z, yaw or 0)
	if id ~= nil then table.insert(list, id) end
	return id
end

local function fileLabel(net, file)
	local name = file.path:match("([^/]+)$")
	if file.node.paydata then
		if Network.state.looted[net.addr .. ":" .. file.path] then return name .. " (already taken)" end
		return name .. " - paydata, ~" .. file.node.paydata .. " eddies"
	end
	return name
end

local function buildFloor(net, i, f, count)
	local cx, cy, cz = centre(i)
	local floor = { z = cz, tiles = {}, props = {}, ice = {}, iceHostile = {}, corpses = {}, objects = {}, kind = f.kind }
	Cyber.floors[i] = floor

	local half = math.floor(Kit.tilesPerSide / 2)
	for a = -half, half do
		for b = -half, half do
			local id = World.spawnTile(cx + a * Kit.tileSize, cy + b * Kit.tileSize, cz - 0.5)
			if id ~= nil then table.insert(floor.tiles, id) end
		end
	end
	prop(floor.props, f.kind == "core" and Kit.templates.floorCore or Kit.templates.floor, cx, cy, cz, 0)

	if i > 1 then
		local x, y = Cyber.arrivalPoint(i)
		addObject(i, "up", x, y - 3.0, cz, "Back up to floor " .. (i - 1))
	end
	if i < count then
		local x, y = descentPoint(i)
		prop(floor.props, Kit.templates.descent, x, y, cz, 0)
		addObject(i, "down", x, y, cz, "Down to floor " .. (i + 1))
	end
	if i == 1 then
		addObject(i, "exit", cx - 7, cy - 7, cz, "Jack out")
	end

	local files = floorFiles(net, i, f)
	local slots = ringPositions(#files + ((f.kind == "control" or f.kind == "core") and 1 or 0))
	for k, file in ipairs(files) do
		local x, y = cx + slots[k][1], cy + slots[k][2]
		prop(floor.props, Kit.templates.data, x, y, cz, 0)
		addObject(i, "file", x, y, cz, fileLabel(net, file), { path = file.path, node = file.node })
	end
	if f.kind == "control" then
		local s = slots[#files + 1]
		prop(floor.props, Kit.templates.console, cx + s[1], cy + s[2], cz, 0)
		addObject(i, "console", cx + s[1], cy + s[2], cz, "Device control")
	elseif f.kind == "core" then
		local s = slots[#files + 1]
		prop(floor.props, Kit.templates.core, cx, cy, cz, 0)
		addObject(i, "core", cx + s[1], cy + s[2], cz, "Network core")
	end
end

-- The way down from floor i is barred while floor i + 1 is locked.
local function lockAfter(i)
	local net = Network.get(Cyber.addr)
	local floors = Network.floors(net)
	if i >= #floors or Network.isFloorOpen(Cyber.addr, i + 1) then return nil end
	return floors[i + 1]
end

local function isIceLock(f)
	return f and (f.kind == "ice" or f.kind == "black" or (f.kind == "core" and f.ice > 0))
end

local function refreshGates()
	for i, floor in pairs(Cyber.floors) do
		local lock = lockAfter(i)
		if lock and floor.gate == nil then
			local x, y, z = descentPoint(i)
			local template = lock.kind == "black" and Kit.templates.blackIceGate
				or (lock.kind == "password" and Kit.templates.passwordGate or Kit.templates.iceGate)
			floor.gate = World.spawnProp(template, x, y - 1.0, z, 0)
		elseif not lock and floor.gate ~= nil then
			World.despawnProp(floor.gate)
			floor.gate = nil
			if #floor.ice > 0 then
				for _, id in ipairs(floor.ice) do World.deleteNPC(id) end
				floor.ice, floor.iceHostile = {}, {}
				say("The ICE guarding floor " .. (i + 1) .. " crashes.", "ok")
			end
		end
	end
end

local function build()
	local net = Network.get(Cyber.addr)
	local org = Lore.getOrg(net.org)
	local floors = Network.floors(net)
	Cyber.floors, Cyber.objects, Cyber.props = {}, {}, {}
	local x, y, z = centre(1)
	prop(Cyber.props, Kit.ambience(org, net.tier), x, y, z + 6, 0)
	prop(Cyber.props, Kit.templates.particles, x, y, z - Kit.floorGap * (#floors - 1) / 2, 0)
	prop(Cyber.props, Kit.templates.blocks, x + 30, y + 30, z - Kit.floorGap, 45)
	for _, f in ipairs(floors) do
		if f.kind == "black" then
			prop(Cyber.props, Kit.templates.blackwall, x, y + 60, z - Kit.floorGap * #floors / 2, 180)
			break
		end
	end
	for i, f in ipairs(floors) do buildFloor(net, i, f, #floors) end
	refreshGates()
end

local function clear()
	for _, floor in pairs(Cyber.floors) do
		for _, id in ipairs(floor.tiles) do World.despawnProp(id) end
		for _, id in ipairs(floor.props) do World.despawnProp(id) end
		for _, id in ipairs(floor.ice) do World.deleteNPC(id) end
		for _, id in ipairs(floor.corpses) do World.deleteNPC(id) end
		if floor.gate then World.despawnProp(floor.gate) end
	end
	for _, id in ipairs(Cyber.props) do World.despawnProp(id) end
	if Cyber.agentNPC then World.deleteNPC(Cyber.agentNPC) end
	Cyber.floors, Cyber.objects, Cyber.props, Cyber.agentNPC = {}, {}, {}, nil
end

---------------------------------------------------------------------------
-- Jacking in and out
---------------------------------------------------------------------------

local function moveToFloor(i, fromBelow)
	local x, y, z
	if fromBelow then
		x, y, z = descentPoint(i)
		y = y - 4.0
	else
		x, y, z = Cyber.arrivalPoint(i)
	end
	Cyber.target = { x = x, y = y, z = z + 0.2, yaw = fromBelow and 180 or 0 }
	Cyber.arrived, Cyber.moveTimer = false, 0
	World.teleport(Cyber.target.x, Cyber.target.y, Cyber.target.z, Cyber.target.yaw)
	Cyber.floor = i
	Cyber.prompt = nil
	local net = Network.get(Cyber.addr)
	Cyber.setCwd("/" .. Network.floorFolder(i, Network.floors(net)[i]))
	emit("cyber.floor", { addr = Cyber.addr, floor = i })
end

-- Returns ok, message.
function Cyber.jackIn()
	if Cyber.active then return false, "You're already in cyberspace. 'jackout' to leave." end
	local addr = Cyber.connected()
	if addr == nil then return false, "Connect to a network first, then jack in." end
	local net = Network.get(addr)
	if net == nil then return false, "That network is gone." end
	if World.inCombat() then return false, "Not in the middle of a fight. Your body would be dead before you got there." end
	if World.inVehicle() then return false, "Get out of the vehicle first." end
	local body = World.playerTransform()
	if body == nil then return false, "Can't find your body. Load a save first." end

	Cyber.active, Cyber.phase, Cyber.enterTimer = true, "entering", 1.5
	Cyber.target, Cyber.arrived, Cyber.moveTimer, Cyber.toldToStepAway = nil, false, 0, false
	Cyber.addr, Cyber.body, Cyber.floor = addr, body, 1
	Cyber.bodySafe = addr:sub(1, 5) == "home."
	Cyber.danger, Cyber.dangerTimer, Cyber.falls, Cyber.prompt = nil, 0, {}, nil
	local s = state()
	s.active, s.body, s.addr = true, { x = body.x, y = body.y, z = body.z, yaw = body.yaw }, addr

	for _, effect in ipairs(Kit.restrictions) do World.applyStatusEffect(effect) end
	World.setJackedIn(true)
	build()
	emit("cyber.jackin", { addr = addr })
	return true, "Jacking in to " .. net.name .. "..."
end

-- reason: "user", "trace", "health", "body", "disconnected", "broken"
function Cyber.jackOut(reason, quiet)
	if not Cyber.active then return false, "You're not in cyberspace." end
	clear()
	local body = Cyber.body
	if body then World.teleport(body.x, body.y, body.z + 0.1, body.yaw) end
	for _, effect in ipairs(Kit.restrictions) do World.removeStatusEffect(effect) end
	World.setJackedIn(false)
	local forced = reason ~= nil and reason ~= "user" and reason ~= "cancelled"
	if forced and reason ~= "broken" and reason ~= "cancelled" then
		World.applyStatusEffect("BaseStatusEffect.PlayerElectrocuted")
	end
	local addr = Cyber.addr
	Cyber.active, Cyber.phase, Cyber.addr, Cyber.body, Cyber.danger = false, nil, nil, nil, nil
	local s = state()
	s.active, s.body, s.addr = false, nil, nil
	emit("cyber.jackout", { addr = addr, reason = reason or "user", forced = forced })
	local messages = {
		trace = "Traced. You're thrown out of cyberspace. Dumpshock.",
		health = "Flatline protocol: your deck pulls you out before your heart stops.",
		body = "Someone yanked your cable. You come to on the floor.",
		disconnected = "The connection drops and cyberspace with it.",
		broken = "Cyberspace couldn't hold together here. Jacked out.",
		cancelled = "Jack-in cancelled.",
	}
	local text = messages[reason] or "Jacked out."
	if not quiet then
		say(text, forced and "err" or "ok")
		if forced then World.warn(text) end
	end
	return true, text
end

-- The shell lost its connection (traced, switched or disconnected).
function Cyber.onDisconnected(e)
	if not Cyber.active then return end
	Cyber.jackOut(e and e.reason == "traced" and "trace" or "disconnected")
end

-- A save loaded while V was in cyberspace: put V back in their body.
function Cyber.onSessionStart()
	Cyber.active, Cyber.floors, Cyber.objects, Cyber.props, Cyber.agentNPC = false, {}, {}, {}, nil
	local s = Network.state and Network.state.cyber
	if s and s.active and s.body then Cyber.pendingRecover = 2.0 end
end

local function recover()
	local s = state()
	if s.body then World.teleport(s.body.x, s.body.y, s.body.z + 0.1, s.body.yaw) end
	for _, effect in ipairs(Kit.restrictions) do World.removeStatusEffect(effect) end
	World.setJackedIn(false)
	s.active, s.body, s.addr = false, nil, nil
	say("You wake up where you jacked in.", "warn")
end

---------------------------------------------------------------------------
-- Using things
---------------------------------------------------------------------------

local function nearest(pos)
	local best, bestDistance
	for _, o in ipairs(Cyber.objects) do
		if math.abs(pos.z - o.z) < 3 then
			local d = math.sqrt((pos.x - o.x) ^ 2 + (pos.y - o.y) ^ 2)
			if d <= Kit.useRadius and (bestDistance == nil or d < bestDistance) then best, bestDistance = o, d end
		end
	end
	return best
end

local function promptFor(o)
	if o.kind == "down" then
		local lock = lockAfter(o.floor)
		if lock == nil then return o.label end
		if isIceLock(lock) then
			return (lock.kind == "black" and "BLACK ICE" or "ICE") .. " bars the way down. Defeat it, or use to breach"
		end
		return "Password gate. Use to open your deck"
	end
	if o.kind == "file" then return o.label end
	return o.label
end

-- The 'use' key: whatever V is standing next to.
function Cyber.use()
	if not Cyber.active or Cyber.phase ~= "in" then return false end
	local pos = World.playerTransform()
	if pos == nil then return false end
	local o = nearest(pos)
	if o == nil then
		World.notify("Nothing here. Walk up to a data object, a gate or the way down.")
		return false
	end
	local net = Network.get(Cyber.addr)
	if o.kind == "down" then
		local lock = lockAfter(o.floor)
		if lock == nil then
			moveToFloor(o.floor + 1, false)
		elseif lock.kind == "password" then
			say("Password gate on floor " .. (o.floor + 1) .. ". Type 'password <code>' or 'crack'.", "warn")
			Cyber.openDeck()
		else
			Cyber.run("breach")
		end
	elseif o.kind == "up" then
		moveToFloor(o.floor - 1, true)
	elseif o.kind == "exit" then
		Cyber.jackOut("user")
	elseif o.kind == "file" then
		local key = net.addr .. ":" .. o.path
		if o.node.paydata and not Network.state.looted[key] then
			Cyber.run("download " .. o.path)
			o.label = fileLabel(net, o)
			World.notify("Downloaded " .. o.path:match("([^/]+)$"))
		else
			Cyber.run("cat " .. o.path)
			Cyber.openDeck()
		end
	elseif o.kind == "console" then
		Cyber.run("devices")
		Cyber.openDeck()
	elseif o.kind == "core" then
		Cyber.run("status")
		World.notify(Network.isOwned(net.addr) and "Root access. This network is yours." or "The core is still locked.")
	end
	emit("cyber.use", { addr = net.addr, kind = o.kind, path = o.path })
	return true
end

---------------------------------------------------------------------------
-- ICE and NetWatch in person
---------------------------------------------------------------------------

local function spawnIce(i)
	local floor = Cyber.floors[i]
	local lock = lockAfter(i)
	if floor == nil or not isIceLock(lock) or #floor.ice > 0 or floor.iceCleared then return end
	local net = Network.get(Cyber.addr)
	local org = Lore.getOrg(net.org)
	local record = Kit.iceRecord(net.org, org, lock.kind == "black")
	local count = 1 + math.floor(lock.ice / 3)
	local x, y, z = descentPoint(i)
	for k = 1, count do
		local offset = (k - (count + 1) / 2) * 2.5
		local id = World.spawnNPC(record, x + offset, y - 3.0, z + 0.2, 180)
		if id ~= nil then table.insert(floor.ice, id) end
	end
	say((lock.kind == "black" and "BLACK ICE" or "ICE") .. " materialises in front of the way down. " ..
		count .. (count == 1 and " program." or " programs."), lock.kind == "black" and "err" or "warn")
	emit("cyber.ice", { addr = Cyber.addr, floor = i + 1, count = count, black = lock.kind == "black" })
end

local function updateIce(dt)
	local floor = Cyber.floors[Cyber.floor]
	if floor == nil then return end
	spawnIce(Cyber.floor)
	if #floor.ice == 0 then return end
	local alive = 0
	for k, id in ipairs(floor.ice) do
		local dead = World.npcDead(id)
		if dead == false then
			alive = alive + 1
			if not floor.iceHostile[k] then floor.iceHostile[k] = World.makeHostile(id) end
		elseif dead == nil then
			alive = alive + 1 -- still spawning
		end
	end
	if alive > 0 then
		-- fighting ICE is loud
		local lock = lockAfter(Cyber.floor)
		Cyber.addTrace(dt * (lock and lock.kind == "black" and 1.0 or 0.5))
		return
	end
	-- every program on this floor is down: the floor below opens
	local index = Network.nextLock(Cyber.addr)
	for _, id in ipairs(floor.ice) do table.insert(floor.corpses, id) end
	floor.ice, floor.iceHostile, floor.iceCleared = {}, {}, true
	if index == Cyber.floor + 1 then
		local revealed = Network.unlockNext(Cyber.addr)
		local net = Network.get(Cyber.addr)
		say("ICE defeated. Floor " .. index .. " is open.", "ok")
		World.notify("ICE defeated")
		emit("hack.breach", { addr = net.addr, org = net.org, ice = net.ice, tier = net.tier, floor = index, success = true, cyberspace = true })
		if Network.isOwned(net.addr) then say("Core broken. Root access on " .. net.name .. ".", "ok") end
		for _, r in ipairs(revealed) do say("New route found: " .. r, "ok") end
	end
	refreshGates()
end

local function updateAgent()
	local agent = NetWatch.agent
	if agent and agent.addr == Cyber.addr and agent.eta <= 0 then
		if Cyber.agentNPC == nil then
			local pos = World.playerTransform()
			if pos then
				Cyber.agentNPC = World.spawnNPC(Kit.netwatch, pos.x + 4, pos.y + 4, pos.z + 0.2, 225)
				Cyber.agentHostile = false
				say(agent.name .. " steps out of the data stream. Take it down.", "err")
			end
		else
			local dead = World.npcDead(Cyber.agentNPC)
			if dead == false and not Cyber.agentHostile then Cyber.agentHostile = World.makeHostile(Cyber.agentNPC) end
			if dead == true then
				Cyber.agentNPC = nil
				local _, message = NetWatch.win()
				say(message, "ok")
			end
		end
	elseif Cyber.agentNPC ~= nil then
		World.deleteNPC(Cyber.agentNPC)
		Cyber.agentNPC = nil
	end
end

---------------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------------

local function updateBody(dt)
	if Cyber.bodySafe then return end
	if Cyber.danger then
		Cyber.danger = Cyber.danger - dt
		if Cyber.danger <= 0 then Cyber.jackOut("body") end
		return
	end
	Cyber.dangerTimer = Cyber.dangerTimer + dt
	if Cyber.dangerTimer < 20 then return end
	Cyber.dangerTimer = 0
	local chance = ({ 0.02, 0.04, 0.07, 0.1 })[NetWatch.tier() + 1]
	if roll() < chance then
		Cyber.danger = 12
		say("Something is moving near your body. Jack out!", "err")
		World.warn("Movement near your body")
	end
end

function Cyber.update(dt)
	if Cyber.pendingRecover then
		Cyber.pendingRecover = Cyber.pendingRecover - dt
		if Cyber.pendingRecover <= 0 then
			Cyber.pendingRecover = nil
			recover()
		end
		return
	end
	if not Cyber.active then return end

	if Cyber.phase == "entering" then
		Cyber.enterTimer = Cyber.enterTimer - dt
		if Cyber.enterTimer <= 0 then
			Cyber.phase = "moving"
			moveToFloor(1, false)
		end
		return
	end

	-- the deck dropped the connection some other way
	if Cyber.connected() ~= Cyber.addr then
		Cyber.jackOut("disconnected")
		return
	end

	local pos = World.playerTransform()
	if pos == nil then return end

	-- Has V actually got where they were sent? The game won't move V while
	-- they're using a computer screen or similar, so keep trying until it does.
	if not Cyber.arrived then
		local t = Cyber.target
		if t and math.abs(pos.x - t.x) < 4 and math.abs(pos.y - t.y) < 4 and math.abs(pos.z - t.z) < 4 then
			Cyber.arrived = true
			if Cyber.phase == "moving" then
				Cyber.phase = "in"
				Cyber.closeDeck()
				local net = Network.get(Cyber.addr)
				say("You're in " .. net.name .. ". " .. #Network.floors(net) .. " floors below you.", "ok")
				World.notify("Cyberspace: " .. net.name)
			end
		else
			Cyber.moveTimer = Cyber.moveTimer + dt
			if Cyber.moveTimer >= 1.5 then
				Cyber.moveTimer = 0
				Cyber.waited = (Cyber.waited or 0) + 1.5
				if Cyber.phase == "moving" and not Cyber.toldToStepAway then
					Cyber.toldToStepAway = true
					say("Your deck is ready. Step away from the screen to finish jacking in.", "warn")
					World.notify("Step away from the screen to jack in")
				end
				if Cyber.waited >= 60 then
					Cyber.waited = 0
					Cyber.jackOut("cancelled")
					return
				end
				if t then World.teleport(t.x, t.y, t.z, t.yaw) end
			end
			return
		end
		Cyber.waited = 0
	end

	do
		-- fell off: put V back, and give up if the floors aren't holding
		local floor = Cyber.floors[Cyber.floor]
		if floor and pos.z < floor.z - Kit.fallLimit then
			table.insert(Cyber.falls, os.clock())
			local recent = 0
			for _, t in ipairs(Cyber.falls) do if os.clock() - t < 10 then recent = recent + 1 end end
			if recent >= 3 then
				Cyber.jackOut("broken")
				return
			end
			moveToFloor(Cyber.floor, false)
		end
		-- prompt for whatever V is next to
		local o = nearest(pos)
		if o ~= Cyber.prompt then
			Cyber.prompt = o
			if o then World.notify("[Use] " .. promptFor(o)) end
		end
	end

	if World.healthPercent() < 15 then
		local lock = lockAfter(Cyber.floor)
		if not (lock and lock.kind == "black") then
			Cyber.jackOut("health")
			return
		end
	end

	Cyber.tickTimer = Cyber.tickTimer + dt
	if Cyber.tickTimer >= 0.5 then
		local step = Cyber.tickTimer
		Cyber.tickTimer = 0
		refreshGates()
		updateIce(step)
		if not Cyber.active then return end
		updateAgent()
		updateBody(step)
	end
end

function Cyber.status()
	if not Cyber.active then return "Not in cyberspace." end
	local net = Network.get(Cyber.addr)
	local lines = { "In cyberspace: " .. net.name .. ", floor " .. Cyber.floor .. " of " .. #Network.floors(net) }
	if Cyber.bodySafe then table.insert(lines, "Your body is safe at home.") end
	if Cyber.danger then table.insert(lines, "Something is near your body: " .. math.ceil(Cyber.danger) .. "s") end
	return table.concat(lines, "\n")
end

return Cyber
