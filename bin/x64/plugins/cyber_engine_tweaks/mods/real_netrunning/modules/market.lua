-- The Night City stock exchange, as Real Netrunning sees it. The exchange itself
-- (companies, prices, trading) is the CyberScript shared core's, so every mod
-- sees the same market; this adds what hacking does to it: leaks and breaches
-- move prices, stolen paydata can carry insider tips, and trading on a tip draws
-- NetWatch heat.

local Core = require("modules/core")
local Network = require("modules/network")
local Rng = require("modules/rng")

local Market = {
	bus = nil,
	companies = {},   -- the core's list of listed companies (set by attach)
}

local function core() return Core.get() and Core.get().market end

Market.tipLines = {
	up = {
		"%s quarterly numbers will beat forecasts. Announcement in the next session.",
		"%s board approved a buyback. Not public yet.",
		"%s won a NUSA contract. Press release is embargoed.",
	},
	down = {
		"%s is hiding losses from the Night City division. Auditors arrive soon.",
		"%s product recall incoming. Legal is drafting the statement now.",
		"%s lost a major contract. The news breaks shortly.",
	},
}

function Market.get(ticker) local m = core() return m and m.get(ticker) end
function Market.forOrg(org) local m = core() return m and m.forOrg(org) end
function Market.price(ticker) local m = core() return m and m.price(ticker) or 0 end
function Market.change(ticker) local m = core() return m and m.change(ticker) or 0 end
function Market.history(ticker) local m = core() return m and m.history(ticker) or {} end
function Market.held(ticker) local m = core() return m and m.held(ticker) or 0 end
function Market.shock(ticker, pct, why) local m = core() if m then m.shock(ticker, pct, why) end end
function Market.step() local m = core() if m then m.step() end end
function Market.portfolio() local m = core() if m == nil then return {}, 0 end return m.portfolio() end

function Market.buy(ticker, qty)
	local m = core()
	if m == nil then return false, "Market offline." end
	return m.buy(ticker, qty)
end

function Market.sell(ticker, qty)
	local m = core()
	if m == nil then return false, "Market offline." end
	return m.sell(ticker, qty)
end

-- The core moves the market on its own clock; nothing to do here.
function Market.update() end

---------------------------------------------------------------------------
-- Hacking and world events
---------------------------------------------------------------------------

-- Downloaded corporate paydata sometimes carries insider information.
function Market.onDownload(e)
	local m = core()
	local c = m and m.forOrg(e.org)
	local s = m and m.state()
	if c == nil or s == nil then return nil end
	m.shock(c.ticker, -0.01 * (e.tier or 1), "data leak")
	local rng = Rng.new(Network.state.seed or 0, "tip", e.addr, s.clock, e.value)
	if not rng:chance(0.5) then return nil end
	local up = rng:chance(0.5)
	local pct = (up and 1 or -1) * (0.06 + rng:next() * 0.08) * math.min(2, e.tier or 1)
	m.addTip(c.ticker, pct, rng:int(2, 4))
	local tip = rng:pick(up and Market.tipLines.up or Market.tipLines.down):format(c.name)
	return "INSIDER: " .. tip .. " (" .. c.ticker .. ")"
end

-- Leaking data to the press hits the company's price hard.
function Market.onLeak(org, tier)
	local m = core()
	local c = m and m.forOrg(org)
	if c == nil then return nil end
	m.shock(c.ticker, -(0.08 + 0.04 * (tier or 1)), "leak")
	Network.addNews(c.name .. " rocked by leaked internal data")
	return c
end

function Market.onBreach(e)
	local m = core()
	local c = m and m.forOrg(e.org)
	if c and e.success then m.shock(c.ticker, -0.005 * (e.tier or 1), "breach") end
end

-- CyberScript faction scores (e.g. a corp's standing) nudge related stocks.
function Market.onFactionScore(e)
	local m = core()
	if m == nil or type(e.old) ~= "number" or type(e.new) ~= "number" or e.new == e.old then return end
	local tag = tostring(e.faction):lower()
	for org, c in pairs(m.byOrg) do
		if tag:find(org, 1, true) then m.shock(c.ticker, (e.new > e.old) and 0.01 or -0.01, "faction") end
	end
end

-- Trading on an insider tip is noticed.
local function onTrade(e)
	if e.tipped then Network.addHeat(3, "suspicious trade in " .. e.ticker) end
	if Market.bus then Market.bus.emit("market.trade", e) end
end

function Market.attach(bus)
	if bus and not Market.busAttached then
		Market.busAttached = true
		Market.bus = bus
		bus.on("hack.breach", Market.onBreach)
		bus.on("world.faction_score", Market.onFactionScore)
	end
	local c = Core.get()
	if c and not Market.attached then
		Market.attached = true
		Market.companies = c.market.companies
		c.on("market.trade", onTrade)
		c.on("market.shock", function(e) if Market.bus then Market.bus.emit("market.shock", e) end end)
	end
end

return Market
