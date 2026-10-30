-- Pages for the desktop Browser app. A page is { title, url, lines }, where each
-- line is { text, link, kind }. kind: "text", "title", "link", "good", "bad", "note".
--
-- Addresses:
--   nc://home              portal
--   nc://directory         every network your deck knows about
--   nc://news              recent events
--   net://<address>        a network's public site (and its files once breached)
--   market://              the stock exchange; market://<TICKER> for one company
--   do://buy/<T>/<qty>     actions; the result is shown on the page they return to
--   do://sell/<T>/<qty|all>

local Network = require("modules/network")
local Lore = require("modules/lore")
local Market = require("modules/market")
local World = require("modules/world")

local Web = {}

-- Public site text for organisations, written in-world.
local blurbs = {
	arasaka = "Arasaka Corporation. Security, banking, manufacturing. Protecting what matters since 1915.",
	militech = "Militech International Armaments. Defending the New United States and its partners.",
	kangtao = "Kang Tao. Smart weapons and civilian technology for a new century.",
	traumateam = "Trauma Team International. Platinum coverage: a medevac at your door in under three minutes.",
	network54 = "Network 54. The news that matters, when it matters.",
	ncpd = "Night City Police Department. To protect and serve. Report crimes on any public terminal.",
	maelstrom = "This page is not for you. Turn back.",
	tygerclaws = "Japantown Business Association. Clubs, dining and entertainment. Members only.",
	valentinos = "Heywood community board. Family first.",
	sixthstreet = "Santo Domingo neighbourhood watch. Patriots welcome.",
	unregistered = "Unregistered host. No public page.",
}

local function page(title, url)
	return { title = title, url = url, lines = {} }
end

local function line(p, text, link, kind)
	table.insert(p.lines, { text = text or "", link = link or "", kind = kind or (link and link ~= "" and "link" or "text") })
end

local function nav(p)
	line(p, "Home  |  Directory  |  Stock exchange  |  News", "", "note")
	line(p, "> Home", "nc://home")
	line(p, "> Directory", "nc://directory")
	line(p, "> Stock exchange", "market://")
	line(p, "> News", "nc://news")
	line(p, "")
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local function home()
	local p = page("NC NET PORTAL", "nc://home")
	line(p, "Night City Net Portal", "", "title")
	line(p, "Your gateway to the data streams of the Free City.", "", "note")
	line(p, "")
	line(p, "> Directory of known networks", "nc://directory")
	line(p, "> Night City Stock Exchange", "market://")
	line(p, "> Newsfeed", "nc://news")
	line(p, "")
	local sites = {}
	for _, net in ipairs(Network.knownList()) do
		if net.kind == "site" then table.insert(sites, net) end
	end
	if #sites > 0 then
		line(p, "Community sites", "", "title")
		for _, net in ipairs(sites) do line(p, "> " .. net.name, "net://" .. net.addr) end
	end
	return p
end

local function directory()
	local p = page("DIRECTORY", "nc://directory")
	nav(p)
	line(p, "Known networks", "", "title")
	for _, net in ipairs(Network.knownList()) do
		local org = Lore.getOrg(net.org)
		local tag = Network.isOwned(net.addr) and "  [ROOT]" or ("  [ICE " .. net.ice .. "]")
		line(p, "> " .. net.name .. "  (" .. net.addr .. ")  " .. org.name .. tag, "net://" .. net.addr)
	end
	line(p, "")
	line(p, "Breach networks with the Terminal to find more.", "", "note")
	return p
end

local function news()
	local p = page("NEWSFEED", "nc://news")
	nav(p)
	line(p, "Newsfeed", "", "title")
	local items = Network.state.news
	if #items == 0 then line(p, "Quiet day in Night City.", "", "note") end
	for i = #items, math.max(1, #items - 20), -1 do line(p, "- " .. items[i]) end
	return p
end

local function listFiles(p, net, node, path)
	local names = {}
	for name in pairs(node.children) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do
		local child = node.children[name]
		local full = path .. "/" .. name
		if child.dir then
			listFiles(p, net, child, full)
		else
			local looted = Network.state.looted[net.addr .. ":" .. full]
			local note = child.paydata and (looted and "  (sold)" or ("  (paydata ~" .. child.paydata .. " eddies)")) or ""
			line(p, "  " .. full .. note, "", child.paydata and not looted and "good" or "text")
		end
	end
end

local function netPage(addr)
	local net = Network.get(addr)
	if net == nil or not Network.isKnown(addr) then
		local p = page("NOT FOUND", "net://" .. addr)
		nav(p)
		line(p, "No route to " .. addr .. ".", "", "bad")
		return p
	end
	local org = Lore.getOrg(net.org)
	local p = page(net.name:upper(), "net://" .. addr)
	nav(p)
	line(p, net.name, "", "title")
	if net.kind == "site" and net.site then
		for text in (tostring(net.site.text) .. "\n"):gmatch("(.-)\n") do line(p, text) end
		return p
	end
	line(p, blurbs[net.org] or blurbs.unregistered)
	line(p, "Operator: " .. org.name .. "    Address: " .. addr, "", "note")
	local company = Market.forOrg(net.org)
	if company then
		line(p, "> " .. company.name .. " on the stock exchange (" .. company.ticker .. ")", "market://" .. company.ticker)
	end
	line(p, "")
	if Network.isOwned(addr) then
		line(p, "Root access: internal files", "", "title")
		listFiles(p, net, Network.fs(net), "")
		line(p, "Use the Terminal to download or leak paydata.", "", "note")
	else
		line(p, "Internal systems protected by ICE level " .. net.ice .. ".", "", "bad")
		line(p, "Breach it from the Terminal:  connect " .. addr .. "  then  breach", "", "note")
	end
	return p
end

local function money(n) return string.format("%.2f", n) end

local function marketPage(status)
	local p = page("NC STOCK EXCHANGE", "market://")
	nav(p)
	if status then line(p, status.text, "", status.ok and "good" or "bad") end
	line(p, "Night City Stock Exchange", "", "title")
	line(p, "Your eddies: " .. World.getMoney(), "", "note")
	for _, c in ipairs(Market.companies) do
		local change = Market.change(c.ticker) * 100
		line(p, string.format("> %-4s %-22s %10s   %+5.1f%%", c.ticker, c.name, money(Market.price(c.ticker)), change),
			"market://" .. c.ticker, change > 0.05 and "good" or (change < -0.05 and "bad" or "link"))
	end
	local rows, value = Market.portfolio()
	line(p, "")
	line(p, "Your portfolio: " .. math.floor(value) .. " eddies in " .. #rows .. " companies", "", "title")
	for _, r in ipairs(rows) do
		line(p, string.format("> %-4s x%d   now %s   paid %s", r.ticker, r.qty, money(r.price), money(r.cost)),
			"market://" .. r.ticker, r.price >= r.cost and "good" or "bad")
	end
	return p
end

local function sparkline(ticker)
	local s = Network.state.market
	local h = s and s.history[ticker] or {}
	if #h < 2 then return "" end
	local lo, hi = math.huge, -math.huge
	for _, v in ipairs(h) do lo = math.min(lo, v); hi = math.max(hi, v) end
	local bars = { "_", ".", "-", "=", "#" }
	local out = {}
	for _, v in ipairs(h) do
		local i = hi > lo and math.floor((v - lo) / (hi - lo) * 4.999) + 1 or 3
		table.insert(out, bars[i])
	end
	return table.concat(out)
end

local function companyPage(ticker, status)
	local c = Market.get(ticker)
	if c == nil then return marketPage({ ok = false, text = "Unknown company " .. tostring(ticker) }) end
	local p = page(c.ticker .. " - " .. c.name:upper(), "market://" .. c.ticker)
	nav(p)
	if status then line(p, status.text, "", status.ok and "good" or "bad") end
	local change = Market.change(c.ticker) * 100
	line(p, c.name .. " (" .. c.ticker .. ")", "", "title")
	line(p, string.format("Price %s   change %+.1f%%", money(Market.price(c.ticker)), change), "", change >= 0 and "good" or "bad")
	line(p, "Trend: " .. sparkline(c.ticker), "", "note")
	local held = Network.state.market and Network.state.market.holdings[c.ticker] or 0
	line(p, "You hold " .. held .. " shares.   Your eddies: " .. World.getMoney(), "", "note")
	line(p, "")
	for _, q in ipairs({ 1, 10, 100 }) do
		line(p, "> Buy " .. q, "do://buy/" .. c.ticker .. "/" .. q)
	end
	if held > 0 then
		line(p, "> Sell 10", "do://sell/" .. c.ticker .. "/10")
		line(p, "> Sell all", "do://sell/" .. c.ticker .. "/all")
	end
	line(p, "")
	line(p, "> Back to the exchange", "market://")
	return p
end

---------------------------------------------------------------------------
-- Routing
---------------------------------------------------------------------------

function Web.render(url)
	url = tostring(url or "")
	if Network.state == nil then
		local p = page("OFFLINE", url)
		line(p, "No connection. Load a save first.", "", "bad")
		return p
	end
	if url == "" or url == "nc://home" or url == "home" then return home() end
	if url == "nc://directory" then return directory() end
	if url == "nc://news" then return news() end
	local addr = url:match("^net://(.+)$")
	if addr then return netPage(addr) end
	if url == "market://" or url == "market" then return marketPage() end
	local ticker = url:match("^market://(%w+)$")
	if ticker then return companyPage(ticker) end

	local action, t, qty = url:match("^do://(%a+)/(%w+)/(%w+)$")
	if action == "buy" or action == "sell" then
		local ok, msg
		if action == "buy" then ok, msg = Market.buy(t, qty) else ok, msg = Market.sell(t, qty) end
		local p = companyPage(t, { ok = ok, text = msg })
		return p
	end

	-- plain addresses typed into the address bar
	if Network.get(url) then return netPage(url) end
	local p = page("NOT FOUND", url)
	nav(p)
	line(p, "Page not found: " .. url, "", "bad")
	return p
end

return Web
