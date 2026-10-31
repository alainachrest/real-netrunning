-- Everything that touches the running game lives here, wrapped in pcall,
-- so a changed game function fails with a message instead of breaking the mod.

local World = {
	hud = nil, -- GameHUD, set by init when available
	log = print,
}

local function try(fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		World.lastError = tostring(a)
		World.log("game call failed: " .. tostring(a))
		return nil, tostring(a)
	end
	return a, b
end

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------

-- Deck power 1-6, from V's Intelligence (3-20).
-- Deck power comes from the tier of the cyberdeck V has installed, the way Much
-- Better Netrunning gates hacking by deck quality:
--   none 0   Common 1   Uncommon 2   Rare 3   Epic 4   Legendary 5   Legendary+ / ++ 6
World.qualityNames = { [0] = "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- The installed cyberdeck: { name, quality (0-4), plus (0-2), tier (1-6) }, or nil if V has none.
function World.cyberdeck()
	local deck = try(function()
		local player = Game.GetPlayer()
		if player == nil then return nil end
		local equipment = Game.GetScriptableSystemsContainer():Get("EquipmentSystem")
		local data = equipment:GetPlayerData(player)
		local itemID = data:GetItemInEquipSlot(gamedataEquipmentArea.SystemReplacementCW, 0)
		if itemID == nil or not ItemID.IsValid(itemID) then return false end
		local record = TweakDBInterface.GetItemRecord(itemID:GetTDBID())
		if record == nil or not record:TagsContains("Cyberdeck") then return false end
		local name = "Cyberdeck"
		pcall(function()
			local text = Game.GetLocalizedTextByKey(record:DisplayName())
			if text and text ~= "" then name = text end
		end)
		local quality, plus = 0, 0
		pcall(function()
			local itemData = Game.GetTransactionSystem():GetItemData(player, itemID)
			local stats = Game.GetStatsSystem()
			quality = math.floor(stats:GetStatValue(itemData:GetStatsObjectID(), gamedataStatType.Quality) + 0.5)
			plus = math.floor(stats:GetStatValue(itemData:GetStatsObjectID(), gamedataStatType.IsItemPlus) + 0.5)
		end)
		quality = math.max(0, math.min(4, quality))
		local tier = quality + 1
		if quality == 4 and plus >= 1 then tier = 6 end
		return { name = name, quality = quality, plus = plus, tier = tier }
	end)
	return deck or nil
end

function World.qualityName(deck)
	if deck == nil then return "none" end
	return (World.qualityNames[deck.quality] or "Common") .. string.rep("+", deck.plus or 0)
end

-- The deck quality a tier stands for.
function World.tierName(tier)
	if tier >= 6 then return "Legendary+" end
	return World.qualityNames[math.max(1, tier) - 1] or "Common"
end

local cachedDeck, cachedAt = nil, nil
-- 0 with no cyberdeck installed, 1-6 by its tier. Checked at most once a second.
function World.deckPower()
	local now = os.clock()
	if cachedAt == nil or now - cachedAt > 1 then
		cachedDeck, cachedAt = World.cyberdeck(), now
	end
	return cachedDeck and cachedDeck.tier or 0
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

-- The item type name of an item ("Wea_Fists", "Wea_Pistol", ...), or nil.
local function itemTypeName(itemID)
	local record = TweakDBInterface.GetItemRecord(itemID:GetTDBID())
	if record == nil then return nil end
	local kind = record:ItemType():Type()
	local ok, name = pcall(function() return EnumValueToString("gamedataItemType", EnumInt(kind)) end)
	if ok and type(name) == "string" and name ~= "" then return name end
	return tostring(kind):match("([%w_]+)%s*%(") or tostring(kind)
end

-- The item type of the weapon in V's hands ("Wea_Fists", "Wea_Pistol", ...), or nil when empty-handed.
function World.weaponInHand()
	return try(function()
		local player = Game.GetPlayer()
		if player == nil then return nil end
		local item = Game.GetTransactionSystem():GetItemInSlot(player, TweakDBID.new("AttachmentSlots.WeaponRight"))
		if item == nil then return nil end
		return itemTypeName(item:GetItemID()) or "unknown"
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

function World.removeStatusEffect(effect)
	return try(function()
		local player = Game.GetPlayer()
		Game.GetStatusEffectSystem():RemoveStatusEffect(player:GetEntityID(), TweakDBID.new(effect))
		return true
	end)
end

---------------------------------------------------------------------------
-- Cyberspace: spawning, moving V, ICE (see modules/cyberspace.lua)
---------------------------------------------------------------------------

-- V's position and facing: x, y, z, yaw (degrees). nil if unavailable.
function World.playerTransform()
	local result = try(function()
		local player = Game.GetPlayer()
		local p = player:GetWorldPosition()
		local yaw = player:GetWorldYaw()
		return { x = p.x, y = p.y, z = p.z, yaw = yaw }
	end)
	return result
end

function World.teleport(x, y, z, yaw)
	return try(function()
		local player = Game.GetPlayer()
		Game.GetTeleportationFacility():Teleport(player, Vector4.new(x, y, z, 1.0), EulerAngles.new(0, 0, yaw or 0))
		return true
	end)
end

-- Spawns a static entity from a template path. Returns its EntityID.
function World.spawnProp(path, x, y, z, yaw, appearance)
	return try(function()
		local spec = StaticEntitySpec.new()
		spec.templatePath = path
		spec.position = Vector4.new(x, y, z, 1.0)
		spec.orientation = EulerAngles.new(0, 0, yaw or 0):ToQuat()
		if appearance then spec.appearanceName = appearance end
		spec.attached = true
		return Game.GetStaticEntitySystem():SpawnEntity(spec)
	end)
end

-- An invisible 8 x 8 m floor tile (the collider is added in Cyberspace.reds), centred on x, y, z.
World.tileTemplate = "base\\quest\\main_quests\\part1\\q115\\test\\empty_entity.ent"
function World.spawnTile(x, y, z)
	return World.spawnProp(World.tileTemplate, x, y, z, 0)
end

-- true once a static entity is in the world.
function World.propSpawned(id)
	if id == nil then return false end
	return try(function() return Game.GetStaticEntitySystem():IsSpawned(id) end) == true
end

-- Details for 'cyber debug': does the entity exist, and does it have a collider?
function World.propInfo(id)
	local info = { entity = false, collider = false }
	if id == nil then return info end
	try(function()
		local entity = Game.GetStaticEntitySystem():GetEntity(id)
		if entity == nil then return end
		info.entity = true
		for _, comp in ipairs(entity:GetComponents()) do
			if comp:IsA("entColliderComponent") then info.collider = true end
		end
	end)
	return info
end

-- How many floor tiles redscript has given a collider (Cyberspace.reds).
function World.collidersAdded()
	return try(function()
		local system = Game.GetScriptableSystemsContainer():Get("RealNetrunning.RNCyberspaceSystem")
		if system == nil then return "redscript system not found" end
		return system:CollidersAdded()
	end)
end

function World.despawnProp(id)
	if id == nil then return end
	try(function() Game.GetStaticEntitySystem():DespawnEntity(id) end)
end

-- Spawns an NPC from a character record, e.g. "Character.netwatch_base_ma". Returns its EntityID.
function World.spawnNPC(record, x, y, z, yaw)
	return try(function()
		local spec = DynamicEntitySpec.new()
		spec.recordID = record
		spec.position = Vector4.new(x, y, z, 1.0)
		spec.orientation = EulerAngles.new(0, 0, yaw or 0):ToQuat()
		spec.alwaysSpawned = true
		spec.persistState = false
		spec.persistSpawn = false
		return Game.GetDynamicEntitySystem():CreateEntity(spec)
	end)
end

-- A copy of an NPC record that fights with its fists: its equipment is swapped
-- for a fist-fighting gang member's, so it never has a gun to draw (taking guns
-- away after it spawns doesn't stick: NPCs re-arm from their record in a
-- fight) but still has something to fight with (with no equipment at all they
-- just stand there). Its quickhacks and everything else are the original's.
-- Returns the copy's record name, or nil if TweakDB wouldn't do it.
World.fistsFrom = "Character.tyger_claws_gangster2_melee2_fists_ma"

-- A copy of a brawler's record with its secondary equipment (the gun some of
-- them pull when a fist fight goes badly) removed; its fists stay.
local fistsOnly = {}
function World.fistsOnlyRecord(record)
	if fistsOnly[record] ~= nil then return fistsOnly[record] or nil end
	local name = try(function()
		local empty = "RealNetrunning.NoEquipment"
		if TweakDB:GetRecord(empty) == nil then
			TweakDB:CreateRecord(empty, "gamedataNPCEquipmentGroup_Record")
		end
		local copy = "RealNetrunning.FistsOnly_" .. record:gsub("^Character%.", "")
		if TweakDB:GetRecord(copy) == nil and not TweakDB:CloneRecord(copy, record) then return nil end
		TweakDB:SetFlat(copy .. ".secondaryEquipment", TweakDBID.new(empty))
		return copy
	end)
	fistsOnly[record] = name or false
	return name
end
local unarmed = {}
function World.unarmedRecord(record)
	if unarmed[record] ~= nil then return unarmed[record] or nil end
	local name = try(function()
		local fists = TweakDB:GetFlat(World.fistsFrom .. ".primaryEquipment")
		local empty = "RealNetrunning.NoEquipment"
		if TweakDB:GetRecord(empty) == nil then
			TweakDB:CreateRecord(empty, "gamedataNPCEquipmentGroup_Record")
		end
		local copy = "RealNetrunning.Unarmed_" .. record:gsub("^Character%.", "")
		if TweakDB:GetRecord(copy) == nil and not TweakDB:CloneRecord(copy, record) then return nil end
		TweakDB:SetFlat(copy .. ".primaryEquipment", fists or TweakDBID.new(empty))
		TweakDB:SetFlat(copy .. ".secondaryEquipment", TweakDBID.new(empty))
		return copy
	end)
	unarmed[record] = name or false
	return name
end

function World.deleteNPC(id)
	if id == nil then return end
	try(function() Game.GetDynamicEntitySystem():DeleteEntity(id) end)
end

-- Moves a spawned NPC (cyberspace hunters go from room to room this way).
function World.moveNPC(id, x, y, z, yaw)
	return try(function()
		local npc = Game.FindEntityByID(id)
		if npc == nil then return false end
		Game.GetTeleportationFacility():Teleport(npc, Vector4.new(x, y, z, 1.0), EulerAngles.new(0, 0, yaw or 0))
		return true
	end) == true
end

-- Where a spawned NPC is: { x, y, z }, or nil.
function World.npcPosition(id)
	return try(function()
		local npc = Game.FindEntityByID(id)
		if npc == nil then return nil end
		local p = npc:GetWorldPosition()
		return { x = p.x, y = p.y, z = p.z }
	end)
end

World.seenHealthy = {}

-- true dead, false alive, nil not spawned (yet). Down counts as dead: a
-- defeated NPC, or one with no health left (some NPCs drop "defeated" instead
-- of dying). A stunned one that will get back up still counts as alive.
function World.npcDead(id)
	local result = try(function()
		local npc = Game.FindEntityByID(id)
		if npc == nil then return "none" end
		if npc:IsDead() then return "dead" end
		local down = false
		pcall(function() if npc:IsDefeated() then down = true end end)
		-- health reads 0 for a moment while an NPC spawns, so no health only
		-- counts once it has been seen with some
		pcall(function()
			local hp = Game.GetStatPoolsSystem():GetStatPoolValue(npc:GetEntityID(), gamedataStatPoolType.Health, true)
			if type(hp) ~= "number" then return end
			local key = tostring(id.hash or id)
			if hp > 1 then World.seenHealthy[key] = true
			elseif hp <= 0.5 and World.seenHealthy[key] then down = true end
		end)
		return down and "dead" or "alive"
	end)
	if result == "dead" then return true elseif result == "alive" then return false end
	return nil
end

-- Turns a spawned NPC against V. Returns true once it worked.
function World.makeHostile(id)
	return try(function()
		local npc = Game.FindEntityByID(id)
		local player = Game.GetPlayer()
		if npc == nil or player == nil then return false end
		npc:GetAttitudeAgent():SetAttitudeGroup(CName.new("hostile"))
		AIActionHelper.TryChangingAttitudeToHostile(npc, player)
		return true
	end) == true
end

-- Takes every weapon off a spawned NPC except the item types in `keep` (e.g.
-- fists), so it fights with quickhacks and bare hands like V.
-- handsOnly: only take what it's holding right now, leaving its inventory alone.
-- Returns how many weapons were removed (0 once it's unarmed), or nil if it isn't there yet.
-- true if a spawned NPC carries any gun (in its hands or its pockets), false
-- if it has none, nil if it isn't there yet.
function World.npcHasGun(id)
	return try(function()
		local npc = Game.FindEntityByID(id)
		if npc == nil then return nil end
		local ts = Game.GetTransactionSystem()
		local ok, items = ts:GetItemList(npc)
		if not ok or items == nil then return nil end
		for _, data in ipairs(items) do
			local okTag, yes = pcall(function()
				local record = TweakDBInterface.GetItemRecord(data:GetID():GetTDBID())
				return record ~= nil and record:TagsContains("RangedWeapon")
			end)
			if okTag and yes then return true end
		end
		return false
	end)
end

function World.disarm(id, keep, handsOnly)
	-- Only guns go: anything tagged as a ranged weapon. Everything else (fists,
	-- Gorilla Arms) stays, so the NPC still has something to fight with. Going
	-- by item type to spare the fists took them too, and left NPCs passive.
	local function isGun(itemID)
		local ok, yes = pcall(function()
			local record = TweakDBInterface.GetItemRecord(itemID:GetTDBID())
			return record ~= nil and record:TagsContains("RangedWeapon")
		end)
		return ok and yes == true
	end
	return try(function()
		local npc = Game.FindEntityByID(id)
		if npc == nil then return nil end
		local ts = Game.GetTransactionSystem()
		local removed = 0
		for _, slot in ipairs({ "AttachmentSlots.WeaponRight", "AttachmentSlots.WeaponLeft" }) do
			pcall(function()
				local item = ts:GetItemInSlot(npc, TweakDBID.new(slot))
				if item and isGun(item:GetItemID()) then
					ts:RemoveItem(npc, item:GetItemID(), 1)
					removed = removed + 1
				end
			end)
		end
		if handsOnly then return removed end
		local ok, items = ts:GetItemList(npc)
		if not ok or items == nil then return removed end
		for _, data in ipairs(items) do
			if isGun(data:GetID()) then
				ts:RemoveItem(npc, data:GetID(), data:GetQuantity())
				removed = removed + 1
			end
		end
		return removed
	end)
end

-- V's health in percent (0-100).
function World.healthPercent()
	local value = try(function()
		local player = Game.GetPlayer()
		return Game.GetStatPoolsSystem():GetStatPoolValue(player:GetEntityID(), gamedataStatPoolType.Health, true)
	end)
	return type(value) == "number" and value or 100
end

-- Takes a share of V's health (percent of the maximum), as a hack would.
function World.damagePlayer(percent)
	return try(function()
		local player = Game.GetPlayer()
		Game.GetStatPoolsSystem():RequestChangingStatPoolValue(player:GetEntityID(), gamedataStatPoolType.Health,
			-math.abs(percent), player, false, true)
		return true
	end)
end

function World.inCombat()
	return try(function() return Game.GetPlayer():IsInCombat() end) == true
end

function World.inVehicle()
	return try(function() return Game.GetMountedVehicle(Game.GetPlayer()) ~= nil end) == true
end

-- Cyberspace look, set in Cyberspace.reds: floor style, floor scale, sky preset.
local function cyberSystem()
	return Game.GetScriptableSystemsContainer():Get("RealNetrunning.RNCyberspaceSystem")
end

function World.cyberCall(method, ...)
	local args = { ... }
	return try(function()
		local system = cyberSystem()
		if system == nil then return nil end
		return system[method](system, unpack(args))
	end)
end

-- A floor slab (kind 0) or wall/door barrier (kind 1) of any size: half
-- extents hx, hy, hz around x, y, z, turned by yaw. Built in Cyberspace.reds.
function World.spawnBlock(x, y, z, yaw, hx, hy, hz, kind)
	return World.cyberCall("SpawnBlock", x, y, z, yaw or 0, hx, hy, hz, kind or 0)
end

-- Tells redscript V is in cyberspace (blocks manual saves).
function World.setJackedIn(on)
	return try(function()
		local system = Game.GetScriptableSystemsContainer():Get("RealNetrunning.RNCyberspaceSystem")
		if system then system:SetJackedIn(on == true) end
		return true
	end)
end

---------------------------------------------------------------------------
-- The HUD, through the game's own interface settings (Settings > Interface)
---------------------------------------------------------------------------

-- true/false for a HUD setting such as "minimap", or nil if the game has no such setting.
function World.hudSetting(name)
	local value = try(function()
		local var = Game.GetSettingsSystem():GetVar("/interface/hud", name)
		if var == nil then return nil end
		return var:GetValue()
	end)
	if type(value) == "boolean" then return value end
	return nil
end

function World.setHudSettings(values)
	return try(function()
		local settings = Game.GetSettingsSystem()
		for name, value in pairs(values) do
			local var = settings:GetVar("/interface/hud", name)
			if var ~= nil then var:SetValue(value == true) end
		end
		settings:ConfirmChanges()
		return true
	end)
end

-- The names of the visual effects V's own entity can play (from V's entity
-- template), for finding a jack-in effect. The template loads in the
-- background: returns the list once it's in, otherwise a note to try again.
function World.playerEffects()
	if World.effectsToken == nil then
		local ok, err = pcall(function()
			local path = Game.GetPlayer():GetTemplatePath()
			World.effectsPath = tostring(path)
			World.effectsToken = Game.GetResourceDepot():LoadResource(path)
		end)
		if not ok then return "couldn't look up V's template: " .. tostring(err) end
		return "loading V's template... run 'cyber debug' again"
	end
	local ok, result = pcall(function()
		local token = World.effectsToken
		if token:IsFailed() then return "V's template failed to load" end
		if not token:IsLoaded() then return "still loading V's template... run 'cyber debug' again" end
		local template = token:GetResource()
		local names = {}
		for _, desc in ipairs(template.effects or {}) do
			local name = desc.effectName
			local ok2, text = pcall(function() return name.value end)
			table.insert(names, ok2 and text and tostring(text) or tostring(name))
		end
		if #names == 0 then return "no effects on V's template" end
		table.sort(names)
		return table.concat(names, ", ")
	end)
	if not ok then
		World.effectsToken = nil
		return "couldn't read V's effects: " .. tostring(result)
	end
	return result
end

-- Particles in cyberspace rooms: each particle block (kind 5) gets a particle
-- system added as its entity initialises (the redscript side passes every
-- cyberspace block through RNEntityHooks; this observes it), through Codeware's
-- ResourceHelper, the way World Builder adds particles.
World.particlesAdded, World.particleError, World.particleSeen = 0, nil, 0
function World.watchParticleBlocks(kind, path)
	return try(function()
		Observe("RNEntityHooks", "OnEntityInitialize", function(_, event)
			World.particleSeen = World.particleSeen + 1
			local ok, err = pcall(function()
				local entity = event:GetEntity()
				if entity == nil then return end
				-- particle blocks carry a component with this name (Cyberspace.reds)
				if entity:FindComponentByName("rn_particles_here") == nil then return end
				World.particleBlocks = (World.particleBlocks or 0) + 1
				local component = entParticlesComponent.new()
				component.name = "rn_particles"
				ResourceHelper.LoadReferenceResource(component, "particleSystem", path, true)
				component.emissionRate = 1.0
				entity:AddComponent(component)
				World.particlesAdded = World.particlesAdded + 1
			end)
			if not ok then World.particleError = tostring(err) end
		end)
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

-- Every electronic device in the game derives from Device. Checked in order,
-- most specific first; anything else is a plain "device". psClass is the
-- device's controller class, for devices found through the device system.
local deviceKinds = {
	{ class = "Door",                kind = "door",     label = "Door",                ice = 1, psClass = "DoorControllerPS" },
	{ class = "SurveillanceCamera",  kind = "camera",   label = "Surveillance camera", ice = 2, psClass = "SurveillanceCameraControllerPS" },
	{ class = "SecurityTurret",      kind = "turret",   label = "Security turret",     ice = 3, psClass = "SecurityTurretControllerPS" },
	{ class = "AccessPoint",         kind = "access",   label = "Access point",        ice = 2, psClass = "AccessPointControllerPS" },
	{ class = "Computer",            kind = "computer", label = "Computer",            ice = 1, psClass = "ComputerControllerPS" },
	{ class = "Terminal",            kind = "terminal", label = "Terminal",            ice = 1, psClass = "TerminalControllerPS" },
	{ class = "SecurityAlarm",       kind = "alarm",    label = "Security alarm",      ice = 2, psClass = "SecurityAlarmControllerPS" },
	{ class = "SensorDevice",        kind = "sensor",   label = "Sensor",              ice = 2, psClass = "SensorDeviceControllerPS" },
	{ class = "VendingMachine",      kind = "vending",  label = "Vending machine",     ice = 1, psClass = "VendingMachineControllerPS" },
	{ class = "ArcadeMachine",       kind = "arcade",   label = "Arcade machine",      ice = 1, psClass = "ArcadeMachineControllerPS" },
	{ class = "Jukebox",             kind = "jukebox",  label = "Jukebox",             ice = 1, psClass = "JukeboxControllerPS" },
	{ class = "TV",                  kind = "tv",       label = "TV",                  ice = 1, psClass = "TVControllerPS" },
	{ class = "Radio",               kind = "radio",    label = "Radio",               ice = 1, psClass = "RadioControllerPS" },
	{ class = "Speaker",             kind = "speaker",  label = "Speaker",             ice = 1, psClass = "SpeakerControllerPS" },
	{ class = "Intercom",            kind = "intercom", label = "Intercom",            ice = 1, psClass = "IntercomControllerPS" },
	{ class = "LcdScreen",           kind = "screen",   label = "Screen",              ice = 1, psClass = "LcdScreenControllerPS" },
	{ class = "BillboardDevice",     kind = "billboard", label = "Billboard",          ice = 1, psClass = "BillboardDeviceControllerPS" },
	{ class = "ElectricLight",       kind = "light",    label = "Light",               ice = 1, psClass = "ElectricLightControllerPS" },
	{ class = "Fan",                 kind = "fan",      label = "Fan",                 ice = 1, psClass = "FanControllerPS" },
	{ class = "FuseBox",             kind = "fusebox",  label = "Fuse box",            ice = 1, psClass = "FuseBoxControllerPS" },
	{ class = "SmartWindow",         kind = "window",   label = "Smart window",        ice = 1, psClass = "SmartWindowControllerPS" },
	{ class = "LiftDevice",          kind = "elevator", label = "Elevator",            ice = 1, psClass = "LiftControllerPS" },
	{ class = "Device",              kind = "device",   label = "Device",              ice = 1, psClass = "ScriptableDeviceComponentPS" },
}
-- controllers with no device of their own: whole security systems
local systemKinds = {
	{ psClass = "SecuritySystemControllerPS", kind = "security", label = "Security system", ice = 3 },
}

World.deviceKinds = deviceKinds

-- IsA that never throws, even for a class this game version doesn't have.
local function isA(obj, class)
	local ok, yes = pcall(function() return obj:IsA(class) end)
	return ok and yes == true
end

local function cleanName(name)
	if type(name) ~= "string" or name == "" then return nil end
	if name:find("^LocKey") then
		local ok, text = pcall(GetLocalizedText, name)
		name = ok and text or nil
	end
	if name == nil or name == "" or name:find("^LocKey") or #name > 40 then return nil end
	return name
end

local function positionOf(entity)
	local ok, p = pcall(function() return entity:GetWorldPosition() end)
	if ok and p then return { x = p.x, y = p.y, z = p.z } end
	return nil
end

-- A device entity as a plain table: { id, hash, kind, label, ice, pos }, or nil if it isn't one.
local function describeDevice(obj)
	for _, k in ipairs(deviceKinds) do
		if isA(obj, k.class) then
			local id = obj:GetEntityID()
			local info = { id = id, hash = tostring(id.hash), kind = k.kind, label = k.label, ice = k.ice, pos = positionOf(obj) }
			local ok, name = pcall(function() return obj:GetDevicePS():GetDeviceName() end)
			name = ok and cleanName(name)
			if name and name:lower() ~= k.label:lower() then info.label = k.label .. " - " .. name end
			return info
		end
	end
	return nil
end
World.describeDevice = describeDevice

-- Returns info about the device V is looking at, or nil and a reason.
function World.lookAtDevice()
	local result, err = try(function()
		local player = Game.GetPlayer()
		if player == nil then return nil end
		local obj = Game.GetTargetingSystem():GetLookAtObject(player, false, false)
		if obj == nil then return nil end
		return describeDevice(obj) or false
	end)
	if result == nil then return nil, err or "Look at a device first." end
	if result == false then return nil, "That isn't a device you can jack into." end
	return result
end

-- Every device within `radius` metres of V.
function World.devicesNear(radius)
	local list = try(function()
		local player = Game.GetPlayer()
		if player == nil then return {} end
		local query = Game["TSQ_ALL;"]()
		query.maxDistance = radius
		query.includeSecondaryTargets = false
		query.ignoreInstigator = true
		local ok, parts = Game.GetTargetingSystem():GetTargetParts(player, query)
		local out, seen = {}, {}
		if not ok or parts == nil then return out end
		for _, part in ipairs(parts) do
			local okEntity, entity = pcall(function() return part:GetComponent(part):GetEntity() end)
			if okEntity and entity then
				local info = describeDevice(entity)
				if info and not seen[info.hash] then
					seen[info.hash] = true
					table.insert(out, info)
				end
			end
		end
		return out
	end)
	return list or {}
end

-- Rebuilds a device's EntityID from its saved hash (devices remembered across loads).
function World.entityIdFromHash(hash)
	local digits = tostring(hash or ""):gsub("%D", "")
	if digits == "" then return nil end
	return try(function()
		return entEntityID.new({ hash = loadstring("return " .. digits .. "ULL", "")() })
	end)
end

---------------------------------------------------------------------------
-- Access points, security systems and the devices wired to them
---------------------------------------------------------------------------

-- Turns a device controller (PS) into the same shape lookAtDevice returns.
local function describePS(ps)
	local id = PersistentID.ExtractEntityID(ps:GetID())
	local info = { id = id, hash = tostring(id.hash), kind = "device", label = "Device", ice = 1 }
	local matched = false
	for _, k in ipairs(systemKinds) do
		if isA(ps, k.psClass) then info.kind, info.label, info.ice, matched = k.kind, k.label, k.ice, true break end
	end
	if not matched then
		for _, k in ipairs(deviceKinds) do
			if isA(ps, k.psClass) then info.kind, info.label, info.ice = k.kind, k.label, k.ice break end
		end
	end
	local ok, name = pcall(function() return ps:GetDeviceName() end)
	name = ok and cleanName(name)
	if name and name:lower() ~= info.label:lower() then info.label = info.label .. " - " .. name end
	local entity = Game.FindEntityByID(id)
	if entity then info.pos = positionOf(entity) end
	return info
end

local function parentsOf(device)
	if device.id == nil then return {} end
	return try(function()
		local out = {}
		for _, ps in ipairs(Game.GetDeviceSystem():GetParents(device.id) or {}) do table.insert(out, ps) end
		return out
	end) or {}
end

-- The access point a device is wired to (or the device itself if it is one), or nil.
function World.accessPointFor(device)
	if device.kind == "access" then return device end
	for _, ps in ipairs(parentsOf(device)) do
		if isA(ps, "AccessPointControllerPS") then return try(describePS, ps) end
	end
	return nil
end

-- Whatever else a device is wired to (a security system, a master switch, a
-- terminal running doors): the controller, as a device table, or nil.
function World.controllerFor(device)
	for _, ps in ipairs(parentsOf(device)) do
		if not isA(ps, "AccessPointControllerPS") then
			local info = try(describePS, ps)
			if info and info.hash ~= device.hash then return info end
		end
	end
	return nil
end

-- Every device wired to a controller (access point, security system, ...).
function World.devicesOn(controller)
	local list = try(function()
		local out = {}
		local children = Game.GetDeviceSystem():GetChildren(controller.id)
		for _, ps in ipairs(children or {}) do
			local info = describePS(ps)
			if info.kind ~= "access" then table.insert(out, info) end
		end
		return out
	end)
	return list or {}
end

local function entityFor(device)
	if device.id == nil and device.hash then device.id = World.entityIdFromHash(device.hash) end
	if device.id == nil then return nil, "The device is out of range." end
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
-- everything else electronic can at least be switched on and off
local genericPower = powerActions("Device")

local function actionsFor(kind)
	if kind == "access" or kind == "security" then return actions[kind] end
	return actions[kind] or genericPower
end

function World.deviceActionsFor(kind)
	local names = {}
	for name, _ in pairs(actionsFor(kind) or {}) do table.insert(names, name) end
	table.sort(names)
	return names
end

function World.deviceAction(device, action)
	local set = actionsFor(device.kind)
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
