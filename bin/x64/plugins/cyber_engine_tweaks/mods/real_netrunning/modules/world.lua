-- Everything that touches the running game lives here, wrapped in pcall,
-- so a changed game function fails with a message instead of breaking the mod.

local World = {
	hud = nil, -- GameHUD, set by init when available
	log = print,
}

local function try(fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		World.log("game call failed: " .. tostring(a))
		return nil, tostring(a)
	end
	return a, b
end

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------

-- Deck power 1-6, from V's Intelligence (3-20).
function World.deckPower()
	local int = try(function()
		local player = Game.GetPlayer()
		return Game.GetStatsSystem():GetStatValue(player:GetEntityID(), gamedataStatType.Intelligence)
	end)
	if type(int) ~= "number" then return 2 end
	return math.max(1, math.min(6, math.floor(int / 4) + 1))
end

function World.giveMoney(amount)
	return try(function()
		Game.AddToInventory("Items.money", math.floor(amount))
		return true
	end)
end

function World.getMoney()
	local amount = try(function()
		return Game.GetTransactionSystem():GetItemQuantity(Game.GetPlayer(), MarketSystem.Money())
	end)
	return type(amount) == "number" and amount or 0
end

-- Takes eddies from V. Returns true only if V had enough and they were removed.
function World.spendMoney(amount)
	amount = math.floor(amount)
	if amount <= 0 then return true end
	if World.getMoney() < amount then return false end
	local ok = try(function()
		return Game.GetTransactionSystem():RemoveItemByTDBID(Game.GetPlayer(), TweakDBID.new("Items.money"), amount)
	end)
	return ok == true
end

-- Applies one of the game's status effects to V, e.g. "BaseStatusEffect.PlayerElectrocuted".
function World.applyStatusEffect(effect)
	return try(function()
		local player = Game.GetPlayer()
		Game.GetStatusEffectSystem():ApplyStatusEffect(player:GetEntityID(), TweakDBID.new(effect))
		return true
	end)
end

-- Tips off the NCPD: the same request the game makes when a crime is witnessed.
function World.reportToPolice()
	return try(function()
		local player = Game.GetPlayer()
		PreventionSystem.CrimeWitnessRequestToPreventionSystem(player:GetGame(), player:GetWorldPosition())
		return true
	end)
end

function World.notify(text)
	if World.hud then try(function() World.hud.ShowMessage(text) end) end
end

function World.warn(text)
	if World.hud then try(function() World.hud.ShowWarning(text, 4.0) end) end
end

function World.isInGame()
	local player = try(function() return Game.GetPlayer() end)
	return player ~= nil
end

---------------------------------------------------------------------------
-- Real devices
---------------------------------------------------------------------------

-- Checked in order; the first class the object is counts.
local deviceKinds = {
	{ class = "Door",               kind = "door",     label = "Door",              ice = 1 },
	{ class = "SurveillanceCamera", kind = "camera",   label = "Surveillance camera", ice = 2 },
	{ class = "SecurityTurret",     kind = "turret",   label = "Security turret",   ice = 3 },
	{ class = "AccessPoint",        kind = "access",   label = "Access point",      ice = 2 },
	{ class = "Computer",           kind = "computer", label = "Computer",          ice = 1 },
}

World.deviceKinds = deviceKinds

-- Returns info about the device V is looking at, or nil and a reason.
function World.lookAtDevice()
	local result, err = try(function()
		local player = Game.GetPlayer()
		if player == nil then return nil end
		local obj = Game.GetTargetingSystem():GetLookAtObject(player, false, false)
		if obj == nil then return nil end
		for _, k in ipairs(deviceKinds) do
			if obj:IsA(k.class) then
				local id = obj:GetEntityID()
				return { id = id, hash = tostring(id.hash), kind = k.kind, label = k.label, ice = k.ice }
			end
		end
		return false
	end)
	if result == nil then return nil, err or "Look at a device first." end
	if result == false then return nil, "That isn't a device you can jack into." end
	return result
end

---------------------------------------------------------------------------
-- Access points and the devices wired to them
---------------------------------------------------------------------------

-- Device controller classes, most specific first.
local psKinds = {
	{ class = "AccessPointControllerPS",        kind = "access",   label = "Access point" },
	{ class = "SurveillanceCameraControllerPS", kind = "camera",   label = "Camera" },
	{ class = "SecurityTurretControllerPS",     kind = "turret",   label = "Turret" },
	{ class = "DoorControllerPS",               kind = "door",     label = "Door" },
	{ class = "ComputerControllerPS",           kind = "computer", label = "Computer" },
	{ class = "TerminalControllerPS",           kind = "terminal", label = "Terminal" },
}

-- Turns a device controller (PS) into the same shape lookAtDevice returns.
local function describePS(ps)
	local id = PersistentID.ExtractEntityID(ps:GetID())
	local info = { id = id, hash = tostring(id.hash), kind = "device", label = "Device", ice = 1 }
	for _, k in ipairs(psKinds) do
		if ps:IsA(k.class) then
			info.kind, info.label = k.kind, k.label
			break
		end
	end
	local ok, name = pcall(function() return ps:GetDeviceName() end)
	if ok and type(name) == "string" and name ~= "" and not name:find("^LocKey") then
		info.label = info.label .. " - " .. name
	end
	return info
end

-- The access point a device is wired to (or the device itself if it is one), or nil.
function World.accessPointFor(device)
	if device.kind == "access" then return device end
	local found = try(function()
		local parents = Game.GetDeviceSystem():GetParents(device.id)
		for _, ps in ipairs(parents or {}) do
			if ps:IsA("AccessPointControllerPS") then return describePS(ps) end
		end
		return false
	end)
	return found or nil
end

-- Every device wired to an access point.
function World.devicesOn(accessPoint)
	local list = try(function()
		local out = {}
		local children = Game.GetDeviceSystem():GetChildren(accessPoint.id)
		for _, ps in ipairs(children or {}) do
			local info = describePS(ps)
			if info.kind ~= "access" then table.insert(out, info) end
		end
		return out
	end)
	return list or {}
end

local function entityFor(device)
	local entity = try(function() return Game.FindEntityByID(device.id) end)
	if entity == nil then return nil, "The device is out of range." end
	return entity
end

-- Metres between V and a device, or nil when the game can't tell (then callers allow it).
function World.distanceTo(device)
	if device == nil or device.id == nil then return nil end
	return try(function()
		local entity = Game.FindEntityByID(device.id)
		local player = Game.GetPlayer()
		if player == nil then return nil end
		if entity == nil then return math.huge end -- streamed out: V is far away
		return Vector4.Distance(player:GetWorldPosition(), entity:GetWorldPosition())
	end)
end

-- Actions per device kind. Each returns a message for the terminal.
local actions = {
	door = {
		open = function(e)
			local ps = e:GetDevicePS()
			if ps:IsSealed() then ps:ToggleSealOnDoor() end
			if ps:IsLocked() then ps:ToggleLockOnDoor() end
			e:OpenDoor()
			return "Door opened."
		end,
		close = function(e) e:CloseDoor() return "Door closed." end,
		unlock = function(e)
			local ps = e:GetDevicePS()
			if ps:IsSealed() then ps:ToggleSealOnDoor() end
			if ps:IsLocked() then ps:ToggleLockOnDoor() end
			return "Door unlocked."
		end,
		lock = function(e)
			local ps = e:GetDevicePS()
			if not ps:IsLocked() then ps:ToggleLockOnDoor() end
			return "Door locked."
		end,
	},
}

local function powerActions(name)
	return {
		off = function(e)
			e:TurnOffDevice()
			local ps = e:GetDevicePS()
			if ps then ps:UnpowerDevice() end
			return name .. " powered down."
		end,
		on = function(e)
			e:TurnOnDevice()
			local ps = e:GetDevicePS()
			if ps then ps:PowerDevice() end
			return name .. " powered up."
		end,
	}
end

actions.camera = powerActions("Camera")
actions.turret = powerActions("Turret")

function World.deviceActionsFor(kind)
	local names = {}
	for name, _ in pairs(actions[kind] or {}) do table.insert(names, name) end
	table.sort(names)
	return names
end

function World.deviceAction(device, action)
	local set = actions[device.kind]
	if set == nil or set[action] == nil then
		return false, "Can't '" .. tostring(action) .. "' a " .. device.label:lower() .. "."
	end
	local entity, err = entityFor(device)
	if entity == nil then return false, err end
	local msg, callErr = try(set[action], entity)
	if msg == nil then return false, "The device didn't respond (" .. tostring(callErr) .. ")." end
	return true, msg
end

return World
