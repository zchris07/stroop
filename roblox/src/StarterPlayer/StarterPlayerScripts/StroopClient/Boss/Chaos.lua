--!nonstrict
--[[
	The boss's logo, and everything that happens to it.

	The web build churned through ~400 Google fonts while the logo came apart.
	Roblox ships a fixed font list, so the pool here is every usable Enum.Font -
	fewer faces, but the same effect: the wordmark can't hold a single form.

	The logo is built one letter at a time rather than as a single text node,
	because the death sequence needs each glyph to detach and fall on its own.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Stroop.Util)
local Ui = require(script.Parent.Parent.Ui)
local Theme = require(script.Parent.Parent.Theme)

local Chaos = {}

-- ---------- font pool ----------
local POOL = nil
local function fontPool()
	if POOL then
		return POOL
	end
	POOL = {}
	local skip = {
		Unknown = true,
		Legacy = true,
	}
	for _, item in ipairs(Enum.Font:GetEnumItems()) do
		if not skip[item.Name] then
			table.insert(POOL, item)
		end
	end
	if #POOL == 0 then
		POOL = { Enum.Font.SourceSans }
	end
	return POOL
end
Chaos.fontPool = fontPool

-- ---------- logo ----------
local Logo = {}
Logo.__index = Logo

function Chaos.newLogo(parent, text, size, zIndex)
	local self = setmetatable({}, Logo)
	self.text = text or "STROOP"
	self.size = size
	self.font = Theme.SERIF
	self.color = Color3.new(1, 1, 1)
	self.zIndex = zIndex or 62

	self.holder = Ui.new("Frame", {
		Name = "bossLogo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, math.ceil(size * 1.15)),
		ZIndex = self.zIndex,
		Parent = parent,
	})
	-- an inner frame so the bob, the flinch and the churn can each own a
	-- transform without fighting over one
	self.bob = Ui.new("Frame", {
		Name = "bob",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = self.zIndex,
		Parent = self.holder,
	})
	self.inner = Ui.new("Frame", {
		Name = "txt",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = self.zIndex,
		Parent = self.bob,
	})
	self.scale = Ui.scale(self.inner, 1)

	self.letters = {}
	for i = 1, utf8.len(self.text) do
		local offset = utf8.offset(self.text, i)
		local nextOffset = utf8.offset(self.text, i + 1) or (#self.text + 1)
		local ch = self.text:sub(offset, nextOffset - 1)
		self.letters[i] = Ui.new("TextLabel", {
			Name = "l" .. i,
			BackgroundTransparency = 1,
			Text = ch,
			Font = self.font,
			TextSize = size,
			TextColor3 = self.color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Size = UDim2.fromOffset(10, math.ceil(size * 1.15)),
			ZIndex = self.zIndex,
			Parent = self.inner,
		})
	end
	self:relayout()
	return self
end

function Logo:relayout()
	local x = 0
	for _, label in ipairs(self.letters) do
		local w = Ui.textWidth(label.Text, self.size, label.Font)
		label.Size = UDim2.fromOffset(math.ceil(w) + 2, math.ceil(self.size * 1.15))
		label.Position = UDim2.fromOffset(math.floor(x + 0.5), 0)
		x = x + w
	end
	self.width = x
	self.holder.Size = UDim2.fromOffset(math.ceil(x), math.ceil(self.size * 1.15))
	if not self.baseWidth then
		self.baseWidth = x
	end
end

function Logo:setFont(font)
	self.font = font
	for _, label in ipairs(self.letters) do
		label.Font = font
	end
	self:relayout()
end

function Logo:setColor(color)
	self.color = color
	for _, label in ipairs(self.letters) do
		label.TextColor3 = color
	end
end

function Logo:setTransparency(t)
	for _, label in ipairs(self.letters) do
		label.TextTransparency = t
	end
end

function Logo:setVisible(v)
	self.holder.Visible = v
end

function Logo:setSize(size)
	self.size = size
	for _, label in ipairs(self.letters) do
		label.TextSize = size
	end
	self.baseWidth = nil
	self:relayout()
end

function Logo:destroy()
	self.holder:Destroy()
end

-- ---------- bob ----------
-- `@keyframes bossBob` - a 5.4s ease-in-out rise and fall of 7px.
function Logo:startBob()
	self:stopBob()
	local t = 0
	self.bobConn = RunService.RenderStepped:Connect(function(dt)
		t = (t + dt) % 5.4
		local k = t / 5.4
		local eased = -math.cos(k * math.pi * 2) * 0.5 + 0.5
		self.bob.Position = UDim2.fromOffset(0, math.floor(-7 * eased + 0.5))
	end)
end

function Logo:stopBob()
	if self.bobConn then
		self.bobConn:Disconnect()
		self.bobConn = nil
	end
end

-- `settleBob` - let it glide back to rest rather than snapping.
function Logo:settleBob()
	self:stopBob()
	local from = self.bob.Position.Y.Offset
	if from == 0 then
		return
	end
	task.spawn(function()
		local t = 0
		while t < 0.7 do
			local dt = RunService.RenderStepped:Wait()
			t = math.min(0.7, t + dt)
			local p = 1 - (1 - t / 0.7) ^ 2
			self.bob.Position = UDim2.fromOffset(0, math.floor(from * (1 - p) + 0.5))
		end
	end)
end

-- ---------- churn ----------
-- `startChaos`: a font swap every 40-120ms, with the jitter ramping up over
-- six seconds and the occasional big spike.
function Chaos.startChaos(logo)
	local alive = true
	local t0 = os.clock()
	local baseW = logo.baseWidth or logo.width

	task.spawn(function()
		while alive do
			logo:setFont(Util.pick(fontPool()))
			-- hold the same visual width whatever the face does to it
			local s = math.clamp(baseW / math.max(1, logo.width), 0.5, 1.9)
			local k = math.min(1, (os.clock() - t0) / 6)
			local spike = Util.chance(0.14)
			local mag = (spike and Util.rand(9, 24) or Util.rand(0, 7)) * (0.55 + k * 0.9)
			local rot = Util.rand(-2.4, 2.4) * (spike and 2 or 1)
			logo.scale.Scale = s
			logo.inner.Position = UDim2.new(0.5, math.floor(Util.rand(-mag, mag) + 0.5), 0.5, math.floor(Util.rand(-mag, mag) + 0.5))
			logo.inner.Rotation = rot
			task.wait(Util.rand(0.04, 0.12))
		end
	end)

	return function()
		alive = false
	end
end

-- `.bl-txt.convulse` - shaking beyond control, on a 90ms two-step.
function Chaos.startConvulse(logo)
	local alive = true
	task.spawn(function()
		local frames = {
			{ x = -9, y = 4, r = -1.6 },
			{ x = 8, y = -5, r = 1.9 },
			{ x = -6, y = 6, r = -1.1 },
		}
		local i = 1
		while alive do
			local f = frames[i]
			logo.inner.Position = UDim2.new(0.5, f.x, 0.5, f.y)
			logo.inner.Rotation = f.r
			i = i % #frames + 1
			task.wait(0.045)
		end
	end)
	return function()
		alive = false
	end
end

-- `bossFlinch` - jerk, glitch to a random font, flash the colour just guessed.
function Chaos.flinch(logo, color)
	-- @keyframes bossHit
	task.spawn(function()
		local steps = {
			{ at = 0.00, x = 0, y = 0, a = 0, r = 0 },
			{ at = 0.14, x = -8, y = 2, a = 0.55, r = -2.5 },
			{ at = 0.34, x = 7, y = -2, a = 0.15, r = 2 },
			{ at = 0.56, x = -3, y = 1, a = 0, r = -0.5 },
			{ at = 1.00, x = 0, y = 0, a = 0, r = 0 },
		}
		local duration = 0.55
		local t = 0
		while t < duration do
			local dt = RunService.RenderStepped:Wait()
			t = math.min(duration, t + dt)
			local p = t / duration
			for i = 1, #steps - 1 do
				if p >= steps[i].at and p <= steps[i + 1].at then
					local a, b = steps[i], steps[i + 1]
					local k = (p - a.at) / math.max(1e-6, b.at - a.at)
					logo.inner.Position = UDim2.new(
						0.5, math.floor(Util.lerp(a.x, b.x, k) + 0.5),
						0.5, math.floor(Util.lerp(a.y, b.y, k) + 0.5)
					)
					logo.inner.Rotation = Util.lerp(a.r, b.r, k)
					logo:setTransparency(Util.lerp(a.a, b.a, k))
					break
				end
			end
		end
		logo.inner.Position = UDim2.fromScale(0.5, 0.5)
		logo.inner.Rotation = 0
		logo:setTransparency(0)
	end)

	-- the glitch: five quick faces, flashing the guessed colour, then back
	task.spawn(function()
		local original = logo.font
		logo:setColor(color)
		for _ = 1, 5 do
			logo:setFont(Util.pick(fontPool()))
			task.wait(0.055)
		end
		logo:setFont(original)
		logo:setColor(Color3.new(1, 1, 1))
	end)
end

-- ---------- the letters letting go ----------
--[[
	One at a time, in a scrambled order, each letter detaches and falls off the
	bottom of the screen - its own gravity, drift and lazy rotation, knocking
	the others around on the way down.
]]
function Chaos.dropLetters(logo, layer)
	local parentPos = layer.AbsolutePosition
	local pieces = {}

	for i, label in ipairs(logo.letters) do
		local abs = label.AbsolutePosition - parentPos
		local size = label.AbsoluteSize
		local piece = Ui.new("TextLabel", {
			Name = "fall" .. i,
			BackgroundTransparency = 1,
			Text = label.Text,
			Font = label.Font,
			TextSize = label.TextSize,
			TextColor3 = label.TextColor3,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(abs.X + size.X / 2, abs.Y + size.Y / 2),
			Size = UDim2.fromOffset(size.X, size.Y),
			ZIndex = 68,
			Parent = layer,
		})
		table.insert(pieces, {
			el = piece,
			x = abs.X + size.X / 2,
			y = abs.Y + size.Y / 2,
			w = size.X,
			h = size.Y,
			vx = Util.rand(-26, 26), -- a small kick as it lets go
			vy = Util.rand(-40, 10),
			rot = 0,
			spin = Util.rand(-95, 95), -- degrees per second
			g = Util.rand(1500, 2000),
		})
	end

	logo:setVisible(false)

	-- one at a time, but in a scrambled order rather than left to right
	local order = Util.shuffle((function()
		local idx = {}
		for i = 1, #pieces do
			idx[i] = i
		end
		return idx
	end)())
	for slot, idx in ipairs(order) do
		pieces[idx].start = (slot - 1) * 0.42 + Util.rand(0, 0.08)
	end

	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		dt = math.min(0.05, dt)
		local t = os.clock() - t0
		local alive = 0

		for _, L in ipairs(pieces) do
			if L.el then
				alive = alive + 1
				if t >= L.start then
					L.vy = L.vy + L.g * dt
					L.x = L.x + L.vx * dt
					L.y = L.y + L.vy * dt
					L.rot = L.rot + L.spin * dt
					if L.y - L.h > layer.AbsoluteSize.Y then -- fully off the bottom
						L.el:Destroy()
						L.el = nil
						alive = alive - 1
					end
				end
			end
		end

		-- letters already falling bump into each other and into ones still hanging
		local live = {}
		for _, L in ipairs(pieces) do
			if L.el then
				table.insert(live, L)
			end
		end
		for i = 1, #live do
			for j = i + 1, #live do
				local a, b = live[i], live[j]
				local aFalling, bFalling = t >= a.start, t >= b.start
				if aFalling or bFalling then
					local ox = (a.w + b.w) / 2 - math.abs(a.x - b.x)
					local oy = (a.h + b.h) / 2 - math.abs(a.y - b.y)
					if ox > 0 and oy > 0 then
						local REST = 0.45
						if ox < oy then -- resolve along the shallower axis
							local sgn = Util.sign(a.x - b.x)
							if sgn == 0 then
								sgn = 1
							end
							if aFalling and bFalling then
								a.x = a.x + sgn * ox / 2
								b.x = b.x - sgn * ox / 2
								a.vx, b.vx = b.vx * REST, a.vx * REST
							elseif aFalling then
								a.x = a.x + sgn * ox
								a.vx = sgn * math.abs(a.vx) * REST
							else
								b.x = b.x - sgn * ox
								b.vx = -sgn * math.abs(b.vx) * REST
							end
						else
							local sgn = Util.sign(a.y - b.y)
							if sgn == 0 then
								sgn = 1
							end
							if aFalling and bFalling then
								a.y = a.y + sgn * oy / 2
								b.y = b.y - sgn * oy / 2
								a.vy, b.vy = b.vy * REST, a.vy * REST
							elseif aFalling then
								a.y = a.y + sgn * oy
								a.vy = sgn * math.abs(a.vy) * REST
							else
								b.y = b.y - sgn * oy
								b.vy = -sgn * math.abs(b.vy) * REST
							end
						end
						-- a knock sets them spinning a little differently
						if aFalling then
							a.spin = a.spin + Util.rand(-70, 70)
						end
						if bFalling then
							b.spin = b.spin + Util.rand(-70, 70)
						end
					end
				end
			end
		end

		for _, L in ipairs(pieces) do
			if L.el and t >= L.start then
				L.el.Position = UDim2.fromOffset(math.floor(L.x + 0.5), math.floor(L.y + 0.5))
				L.el.Rotation = L.rot
			end
		end

		if alive == 0 or t >= 12 then
			conn:Disconnect()
			for _, L in ipairs(pieces) do
				if L.el then
					L.el:Destroy()
					L.el = nil
				end
			end
		end
	end)

	return function()
		if conn.Connected then
			conn:Disconnect()
		end
		for _, L in ipairs(pieces) do
			if L.el then
				L.el:Destroy()
				L.el = nil
			end
		end
	end
end

return Chaos
