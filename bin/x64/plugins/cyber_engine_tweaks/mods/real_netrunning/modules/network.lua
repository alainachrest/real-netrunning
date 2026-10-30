-- The network graph: every network V can find, built from lore plus the save's seed.
-- What changes during play (known, owned, looted, heat) lives in Network.state,
-- which init.lua persists per save slot.

local Lore = require("modules/lore")
local Rng = require("modules/rng")

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
		owned = {},   -- addr -> true once breached
		looted = {},  -- "addr:path" -> true once paydata was downloaded
		heat = 0,     -- NetWatch heat, 0-100
		news = {},    -- recent world events, newest last
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
		reveals = def.reveals or {},
		kind = def.kind or "lore",
		device = def.device,
		site = def.site,
		extraFiles = def.files,
		fs = nil, -- built on first use
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
	for _, def in pairs(Network.external) do
		Network.register(def)
	end
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

function Network.addHeat(amount, why)
	local before = Network.state.heat
	Network.state.heat = math.max(0, math.min(100, before + amount))
	if Network.state.heat ~= before then
		emit("netwatch.heat", { heat = Network.state.heat, change = Network.state.heat - before, why = why })
	end
end

function Network.addNews(text)
	table.insert(Network.state.news, text)
	while #Network.state.news > 30 do table.remove(Network.state.news, 1) end
end

---------------------------------------------------------------------------
-- Filesystem (generated, deterministic per save)
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

local function buildFs(net)
	local org = Lore.getOrg(net.org)
	local rng = Rng.new(Network.state.seed or 0, "fs", net.addr)
	local root = newDir()

	if net.kind == "site" and net.site then
		addFile(root, "index.page", { text = net.site.text or net.name })
		return root
	end

	-- users
	local users = {}
	for _, u in ipairs(org.users) do
		if rng:chance(0.7) or #users == 0 then table.insert(users, u) end
	end
	addFile(root, "etc/users", { text = table.concat(users, "\n") })

	-- access log
	local lines = {}
	for i = 1, rng:int(4, 9) do
		local line = rng:pick(Lore.logLines):format(rng:pick(users))
		table.insert(lines, string.format("[%02d:%02d] %s", rng:int(0, 23), rng:int(0, 59), line))
	end
	addFile(root, "logs/access.log", { text = table.concat(lines, "\n") })

	-- mail
	local mails = Lore.mail[org.tone] or Lore.mail.device
	for i = 1, rng:int(1, 3) do
		local body = rng:pick(mails):format(org.name)
		local from, to = rng:pick(users), rng:pick(users)
		addFile(root, string.format("home/%s/mail/%03d.msg", to, rng:int(1, 999)),
			{ text = "From: " .. from .. "\nTo: " .. to .. "\n\n" .. body })
	end

	-- paydata
	if org.paydata[2] > 0 then
		for i = 1, rng:int(1, 2) do
			local value = rng:int(org.paydata[1], org.paydata[2]) * net.tier
			addFile(root, string.format("data/paydata_%04x.dat", rng:int(0, 65535)),
				{ text = "[encrypted corporate data]", paydata = value })
		end
	end

	-- device networks: device file describes the real device
	if net.kind == "device" and net.device then
		addFile(root, "device/info", { text = "Device: " .. (net.device.label or "unknown") ..
			"\nControl: run 'device' while connected to this network." })
	end

	-- extra files from other mods
	if type(net.extraFiles) == "table" then
		for path, file in pairs(net.extraFiles) do addFile(root, path, file) end
	end

	return root
end

function Network.fs(net)
	if net.fs == nil then net.fs = buildFs(net) end
	return net.fs
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
