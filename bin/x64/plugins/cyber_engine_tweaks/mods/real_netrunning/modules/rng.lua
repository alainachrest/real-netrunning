-- Deterministic random numbers, so a save's generated content is the same every load.
-- Park-Miller "minimal standard" generator: all intermediate values stay below 2^53,
-- so results are exact in Lua's double-precision numbers on every machine.

local Rng = {}
Rng.__index = Rng

local MOD = 2147483647
local MUL = 16807

function Rng.hash(text)
	local h = 5381
	text = tostring(text)
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % MOD
	end
	if h == 0 then h = 1 end
	return h
end

function Rng.new(...)
	local parts = { ... }
	for i = 1, #parts do parts[i] = tostring(parts[i]) end
	local self = setmetatable({}, Rng)
	self.state = Rng.hash(table.concat(parts, "|"))
	return self
end

-- Float in [0, 1)
function Rng:next()
	self.state = (self.state * MUL) % MOD
	return (self.state - 1) / (MOD - 1)
end

-- Integer in [low, high]
function Rng:int(low, high)
	return low + math.floor(self:next() * (high - low + 1))
end

function Rng:pick(list)
	if #list == 0 then return nil end
	return list[self:int(1, #list)]
end

function Rng:chance(p)
	return self:next() < p
end

return Rng
