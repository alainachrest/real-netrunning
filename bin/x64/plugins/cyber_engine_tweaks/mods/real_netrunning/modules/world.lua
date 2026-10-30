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

local function entityFor(device)
	local entity = try(function() return Game.FindEntityByID(device.id) end)
	if entity == nil then return nil, "The device is out of range." end
	return entity
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
