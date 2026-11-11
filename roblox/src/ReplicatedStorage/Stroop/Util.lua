--!nonstrict
-- Small shared helpers: the JS one-liners the page leaned on, plus the colour
-- maths the boss layer uses to keep every button readable.

local Util = {}

local rng = Random.new(os.clock() * 1e6 % 2 ^ 31)

function Util.random(a, b)
	if a == nil then
		return rng:NextNumber()
	end
	if b == nil then
		return rng:NextNumber() * a
	end
	return rng:NextNumber(a, b)
end

-- `rand(a, b)` in the original.
Util.rand = Util.random

function Util.randInt(a, b)
	return rng:NextInteger(a, b)
end

function Util.chance(p)
	return rng:NextNumber() < p
end

function Util.pick(list)
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

function Util.shuffle(list)
	local a = table.create(#list)
	for i = 1, #list do
		a[i] = list[i]
	end
	for i = #a, 2, -1 do
		local j = rng:NextInteger(1, i)
		a[i], a[j] = a[j], a[i]
	end
	return a
end

function Util.filter(list, fn)
	local out = {}
	for _, v in ipairs(list) do
		if fn(v) then
			table.insert(out, v)
		end
	end
	return out
end

function Util.map(list, fn)
	local out = table.create(#list)
	for i, v in ipairs(list) do
		out[i] = fn(v, i)
	end
	return out
end

function Util.contains(list, v)
	for _, x in ipairs(list) do
		if x == v then
			return true
		end
	end
	return false
end

function Util.indexOf(list, v)
	for i, x in ipairs(list) do
		if x == v then
			return i
		end
	end
	return nil
end

function Util.concat(a, b)
	local out = {}
	for _, v in ipairs(a) do
		table.insert(out, v)
	end
	for _, v in ipairs(b) do
		table.insert(out, v)
	end
	return out
end

function Util.clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

function Util.sign(v)
	if v > 0 then
		return 1
	elseif v < 0 then
		return -1
	end
	return 0
end

-- ---------- colour ----------

local hexCache = {}

function Util.hex(h)
	local c = hexCache[h]
	if not c then
		c = Color3.fromHex(h)
		hexCache[h] = c
	end
	return c
end

local function channel(v)
	if v <= 0.03928 then
		return v / 12.92
	end
	return ((v + 0.055) / 1.055) ^ 2.4
end

function Util.luminance(h)
	local c = typeof(h) == "Color3" and h or Util.hex(h)
	return 0.2126 * channel(c.R) + 0.7152 * channel(c.G) + 0.0722 * channel(c.B)
end

function Util.contrast(a, b)
	local la, lb = Util.luminance(a), Util.luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

-- Roblox has no `mix-blend-mode: difference`, so anything that relied on it to
-- stay legible picks black or white against whatever is currently behind it.
function Util.readableOn(bg)
	return Util.luminance(bg) > 0.42 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
end

-- CSS `color-mix(in srgb, A p%, B)`.
function Util.mix(a, b, p)
	local ca = typeof(a) == "Color3" and a or Util.hex(a)
	local cb = typeof(b) == "Color3" and b or Util.hex(b)
	return ca:Lerp(cb, 1 - p)
end

-- ---------- misc ----------

function Util.escapeName(s)
	s = tostring(s or "")
	s = s:gsub("[%c]", "")
	s = s:sub(1, 16)
	if s:gsub("%s", "") == "" then
		return "PLAYER"
	end
	return s
end

function Util.ordinal(n)
	local words = {
		"first", "second", "third", "fourth", "fifth",
		"sixth", "seventh", "eighth", "ninth", "tenth",
	}
	return words[n] or ("#" .. n)
end

return Util
