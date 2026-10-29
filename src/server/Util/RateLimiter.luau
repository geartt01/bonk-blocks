--[[
	RateLimiter: per-player token bucket for remotes.

		local limiter = RateLimiter.new("SwingRequest", Config.RateLimits.SwingRequest)
		remote.OnServerEvent:Connect(function(player, ...)
			if not limiter:Allow(player) then return end
			...
		end)

	Drops are counted across all limiters; a player who floods past
	Config.RateLimits.KickAfterDrops within DropWindow seconds is kicked.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

type Bucket = { tokens: number, updated: number }

local RateLimiter = {}
RateLimiter.__index = RateLimiter

local limiters = {}
local drops: { [Player]: { count: number, windowStart: number } } = {}

local function recordDrop(player: Player, name: string)
	if Config.Debug.LogRejectedRemotes then
		warn(`[RateLimiter] Dropped {name} from {player.Name}`)
	end
	local limit = Config.RateLimits.KickAfterDrops
	if limit <= 0 then
		return
	end
	local now = os.clock()
	local entry = drops[player]
	if not entry or now - entry.windowStart > Config.RateLimits.DropWindow then
		entry = { count = 0, windowStart = now }
		drops[player] = entry
	end
	entry.count += 1
	if entry.count == limit then
		player:Kick("Too many requests. Please rejoin.")
	end
end

function RateLimiter.new(name: string, settings: { PerSecond: number, Burst: number })
	local self = setmetatable({
		name = name,
		rate = settings.PerSecond,
		burst = settings.Burst,
		buckets = {} :: { [Player]: Bucket },
	}, RateLimiter)
	table.insert(limiters, self)
	return self
end

function RateLimiter:Allow(player: Player): boolean
	local now = os.clock()
	local bucket = self.buckets[player]
	if not bucket then
		bucket = { tokens = self.burst, updated = now }
		self.buckets[player] = bucket
	end
	bucket.tokens = math.min(self.burst, bucket.tokens + (now - bucket.updated) * self.rate)
	bucket.updated = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	recordDrop(player, self.name)
	return false
end

-- Log a request that passed the rate limit but failed validation (debug only)
function RateLimiter.Reject(player: Player, name: string, why: string)
	if Config.Debug.LogRejectedRemotes then
		warn(`[Remote] {name} from {player.Name} rejected: {why}`)
	end
end

Players.PlayerRemoving:Connect(function(player)
	for _, limiter in limiters do
		limiter.buckets[player] = nil
	end
	drops[player] = nil
end)

return RateLimiter
