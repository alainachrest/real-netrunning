-- Connects the Lua shell to the native deck popup (r6/scripts/RealNetrunning/Deck.reds).
-- If the redscript part or Codeware is missing, everything here quietly does nothing
-- and the CET overlay deck still works.

local Shell = require("modules/shell")
local Network = require("modules/network")
local World = require("modules/world")

local Native = {
	service = nil,
	synced = false,
	refreshTimer = 0,
	last = {},
	kinds = { out = 0, cmd = 1, ok = 2, warn = 3, err = 4 },
	log = print,
	missingLogged = false,
	machines = {},    -- desktop key -> network addr
	findTimer = 0,
}

local SERVICE = "RealNetrunning.DeckService"

function Native.getService()
	if Native.service then return Native.service end
	local ok, svc = pcall(function()
		return Game.GetScriptableServiceContainer():GetService(SERVICE)
	end)
	if ok and svc ~= nil then
		Native.service = svc
		Native.synced = false
		return svc
	end
	if not Native.missingLogged then
		Native.missingLogged = true
		Native.log("native deck not found (needs Codeware 1.21+ and r6/scripts/RealNetrunning). The CET overlay deck still works.")
	end
	return nil
end

local function call(fn)
	local ok, result = pcall(fn)
	if not ok then
		Native.log("native deck call failed: " .. tostring(result))
		return nil
	end
	return result
end

local function pushLine(text, kind)
	local svc = Native.service
	if svc and Native.synced then
		call(function() svc:AddLine(text, Native.kinds[kind] or 0) end)
	end
end

-- Copies the current screen into the native deck (first use, or after a reload).
local function sync(svc)
	call(function() svc:ClearLines() end)
	local first = math.max(1, #Shell.lines - 399)
	for i = first, #Shell.lines do
		local line = Shell.lines[i]
		call(function() svc:AddLine(line.text, Native.kinds[line.kind] or 0) end)
	end
	Native.synced = true
	Native.last = {}
end

Shell.onLine = pushLine
Shell.onClear = function()
	local svc = Native.service
	if svc and Native.synced then call(function() svc:ClearLines() end) end
end

local function statusText()
	local net = Shell.connected and Network.get(Shell.connected)
	local parts = {
		"DECK POWER " .. World.deckPower(),
		"NETWATCH HEAT " .. (Network.state and Network.state.heat or 0) .. "/100",
	}
	if net then
		table.insert(parts, "CONNECTED " .. net.name:upper() .. "  ICE " .. net.ice ..
			(Network.isOwned(net.addr) and "  ROOT" or ""))
	end
	return table.concat(parts, "   //   ")
end

---------------------------------------------------------------------------
-- Computer desktops (r6/scripts/RealNetrunning/Desktop.reds)
---------------------------------------------------------------------------

local function machineAddr(key)
	return "computer." .. tostring(key):gsub("[^%w_%-]", "_")
end

-- Flattens a network's generated filesystem into (path, text) pairs.
local function flatten(node, path, out)
	if node.dir then
		local names = {}
		for name in pairs(node.children) do table.insert(names, name) end
		table.sort(names)
		for _, name in ipairs(names) do flatten(node.children[name], path .. "/" .. name, out) end
	else
		local text = node.text or ""
		if node.paydata then
			text = text .. "\n\nPaydata worth about " .. node.paydata .. " eddies. Use 'download' in the Terminal to sell it."
		end
		table.insert(out, { path = path, text = text })
	end
end

function Native.pushMachineFiles(key)
	local svc, addr = Native.service, Native.machines[key]
	local net = addr and Network.get(addr)
	if svc == nil or net == nil then return end
	local files = {}
	flatten(Network.fs(net), "", files)
	local locked = not Network.isOwned(addr)
	call(function()
		svc:ClearMachineFiles(key)
		for _, f in ipairs(files) do svc:AddMachineFile(key, f.path, f.text, locked) end
		svc:MachineFilesReady(key)
	end)
end

-- A desktop opened on a computer: make that computer a network and send its files.
local function handleMachineRequest(request)
	local key, name = request:match("^(.-)|(.*)$")
	if not key or key == "" then return end
	local addr = machineAddr(key)
	Native.machines[key] = addr
	if Network.get(addr) == nil then
		Network.register({
			addr = addr, name = (name ~= "" and name or "Computer"), org = "unregistered",
			tier = 1, ice = 1, kind = "computer", known = true,
		})
	end
	call(function() Native.service:SetMachineAddr(key, addr) end)
	Native.pushMachineFiles(key)
end

-- After a breach the computer's system files unlock.
function Native.onBreached(e)
	if e.kind ~= "computer" then return end
	for key, addr in pairs(Native.machines) do
		if addr == e.addr then Native.pushMachineFiles(key) end
	end
end

-- The world is rebuilt on every save load, so computers re-register on request.
function Native.onWorldRebuilt()
	Native.machines = {}
end

function Native.isOpen()
	local svc = Native.service
	return svc ~= nil and call(function() return svc:IsOpen() end) == true
end

function Native.open()
	local svc = Native.getService()
	if svc == nil then return false end
	if not Native.synced then sync(svc) end
	Native.refreshTimer = 1 -- refresh status right away
	return call(function() return svc:Open() end) == true
end

function Native.close()
	local svc = Native.service
	if svc then call(function() svc:Close() end) end
end

function Native.update(dt)
	local svc = Native.service
	if svc == nil then
		-- desktops can talk to us before the deck is ever opened, so look for it
		Native.findTimer = Native.findTimer + dt
		if Native.findTimer < 2 then return end
		Native.findTimer = 0
		svc = Native.getService()
		if svc == nil then return end
	end
	if not Native.synced then sync(svc) end

	for _ = 1, 5 do
		local has = call(function() return svc:HasMachineRequest() end)
		if not has then break end
		local request = call(function() return svc:TakeMachineRequest() end)
		if request and request ~= "" then handleMachineRequest(request) end
	end

	-- run what was typed in the native deck (a few per frame at most)
	for _ = 1, 5 do
		local has = call(function() return svc:HasCommand() end)
		if not has then break end
		local command = call(function() return svc:TakeCommand() end)
		if command and command ~= "" then Shell.run(command) end
	end

	-- prompt, status and trace only change occasionally; push them when they do
	Native.refreshTimer = Native.refreshTimer + dt
	if Native.refreshTimer < 0.2 then return end
	Native.refreshTimer = 0
	if not Native.isOpen() then return end

	local prompt = Shell.prompt()
	if prompt ~= Native.last.prompt then
		Native.last.prompt = prompt
		call(function() svc:SetPrompt(prompt) end)
	end
	local status = statusText()
	if status ~= Native.last.status then
		Native.last.status = status
		call(function() svc:SetStatus(status) end)
	end
	local trace = Shell.connected and math.floor(Shell.trace) or -1
	if trace ~= Native.last.trace then
		Native.last.trace = trace
		call(function() svc:SetTrace(trace) end)
	end
end

return Native
