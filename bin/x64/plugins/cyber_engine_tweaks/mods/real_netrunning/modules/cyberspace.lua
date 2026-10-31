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
--   * NetWatch agents who trace into the network turn up in person, on the far
--     side of the floor, and hunt V through the rooms
--   * patrolling ICE wanders the corridors; rival netrunners and rogue AIs
--     turn up now and then, even in networks V owns
--   * deep floors of networks V doesn't own raise trace just for being there
--   * 'cyber scan' maps the rooms around V, at a cost in trace
--
-- No guns or blades in cyberspace: quickhacks and bare hands (fists, Gorilla
-- Arms). Saving is blocked while jacked in.
-- Jack out any time; a dangerous jack-out (trace, low health, something
-- finding V's body) hurts.

local Network = require("modules/network")
local Lore = require("modules/lore")
local World = require("modules/world")
local Kit = require("modules/cyberkit")
local NetWatch = require("modules/netwatch")
local Rng = require("modules/rng")
local Territory = require("modules/territory")

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
-- Keeps a spawned enemy fighting like V: fists and Gorilla Arms only. Some of
-- the brawlers carry a sidearm they pull once a fight starts, so any guns and
-- blades are taken from their hands and pockets every half second; their fists
-- are left alone, so they keep fighting. (Spawning them from edited copies of
-- their records instead leaves them standing about, not fighting.)
Cyber.armedRecords = {}   -- fighters found carrying guns: never used again this session

-- The record to spawn for a fighter: the one asked for, unless it's known to
-- carry a gun, in which case the first fallback brawler that isn't.
local function fighterRecord(record)
	if not Kit.combatRules or not Cyber.armedRecords[record] then return record end
	for _, r in ipairs(Kit.fallbackBrawlers) do
		if not Cyber.armedRecords[r] then return r end
	end
	return record
end
Cyber.fighterRecord = fighterRecord

-- Checks a newly spawned fighter once. Returns true when it carries a gun and
-- should be swapped (its record is remembered as armed). Fighters are never
-- disarmed: an NPC whose gun is taken just stands there trying to draw it.
local function carriesGun(id, record, checked)
	if checked[id] then return false end
	local gun = World.npcHasGun(id)
	if gun == nil then return false end -- not ready yet
	checked[id] = true
	if gun then
		Cyber.armedRecords[record] = true
		return fighterRecord(record) ~= record
	end
	return false
end
Cyber.gunChecked = {}

-- The jack-in/out effect: spawned around V for a few seconds.
local function playTransition(x, y, z)
	if Kit.templates.transition == nil then return end
	local id = World.spawnProp(Kit.templates.transition, x, y, z, 0)
	if id then
		Cyber.transitions = Cyber.transitions or {}
		table.insert(Cyber.transitions, { id = id, timer = 5.0 })
	end
end

function Cyber.updateTransitions(dt)
	if Cyber.transitions == nil then return end
	local kept = {}
	for _, t in ipairs(Cyber.transitions) do
		t.timer = t.timer - dt
		if t.timer <= 0 then World.despawnProp(t.id) else table.insert(kept, t) end
	end
	Cyber.transitions = kept
end

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

-- The rooms of floor i. A branching maze (randomised Prim's algorithm: it grows
-- out in many directions, leaving side passages and dead ends), then extra
-- doorways for loops, so there's usually more than one way through. The way
-- down is in the room furthest from where V arrives, behind a single doorway
-- that seals while the floor below is locked. Dead-end rooms are where data
-- tends to be. The same for every visit to a network.
function Cyber.layout(net, i, f)
	local rng = Rng.new(Network.state.seed or 0, "rooms", net.addr, i)
	-- 4 x 4 at the smallest; files and control floors, bigger and corporate
	-- networks are larger; off-world headquarters reach 8 x 8
	local base = 4
	if f.kind == "files" or f.kind == "control" then base = base + 1 end
	if net.ice >= 4 or net.tier >= 2 then base = base + 1 end
	if net.tier >= 3 then base = base + 2 end
	local w = math.min(8, base + rng:int(0, 1))
	local h = math.min(8, base + rng:int(0, 1))
	local doors = {}
	local function key(ax, ay, bx, by)
		if ax > bx or (ax == bx and ay > by) then ax, ay, bx, by = bx, by, ax, ay end
		return ax .. "," .. ay .. "|" .. bx .. "," .. by
	end
	local function id(x, y) return x .. "," .. y end
	local function neighbours(x, y)
		local list = {}
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nx, ny = x + d[1], y + d[2]
			if nx >= 0 and nx < w and ny >= 0 and ny < h then table.insert(list, { nx, ny }) end
		end
		return list
	end
	local degree = {}
	local function connect(ax, ay, bx, by)
		doors[key(ax, ay, bx, by)] = true
		degree[id(ax, ay)] = (degree[id(ax, ay)] or 0) + 1
		degree[id(bx, by)] = (degree[id(bx, by)] or 0) + 1
	end

	-- V arrives somewhere along one edge of the floor
	local start = { rng:int(0, w - 1), 0 }
	local inMaze, parent = { [id(start[1], start[2])] = true }, {}
	local frontier = {}
	local function addFrontier(x, y)
		for _, n in ipairs(neighbours(x, y)) do
			if not inMaze[id(n[1], n[2])] then table.insert(frontier, { n[1], n[2], x, y }) end
		end
	end
	addFrontier(start[1], start[2])
	while #frontier > 0 do
		local pick = table.remove(frontier, rng:int(1, #frontier))
		local x, y, fx, fy = pick[1], pick[2], pick[3], pick[4]
		if not inMaze[id(x, y)] then
			inMaze[id(x, y)] = true
			parent[id(x, y)] = { fx, fy }
			connect(fx, fy, x, y)
			addFrontier(x, y)
		end
	end

	-- how far each room is from the start, through the maze
	local depth = { [id(start[1], start[2])] = 0 }
	local queue = { start }
	while #queue > 0 do
		local c = table.remove(queue, 1)
		for _, n in ipairs(neighbours(c[1], c[2])) do
			if doors[key(c[1], c[2], n[1], n[2])] and depth[id(n[1], n[2])] == nil then
				depth[id(n[1], n[2])] = depth[id(c[1], c[2])] + 1
				table.insert(queue, n)
			end
		end
	end

	-- the way down: the furthest room with a single doorway
	local goal, best = nil, -1
	for x = 0, w - 1 do
		for y = 0, h - 1 do
			local d = depth[id(x, y)] or 0
			if (x ~= start[1] or y ~= start[2]) and (degree[id(x, y)] or 0) == 1 and d > best then goal, best = { x, y }, d end
		end
	end
	goal = goal or { w - 1, h - 1 }

	-- loops: extra doorways (about one for every five rooms), never into the
	-- goal room, so there's more than one route but still one way in to it
	local wanted = math.max(1, math.floor(w * h / 5))
	for _ = 1, wanted * 6 do
		if wanted <= 0 then break end
		local x, y = rng:int(0, w - 1), rng:int(0, h - 1)
		local list = neighbours(x, y)
		local n = list[rng:int(1, #list)]
		local touchesGoal = (x == goal[1] and y == goal[2]) or (n[1] == goal[1] and n[2] == goal[2])
		if not doors[key(x, y, n[1], n[2])] and not touchesGoal then
			connect(x, y, n[1], n[2])
			wanted = wanted - 1
		end
	end

	-- dead ends: rooms with one doorway (not where V arrives, not the goal)
	local deadEnds, others = {}, {}
	for x = 0, w - 1 do
		for y = 0, h - 1 do
			local isStart = x == start[1] and y == start[2]
			local isGoal = x == goal[1] and y == goal[2]
			if not isStart and not isGoal then
				table.insert((degree[id(x, y)] or 0) == 1 and deadEnds or others, { x, y })
			end
		end
	end
	return { w = w, h = h, doors = doors, key = key, start = start, goal = goal, parent = parent[id(goal[1], goal[2])],
		deadEnds = deadEnds, others = others, depth = depth }
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
			else table.insert(list, { path = path .. "/" .. name, node = child }) end
		end
	end
	if root then walk(root, "/" .. folder) end
	-- a room holds 12 at most: paydata and bank accounts first, then the rest in order
	local function rank(file) return file.node.paydata and 0 or (file.node.bank and 1 or 2) end
	for i, file in ipairs(list) do file.order = i end
	table.sort(list, function(a, b)
		if rank(a) ~= rank(b) then return rank(a) < rank(b) end
		return a.order < b.order
	end)
	while #list > 12 do table.remove(list) end
	return list
end

-- Which marker an object shows (see Kit.markers), or nil for none.
local function markerKind(o)
	if o.kind == "file" then
		if o.node and o.node.paydata then
			if Network.state.looted[Cyber.addr .. ":" .. o.path] then return Kit.markers.taken end
			return Kit.markers.paydata
		end
		return Kit.markers.file
	end
	return Kit.markers[o.kind]
end

-- Shows (or updates, or removes) an object's marker to match its state.
local function showObject(o)
	local kind = markerKind(o)
	if o.markerId and o.markerKind == kind then return end
	if o.markerId then World.despawnProp(o.markerId) o.markerId = nil end
	o.markerKind = kind
	if kind == nil then return end
	local size = Kit.markerSize[kind] or 1.0
	o.markerId = World.spawnBlock(o.x, o.y, o.z, o.yaw or 0, size, size, size, kind)
	local floor = Cyber.floors[o.floor]
	if floor and o.markerId then table.insert(floor.props, o.markerId) end
end
Cyber.showObject = showObject

local function addObject(i, kind, x, y, z, label, extra)
	local o = { floor = i, kind = kind, x = x, y = y, z = z, label = label }
	if extra then for k, v in pairs(extra) do o[k] = v end end
	table.insert(Cyber.objects, o)
	table.insert(Cyber.floors[i].objects, o)
	showObject(o)
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
	if file.node.bank then
		local status = Network.bankStatus(net, file.node.bank)
		if status.frozen then return name .. " (frozen)" end
		if status.available < 20 then return name .. " (emptied)" end
		return name .. " - bank account, " .. status.available .. " eddies"
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
			-- cyberspace particles drifting through the room
			if Kit.particleRooms > 0 and (x + y) % Kit.particleRooms == 0 then
				local id = World.spawnBlock(rx, ry, cz + Kit.wallHeight / 2, 0, r / 2, r / 2, Kit.wallHeight / 2, Kit.particleKind)
				if id ~= nil then
					table.insert(floor.props, id)
					Cyber.particlesAsked = (Cyber.particlesAsked or 0) + 1
					floor.particleIds = floor.particleIds or {}
					floor.particleIds[x .. "," .. y] = id
				end
			end
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

	-- data objects: dead-end rooms first (worth exploring), then the rest
	local rooms = {}
	for _, c in ipairs(L.deadEnds) do table.insert(rooms, c) end
	for _, c in ipairs(L.others) do table.insert(rooms, c) end
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
		addObject(i, "file", x, y, cz, fileLabel(net, file), { path = file.path, node = file.node })
	end
	if f.kind == "control" then
		local x, y = place(#files + 1)
		addObject(i, "console", x, y, cz, "Device control")
	elseif f.kind == "core" then
		addObject(i, "core", gx, gy + 3, cz, "Network core")
	end
end

-- The way down from floor i is barred while floor i + 1 is locked.
local function lockAfter(i)
	local net = Network.get(Cyber.addr)
	local floors = Network.floors(net)
	if i >= #floors or Network.isFloorOpen(Cyber.addr, i + 1) then return nil end
	-- an unguarded core isn't sealed off: walk down and take it
	if Network.isUnguardedCore(floors[i + 1]) and Network.nextLock(Cyber.addr) == i + 1 then return nil end
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
				floor.gateObject = addObject(i, "gate", floor.gateUse.x, floor.gateUse.y, floor.z, "Sealed doorway",
					{ yaw = door.along == "x" and 0 or 90 })
			end
		elseif not lock and floor.gate ~= nil then
			World.despawnProp(floor.gate.barrier)
			floor.gate = nil
			if floor.gateObject then
				floor.gateObject.kind = "spent"
				showObject(floor.gateObject)
				floor.gateObject = nil
			end
			if #floor.ice > 0 then
				for _, id in ipairs(floor.ice) do World.deleteNPC(id) end
				floor.ice, floor.iceHostile = {}, {}
				say("The ICE guarding floor " .. (i + 1) .. " crashes.", "ok")
			end
			say("The doorway on floor " .. i .. " opens.", "ok")
		end
	end
end

-- Takes one floor down: its blocks, props, ICE and objects.
local function unbuildFloor(i)
	local floor = Cyber.floors[i]
	if floor == nil then return end
	for _, id in ipairs(floor.tiles) do World.despawnProp(id) end
	for _, id in ipairs(floor.props) do World.despawnProp(id) end
	for _, id in ipairs(floor.ice) do World.deleteNPC(id) end
	for _, id in ipairs(floor.corpses) do World.deleteNPC(id) end
	if floor.gate then World.despawnProp(floor.gate.barrier) end
	-- patrols go with their floor; anything hunting V waits to follow
	for _, h in ipairs(Cyber.hunters or {}) do
		if h.floor == i and not h.gone then
			if h.id then World.deleteNPC(h.id) end
			h.id = nil
			if h.kind == "patrol" or h.mode ~= "hunt" then h.gone = true end
		end
	end
	local kept = {}
	for _, o in ipairs(Cyber.objects) do
		if o.floor ~= i then table.insert(kept, o) end
	end
	Cyber.objects = kept
	Cyber.floors[i] = nil
end

-- Only the floor V is on and the one below (where V is heading) exist; the
-- rest are built and taken down as V moves, so big networks stay light.
-- Returns true if floor i itself had to be built just now.
function Cyber.ensureFloors(i)
	local net = Network.get(Cyber.addr)
	local floors = Network.floors(net)
	for j in pairs(Cyber.floors) do
		if j < i or j > i + 1 then unbuildFloor(j) end
	end
	local fresh = Cyber.floors[i] == nil
	for j = i, math.min(#floors, i + 1) do
		if Cyber.floors[j] == nil then buildFloor(net, j, floors[j], #floors) end
	end
	refreshGates()
	return fresh
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
	Cyber.ensureFloors(Cyber.startFloor or 1)
end

local function clear()
	for i in pairs(Cyber.floors) do unbuildFloor(i) end
	for _, id in ipairs(Cyber.props) do World.despawnProp(id) end
	Cyber.clearHunters()
	Cyber.armory, Cyber.hackers, Cyber.burning = {}, {}, nil
	for _, e in ipairs(Cyber.hackEffects or {}) do World.removeStatusEffect(e.effect) end
	Cyber.hackEffects = {}
	World.cyberCall("ForgetBlocks")
	Cyber.floors, Cyber.objects, Cyber.props, Cyber.agentNPC = {}, {}, {}, nil
end

---------------------------------------------------------------------------
-- The HUD: meatspace's map and quest tracker don't belong in the Net
---------------------------------------------------------------------------
--
-- Hidden by switching off the game's own HUD settings while jacked in. What
-- was on is remembered in a small file next to the mod as well as in memory,
-- so it's put back even if the game closes while V is still in cyberspace.

Cyber.hudFile = "hud_restore.txt"

local function writeHudFile(names)
	pcall(function()
		local f = io.open(Cyber.hudFile, "w")
		if f then f:write(table.concat(names, "\n")) f:close() end
	end)
end

local function hideHud()
	if Cyber.hudHidden then return end
	local hidden = {}
	for _, name in ipairs(Kit.hideHud) do
		if World.hudSetting(name) == true then table.insert(hidden, name) end
	end
	Cyber.hudHidden = hidden
	if #hidden == 0 then return end
	writeHudFile(hidden)
	local values = {}
	for _, name in ipairs(hidden) do values[name] = false end
	World.setHudSettings(values)
end

-- Puts back whatever hideHud switched off (this session, or one that ended in cyberspace).
function Cyber.restoreHud()
	local names = Cyber.hudHidden
	if names == nil then
		names = {}
		pcall(function()
			local f = io.open(Cyber.hudFile, "r")
			if f then
				for line in f:lines() do if line ~= "" then table.insert(names, line) end end
				f:close()
			end
		end)
	end
	Cyber.hudHidden = nil
	if #names > 0 then
		local values = {}
		for _, name in ipairs(names) do values[name] = true end
		World.setHudSettings(values)
	end
	pcall(os.remove, Cyber.hudFile)
end

---------------------------------------------------------------------------
-- Jacking in and out
---------------------------------------------------------------------------

local function moveToFloor(i, fromBelow, waited)
	if not waited and Cyber.ensureFloors(i) then
		-- the floor was just built (going back up): give it a moment to spawn
		Cyber.pendingMove = { floor = i, fromBelow = fromBelow, timer = 1.0 }
		World.notify("Climbing back up...")
		return
	end
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
	Cyber.huntersFollow(i, fromBelow)
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
	Cyber.target, Cyber.arrived, Cyber.moveTimer, Cyber.toldToStepAway, Cyber.pendingMove = nil, false, 0, false, nil
	-- jacked in through a device wired into a deeper floor: start there
	local start = 1
	if Network.jacked == addr and (Network.jackedFloor or 1) > 1 and Network.isFloorOpen(addr, Network.jackedFloor) then
		start = math.min(Network.jackedFloor, #Network.floors(net))
	end
	Cyber.addr, Cyber.body, Cyber.floor, Cyber.startFloor = addr, body, start, start
	Cyber.bodySafe = addr:sub(1, 5) == "home."
	Cyber.danger, Cyber.dangerTimer, Cyber.falls, Cyber.prompt = nil, 0, {}, nil
	Cyber.hunters, Cyber.encounterTimer, Cyber.deepWarned, Cyber.agentFought = {}, 0, 0, false
	Cyber.raidId, Cyber.raidWave = nil, nil
	local s = state()
	s.active, s.body, s.addr = true, { x = body.x, y = body.y, z = body.z, yaw = body.yaw }, addr

	for _, effect in ipairs(Kit.restrictions) do World.applyStatusEffect(effect) end
	World.setJackedIn(true)
	hideHud()
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
	if body then
		World.teleport(body.x, body.y, body.z + 0.1, body.yaw)
		playTransition(body.x, body.y, body.z)
	end
	for _, effect in ipairs(Kit.restrictions) do World.removeStatusEffect(effect) end
	World.removeStatusEffect(Kit.holsterEffect)
	World.setJackedIn(false)
	Cyber.restoreHud()
	local forced = reason ~= nil and reason ~= "user" and reason ~= "cancelled"
	if forced and reason ~= "broken" and reason ~= "cancelled" then
		World.applyStatusEffect("BaseStatusEffect.PlayerElectrocuted")
	end
	local addr = Cyber.addr
	Cyber.active, Cyber.phase, Cyber.addr, Cyber.body, Cyber.danger, Cyber.pendingMove = false, nil, nil, nil, nil, nil
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
	Cyber.active, Cyber.floors, Cyber.objects, Cyber.props, Cyber.agentNPC, Cyber.hunters = false, {}, {}, {}, nil, {}
	-- the HUD comes back if the game last closed (or a save loaded) mid-cyberspace
	Cyber.restoreHud()
	local s = Network.state and Network.state.cyber
	if s and s.active and s.body then Cyber.pendingRecover = 2.0 end
end

local function recover()
	local s = state()
	if s.body then World.teleport(s.body.x, s.body.y, s.body.z + 0.1, s.body.yaw) end
	for _, effect in ipairs(Kit.restrictions) do World.removeStatusEffect(effect) end
	World.removeStatusEffect(Kit.holsterEffect)
	World.setJackedIn(false)
	Cyber.restoreHud()
	s.active, s.body, s.addr = false, nil, nil
	say("You wake up where you jacked in.", "warn")
end

---------------------------------------------------------------------------
-- How cyberspace looks (see cyberkit.lua for the settings)
---------------------------------------------------------------------------

function Cyber.applyLook()
	World.cyberCall("SetFloorStyle", Kit.defaultStyle)
	World.cyberCall("SetWallStyle", Kit.defaultWalls)
	World.cyberCall("SetLight", Kit.lightLevel, Kit.defaultLightColour)
	World.cyberCall("SetFloorScale", Kit.defaultScale)
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
			showObject(o)
			World.notify("Downloaded " .. o.path:match("([^/]+)$"))
		elseif o.node.bank then
			Cyber.run("bank " .. o.path)
			o.label = fileLabel(net, o)
			Cyber.openDeck()
		else
			Cyber.run("cat " .. o.path)
			Cyber.openDeck()
		end
	elseif o.kind == "console" then
		Cyber.run("devices")
		Cyber.openDeck()
	elseif o.kind == "core" then
		local revealed = Network.claimCore(net.addr)
		if revealed then
			say("Nothing guards the core. Root access on " .. net.name .. ".", "ok")
			for _, r in ipairs(revealed) do say("New route found: " .. r, "ok") end
			emit("hack.breach", { addr = net.addr, org = net.org, success = true, ice = 0, tier = net.tier, floor = o.floor, cyberspace = true })
			World.notify("Root access")
		else
			Cyber.run("status")
			World.notify(Network.isOwned(net.addr) and "Root access. This network is yours." or "The core is still locked.")
		end
	end
	emit("cyber.use", { addr = net.addr, kind = o.kind, path = o.path })
	return true
end

---------------------------------------------------------------------------
-- ICE and NetWatch in person
---------------------------------------------------------------------------

-- What the scanner calls something that belongs to `who` (an org id, or one of
-- NetWatch / a rogue AI): name, affiliation.
local function scanLabelFor(who, role)
	if who == "rogueai" then return "Rogue AI construct", "Beyond the Blackwall" end
	if who == "netwatch" then return "NetWatch agent", "NetWatch" end
	local org = Lore.getOrg(who)
	return org.name .. " " .. role, org.name
end

local function scanLabel(h)
	if h.kind == "patrol" then return scanLabelFor(h.holder, "ICE") end
	if h.kind == "raider" then return scanLabelFor(h.attacker, "netrunner") end
	if h.kind == "rogue" then return "Rogue AI", "Beyond the Blackwall" end
	if h.kind == "agent" then return "NetWatch agent", "NetWatch" end
	if h.kind == "rival" then return "Rival netrunner", "Freelance" end
	return nil
end

-- The gate's ICE, named for whoever holds the network now.
local function iceLabel(lock)
	local holder = Territory.holder(Cyber.addr) or (Network.get(Cyber.addr) or {}).org
	local name, faction = scanLabelFor(holder, lock.kind == "black" and "Black ICE" or "ICE")
	if holder == "rogueai" or holder == "netwatch" then name = lock.kind == "black" and "Black ICE" or "ICE" end
	return name, faction
end

local function spawnIce(i)
	local floor = Cyber.floors[i]
	local lock = lockAfter(i)
	if floor == nil or not isIceLock(lock) or #floor.ice > 0 or floor.iceCleared then return end
	local net = Network.get(Cyber.addr)
	local holder = Territory.holder(net.addr) or net.org
	local org = Lore.getOrg(holder)
	local record = Kit.iceRecord(holder, org, lock.kind == "black")
	if lock.kind ~= "black" then
		if holder == "rogueai" then record = Kit.rogueAI[math.floor(roll() * #Kit.rogueAI) + 1] or Kit.rogueAI[1]
		elseif holder == "netwatch" then record = Kit.netwatch end
	end
	local count = 1 + math.floor(lock.ice / 3)
	local spot = floor.iceSpot
	local x, y, z
	if spot then x, y, z = spot.x, spot.y, spot.z else x, y, z = descentPoint(i) end
	for k = 1, count do
		local offset = (k - (count + 1) / 2) * 2.5
		local id = World.spawnNPC(fighterRecord(record), x + offset, y + offset * 0.3, z + 0.2, 180)
		if id ~= nil then World.setScannerName(id, iceLabel(lock)) end
		if id ~= nil then table.insert(floor.ice, id) floor.iceRecords = floor.iceRecords or {} floor.iceRecords[id] = fighterRecord(record) end
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
			-- ICE fights like V: bare hands. One that turns out to carry a gun is
			-- swapped for a fist fighter where it stands.
			local rec = floor.iceRecords and floor.iceRecords[id]
			if Kit.combatRules and rec and carriesGun(id, rec, Cyber.gunChecked) then
				local p = World.npcPosition(id)
				World.deleteNPC(id)
				local newRec = fighterRecord(rec)
				local newId = p and World.spawnNPC(newRec, p.x, p.y, p.z, 180)
				if newId then World.setScannerName(newId, iceLabel(lockAfter(Cyber.floor) or { kind = "ice" })) end
				if newId then
					floor.ice[k], floor.iceRecords[newId], floor.iceHostile[k] = newId, newRec, false
				end
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

---------------------------------------------------------------------------
-- Things that hunt V through the rooms
---------------------------------------------------------------------------
--
-- Cyberspace has no navigation mesh, so hunters move the way data does: they
-- blink from room to room through the doorways, following the maze. Once one
-- shares a room with V it fights normally.
--
--   patrol  the network's own ICE, wandering the corridors of networks you
--           don't own; it starts hunting when it gets close
--   rival   another netrunner working the same network; anywhere, even
--           networks you own; drops eddies
--   rogue   a rogue AI loose in the network; rarer, tougher, worth more, makes
--           the news
--   agent   a NetWatch agent who traced in: it arrives on the far side of the
--           floor and works its way to you
--
-- Rivals, rogue AIs and agents follow V between floors; patrols stay on theirs.

Cyber.hunters = {}

local function cellId(c) return c[1] .. "," .. c[2] end

-- The room a point on floor i is in: { x, y }.
local function roomAt(i, px, py)
	local floor = Cyber.floors[i]
	if floor == nil or floor.layout == nil then return nil end
	local L = floor.layout
	local cx, cy = centre(i)
	local r = Kit.roomSize
	local x = math.floor((px - cx) / r + L.w / 2)
	local y = math.floor((py - cy) / r + L.h / 2)
	return { math.max(0, math.min(L.w - 1, x)), math.max(0, math.min(L.h - 1, y)) }
end
Cyber.roomAt = roomAt

local function doorsFrom(L, c)
	local list = {}
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local nx, ny = c[1] + d[1], c[2] + d[2]
		if nx >= 0 and nx < L.w and ny >= 0 and ny < L.h and L.doors[L.key(c[1], c[2], nx, ny)] then
			table.insert(list, { nx, ny })
		end
	end
	return list
end

-- Steps (through doorways) from room a to every room: id -> steps, id -> first step.
local function distances(L, a)
	local dist, first = { [cellId(a)] = 0 }, {}
	local queue = { a }
	while #queue > 0 do
		local c = table.remove(queue, 1)
		for _, n in ipairs(doorsFrom(L, c)) do
			local nid = cellId(n)
			if dist[nid] == nil then
				dist[nid] = dist[cellId(c)] + 1
				first[nid] = first[cellId(c)] or n
				table.insert(queue, n)
			end
		end
	end
	return dist, first
end
Cyber.distances = distances

-- The next room from a towards b.
local function stepToward(L, a, b)
	local dist, first = distances(L, a)
	return first[cellId(b)], dist[cellId(b)]
end

local function vRoom()
	local pos = World.playerTransform()
	if pos == nil then return nil end
	return roomAt(Cyber.floor, pos.x, pos.y)
end

local hunterNames = {
	rival = { "a rival netrunner", "a merc netrunner", "a freelance runner" },
	rogue = { "a rogue AI", "a fragment from beyond the Blackwall", "a feral AI" },
}

local function spawnHunter(h, room, from)
	local floor = Cyber.floors[h.floor]
	if floor == nil then return false end
	local x, y = cellCentre(h.floor, floor.layout, room[1], room[2])
	local yaw = 0
	if from then
		-- coming through the doorway from the room it was in
		x = x + (from[1] - room[1]) * (Kit.roomSize / 2 - 2.5)
		y = y + (from[2] - room[2]) * (Kit.roomSize / 2 - 2.5)
		yaw = math.deg(math.atan2(room[1] - from[1], room[2] - from[2])) * -1
	end
	h.room = room
	if h.id == nil then
		h.actualRecord = fighterRecord(h.record)
		h.id = World.spawnNPC(h.actualRecord, x, y, floor.z + 0.2, yaw)
		h.hostile, h.disarmed = false, 0
		if h.id then World.setScannerName(h.id, scanLabel(h)) end
		return h.id ~= nil
	end
	return World.moveNPC(h.id, x, y, floor.z + 0.2, yaw)
end

local function addHunter(kind, record, floorIndex, room, extra)
	local h = { kind = kind, record = record, floor = floorIndex, hop = 0,
		mode = kind == "patrol" and "patrol" or "hunt" }
	if extra then for k, v in pairs(extra) do h[k] = v end end
	if not spawnHunter(h, room) then return nil end
	table.insert(Cyber.hunters, h)
	return h
end

-- A room on floor i at least `far` steps from V (the furthest it can find).
local function farRoom(i, far, notGoal)
	local floor = Cyber.floors[i]
	local L = floor.layout
	local here = (i == Cyber.floor and vRoom()) or L.start
	local dist = distances(L, here)
	local options, best, bestD = {}, nil, -1
	for x = 0, L.w - 1 do
		for y = 0, L.h - 1 do
			local d = dist[x .. "," .. y] or 0
			local isGoal = notGoal and x == L.goal[1] and y == L.goal[2]
			if not isGoal then
				if d >= far then table.insert(options, { x, y }) end
				if d > bestD then best, bestD = { x, y }, d end
			end
		end
	end
	if #options > 0 then return options[math.floor(roll() * #options) + 1] or options[1] end
	return best or L.start
end

local function removeHunter(h, keepBody)
	if h.id then
		local floor = Cyber.floors[h.floor]
		if keepBody and floor then table.insert(floor.corpses, h.id) else World.deleteNPC(h.id) end
	end
	h.id, h.gone = nil, true
end

-- Patrols: the network's own ICE, on networks V doesn't own.
local function spawnPatrols(i)
	local floor = Cyber.floors[i]
	local net = Network.get(Cyber.addr)
	if floor == nil or floor.patrolled or net == nil then return end
	floor.patrolled = true
	if net.ice <= 0 or Network.isOwned(net.addr) or Cyber.bodySafe then return end
	-- whoever holds the network now runs its ICE (modules/territory)
	local holder = Territory.holder(net.addr) or net.org
	local org = Lore.getOrg(holder)
	local count = 1
	if net.ice >= 5 or floor.layout.w * floor.layout.h >= 36 then count = 2 end
	if net.ice >= 8 then count = 3 end
	for _ = 1, count do
		local record = Kit.iceRecord(holder, org, false)
		if holder == "rogueai" then record = Kit.rogueAI[math.floor(roll() * #Kit.rogueAI) + 1] or Kit.rogueAI[1]
		elseif holder == "netwatch" then record = Kit.netwatch end
		addHunter("patrol", record, i, farRoom(i, 3, true), { holder = holder })
	end
end

local function rewardFor(h)
	local net = Network.get(Cyber.addr)
	local tier = net and net.tier or 1
	if h.kind == "rival" then
		local eddies = math.floor((150 + roll() * 250) * tier)
		World.giveMoney(eddies)
		say("You derezzed " .. h.name .. ". Their deck shards fence for " .. eddies .. " eddies.", "ok")
	elseif h.kind == "rogue" then
		local eddies = math.floor((900 + roll() * 900) * tier)
		World.giveMoney(eddies)
		say("The rogue AI comes apart. What's left of its code is worth " .. eddies .. " eddies to the right buyer.", "ok")
		Network.addNews("Unknown netrunner purges a rogue AI from " .. (net and net.name or "a network"))
		emit("cyber.rogue_ai_defeated", { addr = Cyber.addr })
	elseif h.kind == "agent" then
		local _, message = NetWatch.win()
		say(message, "ok")
	elseif h.kind == "patrol" then
		say("Patrol ICE derezzed.", "ok")
	elseif h.kind == "raider" then
		local eddies = math.floor((100 + roll() * 150) * tier)
		World.giveMoney(eddies)
		local a = Territory.weaken(Cyber.addr, 2, "cyberspace")
		say("You derezzed " .. h.name .. " (+" .. eddies .. " eddies)." .. (a and (" Attack strength " .. a.power .. ".") or " The attack is broken."), "ok")
	end
	emit("cyber.hunter_defeated", { addr = Cyber.addr, kind = h.kind })
end

local function updateHunter(h, dt, here)
	if h.gone then return end
	if h.follow then
		-- following V to another floor
		h.follow = h.follow - dt
		if h.follow <= 0 and Cyber.floors[h.floor] then
			h.follow = nil
			if spawnHunter(h, h.room) then
				say((h.name or "Something") .. " followed you down here.", "err")
			else
				h.gone = true
			end
		end
		return
	end
	if h.id == nil then h.gone = true return end -- (followers waiting for V have h.follow)
	local dead = World.npcDead(h.id)
	if dead == nil then return end -- still spawning
	if dead == true then
		removeHunter(h, true)
		rewardFor(h)
		return
	end
	if not h.hostile then h.hostile = World.makeHostile(h.id) end
	-- a fighter carrying a gun is swapped for a fist fighter where it stands
	if Kit.combatRules and carriesGun(h.id, h.actualRecord or h.record, Cyber.gunChecked) then
		World.deleteNPC(h.id)
		h.id = nil
		h.record = fighterRecord(h.actualRecord or h.record)
		spawnHunter(h, h.room)
		return
	end
	if h.floor ~= Cyber.floor then return end
	local floor = Cyber.floors[h.floor]
	local L = floor and floor.layout
	if L == nil or here == nil then return end

	-- where it really is (it may have walked)
	local p = World.npcPosition(h.id)
	if p then h.room = roomAt(h.floor, p.x, p.y) or h.room end
	local _, steps = stepToward(L, h.room, here)
	steps = steps or 99

	if h.mode == "patrol" and steps <= Kit.patrolSight then
		h.mode = "hunt"
		say("Patrol ICE has picked up your trail.", "warn")
		World.notify("ICE is hunting you")
	end
	if steps == 0 then
		h.hop = 0
		-- fighting the network's own ICE is loud
		if h.kind == "patrol" then Cyber.addTrace(dt * 0.5) end
		return
	end

	h.hop = h.hop + dt
	local every = h.mode == "hunt" and Kit.huntHop or Kit.patrolHop
	if h.hop < every then return end
	h.hop = 0
	local nextRoom
	if h.mode == "hunt" then
		nextRoom = stepToward(L, h.room, here)
	else
		local options = doorsFrom(L, h.room)
		nextRoom = options[math.floor(roll() * #options) + 1] or options[1]
	end
	if nextRoom then spawnHunter(h, nextRoom, h.room) end
	if h.mode == "hunt" and nextRoom and nextRoom[1] == here[1] and nextRoom[2] == here[2] and not h.announced then
		h.announced = true
		World.warn((h.name or "Something") .. " is here")
	end
end

-- V went to floor i: followers come after them, patrols stay behind.
local function huntersFollow(i, fromBelow)
	local floor = Cyber.floors[i]
	if floor == nil or floor.layout == nil then return end
	local entry = fromBelow and floor.layout.goal or floor.layout.start
	for _, h in ipairs(Cyber.hunters) do
		if not h.gone and h.kind ~= "patrol" and h.floor ~= i and h.mode == "hunt" then
			if h.id then World.deleteNPC(h.id) end
			h.id, h.floor, h.room, h.follow = nil, i, entry, 6 + roll() * 6
		end
	end
end

local function clearHunters()
	for _, h in ipairs(Cyber.hunters or {}) do removeHunter(h, false) end
	Cyber.hunters, Cyber.agentNPC = {}, nil
end
Cyber.clearHunters = clearHunters
Cyber.huntersFollow = huntersFollow

local function activeCount(kinds)
	local n = 0
	for _, h in ipairs(Cyber.hunters) do
		if not h.gone and kinds[h.kind] then n = n + 1 end
	end
	return n
end

-- Now and then something else turns up: on any network, even yours.
local function rollEncounter(dt)
	Cyber.encounterTimer = (Cyber.encounterTimer or 0) + dt
	if Cyber.encounterTimer < Kit.encounterEvery then return end
	Cyber.encounterTimer = 0
	local function last(text) Cyber.lastEncounter = text end
	if Cyber.bodySafe then return last("none: you're at home") end -- your own machine at home
	local here = Network.get(Cyber.addr)
	-- no other netrunner can get into a network with no link to the Net
	local cutOff = here and (here.isolated or here.closed)
	if activeCount({ rival = true, rogue = true }) >= Kit.encounterMax then return last("none: already " .. Kit.encounterMax .. " here") end
	local net = Network.get(Cyber.addr)
	local tier = net and net.tier or 1
	local floor = Cyber.floors[Cyber.floor]
	if floor == nil or floor.layout == nil then return last("none: floor not built") end
	local r = roll()
	local rogueChance = 0.03 + 0.02 * tier + (Cyber.floor >= Kit.deepFloor and 0.03 or 0)
	if here and Territory.holder(here.addr) == "rogueai" then rogueChance = rogueChance + 0.3 end -- its home now
	local rivalChance = 0.12 + 0.03 * tier
	local kind
	if r < rogueChance then kind = "rogue" elseif r < rogueChance + rivalChance and not cutOff then kind = "rival"
	else
		return last(string.format("nothing (rolled %.2f; rival under %.2f%s, rogue AI under %.2f)", r, rogueChance + rivalChance,
			cutOff and " but this network is cut off" or "", rogueChance))
	end
	local list = kind == "rogue" and Kit.rogueAI or Kit.rivals
	local names = hunterNames[kind]
	local name = names[math.floor(roll() * #names) + 1] or names[1]
	local h = addHunter(kind, list[math.floor(roll() * #list) + 1] or list[1], Cyber.floor, farRoom(Cyber.floor, 3, false), { name = name })
	if h == nil then return last(kind .. " failed to spawn (" .. tostring(World.lastError) .. ")") end
	last(kind .. " spawned")
	if kind == "rogue" then
		say("Something else is in here with you: " .. name .. ". It knows where you are.", "err")
		World.warn("Rogue AI in the network")
	else
		say("You're not alone: " .. name .. " is working this network, and wants you out of it.", "warn")
		World.warn("Rival netrunner")
	end
	emit("cyber.encounter", { addr = Cyber.addr, kind = kind, floor = Cyber.floor })
end

-- A fight over this network (modules/territory): the attackers' netrunners are
-- here. Each one V derezzes weakens the attack; they come in waves until it ends.
local function updateRaid(dt)
	local a = Territory.attackOn(Cyber.addr)
	local id = a and a.id
	if id ~= Cyber.raidId then
		if Cyber.raidId then
			for _, h in ipairs(Cyber.hunters) do
				if h.kind == "raider" and not h.gone then removeHunter(h, false) end
			end
			if a == nil then say("The fight over this network is over.", "warn") end
		end
		Cyber.raidId, Cyber.raidWave = id, nil
	end
	if a == nil then return end
	local raiders = activeCount({ raider = true })
	local floor = Cyber.floors[Cyber.floor]
	if floor == nil or floor.layout == nil then return end
	if raiders == 0 then
		-- a new wave: straight away the first time, then after a breather
		if Cyber.raidWave ~= nil then
			Cyber.raidWave = Cyber.raidWave - dt
			if Cyber.raidWave > 0 then return end
		end
		local org = Lore.getOrg(a.attacker)
		local count = math.max(1, math.min(3, math.ceil(a.power / 3)))
		local spawned = 0
		local who = a.attacker == "rogueai" and "The rogue AI's constructs" or a.attacker == "netwatch" and "NetWatch agents"
			or (org.name .. " netrunners")
		for _ = 1, count do
			local record, name = Kit.iceRecord(a.attacker, org, false), org.name .. " netrunner"
			if a.attacker == "rogueai" then record, name = Kit.rogueAI[math.floor(roll() * #Kit.rogueAI) + 1] or Kit.rogueAI[1], "a rogue AI construct"
			elseif a.attacker == "netwatch" then record, name = Kit.netwatch, "a NetWatch agent" end
			if addHunter("raider", record, Cyber.floor, farRoom(Cyber.floor, 2, false), { name = name, attacker = a.attacker }) then spawned = spawned + 1 end
		end
		if spawned > 0 then
			if a.raid then
				say(who .. " are in your network, fighting for it. Derezz them.", "err")
				World.warn(a.attacker == "rogueai" and "Rogue AI in your network" or (org.name .. " raiders"))
			elseif Cyber.raidWave == nil then
				say(who .. " are fighting " .. Territory.holderName(a.holder) ..
					" for this network. Hit them and you help the defenders.", "warn")
			end
		end
		Cyber.raidWave = 20
		return
	end
	-- the raiders and the network's own ICE fight each other
	for _, r in ipairs(Cyber.hunters) do
		if r.kind == "raider" and not r.gone and r.id and not r.enemies then
			local ready = World.npcDead(r.id) ~= nil
			if ready then
				r.enemies = true
				for _, h in ipairs(Cyber.hunters) do
					if h.kind == "patrol" and not h.gone and h.id then World.makeEnemies(r.id, h.id) end
				end
			end
		end
	end
end

-- The NetWatch agent who traced into this network comes for V in person.
local function updateAgent()
	local agent = NetWatch.agent
	local mine
	for _, h in ipairs(Cyber.hunters) do
		if h.kind == "agent" and not h.gone then mine = h end
	end
	if agent and agent.addr == Cyber.addr and agent.eta <= 0 then
		if mine == nil and not Cyber.agentFought then
			local floor = Cyber.floors[Cyber.floor]
			if floor and floor.layout then
				mine = addHunter("agent", Kit.netwatch, Cyber.floor, farRoom(Cyber.floor, 99, false), { name = agent.name })
				if mine then
					Cyber.agentFought = true
					say(agent.name .. " is in the network, on the far side of this floor, and closing on you.", "err")
					World.warn("NetWatch is coming")
				end
			end
		end
	elseif mine then
		removeHunter(mine, false)
	end
	if agent == nil then Cyber.agentFought = false end
	Cyber.agentNPC = mine and not mine.gone and mine.id or nil
end

---------------------------------------------------------------------------
-- Enemy quickhacks
---------------------------------------------------------------------------
--
-- The fighters in cyberspace are brawlers, so the hacking is done here:
-- every fighter close to V uploads a quickhack now and then, with a warning
-- while it uploads. Killing it first cancels the hack.

Cyber.hackers = {}

local function isElite(record)
	return tostring(record):find("elite", 1, true) ~= nil or tostring(record):find("boxingrobot", 1, true) ~= nil
end

local function pickHack(elite)
	local options = {}
	for _, h in ipairs(Kit.enemyHacks) do
		if elite or not h.elite then table.insert(options, h) end
	end
	return options[math.floor(roll() * #options) + 1] or options[1]
end

local function landHack(hack, who)
	if hack.damage then World.damagePlayer(hack.damage) end
	if hack.trace then Cyber.addTrace(hack.trace) end
	if hack.effect then
		World.applyStatusEffect(hack.effect)
		table.insert(Cyber.hackEffects, { effect = hack.effect, timer = hack.burn or 1.5 })
	end
	if hack.burn then Cyber.burning = { left = hack.burn, perSecond = hack.damage / hack.burn } end
	say(who .. "'s " .. hack.name .. " hits you.", "err")
end

-- Every fighter on V's floor: { id, record, name }
local function fighters()
	local list = {}
	local floor = Cyber.floors[Cyber.floor]
	if floor == nil then return list end
	local net = Network.get(Cyber.addr)
	local org = net and Lore.getOrg(net.org)
	for _, id in ipairs(floor.ice) do
		table.insert(list, { id = id, record = org and Kit.iceRecord(net.org, org, false) or "", name = "ICE" })
	end
	for _, h in ipairs(Cyber.hunters) do
		if not h.gone and h.id and h.floor == Cyber.floor then
			local names = { patrol = "Patrol ICE", rival = "The rival netrunner", rogue = "The rogue AI", agent = "NetWatch" }
			table.insert(list, { id = h.id, record = h.record, name = names[h.kind] or "Something" })
		end
	end
	return list
end

local function updateEnemyHacks(dt, here)
	Cyber.hackEffects = Cyber.hackEffects or {}
	-- effects wearing off
	local kept = {}
	for _, e in ipairs(Cyber.hackEffects) do
		e.timer = e.timer - dt
		if e.timer <= 0 then World.removeStatusEffect(e.effect) else table.insert(kept, e) end
	end
	Cyber.hackEffects = kept
	-- Overheat keeps burning for a few seconds
	if Cyber.burning then
		local step = math.min(dt, Cyber.burning.left)
		World.damagePlayer(Cyber.burning.perSecond * step)
		Cyber.burning.left = Cyber.burning.left - step
		if Cyber.burning.left <= 0 then Cyber.burning = nil end
	end

	local floor = Cyber.floors[Cyber.floor]
	local L = floor and floor.layout
	if L == nil or here == nil then return end
	local dist = distances(L, here)
	local alive = {}
	for _, f in ipairs(fighters()) do
		alive[f.id] = true
		local s = Cyber.hackers[f.id]
		local elite = isElite(f.record)
		if s == nil then
			s = { cool = Kit.hackEvery[1] * 0.5 + roll() * 4 }
			Cyber.hackers[f.id] = s
		end
		local dead = World.npcDead(f.id)
		local p = dead == false and World.npcPosition(f.id)
		local room = p and roomAt(Cyber.floor, p.x, p.y)
		local close = room and (dist[cellId(room)] or 99) <= Kit.hackRange
		if dead ~= false then
			if s.upload then say(f.name .. "'s upload dies with it.", "ok") end
			s.upload = nil
		elseif s.upload then
			s.upload.left = s.upload.left - dt
			if s.upload.left <= 0 then
				local hack = s.upload.hack
				s.upload = nil
				if close then landHack(hack, f.name) else say(f.name .. "'s " .. hack.name .. " loses you.", "ok") end
				if not Cyber.active then return end
			end
		elseif close then
			s.cool = s.cool - dt
			if s.cool <= 0 then
				local hack = pickHack(elite)
				s.upload = { hack = hack, left = hack.upload }
				local every = Kit.hackEvery[1] + roll() * (Kit.hackEvery[2] - Kit.hackEvery[1])
				s.cool = elite and every * 0.66 or every
				World.warn("QUICKHACK UPLOAD: " .. hack.name .. " (" .. math.floor(hack.upload) .. "s)")
				say(f.name .. " is uploading " .. hack.name .. " into you. Take it down!", "warn")
				emit("cyber.enemy_hack", { addr = Cyber.addr, hack = hack.name })
			end
		end
	end
	for id in pairs(Cyber.hackers) do if not alive[id] then Cyber.hackers[id] = nil end end
end
Cyber.updateEnemyHacks = updateEnemyHacks

local function updateHunters(dt)
	spawnPatrols(Cyber.floor)
	updateAgent()
	rollEncounter(dt)
	local here = vRoom()
	for _, h in ipairs(Cyber.hunters) do updateHunter(h, dt, here) end
	if Kit.combatRules then
		updateEnemyHacks(dt, here)
		if not Cyber.active then return end
	end
	local kept = {}
	for _, h in ipairs(Cyber.hunters) do if not h.gone then table.insert(kept, h) end end
	Cyber.hunters = kept
	updateAgent()
end

-- The deeper V goes into a network that isn't theirs, the easier V is to find.
local function updateDepth(dt)
	local net = Network.get(Cyber.addr)
	if net == nil or Cyber.bodySafe or Network.isOwned(net.addr) or Cyber.floor < Kit.deepFloor then return end
	local depth = Cyber.floor - Kit.deepFloor + 1
	Cyber.addTrace(dt * Kit.deepTrace * depth * (1 + 0.5 * (net.tier or 1)))
	if (Cyber.deepWarned or 0) < Cyber.floor then
		Cyber.deepWarned = Cyber.floor
		say("Deep in " .. net.name .. ". Every second down here makes you easier to trace.", "warn")
	end
end

---------------------------------------------------------------------------
-- Scanning: a map of the rooms around V
---------------------------------------------------------------------------

-- Returns ok, text.
function Cyber.scan()
	if not Cyber.active or Cyber.phase ~= "in" then return false, "Scan works in cyberspace. 'jackin' first." end
	local floor = Cyber.floors[Cyber.floor]
	local here = vRoom()
	if floor == nil or floor.layout == nil or here == nil then return false, "Nothing to scan yet." end
	local L = floor.layout
	local net = Network.get(Cyber.addr)
	local free = Cyber.bodySafe or Network.isOwned(net.addr)
	if not free then Cyber.addTrace(Kit.scanTrace) end
	if not Cyber.active then return false, "The scan gave you away." end

	-- every room within range, by the route to it (the deck's font isn't
	-- monospaced, so routes rather than a drawn map)
	local range = Kit.scanRange
	local function dirName(a, b)
		if b[1] > a[1] then return "east" elseif b[1] < a[1] then return "west"
		elseif b[2] > a[2] then return "north" end
		return "south"
	end
	local routes, order = { [cellId(here)] = {} }, {}
	local queue = { here }
	while #queue > 0 do
		local c = table.remove(queue, 1)
		local route = routes[cellId(c)]
		if #route < range then
			for _, n in ipairs(doorsFrom(L, c)) do
				if routes[cellId(n)] == nil then
					local r = { unpack(route) }
					table.insert(r, dirName(c, n))
					routes[cellId(n)] = r
					table.insert(order, n)
					table.insert(queue, n)
				end
			end
		end
	end

	local found = {}
	local function note(c, text)
		local id = cellId(c)
		if routes[id] == nil then return end
		found[id] = found[id] or {}
		for _, v in ipairs(found[id]) do if v == text then return end end
		table.insert(found[id], text)
	end
	for _, o in ipairs(floor.objects) do
		local c = roomAt(Cyber.floor, o.x, o.y)
		if c then
			if o.kind == "file" then note(c, "data")
			elseif o.kind == "console" then note(c, "device control")
			elseif o.kind == "core" then note(c, "the network core")
			elseif o.kind == "up" or o.kind == "exit" then note(c, "the way back up")
			end
		end
	end
	local floors = Network.floors(net)
	if Cyber.floor < #floors then note(L.goal, floor.gate and "the way down (sealed)" or "the way down") end
	local hostiles = 0
	local function hostileAt(c, what)
		if c and routes[cellId(c)] then
			note(c, what)
			hostiles = hostiles + 1
		end
	end
	for _, h in ipairs(Cyber.hunters) do
		if not h.gone and h.id and h.floor == Cyber.floor then
			local what = ({ patrol = "patrol ICE", rival = "a rival netrunner", rogue = "a rogue AI", agent = "NetWatch" })[h.kind]
			hostileAt(h.room, (what or "something") .. "!")
		end
	end
	for _, id in ipairs(floor.ice) do
		local p = World.npcPosition(id)
		hostileAt(p and roomAt(Cyber.floor, p.x, p.y), "ICE guarding the doorway!")
	end

	local lines = { "SCAN - floor " .. Cyber.floor .. (free and "" or " (+" .. Kit.scanTrace .. "% trace)") }
	local exits = {}
	for _, n in ipairs(doorsFrom(L, here)) do
		local text = dirName(here, n)
		if #doorsFrom(L, n) == 1 then text = text .. " (dead end)" end
		table.insert(exits, text)
	end
	table.insert(lines, "Doorways here: " .. (#exits > 0 and table.concat(exits, ", ") or "none"))
	if found[cellId(here)] then table.insert(lines, "This room: " .. table.concat(found[cellId(here)], ", ")) end
	for _, c in ipairs(order) do
		local things = found[cellId(c)]
		if things then table.insert(lines, "  " .. table.concat(routes[cellId(c)], ", then ") .. ": " .. table.concat(things, ", ")) end
	end
	local dist = distances(L, here)
	local goalSteps = dist[cellId(L.goal)]
	if Cyber.floor < #floors and goalSteps and goalSteps > range then
		table.insert(lines, "The way down is " .. goalSteps .. " rooms away, beyond the scan.")
	end
	if hostiles == 0 then table.insert(lines, "Nothing hostile nearby.") end
	local text = table.concat(lines, "\n")
	World.notify("Scan: " .. (goalSteps and ("way down " .. goalSteps .. (goalSteps == 1 and " room" or " rooms") .. " away") or "done") ..
		(hostiles > 0 and (", " .. hostiles .. " hostile nearby") or ""))
	emit("cyber.scan", { addr = Cyber.addr, floor = Cyber.floor })
	return true, text
end

---------------------------------------------------------------------------
-- Bare hands only
---------------------------------------------------------------------------

local function allowedWeapon(kind)
	if kind == nil then return true end
	for _, k in ipairs(Kit.allowedWeapons) do
		if kind == k then return true end
	end
	return false
end

-- A gun or blade in V's hands is put away (briefly blocking weapons, which
-- makes V holster), then weapons are allowed again so fists still work.
local function updateWeapons(dt)
	local kind = World.weaponInHand()
	if Cyber.holstering then
		-- kept on until the weapon has been gone for a moment
		if allowedWeapon(kind) then
			Cyber.holstering = Cyber.holstering - dt
		else
			Cyber.holstering = Kit.holsterTime
		end
		if Cyber.holstering <= 0 then
			World.removeStatusEffect(Kit.holsterEffect)
			Cyber.holstering = nil
		end
		return
	end
	if not allowedWeapon(kind) then
		World.applyStatusEffect(Kit.holsterEffect)
		Cyber.holstering = Kit.holsterTime
		World.notify("No weapons in cyberspace: quickhacks and bare hands only")
	end
end
Cyber.allowedWeapon = allowedWeapon

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
	Cyber.updateTransitions(dt)
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
			moveToFloor(Cyber.startFloor or 1, false)
		end
		return
	end

	if Cyber.pendingMove then
		Cyber.pendingMove.timer = Cyber.pendingMove.timer - dt
		if Cyber.pendingMove.timer <= 0 then
			local move = Cyber.pendingMove
			Cyber.pendingMove = nil
			moveToFloor(move.floor, move.fromBelow, true)
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
				playTransition(pos.x, pos.y, pos.z)
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

	if Kit.combatRules then updateWeapons(dt) end

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
		updateHunters(step)
		if not Cyber.active then return end
		updateRaid(step)
		if not Cyber.active then return end
		updateDepth(step)
		if not Cyber.active then return end
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
		", floor mesh size: " .. tostring(World.cyberCall("FloorMeshSize")) ..
		", marker meshes loaded: " .. tostring((World.cyberCall("MarkersLoaded"))) .. "/8")
	table.insert(lines, string.format("encounters: next roll in %ds, last: %s", math.max(0, math.floor(Kit.encounterEvery - (Cyber.encounterTimer or 0))),
		tostring(Cyber.lastEncounter or "none yet")))
	local hl = {}
	for _, h in ipairs(Cyber.hunters or {}) do
		table.insert(hl, h.kind .. (h.follow and " (following)" or "") .. " floor " .. tostring(h.floor) .. (h.mode == "hunt" and " hunting" or ""))
	end
	table.insert(lines, "hunters: " .. (#hl > 0 and table.concat(hl, ", ") or "none"))
	do
		local floor = Cyber.floors[Cyber.floor]
		local here = pos and roomAt(Cyber.floor, pos.x, pos.y)
		local id = floor and floor.particleIds and here and floor.particleIds[here[1] .. "," .. here[2]]
		local name
		if id then pcall(function() name = World.particleFor[tostring(id.hash)] end) end
		table.insert(lines, "particles in this room: " .. tostring(name or "none"))
	end
	table.insert(lines, "particles: asked " .. (Cyber.particlesAsked or 0) .. ", blocks seen " .. tostring(World.particleSeen) ..
		", particle blocks found " .. tostring(World.particleBlocks or 0) .. ", added " .. tostring(World.particlesAdded) ..
		(World.particleError and (", error: " .. World.particleError) or ""))
	table.insert(lines, "V's effects: " .. tostring(World.playerEffects()))
	local looks = World.cyberCall("MarkerAppearances")
	if type(looks) == "string" and looks ~= "" then
		table.insert(lines, "hologram looks:")
		table.insert(lines, looks)
	end
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
