-- Every electronic device in Night City is on a network.
--
-- When V jacks into a device (or scans the devices around them), the device's
-- network is worked out from how the game itself wires things, then from where
-- the device is:
--
--   ap      wired to an access point: the access point's network, with every
--           device on it
--   system  wired to something else that runs it (a building's security
--           system, a terminal that works the doors, a master switch): that
--           controller's network, with everything it runs
--   device  some devices are on a network of their own: a vending machine, an
--           arcade cabinet, an old computer nobody networked
--   mesh    everything else shares a local mesh with the devices around it:
--           one per block of the city (and per few storeys of a building)
--
-- Some networks are linked to the Net: once found, V can connect from
-- anywhere. Others are isolated: no link out at all, so the only way in is to
-- stand there and jack into one of their devices.
--
-- Everything here is decided from the save's seed and the devices' own IDs,
-- so a device is always on the same network. Networks V has found are saved
-- (state.deviceNets) and come back on load; their device lists grow as V finds
-- more of their devices.

local Network = require("modules/network")
local World = require("modules/world")
local Rng = require("modules/rng")

local DeviceNet = {}

-- How likely each kind of device is to be on a network of its own.
DeviceNet.standalone = {
	vending = 0.5, arcade = 0.6, jukebox = 0.5, computer = 0.4, terminal = 0.3, tv = 0.35, radio = 0.5,
	speaker = 0.3, intercom = 0.3, screen = 0.25, billboard = 0.3, light = 0.1, fan = 0.15, fusebox = 0.4,
	window = 0.3, elevator = 0.6, door = 0.2, camera = 0.15, turret = 0.1, alarm = 0.2, sensor = 0.2, device = 0.35,
}
-- How likely each kind of network is to have no link to the Net.
DeviceNet.isolatedChance = { device = 0.6, mesh = 0.35, system = 0.5, ap = 0.25 }
DeviceNet.cellSize = 32    -- metres: one mesh per block...
DeviceNet.cellHeight = 12  -- ...and per few storeys
DeviceNet.radius = 40      -- how far 'scan nearby' reaches
DeviceNet.maxDevices = 60  -- devices remembered per network

local function seed() return Network.state and Network.state.seed or 0 end
local function hex(text) return string.format("%06x", Rng.hash(text) % 16777216) end

local function isolated(addr, kind)
	return Rng.new(seed(), "isolated", addr):chance(DeviceNet.isolatedChance[kind] or 0.4)
end

function DeviceNet.isStandalone(d)
	return Rng.new(seed(), "standalone", d.hash):chance(DeviceNet.standalone[d.kind] or 0.35)
end

local function cellOf(d)
	if d.pos == nil then return nil end
	return math.floor(d.pos.x / DeviceNet.cellSize) .. "," .. math.floor(d.pos.y / DeviceNet.cellSize) .. "," ..
		math.floor(d.pos.z / DeviceNet.cellHeight)
end

local categories = {
	{ name = "Building security mesh", kinds = { door = 1, camera = 1, turret = 1, alarm = 1, sensor = 1 } },
	{ name = "Storefront network", kinds = { vending = 1, arcade = 1, jukebox = 1, tv = 1, screen = 1, billboard = 1, speaker = 1, radio = 1 } },
	{ name = "Building LAN", kinds = { computer = 1, terminal = 1, intercom = 1, window = 1, elevator = 1 } },
}

local function meshName(devices, addr)
	local best, bestCount = "Street utility mesh", 0
	for _, c in ipairs(categories) do
		local n = 0
		for _, d in ipairs(devices) do if c.kinds[d.kind] then n = n + 1 end end
		if n > bestCount then best, bestCount = c.name, n end
	end
	return best .. " " .. addr:sub(-4):upper()
end

local function strip(d) return { hash = d.hash, kind = d.kind, label = d.label } end

-- Registers (or updates) a device network and remembers it in the save.
-- def: { addr, name, kind, ice }; members: the devices found on it now.
local function save(def, members)
	local s = Network.state
	s.deviceNets = s.deviceNets or {}
	local old = s.deviceNets[def.addr]
	local list, seen = {}, {}
	for i, d in ipairs(members) do
		d.hash = d.hash or (def.addr .. "#" .. i)
		if not seen[d.hash] and #list < DeviceNet.maxDevices then seen[d.hash] = true table.insert(list, d) end
	end
	if old and old.devices then
		for _, d in ipairs(old.devices) do
			if not seen[d.hash] and #list < DeviceNet.maxDevices then
				seen[d.hash] = true
				table.insert(list, { hash = d.hash, kind = d.kind, label = d.label })
			end
		end
	end
	-- the architecture is fixed the first time a network is found
	local ice = old and old.ice or math.max(1, math.min(6, def.ice))
	local name = old and old.name or def.name
	local cut = isolated(def.addr, def.kind)
	local saved = {}
	for _, d in ipairs(list) do table.insert(saved, strip(d)) end
	s.deviceNets[def.addr] = { name = name, kind = def.kind, ice = ice, isolated = cut, devices = saved }
	local net = Network.register({
		addr = def.addr, name = name, org = "unregistered", tier = 1, ice = ice, kind = def.kind,
		devices = def.kind ~= "device" and list or nil, device = def.kind == "device" and list[1] or nil,
		isolated = cut, known = true,
	})
	return net
end

-- Classifies devices once per call: "ap", "system" or "loose".
local function wiring(d, cache)
	local c = cache[d.hash]
	if c then return c end
	local ap = World.accessPointFor(d)
	if ap then c = { kind = "ap", controller = ap }
	else
		local ctrl = World.controllerFor(d)
		if ctrl == nil and #World.devicesOn(d) > 0 then ctrl = d end
		if ctrl then c = { kind = "system", controller = ctrl } else c = { kind = "loose" } end
	end
	cache[d.hash] = c
	return c
end

local function accessPointNet(ap, cache)
	local addr = "ap." .. hex(ap.hash)
	local devices = cache["children:" .. ap.hash] or World.devicesOn(ap)
	cache["children:" .. ap.hash] = devices
	local turrets = 0
	for _, d in ipairs(devices) do if d.kind == "turret" then turrets = turrets + 1 end end
	return save({ addr = addr, name = "Access point network", kind = "ap",
		ice = 2 + math.floor(#devices / 6) + (turrets > 0 and 1 or 0) }, devices), { turrets = turrets }
end

local function systemNet(ctrl, cache)
	local addr = "sys." .. hex(ctrl.hash)
	local devices = cache["children:" .. ctrl.hash] or World.devicesOn(ctrl)
	cache["children:" .. ctrl.hash] = devices
	local members, turrets = { ctrl }, 0
	for _, d in ipairs(devices) do
		table.insert(members, d)
		if d.kind == "turret" then turrets = turrets + 1 end
	end
	local base = ctrl.label:gsub(" %- .*$", "")
	return save({ addr = addr, name = base .. " network", kind = "system",
		ice = (ctrl.kind == "security" and 3 or 1) + math.floor(#members / 8) + (turrets > 0 and 1 or 0) }, members), { turrets = turrets }
end

local function singleNet(device)
	return save({ addr = "local.device." .. device.hash, name = device.label .. " (local)", kind = "device",
		ice = device.ice or 1 }, { device }), {}
end

local function meshNet(device, nearby, cache)
	local cell = cellOf(device)
	local addr = "mesh." .. hex(cell)
	local members = { device }
	local security = 0
	for _, d in ipairs(nearby) do
		if d.hash ~= device.hash and cellOf(d) == cell and not DeviceNet.isStandalone(d) and wiring(d, cache).kind == "loose" then
			table.insert(members, d)
		end
	end
	for _, d in ipairs(members) do
		if d.kind == "camera" or d.kind == "turret" or d.kind == "alarm" or d.kind == "sensor" then security = security + 1 end
	end
	return save({ addr = addr, name = meshName(members, addr), kind = "mesh",
		ice = 1 + math.floor(#members / 8) + (security > 0 and 1 or 0) }, members), {}
end

-- The network a device is on (registered and remembered). Returns net, extra.
-- nearby: devices around it (looked up if not given); cache: shared within one scan.
function DeviceNet.forDevice(device, nearby, cache)
	cache = cache or {}
	local w = wiring(device, cache)
	if w.kind == "ap" then return accessPointNet(w.controller, cache) end
	if w.kind == "system" then return systemNet(w.controller, cache) end
	if device.pos == nil or DeviceNet.isStandalone(device) then return singleNet(device) end
	return meshNet(device, nearby or World.devicesNear(DeviceNet.radius), cache)
end

-- Every device network around V: { { net, count } }, nearest first found.
function DeviceNet.nearby()
	local devices = World.devicesNear(DeviceNet.radius)
	local cache, found, order = {}, {}, {}
	for _, d in ipairs(devices) do
		local net = DeviceNet.forDevice(d, devices, cache)
		if net then
			if found[net.addr] == nil then
				found[net.addr] = { net = net, count = 0 }
				table.insert(order, found[net.addr])
			end
			found[net.addr].count = found[net.addr].count + 1
		end
	end
	return order, #devices
end

-- The floor of its network a device is wired into. Most devices sit on the
-- lobby, but some are wired in deeper, down to the control floor: jacking into
-- one of those gets V straight to that floor, past the locks above it.
function DeviceNet.floorFor(net, device)
	if net == nil or device == nil or net.kind == "device" or device.kind == "access" or device.kind == "security" then return 1 end
	local floors = Network.floors(net)
	local deepest = 1
	for i, f in ipairs(floors) do if f.kind == "control" then deepest = i end end
	if deepest <= 1 then return 1 end
	local rng = Rng.new(seed(), "wired", net.addr, device.hash)
	if rng:chance(0.55) then return 1 end
	return rng:int(2, deepest)
end

-- Short description for the deck.
function DeviceNet.describe(net)
	local n = net.devices and #net.devices or 1
	local what = ({
		ap = "an access point network",
		system = "a network run by a " .. (net.name:gsub(" network$", ""):lower()),
		mesh = "a local mesh",
		device = "a network of its own",
	})[net.kind] or "a network"
	return what, n
end

return DeviceNet
