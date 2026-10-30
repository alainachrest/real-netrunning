-- NetWatch: what heat actually does.
--
-- Threat levels by heat:
--   0-24  CLEAR    nothing happens
--   25-49 WATCHED  counter-netrunners occasionally enter networks you're in
--   50-74 HUNTED   agents show up often; NetWatch netrunners hack V in the world
--   75+   BURNED   agents everywhere; NetWatch tips off the NCPD as well
--
-- In the Net, an agent enters the network you're connected to, then attacks
-- your trace until you 'fight' it or disconnect. These agents are what will
-- hunt V in cyberspace later.

local Network = require("modules/network")
local Lore = require("modules/lore")
local World = require("modules/world")

local NetWatch = {
	bus = nil,
	print = function() end,    -- set by init to Shell.print
	addTrace = function() end, -- set by init to the shell's trace function
	agent = nil,               -- { name, level, addr, eta, attackTimer }
	spawnTimer = 0,
	worldTimer = 0,
	lockout = 0,               -- seconds left before the deck can breach again
	lastTier = nil,
	random = nil,              -- tests can force rolls
}

NetWatch.tiers = {
	{ name = "CLEAR",   min = 0 },
	{ name = "WATCHED", min = 25 },
	{ name = "HUNTED",  min = 50 },
	{ name = "BURNED",  min = 75 },
}

local agentNames = {
	"NetWatch agent K-17", "NetWatch agent Lumen", "NetWatch agent Varga", "NetWatch agent 0xDEAD",
	"NetWatch agent Saito", "NetWatch agent Mercer",
}

local function roll()
	return NetWatch.random and NetWatch.random() or math.random()
end

local function emit(event, data)
	if NetWatch.bus then NetWatch.bus.emit(event, data) end
end

local function settings()
	local s = Network.state
	if s.netwatch == nil then s.netwatch = { worldEffects = true, scrubbed = {}, agentsDefeated = 0 } end
	return s.netwatch
end

-- 0 CLEAR .. 3 BURNED
function NetWatch.tier(heat)
	heat = heat or (Network.state and Network.state.heat or 0)
	local tier = 0
	for i, t in ipairs(NetWatch.tiers) do
		if heat >= t.min then tier = i - 1 end
	end
	return tier
end

function NetWatch.tierName(tier)
	return NetWatch.tiers[(tier or NetWatch.tier()) + 1].name
end

---------------------------------------------------------------------------
-- Agents in the Net
---------------------------------------------------------------------------

local function spawnChance(tier)
	return ({ 0, 0.05, 0.15, 0.3 })[tier + 1]
end

local function makeAgent(net, tier)
	local org = Lore.getOrg(net.org)
	local name
	if org.kind == "corp" and roll() < 0.5 then
		name = org.name .. " counter-intel netrunner"
	else
		name = agentNames[math.floor(roll() * #agentNames) + 1]
	end
	return { name = name, level = math.min(6, tier + math.floor(net.ice / 2) + 1), addr = net.addr, eta = 8, attackTimer = 0 }
end

function NetWatch.onDisconnect()
	if NetWatch.agent then
		NetWatch.agent = nil
	end
end

local function updateAgent(dt, connected)
	local agent = NetWatch.agent
	if agent == nil then
		if connected == nil then return end
		NetWatch.spawnTimer = NetWatch.spawnTimer + dt
		if NetWatch.spawnTimer < 10 then return end
		NetWatch.spawnTimer = 0
		local tier = NetWatch.tier()
		local net = Network.get(connected)
		if net == nil or net.kind == "site" or roll() >= spawnChance(tier) then return end
		NetWatch.agent = makeAgent(net, tier)
		NetWatch.print("WARNING: " .. NetWatch.agent.name .. " is tracing into this network. 'fight' it when it arrives, or disconnect.", "err")
		World.warn("NetWatch incoming")
		emit("netwatch.agent_spawn", { addr = net.addr, name = NetWatch.agent.name, level = NetWatch.agent.level })
		return
	end

	if connected ~= agent.addr then
		NetWatch.agent = nil
		return
	end
	if agent.eta > 0 then
		agent.eta = agent.eta - dt
		if agent.eta <= 0 then
			NetWatch.print(agent.name .. " is in the network. Level " .. agent.level .. ". It's going after your trace.", "err")
			emit("netwatch.agent_arrived", { addr = agent.addr, name = agent.name, level = agent.level })
		end
		return
	end
	agent.attackTimer = agent.attackTimer + dt
	if agent.attackTimer >= 4 then
		agent.attackTimer = 0
		NetWatch.print(agent.name .. " hits your connection.", "err")
		NetWatch.addTrace(12)
	end
end

-- The agent in the network is beaten (by 'fight', or in person in cyberspace).
function NetWatch.win()
	local agent = NetWatch.agent
	if agent == nil then return false, "There's nobody here to fight." end
	NetWatch.agent = nil
	local s = settings()
	s.agentsDefeated = (s.agentsDefeated or 0) + 1
	local bounty = 150 * agent.level
	World.giveMoney(bounty)
	Network.addHeat(2, "derezzed " .. agent.name)
	Network.addNews("NetWatch confirms an agent was flatlined in the Net")
	emit("netwatch.agent_defeated", { addr = agent.addr, name = agent.name, level = agent.level })
	return true, "You derezzed " .. agent.name .. ". Its deck shards fence for " .. bounty .. " eddies. NetWatch noticed."
end

-- Returns ok, message.
function NetWatch.fight()
	local agent = NetWatch.agent
	if agent == nil then return false, "There's nobody here to fight." end
	if agent.eta > 0 then return false, agent.name .. " hasn't arrived yet. Disconnecting now would be easy." end
	local power = World.deckPower()
	local chance = math.max(0.1, math.min(0.9, 0.5 + 0.12 * (power - agent.level)))
	if roll() < chance then
		return NetWatch.win()
	end
	NetWatch.lockout = 20
	Network.addHeat(5, "lost to " .. agent.name)
	NetWatch.addTrace(20)
	emit("netwatch.agent_won", { addr = agent.addr, name = agent.name, level = agent.level })
	return false, agent.name .. " fried your deck. Breaching is locked out for 20 seconds."
end

---------------------------------------------------------------------------
-- In the world
---------------------------------------------------------------------------

local function worldAttack(tier)
	local s = settings()
	if not s.worldEffects or not World.isInGame() then return end
	if tier >= 2 and roll() < (tier == 3 and 0.35 or 0.25) then
		World.applyStatusEffect("BaseStatusEffect.PlayerElectrocuted")
		World.warn("NetWatch netrunner attack")
		Network.addNews("Witnesses report a netrunner attack on a merc in the street")
		emit("netwatch.world_attack", { tier = tier, kind = "shock" })
		if tier == 3 then
			World.reportToPolice()
			emit("netwatch.world_attack", { tier = tier, kind = "police" })
		end
	end
end

function NetWatch.update(dt, connected)
	if Network.state == nil then return end
	if NetWatch.lockout > 0 then NetWatch.lockout = math.max(0, NetWatch.lockout - dt) end

	local tier = NetWatch.tier()
	if NetWatch.lastTier ~= nil and tier ~= NetWatch.lastTier then
		local up = tier > NetWatch.lastTier
		local text = "NetWatch threat level: " .. NetWatch.tierName(tier)
		NetWatch.print(text, up and "err" or "ok")
		if up then World.warn(text) else World.notify(text) end
		if up and tier >= 2 then Network.addNews("NetWatch raises its alert on an unidentified netrunner") end
		emit("netwatch.tier", { tier = tier, name = NetWatch.tierName(tier), up = up })
	end
	NetWatch.lastTier = tier

	updateAgent(dt, connected)

	NetWatch.worldTimer = NetWatch.worldTimer + dt
	if NetWatch.worldTimer >= 120 then
		NetWatch.worldTimer = 0
		if connected == nil then worldAttack(tier) end
	end
end

---------------------------------------------------------------------------
-- Lowering heat
---------------------------------------------------------------------------

-- Wipe your traces from a network you own. Once per network.
function NetWatch.scrub(addr)
	local s = settings()
	if not Network.isOwned(addr) then return false, "You need root on this network to scrub its logs." end
	if s.scrubbed[addr] then return false, "You already scrubbed this network's logs." end
	s.scrubbed[addr] = true
	local net = Network.get(addr)
	local amount = 4 + (net and net.tier or 1) * 2
	Network.addHeat(-amount, "scrubbed " .. addr)
	return true, "Logs scrubbed. NetWatch heat -" .. amount .. "."
end

function NetWatch.setWorldEffects(on)
	settings().worldEffects = on
end

function NetWatch.worldEffects()
	return settings().worldEffects
end

function NetWatch.defeated()
	return settings().agentsDefeated or 0
end

function NetWatch.reset()
	NetWatch.agent, NetWatch.spawnTimer, NetWatch.worldTimer, NetWatch.lockout, NetWatch.lastTier = nil, 0, 0, 0, nil
end

return NetWatch
