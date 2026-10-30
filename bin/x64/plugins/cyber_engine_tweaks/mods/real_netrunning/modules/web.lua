-- Pages for the desktop Browser app.
--
-- A page is { title, url, theme, blocks }. Each block is
-- { type, text, extra, link, color } and is drawn by Browser.reds:
--
--   banner   site header: text = name, extra = tagline
--   nav      one navigation link (consecutive ones form a bar)
--   heading  section heading
--   text     paragraph
--   link     a link line
--   button   a button (consecutive ones form a row)
--   card     boxed item: text = title, extra = body
--   row      table row: columns in text separated by "|"
--   chart    bar chart: extra = comma-separated values
--   divider  horizontal rule
--   notice   highlighted message
--   icon     icon tile: extra = hub icon name (consecutive ones form a row)
--   field    label/value line: text = label, extra = value
--
-- color is a game style colour such as "MainColors.Red" ("" for the default).
--
-- Addresses:
--   nc://home, nc://directory, nc://news, nc://search?q=<words>
--   net://<address>        a network's site (and its files once breached)
--   market://              the exchange; market://<TICKER> for one company
--   do://buy/<T>/<qty>, do://sell/<T>/<qty|all>   trades

local Network = require("modules/network")
local Lore = require("modules/lore")
local Market = require("modules/market")
local World = require("modules/world")

local Web = {}

local RED, BLUE, LINK = "MainColors.Red", "MainColors.Blue", "MainColors.ActiveBlue"
local YELLOW, GREEN = "MainColors.Yellow", "MainColors.Green"

-- Site look and in-world text per organisation.
local sites = {
	arasaka     = { color = RED,    tagline = "Security. Banking. Manufacturing. Since 1915.",
		about = "Arasaka Corporation provides security solutions, banking and manufacturing across the globe. Our Night City tower is the heart of our operations on the West Coast." },
	militech    = { color = YELLOW, tagline = "Defending the New United States.",
		about = "Militech International Armaments supplies the armed forces of the NUSA and its partners with the finest weapons, vehicles and cyberware." },
	kangtao     = { color = GREEN,  tagline = "Smart technology for a new century.",
		about = "Kang Tao designs smart weapons and civilian technology. Our Night City branch serves the growing Pacific market." },
	traumateam  = { color = GREEN,  tagline = "Platinum coverage. Three minutes or less.",
		about = "Trauma Team International. Subscribers receive armed medevac anywhere in Night City. Upgrade to Platinum today." },
	network54   = { color = BLUE,   tagline = "The news that matters, when it matters.",
		about = "Network 54 brings Night City the stories that shape the Free City, around the clock." },
	ncpd        = { color = LINK,   tagline = "To protect and serve.",
		about = "Night City Police Department. Report crimes on any public terminal. MaxTac requests go through precinct command." },
	maelstrom   = { color = RED,    tagline = "Turn back.",
		about = "This node is not for you." },
	tygerclaws  = { color = RED,    tagline = "Japantown Business Association",
		about = "Clubs, dining and entertainment in Japantown. Members only." },
	valentinos  = { color = YELLOW, tagline = "Heywood community board",
		about = "Family first. Respect the neighbourhood." },
	sixthstreet = { color = YELLOW, tagline = "Santo Domingo neighbourhood watch",
		about = "Patriots welcome. Outsiders, keep moving." },
	unregistered = { color = BLUE,  tagline = "Unregistered host",
		about = "No public page." },
}

---------------------------------------------------------------------------
-- Page builder
---------------------------------------------------------------------------

local Page = {}
Page.__index = Page

local function page(title, url, theme)
	return setmetatable({ title = title, url = url, theme = theme or RED, blocks = {} }, Page)
end

function Page:add(type, text, extra, link, color)
	table.insert(self.blocks, { type = type, text = text or "", extra = extra or "", link = link or "", color = color or "" })
	return self
end

function Page:banner(name, tagline, color) return self:add("banner", name, tagline, "", color) end
function Page:nav(label, link) return self:add("nav", label, "", link) end
function Page:heading(text, color) return self:add("heading", text, "", "", color) end
function Page:text(text, color) return self:add("text", text, "", "", color) end
function Page:link(text, link) return self:add("link", text, "", link) end
function Page:button(text, link, color) return self:add("button", text, "", link, color) end
function Page:card(title, body, link, color) return self:add("card", title, body, link, color) end
function Page:row(columns, link, color)
	local safe = {}
	for i, c in ipairs(columns) do safe[i] = tostring(c):gsub("|", "/") end
	return self:add("row", table.concat(safe, "|"), "", link, color)
end
function Page:chart(values, color) return self:add("chart", "", table.concat(values, ","), "", color) end
function Page:divider() return self:add("divider") end
function Page:notice(text, color) return self:add("notice", text, "", "", color) end
function Page:icon(label, icon, link) return self:add("icon", label, icon, link) end
function Page:field(label, value, color) return self:add("field", label, value, "", color) end

-- The portal's navigation bar, shown on every page.
function Page:portalNav()
	self:nav("Home", "nc://home")
	self:nav("Directory", "nc://directory")
	self:nav("Exchange", "market://")
	self:nav("News", "nc://news")
	return self
end

local function money(n) return string.format("%.2f", n) end
local function pct(n) return string.format("%+.1f%%", n) end

---------------------------------------------------------------------------
-- Portal pages
---------------------------------------------------------------------------

local function home()
	local p = page("NC Net Portal", "nc://home", BLUE)
	p:banner("NC NET", "Your gateway to the data streams of the Free City", BLUE)
	p:portalNav()
	p:icon("Directory", "ico_map", "nc://directory")
	p:icon("Exchange", "ico_inventory", "market://")
	p:icon("News", "ico_journal", "nc://news")
	p:icon("Your data", "ico_data", "nc://directory")

	p:heading("Top stories")
	local news = Network.state.news
	if #news == 0 then
		p:text("Quiet day in Night City.", YELLOW)
	else
		for i = #news, math.max(1, #news - 2), -1 do p:card(news[i], "", "nc://news", RED) end
	end

	p:heading("Markets")
	local count = 0
	for _, c in ipairs(Market.companies) do
		if count < 4 then
			local change = Market.change(c.ticker) * 100
			p:row({ c.ticker, c.name, money(Market.price(c.ticker)), pct(change) }, "market://" .. c.ticker,
				change >= 0 and GREEN or RED)
			count = count + 1
		end
	end
	p:link("All listings on the Night City Stock Exchange", "market://")

	local sitesList = {}
	for _, net in ipairs(Network.knownList()) do
		if net.kind == "site" then table.insert(sitesList, net) end
	end
	if #sitesList > 0 then
		p:heading("Community sites")
		for _, net in ipairs(sitesList) do p:link(net.name, "net://" .. net.addr) end
	end
	return p
end

local function directory()
	local p = page("Directory", "nc://directory", BLUE)
	p:banner("DIRECTORY", "Every network your deck can reach", BLUE)
	p:portalNav()
	p:row({ "ACCESS", "NETWORK", "OPERATOR", "ADDRESS" }, "", YELLOW)
	for _, net in ipairs(Network.knownList()) do
		local org = Lore.getOrg(net.org)
		local owned = Network.isOwned(net.addr)
		p:row({ owned and "ROOT" or ("ICE " .. net.ice), net.name, org.name, net.addr }, "net://" .. net.addr,
			owned and GREEN or (net.ice >= 4 and RED or BLUE))
	end
	p:divider()
	p:text("Breach networks with the Terminal to find more routes.", YELLOW)
	return p
end

local function news()
	local p = page("Newsfeed", "nc://news", RED)
	p:banner("NEWSFEED", "Night City, as it happens", RED)
	p:portalNav()
	local items = Network.state.news
	if #items == 0 then p:text("Quiet day in Night City.", YELLOW) end
	for i = #items, math.max(1, #items - 20), -1 do p:card(items[i], "", "", RED) end
	return p
end

local function search(query)
	local p = page("Search: " .. query, "nc://search?q=" .. query, BLUE)
	p:banner("SEARCH", "Results for \"" .. query .. "\"", BLUE)
	p:portalNav()
	local q, found = query:lower(), 0
	for _, net in ipairs(Network.knownList()) do
		local org = Lore.getOrg(net.org)
		if net.name:lower():find(q, 1, true) or net.addr:lower():find(q, 1, true) or org.name:lower():find(q, 1, true) then
			p:card(net.name, org.name .. "  -  " .. net.addr, "net://" .. net.addr, BLUE)
			found = found + 1
		end
	end
	for _, c in ipairs(Market.companies) do
		if c.name:lower():find(q, 1, true) or c.ticker:lower() == q then
			p:card(c.name .. " (" .. c.ticker .. ")", "Stock price " .. money(Market.price(c.ticker)), "market://" .. c.ticker, YELLOW)
			found = found + 1
		end
	end
	if found == 0 then p:notice("No results. Your deck only finds networks you've discovered.", RED) end
	return p
end

---------------------------------------------------------------------------
-- Network sites
---------------------------------------------------------------------------

local function fileRows(p, net, node, path)
	local names = {}
	for name in pairs(node.children) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do
		local child = node.children[name]
		local full = path .. "/" .. name
		if child.dir then
			fileRows(p, net, child, full)
		else
			local sold = Network.state.looted[net.addr .. ":" .. full]
			local value = child.paydata and (sold and "sold" or ("~" .. child.paydata .. " eddies")) or ""
			p:row({ child.paydata and "PAYDATA" or "FILE", full, value }, "", child.paydata and not sold and GREEN or BLUE)
		end
	end
end

local function notFound(url, message)
	local p = page("Not found", url, RED)
	p:banner("404", "No route to host", RED)
	p:portalNav()
	p:notice(message, RED)
	return p
end

local function netPage(addr)
	local net = Network.get(addr)
	if net == nil or not Network.isKnown(addr) then
		return notFound("net://" .. addr, "No route to " .. addr .. ". Breach networks to discover new routes.")
	end
	local site = sites[net.org] or sites.unregistered
	local org = Lore.getOrg(net.org)
	local p = page(net.name, "net://" .. addr, site.color)

	if net.kind == "site" and net.site then
		local first = true
		for paragraph in (tostring(net.site.text) .. "\n\n"):gmatch("(.-)\n\n") do
			if first then
				p:banner(paragraph:upper(), "Community site", BLUE)
				p:portalNav()
				first = false
			elseif paragraph ~= "" then
				p:text(paragraph)
			end
		end
		return p
	end

	p:banner(org.name:upper(), site.tagline, site.color)
	p:nav("About", "net://" .. addr)
	local company = Market.forOrg(net.org)
	if company then p:nav("Investors", "market://" .. company.ticker) end
	p:nav("Portal", "nc://home")
	p:heading(net.name, site.color)
	p:text(site.about)
	p:field("Address", addr)
	p:field("Operator", org.name)
	p:field("Security", Network.isOwned(addr) and "ROOT ACCESS" or ("ICE level " .. net.ice),
		Network.isOwned(addr) and GREEN or RED)

	if company then
		local change = Market.change(company.ticker) * 100
		p:card(company.name .. " on the exchange", company.ticker .. "  " .. money(Market.price(company.ticker)) .. "  " .. pct(change),
			"market://" .. company.ticker, change >= 0 and GREEN or RED)
	end

	p:divider()
	if Network.isOwned(addr) then
		p:heading("Internal files", GREEN)
		fileRows(p, net, Network.fs(net), "")
		p:text("Use the Terminal to download or leak paydata.", YELLOW)
	else
		p:notice("Internal systems protected by ICE level " .. net.ice .. ". Breach from the Terminal:  connect " .. addr .. "  then  breach", RED)
	end
	return p
end

---------------------------------------------------------------------------
-- Stock exchange
---------------------------------------------------------------------------

local function status(p, result)
	if result then p:notice(result.text, result.ok and GREEN or RED) end
end

local function marketPage(result)
	local p = page("NC Stock Exchange", "market://", YELLOW)
	p:banner("NC STOCK EXCHANGE", "Live prices from the Free City", YELLOW)
	p:portalNav()
	status(p, result)
	p:field("Your eddies", tostring(World.getMoney()), YELLOW)
	p:row({ "TICKER", "COMPANY", "PRICE", "CHANGE" }, "", YELLOW)
	for _, c in ipairs(Market.companies) do
		local change = Market.change(c.ticker) * 100
		p:row({ c.ticker, c.name, money(Market.price(c.ticker)), pct(change) }, "market://" .. c.ticker,
			change > 0.05 and GREEN or (change < -0.05 and RED or BLUE))
	end
	local rows, value = Market.portfolio()
	p:heading("Your portfolio  -  " .. math.floor(value) .. " eddies")
	if #rows == 0 then p:text("You don't own any shares yet.") end
	for _, r in ipairs(rows) do
		p:row({ r.ticker, "x" .. r.qty, money(r.price), "paid " .. money(r.cost) }, "market://" .. r.ticker,
			r.price >= r.cost and GREEN or RED)
	end
	return p
end

local function companyPage(ticker, result)
	local c = Market.get(ticker)
	if c == nil then return marketPage({ ok = false, text = "Unknown company " .. tostring(ticker) }) end
	local change = Market.change(c.ticker) * 100
	local up = change >= 0
	local p = page(c.ticker .. " - " .. c.name, "market://" .. c.ticker, YELLOW)
	p:banner(c.name:upper(), c.ticker .. "  on the Night City Stock Exchange", YELLOW)
	p:portalNav()
	status(p, result)
	p:heading(money(Market.price(c.ticker)) .. "   " .. pct(change), up and GREEN or RED)
	local history = Network.state.market and Network.state.market.history[c.ticker] or {}
	p:chart(history, up and GREEN or RED)
	local held = Network.state.market and Network.state.market.holdings[c.ticker] or 0
	p:field("You hold", held .. " shares")
	p:field("Your eddies", tostring(World.getMoney()), YELLOW)
	p:button("Buy 1", "do://buy/" .. c.ticker .. "/1", GREEN)
	p:button("Buy 10", "do://buy/" .. c.ticker .. "/10", GREEN)
	p:button("Buy 100", "do://buy/" .. c.ticker .. "/100", GREEN)
	if held > 0 then
		p:button("Sell 10", "do://sell/" .. c.ticker .. "/10", RED)
		p:button("Sell all", "do://sell/" .. c.ticker .. "/all", RED)
	end
	p:text("1% fee per trade.", YELLOW)
	if c.org then
		local net
		for _, n in ipairs(Network.knownList()) do
			if n.org == c.org then net = n break end
		end
		if net then p:link(c.name .. " website", "net://" .. net.addr) end
	end
	p:link("Back to all listings", "market://")
	return p
end

---------------------------------------------------------------------------
-- Routing
---------------------------------------------------------------------------

function Web.render(url)
	url = tostring(url or ""):match("^%s*(.-)%s*$")
	if Network.state == nil then
		local p = page("Offline", url, RED)
		p:notice("No connection. Load a save first.", RED)
		return p
	end
	if url == "" or url == "nc://home" or url == "home" then return home() end
	if url == "nc://directory" then return directory() end
	if url == "nc://news" then return news() end
	local query = url:match("^nc://search%?q=(.*)$")
	if query then return search(query) end
	local addr = url:match("^net://(.+)$")
	if addr then return netPage(addr) end
	if url == "market://" or url == "market" then return marketPage() end
	local ticker = url:match("^market://(%w+)$")
	if ticker then return companyPage(ticker) end

	local action, t, qty = url:match("^do://(%a+)/(%w+)/(%w+)$")
	if action == "buy" or action == "sell" then
		local ok, msg
		if action == "buy" then ok, msg = Market.buy(t, qty) else ok, msg = Market.sell(t, qty) end
		return companyPage(t, { ok = ok, text = msg })
	end

	-- typed into the address bar: an address, a ticker, or a search
	if Network.get(url) then return netPage(url) end
	if Market.get(url) then return companyPage(url) end
	if url:find("://", 1, true) then return notFound(url, "Page not found: " .. url) end
	return search(url)
end

return Web
