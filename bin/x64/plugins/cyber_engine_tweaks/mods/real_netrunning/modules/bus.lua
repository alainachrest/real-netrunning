-- Event bus shared by every Real Netrunning system (and other mods, through the API).
-- Systems publish what happened; others (stock market, NetWatch heat, news) react.

local Bus = {
	listeners = {},
	nextId = 0,
	depth = 0,
	maxDepth = 8,
	log = nil, -- set by init to a logging function
}

function Bus.on(event, callback)
	if type(event) ~= "string" or type(callback) ~= "function" then return nil end
	Bus.nextId = Bus.nextId + 1
	Bus.listeners[event] = Bus.listeners[event] or {}
	Bus.listeners[event][Bus.nextId] = callback
	return Bus.nextId
end

function Bus.off(id)
	for _, list in pairs(Bus.listeners) do
		if list[id] then
			list[id] = nil
			return true
		end
	end
	return false
end

-- Calls listeners for this event, then wildcard ("*") listeners.
-- A failing listener is logged and skipped so it can't break the caller.
function Bus.emit(event, data)
	if Bus.depth >= Bus.maxDepth then
		if Bus.log then Bus.log("event '" .. event .. "' dropped: listeners re-triggering too deeply") end
		return
	end
	Bus.depth = Bus.depth + 1
	data = data or {}
	for _, key in ipairs({ event, "*" }) do
		local list = Bus.listeners[key]
		if list then
			for id, callback in pairs(list) do
				local ok, err = pcall(callback, data, event)
				if not ok and Bus.log then
					Bus.log("listener " .. id .. " for '" .. event .. "' failed: " .. tostring(err))
				end
			end
		end
	end
	Bus.depth = Bus.depth - 1
end

return Bus
