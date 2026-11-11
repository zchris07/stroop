--!nonstrict
-- The six overlay cards: menu, create, join, lobby, brief and the end screen.
-- The overlay is always dark in the original, so these use the literal hex
-- values from the stylesheet rather than the themed tokens.

local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Stroop.Util)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local Root = require(script.Parent.Root)

local INK = Util.hex("#eef0f6")
local DIM = Util.hex("#7b8096")
local LINE = Util.hex("#2a2e3c")
local FIELD_BG = Util.hex("#1b1e29")
local NOTE_TEXT = Util.hex("#b9bdc9")

local Cards = {}
Cards.list = {}

-- Paragraphs re-wrap when the card width changes, so every one of them is
-- remeasured on resize.
local autoText = {}

local function measureHeight(label, width, lineHeight)
	local ok, size = pcall(function()
		return TextService:GetTextSize(
			label.Text,
			label.TextSize,
			label.Font,
			Vector2.new(math.max(20, width), 100000)
		)
	end)
	local h = ok and size.Y or label.TextSize * 1.4
	local lines = math.max(1, math.ceil(h / math.max(1, label.TextSize)))
	return math.ceil(lines * label.TextSize * (lineHeight or 1))
end

-- ---------- stack builder ----------
local Stack = {}
Stack.__index = Stack

local function newStack(card)
	return setmetatable({ card = card, order = 0 }, Stack)
end

-- Wraps an element so the CSS bottom margin can live on the wrapper.
function Stack:row(height, marginBottom)
	self.order = self.order + 1
	local row = Ui.new("Frame", {
		Name = "row" .. self.order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height + (marginBottom or 0)),
		LayoutOrder = self.order,
		ZIndex = 52,
		Parent = self.card,
	})
	row:SetAttribute("Margin", marginBottom or 0)
	return row
end

function Stack:label(text, props, marginBottom)
	local lineHeight = props.LineHeight or 1.3
	local size = props.TextSize or 13
	local row = self:row(math.ceil(size * lineHeight), marginBottom)
	local label = Ui.new("TextLabel", {
		Name = props.Name or "label",
		BackgroundTransparency = 1,
		Text = text,
		Font = props.Font or Theme.MONO,
		TextSize = size,
		TextColor3 = props.TextColor3 or INK,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = props.TextWrapped ~= false,
		LineHeight = lineHeight,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 53,
		Parent = row,
	})
	if props.TextWrapped ~= false then
		table.insert(autoText, { row = row, label = label, lineHeight = lineHeight })
	end
	return label, row
end

function Stack:tracked(text, props, marginBottom)
	local size = props.TextSize or 11
	local row = self:row(math.ceil(size * 1.4), marginBottom)
	local t = Ui.tracked({
		Name = props.Name or "tracked",
		Text = text,
		Font = props.Font or Theme.MONO,
		TextSize = size,
		Spacing = props.Spacing or 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		ZIndex = 53,
		Parent = row,
	})
	t:setColor(props.TextColor3 or DIM)
	return t, row
end

-- .go-btn / .go-btn.ghost
function Stack:button(text, opts)
	opts = opts or {}
	local h = 14 * 2 + math.ceil(13 * 1.2)
	local row = self:row(h, opts.marginBottom or 8)
	local btn = Ui.new("TextButton", {
		Name = opts.Name or "goBtn",
		Text = "",
		BackgroundTransparency = opts.ghost and 1 or 0,
		BackgroundColor3 = INK,
		Size = UDim2.new(1, 0, 0, h),
		ZIndex = 53,
		Parent = row,
	})
	Ui.corner(btn, 10)
	if opts.ghost then
		Ui.stroke(btn, 1.5, LINE)
	end
	local label = Ui.tracked({
		Name = "label",
		Text = text,
		Font = Theme.MONO,
		TextSize = 13,
		Spacing = 13 * 0.1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 54,
		Parent = btn,
	})
	label:setColor(opts.ghost and INK or Util.hex("#0a0b10"))

	local scale = Ui.scale(btn, 1)
	btn.MouseEnter:Connect(function()
		btn.BackgroundTransparency = opts.ghost and 1 or 0.1
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundTransparency = opts.ghost and 1 or 0
		scale.Scale = 1
	end)
	btn.MouseButton1Down:Connect(function()
		scale.Scale = 0.98
	end)
	btn.MouseButton1Up:Connect(function()
		scale.Scale = 1
	end)

	return btn, label, row
end

-- .small-link
function Stack:smallLink(text, marginBottom)
	local row = self:row(math.ceil(11.5 * 1.4) + 14, marginBottom or 0)
	local btn = Ui.new("TextButton", {
		Name = "smallLink",
		Text = text,
		Font = Theme.MONO,
		TextSize = 11.5,
		TextColor3 = DIM,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, math.ceil(11.5 * 1.4)),
		ZIndex = 53,
		Parent = row,
	})
	-- Roblox text has no underline, so the link is drawn with a hairline.
	Ui.new("Frame", {
		Name = "underline",
		BackgroundTransparency = 0,
		BackgroundColor3 = DIM,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(math.ceil(Ui.textWidth(text, 11.5, Theme.MONO)), 1),
		ZIndex = 53,
		Parent = btn,
	})
	return btn, row
end

-- .field
function Stack:field(labelText, placeholder, opts)
	opts = opts or {}
	local labelH = math.ceil(10.5 * 1.4) + 6
	local inputH = 12 * 2 + math.ceil(15 * 1.3)
	local row = self:row(labelH + inputH + 14, opts.marginBottom or 0)

	local cap = Ui.tracked({
		Name = "fieldLabel",
		Text = labelText:upper(),
		Font = Theme.MONO,
		TextSize = 10.5,
		Spacing = 10.5 * 0.16,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(0, 14),
		ZIndex = 53,
		Parent = row,
	})
	cap:setColor(DIM)

	local box = Ui.new("TextBox", {
		Name = "input",
		Text = "",
		PlaceholderText = placeholder or "",
		PlaceholderColor3 = DIM,
		Font = Theme.MONO,
		TextSize = 15,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = FIELD_BG,
		Position = UDim2.fromOffset(0, 14 + labelH),
		Size = UDim2.new(1, 0, 0, inputH),
		ZIndex = 53,
		Parent = row,
	})
	Ui.corner(box, 9)
	local stroke = Ui.stroke(box, 1.5, LINE)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = box
	box.Focused:Connect(function()
		stroke.Color = Util.hex("#454a5e")
	end)
	box.FocusLost:Connect(function()
		stroke.Color = LINE
	end)
	if opts.upper then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local up = box.Text:upper()
			if up ~= box.Text then
				box.Text = up
			end
		end)
	end
	return box, row
end

-- .roster
function Stack:roster(marginBottom)
	local row = self:row(0, marginBottom or 16)
	local list = Ui.new("Frame", {
		Name = "roster",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 53,
		Parent = row,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	-- the wrapper follows the roster's own height so the card keeps flowing
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		row.Size = UDim2.new(1, 0, 0, list.AbsoluteSize.Y + (marginBottom or 16))
	end)
	return list, row
end

-- .stat-row
function Stack:statRow(names)
	local row = self:row(math.ceil(22 * 1.3) + math.ceil(10 * 1.6) + 18, 22)
	local holder = Ui.new("Frame", {
		Name = "statRow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 1, -18),
		ZIndex = 53,
		Parent = row,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 26)
	layout.Parent = holder

	local out = {}
	for i, name in ipairs(names) do
		local stat = Ui.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, math.ceil(22 * 1.3) + math.ceil(10 * 1.6)),
			LayoutOrder = i,
			ZIndex = 53,
			Parent = holder,
		})
		local value = Ui.new("TextLabel", {
			Name = "value",
			BackgroundTransparency = 1,
			Text = "0",
			Font = Theme.SERIF,
			TextSize = 22,
			TextColor3 = INK,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, math.ceil(22 * 1.3)),
			ZIndex = 54,
			Parent = stat,
		})
		local cap = Ui.tracked({
			Name = "caption",
			Text = name,
			Font = Theme.MONO,
			TextSize = 10,
			Spacing = 10 * 0.18,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, math.ceil(22 * 1.3)),
			ZIndex = 54,
			Parent = stat,
		})
		cap:setColor(DIM)
		out[name] = { frame = stat, value = value, caption = cap }
	end
	return out, row
end

-- The shared "The Stroop Effect" explainer used by the lobby and brief cards.
local function stroopNote(stack)
	stack:label("The Stroop Effect", {
		Font = Theme.SERIF,
		TextSize = 30,
		TextColor3 = Color3.new(1, 1, 1),
		LineHeight = 1.2,
	}, 18)
	stack:label(
		"Your brain reads words faster than it processes color. When the two conflict "
			.. "\u{2014} the word RED written in blue ink \u{2014} it creates interference, and you slow down.",
		{ Font = Theme.MONO, TextSize = 13.5, TextColor3 = NOTE_TEXT, LineHeight = 1.85 },
		14
	)
	stack:label(
		"Pick the ink color, not the word. The game gets harder as your streak grows "
			.. "\u{2014} more choices, a flashing backdrop, and a voice calling out the wrong color to throw you off.",
		{ Font = Theme.MONO, TextSize = 13.5, TextColor3 = NOTE_TEXT, LineHeight = 1.85 },
		24
	)
end

-- ---------- cards ----------
local function newCard(name, order, full)
	local card = Ui.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 400, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = order,
		ZIndex = 52,
		Parent = Root.scroller,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
	if not full then
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 24)
		pad.PaddingRight = UDim.new(0, 24)
		pad.Parent = card
	end
	Cards.list[name] = card
	return card, newStack(card)
end

function Cards.build()
	-- ===== MAIN MENU =====
	local menu, s = newCard("cardMenu", 1, true)
	Cards.menu = {}
	do
		local inner = Ui.new("Frame", {
			Name = "menuContent",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 52,
			Parent = menu,
		})
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = inner
		local st = newStack(inner)

		-- h1.mega gets the full viewport width lane
		local megaRow = st:row(110, 0)
		Cards.menu.mega = Ui.new("TextLabel", {
			Name = "mega",
			BackgroundTransparency = 1,
			Text = "STROOP",
			Font = Theme.SERIF,
			TextSize = 104,
			TextColor3 = INK,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 53,
			Parent = megaRow,
		})
		Cards.menu.megaRow = megaRow

		local body = Ui.new("Frame", {
			Name = "body",
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 400, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 99,
			ZIndex = 52,
			Parent = inner,
		})
		Cards.menu.body = body
		local bodyLayout = Instance.new("UIListLayout")
		bodyLayout.FillDirection = Enum.FillDirection.Vertical
		bodyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bodyLayout.Parent = body
		local bodyPad = Instance.new("UIPadding")
		bodyPad.PaddingLeft = UDim.new(0, 24)
		bodyPad.PaddingRight = UDim.new(0, 24)
		bodyPad.Parent = body

		local bs = newStack(body)
		Cards.menu.tagline = bs:tracked("guess the ink, not the word", {
			Font = Theme.MONO,
			TextSize = 13,
			Spacing = 13 * 0.06,
			TextColor3 = DIM,
		}, 26)
		Cards.menu.solo = bs:button("PLAY SOLO")
		Cards.menu.create = bs:button("CREATE LOBBY", { ghost = true })
		Cards.menu.join = bs:button("JOIN LOBBY", { ghost = true })

		-- the developer layout previews, hidden until the dev code is entered
		local devRow = bs:row(0, 0)
		devRow.Visible = false
		devRow.AutomaticSize = Enum.AutomaticSize.Y
		devRow.Size = UDim2.new(1, 0, 0, 0)
		local devGrid = Instance.new("UIGridLayout")
		devGrid.CellSize = UDim2.new(0, 96, 0, 22)
		devGrid.CellPadding = UDim2.fromOffset(8, 4)
		devGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		devGrid.SortOrder = Enum.SortOrder.LayoutOrder
		devGrid.Parent = devRow
		Cards.menu.devRow = devRow
		Cards.menu.devButtons = {}

		local devItems = {
			{ id = "boss", text = "jump to stage 4" },
			{ id = "win", text = "win ending" },
			{ id = "loss", text = "loss ending" },
			{ id = "grid", text = "grid" },
			{ id = "orbit", text = "orbit" },
			{ id = "pulse", text = "pulse" },
			{ id = "fall", text = "fall" },
			{ id = "drift", text = "drift" },
			{ id = "dvd", text = "dvd" },
			{ id = "alternate", text = "alternate" },
			{ id = "decoy", text = "decoy" },
			{ id = "spotlight", text = "spotlight" },
			{ id = "blink", text = "blink" },
			{ id = "ribbon", text = "ribbon" },
		}
		for i, item in ipairs(devItems) do
			Cards.menu.devButtons[item.id] = Ui.new("TextButton", {
				Name = item.id,
				Text = item.text,
				Font = Theme.MONO,
				TextSize = 11,
				TextColor3 = DIM,
				BackgroundTransparency = 1,
				LayoutOrder = i,
				ZIndex = 53,
				Parent = devRow,
			})
		end
	end

	-- ===== CREATE =====
	local _, cs = newCard("cardCreate", 2)
	Cards.create = {}
	cs:tracked("NEW LOBBY", { TextSize = 11, Spacing = 11 * 0.3, TextColor3 = DIM }, 10)
	cs:label("Pick a name", { Font = Theme.SERIF, TextSize = 27, LineHeight = 1.25 }, 14)
	Cards.create.name = cs:field("Display name", "e.g. RIVER")
	Cards.create.err = cs:label("", {
		Font = Theme.MONO,
		TextSize = 12,
		TextColor3 = Theme.BAD,
		LineHeight = 1.2,
	}, 8)
	Cards.create.submit, Cards.create.submitLabel = cs:button("CREATE")
	Cards.create.back = cs:smallLink("\u{2190} back")

	-- ===== JOIN =====
	local _, js = newCard("cardJoin", 3)
	Cards.join = {}
	js:tracked("JOIN A LOBBY", { TextSize = 11, Spacing = 11 * 0.3, TextColor3 = DIM }, 10)
	js:label("Enter the code", { Font = Theme.SERIF, TextSize = 27, LineHeight = 1.25 }, 14)
	Cards.join.code = js:field("Lobby code", "e.g. 7K3QM", { upper = true })
	Cards.join.name = js:field("Display name", "e.g. RIVER")
	Cards.join.err = js:label("", {
		Font = Theme.MONO,
		TextSize = 12,
		TextColor3 = Theme.BAD,
		LineHeight = 1.2,
	}, 8)
	Cards.join.submit, Cards.join.submitLabel = js:button("JOIN")
	Cards.join.back = js:smallLink("\u{2190} back")

	-- ===== LOBBY =====
	local _, ls = newCard("cardLobby", 4)
	Cards.lobby = {}
	ls:tracked("LOBBY CODE", { TextSize = 11, Spacing = 11 * 0.3, TextColor3 = DIM }, 10)
	Cards.lobby.code = ls:tracked("------", {
		Font = Theme.SERIF,
		TextSize = 38,
		Spacing = 38 * 0.14,
		TextColor3 = INK,
	}, 6)
	-- The web build offered a shareable URL; in Roblox the code is the whole
	-- invitation, so this says how to use it instead.
	ls:label(
		"Anyone in this server can join with that code \u{2014} they pick JOIN LOBBY on the menu. "
			.. "To play with friends, have them join your server first.",
		{ Font = Theme.MONO, TextSize = 12, TextColor3 = DIM, LineHeight = 1.7 },
		16
	)
	ls:label(
		"Everyone sees the exact same word and color at the same moment. "
			.. "Fastest correct answer scores the most.",
		{ Font = Theme.MONO, TextSize = 13, TextColor3 = DIM, LineHeight = 1.6 },
		16
	)
	stroopNote(ls)
	Cards.lobby.target = ls:field("Points to win (optional \u{2014} defaults to 10 \u{00D7} players)", "auto")
	Cards.lobby.roster = ls:roster()
	Cards.lobby.play = ls:button("START GAME")
	Cards.lobby.waitNote = ls:label("Waiting for the host to start the game\u{2026}", {
		Font = Theme.MONO,
		TextSize = 11,
		TextColor3 = DIM,
		LineHeight = 1.4,
	}, 0)
	Cards.lobby.leave = ls:smallLink("leave lobby")

	-- ===== SOLO BRIEF =====
	local _, bs2 = newCard("cardBrief", 5)
	Cards.brief = {}
	stroopNote(bs2)
	Cards.brief.start = bs2:button("BEGIN SESSION")
	Cards.brief.back = bs2:button("RETURN", { ghost = true })

	-- ===== END =====
	local _, os2 = newCard("cardOver", 6)
	Cards.over = {}
	Cards.over.eyebrow = os2:tracked("SESSION ENDED", {
		TextSize = 11,
		Spacing = 11 * 0.3,
		TextColor3 = DIM,
	}, 10)
	Cards.over.headline = os2:label("Session complete", {
		Font = Theme.SERIF,
		TextSize = 27,
		LineHeight = 1.25,
		TextWrapped = false,
	}, 14)
	Cards.over.headlineRow = Cards.over.headline.Parent
	Cards.over.stats = os2:statRow({ "SCORE", "STAGE", "BEST" })
	Cards.over.roster = os2:roster()
	Cards.over.rosterRow = Cards.over.roster.Parent
	Cards.over.restart = os2:button("RUN AGAIN")
	Cards.over.waitNote = os2:label("Waiting for the host to start a new match\u{2026}", {
		Font = Theme.MONO,
		TextSize = 11,
		TextColor3 = DIM,
		LineHeight = 1.4,
	}, 0)
	Cards.over.returnBtn = os2:button("RETURN", { ghost = true })
	Cards.over.leave = os2:smallLink("leave lobby")

	Root.onResize(Cards.relayout)
	Cards.relayout(Root.m)
	return Cards
end

-- ---------- roster rendering ----------
function Cards.renderRoster(container, players)
	container:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	if not players or #players == 0 then
		local row = Ui.new("Frame", {
			Name = "empty",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 33),
			LayoutOrder = 1,
			ZIndex = 53,
			Parent = container,
		})
		Ui.new("TextLabel", {
			Name = "text",
			BackgroundTransparency = 1,
			Text = "waiting for players\u{2026}",
			Font = Theme.MONO,
			TextSize = 13,
			TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			ZIndex = 54,
			Parent = row,
		})
		return
	end

	for i, p in ipairs(players) do
		local row = Ui.new("Frame", {
			Name = "row" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 33),
			LayoutOrder = i,
			ZIndex = 53,
			Parent = container,
		})
		Ui.new("Frame", {
			Name = "line",
			BackgroundTransparency = 0,
			BackgroundColor3 = LINE,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 53,
			Parent = row,
		})
		Ui.new("TextLabel", {
			Name = "name",
			BackgroundTransparency = 1,
			Text = p.name,
			Font = Theme.MONO,
			TextSize = 13,
			TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -70, 1, 0),
			ZIndex = 54,
			Parent = row,
		})
		Ui.new("TextLabel", {
			Name = "score",
			BackgroundTransparency = 1,
			Text = tostring(p.score),
			Font = Theme.MONO,
			TextSize = 13,
			TextColor3 = DIM,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.fromOffset(60, 33),
			ZIndex = 54,
			Parent = row,
		})
	end
end

-- ---------- visibility ----------
-- Takes the short name the page used ("menu", "lobby", ...).
function Cards.show(name)
	local target = "card" .. name:sub(1, 1):upper() .. name:sub(2)
	for cardName, card in pairs(Cards.list) do
		card.Visible = (cardName == target)
	end
	Root.overlay.Visible = true
	Root.scroller.CanvasPosition = Vector2.new(0, 0)
end

function Cards.hideAll()
	for _, card in pairs(Cards.list) do
		card.Visible = false
	end
end

-- ---------- resize ----------
function Cards.relayout(m)
	if not m then
		return
	end
	local cardW = m.cardWidth

	for name, card in pairs(Cards.list) do
		if name == "cardMenu" then
			card.Size = UDim2.new(1, 0, 0, 0)
		else
			card.Size = UDim2.new(0, math.ceil(cardW), 0, 0)
		end
	end

	if Cards.menu then
		Cards.menu.mega.TextSize = m.megaSize
		Cards.menu.megaRow.Size = UDim2.new(1, 0, 0, math.ceil(m.megaSize * 1.08))
		Cards.menu.body.Size = UDim2.new(0, math.ceil(math.min(400, m.vw * 0.9)), 0, 0)
	end

	-- paragraphs re-wrap at the new width
	for _, entry in ipairs(autoText) do
		if entry.row.Parent then
			local width = entry.row.AbsoluteSize.X
			if width < 10 then
				width = cardW - 48
			end
			local h = measureHeight(entry.label, width, entry.lineHeight)
			local margin = entry.row:GetAttribute("Margin") or 0
			entry.row.Size = UDim2.new(1, 0, 0, h + margin)
			entry.label.Size = UDim2.new(1, 0, 0, h)
		end
	end
end

return Cards
