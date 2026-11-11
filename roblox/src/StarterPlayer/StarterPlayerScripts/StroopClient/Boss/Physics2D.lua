--!nonstrict
--[[
	A small 2D rigid-body solver - the stand-in for Matter.js, which the web
	build pulled from a CDN to run the FALL challenge.

	Boxes only, which is all that challenge needs: the nine buttons tumble under
	gravity, bounce off the walls and the floor, land on the word and stack on
	each other. Oriented boxes are separated with SAT, the contact manifold comes
	from reference/incident face clipping, and contacts are resolved with
	sequential impulses plus Baumgarte position correction - the same shape of
	solver Matter.js uses, so the motion reads the same.

	Screen coordinates: +y is down, so gravity is positive.
]]

local Physics2D = {}

local Body = {}
Body.__index = Body

local World = {}
World.__index = World

-- ---------- body ----------
local function newBody(x, y, w, h, opts)
	opts = opts or {}
	local self = setmetatable({}, Body)
	self.x, self.y = x, y
	self.hw, self.hh = w / 2, h / 2
	self.angle = opts.angle or 0
	self.vx, self.vy = opts.vx or 0, opts.vy or 0
	self.w = opts.angularVelocity or 0
	self.static = opts.static or false
	self.restitution = opts.restitution or 0.3
	self.friction = opts.friction or 0.3
	self.frictionAir = opts.frictionAir or 0.006

	if self.static then
		self.invMass, self.invInertia = 0, 0
	else
		local density = opts.density or 0.0016
		local mass = math.max(0.0001, density * w * h)
		-- a rectangle's moment of inertia about its centre
		local inertia = mass * (w * w + h * h) / 12
		self.invMass = 1 / mass
		self.invInertia = 1 / math.max(0.0001, inertia)
	end
	return self
end

function Body:corners()
	local c, s = math.cos(self.angle), math.sin(self.angle)
	local hw, hh = self.hw, self.hh
	local ax, ay = c * hw, s * hw
	local bx, by = -s * hh, c * hh
	return {
		{ x = self.x - ax - bx, y = self.y - ay - by },
		{ x = self.x + ax - bx, y = self.y + ay - by },
		{ x = self.x + ax + bx, y = self.y + ay + by },
		{ x = self.x - ax + bx, y = self.y - ay + by },
	}
end

-- Outward normals, indexed so that normals[i] belongs to the edge running from
-- corners[i] to corners[i + 1]. The face-clipping below depends on that pairing.
function Body:normals()
	local c, s = math.cos(self.angle), math.sin(self.angle)
	return {
		{ x = s, y = -c },  -- edge 1 -> 2 lies on the local -y side
		{ x = c, y = s },   -- edge 2 -> 3, local +x
		{ x = -s, y = c },  -- edge 3 -> 4, local +y
		{ x = -c, y = -s }, -- edge 4 -> 1, local -x
	}
end

function Body:radius()
	return math.sqrt(self.hw * self.hw + self.hh * self.hh)
end

-- ---------- SAT ----------
local function project(corners, ax, ay)
	local lo, hi = math.huge, -math.huge
	for _, p in ipairs(corners) do
		local d = p.x * ax + p.y * ay
		if d < lo then
			lo = d
		end
		if d > hi then
			hi = d
		end
	end
	return lo, hi
end

-- Returns depth, normal (pointing from a toward b), and which body owns the
-- reference face; nil when the boxes are apart.
local function overlap(a, b)
	local ca, cb = a:corners(), b:corners()
	local best, bestAxis, bestOwner = math.huge, nil, nil

	local function testAxes(normals, owner)
		for _, n in ipairs(normals) do
			local loA, hiA = project(ca, n.x, n.y)
			local loB, hiB = project(cb, n.x, n.y)
			if hiA < loB or hiB < loA then
				return false
			end
			local depth = math.min(hiA - loB, hiB - loA)
			if depth < best then
				best = depth
				bestAxis = n
				bestOwner = owner
			end
		end
		return true
	end

	if not testAxes(a:normals(), "a") then
		return nil
	end
	if not testAxes(b:normals(), "b") then
		return nil
	end
	if not bestAxis then
		return nil
	end

	-- orient the normal so it always points from a to b
	local dx, dy = b.x - a.x, b.y - a.y
	local nx, ny = bestAxis.x, bestAxis.y
	if dx * nx + dy * ny < 0 then
		nx, ny = -nx, -ny
	end
	return best, nx, ny, bestOwner, ca, cb
end

-- The face of `body` most anti-parallel to the contact normal.
local function incidentFace(body, nx, ny)
	local normals = body:normals()
	local corners = body:corners()
	local bestIdx, bestDot = 1, math.huge
	for i, n in ipairs(normals) do
		local d = n.x * nx + n.y * ny
		if d < bestDot then
			bestDot = d
			bestIdx = i
		end
	end
	local a = corners[bestIdx]
	local b = corners[bestIdx % 4 + 1]
	return a, b
end

local function referenceFace(body, nx, ny)
	local normals = body:normals()
	local corners = body:corners()
	local bestIdx, bestDot = 1, -math.huge
	for i, n in ipairs(normals) do
		local d = n.x * nx + n.y * ny
		if d > bestDot then
			bestDot = d
			bestIdx = i
		end
	end
	local a = corners[bestIdx]
	local b = corners[bestIdx % 4 + 1]
	return a, b, normals[bestIdx]
end

-- Sutherland-Hodgman clip of a segment against a half-plane.
local function clipSegment(p1, p2, nx, ny, offset)
	local d1 = p1.x * nx + p1.y * ny - offset
	local d2 = p2.x * nx + p2.y * ny - offset
	local out = {}
	if d1 <= 0 then
		table.insert(out, p1)
	end
	if d2 <= 0 then
		table.insert(out, p2)
	end
	if d1 * d2 < 0 then
		local t = d1 / (d1 - d2)
		table.insert(out, {
			x = p1.x + t * (p2.x - p1.x),
			y = p1.y + t * (p2.y - p1.y),
		})
	end
	return out
end

local function manifold(a, b)
	local depth, nx, ny, owner = overlap(a, b)
	if not depth then
		return nil
	end

	local refBody = (owner == "a") and a or b
	local incBody = (owner == "a") and b or a
	local rn_x, rn_y = nx, ny
	if owner == "b" then
		rn_x, rn_y = -nx, -ny
	end

	local r1, r2, refNormal = referenceFace(refBody, rn_x, rn_y)
	local i1, i2 = incidentFace(incBody, rn_x, rn_y)

	-- clip the incident face to the reference face's side planes
	local tx, ty = r2.x - r1.x, r2.y - r1.y
	local len = math.sqrt(tx * tx + ty * ty)
	if len < 1e-6 then
		return nil
	end
	tx, ty = tx / len, ty / len

	local pts = clipSegment(i1, i2, -tx, -ty, -(r1.x * tx + r1.y * ty))
	if #pts < 2 then
		pts = { i1, i2 }
	else
		pts = clipSegment(pts[1], pts[2], tx, ty, r2.x * tx + r2.y * ty)
		if #pts < 1 then
			pts = { i1, i2 }
		end
	end

	-- keep only points actually behind the reference face
	local refOffset = r1.x * refNormal.x + r1.y * refNormal.y
	local contacts = {}
	for _, p in ipairs(pts) do
		local sep = p.x * refNormal.x + p.y * refNormal.y - refOffset
		if sep <= 0.01 then
			table.insert(contacts, { x = p.x, y = p.y, depth = math.max(0, -sep) })
		end
	end
	if #contacts == 0 then
		return nil
	end

	return { nx = nx, ny = ny, depth = depth, points = contacts }
end

-- ---------- world ----------
function Physics2D.World(gravity)
	local self = setmetatable({}, World)
	self.gravity = gravity or 1150
	self.bodies = {}
	self.iterations = 8
	return self
end

function World:addBox(x, y, w, h, opts)
	local body = newBody(x, y, w, h, opts)
	table.insert(self.bodies, body)
	return body
end

function World:remove(body)
	for i, b in ipairs(self.bodies) do
		if b == body then
			table.remove(self.bodies, i)
			return
		end
	end
end

local function applyImpulse(body, px, py, rx, ry)
	if body.static then
		return
	end
	body.vx = body.vx + px * body.invMass
	body.vy = body.vy + py * body.invMass
	body.w = body.w + (rx * py - ry * px) * body.invInertia
end

local SLOP = 0.35
local BAUMGARTE = 0.28

function World:step(dt)
	if dt <= 0 then
		return
	end
	dt = math.min(dt, 1 / 30)

	-- integrate velocities
	for _, b in ipairs(self.bodies) do
		if not b.static then
			b.vy = b.vy + self.gravity * dt
			local damp = (1 - b.frictionAir) ^ (dt * 60)
			b.vx = b.vx * damp
			b.vy = b.vy * damp
			b.w = b.w * damp
		end
	end

	-- broad phase + manifolds
	local contacts = {}
	local n = #self.bodies
	for i = 1, n do
		for j = i + 1, n do
			local a, b = self.bodies[i], self.bodies[j]
			if not (a.static and b.static) then
				local dx, dy = b.x - a.x, b.y - a.y
				local reach = a:radius() + b:radius()
				if dx * dx + dy * dy <= reach * reach then
					local m = manifold(a, b)
					if m then
						m.a, m.b = a, b
						table.insert(contacts, m)
					end
				end
			end
		end
	end

	-- sequential impulses
	for _ = 1, self.iterations do
		for _, c in ipairs(contacts) do
			local a, b = c.a, c.b
			local e = math.min(a.restitution, b.restitution)
			local mu = math.sqrt(a.friction * b.friction)
			for _, p in ipairs(c.points) do
				local rax, ray = p.x - a.x, p.y - a.y
				local rbx, rby = p.x - b.x, p.y - b.y

				local vax = a.vx - a.w * ray
				local vay = a.vy + a.w * rax
				local vbx = b.vx - b.w * rby
				local vby = b.vy + b.w * rbx
				local rvx, rvy = vbx - vax, vby - vay

				local vn = rvx * c.nx + rvy * c.ny
				if vn < 0 then
					local raCrossN = rax * c.ny - ray * c.nx
					local rbCrossN = rbx * c.ny - rby * c.nx
					local inv = a.invMass + b.invMass
						+ raCrossN * raCrossN * a.invInertia
						+ rbCrossN * rbCrossN * b.invInertia
					if inv > 1e-9 then
						-- low-speed contacts lose their bounce, so stacks settle
						local bounce = (math.abs(vn) < 60) and 0 or e
						local jn = -(1 + bounce) * vn / inv
						applyImpulse(a, -jn * c.nx, -jn * c.ny, rax, ray)
						applyImpulse(b, jn * c.nx, jn * c.ny, rbx, rby)

						-- Coulomb friction along the tangent
						local tx, ty = -c.ny, c.nx
						vax = a.vx - a.w * ray
						vay = a.vy + a.w * rax
						vbx = b.vx - b.w * rby
						vby = b.vy + b.w * rbx
						local vt = (vbx - vax) * tx + (vby - vay) * ty
						local raCrossT = rax * ty - ray * tx
						local rbCrossT = rbx * ty - rby * tx
						local invT = a.invMass + b.invMass
							+ raCrossT * raCrossT * a.invInertia
							+ rbCrossT * rbCrossT * b.invInertia
						if invT > 1e-9 then
							local jt = math.clamp(-vt / invT, -mu * jn, mu * jn)
							applyImpulse(a, -jt * tx, -jt * ty, rax, ray)
							applyImpulse(b, jt * tx, jt * ty, rbx, rby)
						end
					end
				end
			end
		end
	end

	-- integrate positions
	for _, b in ipairs(self.bodies) do
		if not b.static then
			b.x = b.x + b.vx * dt
			b.y = b.y + b.vy * dt
			b.angle = b.angle + b.w * dt
		end
	end

	-- positional correction, so resting stacks do not sink
	for _, c in ipairs(contacts) do
		local a, b = c.a, c.b
		local inv = a.invMass + b.invMass
		if inv > 1e-9 then
			local correction = math.max(c.depth - SLOP, 0) / inv * BAUMGARTE
			if not a.static then
				a.x = a.x - c.nx * correction * a.invMass
				a.y = a.y - c.ny * correction * a.invMass
			end
			if not b.static then
				b.x = b.x + c.nx * correction * b.invMass
				b.y = b.y + c.ny * correction * b.invMass
			end
		end
	end
end

return Physics2D
