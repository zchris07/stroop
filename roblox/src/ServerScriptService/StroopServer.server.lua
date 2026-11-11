--!nonstrict
--[[
	STROOP - server.

	Replaces the Firebase lobby documents from the web build. The web version
	elected one player as "host" and had their browser poll Firestore to score
	each round; here the server owns that loop outright, so scoring is
	authoritative and there is no polling latency. The rules it applies are the
	same ones the host loop applied:

	  * rank everyone who answered by reaction time, unanswered sorts last
	  * a correct answer at rank i (0-based) of n players scores (n - i)
	  * first player to reach the target score wins and the match ends
	  * stage advances with the leader's progress toward the target

	It also flips the place into "pure UI" mode: no characters, no world.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local Stroop = ReplicatedStorage:WaitForChild("Stroop")
local Config = require(Stroop.Config)
local Util = require(Stroop.Util)
local Rounds = require(Stroop.Rounds)
local Net = require(Stroop.Net)

local remotes = Net.build()

-- ============================================================
-- place setup - the game is entirely a screen, so nothing spawns
-- ============================================================
Players.CharacterAutoLoads = false
pcall(function()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(10, 12, 18)
	Lighting.OutdoorAmbient = Color3.fromRGB(10, 12, 18)
	Lighting.GlobalShadows = false
	Lighting.FogEnd = 1e6
end)

-- ============================================================
-- best score persistence
-- ============================================================
local bestStore = nil
pcall(function()
	bestStore = DataStoreService:GetDataStore("StroopBest_v1")
end)

local sessionBest = {} -- userId -> number, always kept so play works without API access

local function loadBest(player)
	local uid = player.UserId
	local value = sessionBest[uid] or 0
	if bestStore and uid > 0 then
		local ok, stored = pcall(function()
			return bestStore:GetAsync("u_" .. uid)
		end)
		if ok and type(stored) == "number" then
			value = math.max(value, stored)
		end
	end
	sessionBest[uid] = value
	return value
end

local function saveBest(player, score)
	local uid = player.UserId
	if type(score) ~= "number" or score ~= score or score < 0 or score > 1e9 then
		return
	end
	score = math.floor(score)
	if score <= (sessionBest[uid] or 0) then
		return
	end
	sessionBest[uid] = score
	if bestStore and uid > 0 then
		pcall(function()
			bestStore:UpdateAsync("u_" .. uid, function(old)
				if type(old) == "number" and old >= score then
					return nil
				end
				return score
			end)
		end)
	end
end

-- ============================================================
-- lobbies
-- ============================================================
--[[
	lobby = {
		code, hostId, status = "waiting" | "active" | "finished",
		roundNumber, targetScore, customTargetScore, stage3StartRound,
		winnerId, winnerName,
		round = { ...Rounds.build(), startedAt = <server clock> },
		resolved = <bool: has this round been scored yet>,
		players = { [userId] = { userId, name, score, answeredRound, correct, elapsed, joinedAt } },
	}
]]
local lobbies = {}
local playerLobby = {} -- userId -> code

local function now()
	return workspace:GetServerTimeNow()
end

local function genCode()
	local chars = Config.LOBBY_CODE_CHARS
	for _ = 1, 400 do
		local c = ""
		for _ = 1, Config.LOBBY_CODE_LEN do
			local i = Util.randInt(1, #chars)
			c = c .. chars:sub(i, i)
		end
		if not lobbies[c] then
			return c
		end
	end
	return nil
end

local function roster(lobby)
	local list = {}
	for _, p in pairs(lobby.players) do
		table.insert(list, {
			userId = p.userId,
			name = p.name,
			score = p.score,
			answeredRound = p.answeredRound,
			elapsed = p.elapsed,
		})
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.name < b.name
	end)
	return list
end

local function defaultTarget(lobby)
	local n = 0
	for _ in pairs(lobby.players) do
		n = n + 1
	end
	return 10 * math.max(1, n)
end

local function broadcast(lobby, event, ...)
	for uid in pairs(lobby.players) do
		local player = Players:GetPlayerByUserId(uid)
		if player then
			remotes[event]:FireClient(player, ...)
		end
	end
end

local function pushState(lobby)
	broadcast(lobby, "LobbyState", {
		code = lobby.code,
		hostId = lobby.hostId,
		status = lobby.status,
		targetScore = lobby.targetScore or defaultTarget(lobby),
		customTargetScore = lobby.customTargetScore,
		roundNumber = lobby.roundNumber,
		players = roster(lobby),
	})
end

local function destroyLobby(code)
	lobbies[code] = nil
end

local function removePlayer(player)
	local code = playerLobby[player.UserId]
	if not code then
		return
	end
	playerLobby[player.UserId] = nil
	local lobby = lobbies[code]
	if not lobby then
		return
	end
	lobby.players[player.UserId] = nil

	local remaining = 0
	for _ in pairs(lobby.players) do
		remaining = remaining + 1
	end
	if remaining == 0 then
		destroyLobby(code)
		return
	end
	-- hand the host role to whoever joined earliest
	if lobby.hostId == player.UserId then
		local oldest, oldestAt = nil, math.huge
		for uid, p in pairs(lobby.players) do
			if p.joinedAt < oldestAt then
				oldest, oldestAt = uid, p.joinedAt
			end
		end
		lobby.hostId = oldest
	end
	pushState(lobby)
end

local function startRound(lobby, roundNumber, stage, delay)
	local round = Rounds.build(roundNumber, stage, lobby.stage3StartRound)
	round.startedAt = now() + delay
	lobby.round = round
	lobby.roundNumber = roundNumber
	lobby.resolved = false
	for _, p in pairs(lobby.players) do
		p.answeredRound = p.answeredRound or -1
	end
	broadcast(lobby, "RoundStart", round)
end

local function beginMatch(lobby)
	lobby.status = "active"
	lobby.winnerId = nil
	lobby.winnerName = nil
	lobby.stage3StartRound = nil
	lobby.targetScore = lobby.customTargetScore or defaultTarget(lobby)
	for _, p in pairs(lobby.players) do
		p.score = 0
		p.answeredRound = -1
		p.correct = false
		p.elapsed = 0
	end
	pushState(lobby)
	startRound(lobby, 1, 1, Config.INTRO_DELAY)
end

-- The old host loop, now running server-side.
local function resolveRound(lobby)
	local round = lobby.round
	if not round or lobby.resolved then
		return
	end

	local list = {}
	for _, p in pairs(lobby.players) do
		table.insert(list, p)
	end
	if #list == 0 then
		return
	end

	local allAnswered = true
	for _, p in ipairs(list) do
		if (p.answeredRound or -1) < round.roundNumber then
			allAnswered = false
			break
		end
	end
	local elapsed = now() - round.startedAt
	local timedOut = elapsed >= round.timerDuration + Config.ROUND_GRACE
	if not (allAnswered or timedOut) then
		return
	end

	lobby.resolved = true

	-- rank by reaction time; unanswered sorts last
	table.sort(list, function(a, b)
		local ea = ((a.answeredRound or -1) >= round.roundNumber) and (a.elapsed or 0) or math.huge
		local eb = ((b.answeredRound or -1) >= round.roundNumber) and (b.elapsed or 0) or math.huge
		if ea ~= eb then
			return ea < eb
		end
		return a.userId < b.userId
	end)

	local n = #list
	local winner, topScore = nil, 0
	for i, p in ipairs(list) do
		local answered = (p.answeredRound or -1) >= round.roundNumber
		local gained = (answered and p.correct) and (n - (i - 1)) or 0
		p.score = (p.score or 0) + gained
		if p.score > topScore then
			topScore = p.score
		end
		local player = Players:GetPlayerByUserId(p.userId)
		if player then
			remotes.ScoreUpdate:FireClient(player, p.score, gained, round.roundNumber)
		end
		if lobby.targetScore and p.score >= lobby.targetScore and not winner then
			winner = p
		end
	end

	if winner then
		lobby.status = "finished"
		lobby.winnerId = winner.userId
		lobby.winnerName = winner.name
		pushState(lobby)
		broadcast(lobby, "MatchFinished", {
			winnerId = winner.userId,
			winnerName = winner.name,
			players = roster(lobby),
			stage = round.stage,
		})
		return
	end

	local nextRoundNumber = round.roundNumber + 1
	local nextStage = Rounds.stageForProgress(topScore, lobby.targetScore)
	-- Record the round stage 3 began on, so the timer can reset there and then
	-- decay at the slower stage-3 rate from that point.
	if nextStage == 3 and not lobby.stage3StartRound then
		lobby.stage3StartRound = nextRoundNumber
	end
	pushState(lobby)
	startRound(lobby, nextRoundNumber, nextStage, Config.REVEAL_DELAY)
end

RunService.Heartbeat:Connect(function()
	for _, lobby in pairs(lobbies) do
		if lobby.status == "active" then
			local ok, err = pcall(resolveRound, lobby)
			if not ok then
				warn("[Stroop] round resolution failed: " .. tostring(err))
			end
		end
	end
end)

-- ============================================================
-- remote handlers
-- ============================================================
local function newPlayerRecord(player, name)
	return {
		userId = player.UserId,
		name = name,
		score = 0,
		answeredRound = -1,
		correct = false,
		elapsed = 0,
		joinedAt = now(),
	}
end

remotes.CreateLobby.OnServerInvoke = function(player, name)
	removePlayer(player)
	name = Util.escapeName(name)
	local code = genCode()
	if not code then
		return { ok = false, err = "Too many lobbies open right now." }
	end
	local lobby = {
		code = code,
		hostId = player.UserId,
		status = "waiting",
		roundNumber = 0,
		players = {},
	}
	lobby.players[player.UserId] = newPlayerRecord(player, name)
	lobbies[code] = lobby
	playerLobby[player.UserId] = code
	task.defer(pushState, lobby)
	-- The roster travels with the reply as well as in the push: the client only
	-- learns its own code when this returns, so a push that beats the reply
	-- would be discarded as belonging to some other lobby.
	return {
		ok = true,
		code = code,
		hostId = lobby.hostId,
		status = lobby.status,
		targetScore = defaultTarget(lobby),
		players = roster(lobby),
	}
end

remotes.JoinLobby.OnServerInvoke = function(player, code, name)
	code = tostring(code or ""):upper():gsub("%s", "")
	local lobby = lobbies[code]
	if not lobby then
		return { ok = false, err = "Lobby not found. Check the code." }
	end
	removePlayer(player)
	lobby.players[player.UserId] = newPlayerRecord(player, Util.escapeName(name))
	playerLobby[player.UserId] = code
	task.defer(pushState, lobby)
	-- Someone joining a match already under way drops straight into it.
	if lobby.status == "active" and lobby.round then
		task.defer(function()
			remotes.RoundStart:FireClient(player, lobby.round)
		end)
	end
	return {
		ok = true,
		code = code,
		hostId = lobby.hostId,
		status = lobby.status,
		targetScore = lobby.targetScore or defaultTarget(lobby),
		players = roster(lobby),
	}
end

remotes.StartMatch.OnServerEvent:Connect(function(player)
	local lobby = lobbies[playerLobby[player.UserId] or ""]
	if not lobby or lobby.hostId ~= player.UserId then
		return
	end
	if lobby.status == "active" then
		return
	end
	beginMatch(lobby)
end)

remotes.RestartMatch.OnServerEvent:Connect(function(player)
	local lobby = lobbies[playerLobby[player.UserId] or ""]
	if not lobby or lobby.hostId ~= player.UserId then
		return
	end
	beginMatch(lobby)
end)

remotes.SetTarget.OnServerEvent:Connect(function(player, value)
	local lobby = lobbies[playerLobby[player.UserId] or ""]
	if not lobby or lobby.hostId ~= player.UserId then
		return
	end
	if type(value) == "number" and value > 0 and value < 100000 then
		lobby.customTargetScore = math.floor(value)
	else
		lobby.customTargetScore = nil
	end
	lobby.targetScore = lobby.customTargetScore or defaultTarget(lobby)
	pushState(lobby)
end)

remotes.SubmitAnswer.OnServerEvent:Connect(function(player, roundNumber, selectedName, elapsed)
	local lobby = lobbies[playerLobby[player.UserId] or ""]
	if not lobby or lobby.status ~= "active" or not lobby.round then
		return
	end
	local round = lobby.round
	if round.roundNumber ~= roundNumber then
		return
	end
	local p = lobby.players[player.UserId]
	if not p or (p.answeredRound or -1) >= roundNumber then
		return -- one answer per round
	end

	-- Trust the client's reaction time only within the window it could be in;
	-- anything outside that is clamped to the server's own measurement.
	local serverElapsed = now() - round.startedAt
	if type(elapsed) ~= "number" or elapsed ~= elapsed then
		elapsed = serverElapsed
	end
	elapsed = math.clamp(elapsed, 0, math.max(0, serverElapsed))

	p.answeredRound = roundNumber
	p.elapsed = elapsed
	p.correct = (selectedName ~= nil and selectedName == round.inkName)
	pushState(lobby) -- lets everyone's provisional placement read the live field
end)

remotes.LeaveLobby.OnServerEvent:Connect(function(player)
	removePlayer(player)
end)

remotes.SaveBest.OnServerEvent:Connect(function(player, score)
	saveBest(player, score)
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local best = loadBest(player)
		remotes.BestScore:FireClient(player, best)
	end)
end)

Players.PlayerRemoving:Connect(removePlayer)

-- Players who beat the loading race get their best score on request.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		remotes.BestScore:FireClient(player, loadBest(player))
	end)
end

print("[Stroop] server ready")
