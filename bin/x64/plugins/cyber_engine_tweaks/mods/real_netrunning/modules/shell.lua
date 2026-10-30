-- The cyberdeck shell: parses commands, runs breaches over time, tracks trace.

local Network = require("modules/network")
local Lore = require("modules/lore")
local World = require("modules/world")

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

def("status", "status", "Deck, connection, trace and NetWatch heat.", function()
	out("Deck power: " .. World.deckPower() .. "   NetWatch heat: " .. Network.state.heat .. "/100")
	local net = current()
	if net then
		out("Connected: " .. net.addr .. " (" .. net.name .. ")")
		out("ICE: " .. net.ice .. "   Trace: " .. math.floor(Shell.trace) .. "%   Access: " ..
			(Network.isOwned(net.addr) and "root" or "none"))
	else
		out("Not connected.")
	end
end)

def("scan", "scan", "List networks your deck can reach.", function()
	local list = Network.knownList()
	if #list == 0 then out("No networks in range.") return end
	for _, net in ipairs(list) do
		local org = Lore.getOrg(net.org)
		out(string.format("  %-34s ICE %d  %-5s %s", net.addr, net.ice,
			Network.isOwned(net.addr) and "ROOT" or "", net.name .. " [" .. org.name .. "]"),
			Network.isOwned(net.addr) and "ok" or "out")
	end
end)

def("connect", "connect <address>", "Connect to a network from scan.", function(args)
	local addr = args[1]
	if not addr then out("Usage: connect <address>", "err") return end
	local net = Network.get(addr)
	if net == nil or not Network.isKnown(addr) then out("No route to " .. addr .. ". Try scan.", "err") return end
	if Shell.connected then disconnect("switched") end
	Shell.connected, Shell.cwd, Shell.trace = addr, "/", 0
	out("Connected to " .. net.name .. ".", "ok")
	if net.ice == 0 and not Network.isOwned(addr) then
		Network.markOwned(addr)
		out("No ICE. Open access.", "ok")
	elseif not Network.isOwned(addr) then
		out("ICE level " .. net.ice .. " detected. Run 'breach' to get access.", "warn")
	end
	emit("hack.connected", { addr = addr, org = net.org })
end)

def("disconnect", "disconnect", "Drop the current connection.", function()
	if not Shell.connected then out("Not connected.") return end
	out("Disconnected from " .. Shell.connected .. ".")
	disconnect("user")
end)

def("breach", "breach", "Break the ICE on the current network.", function()
	local net = current()
	if net == nil then out("Connect to a network first.", "err") return end
	if Network.isOwned(net.addr) then out("You already have root here.") return end
	if Shell.job then out("A breach is already running.", "err") return end
	local power = World.deckPower()
	local duration = 2 + net.ice
	Shell.job = {
		addr = net.addr, elapsed = 0, duration = duration, power = power,
		traceTotal = math.max(5, 15 + net.ice * 10 - power * 3), traced = 0,
	}
	out(string.format("Breaching ICE %d with deck power %d... (%ds)", net.ice, power, duration), "warn")
end)

local function needAccess()
	local net = current()
	if net == nil then out("Connect to a network first.", "err") return nil end
	if not Network.isOwned(net.addr) then out("Access denied. Breach the ICE first.", "err") return nil end
	return net
end

def("ls", "ls [path]", "List files.", function(args)
	local net = needAccess() if not net then return end
	local node, path = Network.resolve(net, Shell.cwd, args[1])
	if node == nil then out("No such path.", "err") return end
	if not node.dir then out(path) return end
	local names = {}
	for name, child in pairs(node.children) do table.insert(names, child.dir and (name .. "/") or name) end
	table.sort(names)
	if #names == 0 then out("(empty)") end
	for _, n in ipairs(names) do out("  " .. n) end
end)

def("cd", "cd <path>", "Change directory.", function(args)
	local net = needAccess() if not net then return end
	local node, path = Network.resolve(net, Shell.cwd, args[1] or "/")
	if node == nil or not node.dir then out("No such directory.", "err") return end
	Shell.cwd = path
end)

def("cat", "cat <file>", "Read a file.", function(args)
	local net = needAccess() if not net then return end
	if not args[1] then out("Usage: cat <file>", "err") return end
	local node = Network.resolve(net, Shell.cwd, args[1])
	if node == nil or node.dir then out("No such file.", "err") return end
	out(node.text or "")
end)

def("download", "download <file>", "Download paydata to sell.", function(args)
	local net = needAccess() if not net then return end
	if not args[1] then out("Usage: download <file>", "err") return end
	local node, path = Network.resolve(net, Shell.cwd, args[1])
	if node == nil or node.dir then out("No such file.", "err") return end
	if not node.paydata then out("Nothing worth selling in that file.") return end
	local key = net.addr .. ":" .. path
	if Network.state.looted[key] then out("Already downloaded.") return end
	Network.state.looted[key] = true
	World.giveMoney(node.paydata)
	out("Paydata fenced through your contacts: +" .. node.paydata .. " eddies.", "ok")
	World.notify("Paydata sold: " .. node.paydata .. " eddies")
	emit("hack.download", { addr = net.addr, org = net.org, value = node.paydata, tier = net.tier })
	if net.ice >= 3 then addTrace(10) end
end)

def("jack", "jack", "Jack into the device you're looking at.", function()
	local device, err = World.lookAtDevice()
	if device == nil then out(err, "err") return end
	local addr = "local.device." .. device.hash
	Network.register({
		addr = addr, name = device.label .. " (local)", org = "unregistered", tier = 1,
		ice = device.ice, kind = "device", device = device, known = true,
	})
	commands.connect.fn({ addr })
	out("Jacked into " .. device.label:lower() .. ". Controls: " ..
		table.concat(World.deviceActionsFor(device.kind), ", "))
end)

def("device", "device <action>", "Control the device you're jacked into.", function(args)
	local net = needAccess() if not net then return end
	if net.kind ~= "device" or not net.device then out("This network has no device to control.", "err") return end
	local actions = World.deviceActionsFor(net.device.kind)
	if not args[1] then
		out(#actions > 0 and ("Actions: " .. table.concat(actions, ", ")) or "No direct controls on this device.")
		return
	end
	local ok, msg = World.deviceAction(net.device, args[1])
	out(msg, ok and "ok" or "err")
	if ok then
		emit("device.action", { kind = net.device.kind, action = args[1], addr = net.addr })
	end
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

local function finishBreach(job)
	local net = Network.get(job.addr)
	if net == nil then return end
	local chance = math.max(0.05, math.min(0.95, 0.55 + 0.15 * (job.power - net.ice)))
	local roll = Shell.random and Shell.random() or math.random()
	if roll < chance then
		local revealed = Network.markOwned(net.addr)
		out("ICE broken. Root access on " .. net.name .. ".", "ok")
		World.notify("Breached " .. net.name)
		for _, r in ipairs(revealed) do out("New route found: " .. r, "ok") end
		emit("hack.breach", { addr = net.addr, org = net.org, success = true, ice = net.ice, tier = net.tier })
	else
		out("Breach failed. The ICE adapted.", "err")
		emit("hack.breach", { addr = net.addr, org = net.org, success = false, ice = net.ice, tier = net.tier })
		if net.ice >= 5 then
			out("Black ICE spike! Your deck took feedback.", "err")
			World.warn("Black ICE")
			Network.addHeat(5, "black ice on " .. net.addr)
		end
		addTrace(15)
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
				finishBreach(job)
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

function Shell.reset()
	Shell.connected, Shell.cwd, Shell.trace, Shell.job = nil, "/", 0, nil
end

Shell.commands = commands
return Shell
