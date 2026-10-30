-- The Night City stock exchange. Prices drift, react to world events and to V's
-- hacking, and can be traded with real eddies. State lives in Network.state.market,
-- so each save has its own market.

local Network = require("modules/network")
local World = require("modules/world")
local Rng = require("modules/rng")

local Market = {
	bus = nil,
	tickEvery = 30,   -- seconds of play per market step
	timer = 0,
	feeRate = 0.01,   -- 1% per trade
}

-- Listed companies. org links a company to the lore organisation hacks affect.
Market.companies = {
	{ ticker = "ARA", name = "Arasaka",             org = "arasaka",    price = 820, vol = 0.012, rivals = { "MIL" } },
	{ ticker = "MIL", name = "Militech",            org = "militech",   price = 640, vol = 0.014, rivals = { "ARA" } },
	{ ticker = "KTC", name = "Kang Tao",            org = "kangtao",    price = 410, vol = 0.020, rivals = { "ARA" } },
	{ ticker = "TTI", name = "Trauma Team Int.",    org = "traumateam", price = 330, vol = 0.010 },
	{ ticker = "BTC", name = "Biotechnica",         price = 300, vol = 0.016 },
	{ ticker = "PTC", name = "Petrochem",           price = 260, vol = 0.015, rivals = { "SOV" } },
	{ ticker = "SOV", name = "SovOil",              price = 240, vol = 0.018, rivals = { "PTC" } },
	{ ticker = "ORB", name = "Orbital Air",         price = 390, vol = 0.013 },
	{ ticker = "KIR", name = "Kiroshi Opticals",    price = 180, vol = 0.022 },
	{ ticker = "ZTC", name = "Zetatech",            price = 150, vol = 0.024 },
	{ ticker = "N54", name = "Network 54",          org = "network54",  price = 140, vol = 0.020, rivals = { "WNS" } },
	{ ticker = "WNS", name = "World News Service",  price = 110, vol = 0.020, rivals = { "N54" } },
	{ ticker = "DLM", name = "Delamain",            price = 90,  vol = 0.025 },
}

local byTicker, byOrg = {}, {}
for _, c in ipairs(Market.companies) do
	byTicker[c.ticker] = c
	if c.org then byOrg[c.org] = c end
end

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

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

function Market.newState()
	local state = { clock = 0, prices = {}, history = {}, holdings = {}, cost = {}, shocks = {}, tips = {} }
	for _, c in ipairs(Market.companies) do
		state.prices[c.ticker] = c.price
		state.history[c.ticker] = { c.price }
	end
	return state
end

local function state()
	local s = Network.state
	if s == nil then return nil end
	if s.market == nil then s.market = Market.newState() end
	-- companies added in later versions
	for _, c in ipairs(Market.companies) do
		if s.market.prices[c.ticker] == nil then
			s.market.prices[c.ticker] = c.price
			s.market.history[c.ticker] = { c.price }
		end
	end
	return s.market
end

local function emit(event, data)
	if Market.bus then Market.bus.emit(event, data) end
end

function Market.get(ticker) return byTicker[tostring(ticker):upper()] end
function Market.forOrg(org) return byOrg[org] end

function Market.price(ticker)
	local s = state()
	return s and s.prices[ticker] or 0
end

-- Change over the last few steps, as a fraction.
function Market.change(ticker)
	local s = state()
	local h = s and s.history[ticker]
	if h == nil or #h < 2 then return 0 end
	local from = h[math.max(1, #h - 5)]
	return (h[#h] - from) / from
end

---------------------------------------------------------------------------
-- Price movement
---------------------------------------------------------------------------

-- A shock moves a price by pct, spread over the next few steps.
function Market.shock(ticker, pct, why)
	local s = state()
	if s == nil or byTicker[ticker] == nil then return end
	table.insert(s.shocks, { ticker = ticker, remaining = pct })
	-- rivals move a little the other way
	for _, rival in ipairs(byTicker[ticker].rivals or {}) do
		table.insert(s.shocks, { ticker = rival, remaining = -pct * 0.25 })
	end
	emit("market.shock", { ticker = ticker, pct = pct, why = why })
end

function Market.step()
	local s = state()
	if s == nil then return end
	s.clock = s.clock + 1
	local rng = Rng.new(Network.state.seed or 0, "market", s.clock)

	-- pending insider tips become public
	for i = #s.tips, 1, -1 do
		local tip = s.tips[i]
		if s.clock >= tip.due then
			table.remove(s.tips, i)
			Market.shock(tip.ticker, tip.pct, "news")
			Network.addNews(byTicker[tip.ticker].name .. (tip.pct > 0 and " shares jump on surprise news" or " shares slide on surprise news"))
		end
	end

	-- apply half of each shock per step
	local moves = {}
	for i = #s.shocks, 1, -1 do
		local shock = s.shocks[i]
		local part = shock.remaining * 0.5
		if math.abs(shock.remaining) < 0.002 then part = shock.remaining end
		moves[shock.ticker] = (moves[shock.ticker] or 0) + part
		shock.remaining = shock.remaining - part
		if math.abs(shock.remaining) < 0.0005 then table.remove(s.shocks, i) end
	end

	for _, c in ipairs(Market.companies) do
		local price = s.prices[c.ticker]
		-- noise, a slight pull back towards the listing price, and shocks
		local noise = (rng:next() * 2 - 1) * c.vol
		local revert = (c.price - price) / c.price * 0.01
		local move = noise + revert + (moves[c.ticker] or 0)
		price = math.max(1, math.floor(price * (1 + move) * 100 + 0.5) / 100)
		s.prices[c.ticker] = price
		local h = s.history[c.ticker]
		table.insert(h, price)
		while #h > 30 do table.remove(h, 1) end
	end
end

function Market.update(dt)
	if state() == nil then return end
	Market.timer = Market.timer + dt
	if Market.timer >= Market.tickEvery then
		Market.timer = 0
		Market.step()
	end
end

---------------------------------------------------------------------------
-- Trading
---------------------------------------------------------------------------

local function tipped(ticker)
	local s = state()
	for _, tip in ipairs(s.tips) do
		if tip.ticker == ticker then return true end
	end
	return false
end

-- Returns ok, message.
function Market.buy(ticker, qty)
	local s = state()
	local c = Market.get(ticker)
	qty = math.floor(tonumber(qty) or 0)
	if s == nil then return false, "Market offline." end
	if c == nil then return false, "Unknown ticker '" .. tostring(ticker) .. "'." end
	if qty <= 0 then return false, "Quantity must be at least 1." end
	local price = s.prices[c.ticker]
	local total = math.ceil(price * qty * (1 + Market.feeRate))
	if not World.spendMoney(total) then
		return false, "Not enough eddies: " .. qty .. " " .. c.ticker .. " costs " .. total .. "."
	end
	local held = s.holdings[c.ticker] or 0
	s.cost[c.ticker] = ((s.cost[c.ticker] or 0) * held + price * qty) / (held + qty)
	s.holdings[c.ticker] = held + qty
	if tipped(c.ticker) then
		Network.addHeat(3, "suspicious trade in " .. c.ticker)
	end
	emit("market.trade", { side = "buy", ticker = c.ticker, qty = qty, price = price })
	return true, string.format("Bought %d %s at %.2f for %d eddies (fee included).", qty, c.ticker, price, total)
end

function Market.sell(ticker, qty)
	local s = state()
	local c = Market.get(ticker)
	if s == nil then return false, "Market offline." end
	if c == nil then return false, "Unknown ticker '" .. tostring(ticker) .. "'." end
	local held = s.holdings[c.ticker] or 0
	qty = (qty == "all") and held or math.floor(tonumber(qty) or 0)
	if qty <= 0 then return false, "Quantity must be at least 1." end
	if qty > held then return false, "You only hold " .. held .. " " .. c.ticker .. "." end
	local price = s.prices[c.ticker]
	local total = math.floor(price * qty * (1 - Market.feeRate))
	s.holdings[c.ticker] = held - qty
	if s.holdings[c.ticker] == 0 then
		s.holdings[c.ticker] = nil
		s.cost[c.ticker] = nil
	end
	World.giveMoney(total)
	if tipped(c.ticker) then
		Network.addHeat(3, "suspicious trade in " .. c.ticker)
	end
	emit("market.trade", { side = "sell", ticker = c.ticker, qty = qty, price = price })
	return true, string.format("Sold %d %s at %.2f for %d eddies (fee included).", qty, c.ticker, price, total)
end

function Market.portfolio()
	local s = state()
	local rows, value = {}, 0
	if s == nil then return rows, 0 end
	for _, c in ipairs(Market.companies) do
		local qty = s.holdings[c.ticker]
		if qty then
			local worth = qty * s.prices[c.ticker]
			value = value + worth
			table.insert(rows, { ticker = c.ticker, name = c.name, qty = qty, price = s.prices[c.ticker],
				cost = s.cost[c.ticker] or 0, worth = worth })
		end
	end
	return rows, value
end

---------------------------------------------------------------------------
-- Hacking and world events
---------------------------------------------------------------------------

-- Downloaded corporate paydata sometimes carries insider information.
function Market.onDownload(e)
	local c = byOrg[e.org]
	local s = state()
	if c == nil or s == nil then return nil end
	Market.shock(c.ticker, -0.01 * (e.tier or 1), "data leak")
	local rng = Rng.new(Network.state.seed or 0, "tip", e.addr, s.clock, e.value)
	if not rng:chance(0.5) then return nil end
	local up = rng:chance(0.5)
	local pct = (up and 1 or -1) * (0.06 + rng:next() * 0.08) * math.min(2, e.tier or 1)
	table.insert(s.tips, { ticker = c.ticker, pct = pct, due = s.clock + rng:int(2, 4) })
	local tip = rng:pick(up and Market.tipLines.up or Market.tipLines.down):format(c.name)
	return "INSIDER: " .. tip .. " (" .. c.ticker .. ")"
end

-- Leaking data to the press hits the company's price hard.
function Market.onLeak(org, tier)
	local c = byOrg[org]
	if c == nil then return nil end
	local pct = -(0.08 + 0.04 * (tier or 1))
	Market.shock(c.ticker, pct, "leak")
	Network.addNews(c.name .. " rocked by leaked internal data")
	return c
end

function Market.onBreach(e)
	local c = byOrg[e.org]
	if c and e.success then Market.shock(c.ticker, -0.005 * (e.tier or 1), "breach") end
end

-- CyberScript faction scores (e.g. a corp's standing) nudge related stocks.
function Market.onFactionScore(e)
	if type(e.old) ~= "number" or type(e.new) ~= "number" or e.new == e.old then return end
	local tag = tostring(e.faction):lower()
	for org, c in pairs(byOrg) do
		if tag:find(org, 1, true) then
			Market.shock(c.ticker, (e.new > e.old) and 0.01 or -0.01, "faction")
		end
	end
end

function Market.attach(bus)
	Market.bus = bus
	bus.on("hack.breach", Market.onBreach)
	bus.on("world.faction_score", Market.onFactionScore)
end

return Market
