-- Other mods' stores and sites, for the desktop Browser.
--
-- Virtual Atelier stores are read through DeckService (see Stores.reds). Other CET
-- mods can add their own stores with the Lua API (rn.api.registerStore). Sites
-- added to computers by Browser Extension, and vanilla sites, come from the
-- computer the Browser is open on.
--
-- Store keys used in addresses:  va/<index>  (Virtual Atelier),  rn/<id>  (Lua API)

local Stores = {
	provider = nil,   -- set by modules/native: talks to DeckService
	registered = {},  -- id -> store registered through the Lua API
	order = {},       -- ids in registration order
	perPage = 40,
}

local function provider() return Stores.provider end

Stores.clock = os.clock
local lastRefresh, storeCount = nil, 0

-- Re-reads Virtual Atelier's stores at most every few seconds.
local function refresh(force)
	local p = provider()
	if p == nil then return 0 end
	local now = Stores.clock()
	if force or lastRefresh == nil or now - lastRefresh > 5 then
		storeCount = p.refresh() or 0
		lastRefresh = now
	end
	return storeCount
end

-- def: { id, name, items = { { id = "Items.X", price = 100, quantity = 1, name = "optional" }, ... } }
function Stores.register(def)
	if type(def) ~= "table" or type(def.id) ~= "string" or type(def.items) ~= "table" then
		return false, "registerStore needs { id, name, items }"
	end
	local id = def.id:gsub("[^%w_%-]", "")
	if id == "" then return false, "store id must contain letters or numbers" end
	local items = {}
	for _, item in ipairs(def.items) do
		if type(item) == "table" and type(item.id) == "string" then
			table.insert(items, { id = item.id, price = tonumber(item.price) or 0,
				quantity = math.max(1, math.floor(tonumber(item.quantity) or 1)), name = item.name, quality = item.quality or "" })
		end
	end
	if Stores.registered[id] == nil then table.insert(Stores.order, id) end
	Stores.registered[id] = { id = id, name = tostring(def.name or id), items = items, about = def.about }
	return true
end

function Stores.unregister(id)
	Stores.registered[id] = nil
	for i, v in ipairs(Stores.order) do
		if v == id then table.remove(Stores.order, i) break end
	end
end

function Stores.atelierInstalled()
	local p = provider()
	return p ~= nil and p.installed() == true
end

-- Every store: { key, name, count, source }
function Stores.list()
	local list = {}
	local p = provider()
	if p and p.installed() then
		local n = refresh(true)
		for i = 0, n - 1 do
			table.insert(list, { key = "va/" .. i, name = p.name(i), count = p.itemCount(i), source = "Virtual Atelier" })
		end
	end
	for _, id in ipairs(Stores.order) do
		local s = Stores.registered[id]
		table.insert(list, { key = "rn/" .. id, name = s.name, count = #s.items, source = "Mod store" })
	end
	return list
end

-- A store with items first..last (1-based, default all):
-- { key, name, source, about, count, first, items = { { name, id, price, quantity, quality } } }
function Stores.get(key, first, last)
	local kind, ref = tostring(key):match("^(%a%a)/(.+)$")
	local p = provider()
	if kind == "va" and p then
		local i = tonumber(ref)
		if i == nil or i < 0 or i >= refresh() then return nil end
		local count = p.itemCount(i)
		first = math.max(1, first or 1)
		last = math.min(count, last or count)
		local store = { key = key, name = p.name(i), source = "Virtual Atelier", items = {}, count = count, first = first }
		for j = first, last do
			table.insert(store.items, p.item(i, j - 1))
		end
		return store
	elseif kind == "rn" then
		local s = Stores.registered[ref]
		if s == nil then return nil end
		first = math.max(1, first or 1)
		last = math.min(#s.items, last or #s.items)
		local store = { key = key, name = s.name, source = "Mod store", about = s.about, items = {}, count = #s.items, first = first }
		for j = first, last do
			local item = s.items[j]
			local name = item.name or (p and p.itemName(item.id)) or item.id
			local price = item.price
			if price <= 0 and p then price = p.itemPrice(item.id, 0, item.quantity) end
			table.insert(store.items, { name = (name ~= "" and name or item.id), id = item.id, price = price,
				quantity = item.quantity, quality = item.quality })
		end
		return store
	end
	return nil
end

-- Buys item number j (1-based) of a store. Returns ok, message.
function Stores.buy(key, j)
	local p = provider()
	if p == nil then return false, "Stores aren't available right now." end
	local kind, ref = tostring(key):match("^(%a%a)/(.+)$")
	local result
	if kind == "va" then
		local i = tonumber(ref)
		if i == nil then return false, "No such store." end
		refresh()
		result = p.buyAtelier(i, j - 1)
	elseif kind == "rn" then
		local s = Stores.registered[ref]
		local item = s and s.items[j]
		if item == nil then return false, "That item is no longer in the store." end
		result = p.buy(item.id, item.quantity, item.price)
	else
		return false, "No such store."
	end
	result = tostring(result or "err:The purchase failed.")
	local ok = result:sub(1, 3) == "ok:"
	return ok, (result:gsub("^%a+:", ""))
end

-- Sites on the computer the Browser is open on: { name, address, embedded }
function Stores.sites()
	local p = provider()
	if p == nil then return {} end
	return p.sites() or {}
end

return Stores
