--!nonstrict
-- The eleven stage-4 challenge layouts, ported from the page one for one.
--
-- Every layout gets `ctx` (the arena and its helpers), the word, and the
-- buttons. A layout either places things once or installs `ctx.setSim(fn)`,
-- which then runs every frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Stroop.Config)
local Util = require(ReplicatedStorage.Stroop.Util)
local Ui = require(script.Parent.Parent.Ui)
local Motion = require(script.Parent.Parent.Motion)
local Physics2D = require(script.Parent.Physics2D)

local Layouts = {}

local PULSE_GAP = 1.4
local GLIDE_TIME = 1.15

-- ---------- shared placement ----------
local function place(b)
	b.el.Position = UDim2.fromOffset(math.floor(b.x + 0.5), math.floor(b.y + 0.5))
	b.el.Rotation = math.deg(b.a or 0)
end
Layouts.place = place

local function placeWord(w, x, y)
	w.x, w.y = x, y
	w.el.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
end
Layouts.placeWord = placeWord

-- Random non-overlapping centres across the viewport (buttons may cover the
-- logo and the word).
local function scatter(ctx, btns, avoid, gap)
	local W, H = ctx.width(), ctx.height()
	local m = 16
	local placed = {}
	for _, b in ipairs(btns) do
		local x, y, ok
		local k = 0
		repeat
			x = Util.rand(b.w / 2 + m, W - b.w / 2 - m)
			y = Util.rand(b.h / 2 + m, H - b.h / 2 - m)
			ok = true
			for _, p in ipairs(placed) do
				if math.abs(p.x - x) < (p.w + b.w) / 2 + gap
					and math.abs(p.y - y) < (p.h + b.h) / 2 + gap then
					ok = false
					break
				end
			end
			if ok and avoid and avoid(x, y, b) then
				ok = false
			end
			k = k + 1
		until ok or k >= 150
		b.x, b.y = x, y
		table.insert(placed, b)
	end
end
Layouts.scatter = scatter

-- ============================================================
-- grid - the stage 3 arrangement, scaled up and spread out 50%
-- ============================================================
function Layouts.grid(ctx, word, btns)
	local W, H = ctx.width(), ctx.height()
	local pb = ctx.protectedBottom()
	local bw, bh = 0, 0
	for _, b in ipairs(btns) do
		bw = math.max(bw, b.w)
		bh = math.max(bh, b.h)
	end
	for _, b in ipairs(btns) do
		b.el.Size = UDim2.fromOffset(math.ceil(bw), math.ceil(b.h))
		b.w, b.h = bw, bh
	end

	local cg, rg, gapWord = 72, 30, 64
	local rows = math.ceil(#btns / 3)
	local blockH = word.h + gapWord + bh * rows + rg * (rows - 1)
	local top = pb + math.max(0, (H - pb - blockH) / 2)
	placeWord(word, W / 2, top + word.h / 2)

	local x0 = W / 2 - (bw + cg)
	local y0 = top + word.h + gapWord + bh / 2
	for i, b in ipairs(btns) do
		b.x = x0 + ((i - 1) % 3) * (bw + cg)
		b.y = y0 + math.floor((i - 1) / 3) * (bh + rg)
		place(b)
	end
end

-- ALTERNATE reuses the grid; only its palette differs.
function Layouts.alternate(ctx, word, btns)
	Layouts.grid(ctx, word, btns)
end

-- ============================================================
-- orbit - direction flips every few seconds, eased so reversals stay fluid
-- ============================================================
function Layouts.orbit(ctx, word, btns)
	local W, H = ctx.width(), ctx.height()
	local pb = ctx.protectedBottom()
	local cx = W / 2
	local cy = math.max(H / 2 + 12, pb + word.h / 2 + 12)
	placeWord(word, cx, cy)

	local n = #btns
	local bw, bh = 0, 0
	for _, b in ipairs(btns) do
		bw = math.max(bw, b.w)
		bh = math.max(bh, b.h)
	end
	local r = math.max((bw + 22) / (2 * math.sin(math.pi / n)), word.w / 2 + bw / 2 + 26)
	local ry = math.max(word.h / 2 + bh / 2 + 20, math.min(r, cy - bh / 2 - 10, H - cy - bh / 2 - 12))
	local rx = math.min(math.max(r, ry), W / 2 - bw / 2 - 14)

	local SPEED = 0.85
	local theta = Util.rand(0, math.pi * 2)
	local dir = Util.chance(0.5) and 1 or -1
	local omega = dir * SPEED

	-- reversals are rare but unpredictable
	local function flip()
		dir = -dir
		ctx.after(Util.rand(3.2, 9), flip)
	end
	ctx.after(Util.rand(3.2, 9), flip)

	ctx.setSim(function(dt)
		omega = omega + (dir * SPEED - omega) * math.min(1, dt * 11)
		theta = theta + omega * dt
		for i, b in ipairs(btns) do
			local t = theta + (i - 1) * math.pi * 2 / n
			b.x = cx + rx * math.cos(t)
			b.y = cy + ry * math.sin(t)
			place(b)
		end
	end)
end

-- ============================================================
-- pulse - every button jumps at once to fresh non-overlapping spots
-- ============================================================
function Layouts.pulse(ctx, word, btns)
	local W, H = ctx.width(), ctx.height()
	local pb = ctx.protectedBottom()
	placeWord(word, W / 2, math.max(H / 2 + 12, pb + word.h / 2 + 12))

	local function jump()
		scatter(ctx, btns, nil, 18)
		for _, b in ipairs(btns) do
			b.tx, b.ty = b.x, b.y
		end
	end
	jump()
	for _, b in ipairs(btns) do
		b.cx, b.cy = b.tx, b.ty
		b.fromX, b.fromY = b.tx, b.ty
		b.travel = GLIDE_TIME
		b.x, b.y = b.tx, b.ty
		place(b)
	end

	local function loop()
		if not ctx.isActive() then
			return
		end
		for _, b in ipairs(btns) do
			b.fromX, b.fromY = b.cx, b.cy
			b.travel = 0
		end
		jump()
		ctx.after(PULSE_GAP, loop)
	end
	ctx.after(PULSE_GAP, loop)

	-- the CSS `GLIDE` transition, overshoot and all
	ctx.setSim(function(dt)
		for _, b in ipairs(btns) do
			b.travel = math.min(GLIDE_TIME, (b.travel or GLIDE_TIME) + dt)
			local p = Motion.ease.glide(b.travel / GLIDE_TIME)
			b.cx = Util.lerp(b.fromX, b.tx, p)
			b.cy = Util.lerp(b.fromY, b.ty, p)
			b.x, b.y = b.cx, b.cy
			place(b)
		end
	end)
end

-- ============================================================
-- fall - real rigid bodies: gravity, tumbling, stacking on the word
-- ============================================================
function Layouts.fall(ctx, word, btns)
	local W, H = ctx.width(), ctx.height()
	local pb = ctx.protectedBottom()
	placeWord(word, W / 2, math.max(H / 2 + 12, pb + word.h / 2 + 12))

	local world = Physics2D.World(1150)
	world:addBox(W / 2, H + 60, W + 800, 120, { static = true, friction = 0.7 })
	world:addBox(-60, H / 2, 120, H + 3000, { static = true })
	world:addBox(W + 60, H / 2, 120, H + 3000, { static = true })
	world:addBox(word.x, word.y, word.w, word.h * 0.78, { static = true, friction = 0.6 })

	local placed = {}
	for _, b in ipairs(btns) do
		local R = math.sqrt(b.w * b.w + b.h * b.h) / 2
		local x, y
		local k = 0
		repeat
			x = Util.rand(b.w / 2 + 16, W - b.w / 2 - 16)
			y = -Util.rand(R * 0.6, R * 0.6 + H * 0.42)
			local clear = true
			for _, p in ipairs(placed) do
				if math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2) < p.R + R + 6 then
					clear = false
					break
				end
			end
			k = k + 1
		until clear or k >= 150
		b.x, b.y, b.R = x, y, R
		table.insert(placed, { x = x, y = y, R = R })

		b.body = world:addBox(x, y, b.w, b.h, {
			restitution = 0.3,
			friction = 0.3,
			frictionAir = 0.006,
			density = 0.0016,
			angle = Util.rand(-0.45, 0.45),
			vx = Util.rand(-84, 84),
			vy = Util.rand(60, 210),
			angularVelocity = Util.rand(-2.1, 2.1),
		})
		place(b)
	end

	ctx.onCleanup(function()
		for _, b in ipairs(btns) do
			b.body = nil
		end
	end)

	local STEP = 1 / 60
	local acc = 0
	ctx.setSim(function(dt)
		acc = acc + dt
		local n = 0
		while acc >= STEP and n < 4 do
			world:step(STEP)
			acc = acc - STEP
			n = n + 1
		end
		for _, b in ipairs(btns) do
			if b.body then
				b.x, b.y, b.a = b.body.x, b.body.y, b.body.angle
				place(b)
			end
		end
	end)
end

-- ============================================================
-- drift - each button steers along its own squiggle, never overlapping
-- ============================================================
function Layouts.drift(ctx, word, btns)
	local W, H = ctx.width(), ctx.height()
	local pb = ctx.protectedBottom()
	placeWord(word, W / 2, math.max(H / 2 + 12, pb + word.h / 2 + 12))
	scatter(ctx, btns, nil, 24)

	for _, b in ipairs(btns) do
		b.th0 = Util.rand(0, math.pi * 2)
		b.sp = Util.rand(40, 66)
		b.A1, b.f1, b.p1 = Util.rand(0.55, 1.15), Util.rand(0.55, 1.25), Util.rand(0, 6.28)
		b.A2, b.f2, b.p2 = Util.rand(0.15, 0.45), Util.rand(1.4, 2.6), Util.rand(0, 6.28)
		place(b)
	end

	local t = 0
	local function head(b)
		return b.th0 + b.A1 * math.sin(b.f1 * t + b.p1) + b.A2 * math.sin(b.f2 * t + b.p2)
	end
	local function flipX(b)
		b.th0 = b.th0 + math.pi - 2 * head(b)
	end
	local function flipY(b)
		b.th0 = b.th0 - 2 * head(b)
	end

	ctx.setSim(function(dt)
		t = t + dt
		local w, h, m = ctx.width(), ctx.height(), 10
		for _, b in ipairs(btns) do
			local hd = head(b)
			b.x = b.x + math.cos(hd) * b.sp * dt
			b.y = b.y + math.sin(hd) * b.sp * dt
			if b.x - b.w / 2 < m then
				b.x = m + b.w / 2
				if math.cos(hd) < 0 then
					flipX(b)
				end
			elseif b.x + b.w / 2 > w - m then
				b.x = w - m - b.w / 2
				if math.cos(hd) > 0 then
					flipX(b)
				end
			end
			if b.y - b.h / 2 < m then
				b.y = m + b.h / 2
				if math.sin(hd) < 0 then
					flipY(b)
				end
			elseif b.y + b.h / 2 > h - m then
				b.y = h - m - b.h / 2
				if math.sin(hd) > 0 then
					flipY(b)
				end
			end
		end

		for i = 1, #btns do
			for j = i + 1, #btns do
				local a, c = btns[i], btns[j]
				local ox = (a.w + c.w) / 2 + 10 - math.abs(a.x - c.x)
				local oy = (a.h + c.h) / 2 + 10 - math.abs(a.y - c.y)
				if ox > 0 and oy > 0 then
					if ox < oy then
						local s = Util.sign(a.x - c.x)
						if s == 0 then
							s = 1
						end
						a.x = a.x + s * ox / 2
						c.x = c.x - s * ox / 2
						if Util.sign(math.cos(head(a))) == -s then
							flipX(a)
						end
						if Util.sign(math.cos(head(c))) == s then
							flipX(c)
						end
					else
						local s = Util.sign(a.y - c.y)
						if s == 0 then
							s = 1
						end
						a.y = a.y + s * oy / 2
						c.y = c.y - s * oy / 2
						if Util.sign(math.sin(head(a))) == -s then
							flipY(a)
						end
						if Util.sign(math.sin(head(c))) == s then
							flipY(c)
						end
					end
				end
			end
		end

		for _, b in ipairs(btns) do
			place(b)
		end
	end)
end

-- ============================================================
-- dvd - circles on fixed diagonals, bouncing off walls, each other, the word
-- ============================================================
function Layouts.dvd(ctx, word, btns)
	local W, H = ctx.width(), ctx.height()
	local pb = ctx.protectedBottom()
	local cy = math.min(math.max(H / 2, pb + word.h / 2 + 12), H - word.h / 2 - 12)
	placeWord(word, W / 2, cy)

	local wr = {
		l = word.x - word.w / 2,
		r = word.x + word.w / 2,
		t = word.y - word.h / 2,
		b = word.y + word.h / 2,
	}
	local function rectDist(px, py)
		local cx = math.max(wr.l, math.min(px, wr.r))
		local cy2 = math.max(wr.t, math.min(py, wr.b))
		return math.sqrt((px - cx) ^ 2 + (py - cy2) ^ 2)
	end

	scatter(ctx, btns, function(px, py, b)
		return rectDist(px, py) < b.r + 14
	end, 12)

	local V = 155
	for _, b in ipairs(btns) do
		b.vx = (Util.chance(0.5) and -1 or 1) * V
		b.vy = (Util.chance(0.5) and -1 or 1) * V
		place(b)
	end

	ctx.setSim(function(dt)
		local w, h = ctx.width(), ctx.height()
		for _, b in ipairs(btns) do
			b.x = b.x + b.vx * dt
			b.y = b.y + b.vy * dt
			if b.x - b.r < 0 then
				b.x = b.r
				b.vx = math.abs(b.vx)
			elseif b.x + b.r > w then
				b.x = w - b.r
				b.vx = -math.abs(b.vx)
			end
			if b.y - b.r < 0 then
				b.y = b.r
				b.vy = math.abs(b.vy)
			elseif b.y + b.r > h then
				b.y = h - b.r
				b.vy = -math.abs(b.vy)
			end

			local px = math.max(wr.l, math.min(b.x, wr.r))
			local py = math.max(wr.t, math.min(b.y, wr.b))
			local dx, dy = b.x - px, b.y - py
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist < b.r then
				if dist < 0.001 then
					dx = ((b.x - wr.l) < (wr.r - b.x)) and -1 or 1
					dy = 0
					b.x = (dx < 0) and (wr.l - b.r) or (wr.r + b.r)
				else
					b.x = px + dx / dist * b.r
					b.y = py + dy / dist * b.r
				end
				if math.abs(dx) >= math.abs(dy) then
					b.vx = Util.sign(dx) * math.abs(b.vx)
				else
					b.vy = Util.sign(dy) * math.abs(b.vy)
				end
			end
		end

		for i = 1, #btns do
			for j = i + 1, #btns do
				local a, c = btns[i], btns[j]
				local dx, dy = a.x - c.x, a.y - c.y
				local minD = a.r + c.r
				local dist = math.max(0.001, math.sqrt(dx * dx + dy * dy))
				if dist < minD then
					local nx, ny = dx / dist, dy / dist
					local push = (minD - dist) / 2
					a.x = a.x + nx * push
					a.y = a.y + ny * push
					c.x = c.x - nx * push
					c.y = c.y - ny * push
					if math.abs(nx) >= math.abs(ny) then
						local s = Util.sign(nx)
						if s == 0 then
							s = 1
						end
						a.vx = s * math.abs(a.vx)
						c.vx = -s * math.abs(c.vx)
					else
						local s = Util.sign(ny)
						if s == 0 then
							s = 1
						end
						a.vy = s * math.abs(a.vy)
						c.vy = -s * math.abs(c.vy)
					end
				end
			end
		end

		for _, b in ipairs(btns) do
			place(b)
		end
	end)
end

-- ============================================================
-- decoy - static buttons scattered anywhere, kept clear of the word
-- ============================================================
function Layouts.decoy(ctx, word, btns)
	local W, H = ctx.width(), ctx.height()
	local pb = ctx.protectedBottom()
	placeWord(word, W / 2, math.max(H / 2 + 12, pb + word.h / 2 + 12))
	scatter(ctx, btns, function(x, y, b)
		return math.abs(x - word.x) < (word.w + b.w) / 2 + 20
			and math.abs(y - word.y) < (word.h + b.h) / 2 + 20
	end, 16)
	for _, b in ipairs(btns) do
		place(b)
	end
end

-- ============================================================
-- blink - a random third of the buttons vanish at a time, leaving an outline
-- ============================================================
function Layouts.blink(ctx, word, btns)
	Layouts.grid(ctx, word, btns)
	local groupSize = math.max(1, math.floor(#btns / 3 + 0.5))
	local prev = {}

	local function cycle()
		for _, b in ipairs(btns) do
			ctx.setGhost(b, false)
		end
		local pool = Util.filter(btns, function(b)
			return not Util.contains(prev, b)
		end)
		local group = {}
		local shuffled = Util.shuffle(pool)
		for i = 1, math.min(groupSize, #shuffled) do
			table.insert(group, shuffled[i])
			ctx.setGhost(shuffled[i], true)
		end
		prev = group
	end

	cycle() -- the first blink fires right away
	local function loop()
		if not ctx.isActive() then
			return
		end
		cycle()
		ctx.after(0.8, loop)
	end
	ctx.after(0.8, loop)
end

-- ============================================================
-- spotlight - pitch black; the cursor is a torch and the buttons shy away
-- ============================================================
function Layouts.spotlight(ctx, word, btns)
	local W, H = ctx.width(), ctx.height()
	local pb = ctx.protectedBottom()
	local R = Config.SPOT_RADIUS
	placeWord(word, W / 2, math.max(H / 2 + 12, pb + word.h / 2 + 12))
	scatter(ctx, btns, function(x, y, b)
		return math.abs(x - word.x) < (word.w + b.w) / 2 + 24
			and math.abs(y - word.y) < (word.h + b.h) / 2 + 24
	end, 18)
	for _, b in ipairs(btns) do
		b.vx, b.vy = 0, 0
		place(b)
	end

	--[[
		The darkness sits above everything in the layer. A CSS radial mask isn't
		available, so this is built from two pieces:

		  - concentric ring strokes for the soft fade from the clear centre out
		    to the edge of the circle.
		  - four giant panels, one per quadrant around the cursor, each anchored
		    so its one *near* corner sits exactly on the cursor and rounded with
		    a UICorner equal to the spotlight's radius - which carves a precise
		    quarter-circle out of that one corner. A rounded corner is real
		    geometry, not a transparency trick, so the four panels together are
		    solid black everywhere outside the circle with no seam and no
		    leftover corner - unlike drawing the circle itself and papering
		    around it with rectangles, which always leaves the diagonal wedges
		    between the circle and its own bounding square uncovered.
	]]
	local dark = Ui.new("Frame", {
		Name = "spotlight",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 90,
		Parent = ctx.arena,
	})

	-- alpha at 0% / 32% / 62% / 100% of the radius
	local function alphaAt(k)
		if k <= 0.32 then
			return Util.lerp(0, 0.18, k / 0.32)
		elseif k <= 0.62 then
			return Util.lerp(0.18, 0.62, (k - 0.32) / 0.30)
		end
		return Util.lerp(0.62, 1, math.min(1, (k - 0.62) / 0.38))
	end

	local RINGS = 28 -- finer bands than before, for a smoother fade
	local rings = {}
	for i = 1, RINGS do
		local r0 = R * (i - 1) / RINGS
		local r1 = R * i / RINGS
		local ring = Ui.new("Frame", {
			Name = "ring" .. i,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(math.ceil(r0 * 2), math.ceil(r0 * 2)),
			ZIndex = 90 + i,
			Parent = dark,
		})
		Ui.corner(ring, math.ceil(r0))
		local stroke = Ui.stroke(ring, math.max(1, r1 - r0), Color3.new(0, 0, 0))
		stroke.Transparency = 1 - alphaAt((r0 + r1) / (2 * R))
		table.insert(rings, ring)
	end

	-- BIG is comfortably past any real viewport, so each panel's other three
	-- corners (also rounded, since UICorner rounds all four alike) always land
	-- off-screen and never show - only the corner anchored on the cursor does.
	local BIG = 4000
	local PANEL_ANCHORS = {
		Vector2.new(0, 0), -- covers right + down
		Vector2.new(1, 0), -- covers left + down
		Vector2.new(0, 1), -- covers right + up
		Vector2.new(1, 1), -- covers left + up
	}
	local panels = {}
	for _, anchor in ipairs(PANEL_ANCHORS) do
		local panel = Ui.new("Frame", {
			Name = "quadrant",
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.new(0, 0, 0),
			AnchorPoint = anchor,
			Size = UDim2.fromOffset(BIG, BIG),
			ZIndex = 90 + RINGS + 1,
			Parent = dark,
		})
		Ui.corner(panel, math.ceil(R))
		table.insert(panels, panel)
	end

	ctx.setSim(function(dt)
		local w, h = ctx.width(), ctx.height()
		local mx, my = ctx.pointer()
		mx = math.clamp(mx, 0, w)
		my = math.clamp(my, 0, h)
		local pos = UDim2.fromOffset(math.floor(mx + 0.5), math.floor(my + 0.5))
		for _, ring in ipairs(rings) do
			ring.Position = pos
		end
		for _, panel in ipairs(panels) do
			panel.Position = pos
		end

		for _, b in ipairs(btns) do
			local dx, dy = b.x - mx, b.y - my
			local dist = math.max(0.001, math.sqrt(dx * dx + dy * dy))
			if dist < 240 then -- a slow shove away; they keep the new spot
				local push = (1 - dist / 240) * 180
				b.vx = (b.vx or 0) + dx / dist * push * dt
				b.vy = (b.vy or 0) + dy / dist * push * dt
			end
			b.vx = (b.vx or 0) * (0.14 ^ dt) -- heavy drag, so they glide not dart
			b.vy = (b.vy or 0) * (0.14 ^ dt)
			b.x = b.x + b.vx * dt
			b.y = b.y + b.vy * dt
			if b.x < b.w / 2 + 6 then
				b.x = b.w / 2 + 6
				b.vx = 0
			end
			if b.x > w - b.w / 2 - 6 then
				b.x = w - b.w / 2 - 6
				b.vx = 0
			end
			if b.y < b.h / 2 + 6 then
				b.y = b.h / 2 + 6
				b.vy = 0
			end
			if b.y > h - b.h / 2 - 6 then
				b.y = h - b.h / 2 - 6
				b.vy = 0
			end
			place(b)
		end
	end)
end

-- ============================================================
-- ribbon - one continuous tilted row, wrapped with portal copies
-- ============================================================
function Layouts.ribbon(ctx, word, btns)
	local W, H = ctx.width(), ctx.height()
	local pb = ctx.protectedBottom()
	placeWord(word, W / 2, math.max(H / 2 + 12, pb + word.h / 2 + 12))

	local bw, bh = 0, 0
	for _, b in ipairs(btns) do
		bw = math.max(bw, b.w)
		bh = math.max(bh, b.h)
	end
	for _, b in ipairs(btns) do
		b.w, b.h = bw, bh
		b.el.Size = UDim2.fromOffset(math.ceil(bw), math.ceil(bh))
	end

	local gap = 46
	local hDir = Util.chance(0.5) and 1 or -1
	local vDir = Util.chance(0.5) and 1 or -1
	local hSpeed, vSpeed = Util.rand(220, 340), Util.rand(70, 110)
	local theta = Util.rand(-20, 20) * math.pi / 180
	local cosT, sinT = math.cos(theta), math.sin(theta)

	-- a copy at every neighbouring wrap, so whichever edge a button straddles
	-- the matching half is already drawn there
	local OFFSETS = {
		{ -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
		{ -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 },
	}
	for _, b in ipairs(btns) do
		b.a = theta -- rotate the button itself
		b.ghosts = {}
		for _ = 1, #OFFSETS do
			local g = ctx.cloneButton(b)
			table.insert(b.ghosts, g)
		end
	end

	local function wrap(v, m)
		return ((v % m) + m) % m
	end

	local hOff = Util.rand(0, bw + gap)
	local y0 = Util.rand(0, H)
	for i, b in ipairs(btns) do
		b.i = i - 1
	end

	ctx.setSim(function(dt)
		local w, h = ctx.width(), ctx.height()
		-- wrap over the exact viewport, so a copy sits flush against the edge
		-- the original is leaving
		hOff = hOff + hDir * hSpeed * dt
		y0 = y0 + vDir * vSpeed * dt
		for _, b in ipairs(btns) do
			local along = b.i * (bw + gap)
			local bx = wrap(hOff + along * cosT, w)
			local by = wrap(y0 + along * sinT, h)
			b.x, b.y = bx, by
			place(b)
			for k, g in ipairs(b.ghosts) do
				local ox, oy = OFFSETS[k][1], OFFSETS[k][2]
				ctx.syncGhost(g, b)
				g.Position = UDim2.fromOffset(
					math.floor(bx + ox * w + 0.5),
					math.floor(by + oy * h + 0.5)
				)
				g.Rotation = math.deg(theta)
			end
		end
	end)
end

return Layouts
