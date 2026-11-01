-- Territory: who holds which network, and the fighting over them.
--
-- Gangs and corporations take networks from each other as time passes, and they
-- come for the ones V holds too. A network V loses has to be breached again from
-- the lobby. V defends their networks three ways:
--   harden <level>   install V's own ICE (eddies)
--   guard <kind>     hire a netrunner to sit on it for a while (eddies)
--   defend           fight the attackers off live from the deck; or jack in, and
--                    every raider derezzed in cyberspace weakens the attack
-- Taking a network from a faction costs standing with it (and wins a little with
-- its rivals); the factions V has crossed are the ones most likely to come for V.
--
-- Everything that changes is kept in Network.state.territory, so it's saved.
-- Time only counts while the game is running (init doesn't update while paused).

local Network = require("modules/network")
local Lore = require("modules/lore")
local World = require("modules/world")
local Core = require("modules/core")

local Territory = {
	worldEvery = 180,      -- seconds of play between factions starting a takeover somewhere
	worldWindow = 240,     -- how long a takeover between factions takes to play out
	worldMax = 3,          -- takeovers between factions at once
	raidMin = 3600,        -- seconds of play between raids on V's networks (min, max)
	raidMax = 7200,
	raidWindow = 300,      -- how long V has to respond to a raid
	guardEvery = 30,       -- how often a hired guard pushes back during a raid
	guardTerm = 7200,      -- seconds of play a guard contract lasts
	maxIce = 6,
	guards = {
		basic = { power = 2, cost = 1200, name = "a freelance netrunner" },
		elite = { power = 4, cost = 3500, name = "an Afterlife netrunner" },
	},
	-- who fights whom first
	rivals = {
		valentinos = { "sixthstreet", "tygerclaws" },
		sixthstreet = { "valentinos", "maelstrom", "aldecaldos" },
		maelstrom = { "tygerclaws", "sixthstreet", "scavengers" },
		tygerclaws = { "maelstrom", "valentinos", "mox" },
		mox = { "tygerclaws", "scavengers" },
		scavengers = { "mox", "maelstrom" },
		animals = { "voodooboys" },
		voodooboys = { "animals", "barghest" },
		wraiths = { "aldecaldos" },
		aldecaldos = { "wraiths", "sixthstreet" },
		barghest = { "voodooboys", "militech" },
		ncpd = { "maelstrom", "tygerclaws", "valentinos", "sixthstreet", "animals", "scavengers", "voodooboys" },
		rocklin = { "dynalar", "zhirafa" },
		dynalar = { "rocklin", "kiroshi" },
		zhirafa = { "rocklin", "sovoil" },
		segatari = { "zetatech", "kiroshi" },
		midnightarms = { "constitutionalarms", "budgetarms" },
		constitutionalarms = { "midnightarms", "darra" },
		budgetarms = { "midnightarms", "darra" },
		darra = { "tsunami", "budgetarms" },
		tsunami = { "darra", "militech", "arasaka" },
		arasaka = { "militech", "kangtao" },
		militech = { "arasaka", "kangtao", "barghest" },
		kangtao = { "arasaka", "militech" },
		biotechnica = { "petrochem" },
		petrochem = { "biotechnica", "sovoil" },
		sovoil = { "petrochem" },
		kiroshi = { "zetatech" },
		zetatech = { "kiroshi" },
	},
	print = function() end, -- set by init (the deck screen)
	bus = nil,
	random = nil,          -- tests replace this
	busy = function() return false end, -- set by init: true for the network V is working right now
	worldTimer = 0,
	guardTimer = 0,
}

local function roll() return Territory.random and Territory.random() or math.random() end
local function rint(lo, hi) return lo + math.floor(roll() * (hi - lo + 1)) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function out(text, kind) Territory.print(text, kind or "out") end
local function emit(event, data) if Territory.bus then Territory.bus.emit(event, data) end end

function Territory.state()
	local s = Network.state
	s.territory = s.territory or {}
	local t = s.territory
	t.control = t.control or {}   -- addr -> org holding it, when that isn't its original operator
	t.defense = t.defense or {}   -- addr -> { ice, guard = { kind, power, name, untilClock } } for V's networks
	t.attacks = t.attacks or {}   -- addr -> { attacker, power, left, raid, holder, id, helped }
	t.taken = t.taken or {}       -- addr -> the org V took it from
	t.since = t.since or {}       -- addr -> clock when it last changed hands
	t.clock = t.clock or 0        -- seconds of play
	return t
end

---------------------------------------------------------------------------
-- Who holds what
---------------------------------------------------------------------------

local FACTION_KINDS = { gang = true, corp = true }

-- Every network is fought over except the public subnet and V's home network.
function Territory.contestable(net)
	if net == nil or net.hub or net.addr == "nc.subnet.public" then return false end
	return net.addr:find("^home%.") == nil
end

-- Gangs work Night City's streets (closed networks are in the city too).
local function inGangReach(net) return net.region == "nc" or net.region == "closed" end
-- gangs and the NCPD only work Night City
local function cityBound(id, org) return org.kind == "gang" or id == "ncpd" end

function Territory.holder(addr)
	if Network.isOwned(addr) then return "player" end
	local net = Network.get(addr)
	return Territory.state().control[addr] or (net and net.org)
end

function Territory.holderName(id)
	if id == "player" then return "you" end
	return Lore.getOrg(id).name
end

-- Every gang and corporation (other mods' too, through the shared core).
function Territory.factions()
	local list, seen = {}, {}
	local c = Core.get()
	if c then
		for _, kind in ipairs({ "gang", "corp" }) do
			for _, org in ipairs(c.orgs.all(kind)) do
				if not seen[org.id] then seen[org.id] = true table.insert(list, org.id) end
			end
		end
	end
	for id, org in pairs(Lore.orgs) do
		if FACTION_KINDS[org.kind] and not seen[id] then seen[id] = true table.insert(list, id) end
	end
	-- the NCPD fights for the streets too
	if not seen.ncpd then table.insert(list, "ncpd") end
	table.sort(list)
	return list
end

local function isRival(a, b)
	for _, r in ipairs(Territory.rivals[a] or {}) do if r == b then return true end end
	return false
end

function Territory.strength(orgId)
	local org = Lore.getOrg(orgId)
	local ice = org.ice or { 1, 2 }
	return math.floor((ice[1] + ice[2]) / 2) + 1
end

function Territory.defense(addr)
	local net = Network.get(addr)
	if net == nil then return 0 end
	if Network.isOwned(addr) then
		local d = Territory.state().defense[addr]
		local guard = d and d.guard
		return (d and d.ice or 0) + (guard and guard.power or 0)
	end
	return net.ice + (net.tier - 1)
end

function Territory.attackOn(addr) return Territory.state().attacks[addr] end

-- How many contestable networks each holder has: { [holder] = n }
function Territory.counts()
	local counts = {}
	for _, addr in ipairs(Network.order) do
		local net = Network.get(addr)
		if Territory.contestable(net) then
			local h = Territory.holder(addr)
			counts[h] = (counts[h] or 0) + 1
		end
	end
	return counts
end

function Territory.playerNetworks()
	local list = {}
	for _, addr in ipairs(Network.order) do
		local net = Network.get(addr)
		if Network.isOwned(addr) and Territory.contestable(net) then table.insert(list, net) end
	end
	return list
end

---------------------------------------------------------------------------
-- Standing (the shared core's)
---------------------------------------------------------------------------

local function standing(org, amount, why)
	local c = Core.get()
	if c == nil or org == nil or org == "player" then return end
	if not FACTION_KINDS[Lore.getOrg(org).kind] and Lore.getOrg(org).kind ~= "media" and org ~= "netwatch" and org ~= "ncpd" then return end
	c.standing.change(org, amount, why)
end

local function standingOf(org)
	local c = Core.get()
	return c and c.standing.get(org) or 0
end

---------------------------------------------------------------------------
-- Changing hands
---------------------------------------------------------------------------

local function transfer(addr, to, from)
	local t = Territory.state()
	local net = Network.get(addr)
	if net == nil then return end
	if from == "player" then
		Network.state.owned[addr] = nil
		t.defense[addr] = nil
		t.taken[addr] = nil
		World.warn(net.name .. " lost to " .. Territory.holderName(to))
		local whoTook = to == "rogueai" and "A rogue AI" or Territory.holderName(to)
		out(whoTook .. " took " .. net.name .. " (" .. addr .. ") from you. You'll have to breach it again from the lobby.", "err")
		Network.addNews(to == "rogueai" and ("Something from beyond the Blackwall has taken over " .. net.name)
			or to == "netwatch" and ("NetWatch seizes " .. net.name .. " from an unknown netrunner")
			or (Territory.holderName(to) .. " netrunners seize " .. net.name .. " back from an unknown intruder"))
	elseif to == "rogueai" then
		Network.addNews("Something from beyond the Blackwall has taken over " .. net.name .. ". " .. Territory.holderName(from) .. " lost all contact.")
	elseif to == "netwatch" then
		Network.addNews("NetWatch quarantines " .. net.name .. (from == "rogueai" and " after purging a rogue AI" or (", seized from " .. Territory.holderName(from))))
	else
		Network.addNews(Territory.holderName(to) .. " netrunners seize " .. net.name .. " from " .. Territory.holderName(from))
	end
	-- the new holder rebuilds the ICE: any way V had in is gone
	Network.state.depth[addr] = nil
	t.control[addr] = (to ~= net.org) and to or nil
	t.since[addr] = t.clock
	emit("territory.taken", { addr = addr, to = to, from = from })
	local c = Core.get()
	if c and c.emit then pcall(c.emit, "network.taken", { addr = addr, to = to, from = from, by = "realnetrunning" }) end
end

local function endAttack(addr, a, outcome)
	local t = Territory.state()
	t.attacks[addr] = nil
	local net = Network.get(addr)
	local name = net and net.name or addr
	if outcome == "repelled" then
		if a.raid then
			out("You held " .. name .. " against " .. Territory.holderName(a.attacker) .. ".", "ok")
			World.notify("Held " .. name)
			standing(a.attacker, -1, "V fought off their raid on " .. addr)
			local d = t.defense[addr]
			if d and d.guard and roll() < 0.15 then
				out("Your guard, " .. d.guard.name .. ", was flatlined holding the line. The contract's over.", "err")
				d.guard = nil
			end
		else
			if a.helped then
				out(Territory.holderName(a.holder) .. " held " .. name .. " against " .. Territory.holderName(a.attacker) .. ", with your help.", "ok")
				standing(a.holder, 2, "V helped defend " .. addr)
				standing(a.attacker, -2, "V broke their attack on " .. addr)
			end
			if roll() < 0.5 then
				Network.addNews(Territory.holderName(a.holder) .. " fight off a " .. Territory.holderName(a.attacker) .. " attack on " .. name)
			end
		end
		emit("territory.held", { addr = addr, attacker = a.attacker, holder = a.holder, raid = a.raid })
	else
		if a.raid then
			local d = t.defense[addr]
			if d and d.guard then out("Your guard, " .. d.guard.name .. ", didn't make it out.", "err") end
		end
		transfer(addr, a.attacker, a.raid and "player" or a.holder)
	end
end

-- The attack is over: did the attackers get through?
local function resolve(addr, a)
	if a.power <= 0 then return endAttack(addr, a, "repelled") end
	local chance = clamp(0.5 + 0.12 * (a.power - Territory.defense(addr)), 0.05, 0.95)
	endAttack(addr, a, roll() < chance and "taken" or "repelled")
end

-- Knocks an attack back (V defending from the deck, or raiders derezzed in
-- cyberspace). Returns the attack, or nil if it broke.
function Territory.weaken(addr, amount, how)
	local a = Territory.state().attacks[addr]
	if a == nil then return nil end
	a.power = a.power - amount
	if not a.raid then a.helped = true end
	if a.power <= 0 then
		endAttack(addr, a, "repelled")
		return nil
	end
	return a
end

local function startAttack(addr, attacker, raid)
	local t = Territory.state()
	local net = Network.get(addr)
	local a = {
		attacker = attacker, holder = Territory.holder(addr), raid = raid,
		power = Territory.strength(attacker) + (net.tier - 1) + rint(0, 2),
		left = raid and Territory.raidWindow or Territory.worldWindow,
		id = string.format("%s:%d", addr, math.floor(t.clock)),
	}
	t.attacks[addr] = a
	emit("territory.attack", { addr = addr, attacker = attacker, holder = a.holder, raid = raid })
	return a
end

---------------------------------------------------------------------------
-- Factions against each other
---------------------------------------------------------------------------

local function weightedPick(options)
	local total = 0
	for _, o in ipairs(options) do total = total + o.w end
	if total <= 0 then return nil end
	local r = roll() * total
	for _, o in ipairs(options) do
		r = r - o.w
		if r <= 0 then return o end
	end
	return options[#options]
end

function Territory.worldTick()
	local t = Territory.state()
	local active = 0
	for _, a in pairs(t.attacks) do if not a.raid then active = active + 1 end end
	if active >= Territory.worldMax then return nil end
	-- now and then it's NetWatch or a rogue AI; an AI that's already loose
	-- spreads faster, and NetWatch comes down hard on networks an AI holds
	local counts = Territory.counts()
	local ai = counts.rogueai or 0
	local r = roll()
	local special
	if r < 0.04 + 0.03 * math.min(ai, 5) then special = "rogueai"
	elseif r < 0.12 + 0.03 * math.min(ai, 5) + 0.04 * math.min(ai, 5) then special = "netwatch" end
	if special then return Territory.specialTick(special) end
	local factions = Territory.factions()
	if #factions == 0 then return nil end
	local attacker = factions[rint(1, #factions)]
	local org = Lore.getOrg(attacker)
	local options = {}
	for _, addr in ipairs(Network.order) do
		local net = Network.get(addr)
		local holder = Territory.holder(addr)
		if Territory.contestable(net) and holder ~= attacker and holder ~= "player" and t.attacks[addr] == nil
			and not Territory.busy(addr) and (not cityBound(attacker, org) or inGangReach(net)) then
			-- gangs mostly fight gangs over the streets; corps mostly fight corps
			local hk = Lore.getOrg(holder).kind
			local w
			if isRival(attacker, holder) then w = 4
			elseif attacker == "ncpd" then w = (hk == "gang" and 3) or (holder == "rogueai" and 2) or ((hk == "civilian" or hk == "device") and 0.5) or 0.1
			elseif org.kind == "gang" then w = (hk == "gang" and 1) or (holder == "ncpd" and 1) or ((hk == "civilian" or hk == "device") and 2) or 0.3
			else w = ((hk == "corp" or hk == "media") and 1) or (hk == "gang" and 0.4) or 0.3 end
			if net.tier >= 3 then w = w * 0.2 end
			table.insert(options, { addr = addr, w = w })
		end
	end
	local pick = weightedPick(options)
	if pick == nil then return nil end
	return pick.addr, startAttack(pick.addr, attacker, false)
end

-- NetWatch quarantines networks (rogue AI first, then gang networks); a rogue AI
-- takes anything, big corporate networks most of all, anywhere in the world.
function Territory.specialTick(attacker)
	local t = Territory.state()
	local options = {}
	for _, addr in ipairs(Network.order) do
		local net = Network.get(addr)
		local holder = Territory.holder(addr)
		if Territory.contestable(net) and holder ~= attacker and holder ~= "player" and t.attacks[addr] == nil
			and not Territory.busy(addr) then
			local hk = Lore.getOrg(holder).kind
			local w
			if attacker == "netwatch" then
				w = (holder == "rogueai" and 20) or (hk == "gang" and 1) or (hk == "civilian" and 0.2) or 0.1
			else
				w = ((hk == "corp" or hk == "media") and 1.5) or 1
				if holder == "netwatch" then w = 0.3 end
			end
			table.insert(options, { addr = addr, w = w })
		end
	end
	local pick = weightedPick(options)
	if pick == nil then return nil end
	return pick.addr, startAttack(pick.addr, attacker, false)
end

-- NetWatch hands quarantined networks back to their operators after a while.
Territory.quarantine = 4 * 3600
local function releaseQuarantines()
	local t = Territory.state()
	for addr, holder in pairs(t.control) do
		local since = t.since[addr] or t.clock
		if holder == "netwatch" and t.clock - since >= Territory.quarantine and t.attacks[addr] == nil then
			local net = Network.get(addr)
			t.control[addr] = nil
			Network.state.depth[addr] = nil
			if net then Network.addNews("NetWatch lifts its quarantine on " .. net.name .. ", handing it back to " .. Territory.holderName(net.org)) end
			emit("territory.taken", { addr = addr, to = net and net.org, from = "netwatch" })
		end
	end
end

---------------------------------------------------------------------------
-- Raids on V's networks
---------------------------------------------------------------------------

function Territory.raidTick()
	local t = Territory.state()
	local mine = Territory.playerNetworks()
	if #mine == 0 then t.nextRaid = nil return nil end
	if t.nextRaid == nil then t.nextRaid = t.clock + rint(Territory.raidMin, Territory.raidMax) return nil end
	if t.clock < t.nextRaid then return nil end
	t.nextRaid = t.clock + rint(Territory.raidMin, Territory.raidMax)
	return Territory.startRaid()
end

-- Starts a raid on one of V's networks now (also used by tests and debug).
function Territory.startRaid(addr)
	local t = Territory.state()
	local options = {}
	for _, net in ipairs(Territory.playerNetworks()) do
		if t.attacks[net.addr] == nil and (addr == nil or net.addr == addr) then table.insert(options, net) end
	end
	if #options == 0 then return nil end
	local net = options[rint(1, #options)]
	-- whoever V took it from wants it back; otherwise the factions V has crossed most
	local attacker = t.taken[net.addr]
	local avenger = attacker and (FACTION_KINDS[Lore.getOrg(attacker).kind] or attacker == "netwatch" or attacker == "rogueai" or attacker == "ncpd")
	if not avenger or roll() >= 0.6 then
		local list = {}
		for _, id in ipairs(Territory.factions()) do
			local o = Lore.getOrg(id)
			if not cityBound(id, o) or inGangReach(net) then
				table.insert(list, { id = id, w = 1 + math.max(0, -standingOf(id)) / 10 })
			end
		end
		-- NetWatch comes for V's networks the hotter V is; a rogue AI, rarely, for anyone's
		table.insert(list, { id = "netwatch", w = Network.heat() / 15 })
		table.insert(list, { id = "rogueai", w = 0.3 })
		local pick = weightedPick(list)
		attacker = pick and pick.id or attacker
	end
	if attacker == nil then return nil end
	local a = startAttack(net.addr, attacker, true)
	local who = Territory.holderName(attacker)
	World.warn(who .. " are attacking " .. net.name)
	local who2 = attacker == "rogueai" and "A rogue AI is" or attacker == "netwatch" and "NetWatch agents are" or (who .. " netrunners are")
	out(string.format("RAID: %s attacking %s (%s). You have %d minutes. 'defend' from the deck, jack in and fight them, or trust your ICE (%d) and guards.",
		who2, net.name, net.addr, math.floor(Territory.raidWindow / 60), Territory.defense(net.addr)), "err")
	return net.addr, a
end

---------------------------------------------------------------------------
-- V's defences
---------------------------------------------------------------------------

-- Eddies to raise V's ICE on a network from `from` to `to`.
function Territory.iceCost(net, from, to)
	local cost = 0
	for level = from + 1, to do cost = cost + 300 * level * level * net.tier end
	return cost
end

function Territory.installedIce(addr)
	local d = Territory.state().defense[addr]
	return d and d.ice or 0
end

-- Returns ok, message.
function Territory.harden(addr, level)
	local net = Network.get(addr)
	if not (Network.isOwned(addr) and Territory.contestable(net)) then return false, "You can only harden networks you hold that others fight over." end
	local t = Territory.state()
	local current = Territory.installedIce(addr)
	if level <= current then return false, "Your ICE here is already level " .. current .. "." end
	if level > Territory.maxIce then return false, "ICE only goes up to " .. Territory.maxIce .. "." end
	local cost = Territory.iceCost(net, current, level)
	if not World.spendMoney(cost) then return false, "That costs " .. cost .. " eddies. You don't have enough." end
	t.defense[addr] = t.defense[addr] or {}
	t.defense[addr].ice = level
	return true, string.format("Installed level %d ICE on %s for %d eddies.", level, net.name, cost)
end

function Territory.guardCost(net, kind)
	local g = Territory.guards[kind]
	return g and g.cost * net.tier or nil
end

function Territory.hireGuard(addr, kind)
	local net = Network.get(addr)
	if not (Network.isOwned(addr) and Territory.contestable(net)) then return false, "You can only guard networks you hold that others fight over." end
	local g = Territory.guards[kind]
	if g == nil then return false, "Guards: 'basic' or 'elite'." end
	local cost = Territory.guardCost(net, kind)
	if not World.spendMoney(cost) then return false, "That costs " .. cost .. " eddies. You don't have enough." end
	local t = Territory.state()
	t.defense[addr] = t.defense[addr] or {}
	t.defense[addr].guard = { kind = kind, power = g.power, name = g.name, untilClock = t.clock + Territory.guardTerm }
	return true, string.format("Hired %s to guard %s for %d hours of play (%d eddies).", g.name, net.name, Territory.guardTerm / 3600, cost)
end

function Territory.dismissGuard(addr)
	local d = Territory.state().defense[addr]
	if d == nil or d.guard == nil then return false, "No guard on this network." end
	d.guard = nil
	return true, "Guard dismissed."
end

---------------------------------------------------------------------------
-- Events and time
---------------------------------------------------------------------------

-- V took a network: it's theirs now, and its old holder won't forget it.
function Territory.onBreached(e)
	if Network.state == nil then return end
	local net = Network.get(e.addr)
	if not Territory.contestable(net) then return end
	local t = Territory.state()
	local from = t.control[e.addr] or net.org
	t.control[e.addr] = nil
	t.taken[e.addr] = from
	if t.attacks[e.addr] and not t.attacks[e.addr].raid then
		out("You took " .. net.name .. " out from under " .. Territory.holderName(t.attacks[e.addr].attacker) .. ".", "warn")
		t.attacks[e.addr] = nil
	end
	local org = Lore.getOrg(from)
	if from == "netwatch" then
		standing("netwatch", -(4 + net.tier), "V broke a NetWatch quarantine on " .. e.addr)
		Network.addHeat(10, "broke a NetWatch quarantine on " .. e.addr)
		out("You broke NetWatch's quarantine on " .. net.name .. ". They'll want it back, and you.", "err")
	elseif from == "rogueai" then
		standing("netwatch", 2, "V purged a rogue AI from " .. e.addr)
		Network.addNews("Unknown netrunner purges a rogue AI from " .. net.name)
		out("You've torn the rogue AI out of " .. net.name .. ". Whatever's left of it may try to come back.", "ok")
	elseif FACTION_KINDS[org.kind] or org.kind == "media" or from == "ncpd" then
		standing(from, -(2 + net.tier), "V took " .. e.addr)
		for _, r in ipairs(Territory.rivals[from] or {}) do standing(r, 1, "V hit their rival " .. from) end
		out(org.name .. " won't forget you took " .. net.name .. ". Expect them to come for it.", "warn")
	end
	if t.nextRaid == nil then t.nextRaid = t.clock + rint(Territory.raidMin, Territory.raidMax) end
end

function Territory.reset()
	Territory.worldTimer, Territory.guardTimer = 0, 0
end

function Territory.update(dt)
	if Network.state == nil then return end
	local t = Territory.state()
	t.clock = t.clock + dt

	-- guard contracts run out
	for addr, d in pairs(t.defense) do
		if d.guard and t.clock >= d.guard.untilClock then
			local net = Network.get(addr)
			out("Your guard's contract on " .. (net and net.name or addr) .. " is up.", "warn")
			d.guard = nil
		end
	end

	Territory.worldTimer = Territory.worldTimer + dt
	if Territory.worldTimer >= Territory.worldEvery then
		Territory.worldTimer = 0
		Territory.worldTick()
	end
	Territory.raidTick()
	releaseQuarantines()

	Territory.guardTimer = Territory.guardTimer + dt
	local guardTurn = Territory.guardTimer >= Territory.guardEvery
	if guardTurn then Territory.guardTimer = 0 end

	local addrs = {}
	for addr in pairs(t.attacks) do table.insert(addrs, addr) end
	table.sort(addrs)
	for _, addr in ipairs(addrs) do
		local a = t.attacks[addr]
		if a then
			-- the network changed hands some other way (V took it, say)
			if (a.raid and not Network.isOwned(addr)) or (not a.raid and Network.isOwned(addr)) then
				t.attacks[addr] = nil
			else
				a.left = a.left - dt
				local d = a.raid and t.defense[addr]
				if guardTurn and d and d.guard and roll() < 0.5 then
					a.power = a.power - 1
					if a.power > 0 then out("Your guard on " .. Network.get(addr).name .. " pushed the attackers back.", "ok") end
				end
				if a.power <= 0 then endAttack(addr, a, "repelled")
				elseif a.left <= 0 then resolve(addr, a) end
			end
		end
	end
end

return Territory
