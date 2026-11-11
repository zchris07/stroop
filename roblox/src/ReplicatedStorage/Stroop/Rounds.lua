--!nonstrict
-- Round construction, shared by the solo run (client-side) and the lobby
-- (server-side) so both modes hand out exactly the same kind of challenge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Stroop.Config)
local Util = require(ReplicatedStorage.Stroop.Util)

local Rounds = {}

function Rounds.numButtonsForStage(s)
	if s == 1 then
		return 3
	elseif s == 2 then
		return 5
	end
	return 9
end

-- stage3StartRound: the round number on which stage 3 first began. Once stage 3
-- starts the clock resets to BASE_TIME and decays more slowly.
function Rounds.timerDuration(roundNumber, stage, stage3StartRound)
	if stage == 3 and stage3StartRound then
		local roundsIn = math.max(0, roundNumber - stage3StartRound)
		return math.max(Config.MIN_TIME, Config.BASE_TIME - roundsIn * Config.STAGE3_DECREMENT)
	end
	return math.max(Config.MIN_TIME, Config.BASE_TIME - (roundNumber - 1) * Config.TIME_DECREMENT)
end

function Rounds.build(roundNumber, stage, stage3StartRound)
	local n = Rounds.numButtonsForStage(stage)
	local wordMeaning = Util.pick(Config.COLORS)
	local inkColor = Util.pick(Util.filter(Config.COLORS, function(c)
		return c.name ~= wordMeaning.name
	end))

	local options
	if n >= #Config.COLORS then
		options = Util.shuffle(Config.COLORS)
	else
		local pool = Util.filter(Config.COLORS, function(c)
			return c.name ~= inkColor.name
		end)
		local rest = Util.shuffle(pool)
		local picked = { inkColor }
		for i = 1, n - 1 do
			table.insert(picked, rest[i])
		end
		options = Util.shuffle(picked)
	end

	local optionInk = nil
	if stage == 3 then
		-- yellow is too light to read as a button colour
		optionInk = Util.map(options, function(o)
			return Util.pick(Util.filter(Config.COLORS, function(c)
				return c.name ~= o.name and c.name ~= "YELLOW"
			end)).name
		end)
	end

	local notInk = Util.filter(Config.COLORS, function(c)
		return c.name ~= inkColor.name
	end)
	local tintName = stage >= 2 and Util.pick(notInk).name or nil
	local audioName = stage == 3 and Util.pick(notInk).name or nil

	return {
		roundNumber = roundNumber,
		stage = stage,
		wordName = wordMeaning.name,
		inkName = inkColor.name,
		options = Util.map(options, function(c)
			return c.name
		end),
		optionInk = optionInk,
		tintName = tintName,
		audioName = audioName,
		timerDuration = Rounds.timerDuration(roundNumber, stage, stage3StartRound),
	}
end

-- Multiplayer stage gate: how far through the target score the leader is.
function Rounds.stageForProgress(topScore, target)
	if not target or target <= 0 then
		return 1
	end
	if topScore >= target * 2 / 3 then
		return 3
	end
	if topScore >= target / 3 then
		return 2
	end
	return 1
end

-- Solo stage gate: how many correct answers so far.
function Rounds.soloStage(correct)
	if correct >= Config.SOLO_STAGE4_AT then
		return 4
	end
	if correct >= Config.SOLO_STAGE3_AT then
		return 3
	end
	if correct >= Config.SOLO_STAGE2_AT then
		return 2
	end
	return 1
end

return Rounds
