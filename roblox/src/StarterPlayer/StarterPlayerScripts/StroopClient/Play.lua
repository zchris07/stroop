--!nonstrict
-- The stage 1-3 play surface: the word, the option buttons, the timer bar, the
-- backdrop, the countdown and the transitions in and out of play. Both the solo
-- run and the lobby match drive this same surface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Stroop.Config)
local Util = require(ReplicatedStorage.Stroop.Util)
local Rounds = require(ReplicatedStorage.Stroop.Rounds)

local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local Motion = require(script.Parent.Motion)
local Root = require(script.Parent.Root)
local Cards = require(script.Parent.Cards)
local Audio = require(script.Parent.Audio)
local Voice = require(script.Parent.Voice)

local Play = {}

Play.score = 0
Play.lives = Config.LIVES_START
Play.best = 0

local timerCancel = nil
local flashThread = nil
local flashToken = 0
local countdownTokens = 0
local bgTintCancel = nil
local optionButtons = {}

-- ============================================================
-- HUD
-- ============================================================
function Play.setScore(value)
	Play.score = value
	Root.scoreMetric.value.Text = tostring(math.floor(value))
end

function Play.setBest(value)
	Play.best = value
	Root.bestMetric.value.Text = tostring(math.floor(value))
end

function Play.setStage(stage)
	Root.stageMetric.value.Text = tostring(stage)
	Root.stageLabel:setText("STAGE " .. stage)
end

function Play.setGoal(target)
	Root.goalMetric.value.Text = tostring(target)
	Root.lbGoal.Text = tostring(target)
end

function Play.renderLives()
	for i, dot in ipairs(Root.lifeDots) do
		dot.TextColor3 = (i <= Play.lives) and Theme.BAD or Theme.current.panelLine
	end
end

-- .score-pop - a `+N` that rises out of the score metric and fades.
-- It hangs off the HUD rather than the metric itself: the metric auto-sizes to
-- its contents, so a child there would widen the whole cluster.
function Play.showScorePop(delta)
	if delta <= 0 then
		return
	end
	local metric = Root.scoreMetric.frame
	local rel = metric.AbsolutePosition - Root.hud.AbsolutePosition
	local originX = rel.X + metric.AbsoluteSize.X + 10
	local originY = rel.Y - 6

	local pop = Ui.new("TextLabel", {
		Name = "scorePop",
		BackgroundTransparency = 1,
		Text = "+" .. math.floor(delta),
		Font = Theme.MONO,
		TextSize = 11,
		TextColor3 = Theme.OK,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(originX, originY),
		Size = UDim2.fromOffset(40, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 33,
		Parent = Root.hud,
	})
	Motion.keyframes(0.9, function(p)
		-- 0% hidden / 25% in place / 100% gone, drifting up 14px
		local alpha, dy
		if p < 0.25 then
			local k = p / 0.25
			alpha = 1 - k
			dy = 4 * (1 - k)
		else
			local k = (p - 0.25) / 0.75
			alpha = k
			dy = -14 * k
		end
		pop.TextTransparency = alpha
		pop.Position = UDim2.fromOffset(originX, originY + dy)
	end, Motion.ease.ease)
	task.delay(0.95, function()
		pop:Destroy()
	end)
end

-- ============================================================
-- backdrop
-- ============================================================
local function backdropPool(inkName)
	local banned = Config.TINT_CLASHES[inkName] or { inkName }
	local pool = Util.filter(Config.COLORS, function(c)
		return not Util.contains(banned, c.name)
	end)
	if #pool == 0 then
		pool = Util.filter(Config.COLORS, function(c)
			return c.name ~= inkName
		end)
	end
	return pool
end
Play.backdropPool = backdropPool

local function tintTo(color, duration)
	if bgTintCancel then
		bgTintCancel()
	end
	local fromColor = Root.bgTint.BackgroundColor3
	local fromAlpha = Root.bgTint.BackgroundTransparency
	bgTintCancel = Motion.keyframes(duration, function(p)
		Root.bgTint.BackgroundColor3 = fromColor:Lerp(color, p)
		Root.bgTint.BackgroundTransparency = Util.lerp(fromAlpha, 0, p)
	end, Motion.ease.ease)
end

function Play.stopFlash()
	flashToken = flashToken + 1
	flashThread = nil
end

function Play.applyBackdrop(stage, inkName, tintName)
	Play.stopFlash()
	if stage == 1 then
		if bgTintCancel then
			bgTintCancel()
		end
		local fromAlpha = Root.bgTint.BackgroundTransparency
		bgTintCancel = Motion.keyframes(0.45, function(p)
			Root.bgTint.BackgroundTransparency = Util.lerp(fromAlpha, 1, p)
		end, Motion.ease.ease)
		return
	end

	if stage == 2 then
		local c = tintName and Config.BY_NAME[tintName] or Util.pick(backdropPool(inkName))
		tintTo(Util.hex((c or Config.COLORS[1]).tint), 0.45)
		return
	end

	-- stage 3 - gentle flashing through pale tints, never the ink color
	local pool = backdropPool(inkName)
	tintTo(Util.hex(Util.pick(pool).tint), 0.45)
	flashToken = flashToken + 1
	local mine = flashToken
	flashThread = task.spawn(function()
		while true do
			task.wait(2)
			if mine ~= flashToken then
				return
			end
			tintTo(Util.hex(Util.pick(pool).tint), 0.45)
		end
	end)
end

-- ============================================================
-- option buttons
-- ============================================================
local function clearOptions()
	for _, b in ipairs(optionButtons) do
		b.frame:Destroy()
	end
	optionButtons = {}
	Root.options:ClearAllChildren()
end

local function styleOption(entry, state)
	local panel = Theme.current.panel
	if state == "correct" then
		entry.stroke.Color = Theme.OK
		entry.frame.BackgroundColor3 = Util.mix(Theme.OK, panel, 0.16)
	elseif state == "wrong" then
		entry.stroke.Color = Theme.BAD
		entry.frame.BackgroundColor3 = Util.mix(Theme.BAD, panel, 0.16)
	else
		entry.stroke.Color = entry.baseStroke or Theme.current.panelLine
		entry.frame.BackgroundColor3 = entry.baseFill or panel
	end
end

-- `renderChallenge` in the page: the word, its ink, and one button per option.
function Play.renderChallenge(stage, wordName, inkHex, optionNames, optionInk, onSelect)
	Root.word.Text = wordName
	Root.word.TextColor3 = Util.hex(inkHex)
	Root.wordScale.Scale = 1
	Root.word.Rotation = 0

	clearOptions()

	local m = Root.m
	local isGrid = (stage == 3)
	local font = isGrid and m.gridFont or m.optFont
	local padX = isGrid and m.gridPadX or m.optPadX
	local padY = isGrid and m.gridPadY or m.optPadY
	local btnH = isGrid and m.gridH or m.optH
	local spacing = font * 0.05

	-- measure
	local widths = {}
	local maxW = 0
	for i, name in ipairs(optionNames) do
		local textW = 0
		for _, code in utf8.codes(name) do
			textW = textW + Ui.textWidth(utf8.char(code), font, Theme.MONO)
		end
		textW = textW + math.max(0, utf8.len(name) - 1) * spacing
		local w = math.max(m.optMinWidth, math.ceil(textW) + padX * 2 + m.optBorder * 2)
		widths[i] = w
		maxW = math.max(maxW, w)
	end

	-- place
	local positions = {}
	local totalH
	if isGrid then
		local cols = 3
		local rows = math.ceil(#optionNames / cols)
		local cellW
		if m.narrow then
			local avail = m.vw - m.gridPadSide * 2 - m.gridGapX * (cols - 1)
			cellW = math.floor(avail / cols)
		else
			cellW = maxW
		end
		local gridW = cellW * cols + m.gridGapX * (cols - 1)
		local x0 = (m.vw - gridW) / 2
		for i = 1, #optionNames do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			positions[i] = {
				x = x0 + col * (cellW + m.gridGapX),
				y = m.gridPadTop + row * (btnH + m.gridGapY),
				w = cellW,
			}
		end
		totalH = m.gridPadTop + rows * btnH + (rows - 1) * m.gridGapY + m.gridPadBottom
	else
		-- flex row, wrapping when it runs out of width
		local avail = m.vw - m.optPadSide * 2
		local lines, line, lineW = {}, {}, 0
		for i = 1, #optionNames do
			local w = widths[i]
			local extra = (#line > 0) and (m.optGapX + w) or w
			if #line > 0 and lineW + extra > avail then
				table.insert(lines, { items = line, width = lineW })
				line, lineW = {}, 0
				extra = w
			end
			table.insert(line, i)
			lineW = lineW + extra
		end
		if #line > 0 then
			table.insert(lines, { items = line, width = lineW })
		end
		for li, ln in ipairs(lines) do
			local x = (m.vw - ln.width) / 2
			for _, i in ipairs(ln.items) do
				positions[i] = {
					x = x,
					y = m.optPadTop + (li - 1) * (btnH + m.optGapY),
					w = widths[i],
				}
				x = x + widths[i] + m.optGapX
			end
		end
		totalH = m.optPadTop + #lines * btnH + math.max(0, #lines - 1) * m.optGapY + m.optPadBottom
	end

	Root.setOptionsHeight(totalH)

	for i, name in ipairs(optionNames) do
		local pos = positions[i]
		local frame = Ui.new("TextButton", {
			Name = "opt" .. i,
			Text = "",
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.current.panel,
			Position = UDim2.fromOffset(math.floor(pos.x + 0.5), math.floor(pos.y + 0.5)),
			Size = UDim2.fromOffset(pos.w, btnH),
			ZIndex = 30,
			Parent = Root.options,
		})
		Ui.corner(frame, m.optRadius)
		local stroke = Ui.stroke(frame, m.optBorder, Theme.current.panelLine)

		local label = Ui.tracked({
			Name = "label",
			Text = name,
			Font = Theme.MONO,
			TextSize = font,
			Spacing = spacing,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 31,
			Parent = frame,
		})
		label:setColor(Theme.current.ink)

		local entry = {
			frame = frame,
			stroke = stroke,
			label = label,
			name = name,
			baseFill = Theme.current.panel,
			baseStroke = Theme.current.panelLine,
			disabled = false,
		}

		-- stage 3's buttons carry their own ink, which is its own interference
		if isGrid and optionInk and optionInk[i] then
			local c = Config.BY_NAME[optionInk[i]]
			if c then
				-- pale pink is too faint here, so it is swapped for magenta
				local hex = (c.name == "PINK") and "#FF00FF" or c.hex
				label:setColor(Util.hex(hex))
				stroke.Color = Util.hex(hex)
				entry.baseStroke = Util.hex(hex)
				-- a white label on a white button is invisible - give it a dark plate
				if c.name == "WHITE" then
					frame.BackgroundColor3 = Util.hex("#14161c")
					entry.baseFill = Util.hex("#14161c")
				end
			end
		end

		local baseY = pos.y
		frame.MouseEnter:Connect(function()
			if not entry.disabled then
				frame.Position = UDim2.fromOffset(math.floor(pos.x + 0.5), math.floor(baseY + 0.5) - 2)
			end
		end)
		frame.MouseLeave:Connect(function()
			frame.Position = UDim2.fromOffset(math.floor(pos.x + 0.5), math.floor(baseY + 0.5))
		end)
		frame.MouseButton1Click:Connect(function()
			if entry.disabled then
				return
			end
			Audio.click()
			onSelect(name, entry)
		end)

		optionButtons[i] = entry
	end

	Play.optionButtons = optionButtons
end

function Play.lockOptions(correctName, selectedEntry, isCorrect)
	for _, entry in ipairs(optionButtons) do
		entry.disabled = true
		entry.frame.Active = false
		if entry.name == correctName then
			styleOption(entry, "correct")
		end
		if not isCorrect and selectedEntry and entry == selectedEntry then
			styleOption(entry, "wrong")
		end
	end
end

-- ============================================================
-- word feedback
-- ============================================================
function Play.pulseOk()
	local base = Root.wordScale.Scale
	Motion.keyframes(0.35, function(p)
		-- 0% 1 / 40% 1.1 / 100% 1
		local s
		if p < 0.4 then
			s = 1 + 0.1 * (p / 0.4)
		else
			s = 1.1 - 0.1 * ((p - 0.4) / 0.6)
		end
		Root.wordScale.Scale = base * s
	end, Motion.ease.ease)
end

function Play.pulseBad()
	Motion.keyframes(0.4, function(p)
		-- badshake: -10px / +10px / -6px / +6px, with a slight tilt at the ends
		local x, rot = 0, 0
		if p < 0.2 then
			x, rot = Util.lerp(0, -10, p / 0.2), Util.lerp(0, -1, p / 0.2)
		elseif p < 0.4 then
			x, rot = Util.lerp(-10, 10, (p - 0.2) / 0.2), Util.lerp(-1, 1, (p - 0.2) / 0.2)
		elseif p < 0.6 then
			x, rot = Util.lerp(10, -6, (p - 0.4) / 0.2), Util.lerp(1, 0, (p - 0.4) / 0.2)
		elseif p < 0.8 then
			x = Util.lerp(-6, 6, (p - 0.6) / 0.2)
		else
			x = Util.lerp(6, 0, (p - 0.8) / 0.2)
		end
		Root.word.Position = UDim2.new(0.5, math.floor(x + 0.5), 0.5, 0)
		Root.word.Rotation = rot
	end, Motion.ease.ease)
end

-- ============================================================
-- timer bar
-- ============================================================
function Play.stopTimer()
	if timerCancel then
		timerCancel()
		timerCancel = nil
	end
end

function Play.startTimerBar(remaining, total, onTimeout)
	Play.stopTimer()
	local frac = math.clamp(remaining / math.max(0.001, total), 0, 1)
	Root.timerFill.Size = UDim2.new(frac, 0, 1, 0)
	if remaining <= 0 then
		task.spawn(onTimeout)
		return
	end
	local fired = false
	timerCancel = Motion.keyframes(remaining, function(p)
		Root.timerFill.Size = UDim2.new(frac * (1 - p), 0, 1, 0)
		if p >= 1 and not fired then
			fired = true
			timerCancel = nil
			task.spawn(onTimeout)
		end
	end, Motion.ease.linear)
end

function Play.resetTimerBar()
	Play.stopTimer()
	Root.timerFill.Size = UDim2.new(1, 0, 1, 0)
end

-- ============================================================
-- countdown
-- ============================================================
function Play.clearCountdown()
	countdownTokens = countdownTokens + 1
end

local function showCountdownWord(text)
	Root.word.Text = text
	Root.word.TextColor3 = Theme.current.ink
	Root.word.Rotation = 0
	Root.word.Position = UDim2.fromScale(0.5, 0.5)
	-- countPulse: 0% hidden at .75 scale, 45% at 1.06, settling to 1
	Motion.keyframes(0.55, function(p)
		local s, a
		if p < 0.45 then
			local k = p / 0.45
			s = Util.lerp(0.75, 1.06, k)
			a = 1 - k
		else
			local k = (p - 0.45) / 0.55
			s = Util.lerp(1.06, 1, k)
			a = 0
		end
		Root.wordScale.Scale = s
		Root.word.TextTransparency = a
	end, Motion.ease.ease)
end
Play.showCountdownWord = showCountdownWord

-- Plays READY / SET / GO so that GO lands right before reveal.
function Play.runIntroCountdown(untilReveal)
	Play.clearCountdown()
	countdownTokens = countdownTokens + 1
	local mine = countdownTokens

	if untilReveal < 2.2 then
		showCountdownWord("GET READY")
		return
	end

	local schedule = {
		{ at = math.max(0, untilReveal - 2.35), text = "READY" },
		{ at = math.max(0, untilReveal - 1.55), text = "SET" },
		{ at = math.max(0, untilReveal - 0.75), text = "GO" },
	}
	for _, step in ipairs(schedule) do
		task.delay(step.at, function()
			if mine == countdownTokens then
				showCountdownWord(step.text)
			end
		end)
	end
end

-- ============================================================
-- transitions
-- ============================================================
local function enterFrom(group, dy)
	local base = group.Position
	group.Visible = true
	Motion.keyframes(0.6, function(p)
		group.Position = base + UDim2.fromOffset(0, math.floor(dy * (1 - p) + 0.5))
		group.GroupTransparency = 1 - p
	end, Motion.ease.softer)
end

function Play.transitionIntoPlay()
	-- 1. Fade out the menu/end-screen content in place - opacity only.
	local activeCard = nil
	for _, card in pairs(Cards.list) do
		if card.Visible then
			activeCard = card
			break
		end
	end
	if activeCard then
		local group = activeCard
		Motion.keyframes(0.38, function(p)
			Play.fadeCardContents(group, p)
		end, Motion.ease.ease)
	end
	task.wait(0.38)

	-- 2. Crossfade the full-screen backdrop from dark to off-white - a flat
	--    colour fade, nothing moves.
	Theme.setLight(true, 0.8)
	local fromColor = Root.overlay.BackgroundColor3
	local fromAlpha = Root.overlay.BackgroundTransparency
	local target = Util.hex(Config.THEME.light.pageBg)
	Motion.keyframes(0.8, function(p)
		Root.overlay.BackgroundColor3 = fromColor:Lerp(target, p)
		Root.overlay.BackgroundTransparency = Util.lerp(fromAlpha, 0, p)
	end, Motion.ease.ease)
	task.wait(0.8)

	-- 3. The overlay's backdrop now matches the app's own light background, so
	--    hiding it is a seamless handoff rather than a cut.
	Cards.hideAll()
	Root.overlay.Visible = false
	Root.overlay.BackgroundColor3 = Util.hex(Config.THEME.overlayBg)
	Root.overlay.BackgroundTransparency = 0.07
	if activeCard then
		Play.restoreCard(activeCard)
	end

	-- 4. Animate the HUD/timer/stage/options into view.
	Root.setInGame(true)
	Root.setGroupTransparency(1)
	enterFrom(Root.hud, -26)
	enterFrom(Root.timerTrack, -26)
	enterFrom(Root.stage, 26)
	enterFrom(Root.wordGroup, 26)
	enterFrom(Root.placementGroup, 26)
	enterFrom(Root.options, 26)
	task.wait(0.42)
end

-- `.card.card-fade-out` - opacity only, across everything the card draws.
function Play.fadeCardContents(card, alpha)
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			d.TextTransparency = alpha
			if d.BackgroundTransparency < 1 then
				d.BackgroundTransparency = math.max(d.BackgroundTransparency, alpha)
			end
		elseif d:IsA("UIStroke") then
			d.Transparency = alpha
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			d.BackgroundTransparency = alpha
		end
	end
end

-- Card backgrounds are re-derived rather than remembered: only the solid
-- go-buttons, the field boxes and the hairlines have one.
function Play.restoreCard(card)
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			d.TextTransparency = 0
		elseif d:IsA("UIStroke") then
			d.Transparency = 0
		end
	end
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("TextButton") and d.Name == "goBtn" then
			local ghost = d:FindFirstChildOfClass("UIStroke") ~= nil
			d.BackgroundTransparency = ghost and 1 or 0
		elseif d:IsA("TextBox") then
			d.BackgroundTransparency = 0
		elseif d:IsA("Frame") and (d.Name == "line" or d.Name == "underline") then
			d.BackgroundTransparency = 0
		end
	end
end

function Play.transitionOutOfPlay()
	Root.setInGame(false)
	Play.stopFlash()
	Play.clearCountdown()
	Play.hidePlacement()
	Play.stopTimer()
	Voice.cancel()
	Root.bgTint.BackgroundTransparency = 1
	Theme.setLight(false, 0.8)
	clearOptions()
	Root.word.Text = ""
	Root.word.Rotation = 0
	Root.word.Position = UDim2.fromScale(0.5, 0.5)
	Root.word.TextTransparency = 0
	Root.wordScale.Scale = 1
	Root.timerFill.Size = UDim2.new(1, 0, 1, 0)
end

-- ============================================================
-- placement feedback
-- ============================================================
local placementHide = nil
Play.placementRound = -1

function Play.renderPlacement(text)
	Root.placement.Text = text
	Root.placement.Visible = true
	Motion.keyframes(0.42, function(p)
		-- placementIn: rises 10px while scaling .9 -> 1.05 -> 1
		local dy, s, a
		if p < 0.55 then
			local k = p / 0.55
			dy = Util.lerp(10, 0, k)
			s = Util.lerp(0.9, 1.05, k)
			a = 1 - k
		else
			local k = (p - 0.55) / 0.45
			dy = 0
			s = Util.lerp(1.05, 1, k)
			a = 0
		end
		Root.placementScale.Scale = s
		Root.placement.TextTransparency = a
		Root.placement.Position = UDim2.new(0.5, 0, 0, math.floor(Root.m.placementTop + dy))
	end, Motion.ease.placement)

	if placementHide then
		pcall(task.cancel, placementHide)
		placementHide = nil
	end
	placementHide = task.delay(4, function()
		Root.placement.Visible = false
		placementHide = nil
	end)
end

function Play.hidePlacement()
	if placementHide then
		pcall(task.cancel, placementHide)
		placementHide = nil
	end
	Root.placement.Visible = false
	Play.placementRound = -1
end

function Play.placementLabel(rank, total)
	if total > 1 and rank == total then
		return "last!"
	end
	return Util.ordinal(rank) .. "!"
end

-- ============================================================
-- live leaderboard
-- ============================================================
local INK_LB = nil

function Play.renderLiveboard(players, myUserId)
	Root.lbRows:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = Root.lbRows

	local m = Root.m
	for i = 1, math.min(6, #players) do
		local p = players[i]
		local isMe = (p.userId == myUserId)
		local isLeader = (i == 1 and p.score > 0)

		local row = Ui.new("Frame", {
			Name = "row" .. i,
			BackgroundTransparency = isMe and 0 or 1,
			BackgroundColor3 = Util.mix(Theme.OK, Theme.current.panel, 0.15),
			Size = UDim2.new(1, 0, 0, math.ceil(m.lbFont * 1.25) + 8),
			LayoutOrder = i,
			ZIndex = 41,
			Parent = Root.lbRows,
		})
		if isMe then
			Ui.corner(row, 6)
		end

		Ui.new("TextLabel", {
			Name = "rank",
			BackgroundTransparency = 1,
			Text = tostring(i),
			Font = Theme.MONO,
			TextSize = 10,
			TextColor3 = isMe and Theme.OK or Theme.current.dim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(5, 0),
			Size = UDim2.new(0, 15, 1, 0),
			ZIndex = 42,
			Parent = row,
		})
		Ui.new("TextLabel", {
			Name = "name",
			BackgroundTransparency = 1,
			Text = p.name,
			Font = Theme.MONO,
			TextSize = m.lbFont,
			TextColor3 = Theme.current.ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(27, 0),
			Size = UDim2.new(1, -75, 1, 0),
			ZIndex = 42,
			Parent = row,
		})
		Ui.new("TextLabel", {
			Name = "pts",
			BackgroundTransparency = 1,
			Text = tostring(p.score),
			Font = Theme.SERIF,
			TextSize = m.narrow and 13 or 14,
			TextColor3 = isLeader and Theme.OK or Theme.current.ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -5, 0, 0),
			Size = UDim2.fromOffset(42, math.ceil(m.lbFont * 1.25) + 8),
			ZIndex = 42,
			Parent = row,
		})
	end
end

function Play.showLiveboard(show)
	Root.liveboard.Visible = show
end

return Play
