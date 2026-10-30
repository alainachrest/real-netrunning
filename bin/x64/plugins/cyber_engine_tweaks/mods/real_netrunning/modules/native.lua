-- Connects the Lua shell to the native deck popup (r6/scripts/RealNetrunning/Deck.reds).
-- If the redscript part or Codeware is missing, everything here quietly does nothing
-- and the CET overlay deck still works.

local Shell = require("modules/shell")
local Network = require("modules/network")
local World = require("modules/world")
local Rng = require("modules/rng")
local Web = require("modules/web")
local Stores = require("modules/stores")

local Native = {
	service = nil,
	synced = false,
	refreshTimer = 0,
	last = {},
	kinds = { out = 0, cmd = 1, ok = 2, warn = 3, err = 4 },
	log = print,
	missingLogged = false,
	machines = {},    -- desktop key -> network addr
	addrOwner = {},   -- network addr -> desktop key
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

-- Stores and sites from other mods, read through DeckService (Stores.reds).
local function svcCall(fn, fallback)
	local svc = Native.service or Native.getService()
	if svc == nil then return fallback end
	local result = call(function() return fn(svc) end)
	if result == nil then return fallback end
	return result
end

Stores.provider = {
	installed = function() return svcCall(function(s) return s:AtelierInstalled() end, false) end,
	refresh = function() return svcCall(function(s) return s:RefreshStores() end, 0) end,
	name = function(i) return svcCall(function(s) return s:StoreName(i) end, "") end,
	itemCount = function(i) return svcCall(function(s) return s:StoreItemCount(i) end, 0) end,
	item = function(i, j)
		return svcCall(function(s)
			return { name = s:StoreItemName(i, j), id = s:StoreItemId(i, j), price = s:StoreItemPrice(i, j),
				quantity = s:StoreItemQuantity(i, j), quality = s:StoreItemQuality(i, j) }
		end, { name = "?", id = "", price = 0, quantity = 1, quality = "" })
	end,
	buyAtelier = function(i, j) return svcCall(function(s) return s:BuyStoreItem(i, j) end, "err:The store didn't answer.") end,
	itemName = function(id) return svcCall(function(s) return s:ItemName(id) end, id) end,
	itemPrice = function(id, price, qty) return svcCall(function(s) return s:ItemPrice(id, price, qty) end, price) end,
	buy = function(id, qty, price) return svcCall(function(s) return s:BuyItem(id, qty, price) end, "err:The store didn't answer.") end,
	sites = function()
		return svcCall(function(s)
			local list = {}
			for i = 0, s:ModSiteCount() - 1 do
				table.insert(list, { name = s:ModSiteName(i), address = s:ModSiteAddress(i), embedded = s:ModSiteKind(i) == 1 })
			end
			return list
		end, {})
	end,
}

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
	Native.pushHomeFiles()
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

-- Night City districts, as they appear in the game's world paths.
local districts = {
	"watson", "westbrook", "city_center", "heywood", "santo_domingo", "pacifica",
	"dogtown", "badlands", "northside", "kabuki", "japantown", "charter_hill",
	"vista_del_rey", "glen", "wellsprings", "rancho_coronado", "arroyo", "corpo_plaza",
	"downtown", "little_china", "coastview", "west_wind",
}

-- A short, readable address for a computer, e.g. "watson.pc-3f9a" or "home.pc-81c0".
-- Computer IDs are long world paths; the hash keeps each address unique and stable.
local function machineAddr(key)
	key = tostring(key)
	local lower = key:lower()
	local area = "nc"
	if lower:find("v_room", 1, true) or lower:find("v_apartment", 1, true) then
		area = "home"
	else
		for _, d in ipairs(districts) do
			if lower:find(d, 1, true) then area = d:gsub("_", "") break end
		end
	end
	local addr = string.format("%s.pc-%04x", area, Rng.hash(key) % 65536)
	-- in the rare case two computers hash the same, add more of the hash
	local taken = Native.addrOwner[addr]
	if taken and taken ~= key then
		addr = string.format("%s.pc-%08x", area, Rng.hash(key))
	end
	Native.addrOwner[addr] = key
	return addr
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
	call(function()
		svc:ClearMachineFiles(key)
		for _, f in ipairs(files) do
			svc:AddMachineFile(key, f.path, f.text, not Network.canAccess(net, f.path))
		end
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

-- When a computer's floors open, its locked files unlock on the desktop.
function Native.onBreached(e)
	for key, addr in pairs(Native.machines) do
		if addr == e.addr then Native.pushMachineFiles(key) end
	end
end

-- The world is rebuilt on every save load, so computers re-register on request.
function Native.onWorldRebuilt()
	Native.machines = {}
	Native.addrOwner = {}
	Native.last.heat = nil
	Native.pushHomeFiles()
end

-- Sends the documents V saved to every home computer desktop.
function Native.pushHomeFiles()
	local svc = Native.service
	if svc == nil or Network.state == nil then return end
	local files = Network.state.homeFiles or {}
	call(function()
		svc:ClearHomeFiles()
		for _, f in ipairs(files) do svc:AddHomeFile(f.name, f.text) end
		svc:HomeFilesReady()
	end)
end

local MAX_HOME_FILES = 100

local function saveToHome(name, text)
	if Network.state == nil or name == nil or name == "" then return end
	local files = Network.state.homeFiles
	-- saving the same document again replaces it
	for i = #files, 1, -1 do
		if files[i].name == name then table.remove(files, i) end
	end
	table.insert(files, { name = name, text = text or "" })
	while #files > MAX_HOME_FILES do table.remove(files, 1) end
	Native.pushHomeFiles()
	World.notify("Saved to your home computer")
end

-- Block types, numbered the same way in Browser.reds.
local blockTypes = {
	banner = 1, nav = 2, heading = 3, text = 4, link = 5, button = 6, card = 7,
	row = 8, chart = 9, divider = 10, notice = 11, icon = 12, field = 13,
}

-- A Browser window asked for a page.
local function servePage(url)
	local svc = Native.service
	local ok, p = pcall(Web.render, url)
	if not ok then
		Native.log("page " .. tostring(url) .. " failed: " .. tostring(p))
		p = { title = "Error", url = url, theme = "MainColors.Red",
			blocks = { { type = "notice", text = "This page failed to load.", extra = "", link = "", color = "MainColors.Red" } } }
	end
	call(function()
		svc:BeginPage(url, p.title or "", p.url or url, p.theme or "MainColors.Red")
		for _, b in ipairs(p.blocks) do
			svc:AddPageBlock(url, blockTypes[b.type] or 4, b.text or "", b.extra or "", b.link or "", b.color or "")
		end
		svc:PageReady(url)
	end)
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

	for _ = 1, 5 do
		local has = call(function() return svc:HasPageRequest() end)
		if not has then break end
		local url = call(function() return svc:TakePageRequest() end)
		if url then servePage(url) end
	end

	for _ = 1, 5 do
		local has = call(function() return svc:HasSaveRequest() end)
		if not has then break end
		local name = call(function() return svc:TakeSaveName() end)
		local text = call(function() return svc:TakeSaveText() end)
		saveToHome(name, text)
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

	-- desktop trays show heat whether or not the deck popup is open
	local heat = Network.state and Network.state.heat or 0
	if heat ~= Native.last.heat then
		Native.last.heat = heat
		call(function() svc:SetHeat(heat) end)
	end

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
