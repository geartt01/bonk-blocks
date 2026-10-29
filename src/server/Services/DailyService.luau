--[[
	DailyService: streak-based daily rewards (Config.Daily).
	One claim per CooldownHours; missing StreakExpireHours restarts at day 1.
	Uses server os.time() only, so changing the device clock does nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local Signal = require(Shared.Signal)

local BlocklingService = require(script.Parent.BlocklingService)
local CoinService = require(script.Parent.CoinService)
local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local DailyService = {}
DailyService.Claimed = Signal.new() -- (player, day, streak)

local limiter = RateLimiter.new("DailyClaimRequest", { PerSecond = 1, Burst = 3 })
local resultRemote

local function onClaimRequest(player: Player)
	if not limiter:Allow(player) then
		return
	end
	local data = DataService.GetData(player)
	if not data then
		resultRemote:FireClient(player, { ok = false, code = "Loading" })
		return
	end
	local now = os.time()
	local claimable, nextStreak, day = Progression.DailyState(data.daily, now)
	if not claimable then
		resultRemote:FireClient(player, { ok = false, code = "NotReady" })
		return
	end

	-- Mark claimed first (no yields below), then grant
	data.daily.lastClaim = now
	data.daily.streak = nextStreak
	local coins = CoinService.Add(player, Progression.DailyCoins(day, data.rebirths), "DailyReward", {
		ignoreMultipliers = true,
	})
	local reward = Config.Daily.Rewards[day]
	local speciesId: string? = nil
	if reward.Blockling then
		speciesId = BlocklingService.Roll(reward.Blockling)
		BlocklingService.Grant(player, speciesId :: string, "Daily")
	end
	DataService.Sync(player)

	resultRemote:FireClient(player, { ok = true, code = "Claimed", day = day, coins = coins, streak = nextStreak, speciesId = speciesId })
	DailyService.Claimed:Fire(player, day, nextStreak)
end

-- Debug: make the next claim available now (streak continues)
function DailyService.DebugMakeClaimable(player: Player)
	local data = DataService.GetData(player)
	if data and data.daily.lastClaim > 0 then
		data.daily.lastClaim = os.time() - Config.Daily.CooldownHours * 3600
		DataService.Sync(player)
	end
end

function DailyService.Init()
	resultRemote = Net.Get(Constants.Remotes.DailyResult)
end

function DailyService.Start()
	Net.Get(Constants.Remotes.DailyClaimRequest).OnServerEvent:Connect(onClaimRequest)
end

return DailyService
