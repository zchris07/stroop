--!nonstrict
--[[
	The wrong-colour voice.

	Stage 3 and the whole boss fight lean on a voice calling out a colour that
	isn't the ink, to pull you toward the wrong button. The web build used the
	browser's speechSynthesis; Roblox has no text-to-speech, so this module
	plays recorded clips if you supply them and otherwise falls back to a
	"heard, not read" caption - a faint word that drifts up near the edge of
	the screen and fades, which distracts in the same way without pretending to
	be a voice.

	=== TO USE REAL SPEECH ===
	Upload one short clip per colour name (Create -> Audio on roblox.com),
	then paste the ids into CLIPS below:

		CLIPS.RED = "rbxassetid://123456789"

	Anything left nil keeps the caption fallback for that word, so you can add
	them a few at a time.
]]

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local Voice = {}

Voice.CLIPS = {
	-- the nine inks
	RED = nil,
	CYAN = nil,
	YELLOW = nil,
	GREEN = nil,
	BLUE = nil,
	PURPLE = nil,
	PINK = nil,
	BLACK = nil,
	WHITE = nil,
	-- the ALTERNATE challenge's nine
	MAGENTA = nil,
	CHARTREUSE = nil,
	GRAY = nil,
	MAROON = nil,
	TEAL = nil,
	INDIGO = nil,
	TURQUOISE = nil,
	SALMON = nil,
	BEIGE = nil,
}

Voice.volume = 0.9
Voice.rate = 0.95

-- The UI installs a handler here to draw the caption when no clip exists.
Voice.onCaption = nil

local group = Instance.new("Folder")
group.Name = "StroopVoice"
group.Parent = SoundService

local active = {}
local token = 0

local function stopAll()
	for sound in pairs(active) do
		pcall(function()
			sound:Stop()
			sound:Destroy()
		end)
	end
	table.clear(active)
end

-- Plays `name` and calls `done()` when it finishes. Never cancels an utterance
-- that is already speaking - the page let a phrase play out past round end.
function Voice.say(name, done)
	done = done or function() end
	if not name then
		done()
		return
	end

	local id = Voice.CLIPS[name]
	if id then
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Volume = Voice.volume
		sound.PlaybackSpeed = Voice.rate
		sound.Parent = group
		active[sound] = true

		local finished = false
		local function finish()
			if finished then
				return
			end
			finished = true
			active[sound] = nil
			pcall(function()
				sound:Destroy()
			end)
			done()
		end

		sound.Ended:Connect(finish)
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ sound })
			sound:Play()
		end)
		if not ok then
			finish()
			return
		end
		-- safety net, matching the 2.6s guard the page used
		task.delay(2.6, finish)
		return
	end

	-- fallback: the word appears instead of being spoken
	if Voice.onCaption then
		pcall(Voice.onCaption, name)
	end
	task.delay(0.9, done)
end

function Voice.cancel()
	token = token + 1
	stopAll()
end

-- The boss's rolling distraction: a new wrong colour every BOSS_VOICE_GAP,
-- never the ink and never the same one twice in a row.
function Voice.loop(inkName, palette, gap, isAlive)
	token = token + 1
	local mine = token
	local last = nil

	local function step()
		if mine ~= token or not isAlive() then
			return
		end
		local pool = {}
		for _, c in ipairs(palette) do
			if c.name ~= inkName and c.name ~= last then
				table.insert(pool, c)
			end
		end
		if #pool == 0 then
			return
		end
		local c = pool[math.random(1, #pool)]
		last = c.name
		Voice.say(c.name, function()
			task.delay(gap, step)
		end)
	end

	task.spawn(step)

	return function()
		token = token + 1
	end
end

return Voice
