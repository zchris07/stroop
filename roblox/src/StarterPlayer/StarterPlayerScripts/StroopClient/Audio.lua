--!nonstrict
--[[
	The two synthesised sounds from the page.

	The web build generated both with the Web Audio API - a bandpassed noise
	tick for a mouse click, and a 150 Hz -> 58 Hz sine drop for the wrong-answer
	thud. Roblox can only play assets, so each one is rebuilt from Roblox's own
	built-in sound files, pitched and layered to land in the same place. Every
	candidate is tried in order and the first that actually loads is used, so a
	missing built-in degrades to silence rather than an error.

	To use your own sounds instead, put an asset id in OVERRIDES below.
]]

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local Audio = {}

-- Paste your own "rbxassetid://..." here to replace either sound.
local OVERRIDES = {
	click = nil,
	thud = nil,
}

local CANDIDATES = {
	click = {
		"rbxasset://sounds/switch3.wav",
		"rbxasset://sounds/clickfast.wav",
		"rbxasset://sounds/electronicpingshort.wav",
	},
	thud = {
		"rbxasset://sounds/impact_water.mp3",
		"rbxasset://sounds/metal.ogg",
		"rbxasset://sounds/snap.mp3",
	},
}

-- press + release + the short upward blip, and the thud's two layers
local VOICES = {
	click = {
		{ speed = 2.65, volume = 0.32, delay = 0 },
		{ speed = 3.40, volume = 0.16, delay = 0.042 },
	},
	thud = {
		{ speed = 0.42, volume = 0.65, delay = 0 },
		{ speed = 0.75, volume = 0.22, delay = 0.012 },
	},
}

local group = Instance.new("Folder")
group.Name = "StroopAudio"
group.Parent = SoundService

local resolved = {}

local function resolve(kind)
	if resolved[kind] ~= nil then
		return resolved[kind]
	end
	local list = {}
	if OVERRIDES[kind] then
		table.insert(list, OVERRIDES[kind])
	end
	for _, id in ipairs(CANDIDATES[kind]) do
		table.insert(list, id)
	end

	for _, id in ipairs(list) do
		local probe = Instance.new("Sound")
		probe.SoundId = id
		probe.Volume = 0
		probe.Parent = group
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ probe })
		end)
		local loaded = ok and probe.IsLoaded
		probe:Destroy()
		if loaded then
			resolved[kind] = id
			return id
		end
	end
	resolved[kind] = false
	return false
end

-- Resolution touches the content provider, so it is done once up front rather
-- than on the first click.
task.spawn(function()
	resolve("click")
	resolve("thud")
end)

local function play(kind)
	local id = resolve(kind)
	if not id then
		return
	end
	for _, layer in ipairs(VOICES[kind]) do
		task.delay(layer.delay, function()
			local s = Instance.new("Sound")
			s.SoundId = id
			s.Volume = layer.volume
			s.PlaybackSpeed = layer.speed
			s.Parent = group
			s:Play()
			task.delay(4, function()
				s:Destroy()
			end)
		end)
	end
end

-- A real-mouse double tick with a short upward blip on top.
function Audio.click()
	play("click")
end

-- A dull, low-pitched thud - played for a wrong answer, never for a timeout.
function Audio.thud()
	play("thud")
end

return Audio
