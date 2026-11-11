--!nonstrict
--[[
	STAGE 4 - the boss (solo only).

	Runs in its own full-screen layer so none of the stage 1-3 chrome or layout
	rules apply, exactly as `#boss` did in the page. Everything here is a port of
	that layer: the written intro, the health bar, the eleven challenges, the
	rolling wrong-colour voice, the reactions, and both endings.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Stroop.Config)
local Util = require(ReplicatedStorage.Stroop.Util)

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Motion = require(script.Parent.Motion)
local Audio = require(script.Parent.Audio)
local Voice = require(script.Parent.Voice)

local Chaos = require(script.Chaos)
local Writer = require(script.Writer)
local Layouts = require(script.Layouts)

local Boss = {}

-- ---------- palettes ----------
local BOSS_BG = {}
for _, c in ipairs(Config.COLORS) do
	table.insert(BOSS_BG, c.tint)
end
table.insert(BOSS_BG, "#000000")

local BOSS_SOLID = {}
for _, c in ipairs(Config.COLORS) do
	table.insert(BOSS_SOLID, c.name == "YELLOW" and Config.DARK_YELLOW or c.hex)
end

local BOSS_FILL = Util.concat(Util.concat(BOSS_BG, { "#ffffff" }), BOSS_SOLID)

local BOSS_OUTLINE = {}
for _, c in ipairs(Config.COLORS) do
	table.insert(BOSS_OUTLINE, c.hex)
end
table.insert(BOSS_OUTLINE, Config.DARK_YELLOW)

local ALT_HEX = {}
for _, c in ipairs(Config.ALT_COLORS) do
	table.insert(ALT_HEX, c.hex)
end

-- ---------- typography ----------
-- Stage 4 gives every element a different voice; these stand in for the
-- serif / mono / italic axes the page randomised over.
local SERIF_POOL = {
	Theme.font("Merriweather"),
	Theme.font("Bodoni", Theme.SERIF),
	Theme.font("Garamond", Theme.SERIF),
	Theme.font("Antique", Theme.SERIF),
}
local MONO_POOL = { Theme.font("RobotoMono"), Theme.font("Code") }
local ITALIC_FONT = Theme.font("SourceSansItalic", Theme.font("Nunito"))
local THIN_SPACE = utf8.char(0x2009)

-- ---------- state ----------
local boss = {
	hp = Config.BOSS_MAX_HP,
	timer = Config.BOSS_START_TIME,
	round = 0,
	active = false,
	over = false,
	busy = false,
	lastLayout = nil,
	history = {},
	altUsed = false,
	skipPhase = false,
	forceLayout = nil,
	bag = {},
	reactIdx = 0,
	data = nil,
	word = nil,
	btns = {},
	sim = nil,
	timers = {},
	cleanup = {},
	tStart = 0,
	tTotal = 0,
	canReturn = false,
	stopChaos = nil,
	stopConvulse = nil,
	lives = Config.BOSS_LIVES,
	lastTint = nil,
	stopVoice = nil,
}
Boss.state = boss

local gui, layer, tint, msg, logo, hp, hpFill, timerBar, timerFill
local reactLabel, beginLabel, arena, leaveBtn, livesRow, scoreLabel, hintLabel, clickCatcher
local simConn, timerConn
local activeLines = {}

-- These are supplied by the client bootstrap.
Boss.onExit = nil -- () -> return to the menu
Boss.getScore = nil
Boss.setScore = nil
Boss.getBest = nil
Boss.setBest = nil
Boss.onSoloCorrect = nil

-- ============================================================
-- layer construction
-- ============================================================
local function logoFontSize()
	local w = layer.AbsoluteSize.X
	return math.clamp(w * 0.17, 56, 104)
end

function Boss.build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = Ui.new("ScreenGui", {
		Name = "StroopBoss",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Enabled = false,
		Parent = playerGui,
	})

	layer = Ui.new("Frame", {
		Name = "boss",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BackgroundColor3 = Color3.new(0, 0, 0),
		ClipsDescendants = true,
		ZIndex = 0,
		Parent = gui,
	})

	clickCatcher = Ui.blocker({
		Name = "clickCatcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = layer,
	})

	tint = Ui.new("Frame", {
		Name = "bossTint",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 2,
		Parent = layer,
	})

	msg = Ui.new("Frame", {
		Name = "bossMsg",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 60,
		Parent = layer,
	})

	logo = Chaos.newLogo(layer, "STROOP", 104, 62)
	logo.holder.Visible = false

	hp = Ui.new("Frame", {
		Name = "bossHp",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(400, 4),
		BackgroundTransparency = 1,
		ZIndex = 62,
		Parent = layer,
	})
	hpFill = Ui.new("Frame", {
		Name = "fill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 62,
		Parent = hp,
	})
	Ui.corner(hpFill, 2)

	-- hairline answer clock along the top edge, shrinking toward centre
	timerBar = Ui.new("Frame", {
		Name = "bossTimer",
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundTransparency = 1,
		ZIndex = 63,
		Parent = layer,
	})
	timerFill = Ui.new("Frame", {
		Name = "fill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.4,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 63,
		Parent = timerBar,
	})
	timerBar.Visible = false

	arena = Ui.new("Frame", {
		Name = "bossArena",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 64,
		Parent = layer,
	})

	reactLabel = Ui.new("TextLabel", {
		Name = "bossReact",
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.SourceSans,
		TextSize = 74,
		TextColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(120, 100),
		TextTransparency = 1,
		ZIndex = 68,
		Parent = layer,
	})
	Boss.reactScale = Ui.scale(reactLabel, 0.6)

	beginLabel = Ui.tracked({
		Name = "bossBegin",
		Text = "BEGIN",
		Font = Theme.SERIF,
		TextSize = 48,
		Spacing = 48 * 0.34,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 63,
		Parent = layer,
	})
	beginLabel:setTransparency(1)

	leaveBtn = Ui.new("TextButton", {
		Name = "bossLeave",
		Text = "",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(40, 34),
		Size = UDim2.fromOffset(70, 30),
		Visible = false,
		ZIndex = 70,
		Parent = layer,
	})
	Ui.corner(leaveBtn, 8)
	local leaveStroke = Ui.stroke(leaveBtn, 1.5, Color3.new(1, 1, 1))
	leaveStroke.Transparency = 0.72
	local leaveText = Ui.tracked({
		Name = "label",
		Text = "leave",
		Font = Theme.MONO,
		TextSize = 11,
		Spacing = 11 * 0.14,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 71,
		Parent = leaveBtn,
	})
	leaveText:setColor(Color3.new(1, 1, 1))
	leaveText:setTransparency(0.5)
	leaveBtn.MouseEnter:Connect(function()
		leaveStroke.Transparency = 0
		leaveText:setTransparency(0)
	end)
	leaveBtn.MouseLeave:Connect(function()
		leaveStroke.Transparency = 0.72
		leaveText:setTransparency(0.5)
	end)
	Boss.leaveStroke = leaveStroke
	Boss.leaveText = leaveText

	livesRow = Ui.new("Frame", {
		Name = "bossLives",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -40, 0, 34),
		Size = UDim2.fromOffset(16 * 4 + 14 * 3, 16),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 66,
		Parent = layer,
	})
	local livesLayout = Instance.new("UIListLayout")
	livesLayout.FillDirection = Enum.FillDirection.Horizontal
	livesLayout.Padding = UDim.new(0, 14)
	livesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	livesLayout.Parent = livesRow
	Boss.lifeDots = {}
	for i = 1, Config.BOSS_LIVES do
		local dot = Ui.new("Frame", {
			Name = "dot" .. i,
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.BAD,
			LayoutOrder = i,
			ZIndex = 66,
			Parent = livesRow,
		})
		Ui.corner(dot, 8)
		Ui.stroke(dot, 2, Theme.BAD)
		Boss.lifeDots[i] = dot
	end

	scoreLabel = Ui.new("TextLabel", {
		Name = "bossScore",
		BackgroundTransparency = 1,
		Text = "",
		Font = Theme.SERIF,
		TextSize = 30,
		TextColor3 = Util.hex("#16181d"),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(1, 0, 0, 40),
		TextTransparency = 1,
		ZIndex = 67,
		Parent = layer,
	})

	hintLabel = Ui.tracked({
		Name = "bossHint",
		Text = "click anywhere to return",
		Font = Theme.MONO,
		TextSize = 12,
		Spacing = 12 * 0.14,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -44),
		ZIndex = 67,
		Parent = layer,
	})
	hintLabel:setColor(Util.hex("#5f636d"))
	hintLabel:setTransparency(1)

	Boss.gui, Boss.layer = gui, layer

	clickCatcher.MouseButton1Click:Connect(function()
		if boss.canReturn then
			Boss.returnHome()
		elseif Boss.skipFn then
			Boss.skipFn()
		end
	end)
	leaveBtn.MouseButton1Click:Connect(function()
		Audio.click()
		Boss.quitToMenu()
	end)

	Boss.relayout()
	layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(Boss.relayout)
	return Boss
end

function Boss.relayout()
	if not layer then
		return
	end
	local size = layer.AbsoluteSize
	local fs = logoFontSize()
	if math.abs((logo.size or 0) - fs) > 0.5 then
		logo:setSize(fs)
	end
	-- #bossLogo sits a seventh of the way down, #bossHp just under it
	local logoTop = boss.logoCentred and size.Y * 0.5 or size.Y / 7
	logo.holder.Position = UDim2.fromOffset(size.X / 2, logoTop + (boss.logoEntered and 0 or -size.Y * 0.36))
	hp.Position = UDim2.fromOffset(size.X / 2, size.Y / 7 + fs * 0.5 + 12)
	hp.Size = UDim2.fromOffset(math.max(120, math.min(400, size.X - 80)), 4)
	scoreLabel.Position = UDim2.new(0.5, 0, 0.5, math.floor(math.min(size.Y * 0.33, size.X * 0.29) + 26))
	beginLabel.frame.Position = UDim2.fromScale(0.5, 0.5)
end

-- ============================================================
-- click-to-skip
-- ============================================================
Boss.skipFn = nil

local function snapAll()
	for _, line in ipairs(activeLines) do
		if line.holder and line.holder.Parent then
			line:snap()
		end
	end
	beginLabel:setTransparency(1)
end

--[[
	Cinematic beats await `bwait` instead of `wait`. A click resolves the
	pending beat and snaps whatever is mid-flight to its finished state.

	Each wait remembers which run scheduled it. If the player leaves and the
	layer resets, the generation moves on and the waiting coroutine is simply
	never resumed - so an abandoned intro or death sequence cannot wake up
	later and start drawing over a fresh one.
]]
boss.gen = 0

local function bwait(seconds)
	if seconds <= 0 then
		return
	end
	local thread = coroutine.running()
	local gen = boss.gen
	local done = false
	local handle
	handle = task.delay(seconds, function()
		if done then
			return
		end
		done = true
		Boss.skipFn = nil
		if gen ~= boss.gen then
			return
		end
		task.spawn(thread)
	end)
	Boss.skipFn = function()
		if done then
			return
		end
		done = true
		pcall(task.cancel, handle)
		Boss.skipFn = nil
		if gen ~= boss.gen then
			return
		end
		boss.skipPhase = true
		snapAll()
		task.spawn(thread)
	end
	coroutine.yield()
end

-- Within a phase, one click clears every remaining beat of that phase.
local function phaseStart()
	boss.skipPhase = false
end

local function phaseWait(seconds)
	if boss.skipPhase then
		return
	end
	bwait(seconds)
end

-- ============================================================
-- written lines
-- ============================================================
local function writeLine(text, opts)
	local line = Writer.build(msg, text, opts)
	table.insert(activeLines, line)
	return line
end

local function bossWrite(text, hold)
	local line = writeLine(text)
	bwait(Writer.duration(text))
	bwait(hold)
	local unwriteTime = line:unwrite()
	bwait(unwriteTime)
	line:destroy()
	local i = Util.indexOf(activeLines, line)
	if i then
		table.remove(activeLines, i)
	end
end

-- ============================================================
-- arena lifecycle
-- ============================================================
local function after(seconds, fn)
	local handle = task.delay(seconds, fn)
	table.insert(boss.timers, handle)
	return handle
end

local function stopSim()
	if simConn then
		simConn:Disconnect()
		simConn = nil
	end
	boss.sim = nil
end

local function clearArena()
	for _, handle in ipairs(boss.timers) do
		pcall(task.cancel, handle)
	end
	boss.timers = {}
	stopSim()
	for _, fn in ipairs(boss.cleanup) do
		pcall(fn)
	end
	boss.cleanup = {}
	arena:ClearAllChildren()
	boss.btns = {}
	boss.word = nil
end

local function stopFlash()
	boss.flashToken = (boss.flashToken or 0) + 1
end

local function startFlash(pool)
	stopFlash()
	boss.flashToken = (boss.flashToken or 0) + 1
	local mine = boss.flashToken

	local function next_()
		local opts = Util.filter(pool, function(h)
			return h ~= boss.lastTint
		end)
		boss.lastTint = Util.pick(#opts > 0 and opts or pool)
		local target = Util.hex(boss.lastTint)
		local from = tint.BackgroundColor3
		Motion.keyframes(0.36, function(p)
			tint.BackgroundColor3 = from:Lerp(target, p)
		end, Motion.ease.ease)
		-- the logo, the bar and the clock all relied on difference blending to
		-- stay legible; here they flip between black and white instead
		local readable = Util.readableOn(target)
		logo:setColor(readable)
		hpFill.BackgroundColor3 = readable
		timerFill.BackgroundColor3 = readable
	end

	next_()
	Motion.keyframes(0.9, function(p)
		tint.BackgroundTransparency = 1 - p
	end, Motion.ease.ease)

	task.spawn(function()
		while true do
			task.wait(Config.BOSS_FLASH)
			if mine ~= boss.flashToken then
				return
			end
			next_()
		end
	end)
end

local function hideTint()
	stopFlash()
	local from = tint.BackgroundTransparency
	Motion.keyframes(0.9, function(p)
		tint.BackgroundTransparency = Util.lerp(from, 1, p)
	end, Motion.ease.ease)
	logo:setColor(Color3.new(1, 1, 1))
	hpFill.BackgroundColor3 = Color3.new(1, 1, 1)
	timerFill.BackgroundColor3 = Color3.new(1, 1, 1)
end

function Boss.renderLives()
	for i, dot in ipairs(Boss.lifeDots) do
		local lost = i > boss.lives
		dot.BackgroundTransparency = lost and 1 or 0
		local stroke = dot:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = lost and Util.hex("#8a8f9c") or Theme.BAD
		end
		if lost and not dot:GetAttribute("wasLost") then
			-- @keyframes lifeLost
			local scale = dot:FindFirstChildOfClass("UIScale") or Ui.scale(dot, 1)
			Motion.keyframes(0.6, function(p)
				scale.Scale = p < 0.3 and Util.lerp(1, 1.55, p / 0.3) or Util.lerp(1.55, 1, (p - 0.3) / 0.7)
			end, Motion.ease.ease)
		end
		dot:SetAttribute("wasLost", lost)
	end
end

local function reset()
	boss.gen = boss.gen + 1 -- abandons any beat still waiting on the old run
	gui.Enabled = false
	clearArena()
	stopFlash()
	stopSim()
	if timerConn then
		timerConn:Disconnect()
		timerConn = nil
	end
	if boss.stopChaos then
		boss.stopChaos()
		boss.stopChaos = nil
	end
	if boss.stopConvulse then
		boss.stopConvulse()
		boss.stopConvulse = nil
	end
	if boss.stopVoice then
		boss.stopVoice()
		boss.stopVoice = nil
	end
	Voice.cancel()

	boss.active = false
	boss.over = false
	boss.canReturn = false
	boss.logoCentred = false
	boss.logoEntered = false

	for _, line in ipairs(activeLines) do
		line:destroy()
	end
	activeLines = {}
	msg:ClearAllChildren()

	layer.BackgroundTransparency = 0
	layer.BackgroundColor3 = Color3.new(0, 0, 0)
	tint.BackgroundTransparency = 1
	tint.BackgroundColor3 = Color3.new(0, 0, 0)

	logo:stopBob()
	logo:setVisible(false)
	logo:setColor(Color3.new(1, 1, 1))
	logo:setTransparency(0)
	logo:setFont(Theme.SERIF)
	logo.scale.Scale = 1
	logo.inner.Position = UDim2.fromScale(0.5, 0.5)
	logo.inner.Rotation = 0
	logo.holder.Visible = false

	hp.Visible = true
	hp.BackgroundTransparency = 1
	hpFill.Size = UDim2.new(0, 0, 1, 0)
	hpFill.BackgroundTransparency = 0
	timerBar.Visible = false
	timerFill.Size = UDim2.fromScale(1, 1)
	livesRow.Visible = false
	leaveBtn.Visible = false
	beginLabel:setTransparency(1)
	reactLabel.TextTransparency = 1
	reactLabel.Text = ""
	scoreLabel.Text = ""
	scoreLabel.TextTransparency = 1
	scoreLabel.TextColor3 = Util.hex("#16181d")
	hintLabel:setTransparency(1)
	Boss.relayout()
end
Boss.reset = reset

local function fadeToBlack()
	reset()
	boss.hp = Config.BOSS_MAX_HP
	boss.timer = Config.BOSS_START_TIME
	boss.round = 0
	boss.lastLayout = nil
	boss.history = {}
	boss.altUsed = false
	boss.bag = {}
	boss.reactIdx = 0
	boss.lives = Config.BOSS_LIVES

	gui.Enabled = true
	-- AbsoluteSize is only meaningful once the layer is actually on screen
	task.defer(Boss.relayout)
	layer.BackgroundTransparency = 1
	Motion.keyframes(1.3, function(p)
		layer.BackgroundTransparency = 1 - p
	end, Motion.ease.ease)
	bwait(1.4)
end

-- ============================================================
-- round construction
-- ============================================================
local function buildBossRound(alt, spot)
	local pal = alt and Config.ALT_COLORS or Config.COLORS
	local meaning = Util.pick(pal)
	local ink = Util.pick(Util.filter(pal, function(c)
		return c.name ~= meaning.name and not (spot and c.name == "BLACK")
	end))

	local bg
	if alt then
		bg = Util.filter(ALT_HEX, function(h)
			return h ~= ink.hex and Util.contrast(h, ink.hex) >= 1.35
		end)
		if #bg < 3 then
			bg = Util.filter(ALT_HEX, function(h)
				return h ~= ink.hex
			end)
		end
	else
		-- the original pool never hides the word outright; the stage 4 extras
		-- are added unfiltered
		bg = Util.filter(BOSS_BG, function(h)
			return h ~= ink.tint and Util.contrast(h, ink.hex) >= 1.35
		end)
		if #bg < 3 then
			bg = Util.filter(BOSS_BG, function(h)
				return h ~= ink.tint
			end)
		end
		bg = Util.concat(bg, Util.filter(BOSS_SOLID, function(h)
			return Util.contrast(h, ink.hex) >= 1.5
		end))
	end

	return {
		alt = alt,
		pal = pal,
		wordName = meaning.name,
		ink = ink,
		bg = bg,
		options = Util.map(Util.shuffle(pal), function(c)
			return c.name
		end),
		fill = alt and ALT_HEX or BOSS_FILL,
		outline = alt and ALT_HEX or BOSS_OUTLINE,
	}
end

-- `bossType` - a different typographic voice for every element, every round.
local function bossType(label)
	local serif = Util.chance(0.45)
	local bold = Util.chance(0.45)
	local italic = Util.chance(0.35)
	local spaced = Util.chance(0.4)

	if italic then
		label.Font = ITALIC_FONT
	else
		label.Font = Util.pick(serif and SERIF_POOL or MONO_POOL)
	end

	if bold then
		-- Roblox exposes no bold cut for these faces, so weight is added with a
		-- hairline stroke in the text's own colour.
		local s = Ui.stroke(label, 0.9, label.TextColor3)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		label:SetAttribute("BoldStroke", true)
	end

	-- letter-spacing has no equivalent, so tracking is inserted as thin spaces
	if spaced then
		local out = {}
		for _, code in utf8.codes(label.Text) do
			table.insert(out, utf8.char(code))
		end
		label.Text = table.concat(out, THIN_SPACE)
	end
	return spaced
end

local function protectedBottom()
	return hp.AbsolutePosition.Y - layer.AbsolutePosition.Y + hp.AbsoluteSize.Y + 30
end

local function makeWord(d)
	local size = math.clamp(layer.AbsoluteSize.X * 0.05, 44, 82)
	local holder = Ui.new("Frame", {
		Name = "bword",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, math.ceil(size * 1.15)),
		ZIndex = 64,
		Parent = arena,
	})
	local label = Ui.new("TextLabel", {
		Name = "inner",
		BackgroundTransparency = 1,
		Text = d.wordName,
		Font = Theme.SERIF,
		TextSize = size,
		TextColor3 = Util.hex(d.ink.hex),
		TextTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 64,
		Parent = holder,
	})
	bossType(label)
	local w = Ui.textWidth(label.Text, size, label.Font)
	holder.Size = UDim2.fromOffset(math.ceil(w) + 8, math.ceil(size * 1.15))

	return {
		el = holder,
		inner = label,
		scale = Ui.scale(label, 1),
		x = 0,
		y = 0,
		w = math.ceil(w) + 8,
		h = math.ceil(size * 1.15),
	}
end

local function makeButton(name, circle, d, onAnswer)
	local textHex = Util.pick(Util.filter(d.pal, function(c)
		return c.name ~= name
	end)).hex
	local fill = Util.pick(d.fill)
	for _ = 1, 40 do -- the label must stay readable
		if Util.contrast(textHex, fill) >= 2.6 then
			break
		end
		fill = Util.pick(d.fill)
	end

	local el = Ui.new("TextButton", {
		Name = "bopt",
		Text = "",
		BackgroundTransparency = 0,
		BackgroundColor3 = Util.hex(fill),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(142, 66),
		TextTransparency = 1,
		ZIndex = 65,
		Parent = arena,
	})
	Ui.corner(el, circle and 999 or 14)

	--[[
		If this fill is a near-match for any backdrop the round could show - its
		flashing pool, or the plain black used at rest and in SPOTLIGHT - a
		transparent outline would let the button vanish. Force a real,
		contrasting border in that case instead of rolling the usual dice.
	]]
	local bgPool = Util.concat(d.bg or {}, { "#000000" })
	local invisibleRisk = false
	for _, bgHex in ipairs(bgPool) do
		if Util.contrast(fill, bgHex) < 1.3 then
			invisibleRisk = true
			break
		end
	end

	local borderColor, borderTransparent = nil, false
	if invisibleRisk then
		local safe = Util.filter(d.outline, function(o)
			return Util.contrast(o, fill) >= 1.6
		end)
		if #safe > 0 then
			borderColor = Util.pick(safe)
		else
			borderColor = (Util.contrast("#000000", fill) > Util.contrast("#ffffff", fill))
				and "#000000" or "#ffffff"
		end
	else
		if Util.chance(0.28) then
			borderTransparent = true
		else
			borderColor = Util.pick(d.outline)
		end
	end
	local stroke = Ui.stroke(el, 3, Util.hex(borderColor or "#ffffff"))
	stroke.Transparency = borderTransparent and 1 or 0

	local label = Ui.new("TextLabel", {
		Name = "label",
		BackgroundTransparency = 1,
		Text = name,
		Font = Theme.MONO,
		TextSize = 19.4,
		TextColor3 = Util.hex(textHex),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 65,
		Parent = el,
	})
	bossType(label)

	local textW = Ui.textWidth(label.Text, 19.4, label.Font)
	local w = math.max(142, math.ceil(textW) + 60)
	local h = 66
	el.Size = UDim2.fromOffset(w, h)

	local b = {
		el = el,
		label = label,
		stroke = stroke,
		scale = Ui.scale(el, 0.88),
		name = name,
		x = 0,
		y = 0,
		w = w,
		h = h,
		a = 0,
		fill = fill,
		baseStrokeColor = stroke.Color,
		baseStrokeTransparency = stroke.Transparency,
	}

	el.MouseButton1Click:Connect(function()
		if not boss.active then
			return
		end
		Audio.click()
		onAnswer(b)
	end)

	return b
end

-- ============================================================
-- the round
-- ============================================================
local function startTimer(total)
	boss.tTotal = total
	boss.tStart = os.clock()
	timerBar.Visible = true
	Motion.keyframes(0.8, function(p)
		timerFill.BackgroundTransparency = Util.lerp(1, 0.4, p)
	end, Motion.ease.ease)

	if timerConn then
		timerConn:Disconnect()
	end
	timerConn = RunService.RenderStepped:Connect(function()
		if not boss.active then
			return
		end
		local rem = math.max(0, total - (os.clock() - boss.tStart))
		timerFill.Size = UDim2.fromScale(rem / total, 1)
		if rem <= 0 then
			timerConn:Disconnect()
			timerConn = nil
			Boss.answer(nil)
		end
	end)
end

local function eligibleLayouts()
	return Util.filter(Config.BOSS_LAYOUTS, function(l)
		return l ~= "alternate" or not boss.altUsed
	end)
end

local function makeContext(onAnswer)
	local ctx
	ctx = {
		arena = arena,
		width = function()
			return layer.AbsoluteSize.X
		end,
		height = function()
			return layer.AbsoluteSize.Y
		end,
		protectedBottom = protectedBottom,
		after = after,
		isActive = function()
			return boss.active
		end,
		setSim = function(fn)
			boss.sim = fn
			if not simConn then
				simConn = RunService.RenderStepped:Connect(function(dt)
					if boss.sim then
						local ok, err = pcall(boss.sim, math.min(0.05, dt))
						if not ok then
							warn("[Stroop] boss sim error: " .. tostring(err))
							boss.sim = nil
						end
					end
				end)
			end
			fn(0)
		end,
		onCleanup = function(fn)
			table.insert(boss.cleanup, fn)
		end,
		-- Mouse position in the layer's own coordinates. GetMouseLocation and
		-- AbsolutePosition are both measured from the same origin, so the
		-- difference needs no inset correction.
		pointer = function()
			local m = UserInputService:GetMouseLocation() - layer.AbsolutePosition
			return m.X, m.Y
		end,
		setGhost = function(b, on)
			-- `.bopt.ghost` - the button vanishes, leaving a grey outline
			b.el.BackgroundTransparency = on and 1 or 0
			b.label.TextTransparency = on and 1 or 0
			b.stroke.Transparency = on and 0 or b.baseStrokeTransparency
			b.stroke.Color = on and Util.hex("#6b6f7a") or b.baseStrokeColor
			local bold = b.label:FindFirstChildOfClass("UIStroke")
			if bold then
				bold.Transparency = on and 1 or 0
			end
		end,
		cloneButton = function(b)
			local g = b.el:Clone()
			g.Parent = arena
			local gScale = g:FindFirstChildOfClass("UIScale")
			if gScale then
				gScale.Scale = 1
			end
			g.MouseButton1Click:Connect(function()
				if boss.active then
					Audio.click()
					onAnswer(b)
				end
			end)
			return g
		end,
		syncGhost = function(g, b)
			g.Size = b.el.Size
			g.BackgroundTransparency = b.el.BackgroundTransparency
			g.Active = b.el.Active
			local gs = g:FindFirstChildOfClass("UIScale")
			if gs then
				gs.Scale = b.scale.Scale
			end
			local gl = g:FindFirstChild("label")
			if gl then
				gl.TextTransparency = b.label.TextTransparency
			end
			local gStroke = g:FindFirstChildOfClass("UIStroke")
			if gStroke then
				gStroke.Transparency = b.stroke.Transparency
				gStroke.Color = b.stroke.Color
			end
		end,
	}
	return ctx
end

function Boss.newRound()
	if boss.over or not gui.Enabled then
		return
	end
	clearArena()
	boss.round = boss.round + 1

	local layout = "grid"
	if boss.forceLayout then
		layout = boss.forceLayout
		boss.forceLayout = nil
	elseif boss.round > 1 then
		--[[
			Draw from a shuffled bag: every layout appears once before any
			repeats. At a reshuffle boundary that alone isn't enough - a layout
			used at the tail of the old bag could land right at the head of the
			new one - so pull the first bag entry that doesn't match either of
			the last two layouts actually played.
		]]
		boss.bag = Util.filter(boss.bag, function(l)
			return l ~= "alternate" or not boss.altUsed
		end)
		if #boss.bag == 0 then
			boss.bag = Util.shuffle(eligibleLayouts())
		end
		local idx = nil
		for i, l in ipairs(boss.bag) do
			if not Util.contains(boss.history, l) then
				idx = i
				break
			end
		end
		idx = idx or 1 -- only possible if fewer than 3 layouts are eligible
		layout = table.remove(boss.bag, idx) or Util.pick(eligibleLayouts())
	end

	boss.lastLayout = layout
	boss.history = { boss.history[2], layout }
	if boss.history[1] == nil then
		boss.history = { layout }
	end
	if layout == "alternate" then
		boss.altUsed = true
	end

	local alt = (layout == "alternate")
	local d = buildBossRound(alt, layout == "spotlight")
	d.full = alt -- alternate: 6s and full damage
	if layout == "decoy" then
		d.options = Util.shuffle(Util.concat(d.options, Config.DECOY_WORDS))
	end
	boss.data = d

	local circle = (layout == "dvd")
	local onAnswer = function(b)
		Boss.answer(b)
	end
	-- horizontal even for DVD; only the buttons go round
	local word = makeWord(d)
	local btns = Util.map(d.options, function(n)
		return makeButton(n, circle, d, onAnswer)
	end)
	for _, b in ipairs(btns) do
		if circle then
			local dia = math.max(b.w + 33, 99)
			b.el.Size = UDim2.fromOffset(dia, dia)
			b.w, b.h, b.r = dia, dia, dia / 2
			local corner = b.el:FindFirstChildOfClass("UICorner")
			if corner then
				corner.CornerRadius = UDim.new(0.5, 0)
			end
		end
	end
	boss.word = word
	boss.btns = btns

	local ctx = makeContext(onAnswer)
	Layouts[layout](ctx, word, btns)

	-- start positions land before anything fades in
	Motion.keyframes(0.6, function(p)
		word.inner.TextTransparency = 1 - p
	end, Motion.ease.ease)

	local staggered = (layout == "grid" or layout == "alternate" or layout == "decoy"
		or layout == "spotlight" or layout == "blink")
	for i, b in ipairs(btns) do
		local function fadeIn()
			Motion.keyframes(0.6, function(p)
				b.el.TextTransparency = 1
				b.label.TextTransparency = 1 - p
				b.el.BackgroundTransparency = 1 - p
				b.stroke.Transparency = Util.lerp(1, b.baseStrokeTransparency, p)
				b.scale.Scale = Util.lerp(0.88, 1, Motion.ease.soft(p))
			end, Motion.ease.ease)
		end
		b.el.BackgroundTransparency = 1
		b.label.TextTransparency = 1
		b.stroke.Transparency = 1
		if staggered then
			after((i - 1) * 0.035, fadeIn)
		else
			fadeIn()
		end
	end

	if layout == "spotlight" then
		stopFlash()
		hideTint() -- stays black
	else
		startFlash(d.bg) -- black -> colour happens with the challenge
	end

	boss.active = true
	if boss.stopVoice then
		boss.stopVoice()
	end
	boss.stopVoice = Voice.loop(d.ink.name, d.pal, Config.BOSS_VOICE_GAP, function()
		return boss.active
	end)

	-- drift and blink run 0.4s tighter than their normal allotment, floored at
	-- the same global minimum every other challenge respects
	local rushed = (layout == "drift" or layout == "blink")
	local roundTime
	if d.full then
		roundTime = 6
	elseif rushed then
		roundTime = math.max(Config.BOSS_MIN_TIME, boss.timer - 0.4)
	else
		roundTime = boss.timer
	end
	startTimer(roundTime)
end

local function fadeRound()
	-- challenge pieces vanish outright - no fade, no slide
	if boss.word then
		boss.word.el.Visible = false
	end
	for _, b in ipairs(boss.btns) do
		b.el.Visible = false
		for _, g in ipairs(b.ghosts or {}) do
			g.Visible = false
		end
	end
	stopFlash()
	hideTint() -- back to black for the rest beat
	if not boss.over then
		local from = timerFill.Size.X.Scale
		Motion.keyframes(1, function(p)
			timerFill.Size = UDim2.fromScale(Util.lerp(from, 1, p), 1)
		end, Motion.ease.standard)
	end
end

function Boss.answer(sel)
	if not boss.active then
		return
	end
	boss.active = false
	if boss.stopVoice then
		boss.stopVoice()
		boss.stopVoice = nil
	end
	if timerConn then
		timerConn:Disconnect()
		timerConn = nil
	end

	local d = boss.data
	local remaining = math.max(0, boss.tTotal - (os.clock() - boss.tStart))
	local correct = (sel ~= nil and sel.name == d.ink.name)

	-- Roblox renders only one UIStroke per object, so `.hit-ok` / `.hit-bad`
	-- recolour the border the button already has rather than adding another.
	for _, b in ipairs(boss.btns) do
		b.el.Active = false
		if b.name == d.ink.name then
			b.stroke.Color = Theme.OK
			b.stroke.Thickness = 5
			b.stroke.Transparency = 0
		elseif b ~= sel then
			b.el.BackgroundTransparency = 0.75
			b.label.TextTransparency = 0.75
			b.stroke.Transparency = math.max(b.stroke.Transparency, 0.75)
		end
	end
	if sel and not correct then
		sel.stroke.Color = Theme.BAD
		sel.stroke.Thickness = 5
		sel.stroke.Transparency = 0
		Audio.thud() -- a timeout stays silent
	end
	if boss.word then
		if correct then
			Motion.keyframes(0.35, function(p)
				boss.word.scale.Scale = p < 0.4 and (1 + 0.1 * (p / 0.4)) or (1.1 - 0.1 * ((p - 0.4) / 0.6))
			end, Motion.ease.ease)
		else
			Motion.keyframes(0.4, function(p)
				local x = 0
				if p < 0.2 then
					x = Util.lerp(0, -10, p / 0.2)
				elseif p < 0.4 then
					x = Util.lerp(-10, 10, (p - 0.2) / 0.2)
				elseif p < 0.6 then
					x = Util.lerp(10, -6, (p - 0.4) / 0.2)
				elseif p < 0.8 then
					x = Util.lerp(-6, 6, (p - 0.6) / 0.2)
				else
					x = Util.lerp(6, 0, (p - 0.8) / 0.2)
				end
				boss.word.inner.Position = UDim2.new(0, math.floor(x + 0.5), 0, 0)
			end, Motion.ease.ease)
		end
	end

	if correct then
		local dmg = d.full and Config.BOSS_ALT_HIT
			or ((remaining / boss.tTotal) * Config.BOSS_HIT_SCALED + Config.BOSS_HIT_BASE)
		boss.hp = math.max(0, boss.hp - dmg)
		local target = boss.hp / Config.BOSS_MAX_HP
		local from = hpFill.Size.X.Scale
		Motion.keyframes(0.8, function(p)
			hpFill.Size = UDim2.new(Util.lerp(from, target, p), 0, 1, 0)
		end, Motion.ease.fight)
		Chaos.flinch(logo, Util.hex(d.ink.hex))
		boss.timer = math.max(Config.BOSS_MIN_TIME, boss.timer - Config.BOSS_STEP)
		if Boss.onSoloCorrect then
			Boss.onSoloCorrect()
		end
		-- x = what the final stage-3 correct answer paid; 6hp of damage = x points
		local x = 100 + math.floor(Config.SOLO_STAGE4_AT / 2) * 10
		Boss.setScore(Boss.getScore() + math.floor(dmg * (x / 6) + 0.5))
	else
		boss.lives = boss.lives - 1
		Boss.renderLives()
		reactLabel.Text = Config.REACTIONS[boss.reactIdx % #Config.REACTIONS + 1]
		boss.reactIdx = boss.reactIdx + 1
		-- lands well off-centre; direction of the jump is randomised each time
		local ang = Util.rand(0, math.pi * 2)
		local rx = Util.chance(0.5) and -1 or 1
		local ry = Util.rand(-0.4, 0.4)
		local baseX = 0.5 + math.cos(ang) * Util.rand(0.14, 0.24)
		local baseY = 0.5 + math.sin(ang) * Util.rand(0.10, 0.18)
		Motion.keyframes(1.1, function(p)
			-- @keyframes reactPop
			local alpha, sc, dx, dy, rot
			if p < 0.16 then
				local k = p / 0.16
				alpha = 1 - k
				sc = Util.lerp(0.45, 1.15, k)
				dx = Util.lerp(0, rx * 34, k)
				dy = Util.lerp(0, ry * 34 - 46, k)
				rot = Util.lerp(rx * -14, rx * 8, k)
			else
				local k = (p - 0.16) / 0.84
				alpha = k
				sc = Util.lerp(1.15, 0.9, k)
				dx = Util.lerp(rx * 34, rx * 96, k)
				dy = Util.lerp(ry * 34 - 46, ry * 96 - 150, k)
				rot = Util.lerp(rx * 8, 0, k)
			end
			reactLabel.TextTransparency = alpha
			Boss.reactScale.Scale = sc
			reactLabel.Position = UDim2.new(baseX, math.floor(dx + 0.5), baseY, math.floor(dy + 0.5))
			reactLabel.Rotation = rot
		end, Motion.ease.pop)
		boss.timer = math.min(Config.BOSS_START_TIME, boss.timer + Config.BOSS_STEP)
	end

	-- both go through `after` so that leaving cancels them with the arena
	after(Config.BOSS_FADE_AT, fadeRound)
	if boss.hp <= 0 then
		task.spawn(Boss.death)
		return
	end
	if boss.lives <= 0 then
		task.spawn(Boss.defeat)
		return
	end
	after(Config.BOSS_REST, Boss.newRound)
end

-- ============================================================
-- intro
-- ============================================================
function Boss.runIntro()
	task.spawn(function()
		bwait(0.8)
		bossWrite("test subject shows promise.", 0.42)
		bwait(0.45)

		-- the logo floats down from above
		boss.logoEntered = true
		logo.holder.Visible = true
		local size = layer.AbsoluteSize
		local topY = size.Y / 7
		local fromY = topY - size.Y * 0.36
		logo:setTransparency(1)
		Motion.keyframes(2.24, function(p)
			logo.holder.Position = UDim2.fromOffset(size.X / 2, Util.lerp(fromY, topY, p))
		end, Motion.ease.swoop)
		Motion.keyframes(1.6, function(p)
			logo:setTransparency(1 - p)
		end, Motion.ease.ease)
		bwait(1.6)

		-- the bar extends out from centre
		Motion.keyframes(1.28, function(p)
			hpFill.Size = UDim2.new(p, 0, 1, 0)
		end, Motion.ease.bar)
		Boss.renderLives()
		livesRow.Visible = true
		leaveBtn.Visible = true
		bwait(1.36)
		bwait(0.72)

		-- BEGIN
		Motion.keyframes(0.8, function(p)
			local a
			if p < 0.16 then
				a = 1 - p / 0.16
			elseif p < 0.7 then
				a = 0
			else
				a = (p - 0.7) / 0.3
			end
			beginLabel:setTransparency(a)
		end, Motion.ease.ease)
		bwait(0.8)
		beginLabel:setTransparency(1)
		logo:startBob()
		bwait(0.2)
		boss.busy = false
		Boss.newRound()
	end)
end

-- ============================================================
-- outcomes
-- ============================================================
function Boss.death()
	boss.over = true
	clearArena()
	stopFlash()
	hideTint()
	Motion.keyframes(0.9, function(p)
		hpFill.BackgroundTransparency = p
	end, Motion.ease.ease)
	timerBar.Visible = false
	livesRow.Visible = false
	logo:settleBob()
	logo:setColor(Color3.new(1, 1, 1)) -- plain white, whatever the backdrop did

	-- drops to centre immediately
	boss.logoCentred = true
	local size = layer.AbsoluteSize
	local fromY = logo.holder.Position.Y.Offset
	Motion.keyframes(2.6, function(p)
		logo.holder.Position = UDim2.fromOffset(size.X / 2, Util.lerp(fromY, size.Y * 0.5, p))
	end, Motion.ease.hard)

	-- PHASE 1 - the churning and the shaking. A click here jumps to the pause.
	phaseStart()
	boss.stopChaos = Chaos.startChaos(logo)
	phaseWait(2.6)
	if not boss.skipPhase then
		boss.stopConvulse = Chaos.startConvulse(logo) -- shaking beyond control
	end
	phaseWait(1.5)
	if boss.stopChaos then
		boss.stopChaos()
		boss.stopChaos = nil
	end
	if boss.stopConvulse then
		boss.stopConvulse()
		boss.stopConvulse = nil
	end
	-- the churning drops away and it settles back into its own serif form
	logo:setFont(Theme.SERIF)
	logo.scale.Scale = 1
	logo.inner.Position = UDim2.fromScale(0.5, 0.5)
	logo.inner.Rotation = 0

	-- PHASE 2 - the still pause and the letters falling. A click here jumps
	-- straight to the W screen.
	phaseStart()
	phaseWait(2) -- two full seconds, dead still
	if not boss.skipPhase then
		Chaos.dropLetters(logo, layer)
		phaseWait(4.2) -- the last letter clears the screen
	end
	for _, child in ipairs(layer:GetChildren()) do
		if child.Name:sub(1, 4) == "fall" then
			child:Destroy()
		end
	end
	logo:setVisible(false)

	-- the original off-white
	local fromColor = layer.BackgroundColor3
	Motion.keyframes(2.2, function(p)
		layer.BackgroundColor3 = fromColor:Lerp(Util.hex("#dcdad3"), p)
	end, Motion.ease.ease)
	bwait(2.2)

	--[[
		x = points the last stage-3 correct answer would have earned; that sets
		the going rate for stage 4 (6 damage = x points), and the win bonus below
		spends a 200hp-equivalent purse, split by how many questions the fight
		actually took.
	]]
	local x = 100 + math.floor(Config.SOLO_STAGE4_AT / 2) * 10
	local bonus = math.floor((200 * (x / 6)) / math.max(1, boss.round) + 0.5)
	Boss.setScore(Boss.getScore() + bonus)

	local size2 = layer.AbsoluteSize
	local insigniaSize = math.floor(math.min(size2.Y * 0.666, size2.X * 0.576) + 0.5)
	local w = writeLine("W", {
		size = insigniaSize,
		tight = true,
		color = Util.hex("#16181d"),
		font = Theme.SERIF,
		sw = math.max(1.6, insigniaSize * 0.0045),
		dw = 0.5,
		id = 0.32,
		iw = 0.32,
	})
	Boss.insignia = w

	if Boss.getScore() > Boss.getBest() then
		Boss.setBest(Boss.getScore())
	end
	bwait(1.1)

	scoreLabel.Text = tostring(math.floor(Boss.getScore()))
	scoreLabel.TextColor3 = Util.hex("#16181d")
	Motion.keyframes(1.1, function(p)
		scoreLabel.TextTransparency = 1 - p
		scoreLabel.Position = UDim2.new(
			0.5, 0,
			0.5, math.floor(math.min(size2.Y * 0.33, size2.X * 0.29) + 26 + 10 * (1 - p))
		)
	end, Motion.ease.bar)
	bwait(0.9)

	boss.canReturn = true
	Motion.keyframes(1.4, function(p)
		hintLabel:setTransparency(1 - p)
	end, Motion.ease.ease)
end

function Boss.defeat()
	boss.over = true
	bwait(1.2)
	timerBar.Visible = false
	bwait(0.4)
	stopFlash()
	hideTint()
	Motion.keyframes(0.9, function(p)
		hpFill.BackgroundTransparency = p
	end, Motion.ease.ease)
	livesRow.Visible = false
	bwait(1.4)
	clearArena()
	logo:settleBob()
	Motion.keyframes(2, function(p)
		logo:setTransparency(p)
	end, Motion.ease.ease)
	bwait(2.5)
	logo:setVisible(false)

	bossWrite("test subject did not meet expectations", 1.3)
	bwait(0.7)

	local size = layer.AbsoluteSize
	local insigniaSize = math.floor(math.min(size.Y * 0.74, size.X * 0.64) + 0.5)
	local l = writeLine("L", {
		size = insigniaSize,
		tight = true,
		font = Theme.SERIF,
		sw = math.max(1.5, insigniaSize * 0.004),
		dw = 1.2,
		id = 0.75,
		iw = 0.5,
	})
	Boss.insignia = l

	if Boss.getScore() > Boss.getBest() then
		Boss.setBest(Boss.getScore())
	end
	bwait(1.3)

	scoreLabel.Text = tostring(math.floor(Boss.getScore()))
	scoreLabel.TextColor3 = Color3.new(1, 1, 1) -- the loss screen keeps its black backdrop
	Motion.keyframes(1.1, function(p)
		scoreLabel.TextTransparency = 1 - p
	end, Motion.ease.ease)
	bwait(0.5)

	boss.canReturn = true
	Motion.keyframes(1.4, function(p)
		hintLabel:setTransparency(1 - p)
	end, Motion.ease.ease)
end

-- ============================================================
-- entry and exit
-- ============================================================
local function hideLayer()
	Motion.keyframes(1.3, function(p)
		layer.BackgroundTransparency = p
		tint.BackgroundTransparency = math.max(tint.BackgroundTransparency, p)
		logo:setTransparency(math.max(0, p))
		scoreLabel.TextTransparency = math.max(scoreLabel.TextTransparency, p)
		hintLabel:setTransparency(math.max(0, p))
		for _, line in ipairs(activeLines) do
			for _, letter in ipairs(line.letters) do
				if letter.label.Parent then
					letter.label.TextTransparency = math.max(letter.label.TextTransparency, p)
					letter.stroke.Transparency = p
				end
			end
		end
	end, Motion.ease.ease)
end

-- Bail out of the fight entirely and go back to the menu.
function Boss.quitToMenu()
	boss.over = true
	boss.active = false
	boss.busy = false
	boss.gen = boss.gen + 1   -- stop any cinematic beat still waiting
	boss.canReturn = false
	stopFlash()
	clearArena()
	if timerConn then
		timerConn:Disconnect()
		timerConn = nil
	end
	if boss.stopChaos then
		boss.stopChaos()
		boss.stopChaos = nil
	end
	if boss.stopConvulse then
		boss.stopConvulse()
		boss.stopConvulse = nil
	end
	if boss.stopVoice then
		boss.stopVoice()
		boss.stopVoice = nil
	end
	Voice.cancel()
	if Boss.getScore() > Boss.getBest() then
		Boss.setBest(Boss.getScore())
	end
	if Boss.onExit then
		Boss.onExit()
	end
	hideLayer()
	task.delay(1.5, reset)
end

function Boss.returnHome()
	if not boss.canReturn then
		return
	end
	boss.canReturn = false
	boss.busy = false
	if Boss.onExit then
		Boss.onExit()
	end
	hideLayer() -- off-white crossfades into the menu
	task.delay(1.7, reset)
end

-- The dissolve the stage 3 surface performs on its way into the black.
function Boss.enterFromStage3(fadeOutSurface)
	if boss.busy then
		return
	end
	boss.busy = true
	task.spawn(function()
		if fadeOutSurface then
			fadeOutSurface()
		end
		bwait(1.2)
		fadeToBlack()
		Boss.runIntro()
	end)
end

-- Shared menu -> black handoff for the developer previews.
local function enterFromMenu(fadeMenu)
	if fadeMenu then
		fadeMenu()
	end
	bwait(0.96) -- menu fully gone first
	fadeToBlack()
end

function Boss.startTest(fadeMenu)
	if boss.busy then
		return
	end
	boss.busy = true
	task.spawn(function()
		enterFromMenu(fadeMenu)
		Boss.runIntro()
	end)
end

-- Jumps straight into one named layout, skipping the intro.
function Boss.startLayoutTest(layout, fadeMenu)
	if boss.busy then
		return
	end
	boss.busy = true
	task.spawn(function()
		enterFromMenu(fadeMenu)
		boss.logoEntered = true
		logo.holder.Visible = true
		local size = layer.AbsoluteSize
		logo.holder.Position = UDim2.fromOffset(size.X / 2, size.Y / 7)
		logo:setTransparency(0)
		hpFill.Size = UDim2.new(1, 0, 1, 0)
		Boss.renderLives()
		livesRow.Visible = true
		leaveBtn.Visible = true
		logo:startBob()
		boss.busy = false
		boss.forceLayout = layout
		Boss.newRound()
	end)
end

-- Sets the arena as it looks mid-fight, then plays an ending.
function Boss.startEndingTest(win, fadeMenu)
	if boss.busy then
		return
	end
	boss.busy = true
	task.spawn(function()
		enterFromMenu(fadeMenu)
		boss.logoEntered = true
		logo.holder.Visible = true
		local size = layer.AbsoluteSize
		logo.holder.Position = UDim2.fromOffset(size.X / 2, size.Y / 7)
		logo:setTransparency(0)
		bwait(1.8)
		hpFill.Size = UDim2.new(win and 0.18 or 0.6, 0, 1, 0)
		Boss.renderLives()
		livesRow.Visible = true
		bwait(1.4)
		logo:startBob()
		bwait(0.7)
		boss.busy = false
		boss.round = 8
		if win then
			boss.hp = 0
			hpFill.Size = UDim2.new(0, 0, 1, 0)
			Boss.death()
		else
			boss.lives = 0
			Boss.renderLives()
			Boss.defeat()
		end
	end)
end

function Boss.isRunning()
	return gui and gui.Enabled
end

return Boss
