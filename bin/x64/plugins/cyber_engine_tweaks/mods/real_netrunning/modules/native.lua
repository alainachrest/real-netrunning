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
	if svc == nil then return end
	if not Native.synced then sync(svc) end

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
