--!nonstrict
-- The page's CSS custom properties, plus the dark -> light crossfade that the
-- transition into play performs on `#app`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Stroop.Config)
local Util = require(ReplicatedStorage.Stroop.Util)

local Theme = {}

-- Roblox's built-in font list stands in for the web fonts:
--   IBM Plex Mono -> RobotoMono, Georgia -> Merriweather, Syne Mono -> Code.
-- Looked up by name so a font missing from some future client degrades to a
-- sensible neighbour instead of failing to load the module.
function Theme.font(name, fallback)
	local ok, value = pcall(function()
		return Enum.Font[name]
	end)
	if ok and value then
		return value
	end
	return fallback or Enum.Font.SourceSans
end

Theme.MONO = Theme.font("RobotoMono", Enum.Font.Code)
Theme.SERIF = Theme.font("Merriweather", Enum.Font.SourceSans)
Theme.MSG = Theme.font("Code", Theme.MONO)

Theme.OK = Util.hex(Config.THEME.ok)
Theme.BAD = Util.hex(Config.THEME.bad)

local DARK, LIGHT = Config.THEME.dark, Config.THEME.light

Theme.current = {
	pageBg = Util.hex(DARK.pageBg),
	ink = Util.hex(DARK.ink),
	dim = Util.hex(DARK.dim),
	panel = Util.hex(DARK.panel),
	panelLine = Util.hex(DARK.panelLine),
}

Theme.isLight = false

local subscribers = {}

-- Anything that paints itself from a theme token registers here and is
-- repainted on every frame of the crossfade.
function Theme.bind(fn)
	table.insert(subscribers, fn)
	fn(Theme.current)
	return function()
		local i = Util.indexOf(subscribers, fn)
		if i then
			table.remove(subscribers, i)
		end
	end
end

local function emit()
	for _, fn in ipairs(subscribers) do
		local ok, err = pcall(fn, Theme.current)
		if not ok then
			warn("[Stroop] theme subscriber failed: " .. tostring(err))
		end
	end
end

local KEYS = { "pageBg", "ink", "dim", "panel", "panelLine" }

local activeFade = 0

-- `transition: background-color .8s ease, color .8s ease` on #app.
function Theme.setLight(light, duration)
	duration = duration or 0.8
	Theme.isLight = light
	local target = light and LIGHT or DARK
	local from = {}
	for _, k in ipairs(KEYS) do
		from[k] = Theme.current[k]
	end
	activeFade = activeFade + 1
	local token = activeFade

	if duration <= 0 then
		for _, k in ipairs(KEYS) do
			Theme.current[k] = Util.hex(target[k])
		end
		emit()
		return
	end

	task.spawn(function()
		local t = 0
		while t < duration do
			local dt = RunService.RenderStepped:Wait()
			if token ~= activeFade then
				return
			end
			t = math.min(duration, t + dt)
			-- CSS `ease` == cubic-bezier(.25,.1,.25,1); this is close enough
			-- that the two builds fade at the same apparent rate.
			local k = t / duration
			local a = k < 0.5 and 2 * k * k or 1 - (-2 * k + 2) ^ 2 / 2
			for _, key in ipairs(KEYS) do
				Theme.current[key] = from[key]:Lerp(Util.hex(target[key]), a)
			end
			emit()
		end
	end)
end

function Theme.reset()
	Theme.setLight(false, 0)
end

return Theme
