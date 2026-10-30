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
local Rng = require("modules/rng")

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
-- Layout: every floor is a small complex of rooms joined by doorways
---------------------------------------------------------------------------

local function centre(i)
	return Kit.origin.x, Kit.origin.y, Kit.origin.z - (i - 1) * Kit.floorGap
end

-- The rooms of floor i: a grid of cells, a spanning tree of doorways (so every
-- room can be reached) and the odd extra doorway for loops. The way down is
-- in the room furthest from where V arrives, behind a single doorway that
-- seals while the floor below is locked. The same for every visit to a network.
function Cyber.layout(net, i, f)
	local rng = Rng.new(Network.state.seed or 0, "rooms", net.addr, i)
	local big = net.ice >= 4 or net.tier >= 2
	local w = (f.kind == "lobby" or f.kind == "core") and 2 or (big and 3 or 2)
	local h = (f.kind == "files" or f.kind == "control" or big) and 3 or 2
	local doors = {}
	local function key(ax, ay, bx, by)
		if ax > bx or (ax == bx and ay > by) then ax, ay, bx, by = bx, by, ax, ay end
		return ax .. "," .. ay .. "|" .. bx .. "," .. by
	end
	local visited, depth, parent, degree = {}, {}, {}, {}
	local function id(x, y) return x .. "," .. y end
	local function neighbours(x, y)
		local list = {}
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nx, ny = x + d[1], y + d[2]
			if nx >= 0 and nx < w and ny >= 0 and ny < h then table.insert(list, { nx, ny }) end
		end
		return list
	end
	-- randomised depth-first search from the arrival room
	local stack = { { 0, 0 } }
	visited[id(0, 0)], depth[id(0, 0)] = true, 0
	while #stack > 0 do
		local top = stack[#stack]
		local options = {}
		for _, n in ipairs(neighbours(top[1], top[2])) do
			if not visited[id(n[1], n[2])] then table.insert(options, n) end
		end
		if #options == 0 then
			table.remove(stack)
		else
			local n = options[rng:int(1, #options)]
			visited[id(n[1], n[2])] = true
			depth[id(n[1], n[2])] = depth[id(top[1], top[2])] + 1
			parent[id(n[1], n[2])] = { top[1], top[2] }
			doors[key(top[1], top[2], n[1], n[2])] = true
			degree[id(top[1], top[2])] = (degree[id(top[1], top[2])] or 0) + 1
			degree[id(n[1], n[2])] = (degree[id(n[1], n[2])] or 0) + 1
			table.insert(stack, n)
		end
	end
	-- the way down: the deepest room with a single doorway
	local goal, best = { w - 1, h - 1 }, -1
	for x = 0, w - 1 do
		for y = 0, h - 1 do
			local d = depth[id(x, y)] or 0
			if (x ~= 0 or y ~= 0) and (degree[id(x, y)] or 0) == 1 and d > best then goal, best = { x, y }, d end
		end
	end
	-- one extra doorway for a loop, never into the goal room
	if w * h >= 6 then
		for _ = 1, 8 do
			local x, y = rng:int(0, w - 1), rng:int(0, h - 1)
			local n = neighbours(x, y)[rng:int(1, #neighbours(x, y))]
			local k = key(x, y, n[1], n[2])
			local touchesGoal = (x == goal[1] and y == goal[2]) or (n[1] == goal[1] and n[2] == goal[2])
			if not doors[k] and not touchesGoal then doors[k] = true break end
		end
	end
	return { w = w, h = h, doors = doors, key = key, start = { 0, 0 }, goal = goal, parent = parent[id(goal[1], goal[2])] }
end

local function cellCentre(i, layout, x, y)
	local cx, cy, cz = centre(i)
	local r = Kit.roomSize
	return cx + (x - (layout.w - 1) / 2) * r, cy + (y - (layout.h - 1) / 2) * r, cz
end

function Cyber.arrivalPoint(i)
	local floor = Cyber.floors[i]
	if floor and floor.arrival then return floor.arrival.x, floor.arrival.y, floor.arrival.z end
	return centre(i)
end

local function descentPoint(i)
	local floor = Cyber.floors[i]
	if floor and floor.descent then return floor.descent.x, floor.descent.y, floor.descent.z end
	return centre(i)
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
			elseif #list < 12 then table.insert(list, { path = path .. "/" .. name, node = child }) end
		end
	end
	if root then walk(root, "/" .. folder) end
	return list
end

local function addObject(i, kind, x, y, z, label, extra)
	local o = { floor = i, kind = kind, x = x, y = y, z = z, label = label }
	if extra then for k, v in pairs(extra) do o[k] = v end end
	table.insert(Cyber.objects, o)
	table.insert(Cyber.floors[i].objects, o)
	return o
end

local function prop(list, path, x, y, z, yaw)
	Cyber.propsAsked = (Cyber.propsAsked or 0) + 1
	local id = World.spawnProp(path, x, y, z, yaw or 0)
	if id == nil then
		Cyber.failedProps = Cyber.failedProps or {}
		Cyber.failedProps[path:match("([^\\]+)$") or path] = true
	end
	if id ~= nil then table.insert(list, id) end
	return id
end

-- A floor slab or wall: spec = { x, y, z, yaw, hx, hy, hz, kind }. Kept on the
-- floor so the whole floor can be rebuilt in a new style.
local function block(floor, spec)
	Cyber.tilesAsked = (Cyber.tilesAsked or 0) + 1
	table.insert(floor.specs, spec)
	local id = World.spawnBlock(spec.x, spec.y, spec.z, spec.yaw, spec.hx, spec.hy, spec.hz, spec.kind)
	if id ~= nil then table.insert(floor.tiles, id) end
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

-- A wall along one edge of a cell, with a doorway gap if there's a door.
-- along "x": the wall runs east-west at y = wy; along "y": north-south at x = wx.
local function wall(floor, along, mx, my, z, door)
	local r, d, t = Kit.roomSize, Kit.doorWidth, Kit.wallThickness
	local hz = Kit.wallHeight / 2
	local yaw = along == "x" and 0 or 90
	local function segment(offset, length)
		local x = along == "x" and mx + offset or mx
		local y = along == "y" and my + offset or my
		block(floor, { x = x, y = y, z = z + hz, yaw = yaw, hx = length / 2, hy = t / 2, hz = hz, kind = 1 })
	end
	if not door then
		segment(0, r)
	else
		local length = (r - d) / 2
		segment(-(d / 2 + length / 2), length)
		segment(d / 2 + length / 2, length)
	end
end

local function buildFloor(net, i, f, count)
	local cx, cy, cz = centre(i)
	local floor = { z = cz, tiles = {}, specs = {}, props = {}, ice = {}, iceHostile = {}, corpses = {}, objects = {}, kind = f.kind }
	Cyber.floors[i] = floor
	local L = Cyber.layout(net, i, f)
	floor.layout = L
	local r = Kit.roomSize

	-- slabs and walls
	for x = 0, L.w - 1 do
		for y = 0, L.h - 1 do
			local rx, ry = cellCentre(i, L, x, y)
			block(floor, { x = rx, y = ry, z = cz - 0.5, yaw = 0, hx = r / 2, hy = r / 2, hz = 0.5, kind = 0 })
			-- each room's own glow, just under the ceiling
			block(floor, { x = rx, y = ry, z = cz + Kit.wallHeight - 0.8, yaw = 0, hx = r / 2, hy = r / 2, hz = 0.1, kind = 4 })
			-- a ceiling on top of the walls, so nothing outside cyberspace shows
			block(floor, { x = rx, y = ry, z = cz + Kit.wallHeight + 0.25, yaw = 0, hx = r / 2, hy = r / 2, hz = 0.25, kind = 2 })
			if x == 0 then wall(floor, "y", rx - r / 2, ry, cz, false) end
			if y == 0 then wall(floor, "x", rx, ry - r / 2, cz, false) end
			wall(floor, "y", rx + r / 2, ry, cz, x < L.w - 1 and L.doors[L.key(x, y, x + 1, y)])
			wall(floor, "x", rx, ry + r / 2, cz, y < L.h - 1 and L.doors[L.key(x, y, x, y + 1)])
		end
	end

	-- dark pillars where walls meet (wall meshes leave gaps at the corners) and a
	-- dark shell round the outside of the whole floor, so nothing shows through
	local halfW, halfH = L.w * r / 2, L.h * r / 2
	local hz = Kit.wallHeight / 2
	for a = 0, L.w do
		for b = 0, L.h do
			block(floor, { x = cx - halfW + a * r, y = cy - halfH + b * r, z = cz + hz, yaw = 0,
				hx = 0.45, hy = 0.45, hz = hz, kind = 3 })
		end
	end
	local shell = 0.3   -- half thickness
	local gap = Kit.wallThickness / 2 + shell + 0.05
	local tall = hz + 1.0
	block(floor, { x = cx, y = cy - halfH - gap, z = cz + hz, yaw = 0, hx = halfW + 1.2, hy = shell, hz = tall, kind = 3 })
	block(floor, { x = cx, y = cy + halfH + gap, z = cz + hz, yaw = 0, hx = halfW + 1.2, hy = shell, hz = tall, kind = 3 })
	block(floor, { x = cx - halfW - gap, y = cy, z = cz + hz, yaw = 0, hx = shell, hy = halfH + 1.2, hz = tall, kind = 3 })
	block(floor, { x = cx + halfW + gap, y = cy, z = cz + hz, yaw = 0, hx = shell, hy = halfH + 1.2, hz = tall, kind = 3 })

	-- arriving, leaving
	local sx, sy = cellCentre(i, L, L.start[1], L.start[2])
	floor.arrival = { x = sx, y = sy - 3, z = cz }
	if i > 1 then addObject(i, "up", sx, sy - 6, cz, "Back up to floor " .. (i - 1)) end
	if i == 1 then addObject(i, "exit", sx - 5, sy + 5, cz, "Jack out") end
	local gx, gy = cellCentre(i, L, L.goal[1], L.goal[2])
	floor.descent = { x = gx, y = gy, z = cz }
	if i < count then addObject(i, "down", gx, gy, cz, "Down to floor " .. (i + 1)) end

	-- the doorway into the goal room, where a locked floor below is sealed
	if L.parent then
		local px, py = cellCentre(i, L, L.parent[1], L.parent[2])
		local doorX, doorY = (gx + px) / 2, (gy + py) / 2
		local along = (L.parent[2] == L.goal[2]) and "y" or "x"
		floor.door = { x = doorX, y = doorY, z = cz, along = along }
		floor.iceSpot = { x = px + (doorX - px) * 0.4, y = py + (doorY - py) * 0.4, z = cz }
		-- facing the door from the parent room
		floor.gateUse = { x = doorX + (px - doorX) * 0.18, y = doorY + (py - doorY) * 0.18 }
	end

	-- data objects in the rooms between
	local rooms = {}
	for x = 0, L.w - 1 do
		for y = 0, L.h - 1 do
			local isStart = x == L.start[1] and y == L.start[2]
			local isGoal = x == L.goal[1] and y == L.goal[2]
			if not isStart and not isGoal then table.insert(rooms, { x, y }) end
		end
	end
	if #rooms == 0 then rooms = { L.start } end
	local slots = { { -4, -4 }, { 4, 4 }, { -4, 4 }, { 4, -4 } }
	local used = {}
	local function place(k)
		local room = rooms[(k - 1) % #rooms + 1]
		local rid = room[1] .. "," .. room[2]
		used[rid] = (used[rid] or 0) + 1
		local slot = slots[(used[rid] - 1) % #slots + 1]
		local rx, ry = cellCentre(i, L, room[1], room[2])
		return rx + slot[1], ry + slot[2]
	end
	local files = floorFiles(net, i, f)
	for k, file in ipairs(files) do
		local x, y = place(k)
		prop(floor.props, Kit.templates.data, x, y, cz, 0)
		addObject(i, "file", x, y, cz, fileLabel(net, file), { path = file.path, node = file.node })
	end
	if f.kind == "control" then
		local x, y = place(#files + 1)
		prop(floor.props, Kit.templates.console, x, y, cz, 0)
		addObject(i, "console", x, y, cz, "Device control")
	elseif f.kind == "core" then
		prop(floor.props, Kit.templates.core, gx, gy, cz, 0)
		addObject(i, "core", gx, gy + 3, cz, "Network core")
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

-- Locked floor below: the doorway into the room with the way down is sealed
-- by a barrier V can't walk through, with ICE (or a password gate) in front.
local function refreshGates()
	for i, floor in pairs(Cyber.floors) do
		local lock = lockAfter(i)
		local door = floor.door
		if lock and floor.gate == nil and door then
			local yaw = door.along == "x" and 0 or 90
			local barrier = World.spawnBlock(door.x, door.y, door.z + Kit.wallHeight / 2, yaw,
				Kit.doorWidth / 2 + 0.2, Kit.wallThickness, Kit.wallHeight / 2, 1)
			floor.gate = { barrier = barrier }
			if floor.gateUse then
				floor.gateObject = addObject(i, "gate", floor.gateUse.x, floor.gateUse.y, floor.z, "Sealed doorway")
			end
		elseif not lock and floor.gate ~= nil then
			World.despawnProp(floor.gate.barrier)
			floor.gate = nil
			if floor.gateObject then floor.gateObject.kind = "spent" floor.gateObject = nil end
			if #floor.ice > 0 then
				for _, id in ipairs(floor.ice) do World.deleteNPC(id) end
				floor.ice, floor.iceHostile = {}, {}
				say("The ICE guarding floor " .. (i + 1) .. " crashes.", "ok")
			end
			say("The doorway on floor " .. i .. " opens.", "ok")
		end
	end
end

local function build()
	local net = Network.get(Cyber.addr)
	local org = Lore.getOrg(net.org)
	local floors = Network.floors(net)
	Cyber.floors, Cyber.objects, Cyber.props = {}, {}, {}
	local x, y, z = centre(1)
	local o = Kit.sceneryOffset
	prop(Cyber.props, Kit.ambience(org, net.tier), x + o.x, y + o.y, z + o.z, 0)
	prop(Cyber.props, Kit.templates.particles, x - o.y, y, z + o.z, 0)
	prop(Cyber.props, Kit.templates.blocks, x + o.y, y - o.y / 2, z + o.z, 45)
	for _, f in ipairs(floors) do
		if f.kind == "black" then
			prop(Cyber.props, Kit.templates.blackwall, x, y + o.y * 1.5, z - Kit.floorGap * #floors / 2, 180)
			break
		end
	end
	for i, f in ipairs(floors) do buildFloor(net, i, f, #floors) end
	refreshGates()
end

local function clear()
	for _, floor in pairs(Cyber.floors) do
		for _, id in ipairs(floor.tiles) do World.despawnProp(id) end
		for _, id in ipairs(floor.oldTiles or {}) do World.despawnProp(id) end
		for _, id in ipairs(floor.props) do World.despawnProp(id) end
		for _, id in ipairs(floor.ice) do World.deleteNPC(id) end
		for _, id in ipairs(floor.corpses) do World.deleteNPC(id) end
		if floor.gate then World.despawnProp(floor.gate.barrier) end
	end
	for _, id in ipairs(Cyber.props) do World.despawnProp(id) end
	if Cyber.agentNPC then World.deleteNPC(Cyber.agentNPC) end
	World.cyberCall("ForgetBlocks")
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
	Cyber.closeDeck()
	Cyber.applyLook()
	Cyber.tilesAsked, Cyber.propsAsked, World.lastError, Cyber.failedProps = 0, 0, nil, {}
	-- the floor and wall meshes load first, so blocks can be fitted to them (see update)
	Cyber.phase, Cyber.prepareTimer = "preparing", 4.0
	emit("cyber.jackin", { addr = addr })
	return true, "Jacking in to " .. net.name .. "..."
end

-- reason: "user", "trace", "health", "body", "disconnected", "broken"
function Cyber.jackOut(reason, quiet)
	if not Cyber.active then return false, "You're not in cyberspace." end
	Cyber.lastReason = reason or "user"
	Cyber.lastDebug = Cyber.debug()
	clear()
	local body = Cyber.body
	if body then World.teleport(body.x, body.y, body.z + 0.1, body.yaw) end
	for _, effect in ipairs(Kit.restrictions) do World.removeStatusEffect(effect) end
	World.setJackedIn(false)
	if (state().sky or 0) > 0 then World.cyberCall("SetSky", 0) end
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
-- How cyberspace looks: chosen in game, kept per save
---------------------------------------------------------------------------

function Cyber.applyLook()
	local s = state()
	World.cyberCall("SetFloorStyle", s.style or Kit.defaultStyle)
	World.cyberCall("SetWallStyle", s.walls or Kit.defaultWalls)
	World.cyberCall("SetLight", s.light or 1.0, s.lightColour or Kit.defaultLightColour)
	World.cyberCall("SetFloorScale", s.scale or Kit.defaultScale)
	if (s.sky or 0) > 0 then World.cyberCall("SetSky", s.sky) end
end

-- The rooms are rebuilt in the current style: the new blocks go in before
-- the old ones go, so V never stands on nothing.
local function respawnTiles()
	for _, floor in pairs(Cyber.floors) do
		local old = floor.tiles
		floor.tiles = {}
		for _, s in ipairs(floor.specs or {}) do
			local id = World.spawnBlock(s.x, s.y, s.z, s.yaw, s.hx, s.hy, s.hz, s.kind)
			if id ~= nil then table.insert(floor.tiles, id) end
		end
		floor.oldTiles = old
	end
	Cyber.retireTimer = 1.0
end

local function listChoices(count, nameOf, current)
	local lines = {}
	for i = 0, count - 1 do
		table.insert(lines, (i == current and "> " or "  ") .. i .. ". " .. tostring(nameOf(i)))
	end
	return table.concat(lines, "\n")
end

-- 'cyber style [n]': which of the game's meshes the floor is drawn with.
function Cyber.style(n)
	local s = state()
	local count = World.cyberCall("FloorStyleCount") or 0
	if count == 0 then return false, "Cyberspace styles need the r6 scripts." end
	if n == nil then
		return true, "Floor styles ('cyber style <number>'):\n" ..
			listChoices(count, function(i) return World.cyberCall("FloorStyleName", i) end, s.style or Kit.defaultStyle)
	end
	n = math.floor(tonumber(n) or -1)
	if n < 0 or n >= count then return false, "Pick a style from 0 to " .. (count - 1) .. "." end
	s.style = n
	World.cyberCall("SetFloorStyle", n)
	if Cyber.active then Cyber.restyleTimer = 4.0 end
	return true, "Floor style: " .. tostring(World.cyberCall("FloorStyleName", n)) .. (Cyber.active and "" or " (next time you jack in)")
end

-- 'cyber walls [n]': which of the game's meshes the walls are drawn with.
function Cyber.walls(n)
	local s = state()
	local count = World.cyberCall("WallStyleCount") or 0
	if count == 0 then return false, "Cyberspace styles need the r6 scripts." end
	if n == nil then
		return true, "Wall styles ('cyber walls <number>'):\n" ..
			listChoices(count, function(i) return World.cyberCall("WallStyleName", i) end, s.walls or Kit.defaultWalls)
	end
	n = math.floor(tonumber(n) or -1)
	if n < 0 or n >= count then return false, "Pick a wall style from 0 to " .. (count - 1) .. "." end
	s.walls = n
	World.cyberCall("SetWallStyle", n)
	if Cyber.active then Cyber.restyleTimer = 4.0 end
	return true, "Wall style: " .. tostring(World.cyberCall("WallStyleName", n)) .. (Cyber.active and "" or " (next time you jack in)")
end

-- 'cyber light [brightness] [colour]': how the rooms are lit. Brightness 1 is
-- normal, 0 is off; colour is a number from the list.
function Cyber.light(level, colour)
	local s = state()
	local count = World.cyberCall("LightColourCount") or 0
	if count == 0 then return false, "Cyberspace lighting needs the r6 scripts." end
	if level == nil then
		return true, "Brightness " .. (s.light or 1.0) .. ". 'cyber light <brightness> [colour]', brightness 1 is normal.\nColours:\n" ..
			listChoices(count, function(i) return World.cyberCall("LightColourName", i) end, s.lightColour or Kit.defaultLightColour)
	end
	level = tonumber(level)
	if level == nil or level < 0 then return false, "Give a brightness of 0 or more, like 0.5 or 2." end
	s.light = math.min(10, level)
	if colour ~= nil then
		colour = math.floor(tonumber(colour) or -1)
		if colour < 0 or colour >= count then return false, "Pick a colour from 0 to " .. (count - 1) .. "." end
		s.lightColour = colour
	end
	World.cyberCall("SetLight", s.light, s.lightColour or Kit.defaultLightColour)
	if Cyber.active then Cyber.restyleTimer = 0.1 end
	return true, "Lights: brightness " .. s.light .. ", " .. tostring(World.cyberCall("LightColourName", s.lightColour or Kit.defaultLightColour)) ..
		(Cyber.active and "" or " (next time you jack in)")
end

-- 'cyber scale [x]': resize the floor mesh, if a style comes out too big or small.
function Cyber.scale(x)
	local s = state()
	if x == nil then return true, "Floor scale: " .. (s.scale or Kit.defaultScale) .. ". 'cyber scale <number>', 1 is normal." end
	x = tonumber(x)
	if x == nil or x <= 0 then return false, "Give a number above 0, like 0.5 or 2." end
	s.scale = math.max(0.05, math.min(20, x))
	World.cyberCall("SetFloorScale", s.scale)
	if Cyber.active then respawnTiles() end
	return true, "Floor scale: " .. s.scale
end

-- 'cyber sky [n]': weather while jacked in, put back on jack-out.
function Cyber.sky(n)
	local s = state()
	local count = World.cyberCall("SkyCount") or 0
	if count == 0 then return false, "Cyberspace skies need the r6 scripts." end
	if n == nil then
		return true, "Skies ('cyber sky <number>'):\n" ..
			listChoices(count, function(i) return World.cyberCall("SkyName", i) end, s.sky or 0)
	end
	n = math.floor(tonumber(n) or -1)
	if n < 0 or n >= count then return false, "Pick a sky from 0 to " .. (count - 1) .. "." end
	s.sky = n
	if Cyber.active then World.cyberCall("SetSky", n) end
	return true, "Sky: " .. tostring(World.cyberCall("SkyName", n)) .. (Cyber.active and "" or " (next time you jack in)")
end

---------------------------------------------------------------------------
-- Using things
---------------------------------------------------------------------------

local function nearest(pos)
	local best, bestDistance
	for _, o in ipairs(Cyber.objects) do
		if o.kind ~= "spent" and math.abs(pos.z - o.z) < 3 then
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
	if o.kind == "gate" then
		local lock = lockAfter(o.floor)
		if lock == nil then return "Open doorway" end
		if isIceLock(lock) then
			return (lock.kind == "black" and "BLACK ICE" or "ICE") .. " seals this doorway. Defeat it, or use to breach"
		end
		return "Password-locked doorway. Use to open your deck"
	end
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
	elseif o.kind == "gate" then
		local lock = lockAfter(o.floor)
		if lock == nil then
			World.notify("The doorway is open.")
		elseif lock.kind == "password" then
			say("Password-locked doorway to floor " .. (o.floor + 1) .. ". Type 'password <code>' or 'crack'.", "warn")
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
	local spot = floor.iceSpot
	local x, y, z
	if spot then x, y, z = spot.x, spot.y, spot.z else x, y, z = descentPoint(i) end
	for k = 1, count do
		local offset = (k - (count + 1) / 2) * 2.5
		local id = World.spawnNPC(record, x + offset, y + offset * 0.3, z + 0.2, 180)
		if id ~= nil then table.insert(floor.ice, id) end
	end
	say((lock.kind == "black" and "BLACK ICE" or "ICE") .. " materialises in front of the sealed doorway. " ..
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
			-- ICE fights with quickhacks, like V: no guns. Checked a few times in
			-- case the game hands the weapon back while it spawns in.
			floor.iceDisarmed = floor.iceDisarmed or {}
			if (floor.iceDisarmed[k] or 0) < 6 then
				World.disarm(id)
				floor.iceDisarmed[k] = (floor.iceDisarmed[k] or 0) + 1
			end
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
	floor.ice, floor.iceHostile, floor.iceDisarmed, floor.iceCleared = {}, {}, {}, true
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
				Cyber.agentHostile, Cyber.agentDisarmed = false, 0
				say(agent.name .. " steps out of the data stream. Take it down.", "err")
			end
		else
			local dead = World.npcDead(Cyber.agentNPC)
			if dead == false and not Cyber.agentHostile then Cyber.agentHostile = World.makeHostile(Cyber.agentNPC) end
			if dead == false and (Cyber.agentDisarmed or 0) < 6 then
				World.disarm(Cyber.agentNPC)
				Cyber.agentDisarmed = (Cyber.agentDisarmed or 0) + 1
			end
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

	if Cyber.phase == "preparing" then
		Cyber.prepareTimer = Cyber.prepareTimer - dt
		if World.cyberCall("FloorReady") == true or Cyber.prepareTimer <= 0 then
			build()
			Cyber.phase, Cyber.enterTimer = "entering", 1.5
		end
		return
	end

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

	if Cyber.restyleTimer then
		Cyber.restyleTimer = Cyber.restyleTimer - dt
		if World.cyberCall("FloorReady") == true or Cyber.restyleTimer <= 0 then
			Cyber.restyleTimer = nil
			respawnTiles()
		end
	end

	if Cyber.retireTimer then
		Cyber.retireTimer = Cyber.retireTimer - dt
		if Cyber.retireTimer <= 0 then
			Cyber.retireTimer = nil
			for _, floor in pairs(Cyber.floors) do
				for _, id in ipairs(floor.oldTiles or {}) do World.despawnProp(id) end
				floor.oldTiles = nil
			end
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

-- What's going on, for working out problems in game ('cyber debug').
function Cyber.debug()
	local lines = {}
	local pos = World.playerTransform()
	table.insert(lines, "active=" .. tostring(Cyber.active) .. " phase=" .. tostring(Cyber.phase) .. " floor=" .. tostring(Cyber.floor) ..
		" arrived=" .. tostring(Cyber.arrived))
	if pos then table.insert(lines, string.format("V at %.1f, %.1f, %.1f", pos.x, pos.y, pos.z)) end
	local t = Cyber.target
	if t then table.insert(lines, string.format("sent to %.1f, %.1f, %.1f", t.x, t.y, t.z)) end
	local tiles, spawned, withEntity, withCollider, props, propsSpawned = 0, 0, 0, 0, 0, 0
	for _, floor in pairs(Cyber.floors) do
		for _, id in ipairs(floor.tiles) do
			tiles = tiles + 1
			if World.propSpawned(id) then spawned = spawned + 1 end
			local info = World.propInfo(id)
			if info.entity then withEntity = withEntity + 1 end
			if info.collider then withCollider = withCollider + 1 end
		end
		for _, id in ipairs(floor.props) do props = props + 1 if World.propSpawned(id) then propsSpawned = propsSpawned + 1 end end
	end
	table.insert(lines, "blocks (floors and walls): asked " .. (Cyber.tilesAsked or 0) .. ", got IDs " .. tiles .. ", spawned " .. spawned ..
		", entities " .. withEntity .. ", with collider " .. withCollider)
	table.insert(lines, "props: asked " .. (Cyber.propsAsked or 0) .. ", got IDs " .. props .. ", spawned " .. propsSpawned)
	table.insert(lines, "colliders added by redscript: " .. tostring(World.collidersAdded()) ..
		", floor mesh size: " .. tostring(World.cyberCall("FloorMeshSize")))
	local failed = {}
	for name in pairs(Cyber.failedProps or {}) do table.insert(failed, name) end
	if #failed > 0 then table.insert(lines, "props that didn't spawn: " .. table.concat(failed, ", ")) end
	if World.lastError then table.insert(lines, "last game error: " .. tostring(World.lastError)) end
	local falls = 0
	for _ in ipairs(Cyber.falls or {}) do falls = falls + 1 end
	table.insert(lines, "falls " .. falls .. "   last jack-out: " .. tostring(Cyber.lastReason))
	return table.concat(lines, "\n")
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
