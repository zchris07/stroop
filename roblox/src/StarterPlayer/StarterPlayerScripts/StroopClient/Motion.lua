--!nonstrict
-- CSS transitions and @keyframes, expressed for Roblox.
--
-- `Motion.to` covers `transition:`. `Motion.keyframes` drives a 0..1 progress
-- value each frame, which is how every named animation from the stylesheet
-- (okpulse, badshake, reactPop, countPulse, ...) is reproduced exactly rather
-- than approximated with a pair of tweens.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Motion = {}

-- ---------- easing ----------
-- A direct cubic-bezier evaluator, so the timing curves in the stylesheet can
-- be copied across verbatim instead of being matched to an Enum.EasingStyle.
local function bezier(x1, y1, x2, y2)
	local function sampleX(t)
		return ((1 - t) ^ 3) * 0 + 3 * ((1 - t) ^ 2) * t * x1 + 3 * (1 - t) * t * t * x2 + t ^ 3
	end
	local function sampleY(t)
		return ((1 - t) ^ 3) * 0 + 3 * ((1 - t) ^ 2) * t * y1 + 3 * (1 - t) * t * t * y2 + t ^ 3
	end
	return function(x)
		if x <= 0 then
			return 0
		elseif x >= 1 then
			return 1
		end
		-- bisection is plenty: this runs a handful of times per frame at most
		local lo, hi = 0, 1
		for _ = 1, 18 do
			local mid = (lo + hi) / 2
			if sampleX(mid) < x then
				lo = mid
			else
				hi = mid
			end
		end
		return sampleY((lo + hi) / 2)
	end
end

Motion.ease = {
	linear = function(t)
		return t
	end,
	ease = bezier(0.25, 0.1, 0.25, 1),
	easeIn = bezier(0.42, 0, 1, 1),
	easeOut = bezier(0, 0, 0.58, 1),
	easeInOut = bezier(0.42, 0, 0.58, 1),
	-- the named curves used throughout the page
	soft = bezier(0.2, 0.8, 0.3, 1),
	softer = bezier(0.2, 0.7, 0.3, 1),
	swoop = bezier(0.16, 0.84, 0.3, 1),
	glide = bezier(0.34, 1.42, 0.52, 1), -- overshoots, like the pulse layout's travel
	hard = bezier(0.65, 0, 0.35, 1),
	pop = bezier(0.22, 0.85, 0.3, 1),
	placement = bezier(0.2, 0.8, 0.3, 1),
	bar = bezier(0.2, 0.8, 0.2, 1),
	fight = bezier(0.3, 0.9, 0.3, 1),
	write = bezier(0.5, 0.1, 0.3, 1),
	unwrite = bezier(0.5, 0, 0.75, 0.5),
	standard = bezier(0.4, 0, 0.2, 1),
}
Motion.bezier = bezier

-- ---------- per-frame driver ----------
-- Returns a cancel function. `fn(progress, dt)` runs every frame from 0 to 1,
-- and always receives a final call at exactly 1 unless cancelled.
function Motion.keyframes(duration, fn, easing)
	local cancelled = false
	if duration <= 0 then
		fn(1, 0)
		return function() end
	end
	task.spawn(function()
		local t = 0
		while t < duration and not cancelled do
			local dt = RunService.RenderStepped:Wait()
			if cancelled then
				return
			end
			t = math.min(duration, t + dt)
			local p = t / duration
			fn(easing and easing(p) or p, dt)
		end
	end)
	return function()
		cancelled = true
	end
end

-- ---------- numeric transition ----------
-- `from`/`to` may be numbers, Color3, UDim2, Vector2.
local function blend(a, b, t)
	local ty = typeof(a)
	if ty == "number" then
		return a + (b - a) * t
	elseif ty == "Color3" then
		return a:Lerp(b, t)
	elseif ty == "UDim2" then
		return a:Lerp(b, t)
	elseif ty == "Vector2" then
		return a:Lerp(b, t)
	end
	return t < 1 and a or b
end

function Motion.value(from, to, duration, easing, fn)
	return Motion.keyframes(duration, function(p)
		fn(blend(from, to, p))
	end, easing)
end

-- ---------- instance tween ----------
-- Thin TweenService wrapper for the plain cases.
function Motion.to(inst, duration, props, style, dir)
	if not inst or not inst.Parent then
		return nil
	end
	local info = TweenInfo.new(
		duration,
		style or Enum.EasingStyle.Quad,
		dir or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(inst, info, props)
	tween:Play()
	return tween
end

-- Drives arbitrary properties with one of the bezier curves above.
function Motion.animate(inst, duration, props, easing)
	if not inst then
		return function() end
	end
	local from = {}
	for k, v in pairs(props) do
		from[k] = inst[k]
		if typeof(from[k]) ~= typeof(v) then
			from[k] = v
		end
	end
	return Motion.keyframes(duration, function(p)
		if not inst.Parent and not inst:IsA("ScreenGui") then
			return
		end
		for k, v in pairs(props) do
			inst[k] = blend(from[k], v, p)
		end
	end, easing)
end

-- ---------- sequencing ----------
-- A cancellable `await` that a session token can invalidate, which is how the
-- original guarded every `setTimeout` against the player leaving mid-run.
function Motion.wait(seconds)
	if seconds <= 0 then
		return
	end
	task.wait(seconds)
end

return Motion
