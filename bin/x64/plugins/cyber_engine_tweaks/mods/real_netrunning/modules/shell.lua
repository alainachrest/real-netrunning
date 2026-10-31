-- The cyberdeck shell: parses commands, runs breaches over time, tracks trace.

local Network = require("modules/network")
local Lore = require("modules/lore")
local World = require("modules/world")
local Market = require("modules/market")
local Rng = require("modules/rng")
local NetWatch = require("modules/netwatch")

local Shell = {
	lines = {},        -- { text, kind } kind = "out" | "cmd" | "ok" | "warn" | "err"
	maxLines = 400,
	history = {},
	connected = nil,   -- addr
	cwd = "/",
	trace = 0,         -- 0-100 for the current connection
	job = nil,         -- running breach { addr, elapsed, duration, traceTotal, traced }
	bus = nil,
	heatDecayTimer = 0,
	onLine = nil,      -- function(text, kind) called for every new line (native deck)
	onClear = nil,     -- function() called when the screen is cleared
}

local commands = {}
local helpOrder = {}

local function out(text, kind)
	for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
		table.insert(Shell.lines, { text = line, kind = kind or "out" })
		if Shell.onLine then pcall(Shell.onLine, line, kind or "out") end
	end
	while #Shell.lines > Shell.maxLines do table.remove(Shell.lines, 1) end
end
Shell.print = out

local function emit(event, data)
	if Shell.bus then Shell.bus.emit(event, data) end
end

local function current()
	return Shell.connected and Network.get(Shell.connected) or nil
end

local function def(name, usage, help, fn)
	commands[name] = { usage = usage, help = help, fn = fn }
	table.insert(helpOrder, name)
end

---------------------------------------------------------------------------
-- Trace
---------------------------------------------------------------------------

local function disconnect(reason)
	if not Shell.connected then return end
	emit("hack.disconnected", { addr = Shell.connected, reason = reason })
	NetWatch.onDisconnect()
	Shell.connected, Shell.cwd, Shell.trace, Shell.job = nil, "/", 0, nil
end

local function addTrace(amount)
	local net = current()
	if net == nil then return end
	Shell.trace = math.min(100, Shell.trace + amount)
	if Shell.trace >= 100 then
		out("TRACE COMPLETE. NetWatch has your signature. Connection severed.", "err")
		local heat = 10 + net.ice * 5
		Network.addHeat(heat, "trace on " .. net.addr)
		World.warn("NetWatch trace complete")
		emit("netwatch.traced", { addr = net.addr, org = net.org, heat = heat })
		disconnect("traced")
	end
end

Shell.addTrace = addTrace

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

def("help", "help", "List commands.", function()
	for _, name in ipairs(helpOrder) do
		local c = commands[name]
		out(string.format("  %-22s %s", c.usage, c.help))
	end
end)

def("clear", "clear", "Clear the screen.", function()
	Shell.lines = {}
	if Shell.onClear then pcall(Shell.onClear) end
end)

local function floorLabel(f)
	if f.kind == "ice" then return "ICE " .. f.ice end
	if f.kind == "black" then return "BLACK ICE " .. f.ice end
	if f.kind == "password" then return "PASSWORD GATE" end
	if f.kind == "core" then return f.ice > 0 and ("CORE (ICE " .. f.ice .. ")") or "CORE" end
	return f.kind:upper()
end

local function progress(net)
	local floors = Network.floors(net)
	if Network.isOwned(net.addr) then return "ROOT" end
	return "F" .. Network.depth(net.addr) .. "/" .. #floors
end

def("status", "status", "Deck, connection, trace and NetWatch heat.", function()
	out("Deck power: " .. World.deckPower() .. "   NetWatch heat: " .. Network.state.heat .. "/100 (" .. NetWatch.tierName() .. ")")
	if NetWatch.lockout > 0 then out("Deck locked out for " .. math.ceil(NetWatch.lockout) .. "s.", "err") end
	if NetWatch.agent then out("Agent in the network: " .. NetWatch.agent.name .. " (level " .. NetWatch.agent.level .. ")", "err") end
	if Network.jacked then out("Jacked into: " .. Network.jacked) end
	local net = current()
	if net then
		out("Connected: " .. net.addr .. " (" .. net.name .. ")")
		out("Access: " .. progress(net) .. "   Trace: " .. math.floor(Shell.trace) .. "%")
	else
		out("Not connected.")
	end
end)

def("scan", "scan [region or word]", "List networks you know. Filter by region (nc, nusa, pacific, eu, orbit), 'local' for small nets, or any word.", function(args)
	local filter = args[1] and args[1]:lower()
	local shown = 0
	for _, region in ipairs(Lore.regionOrder) do
		local rows = {}
		for _, net in ipairs(Network.knownList()) do
			if net.region == region then
				local org = Lore.getOrg(net.org)
				local match = filter == nil or filter == region
					or (filter == "local" and net.junk ~= nil)
					or (filter == "corp" and net.junk == nil)
					or net.addr:lower():find(filter, 1, true) or net.name:lower():find(filter, 1, true)
					or org.name:lower():find(filter, 1, true)
				if match then table.insert(rows, net) end
			end
		end
		if #rows > 0 then
			local reach = Network.hasUplink(region)
			local r = Lore.region(region)
			if region == "closed" then
				out("CLOSED NETWORKS  (jack into the device that bridges to each one)", "warn")
			else
				out(r.name:upper() .. (region == "nc" and "" or (reach and ("  (uplink ok, lag x" .. r.lag .. ")") or "  (NO UPLINK)")),
					reach and "warn" or "err")
			end
			for _, net in ipairs(rows) do
				if region == "closed" then reach = Network.canReach(net) end
				local org = Lore.getOrg(net.org)
				local label = net.name .. (net.junk and "" or (" [" .. org.name .. "]"))
				if net.uplink and not Network.isOwned(net.addr) then label = label .. "  <- uplink to " .. Lore.region(net.uplink).name end
				out(string.format("  %-34s ICE %d  %-6s %s", net.addr, net.ice, progress(net), label),
					Network.isOwned(net.addr) and "ok" or (reach and "out" or "err"))
				shown = shown + 1
			end
		end
	end
	if shown == 0 then out(filter and "Nothing matches." or "No networks in range.") end
end)

-- Cyberspace (modules/cyberspace.lua). Set by init, so the shell doesn't need to load it.
Shell.cyber = nil

def("jackin", "jackin", "Jack in to the network you're connected to and walk through it in cyberspace.", function()
	if Shell.cyber == nil then out("Cyberspace isn't available.", "err") return end
	local ok, msg = Shell.cyber.jackIn()
	out(msg, ok and "ok" or "err")
	if ok then out("Walk up to things and press your 'Cyberspace: use' key. 'jackout' or the exit node to leave.") end
end)

def("jackout", "jackout", "Leave cyberspace.", function()
	if Shell.cyber == nil then out("Cyberspace isn't available.", "err") return end
	local ok, msg = Shell.cyber.jackOut("user")
	if not ok then out(msg, "err") end
end)

def("cyber", "cyber [scan|debug]", "Where you are in cyberspace. 'cyber scan' maps the rooms around you (costs trace on networks you don't own). 'cyber debug' shows the details (also after a failed jack-in).", function(args)
	if Shell.cyber == nil then out("Cyberspace isn't available.", "err") return end
	if args[1] == "scan" then
		local ok, text = Shell.cyber.scan()
		out(text, ok and "out" or "err")
		return
	end
	if args[1] == "debug" then
		out(Shell.cyber.active and Shell.cyber.debug() or ("Last jack-in:\n" .. tostring(Shell.cyber.lastDebug or "none yet")))
		return
	end
	out(Shell.cyber.status())
end)

def("uplinks", "uplinks", "Which regions beyond Night City your deck can reach.", function()
	for _, region in ipairs(Lore.regionOrder) do
		if region ~= "nc" and region ~= "closed" then
			local r = Lore.region(region)
			if Network.hasUplink(region) then
				out(string.format("  %-18s ONLINE   lag x%.2f", r.name, r.lag), "ok")
			else
				local via = {}
				for _, net in ipairs(Network.uplinksFor(region)) do
					table.insert(via, Network.isKnown(net.addr) and net.addr or "an unknown relay")
				end
				out(string.format("  %-18s OFFLINE  root %s to reach it", r.name, table.concat(via, " or ")), "err")
			end
		end
	end
	out("Off-world breaches raise trace faster: the signal takes longer to get there and back.")
end)

def("connect", "connect <address>", "Connect to a network from scan.", function(args)
	local addr = args[1]
	if not addr then out("Usage: connect <address>", "err") return end
	local net = Network.get(addr)
	if net == nil or not Network.isKnown(addr) then out("No route to " .. addr .. ". Try scan.", "err") return end
	if net.closed then
		local gw = Network.state.gateways[addr]
		if Network.jacked == nil or Network.jacked ~= gw then
			out(net.name .. " is a closed network. You can only reach it by jacking into the device that bridges to it.", "err")
			return
		end
		if not Network.bridgeOpen(gw) then
			out("The bridge is still locked. Hack " .. gw .. " down to its control floor first.", "err")
			return
		end
		local distance = World.distanceTo(Network.jackedDevice)
		if distance and distance > 15 then
			out("You've moved too far from the device. Go back and jack in again.", "err")
			Network.jacked, Network.jackedDevice = nil, nil
			return
		end
	elseif not Network.canReach(net) then
		out("No uplink to " .. Lore.region(net.region).name .. ". Get root on a backbone that routes there. Type 'uplinks'.", "err")
		return
	end
	-- moving to any network other than the jacked device (or what it bridges to) unplugs you
	if Network.jacked and addr ~= Network.jacked and Network.state.gateways[addr] ~= Network.jacked then
		Network.jacked, Network.jackedDevice = nil, nil
	end
	if Shell.connected then disconnect("switched") end
	local floors = Network.floors(net)
	Shell.connected, Shell.trace = addr, 0
	Shell.cwd = "/" .. Network.floorFolder(1, floors[1])
	out("Connected to " .. net.name .. ". " .. #floors .. " floors." ..
		(Network.lag(net) ~= 1 and (" Routing via " .. Lore.region(net.region).name .. ", lag x" .. Network.lag(net) .. ".") or ""), "ok")
	-- networks with no locks at all open up straight away
	if Network.nextLock(addr) == nil and not Network.isOwned(addr) then
		Network.markOwned(addr)
	end
	if Network.isOwned(addr) then
		out("Root access.", "ok")
	else
		local index, f = Network.nextLock(addr)
		out("Floor " .. index .. " is locked: " .. floorLabel(f) .. ". Type 'map' to see the architecture.", "warn")
	end
	emit("hack.connected", { addr = addr, org = net.org })
end)

def("disconnect", "disconnect", "Drop the current connection.", function()
	if not Shell.connected then out("Not connected.") return end
	out("Disconnected from " .. Shell.connected .. ".")
	disconnect("user")
	Network.jacked, Network.jackedDevice = nil, nil
end)

def("map", "map", "Show the network's floors and what blocks the way.", function()
	local net = current()
	if net == nil then out("Connect to a network first.", "err") return end
	local depth = Network.depth(net.addr)
	for i, f in ipairs(Network.floors(net)) do
		local open = i <= depth
		local here = Shell.cwd:find("^/" .. Network.floorFolder(i, f)) and "  <- you" or ""
		out(string.format("  %s %-16s %s%s", open and "[OPEN]  " or "[LOCKED]", Network.floorFolder(i, f), open and "" or floorLabel(f), here),
			open and "ok" or (f.kind == "black" and "err" or "warn"))
	end
end)

local function startJob(kind, net, index, f, duration, traceTotal)
	local power = World.deckPower()
	Shell.job = {
		kind = kind, addr = net.addr, floor = index, elapsed = 0, duration = duration, power = power,
		traceTotal = traceTotal * Network.lag(net), traced = 0,
	}
	return power
end

def("breach", "breach", "Break the ICE on the next locked floor.", function()
	local net = current()
	if net == nil then out("Connect to a network first.", "err") return end
	if NetWatch.lockout > 0 then out("Your deck is still rebooting (" .. math.ceil(NetWatch.lockout) .. "s).", "err") return end
	if Shell.job then out("A breach is already running.", "err") return end
	local index, f = Network.nextLock(net.addr)
	if index == nil then out("You already have root here.") return end
	if f.kind == "password" then
		out("Floor " .. index .. " is a password gate. Use 'password <code>' or 'crack'.", "warn")
		return
	end
	local power = World.deckPower()
	local duration = 2 + f.ice
	startJob("breach", net, index, f, duration, math.max(5, 12 + f.ice * 8 - power * 3))
	out(string.format("Breaching %s on floor %d with deck power %d... (%ds)", floorLabel(f), index, power, duration),
		f.kind == "black" and "err" or "warn")
end)

def("password", "password <code>", "Open a password gate.", function(args)
	local net = current()
	if net == nil then out("Connect to a network first.", "err") return end
	local index, f = Network.nextLock(net.addr)
	if index == nil or f.kind ~= "password" then out("There's no password gate ahead.") return end
	if not args[1] then out("Usage: password <code>", "err") return end
	if args[1]:upper() == tostring(f.password):upper() then
		Network.unlockNext(net.addr)
		out("Access code accepted. Floor " .. index .. " open.", "ok")
		emit("hack.breach", { addr = net.addr, org = net.org, success = true, ice = f.ice, tier = net.tier, floor = index })
	else
		out("Access code rejected.", "err")
		addTrace(10)
	end
end)

def("crack", "crack", "Brute-force the password gate ahead (slow, raises trace).", function()
	local net = current()
	if net == nil then out("Connect to a network first.", "err") return end
	if NetWatch.lockout > 0 then out("Your deck is still rebooting (" .. math.ceil(NetWatch.lockout) .. "s).", "err") return end
	if Shell.job then out("A job is already running.", "err") return end
	local index, f = Network.nextLock(net.addr)
	if index == nil or f.kind ~= "password" then out("There's no password gate ahead.") return end
	local duration = 4 + f.ice
	local power = startJob("crack", net, index, f, duration, 20 + f.ice * 6)
	out(string.format("Cracking the gate on floor %d with deck power %d... (%ds)", index, power, duration), "warn")
end)

local function needConnection()
	local net = current()
	if net == nil then out("Connect to a network first.", "err") return nil end
	return net
end

local function checkFloor(net, path)
	if Network.canAccess(net, path) then return true end
	out("Locked. Floor " .. Network.floorOfPath(net, path) .. " isn't open yet. Type 'map'.", "err")
	return false
end

def("ls", "ls [path]", "List files.", function(args)
	local net = needConnection() if not net then return end
	local node, path = Network.resolve(net, Shell.cwd, args[1])
	if node == nil then out("No such path.", "err") return end
	if path ~= "/" and not checkFloor(net, path) then return end
	if not node.dir then out(path) return end
	local names = {}
	for name, child in pairs(node.children) do
		local label = child.dir and (name .. "/") or name
		if path == "/" and not Network.canAccess(net, "/" .. name) then label = label .. "  (locked)" end
		table.insert(names, label)
	end
	table.sort(names)
	if #names == 0 then out("(empty)") end
	for _, n in ipairs(names) do out("  " .. n, n:find("locked") and "warn" or "out") end
end)

def("cd", "cd <path>", "Change directory.", function(args)
	local net = needConnection() if not net then return end
	local node, path = Network.resolve(net, Shell.cwd, args[1] or "/")
	if node == nil or not node.dir then out("No such directory.", "err") return end
	if path ~= "/" and not checkFloor(net, path) then return end
	Shell.cwd = path
end)

def("cat", "cat <file>", "Read a file.", function(args)
	local net = needConnection() if not net then return end
	if not args[1] then out("Usage: cat <file>", "err") return end
	local node, path = Network.resolve(net, Shell.cwd, args[1])
	if node == nil or node.dir then out("No such file.", "err") return end
	if not checkFloor(net, path) then return end
	out(node.text or "")
end)

def("download", "download <file>", "Download paydata to sell.", function(args)
	local net = needConnection() if not net then return end
	if not args[1] then out("Usage: download <file>", "err") return end
	local node, path = Network.resolve(net, Shell.cwd, args[1])
	if node == nil or node.dir then out("No such file.", "err") return end
	if not checkFloor(net, path) then return end
	if not node.paydata then out("Nothing worth selling in that file.") return end
	local key = net.addr .. ":" .. path
	if Network.state.looted[key] then out("Already downloaded.") return end
	Network.state.looted[key] = true
	World.giveMoney(node.paydata)
	out("Paydata fenced through your contacts: +" .. node.paydata .. " eddies.", "ok")
	World.notify("Paydata sold: " .. node.paydata .. " eddies")
	local event = { addr = net.addr, org = net.org, value = node.paydata, tier = net.tier }
	emit("hack.download", event)
	local tip = Market.onDownload(event)
	if tip then out(tip, "warn") end
	if node.research then
		out("Experimental research. " .. Lore.getOrg(net.org).name .. " will know something walked out of PROJECT " .. node.research.code .. ".", "warn")
		Network.addHeat(5, "stole research from " .. net.addr)
	end
	if net.ice >= 3 then addTrace(10) end
end)

def("leak", "leak <file>", "Leak paydata to the press (crashes the owner's stock).", function(args)
	local net = needConnection() if not net then return end
	if not args[1] then out("Usage: leak <file>", "err") return end
	local node, path = Network.resolve(net, Shell.cwd, args[1])
	if node == nil or node.dir then out("No such file.", "err") return end
	if not checkFloor(net, path) then return end
	if not node.paydata then out("Nothing in that file the press would care about.") return end
	local key = net.addr .. ":" .. path
	if Network.state.looted[key] then out("That data is already out.") return end
	local company = Market.onLeak(net.org, node.research and 4 or net.tier)
	if company == nil then out("No listed company would be hurt by this leak.") return end
	if node.research then
		Network.addNews("Leaked files expose " .. company.name .. "'s secret project " .. node.research.code .. ": " .. node.research.subject)
		Network.addHeat(5, "exposed PROJECT " .. node.research.code)
	end
	Network.state.looted[key] = true
	local fee = math.floor(node.paydata / 2)
	World.giveMoney(fee)
	out("Leaked to the press. " .. company.name .. " (" .. company.ticker .. ") will take a hit. Journalist paid " .. fee .. " eddies.", "ok")
	Network.addHeat(5, "leak from " .. net.addr)
	emit("hack.leak", { addr = net.addr, org = net.org, ticker = company.ticker, tier = net.tier })
	addTrace(10)
end)

local function money(n) return string.format("%.2f", n) end

def("market", "market", "Night City stock prices.", function()
	for _, c in ipairs(Market.companies) do
		local change = Market.change(c.ticker) * 100
		out(string.format("  %-4s %-22s %10s  %+6.1f%%", c.ticker, c.name, money(Market.price(c.ticker)), change),
			change > 0.05 and "ok" or (change < -0.05 and "err" or "out"))
	end
	out("Trade with: buy <ticker> <qty>, sell <ticker> <qty|all>. 1% fee per trade.")
end)

def("buy", "buy <ticker> <qty>", "Buy shares.", function(args)
	local ok, msg = Market.buy(args[1] or "", args[2] or "")
	out(msg, ok and "ok" or "err")
end)

def("sell", "sell <ticker> <qty|all>", "Sell shares.", function(args)
	local ok, msg = Market.sell(args[1] or "", args[2] or "")
	out(msg, ok and "ok" or "err")
end)

def("portfolio", "portfolio", "Your shares and their value.", function()
	local rows, value = Market.portfolio()
	if #rows == 0 then out("You don't own any shares.") return end
	for _, r in ipairs(rows) do
		local gain = (r.price - r.cost) * r.qty
		out(string.format("  %-4s x%-6d now %10s   paid %10s   %+.0f", r.ticker, r.qty, money(r.price), money(r.cost), gain),
			gain >= 0 and "ok" or "err")
	end
	out("Total value: " .. math.floor(value) .. " eddies")
end)

-- The floor index of a network's control floor, or nil.
local function controlFloor(net)
	for i, f in ipairs(Network.floors(net)) do
		if f.kind == "control" then return i end
	end
	return nil
end

-- Some devices bridge to a closed network that can't be reached from outside.
local function bridgeCheck(addr, opts)
	local closed = Network.gatewayFor(addr, opts)
	if closed == nil then return end
	local first = Network.reveal(closed.addr, addr)
	out((first and "Something else is wired in here: a closed network, " or "This device bridges to ") ..
		closed.name .. " (" .. closed.addr .. ").", closed.lab and "err" or "warn")
	if Network.bridgeOpen(addr) then
		out("The bridge is open. 'connect " .. closed.addr .. "' while you're jacked in here.", "ok")
	else
		out("Hack this network down to its control floor to open the bridge, then 'connect " .. closed.addr .. "'.")
	end
	if first then
		emit("network.closed_found", { addr = closed.addr, gateway = addr, lab = closed.lab ~= nil, org = closed.org })
		if closed.lab then World.warn("Closed corporate network found") end
	end
end

def("jack", "jack", "Jack into the device you're looking at.", function()
	local device, err = World.lookAtDevice()
	if device == nil then out(err, "err") return end

	-- devices wired to an access point join its network
	local ap = World.accessPointFor(device)
	if ap then
		local devices = World.devicesOn(ap)
		local turrets = 0
		for _, d in ipairs(devices) do if d.kind == "turret" then turrets = turrets + 1 end end
		local addr = "ap." .. string.format("%06x", Rng.hash(ap.hash) % 16777216)
		Network.register({
			addr = addr, name = "Access point network", org = "unregistered", tier = 1, kind = "ap",
			ice = math.min(6, 2 + math.floor(#devices / 6) + (turrets > 0 and 1 or 0)),
			devices = devices, known = true,
		})
		Network.jacked, Network.jackedDevice = addr, ap
		commands.connect.fn({ addr })
		out("Jacked into an access point network with " .. #devices .. " devices. Reach its control floor to use 'devices'.")
		emit("hack.jack", { addr = addr, devices = #devices })
		bridgeCheck(addr, { kind = "ap", devices = #devices, turrets = turrets })
		return
	end

	local addr = "local.device." .. device.hash
	Network.register({
		addr = addr, name = device.label .. " (local)", org = "unregistered", tier = 1,
		ice = device.ice, kind = "device", device = device, known = true,
	})
	Network.jacked, Network.jackedDevice = addr, device
	commands.connect.fn({ addr })
	out("Jacked into " .. device.label:lower() .. ". Controls: " ..
		table.concat(World.deviceActionsFor(device.kind), ", "))
	if device.kind == "computer" or device.kind == "terminal" then
		bridgeCheck(addr, { kind = "computer" })
	end
end)

local function controlAccess(net)
	local index = controlFloor(net)
	if index == nil then out("This network doesn't control any devices.", "err") return false end
	if not Network.isFloorOpen(net.addr, index) then
		out("The control floor (" .. index .. ") isn't open yet. Type 'map'.", "err")
		return false
	end
	return true
end

def("devices", "devices", "List the devices this network controls.", function()
	local net = needConnection() if not net then return end
	if not controlAccess(net) then return end
	local list = net.devices or (net.device and { net.device }) or {}
	if #list == 0 then out("No devices online.") return end
	for n, d in ipairs(list) do
		local actions = World.deviceActionsFor(d.kind)
		out(string.format("  %2d. %-34s %s", n, d.label, #actions > 0 and table.concat(actions, ", ") or "(no direct controls)"))
	end
	out("Use: device <number> <action>")
end)

def("device", "device [number] <action>", "Control a device on this network.", function(args)
	local net = needConnection() if not net then return end
	if not controlAccess(net) then return end
	local target, action
	if net.devices then
		target = net.devices[tonumber(args[1] or "")]
		action = args[2]
		if target == nil then out("Usage: device <number> <action>. Type 'devices' for the list.", "err") return end
	else
		target, action = net.device, args[1]
		if target == nil then out("This network has no device to control.", "err") return end
	end
	local actions = World.deviceActionsFor(target.kind)
	if not action then
		out(#actions > 0 and ("Actions: " .. table.concat(actions, ", ")) or "No direct controls on this device.")
		return
	end
	local ok, msg = World.deviceAction(target, action)
	out(msg, ok and "ok" or "err")
	if ok then
		emit("device.action", { kind = target.kind, action = action, addr = net.addr })
	end
end)

def("fight", "fight", "Fight the NetWatch agent in this network.", function()
	local ok, msg = NetWatch.fight()
	out(msg, ok and "ok" or "err")
end)

def("scrub", "scrub", "Wipe your traces from a network you own (lowers heat, once each).", function()
	local net = needConnection() if not net then return end
	local ok, msg = NetWatch.scrub(net.addr)
	out(msg, ok and "ok" or "err")
end)

def("netwatch", "netwatch [world on|off]", "Your NetWatch threat level; turn world attacks on or off.", function(args)
	if args[1] == "world" and (args[2] == "on" or args[2] == "off") then
		NetWatch.setWorldEffects(args[2] == "on")
		out("NetWatch attacks in the world are now " .. args[2] .. ".", "ok")
		return
	end
	local heat = Network.state.heat
	out("Threat level: " .. NetWatch.tierName() .. " (heat " .. heat .. "/100)", NetWatch.tier() >= 2 and "err" or "ok")
	out("  WATCHED at 25: agents sometimes trace into networks you're in.")
	out("  HUNTED at 50: agents come often, and NetWatch netrunners hack you in the street.")
	out("  BURNED at 75: NetWatch also tips off the NCPD.")
	out("Agents derezzed: " .. NetWatch.defeated() .. ".   World attacks: " .. (NetWatch.worldEffects() and "on" or "off") .. ".")
	out("Heat cools by 1 a minute. 'scrub' on a network you own lowers it faster.")
end)

def("news", "news", "Recent events across Night City's nets.", function()
	local news = Network.state.news
	if #news == 0 then out("Nothing new.") return end
	for i = math.max(1, #news - 9), #news do out("  " .. news[i]) end
end)

---------------------------------------------------------------------------
-- Input and update
---------------------------------------------------------------------------

function Shell.run(line)
	line = (line or ""):match("^%s*(.-)%s*$")
	if line == "" then return end
	table.insert(Shell.history, line)
	out((Shell.connected and (Shell.connected .. ":" .. Shell.cwd) or "deck") .. "> " .. line, "cmd")
	local args = {}
	for word in line:gmatch("%S+") do table.insert(args, word) end
	local name = table.remove(args, 1):lower()
	local cmd = commands[name]
	if cmd == nil then out("Unknown command '" .. name .. "'. Type help.", "err") return end
	local ok, err = pcall(cmd.fn, args)
	if not ok then out("Command failed: " .. tostring(err), "err") end
end

function Shell.prompt()
	return (Shell.connected and (Shell.connected .. ":" .. Shell.cwd) or "deck") .. ">"
end

local function finishJob(job)
	local net = Network.get(job.addr)
	if net == nil then return end
	local f = Network.floors(net)[job.floor]
	local index = Network.nextLock(net.addr)
	if f == nil or index ~= job.floor then return end
	local chance = math.max(0.05, math.min(0.95, 0.55 + 0.15 * (job.power - f.ice)))
	if job.kind == "crack" then chance = math.max(0.2, chance) end
	local roll = Shell.random and Shell.random() or math.random()
	local event = { addr = net.addr, org = net.org, ice = f.ice, tier = net.tier, floor = job.floor }
	if roll < chance then
		local bridgeBefore = Network.bridgeOpen(net.addr)
		local revealed = Network.unlockNext(net.addr)
		event.success = true
		if Network.isOwned(net.addr) then
			out("Core broken. Root access on " .. net.name .. ".", "ok")
			World.notify("Breached " .. net.name)
		else
			local nextIndex, nextFloor = Network.nextLock(net.addr)
			out((job.kind == "crack" and "Gate cracked." or "ICE broken.") .. " Open to floor " .. Network.depth(net.addr) ..
				(nextIndex and (". Next: floor " .. nextIndex .. ", " .. floorLabel(nextFloor)) or "") .. ".", "ok")
		end
		for _, r in ipairs(revealed) do out("New route found: " .. r, "ok") end
		if not bridgeBefore and Network.bridgeOpen(net.addr) then
			for closedAddr, gw in pairs(Network.state.gateways) do
				if gw == net.addr and Network.isKnown(closedAddr) then
					out("Bridge open. 'connect " .. closedAddr .. "' to reach the closed network.", "ok")
				end
			end
		end
		emit("hack.breach", event)
	else
		event.success = false
		out(job.kind == "crack" and "Crack failed. The gate locked you out." or "Breach failed. The ICE adapted.", "err")
		emit("hack.breach", event)
		if f.kind == "black" then
			out("Black ICE spike! Your deck took feedback.", "err")
			World.warn("Black ICE")
			Network.addHeat(8, "black ice on " .. net.addr)
			emit("hack.blackice", event)
			addTrace(25)
		else
			addTrace(15)
		end
	end
end

function Shell.update(dt)
	local job = Shell.job
	if job then
		if Shell.connected ~= job.addr then
			Shell.job = nil
		else
			job.elapsed = job.elapsed + dt
			local target = job.traceTotal * math.min(1, job.elapsed / job.duration)
			local step = target - job.traced
			job.traced = target
			addTrace(step)
			if Shell.job and job.elapsed >= job.duration then
				Shell.job = nil
				finishJob(job)
			end
		end
	end
	-- NetWatch heat cools by 1 per minute of play
	Shell.heatDecayTimer = Shell.heatDecayTimer + dt
	if Shell.heatDecayTimer >= 60 then
		Shell.heatDecayTimer = 0
		if Network.state and Network.state.heat > 0 then Network.addHeat(-1, "cooling") end
	end
end

function Shell.setCwd(path)
	Shell.cwd = path
end

function Shell.reset()
	Shell.connected, Shell.cwd, Shell.trace, Shell.job = nil, "/", 0, nil
	Network.jacked, Network.jackedDevice = nil, nil
end

Shell.commands = commands
return Shell
