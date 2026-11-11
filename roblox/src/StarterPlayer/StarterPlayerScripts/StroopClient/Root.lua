--!nonstrict
-- The play surface: HUD, timer, stage, word, options, live leaderboard and the
-- overlay the cards sit in. Mirrors the markup and stylesheet of the page.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Stroop.Config)
local Util = require(ReplicatedStorage.Stroop.Util)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local Root = {}

local resizeHandlers = {}

function Root.onResize(fn)
	table.insert(resizeHandlers, fn)
end

function Root.build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Ui.new("ScreenGui", {
		Name = "Stroop",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		Parent = playerGui,
	})
	Root.gui = gui

	-- ---------- #app ----------
	local app = Ui.new("Frame", {
		Name = "app",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.current.pageBg,
		ZIndex = 0,
		Parent = gui,
	})
	Root.app = app
	Theme.bind(function(t)
		app.BackgroundColor3 = t.pageBg
	end)

	-- ---------- #bgTint ----------
	Root.bgTint = Ui.new("Frame", {
		Name = "bgTint",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 1,
		Parent = app,
	})

	-- ---------- .hud ----------
	local hud = Ui.new("CanvasGroup", {
		Name = "hud",
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = app,
	})
	Root.hud = hud

	local brandWrap = Ui.new("Frame", {
		Name = "brandWrap",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 30,
		Parent = hud,
	})
	local brandText = Ui.tracked({
		Name = "brandText",
		Text = "STROOP",
		Font = Theme.SERIF,
		TextSize = 15,
		Spacing = 15 * 0.08,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(0, 0),
		ZIndex = 31,
		Parent = brandWrap,
	})
	local brandBtn = Ui.blocker({
		Name = "brandBtn",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 32,
		Parent = brandWrap,
	})
	Root.brandWrap = brandWrap
	Root.brandBtn = brandBtn
	Root.brandText = brandText
	Theme.bind(function(t)
		brandText:setColor(t.ink)
	end)
	brandBtn.MouseEnter:Connect(function()
		brandText:setTransparency(0.35)
	end)
	brandBtn.MouseLeave:Connect(function()
		brandText:setTransparency(0)
	end)

	-- the right-hand cluster
	local cluster = Ui.new("Frame", {
		Name = "cluster",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 30,
		Parent = hud,
	})
	Root.cluster = cluster
	local clusterLayout = Instance.new("UIListLayout")
	clusterLayout.FillDirection = Enum.FillDirection.Horizontal
	clusterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	clusterLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	clusterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	clusterLayout.Padding = UDim.new(0, 18)
	clusterLayout.Parent = cluster
	Root.clusterLayout = clusterLayout

	-- A HUD metric: tracked caption above, serif value below.
	local function metric(name, caption, order, key, valueColor)
		local frame = Ui.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.XY,
			LayoutOrder = order,
			ZIndex = 30,
			Parent = cluster,
		})
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 2)
		layout.Parent = frame

		local cap = Ui.tracked({
			Name = "caption",
			Text = caption,
			Font = Theme.MONO,
			TextSize = 11.5,
			Spacing = 11.5 * 0.14,
			AnchorPoint = Vector2.new(0, 0),
			ZIndex = 30,
			Parent = frame,
		})
		cap.frame.LayoutOrder = 1

		local value = Ui.new("TextLabel", {
			Name = "value",
			BackgroundTransparency = 1,
			Text = "0",
			Font = Theme.SERIF,
			TextSize = key and 21 or 15,
			TextColor3 = valueColor or Theme.current.ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			LayoutOrder = 2,
			ZIndex = 30,
			Parent = frame,
		})

		Theme.bind(function(t)
			cap:setColor(t.dim)
			if not valueColor then
				value.TextColor3 = t.ink
			end
		end)

		return { frame = frame, caption = cap, value = value, key = key }
	end

	Root.scoreMetric = metric("scoreMetric", "SCORE", 1, true)
	Root.goalMetric = metric("goalMetric", "TO WIN", 2, true, Theme.OK)
	Root.goalMetric.value.Text = "\u{2013}"
	Root.goalMetric.frame.Visible = false
	Root.stageMetric = metric("stageNum", "STAGE", 3, false)
	Root.stageMetric.value.Text = "1"
	Root.bestMetric = metric("bestMetric", "BEST", 4, false)

	-- #lives - three dots, letter-spaced
	local lives = Ui.new("Frame", {
		Name = "lives",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 5,
		ZIndex = 30,
		Parent = cluster,
	})
	local livesLayout = Instance.new("UIListLayout")
	livesLayout.FillDirection = Enum.FillDirection.Horizontal
	livesLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	livesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	livesLayout.Padding = UDim.new(0, math.floor(14 * 0.2 + 0.5))
	livesLayout.Parent = lives
	Root.lives = lives
	Root.lifeDots = {}
	for i = 1, Config.LIVES_START do
		Root.lifeDots[i] = Ui.new("TextLabel", {
			Name = "dot" .. i,
			BackgroundTransparency = 1,
			Text = utf8.char(0x25CF),
			Font = Theme.MONO,
			TextSize = 14,
			TextColor3 = Theme.BAD,
			AutomaticSize = Enum.AutomaticSize.XY,
			LayoutOrder = i,
			ZIndex = 30,
			Parent = lives,
		})
	end

	-- .hud-leave
	local leaveWrap = Ui.new("TextButton", {
		Name = "leaveBtn",
		Text = "",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 6,
		ZIndex = 30,
		Parent = cluster,
	})
	Ui.corner(leaveWrap, 8)
	local leaveStroke = Ui.stroke(leaveWrap, 1.5, Theme.current.panelLine)
	local leavePad = Instance.new("UIPadding")
	leavePad.PaddingLeft = UDim.new(0, 12)
	leavePad.PaddingRight = UDim.new(0, 12)
	leavePad.Parent = leaveWrap
	local leaveText = Ui.tracked({
		Name = "leaveText",
		Text = "leave",
		Font = Theme.MONO,
		TextSize = 11,
		Spacing = 11 * 0.14,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		ZIndex = 31,
		Parent = leaveWrap,
	})
	Root.leaveBtn = leaveWrap
	Theme.bind(function(t)
		leaveStroke.Color = t.panelLine
		leaveText:setColor(t.dim)
	end)
	leaveWrap.MouseEnter:Connect(function()
		leaveStroke.Color = Theme.current.ink
		leaveText:setColor(Theme.current.ink)
	end)
	leaveWrap.MouseLeave:Connect(function()
		leaveStroke.Color = Theme.current.panelLine
		leaveText:setColor(Theme.current.dim)
	end)

	-- ---------- .timer-track ----------
	local timerTrack = Ui.new("CanvasGroup", {
		Name = "timerTrack",
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.current.panelLine,
		ZIndex = 30,
		ClipsDescendants = true,
		Parent = app,
	})
	Root.timerTrack = timerTrack
	Theme.bind(function(t)
		timerTrack.BackgroundColor3 = t.panelLine
	end)

	local timerFill = Ui.new("Frame", {
		Name = "timerFill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 31,
		Parent = timerTrack,
	})
	Ui.gradient(timerFill, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.OK),
		ColorSequenceKeypoint.new(0.65, Util.hex("#f5b800")),
		ColorSequenceKeypoint.new(1, Theme.BAD),
	}))
	Root.timerFill = timerFill

	-- ---------- .stage ----------
	local stage = Ui.new("CanvasGroup", {
		Name = "stage",
		BackgroundTransparency = 1,
		ZIndex = 15,
		Parent = app,
	})
	Root.stage = stage

	Root.stageLabel = Ui.tracked({
		Name = "stageLabel",
		Text = "STAGE 1",
		Font = Theme.MONO,
		TextSize = 10,
		Spacing = 10 * 0.28,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		ZIndex = 30,
		Parent = stage,
	})
	Theme.bind(function(t)
		Root.stageLabel:setColor(t.dim)
	end)

	Root.waitingMsg = Ui.new("TextLabel", {
		Name = "waitingMsg",
		BackgroundTransparency = 1,
		Text = "",
		Font = Theme.MONO,
		TextSize = 11,
		TextColor3 = Theme.OK,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.new(0.9, 0, 0, 16),
		Visible = false,
		ZIndex = 30,
		Parent = stage,
	})

	-- ---------- #liveboard ----------
	local liveboard = Ui.new("Frame", {
		Name = "liveboard",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.current.panel,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(180, 60),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 40,
		Parent = stage,
	})
	Ui.corner(liveboard, 12)
	local lbStroke = Ui.stroke(liveboard, 1, Theme.current.panelLine)
	Root.liveboard = liveboard

	local lbListLayout = Instance.new("UIListLayout")
	lbListLayout.FillDirection = Enum.FillDirection.Vertical
	lbListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lbListLayout.Parent = liveboard

	local lbHead = Ui.new("Frame", {
		Name = "lbHead",
		BackgroundTransparency = 0,
		BackgroundColor3 = Util.mix(Theme.current.ink, Theme.current.panel, 0.05),
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		ZIndex = 41,
		Parent = liveboard,
	})
	local lbHeadLine = Ui.new("Frame", {
		Name = "line",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.current.panelLine,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 42,
		Parent = lbHead,
	})
	local lbLbl = Ui.tracked({
		Name = "lbLbl",
		Text = "FIRST TO",
		Font = Theme.MONO,
		TextSize = 9,
		Spacing = 9 * 0.16,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 11, 0.5, 1),
		ZIndex = 42,
		Parent = lbHead,
	})
	local lbGoal = Ui.new("TextLabel", {
		Name = "lbGoal",
		BackgroundTransparency = 1,
		Text = "\u{2013}",
		Font = Theme.SERIF,
		TextSize = 15,
		TextColor3 = Theme.current.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -11, 0.5, 0),
		Size = UDim2.fromOffset(60, 18),
		ZIndex = 42,
		Parent = lbHead,
	})
	Root.lbGoal = lbGoal

	local lbRows = Ui.new("Frame", {
		Name = "lbRows",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		ZIndex = 41,
		Parent = liveboard,
	})
	local lbRowsPad = Instance.new("UIPadding")
	lbRowsPad.PaddingTop = UDim.new(0, 5)
	lbRowsPad.PaddingBottom = UDim.new(0, 6)
	lbRowsPad.PaddingLeft = UDim.new(0, 6)
	lbRowsPad.PaddingRight = UDim.new(0, 6)
	lbRowsPad.Parent = lbRows
	local lbRowsLayout = Instance.new("UIListLayout")
	lbRowsLayout.FillDirection = Enum.FillDirection.Vertical
	lbRowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lbRowsLayout.Parent = lbRows
	Root.lbRows = lbRows

	Theme.bind(function(t)
		liveboard.BackgroundColor3 = t.panel
		lbStroke.Color = t.panelLine
		lbHead.BackgroundColor3 = Util.mix(t.ink, t.panel, 0.05)
		lbHeadLine.BackgroundColor3 = t.panelLine
		lbLbl:setColor(t.dim)
		lbGoal.TextColor3 = t.ink
	end)

	-- ---------- .word ----------
	-- The word spans the whole app box so it lands on the true visual centre of
	-- the window, not the centre of the space under the HUD.
	local wordGroup = Ui.new("CanvasGroup", {
		Name = "wordGroup",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = app,
	})
	Root.wordGroup = wordGroup

	local word = Ui.new("TextLabel", {
		Name = "word",
		BackgroundTransparency = 1,
		Text = "",
		Font = Theme.SERIF,
		TextSize = 60,
		TextColor3 = Theme.current.ink,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.88, 0, 0, 120),
		ZIndex = 20,
		Parent = wordGroup,
	})
	Root.word = word
	Root.wordScale = Ui.scale(word, 1)

	-- #placement
	local placementGroup = Ui.new("CanvasGroup", {
		Name = "placementGroup",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = app,
	})
	Root.placementGroup = placementGroup

	local placement = Ui.new("TextLabel", {
		Name = "placement",
		BackgroundTransparency = 1,
		Text = "",
		Font = Theme.SERIF,
		TextSize = 26,
		TextColor3 = Theme.current.ink,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(1, 0, 0, 40),
		Visible = false,
		ZIndex = 30,
		Parent = placementGroup,
	})
	Root.placement = placement
	Root.placementScale = Ui.scale(placement, 1)
	Theme.bind(function(t)
		placement.TextColor3 = t.ink
	end)

	-- ---------- .options ----------
	local options = Ui.new("CanvasGroup", {
		Name = "options",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 200),
		ZIndex = 30,
		Parent = app,
	})
	Root.options = options

	-- ---------- .overlay ----------
	local overlay = Ui.new("Frame", {
		Name = "overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.07,
		BackgroundColor3 = Util.hex(Config.THEME.overlayBg),
		ZIndex = 50,
		Parent = app,
	})
	Root.overlay = overlay
	-- swallows clicks aimed at the play surface underneath
	Ui.blocker({
		Name = "overlayBlock",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = overlay,
	})

	local scroller = Ui.new("ScrollingFrame", {
		Name = "scroller",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ZIndex = 51,
		Parent = overlay,
	})
	Root.scroller = scroller
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 24)
	scrollPad.PaddingBottom = UDim.new(0, 24)
	scrollPad.Parent = scroller
	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.FillDirection = Enum.FillDirection.Vertical
	scrollLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	scrollLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Parent = scroller
	Root.scrollLayout = scrollLayout

	-- `#app:not(.in-game)` hides the whole play surface; these are the groups
	-- that fade together when it comes and goes.
	Root.playGroups = {
		Root.hud,
		Root.timerTrack,
		Root.stage,
		Root.wordGroup,
		Root.placementGroup,
		Root.options,
	}
	Root.setInGame(false)

	Root.relayout()
	return Root
end

function Root.setInGame(inGame)
	Root.inGame = inGame
	for _, group in ipairs(Root.playGroups or {}) do
		group.GroupTransparency = inGame and 0 or 1
		group.Visible = inGame
	end
	if not inGame then
		Root.bgTint.BackgroundTransparency = 1
	end
end

function Root.setGroupTransparency(t)
	for _, group in ipairs(Root.playGroups or {}) do
		group.GroupTransparency = t
	end
end

-- ---------- layout ----------
-- `.options` reports its own height; the stage takes whatever is left, exactly
-- as the column flexbox did.
Root.optionsHeight = 200

function Root.relayout()
	local viewport = Root.gui.AbsoluteSize
	if viewport.X < 1 then
		viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	end
	local m = Ui.metrics(viewport)
	Root.m = m

	Root.hud.Size = UDim2.new(1, 0, 0, m.hudH)
	Root.clusterLayout.Padding = UDim.new(0, m.hudGap)
	Root.cluster.Position = UDim2.new(1, -m.hudPadX, 1, -m.hudPadBottom)
	Root.cluster.Size = UDim2.new(0, 0, 0, m.hudH - m.hudPadTop - m.hudPadBottom)
	local brandW = Root.brandText.width
	Root.brandWrap.Position = UDim2.new(0, m.hudPadX, 1, -m.hudPadBottom)
	Root.brandWrap.Size = UDim2.fromOffset(math.ceil(brandW), math.ceil(15 * 1.4))

	for _, met in ipairs({ Root.scoreMetric, Root.goalMetric, Root.stageMetric, Root.bestMetric }) do
		met.value.TextSize = met.key and m.hudKeyValue or m.hudValue
	end

	Root.timerTrack.Position = UDim2.fromOffset(0, m.hudH)
	Root.timerTrack.Size = UDim2.new(1, 0, 0, m.timerH)

	local stageTop = m.hudH + m.timerH
	local stageH = math.max(0, viewport.Y - stageTop - Root.optionsHeight)
	Root.stage.Position = UDim2.fromOffset(0, stageTop)
	Root.stage.Size = UDim2.new(1, 0, 0, stageH)

	Root.liveboard.Position = UDim2.new(1, -m.lbRight, 0, m.lbTop)
	Root.liveboard.Size = UDim2.fromOffset(m.lbMinW, 0)

	Root.word.TextSize = m.wordSize
	Root.word.Size = UDim2.new(0.88, 0, 0, math.ceil(m.wordSize * 1.6))

	Root.placement.TextSize = m.placementSize
	Root.placement.Position = UDim2.new(0.5, 0, 0, math.floor(m.placementTop))
	Root.placement.Size = UDim2.new(1, 0, 0, math.ceil(m.placementSize * 1.4))

	Root.options.Size = UDim2.new(1, 0, 0, Root.optionsHeight)

	-- the cards size themselves through Cards.relayout, which is registered
	-- below as a resize handler
	for _, fn in ipairs(resizeHandlers) do
		local ok, err = pcall(fn, m)
		if not ok then
			warn("[Stroop] resize handler failed: " .. tostring(err))
		end
	end
end

function Root.setOptionsHeight(h)
	Root.optionsHeight = h
	Root.relayout()
end

return Root
