--!nonstrict
-- Widget construction, text measurement and the layout numbers lifted straight
-- out of the stylesheet.

local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Stroop.Util)
local Theme = require(script.Parent.Theme)

local Ui = {}

-- ---------- construction ----------
function Ui.new(class, props, children)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		inst.BackgroundTransparency = 1
	end
	if inst:IsA("GuiButton") then
		-- the page styled every button itself; Roblox's automatic press tint
		-- would fight that
		inst.AutoButtonColor = false
	end
	if props then
		local parent = props.Parent
		props.Parent = nil
		for k, v in pairs(props) do
			inst[k] = v
		end
		if parent then
			inst.Parent = parent
		end
		props.Parent = parent
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	return inst
end

function Ui.corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function Ui.stroke(parent, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.new(1, 1, 1)
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Ui.scale(parent, value)
	local s = Instance.new("UIScale")
	s.Scale = value or 1
	s.Parent = parent
	return s
end

-- ---------- measurement ----------
local measureCache = {}

function Ui.measure(text, size, font)
	local key = font.Name .. "\0" .. size .. "\0" .. text
	local cached = measureCache[key]
	if cached then
		return cached
	end
	-- TextService:GetTextSize silently clamps its fontSize argument to 100, so
	-- anything asking for a bigger size (the win/lose insignia, for one) would
	-- otherwise get back the measurement for a much smaller font. Measure at
	-- the capped size and scale the result back up - font metrics scale
	-- linearly, so this recovers the true size.
	local measureSize = math.min(size, 100)
	local scale = size / measureSize
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, measureSize, font, Vector2.new(100000, 100000))
	end)
	if not ok or not v then
		v = Vector2.new(#text * size * 0.6, size * 1.2)
	else
		v = v * scale
	end
	measureCache[key] = v
	return v
end

function Ui.textWidth(text, size, font)
	return Ui.measure(text, size, font).X
end

-- ---------- tracked text ----------
-- Roblox text has no letter-spacing, so anything the page tracked out (every
-- small uppercase label, the logo, BEGIN) is laid out a character at a time.
local Tracked = {}
Tracked.__index = Tracked

function Ui.tracked(props)
	local self = setmetatable({}, Tracked)
	self.font = props.Font or Theme.MONO
	self.size = props.TextSize or 11
	self.spacing = props.Spacing or 0 -- extra px after each glyph
	self.color = props.TextColor3 or Color3.new(1, 1, 1)
	self.transparency = props.TextTransparency or 0
	self.chars = {}
	self.width = 0

	self.frame = Ui.new("Frame", {
		Name = props.Name or "Tracked",
		BackgroundTransparency = 1,
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, math.ceil(self.size * 1.25)),
		ZIndex = props.ZIndex or 1,
		Visible = props.Visible ~= false,
		Parent = props.Parent,
	})
	self:setText(props.Text or "")
	return self
end

function Tracked:setText(text)
	text = tostring(text)
	if self.text == text then
		return
	end
	self.text = text
	for _, c in ipairs(self.chars) do
		c:Destroy()
	end
	self.chars = {}

	local widths = {}
	local total = 0
	local n = 0
	for _, code in utf8.codes(text) do
		n = n + 1
		local ch = utf8.char(code)
		local w = Ui.textWidth(ch, self.size, self.font)
		widths[n] = { ch = ch, w = w }
		total = total + w
	end
	-- the trailing letter-space is dropped so the run stays optically centred
	local visual = total + math.max(0, n - 1) * self.spacing
	self.width = visual
	self.frame.Size = UDim2.fromOffset(math.ceil(visual), math.ceil(self.size * 1.25))

	local x = 0
	for i = 1, n do
		local info = widths[i]
		local label = Ui.new("TextLabel", {
			Name = "c" .. i,
			BackgroundTransparency = 1,
			Text = info.ch,
			Font = self.font,
			TextSize = self.size,
			TextColor3 = self.color,
			TextTransparency = self.transparency,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Position = UDim2.fromOffset(math.floor(x + 0.5), 0),
			Size = UDim2.new(0, math.ceil(info.w) + 2, 1, 0),
			ZIndex = self.frame.ZIndex,
			Parent = self.frame,
		})
		self.chars[i] = label
		x = x + info.w + self.spacing
	end
end

function Tracked:setColor(color)
	self.color = color
	for _, c in ipairs(self.chars) do
		c.TextColor3 = color
	end
end

function Tracked:setTransparency(t)
	self.transparency = t
	for _, c in ipairs(self.chars) do
		c.TextTransparency = t
	end
end

function Tracked:setZIndex(z)
	self.frame.ZIndex = z
	for _, c in ipairs(self.chars) do
		c.ZIndex = z
	end
end

function Tracked:destroy()
	self.frame:Destroy()
end

-- ---------- layout metrics ----------
-- Every number here is the value the stylesheet uses, including the
-- `@media (max-width:520px)` overrides.
function Ui.metrics(viewport)
	local vw, vh = viewport.X, viewport.Y
	local narrow = vw <= 520

	local m = {
		vw = vw,
		vh = vh,
		narrow = narrow,
	}

	-- .hud - padding 16px 20px 6px, label 11.5px, value 15px (21px for .key)
	m.hudPadX = narrow and 12 or 20
	m.hudPadTop = narrow and 12 or 16
	m.hudPadBottom = narrow and 5 or 6
	m.hudLabel = 11.5
	m.hudValue = 15
	m.hudKeyValue = narrow and 18 or 21
	m.hudGap = narrow and 12 or 18
	m.hudH = m.hudPadTop + math.ceil(m.hudLabel * 1.25) + 2 + m.hudKeyValue + m.hudPadBottom

	-- .timer-track
	m.timerH = 3

	-- .word - clamp(32px, 7.5vw, 72px)
	m.wordSize = math.clamp(vw * 0.075, 32, 72)

	-- #placement - clamp(19px, 3.4vw, 30px), top: 50% + clamp(38px, 6vh, 64px)
	m.placementSize = math.clamp(vw * 0.034, 19, 30)
	m.placementTop = vh * 0.5 + math.clamp(vh * 0.06, 38, 64)

	-- .opt
	m.optFont = narrow and 14 or 18
	m.optPadX = narrow and 10 or 28
	m.optPadY = narrow and 12 or 21
	m.optBorder = 2
	m.optRadius = 13
	m.optMinWidth = narrow and 0 or 132
	m.optH = math.ceil(m.optFont * 1.2) + m.optPadY * 2 + m.optBorder * 2

	m.gridFont = narrow and 12.5 or 18
	m.gridPadX = narrow and 6 or 28
	m.gridPadY = narrow and 10 or 21
	m.gridH = math.ceil(m.gridFont * 1.2) + m.gridPadY * 2 + m.optBorder * 2

	-- .options - gap 20/48, padding 16 18 62, with the desktop "lift"
	m.optGapX = narrow and 12 or 48
	m.optGapY = narrow and 10 or 20
	m.optPadTop = narrow and 10 or 16
	m.optPadSide = narrow and 14 or 18
	m.optPadBottom = narrow and 20 or 188

	m.gridGapX = narrow and 8 or 48
	m.gridGapY = narrow and 8 or 20
	m.gridPadTop = narrow and 10 or 16
	m.gridPadSide = narrow and 10 or 18
	m.gridPadBottom = narrow and 16 or 104

	-- .stage-label
	m.stageLabelSize = 10
	m.stageLabelTrack = 10 * 0.28

	-- #liveboard
	m.lbTop = narrow and 52 or 56
	m.lbRight = narrow and 8 or 14
	m.lbMinW = narrow and 140 or 168
	m.lbMaxW = narrow and 170 or 220
	m.lbFont = narrow and 10.5 or 11

	-- cards
	m.cardWidth = math.min(400, vw * 0.9)
	m.megaSize = math.clamp(vw * 0.17, 56, 104)
	m.resultSize = math.clamp(vw * 0.26, 88, 168)

	return m
end

-- ---------- misc ----------
function Ui.gradient(parent, colors, rotation)
	local g = Instance.new("UIGradient")
	g.Color = colors
	g.Rotation = rotation or 0
	g.Parent = parent
	return g
end

-- A non-interactive click-through blocker used by the overlay.
function Ui.blocker(props)
	props = props or {}
	props.Text = ""
	props.AutoButtonColor = false
	return Ui.new("TextButton", props)
end

return Ui
