--!nonstrict
--[[
	The boss layer's handwriting.

	In the web build each letter was an SVG <text> whose outline was stroked on
	with a dash-offset animation and then inked in. Roblox has no path access to
	a glyph, so the outline is revealed by a per-letter clip that sweeps across
	it - one letter at a time, on the same 54 ms stagger - and the fill then
	fades in underneath, with the stroke thinning to a third as it does. The
	beats and their timings are the ones from the stylesheet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Stroop.Util)
local Ui = require(script.Parent.Parent.Ui)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)

local Writer = {}

Writer.STAGGER = 0.054
Writer.TAIL = 1.08
Writer.UNSTAGGER = 0.011
Writer.UNTAIL = 0.32

local Line = {}
Line.__index = Line

-- opts: size, tight, color, font, sw, dw, id, iw, bold, yOffset
function Writer.build(parent, text, opts)
	opts = opts or {}
	local viewport = parent.AbsoluteSize
	local size = opts.size or math.floor(math.min(52, math.max(30, viewport.X * 0.032)) + 0.5)
	local font = opts.font or Theme.MSG
	local color = opts.color or Color3.new(1, 1, 1)
	local sw = opts.sw or 1.1
	local dw = opts.dw or 1.0
	local inkDelay = opts.id or 0.416
	local inkTime = opts.iw or 0.64

	local self = setmetatable({}, Line)
	self.letters = {}
	self.size = size
	self.sw = sw
	self.dw = dw
	self.inkDelay = inkDelay
	self.inkTime = inkTime
	self.cancels = {}

	-- lay the line out once to get per-glyph widths
	local glyphs = {}
	local total = 0
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		local w = Ui.textWidth(ch == " " and "\u{00A0}" or ch, size, font)
		table.insert(glyphs, { ch = ch, w = w })
		total = total + w
	end

	local h = opts.tight and math.ceil(size * 1.02) or math.ceil(size * 1.4)
	local holder = Ui.new("Frame", {
		Name = "writeLine",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, opts.yOffset or 0),
		Size = UDim2.fromOffset(math.ceil(total), h),
		ZIndex = opts.zIndex or 60,
		Parent = parent,
	})
	self.holder = holder

	local x = 0
	for i, g in ipairs(glyphs) do
		if g.ch ~= " " then
			-- the clip that sweeps the outline into view
			local clip = Ui.new("Frame", {
				Name = "clip" .. i,
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Position = UDim2.fromOffset(math.floor(x + 0.5), 0),
				Size = UDim2.fromOffset(0, h),
				ZIndex = holder.ZIndex,
				Parent = holder,
			})
			local label = Ui.new("TextLabel", {
				Name = "g" .. i,
				BackgroundTransparency = 1,
				Text = g.ch,
				Font = font,
				TextSize = size,
				TextColor3 = color,
				TextTransparency = 1, -- the fill arrives later
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				Size = UDim2.fromOffset(math.ceil(g.w) + 4, h),
				ZIndex = holder.ZIndex,
				Parent = clip,
			})
			local stroke = Ui.stroke(label, sw, color)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

			local letter = {
				clip = clip,
				label = label,
				stroke = stroke,
				width = math.ceil(g.w) + 4,
				delay = (i - 1) * Writer.STAGGER,
			}
			table.insert(self.letters, letter)
			self:animateIn(letter)
		end
		x = x + g.w
	end

	return self
end

function Line:animateIn(letter)
	local sw, dw = self.sw, self.dw
	local inkDelay, inkTime = self.inkDelay, self.inkTime
	table.insert(self.cancels, task.delay(letter.delay, function()
		if not letter.clip.Parent then
			return
		end
		Motion.keyframes(dw, function(p)
			letter.clip.Size = UDim2.fromOffset(math.ceil(letter.width * p), letter.clip.Size.Y.Offset)
		end, Motion.ease.write)
		task.delay(inkDelay, function()
			if not letter.label.Parent then
				return
			end
			Motion.keyframes(inkTime, function(p)
				letter.label.TextTransparency = 1 - p
				letter.stroke.Thickness = Util.lerp(sw, sw * 0.32, p)
			end, Motion.ease.ease)
		end)
	end))
end

-- Drives everything straight to its finished state - used by click-to-skip.
function Line:snap()
	for _, c in ipairs(self.cancels) do
		pcall(task.cancel, c)
	end
	self.cancels = {}
	for _, letter in ipairs(self.letters) do
		if letter.clip.Parent then
			letter.clip.Size = UDim2.fromOffset(letter.width, letter.clip.Size.Y.Offset)
			letter.label.TextTransparency = 0
			letter.stroke.Thickness = self.sw * 0.32
		end
	end
end

-- Reverse of the write: ink drains and each outline retracts, quicker than it
-- formed.
function Line:unwrite()
	for i, letter in ipairs(self.letters) do
		local delay = (i - 1) * Writer.UNSTAGGER
		task.delay(delay, function()
			if not letter.clip.Parent then
				return
			end
			Motion.keyframes(0.15, function(p)
				letter.label.TextTransparency = p
				letter.stroke.Thickness = Util.lerp(self.sw * 0.32, self.sw, p)
			end, Motion.ease.ease)
			task.delay(0.04, function()
				if not letter.clip.Parent then
					return
				end
				local w = letter.clip.Size.X.Offset
				Motion.keyframes(0.26, function(p)
					letter.clip.Size = UDim2.fromOffset(math.ceil(w * (1 - p)), letter.clip.Size.Y.Offset)
				end, Motion.ease.unwrite)
			end)
		end)
	end
	return Writer.UNSTAGGER * math.max(0, #self.letters - 1) + Writer.UNTAIL
end

function Line:destroy()
	for _, c in ipairs(self.cancels) do
		pcall(task.cancel, c)
	end
	self.cancels = {}
	if self.holder then
		self.holder:Destroy()
		self.holder = nil
	end
end

function Line:setYOffset(dy)
	self.holder.Position = UDim2.new(0.5, 0, 0.5, dy)
end

-- How long a line takes to finish writing itself.
function Writer.duration(text)
	local n = utf8.len(text) or #text
	return Writer.STAGGER * math.max(0, n - 1) + Writer.TAIL
end

return Writer
