--!nonstrict
--[[
	STROOP - client.

	Owns the whole screen: the menu, the solo run, the lobby match and the
	stage 4 boss. The solo run is driven entirely here, exactly as it was in the
	browser; the lobby match takes its rounds from the server instead of from a
	polled Firestore document.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stroop = ReplicatedStorage:WaitForChild("Stroop")
local Config = require(Stroop.Config)
local Util = require(Stroop.Util)
local Rounds = require(Stroop.Rounds)
local Net = require(Stroop.Net)

local Theme = require(script.Theme)
local Ui = require(script.Ui)
local Motion = require(script.Motion)
local Root = require(script.Root)
local Cards = require(script.Cards)
local Play = require(script.Play)
local Audio = require(script.Audio)
local Voice = require(script.Voice)
local Boss = require(script.Boss)

local player = Players.LocalPlayer
local remotes = Net.get()

-- ============================================================
-- chrome
-- ============================================================
-- The game is the whole screen, so the default Roblox HUD is out of the way.
local function hideCoreGui()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		if ok then
			return
		end
		task.wait(0.2)
	end
end
task.spawn(hideCoreGui)

task.spawn(function()
	local camera = workspace.CurrentCamera
	while not camera do
		task.wait(0.1)
		camera = workspace.CurrentCamera
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(0, 500, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
end)

-- ============================================================
-- build
-- ============================================================
Root.build()
Cards.build()
Boss.build()

Root.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(Root.relayout)
Root.app:GetPropertyChangedSignal("AbsoluteSize"):Connect(Root.relayout)
task.defer(Root.relayout)

-- ============================================================
-- state
-- ============================================================
local score = 0
local lives = Config.LIVES_START
local best = 0

local soloCorrect, soloRound, soloActive, soloSession = 0, 0, false, 0

local lobby = {
	code = nil,
	isHost = false,
	inGame = false,
	players = {},
	targetScore = nil,
	round = nil,
	answered = false,
	finished = false,
}

local function setScore(value)
	score = value
	Play.setScore(value)
end

local function setBest(value)
	if value <= best then
		return
	end
	best = value
	Play.setBest(value)
	remotes.SaveBest:FireServer(math.floor(value))
end

local function setLives(value)
	lives = value
	Play.lives = value
	Play.renderLives()
end

Play.setScore(0)
Play.setBest(0)
setLives(Config.LIVES_START)

remotes.BestScore.OnClientEvent:Connect(function(value)
	if type(value) == "number" and value > best then
		best = value
		Play.setBest(value)
	end
end)

-- ============================================================
-- menu helpers
-- ============================================================
local function showCard(name)
	Cards.show(name)
end

local function leaveLobbyState()
	if lobby.code then
		remotes.LeaveLobby:FireServer()
	end
	lobby.code = nil
	lobby.isHost = false
	lobby.inGame = false
	lobby.players = {}
	lobby.targetScore = nil
	lobby.round = nil
	lobby.answered = false
	lobby.finished = false
	Play.showLiveboard(false)
	Root.goalMetric.frame.Visible = false
	Root.bestMetric.frame.Visible = true
	Root.lives.Visible = true
end

local function exitToMenu()
	if Boss.isRunning() then
		return -- no way out mid boss fight
	end
	if not Root.inGame then
		return
	end
	soloSession = soloSession + 1
	soloActive = false
	Play.stopTimer()
	Voice.cancel()
	if not lobby.code and score > best then
		setBest(score)
	end
	leaveLobbyState()
	Play.transitionOutOfPlay()
	showCard("menu")
	Root.overlay.Visible = true
	Motion.keyframes(0.5, function(p)
		Root.overlay.BackgroundTransparency = Util.lerp(1, 0.07, p)
	end, Motion.ease.ease)
end

-- ============================================================
-- solo
-- ============================================================
local soloNewRound, enterStage4FromStage3, endSoloSession

-- Runs fn only if the solo run that scheduled it is still the live one.
local function soloLater(fn, delay)
	local sess = soloSession
	task.delay(delay, function()
		if sess == soloSession then
			fn()
		end
	end)
end

local function soloAnswer(isCorrect, selectedEntry, correctName)
	if not soloActive then
		return
	end
	soloActive = false
	Play.stopTimer()
	Play.lockOptions(correctName, selectedEntry, isCorrect)

	if isCorrect then
		Play.pulseOk()
		soloCorrect = soloCorrect + 1
		setScore(score + 100 + math.floor(soloCorrect / 2) * 10)
		soloLater(
			soloCorrect >= Config.SOLO_STAGE4_AT and enterStage4FromStage3 or soloNewRound,
			0.46
		)
	else
		Play.pulseBad()
		if selectedEntry then
			Audio.thud() -- wrong click - a timeout stays silent
		end
		setLives(lives - 1)
		if lives <= 0 then
			soloLater(endSoloSession, 0.6)
		else
			soloLater(soloNewRound, 0.65)
		end
	end
end

soloNewRound = function()
	soloRound = soloRound + 1
	local stage = Rounds.soloStage(soloCorrect)
	local data = Rounds.build(soloRound, stage)
	Play.setStage(stage)
	Play.applyBackdrop(stage, data.inkName, data.tintName)
	soloActive = true
	Play.renderChallenge(
		stage,
		data.wordName,
		Config.BY_NAME[data.inkName].hex,
		data.options,
		data.optionInk,
		function(name, entry)
			soloAnswer(name == data.inkName, entry, data.inkName)
		end
	)
	if data.audioName then
		Voice.say(data.audioName)
	end

	-- Stage 3 resets the clock to full and then decays at the slower rate.
	local dur
	if stage == 3 then
		dur = math.max(
			Config.MIN_TIME,
			Config.BASE_TIME - (soloCorrect - Config.SOLO_STAGE3_AT) * Config.STAGE3_DECREMENT
		)
	else
		dur = math.max(Config.MIN_TIME, Config.BASE_TIME - soloCorrect * Config.TIME_DECREMENT)
	end
	Play.startTimerBar(dur, dur, function()
		if soloActive then
			soloAnswer(false, nil, data.inkName)
		end
	end)
end

endSoloSession = function()
	soloActive = false
	Play.transitionOutOfPlay()
	setBest(score)
	Cards.over.eyebrow:setText("SESSION ENDED")
	Cards.over.headline.Text = "Session complete"
	Cards.over.headline.TextSize = 27
	Cards.over.headlineRow.Size = UDim2.new(1, 0, 0, math.ceil(27 * 1.25) + 14)
	Cards.over.stats.SCORE.value.Text = tostring(math.floor(score))
	Cards.over.stats.STAGE.value.Text = tostring(Rounds.soloStage(soloCorrect))
	Cards.over.stats.BEST.value.Text = tostring(math.floor(best))
	Cards.over.stats.BEST.frame.Visible = true
	Cards.over.rosterRow.Visible = false
	Cards.over.restart.Parent.Visible = true
	Cards.over.waitNote.Parent.Visible = false
	Cards.over.leave.Parent.Visible = false
	Cards.over.returnBtn.Parent.Visible = true
	showCard("over")
end

local function startSoloGame()
	soloSession = soloSession + 1
	local sess = soloSession
	leaveLobbyState()
	setScore(0)
	setLives(Config.LIVES_START)
	soloCorrect, soloRound = 0, 0
	Root.lives.Visible = true
	Root.bestMetric.frame.Visible = true
	Root.goalMetric.frame.Visible = false
	Root.waitingMsg.Visible = false
	Play.setStage(1)
	Play.resetTimerBar()

	task.spawn(function()
		Play.transitionIntoPlay()
		if sess ~= soloSession then
			return
		end
		Play.runIntroCountdown(2.6)
		task.wait(2.6)
		if sess == soloSession then
			soloNewRound()
		end
	end)
end

-- ============================================================
-- stage 4 handoff
-- ============================================================
Boss.getScore = function()
	return score
end
Boss.setScore = function(value)
	setScore(value)
end
Boss.getBest = function()
	return best
end
Boss.setBest = function(value)
	setBest(value)
end
Boss.onSoloCorrect = function()
	soloCorrect = soloCorrect + 1
end
Boss.onExit = function()
	Play.transitionOutOfPlay()
	showCard("menu")
	Root.overlay.Visible = true
	Root.overlay.BackgroundTransparency = 0.07
end

-- Everything still on screen dissolves before the black comes in.
local function dissolvePlaySurface()
	soloActive = false
	Play.stopTimer()
	Play.stopFlash()
	Voice.cancel()
	local fromTint = Root.bgTint.BackgroundTransparency
	Motion.keyframes(1.12, function(p)
		Root.setGroupTransparency(p)
		Root.bgTint.BackgroundTransparency = Util.lerp(fromTint, 1, p)
	end, Motion.ease.ease)
end

enterStage4FromStage3 = function()
	soloSession = soloSession + 1 -- the boss owns the run from here
	Boss.enterFromStage3(dissolvePlaySurface)
	-- the surface is fully faded by now, so resetting it is invisible
	task.delay(1.25, Play.transitionOutOfPlay)
end

local function fadeMenuOut()
	local card = nil
	for _, c in pairs(Cards.list) do
		if c.Visible then
			card = c
			break
		end
	end
	if not card then
		return
	end
	Motion.keyframes(0.88, function(p)
		Play.fadeCardContents(card, p)
	end, Motion.ease.ease)
	task.delay(0.95, function()
		Root.overlay.Visible = false
		Cards.hideAll()
		Play.restoreCard(card)
	end)
end

-- ============================================================
-- lobby
-- ============================================================
local function prepLobbyPlaySurface()
	setScore(0)
	Root.lives.Visible = false -- no lives in multiplayer
	Root.bestMetric.frame.Visible = false
	Root.goalMetric.frame.Visible = true
	Root.waitingMsg.Visible = false
	Play.setStage(1)
	Play.resetTimerBar()
	lobby.round = nil
	lobby.answered = false
	lobby.finished = false
end

local function revealRound(round)
	if round ~= lobby.round then
		return
	end
	Play.clearCountdown()
	Root.waitingMsg.Visible = false
	Play.applyBackdrop(round.stage, round.inkName, round.tintName)
	Play.renderChallenge(
		round.stage,
		round.wordName,
		Config.BY_NAME[round.inkName].hex,
		round.options,
		round.optionInk,
		function(name, entry)
			Play.lobbyAnswerFn(name, entry, round)
		end
	)
	if round.audioName then
		Voice.say(round.audioName)
	end
	local remaining = round.timerDuration - (workspace:GetServerTimeNow() - round.startedAt)
	Play.startTimerBar(math.max(0, remaining), round.timerDuration, function()
		Play.lobbyAnswerFn(nil, nil, round)
	end)
end

--[[
	Placement feedback.

	Points are finalised by the server once the round resolves, so the exact
	placement of an early answerer genuinely isn't knowable at click time. A
	provisional placement is shown from the players who have already submitted,
	then reconciled against the authoritative score once it lands.
]]
local function showPlacementFeedback(correct, timedOut, elapsed, roundNumber)
	Play.placementRound = roundNumber
	if timedOut then
		Play.renderPlacement("bro didn't click anything \u{1F62D} +0")
		return
	end
	if not correct then
		Play.renderPlacement("incorrect \u{1F921} +0")
		return
	end

	local total = math.max(1, #lobby.players)
	local faster = 0
	for _, p in ipairs(lobby.players) do
		if p.userId ~= player.UserId
			and (p.answeredRound or -1) >= roundNumber
			and (p.elapsed or 0) < elapsed then
			faster = faster + 1
		end
	end
	local rank = faster + 1
	Play.renderPlacement(
		Play.placementLabel(rank, total) .. " +" .. math.max(0, total - faster)
	)
end

local function reconcilePlacement(actualGain)
	if not Root.placement.Visible then
		return
	end
	local shown = Root.placement.Text:match("%+(%d+)$")
	if not shown or tonumber(shown) == actualGain then
		return
	end
	if actualGain <= 0 then
		Play.renderPlacement("incorrect \u{1F921} +0")
		return
	end
	Root.placement.Text = Root.placement.Text:gsub("%+%d+$", "+" .. actualGain)
end

Play.lobbyAnswerFn = function(selectedName, entry, round)
	if lobby.answered or not round or round ~= lobby.round then
		return
	end
	lobby.answered = true
	Play.stopTimer()

	local correct = (selectedName == round.inkName)
	Play.lockOptions(round.inkName, entry, correct)
	if not correct and selectedName then
		Audio.thud() -- wrong click - a timeout stays silent
	end

	local elapsed = workspace:GetServerTimeNow() - round.startedAt
	if correct then
		Play.pulseOk()
	else
		Play.pulseBad()
	end

	-- Write the answer first so other clients can rank us, then show our own
	-- provisional placement from whatever data is already local.
	remotes.SubmitAnswer:FireServer(round.roundNumber, selectedName, elapsed)
	showPlacementFeedback(correct, selectedName == nil, elapsed, round.roundNumber)
	Root.waitingMsg.Visible = false
end

local function renderRoundFromServer(round)
	lobby.round = round
	lobby.answered = false
	Play.hidePlacement()
	Play.clearCountdown()
	Play.stopFlash()
	Play.setStage(round.stage)
	Play.resetTimerBar()

	local untilReveal = round.startedAt - workspace:GetServerTimeNow()
	if untilReveal > 0.12 then
		Root.waitingMsg.Visible = false
		Play.runIntroCountdown(untilReveal)
		task.delay(untilReveal, function()
			revealRound(round)
		end)
	else
		revealRound(round)
	end
end

local function showLobbyFinished(info)
	lobby.inGame = false
	lobby.finished = true
	Play.transitionOutOfPlay()
	setBest(score)

	local iWon = (info.winnerId == player.UserId)
	Cards.over.eyebrow:setText("MATCH COMPLETE")
	Cards.over.headline.Text = iWon and "W" or "L"
	Cards.over.headline.TextSize = Root.m.resultSize
	Cards.over.headlineRow.Size = UDim2.new(1, 0, 0, math.ceil(Root.m.resultSize * 1.05) + 10)
	Cards.over.stats.SCORE.value.Text = tostring(math.floor(score))
	Cards.over.stats.STAGE.value.Text = tostring(info.stage or 1)
	Cards.over.stats.BEST.frame.Visible = false
	Cards.over.returnBtn.Parent.Visible = false
	Cards.over.restart.Parent.Visible = lobby.isHost
	Cards.over.waitNote.Parent.Visible = not lobby.isHost
	Cards.over.leave.Parent.Visible = true
	Cards.over.rosterRow.Visible = true
	Cards.renderRoster(Cards.over.roster, info.players or {})
	showCard("over")
end

local function enterLobbyScreen(initial)
	Cards.lobby.code:setText(lobby.code or "------")
	Cards.lobby.play.Parent.Visible = lobby.isHost
	Cards.lobby.waitNote.Parent.Visible = not lobby.isHost
	Cards.lobby.target.TextEditable = lobby.isHost
	if initial then
		lobby.players = initial.players or {}
		lobby.targetScore = initial.targetScore
		if initial.targetScore then
			Play.setGoal(initial.targetScore)
		end
		Cards.renderRoster(Cards.lobby.roster, lobby.players)
		Play.renderLiveboard(lobby.players, player.UserId)
	end
	showCard("lobby")
	Play.showLiveboard(true)
end

remotes.LobbyState.OnClientEvent:Connect(function(state)
	if not state or state.code ~= lobby.code then
		return
	end
	lobby.players = state.players or {}
	lobby.isHost = (state.hostId == player.UserId)
	lobby.targetScore = state.targetScore
	if state.targetScore then
		Play.setGoal(state.targetScore)
	end
	Cards.renderRoster(Cards.lobby.roster, lobby.players)
	Play.renderLiveboard(lobby.players, player.UserId)

	if Cards.list.cardLobby.Visible then
		Cards.lobby.play.Parent.Visible = lobby.isHost
		Cards.lobby.waitNote.Parent.Visible = not lobby.isHost
	end

	-- a guest dropping into a match already under way
	if state.status == "active" and not lobby.inGame and not Boss.isRunning() then
		lobby.inGame = true
		task.spawn(function()
			prepLobbyPlaySurface()
			Play.transitionIntoPlay()
			Play.showLiveboard(true)
		end)
	end
end)

remotes.RoundStart.OnClientEvent:Connect(function(round)
	if not lobby.code or not round then
		return
	end
	lobby.inGame = true
	renderRoundFromServer(round)
end)

remotes.ScoreUpdate.OnClientEvent:Connect(function(newScore, gained)
	local delta = newScore - score
	setScore(newScore)
	if delta > 0 then
		Play.showScorePop(delta)
	end
	if delta ~= 0 or Play.placementRound >= 0 then
		reconcilePlacement(gained or delta)
	end
end)

remotes.MatchFinished.OnClientEvent:Connect(function(info)
	if not lobby.code then
		return
	end
	showLobbyFinished(info)
end)

-- ============================================================
-- wiring
-- ============================================================
local function wireButton(btn, fn)
	btn.MouseButton1Click:Connect(function()
		Audio.click()
		fn()
	end)
end

wireButton(Cards.menu.solo, function()
	leaveLobbyState()
	showCard("brief")
end)
wireButton(Cards.menu.create, function()
	showCard("create")
end)
wireButton(Cards.menu.join, function()
	showCard("join")
end)
wireButton(Cards.create.back, function()
	showCard("menu")
end)
wireButton(Cards.join.back, function()
	showCard("menu")
end)
wireButton(Cards.brief.start, startSoloGame)
wireButton(Cards.brief.back, function()
	showCard("menu")
end)

wireButton(Cards.create.submit, function()
	local name = Util.escapeName(Cards.create.name.Text)
	Cards.create.err.Text = ""
	Cards.create.submitLabel:setText("CREATING\u{2026}")
	task.spawn(function()
		local ok, result = pcall(function()
			return remotes.CreateLobby:InvokeServer(name)
		end)
		Cards.create.submitLabel:setText("CREATE")
		if not ok or not result or not result.ok then
			Cards.create.err.Text = (result and result.err) or "Could not create lobby."
			return
		end
		lobby.code = result.code
		lobby.isHost = true
		enterLobbyScreen(result)
	end)
end)

wireButton(Cards.join.submit, function()
	local code = Cards.join.code.Text:upper():gsub("%s", "")
	local name = Util.escapeName(Cards.join.name.Text)
	Cards.join.err.Text = ""
	if code == "" then
		Cards.join.err.Text = "Enter a code."
		return
	end
	Cards.join.submitLabel:setText("JOINING\u{2026}")
	task.spawn(function()
		local ok, result = pcall(function()
			return remotes.JoinLobby:InvokeServer(code, name)
		end)
		Cards.join.submitLabel:setText("JOIN")
		if not ok or not result or not result.ok then
			Cards.join.err.Text = (result and result.err) or "Could not join."
			return
		end
		lobby.code = result.code
		lobby.isHost = (result.hostId == player.UserId)
		enterLobbyScreen(result)
	end)
end)

wireButton(Cards.lobby.play, function()
	if not lobby.isHost then
		return
	end
	task.spawn(function()
		prepLobbyPlaySurface()
		remotes.StartMatch:FireServer()
		Play.transitionIntoPlay()
		Play.showLiveboard(true)
	end)
end)

wireButton(Cards.lobby.leave, function()
	leaveLobbyState()
	Play.transitionOutOfPlay()
	showCard("menu")
end)
wireButton(Cards.over.leave, function()
	leaveLobbyState()
	Play.transitionOutOfPlay()
	showCard("menu")
end)
wireButton(Cards.over.returnBtn, function()
	leaveLobbyState()
	Play.transitionOutOfPlay()
	showCard("menu")
end)
wireButton(Cards.over.restart, function()
	if lobby.code and lobby.isHost then
		task.spawn(function()
			prepLobbyPlaySurface()
			remotes.RestartMatch:FireServer()
			Play.transitionIntoPlay()
			Play.showLiveboard(true)
		end)
	elseif not lobby.code then
		startSoloGame()
	end
end)

Cards.lobby.target.FocusLost:Connect(function()
	if not lobby.isHost then
		return
	end
	local value = tonumber(Cards.lobby.target.Text)
	remotes.SetTarget:FireServer(value)
end)

Root.leaveBtn.MouseButton1Click:Connect(function()
	Audio.click()
	exitToMenu()
end)
Root.brandBtn.MouseButton1Click:Connect(function()
	Audio.click()
	exitToMenu()
end)

-- ============================================================
-- developer previews
-- ============================================================
-- Typing this code into the lobby-code box reveals the stage 4 previews.
local DEV_CODE = "DEVMODE"

Cards.join.code:GetPropertyChangedSignal("Text"):Connect(function()
	if Cards.join.code.Text:upper():gsub("%s", "") == DEV_CODE then
		Cards.menu.devRow.Visible = true
		Cards.join.code.Text = ""
		showCard("menu")
		Root.relayout()
	end
end)

local function devButton(id, fn)
	local btn = Cards.menu.devButtons[id]
	if btn then
		wireButton(btn, fn)
	end
end

devButton("boss", function()
	Boss.startTest(fadeMenuOut)
end)
devButton("win", function()
	Boss.startEndingTest(true, fadeMenuOut)
end)
devButton("loss", function()
	Boss.startEndingTest(false, fadeMenuOut)
end)
for _, layout in ipairs({
	"grid", "orbit", "pulse", "fall", "drift", "dvd",
	"alternate", "decoy", "spotlight", "blink", "ribbon",
}) do
	devButton(layout, function()
		setScore(0)
		soloCorrect = Config.SOLO_STAGE4_AT
		Boss.startLayoutTest(layout, fadeMenuOut)
	end)
end

-- ============================================================
-- keyboard
-- ============================================================
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		exitToMenu()
	end
end)

-- ============================================================
-- start
-- ============================================================
Theme.reset()
Play.renderLives()
showCard("menu")
print("[Stroop] client ready")
