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
--   shop://                 other mods' stores; shop://<store>[/p<page>], shop://<store>/item/<n>
--   do://shop/<store>/<n>   buy item n
--   NETdir://...            other mods' sites: embedded by Browser.reds, or nc://outside?<address>
--   open://<address>        open a vanilla site in the computer's own browser (Browser.reds)

local Network = require("modules/network")
local Lore = require("modules/lore")
local Market = require("modules/market")
local World = require("modules/world")
local NetWatch = require("modules/netwatch")
local Stores = require("modules/stores")

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
	biotechnica = { color = GREEN,  tagline = "Feeding the world. Healing the world.",
		about = "Biotechnica engineers the crops, livestock and medicines the world runs on. Our Night City operation farms the Biotechnica Flats." },
	petrochem   = { color = YELLOW, tagline = "Fuel for the future.",
		about = "Petrochem produces CHOOH2 and agricultural products across the NUSA. Our Badlands fields keep Night City moving." },
	sovoil      = { color = RED,    tagline = "Energy without borders.",
		about = "SovOil supplies fuel and petrochemicals to Eurasia and beyond, from Moscow to the Pacific." },
	orbitalair  = { color = BLUE,   tagline = "Your gateway to the stars.",
		about = "Orbital Air flies passengers and cargo between Earth and orbit. Book your seat on the next suborbital from Night City." },
	kiroshi     = { color = BLUE,   tagline = "See more.",
		about = "Kiroshi Opticals makes the cybernetic eyes trusted by half the world. Firmware updates are mandatory." },
	zetatech    = { color = GREEN,  tagline = "Thinking ahead.",
		about = "Zetatech builds computers, cyberdecks and the software that runs them." },
	wns         = { color = BLUE,   tagline = "The world, on the wire.",
		about = "World News Service. Bureaus in every major city, stringers everywhere else." },
	delamain    = { color = YELLOW, tagline = "Your journey. Our pleasure.",
		about = "Delamain Corporation: Night City's premier autonomous cab service. Every car, a gentleman." },
	esa         = { color = BLUE,   tagline = "Crystal Palace: humanity's home in orbit.",
		about = "The European Space Agency's Crystal Palace is the largest habitat in orbit. Visitor permits are issued by ESA only." },
	civilian    = { color = BLUE,   tagline = "Private network",
		about = "A small private network." },
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
	self:nav("NetWatch", "nc://netwatch")
	self:nav("Stores", "shop://")
	return self
end

local function money(n) return string.format("%.2f", n) end
local function pct(n) return string.format("%+.1f%%", n) end
local function status(p, result)
	if result then p:notice(result.text, result.ok and GREEN or RED) end
end

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

	-- other mods' stores and sites on this computer
	local stores = Stores.list()
	if #stores > 0 then
		p:heading("Stores")
		for i = 1, math.min(4, #stores) do
			local s = stores[i]
			p:card(s.name, s.count .. " items  -  " .. s.source, "shop://" .. s.key, GREEN)
		end
		p:link("All " .. #stores .. " stores", "shop://")
	end
	local sites = Stores.sites()
	if #sites > 0 then
		p:heading("Sites on this computer")
		for _, site in ipairs(sites) do
			p:card(site.name, site.embedded and site.address or (site.address .. "  -  opens in the computer's browser"),
				site.address, site.embedded and BLUE or YELLOW)
		end
	end
	return p
end

---------------------------------------------------------------------------
-- Other mods' stores and sites
---------------------------------------------------------------------------

local function shopList()
	local p = page("Stores", "shop://", GREEN)
	p:banner("STORES", "Every store on the Net, delivered to your door", GREEN)
	p:portalNav()
	p:field("Your eddies", tostring(World.getMoney()), YELLOW)
	local stores = Stores.list()
	if #stores == 0 then
		p:notice(Stores.atelierInstalled() and "Virtual Atelier is installed but no stores are registered yet. Try again in a moment."
			or "No stores found. Install Virtual Atelier and some Atelier stores, or a mod that adds stores to Real Netrunning.", YELLOW)
		return p
	end
	for _, s in ipairs(stores) do
		p:card(s.name, s.count .. " items  -  " .. s.source, "shop://" .. s.key, GREEN)
	end
	return p
end

local function shopPage(key, pageNo, result)
	local per = Stores.perPage
	pageNo = math.max(1, pageNo or 1)
	local store = Stores.get(key, (pageNo - 1) * per + 1, pageNo * per)
	if store == nil then
		local p = page("Stores", "shop://" .. key, RED)
		p:banner("404", "Store not found", RED)
		p:portalNav()
		p:notice("That store isn't on the Net anymore.", RED)
		return p
	end
	local pages = math.max(1, math.ceil(store.count / per))
	local url = "shop://" .. key .. (pageNo > 1 and ("/p" .. pageNo) or "")
	local p = page(store.name, url, GREEN)
	p:banner(store.name:upper(), store.source, GREEN)
	p:nav("All stores", "shop://")
	p:nav("Portal", "nc://home")
	status(p, result)
	if store.about then p:text(store.about) end
	p:field("Your eddies", tostring(World.getMoney()), YELLOW)
	p:field("Items", tostring(store.count))
	p:row({ "ITEM", "QUALITY", "QTY", "PRICE" }, "", YELLOW)
	for n, item in ipairs(store.items) do
		local index = store.first + n - 1
		p:row({ item.name, item.quality ~= "" and item.quality or "-", "x" .. item.quantity, tostring(item.price) .. " eddies" },
			"shop://" .. key .. "/item/" .. index, BLUE)
	end
	if pages > 1 then
		p:divider()
		p:field("Page", pageNo .. " of " .. pages)
		if pageNo > 1 then p:button("< Previous", "shop://" .. key .. (pageNo > 2 and ("/p" .. (pageNo - 1)) or ""), BLUE) end
		if pageNo < pages then p:button("Next >", "shop://" .. key .. "/p" .. (pageNo + 1), BLUE) end
	end
	return p
end

local function itemPage(key, index, result)
	local store = Stores.get(key, index, index)
	local item = store and store.items[1]
	if item == nil then return shopPage(key, 1, result or { ok = false, text = "That item is no longer in the store." }) end
	local p = page(item.name, "shop://" .. key .. "/item/" .. index, GREEN)
	p:banner(store.name:upper(), store.source, GREEN)
	p:nav("Back to the store", "shop://" .. key .. "/p" .. math.ceil(index / Stores.perPage))
	p:nav("All stores", "shop://")
	status(p, result)
	p:heading(item.name, GREEN)
	p:field("Price", item.price .. " eddies", YELLOW)
	if item.quality ~= "" then p:field("Quality", item.quality) end
	p:field("Quantity", "x" .. item.quantity)
	p:field("Item ID", item.id)
	p:field("Your eddies", tostring(World.getMoney()), YELLOW)
	p:button("Buy for " .. item.price .. " eddies", "do://shop/" .. key .. "/" .. index, GREEN)
	p:text("Delivered straight to your inventory.", BLUE)
	return p
end

-- A vanilla site, or a mod site this computer can't embed.
local function outsidePage(address)
	local p = page(address, address, YELLOW)
	p:banner("NETDIR", address, YELLOW)
	p:portalNav()
	local known
	for _, site in ipairs(Stores.sites()) do
		if site.address:lower() == address:lower() then known = site end
	end
	if known then
		p:heading(known.name, YELLOW)
		p:text("This site runs on the computer's own browser.")
	else
		p:notice("No site on this computer answers at " .. address .. ".", RED)
		p:text("Some sites only exist on certain computers. You can still try the computer's own browser.")
	end
	p:button("Open in the computer's browser", "open://" .. address, YELLOW)
	return p
end

local function directory()
	local p = page("Directory", "nc://directory", BLUE)
	p:banner("DIRECTORY", "Every network your deck can reach", BLUE)
	p:portalNav()
	for _, region in ipairs(Lore.regionOrder) do
		local rows = {}
		for _, net in ipairs(Network.knownList()) do
			if net.region == region then table.insert(rows, net) end
		end
		if #rows > 0 then
			local reach = Network.hasUplink(region)
			if region == "closed" then
				p:heading("Closed networks  -  jack into the device that bridges to each one", YELLOW)
			else
				p:heading(Lore.region(region).name .. (reach and "" or "  -  NO UPLINK"), reach and nil or RED)
			end
			p:row({ "ACCESS", "NETWORK", "OPERATOR", "ADDRESS" }, "", YELLOW)
			for _, net in ipairs(rows) do
				local org = Lore.getOrg(net.org)
				local owned = Network.isOwned(net.addr)
				local ok = Network.canReach(net)
				p:row({ owned and "ROOT" or ("ICE " .. net.ice), net.name, net.junk and "Private" or org.name, net.addr }, "net://" .. net.addr,
					owned and GREEN or ((not ok or net.ice >= 4) and RED or BLUE))
			end
		end
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

local function netwatchPage()
	local tier = NetWatch.tier()
	local heat = Network.state.heat
	local colors = { GREEN, YELLOW, RED, RED }
	local p = page("NetWatch", "nc://netwatch", RED)
	p:banner("NETWATCH", "Keeping the Net safe since the DataKrash", RED)
	p:portalNav()
	p:heading("Public bulletin: unidentified netrunner")
	p:field("Threat level", NetWatch.tierName(tier), colors[tier + 1])
	p:field("Heat", heat .. " / 100", colors[tier + 1])
	p:field("Agents lost", tostring(NetWatch.defeated()))
	p:card("WATCHED  (25+)", "Agents sometimes trace into networks the suspect enters.", "", YELLOW)
	p:card("HUNTED  (50+)", "Agents are assigned on sight. Field netrunners may engage the suspect in public.", "", RED)
	p:card("BURNED  (75+)", "All of the above. NCPD has been notified.", "", RED)
	p:text("Citizens with information should report it at any public terminal. NetWatch thanks you for your cooperation.", YELLOW)
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
		if path == "" and not Network.canAccess(net, full) then
			-- locked floor: skip
		elseif child.dir then
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

	local operator = net.junk and net.name or org.name
	p:banner(operator:upper(), net.tagline or site.tagline, site.color)
	p:nav("About", "net://" .. addr)
	local company = Market.forOrg(net.org)
	if company then p:nav("Investors", "market://" .. company.ticker) end
	p:nav("Portal", "nc://home")
	p:heading(net.name, site.color)
	p:text(net.about or site.about)
	p:field("Address", addr)
	p:field("Operator", net.junk and "Private" or org.name)
	p:field("Region", Lore.region(net.region).name .. (Network.lag(net) ~= 1 and ("  (lag x" .. Network.lag(net) .. ")") or ""))
	if net.uplink then
		p:field("Routes to", Lore.region(net.uplink).name, Network.isOwned(addr) and GREEN or YELLOW)
	end
	if net.closed then
		p:field("Bridged from", Network.state.gateways[addr] or "unknown", YELLOW)
		if net.lab then p:notice("PROJECT " .. net.lab.code .. ". This network does not officially exist.", RED) end
		if not Network.canReach(net) then
			p:notice("Closed network. Jack into the device that bridges to it and hack it down to its control floor.", YELLOW)
		end
	elseif net.isolated then
		p:field("Link", "Isolated: no link to the Net", YELLOW)
		if not Network.canReach(net) then
			p:notice("Isolated device network. The only way in is to go there and jack into one of its devices.", YELLOW)
		end
	elseif not Network.canReach(net) then
		p:notice("No uplink to " .. Lore.region(net.region).name .. ". Root a backbone that routes there to reach this network.", RED)
	end
	p:field("Security", Network.isOwned(addr) and "ROOT ACCESS" or ("ICE level " .. net.ice),
		Network.isOwned(addr) and GREEN or RED)

	if company then
		local change = Market.change(company.ticker) * 100
		p:card(company.name .. " on the exchange", company.ticker .. "  " .. money(Market.price(company.ticker)) .. "  " .. pct(change),
			"market://" .. company.ticker, change >= 0 and GREEN or RED)
	end

	p:divider()
	p:heading("Architecture")
	local depth = Network.depth(addr)
	for i, f in ipairs(Network.floors(net)) do
		local open = i <= depth
		local lock = f.kind == "ice" and ("ICE " .. f.ice) or f.kind == "black" and ("BLACK ICE " .. f.ice)
			or f.kind == "password" and "PASSWORD" or (f.kind == "core" and f.ice > 0) and ("ICE " .. f.ice) or ""
		p:row({ "FLOOR " .. i, f.kind:upper(), open and "OPEN" or lock }, "", open and GREEN or (f.kind == "black" and RED or YELLOW))
	end
	if depth > 1 then
		p:heading(Network.isOwned(addr) and "Internal files" or "Files on open floors", GREEN)
		fileRows(p, net, Network.fs(net), "")
		p:text("Use the Terminal to download or leak paydata.", YELLOW)
	end
	if not Network.isOwned(addr) then
		p:notice("Work down the floors from the Terminal:  connect " .. addr .. "  then  map  and  breach", RED)
	end
	return p
end

---------------------------------------------------------------------------
-- Stock exchange
---------------------------------------------------------------------------

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
	if url == "nc://netwatch" then return netwatchPage() end
	local query = url:match("^nc://search%?q=(.*)$")
	if query then return search(query) end
	local addr = url:match("^net://(.+)$")
	if addr then return netPage(addr) end
	if url == "market://" or url == "market" then return marketPage() end
	local ticker = url:match("^market://(%w+)$")
	if ticker then return companyPage(ticker) end

	if url == "shop://" or url == "shop" then return shopList() end
	local skey, sindex = url:match("^shop://(%a%a/[^/]+)/item/(%d+)$")
	if skey then return itemPage(skey, tonumber(sindex)) end
	local pkey, pno = url:match("^shop://(%a%a/[^/]+)/p(%d+)$")
	if pkey then return shopPage(pkey, tonumber(pno)) end
	local key = url:match("^shop://(%a%a/[^/]+)$")
	if key then return shopPage(key, 1) end
	local bkey, bindex = url:match("^do://shop/(%a%a/[^/]+)/(%d+)$")
	if bkey then
		local ok, msg = Stores.buy(bkey, tonumber(bindex))
		return itemPage(bkey, tonumber(bindex), { ok = ok, text = msg })
	end
	local outside = url:match("^nc://outside%?(.+)$")
	if outside then return outsidePage(outside) end

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
