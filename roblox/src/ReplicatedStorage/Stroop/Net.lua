--!nonstrict
-- Creates (server) or waits for (client) every remote the game uses. Replaces
-- the Firebase document adapter from the web build: instead of polling
-- documents, the server pushes state the moment it changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"LobbyState",    -- server -> client: roster + meta for my lobby
	"RoundStart",    -- server -> client: the next challenge
	"ScoreUpdate",   -- server -> client: my score after a round resolved
	"MatchFinished", -- server -> client: someone hit the target
	"SubmitAnswer",  -- client -> server
	"StartMatch",    -- client -> server (host only)
	"RestartMatch",  -- client -> server (host only)
	"SetTarget",     -- client -> server (host only)
	"LeaveLobby",    -- client -> server
	"SaveBest",      -- client -> server: persist a new personal best
	"BestScore",     -- server -> client: the stored personal best on join
}

local FUNCTIONS = {
	"CreateLobby",
	"JoinLobby",
}

local Net = {}

local function container()
	local stroop = ReplicatedStorage:FindFirstChild("Stroop")
	if not stroop then
		stroop = Instance.new("Folder")
		stroop.Name = "Stroop"
		stroop.Parent = ReplicatedStorage
	end
	local remotes = stroop:FindFirstChild("Remotes")
	if not remotes and RunService:IsServer() then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = stroop
	end
	return stroop, remotes
end

function Net.build()
	local _, remotes = container()
	for _, name in ipairs(EVENTS) do
		if not remotes:FindFirstChild(name) then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = remotes
		end
	end
	for _, name in ipairs(FUNCTIONS) do
		if not remotes:FindFirstChild(name) then
			local f = Instance.new("RemoteFunction")
			f.Name = name
			f.Parent = remotes
		end
	end
	return Net.get()
end

local cache = nil

function Net.get()
	if cache then
		return cache
	end
	local stroop = ReplicatedStorage:WaitForChild("Stroop")
	local remotes = stroop:WaitForChild("Remotes")
	cache = setmetatable({}, {
		__index = function(_, key)
			return remotes:WaitForChild(key, 10)
		end,
	})
	return cache
end

return Net
