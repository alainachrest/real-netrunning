-- The network graph: every network V can find, built from lore plus the save's seed.
-- What changes during play (known, owned, looted, heat) lives in Network.state,
-- which init.lua persists per save slot.

local Lore = require("modules/lore")
local Rng = require("modules/rng")
local Core = require("modules/core")
local Junk = require("modules/junk")

local Network = {
	nets = {},     -- addr -> network
	order = {},    -- addrs in registration order
	state = nil,   -- persisted per save, see Network.newState
	bus = nil,     -- set by init
	external = {}, -- networks other mods registered; re-added on every rebuild
}

function Network.newState()
	return {
		schema = 1,
		seed = nil,
		known = {},   -- addr -> true once V can scan it
		owned = {},   -- addr -> true once the core floor is breached
		depth = {},   -- addr -> how many floors are open (1 = only the lobby)
		looted = {},  -- "addr:path" -> true once paydata was downloaded
		heat = 0,     -- NetWatch heat, 0-100
		news = {},    -- recent world events, newest last
		homeFiles = {}, -- documents saved to V's home computers: { name, text }
		market = nil,   -- created by modules/market on first use
		gateways = {},  -- closed network addr -> the access point network that bridges to it
		banks = {},      -- "addr:path" -> { strikes, drained, frozen } for bank account files
		deviceNets = {}, -- device networks V has found: addr -> { name, kind, ice, isolated, devices }
	}
end

local function emit(event, data)
	if Network.bus then Network.bus.emit(event, data) end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local function clampIce(v) return math.max(0, math.min(6, v)) end

-- def: { addr, name, org, tier, ice?, reveals?, hub?, known?, kind?, files?, device?, site? }
function Network.register(def)
	if type(def) ~= "table" or type(def.addr) ~= "string" then return nil end
	local org = Lore.getOrg(def.org)
	local rng = Rng.new(Network.state and Network.state.seed or 0, "ice", def.addr)
	local ice = def.ice
	if ice == nil then
		ice = rng:int(org.ice[1], org.ice[2]) + ((def.tier or 1) - 1)
	end
	local net = {
		addr = def.addr,
		name = def.name or def.addr,
		org = def.org or "unregistered",
		tier = def.tier or 1,
		ice = clampIce(ice),
		hub = def.hub == true,
		reveals = { unpack(def.reveals or {}) }, -- a copy: build() adds to the hub's list
		kind = def.kind or "lore",
		device = def.device,
		devices = def.devices,       -- access point networks: the real devices wired to it
		site = def.site,
		extraFiles = def.files,
		region = Lore.regions[def.region or "nc"] and (def.region or "nc") or "nc",
		uplink = def.uplink,         -- owning this network gives reach into that region
		tone = def.tone,             -- overrides for generated content
		users = def.users,
		paydata = def.paydata,
		tagline = def.tagline,
		about = def.about,
		district = def.district,
		junk = def.junk,
		closed = def.closed == true, -- air-gapped: only reachable through its gateway
		isolated = def.isolated == true, -- a device network with no link to the Net: jack into one of its devices
		lab = def.lab,               -- secret corporate lab: { code, subject }
		fs = nil,     -- built on first use
		floors = nil, -- built on first use
	}
	if Network.nets[net.addr] == nil then table.insert(Network.order, net.addr) end
	Network.nets[net.addr] = net
	if def.known and Network.state then Network.state.known[net.addr] = true end
	return net
end

function Network.unregister(addr)
	Network.nets[addr] = nil
	for i, a in ipairs(Network.order) do
		if a == addr then table.remove(Network.order, i) break end
	end
end

function Network.get(addr) return Network.nets[addr] end

-- Builds the lore world. Call after Network.state is set (per save).
function Network.build()
	Network.nets, Network.order = {}, {}
	for _, def in ipairs(Lore.networks) do
		Network.register(def)
	end
	-- the public subnet is always known
	for _, def in ipairs(Lore.networks) do
		if def.known then Network.state.known[def.addr] = true end
	end
	-- junk networks, the same for every load of this save
	local junk = Lore.junkNetworks(Rng.new(Network.state.seed or 0, "junk"), Network.junkCount)
	local hub, seen = Network.nets["nc.subnet.public"], {}
	for _, def in ipairs(junk) do
		Network.register(def)
		-- the public subnet leads to one junk network in each district
		if hub and not seen[def.district] then
			seen[def.district] = true
			table.insert(hub.reveals, def.addr)
		end
	end
	-- closed networks: registered now so progress is kept, found by jacking in
	local closed = Lore.closedNetworks(Rng.new(Network.state.seed or 0, "closed"), Network.closedJunkCount, Network.labCount)
	Network.closedJunk, Network.closedLabs = {}, {}
	for _, def in ipairs(closed.junk) do Network.register(def) table.insert(Network.closedJunk, def.addr) end
	for _, def in ipairs(closed.labs) do Network.register(def) table.insert(Network.closedLabs, def.addr) end
	Network.state.gateways = Network.state.gateways or {}
	for _, def in pairs(Network.external) do
		Network.register(def)
	end
	-- device networks V has found (modules/devicenet)
	Network.state.deviceNets = Network.state.deviceNets or {}
	for addr, d in pairs(Network.state.deviceNets) do
		local devices = {}
		for _, x in ipairs(d.devices or {}) do table.insert(devices, { hash = x.hash, kind = x.kind, label = x.label }) end
		Network.register({ addr = addr, name = d.name, org = "unregistered", tier = 1, ice = d.ice, kind = d.kind,
			isolated = d.isolated, devices = d.kind ~= "device" and devices or nil, device = d.kind == "device" and devices[1] or nil })
	end
	-- networks owned in older versions reveal routes added since
	for addr in pairs(Network.state.owned) do
		local net = Network.nets[addr]
		if net then for _, r in ipairs(net.reveals) do Network.state.known[r] = true end end
	end
end

Network.junkCount = 48
Network.closedJunkCount = 14
Network.labCount = 10

---------------------------------------------------------------------------
-- Closed networks and their gateways
---------------------------------------------------------------------------

Network.jacked = nil -- runtime: the network of the device V is jacked into right now
Network.jackedFloor = nil -- runtime: the floor of that network the device is wired into

local function unclaimed(list)
	local free = {}
	for _, addr in ipairs(list) do
		if Network.state.gateways[addr] == nil then table.insert(free, addr) end
	end
	return free
end

-- Called when V jacks into a device network. Some of them bridge to a closed
-- network. Big, guarded sites are more likely to hide a corporate lab.
-- opts: { kind = "ap" | "computer", devices = n, turrets = n }
-- Returns the closed network, or nil.
function Network.gatewayFor(gatewayAddr, opts)
	opts = opts or {}
	for addr, gw in pairs(Network.state.gateways) do
		if gw == gatewayAddr then return Network.nets[addr] end
	end
	local rng = Rng.new(Network.state.seed or 0, "gateway", gatewayAddr)
	local chance = opts.kind == "ap" and 0.35 or (opts.kind == "computer" and 0.15 or 0)
	if not rng:chance(chance) then return nil end
	local guarded = (opts.turrets or 0) > 0 or (opts.devices or 0) >= 8
	local wantLab = opts.kind == "ap" and rng:chance(guarded and 0.7 or 0.15)
	local pool = unclaimed(wantLab and Network.closedLabs or Network.closedJunk)
	if #pool == 0 then pool = unclaimed(wantLab and Network.closedJunk or Network.closedLabs) end
	if #pool == 0 then return nil end
	local addr = pool[rng:int(1, #pool)]
	Network.state.gateways[addr] = gatewayAddr
	return Network.nets[addr]
end

-- The floor a gateway has to be hacked down to before the bridge opens:
-- its control floor, or the whole network if it has none.
function Network.bridgeOpen(gatewayAddr)
	local gw = Network.nets[gatewayAddr]
	if gw == nil then return false end
	for i, f in ipairs(Network.floors(gw)) do
		if f.kind == "control" then return Network.isFloorOpen(gatewayAddr, i) end
	end
	return Network.isOwned(gatewayAddr)
end

---------------------------------------------------------------------------
-- Reach: off-world regions need an uplink
---------------------------------------------------------------------------

function Network.hasUplink(region)
	if region == nil or region == "nc" then return true end
	for addr in pairs(Network.state.owned) do
		local net = Network.nets[addr]
		if net and net.uplink == region then return true end
	end
	return false
end

function Network.canReach(net)
	if net.isolated then return Network.jacked == net.addr end
	if net.closed then
		local gw = Network.state.gateways[net.addr]
		return gw ~= nil and Network.jacked == gw and Network.bridgeOpen(gw)
	end
	return Network.hasUplink(net.region)
end

-- The networks that would give an uplink to a region.
function Network.uplinksFor(region)
	local list = {}
	for _, addr in ipairs(Network.order) do
		local net = Network.nets[addr]
		if net.uplink == region then table.insert(list, net) end
	end
	return list
end

function Network.lag(net)
	return Lore.region(net.region).lag
end

-- For other mods: remembered across save loads, unlike runtime-only networks.
function Network.registerExternal(def)
	if type(def) ~= "table" or type(def.addr) ~= "string" then return nil end
	Network.external[def.addr] = def
	if Network.state then return Network.register(def) end
	return true
end

---------------------------------------------------------------------------
-- Knowledge and ownership
---------------------------------------------------------------------------

function Network.isKnown(addr) return Network.state.known[addr] == true end
function Network.isOwned(addr) return Network.state.owned[addr] == true end

function Network.reveal(addr, why)
	if Network.state.known[addr] or Network.nets[addr] == nil then return false end
	Network.state.known[addr] = true
	emit("network.revealed", { addr = addr, why = why })
	return true
end

function Network.markOwned(addr)
	local net = Network.nets[addr]
	if net == nil or Network.state.owned[addr] then return {} end
	Network.state.owned[addr] = true
	Network.state.depth[addr] = #Network.floors(net)
	local revealed = {}
	for _, r in ipairs(net.reveals) do
		if Network.reveal(r, addr) then table.insert(revealed, r) end
	end
	emit("network.breached", { addr = addr, org = net.org, tier = net.tier, ice = net.ice, kind = net.kind })
	return revealed
end

function Network.knownList()
	local list = {}
	for _, addr in ipairs(Network.order) do
		if Network.state.known[addr] then table.insert(list, Network.nets[addr]) end
	end
	return list
end

---------------------------------------------------------------------------
-- Heat and news
---------------------------------------------------------------------------

-- NetWatch heat and the news feed are the CyberScript shared core's, so every
-- mod sees the same: heat is the core's "netwatch" channel, news its feed.

function Network.heat()
	local c = Core.get()
	return c and c.heat.get("netwatch") or 0
end

function Network.addHeat(amount, why)
	local c = Core.get()
	if c == nil then return end
	local before = c.heat.get("netwatch")
	local after = c.heat.add("netwatch", amount, why)
	if after ~= before then
		emit("netwatch.heat", { heat = after, change = after - before, why = why })
	end
end

function Network.addNews(text)
	local c = Core.get()
	if c then c.news.add(text, { source = "realnetrunning" }) end
end

-- The latest n news lines (all if n is nil), oldest first.
function Network.news(n)
	local c = Core.get()
	return c and c.news.texts(n) or {}
end

-- Moves heat, news and the market from saves made before the shared core into
-- it, once per save, and adds Real Netrunning's side of the organisations.
function Network.attachCore()
	local c = Core.get()
	if c == nil or Network.state == nil then return false end
	-- each organisation's security profile (ICE, paydata, users) joins the core's entry
	for id, profile in pairs(Lore.orgs) do
		local def = { id = id }
		for k, v in pairs(profile) do def[k] = v end
		local existing = c.orgs.get(id)
		if existing then def.name, def.kind = existing.name, existing.kind end
		c.orgs.register(def)
	end
	c.heat.setDecay("netwatch", 1) -- NetWatch heat cools by 1 a minute of play
	local s = Network.state
	if not s.movedToCore then
		s.movedToCore = true
		if (s.heat or 0) > c.heat.get("netwatch") then c.heat.set("netwatch", s.heat, "moved from Real Netrunning") end
		if s.news and #s.news > 0 and #c.news.list() == 0 then
			for _, line in ipairs(s.news) do c.news.add(line, { source = "realnetrunning" }) end
		end
		local root = c.state and c.state()
		if s.market and root and root.market == nil then root.market = s.market end
		s.heat, s.news, s.market = 0, {}, nil
	end
	return true
end

---------------------------------------------------------------------------
-- Architecture: every network is a stack of floors (as in Cyberpunk Red).
--
--   lobby     always open, public files
--   ice       an ICE program; break it with 'breach'
--   black     Black ICE; like ice, but failing hurts
--   password  a gate; 'password <code>' (codes hide in earlier files) or 'crack'
--   files     open once reached: users, logs, mail, paydata
--   control   open once reached: the devices this network runs
--   core      root; breaching it owns the whole network
---------------------------------------------------------------------------

local LOCKED = { ice = true, black = true, password = true, core = true }

local passwords = {
	"KIROSHI", "SAKURA", "CHROME", "NEONRAIN", "SILVERHAND", "SAMURAI", "AFTERLIFE",
	"BADLANDS", "PACIFICA", "DATAKRASH", "BARTMOSS", "MIKOSHI", "RELIC", "TOTENTANZ",
}

local function floor(kind, ice, extra)
	local f = { kind = kind, ice = ice or 0 }
	if extra then for k, v in pairs(extra) do f[k] = v end end
	return f
end

local function buildFloors(net)
	local rng = Rng.new(Network.state.seed or 0, "arch", net.addr)
	local floors = { floor("lobby") }

	if net.kind == "site" or net.ice == 0 then
		table.insert(floors, floor("files"))
		table.insert(floors, floor("core", 0))
		return floors
	end

	if net.kind == "device" then
		table.insert(floors, floor("ice", net.ice))
		table.insert(floors, floor("control"))
		table.insert(floors, floor("core", 0))
		return floors
	end

	if net.kind == "computer" then
		table.insert(floors, floor("ice", net.ice))
		table.insert(floors, floor("files"))
		table.insert(floors, floor("core", 0))
		return floors
	end

	if net.kind == "ap" or net.kind == "system" or net.kind == "mesh" then
		table.insert(floors, floor("ice", math.max(1, net.ice - 1)))
		if net.ice >= 3 then table.insert(floors, floor("password", net.ice, { password = rng:pick(passwords) .. rng:int(10, 99) })) end
		table.insert(floors, floor("files"))
		table.insert(floors, floor("control"))
		table.insert(floors, floor("core", net.ice))
		return floors
	end

	-- lore networks: deeper the harder they are
	local middle = 1 + math.floor(net.ice / 2) + (net.tier - 1)
	local hasFiles = false
	for i = 1, middle do
		local roll = rng:next()
		if i == 1 then
			table.insert(floors, floor("ice", math.max(1, net.ice - 1)))
		elseif roll < 0.4 then
			local black = net.ice >= 5 and rng:chance(0.5)
			table.insert(floors, floor(black and "black" or "ice", net.ice))
		elseif roll < 0.65 then
			table.insert(floors, floor("password", net.ice, { password = rng:pick(passwords) .. rng:int(10, 99) }))
		else
			table.insert(floors, floor("files"))
			hasFiles = true
		end
	end
	if not hasFiles then table.insert(floors, floor("files")) end
	table.insert(floors, floor("core", net.ice))
	return floors
end

function Network.floors(net)
	if net.floors == nil then net.floors = buildFloors(net) end
	return net.floors
end

function Network.floorFolder(index, f)
	return string.format("%02d_%s", index, f.kind)
end

-- An unguarded core (no ICE) still has to be reached to take root: it stays
-- shut until V walks in (cyberspace) or breaches it (deck), which is instant.
local function isLocked(f)
	return LOCKED[f.kind] == true
end

function Network.isUnguardedCore(f)
	return f ~= nil and f.kind == "core" and (f.ice or 0) == 0
end

-- Takes root by reaching an unguarded core that's next in line. Returns the
-- revealed routes (a table) when it worked, nil when there's no such core.
function Network.claimCore(addr)
	local index, f = Network.nextLock(addr)
	if index == nil or not Network.isUnguardedCore(f) then return nil end
	return Network.unlockNext(addr)
end

-- How many floors are open. Open floors right after an unlocked one open too.
function Network.depth(addr)
	local net = Network.nets[addr]
	if net == nil then return 0 end
	local floors = Network.floors(net)
	if Network.state.owned[addr] then return #floors end
	local depth = Network.state.depth[addr] or 1
	while depth < #floors and not isLocked(floors[depth + 1]) do depth = depth + 1 end
	return depth
end

-- The next locked floor: index, floor (nil when everything is open).
function Network.nextLock(addr)
	local net = Network.nets[addr]
	if net == nil then return nil end
	local floors = Network.floors(net)
	local depth = Network.depth(addr)
	if depth >= #floors then return nil end
	return depth + 1, floors[depth + 1]
end

-- Opens the next locked floor. Returns revealed routes when that owns the network.
function Network.unlockNext(addr)
	local net = Network.nets[addr]
	if net == nil then return {} end
	local index = Network.nextLock(addr)
	if index == nil then return {} end
	Network.state.depth[addr] = index
	local floors = Network.floors(net)
	emit("network.floor", { addr = addr, floor = index, kind = floors[index].kind, org = net.org })
	if Network.depth(addr) >= #floors then
		return Network.markOwned(addr)
	end
	return {}
end

-- Opens every floor down to index (a device wired in there gives a way in
-- below the locks above it). Never opens the core. Returns true if it opened anything.
function Network.openTo(addr, index)
	local net = Network.nets[addr]
	if net == nil then return false end
	local floors = Network.floors(net)
	index = math.min(index, #floors - 1)
	if index <= Network.depth(addr) then return false end
	Network.state.depth[addr] = index
	emit("network.floor", { addr = addr, floor = index, kind = floors[index].kind, org = net.org, bypass = true })
	return true
end

function Network.isFloorOpen(addr, index)
	return index <= Network.depth(addr)
end

---------------------------------------------------------------------------
-- Filesystem (generated, deterministic per save): one folder per floor
---------------------------------------------------------------------------

local function newDir() return { dir = true, children = {} } end

local function addFile(root, path, file)
	local node = root
	local parts = {}
	for part in path:gmatch("[^/]+") do table.insert(parts, part) end
	for i = 1, #parts - 1 do
		node.children[parts[i]] = node.children[parts[i]] or newDir()
		node = node.children[parts[i]]
	end
	node.children[parts[#parts]] = file
end

-- Like addFile, but never replaces a file already there (adds -2, -3... to the name).
local function addNew(root, path, file)
	local node = root
	for part in path:gmatch("([^/]+)/") do node = node.children and node.children[part] if node == nil then break end end
	local name = path:match("([^/]+)$")
	if node and node.children and node.children[name] then
		local base, ext = name:match("^(.-)(%.[^.]*)$")
		base, ext = base or name, ext or ""
		local n = 2
		while node.children[base .. "-" .. n .. ext] do n = n + 1 end
		path = path:sub(1, #path - #name) .. base .. "-" .. n .. ext
	end
	addFile(root, path, file)
end

-- The people who use a computer: a couple of names besides the admin account.
local function computerUsers(net)
	local rng = Rng.new(Network.state.seed or 0, "pcusers", net.addr)
	local users = { "admin" }
	for _ = 1, rng:int(1, 2) do
		local u = (rng:pick(Lore.firstNames):sub(1, 1) .. "." .. rng:pick(Lore.surnames)):lower()
		if u ~= users[#users] then table.insert(users, u) end
	end
	return users
end

local NO_BANK_TONES = { device = true, vending = true, transit = true }

-- Clutter, home folders and bank accounts (modules/junk), from their own random
-- stream so the rest of a network's files stay exactly as they were.
local function addClutter(net, root, floors, users, org)
	if net.kind == "site" then return end
	local home = net.kind == "computer" and net.addr:find("^home%.") ~= nil -- V's own computers
	local rng = Rng.new(Network.state.seed or 0, "clutter", net.addr)
	-- a computer belongs to whoever sits at it, not to the device network around it
	local tone = net.tone or (net.kind == "computer" and "residential") or org.tone
	local ctx = {
		name = net.name, org = org, tone = tone, tier = net.tier, users = users,
		bank = not home and not NO_BANK_TONES[tone] and net.kind ~= "ap" and net.kind ~= "system"
			and net.kind ~= "mesh" and net.kind ~= "device",
	}
	local homesDone = false
	for i, f in ipairs(floors) do
		local dir = Network.floorFolder(i, f)
		local function add(path, file) addNew(root, dir .. "/" .. path, file) end
		if f.kind == "lobby" then
			if not home then Junk.lobby(rng, add, ctx) end
		elseif f.kind == "ice" or f.kind == "black" then
			Junk.ice(rng, add)
		elseif f.kind == "password" then
			Junk.gate(rng, add)
		elseif f.kind == "control" then
			Junk.control(rng, add)
		elseif f.kind == "core" then
			Junk.core(rng, add)
		elseif f.kind == "files" then
			if not home then Junk.shared(rng, add, ctx) end
			if not homesDone and not home then
				homesDone = true
				for _, u in ipairs(users) do Junk.home(rng, add, ctx, u) end
			end
		end
	end
end

local function buildFs(net)
	local org = Lore.getOrg(net.org)
	local rng = Rng.new(Network.state.seed or 0, "fs", net.addr)
	local root = newDir()
	local floors = Network.floors(net)

	local users = {}
	for _, u in ipairs(net.users or (net.kind == "computer" and computerUsers(net)) or org.users) do
		if rng:chance(0.7) or #users == 0 then table.insert(users, u) end
	end

	-- password hints go into the files floor just before each gate, if there is one
	local hints = {}
	for i, f in ipairs(floors) do
		if f.kind == "password" then
			for j = i - 1, 2, -1 do
				if floors[j].kind == "files" then
					hints[j] = hints[j] or {}
					table.insert(hints[j], { floor = i, code = f.password })
					break
				end
			end
		end
	end

	local paydataRange = net.paydata or org.paydata
	local paydataPlaced = false
	for i, f in ipairs(floors) do
		local dir = Network.floorFolder(i, f)

		if f.kind == "lobby" then
			if net.kind == "site" and net.site then
				addFile(root, dir .. "/index.page", { text = net.site.text or net.name })
			else
				addFile(root, dir .. "/welcome.txt", { text = net.name .. "\nOperator: " .. (net.junk and "Private" or org.name) ..
					"\nAddress: " .. net.addr .. "\nArchitecture: " .. #floors .. " floors" ..
					"\n\nUnauthorised access is a violation of NetWatch regulations." })
			end
			if net.kind == "device" and net.device then
				addFile(root, dir .. "/device.txt", { text = "Device: " .. (net.device.label or "unknown") })
			end

		elseif f.kind == "ice" or f.kind == "black" then
			addFile(root, dir .. "/ice.daemon", { text = (f.kind == "black" and "BLACK ICE. Lethal countermeasures active." or
				"ICE program, rating " .. f.ice .. ".") .. "\nStatus: broken." })

		elseif f.kind == "password" then
			addFile(root, dir .. "/gate.txt", { text = "Password gate. Status: open." })

		elseif f.kind == "files" then
			addFile(root, dir .. "/etc/users", { text = table.concat(users, "\n") })
			local lines = {}
			for _ = 1, rng:int(4, 9) do
				local line = rng:pick(Lore.logLines):format(rng:pick(users))
				table.insert(lines, string.format("[%02d:%02d] %s", rng:int(0, 23), rng:int(0, 59), line))
			end
			addFile(root, dir .. "/logs/access.log", { text = table.concat(lines, "\n") })
			local mails = Lore.mail[net.tone or org.tone] or Lore.mail.device
			for _ = 1, rng:int(1, 3) do
				local from, to = rng:pick(users), rng:pick(users)
				addFile(root, string.format("%s/home/%s/mail/%03d.msg", dir, to, rng:int(1, 999)),
					{ text = "From: " .. from .. "\nTo: " .. to .. "\n\n" .. rng:pick(mails):format(org.name) })
			end
			for _, hint in ipairs(hints[i] or {}) do
				local who = rng:pick(users)
				addFile(root, string.format("%s/home/%s/mail/%03d.msg", dir, who, rng:int(1, 999)),
					{ text = "From: secops\nTo: " .. who .. "\n\nTemporary access code for floor " .. hint.floor ..
						": " .. hint.code .. "\nDelete this message after reading." })
			end
			if paydataRange[2] > 0 and (not paydataPlaced or rng:chance(0.5)) then
				local value = rng:int(paydataRange[1], paydataRange[2]) * net.tier
				addFile(root, string.format("%s/data/paydata_%04x.dat", dir, rng:int(0, 65535)),
					{ text = "[encrypted corporate data]", paydata = value })
				paydataPlaced = true
			end

		elseif f.kind == "control" then
			local lines = {}
			for n, d in ipairs(net.devices or {}) do table.insert(lines, n .. ". " .. d.label) end
			if net.device then table.insert(lines, "1. " .. (net.device.label or "Device")) end
			addFile(root, dir .. "/devices.txt", { text = #lines > 0 and table.concat(lines, "\n") or "No devices online." })

		elseif f.kind == "core" then
			addFile(root, dir .. "/root.key", { text = "ROOT ACCESS GRANTED." })
			if paydataRange[2] > 0 then
				local value = rng:int(paydataRange[1], paydataRange[2]) * net.tier * 2
				addFile(root, string.format("%s/vault/paydata_%04x.dat", dir, rng:int(0, 65535)),
					{ text = "[encrypted core data]", paydata = value })
			end
			if type(net.extraFiles) == "table" then
				for path, file in pairs(net.extraFiles) do addFile(root, dir .. "/" .. path, file) end
			end
		end
	end

	addClutter(net, root, floors, users, org)
	return root
end

function Network.fs(net)
	if net.fs == nil then net.fs = buildFs(net) end
	return net.fs
end

-- Which floor a path is on (1 for the root itself).
function Network.floorOfPath(net, path)
	local first = tostring(path):match("^/?(%d%d)_")
	return first and tonumber(first) or 1
end

function Network.canAccess(net, path)
	return Network.isFloorOpen(net.addr, Network.floorOfPath(net, path))
end

-- Resolves a path ("/a/b", "b", "..") against cwd; returns node, normalisedPath.
function Network.resolve(net, cwd, path)
	local parts = {}
	local full = (path and path:sub(1, 1) == "/") and path or ((cwd or "/") .. "/" .. (path or ""))
	for part in full:gmatch("[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	local node = Network.fs(net)
	for _, part in ipairs(parts) do
		if not node.dir or node.children[part] == nil then return nil, nil end
		node = node.children[part]
	end
	return node, "/" .. table.concat(parts, "/")
end

return Network
