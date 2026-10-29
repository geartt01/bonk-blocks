--[[
	RebirthService: trade coins + hammer upgrades for a permanent coin multiplier
	(Config.Rebirth.CoinBonusPerRebirth each) and extra Blockling slots.
	Keeps: Blocklings, totalBlocksCrushed (leaderboard), settings, daily streak.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local HammerStats = require(Shared.HammerStats)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local Signal = require(Shared.Signal)

local CoinService = require(script.Parent.CoinService)
local DataService = require(script.Parent.DataService)
local HammerService = require(script.Parent.HammerService)
local RoundService = require(script.Parent.RoundService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local RebirthService = {}
RebirthService.Rebirthed = Signal.new() -- (player, newRebirthCount)

local limiter = RateLimiter.new("RebirthRequest", { PerSecond = 1, Burst = 2 })
local notifyRemote, rebirthedRemote

local function onRebirthRequest(player: Player)
	if not limiter:Allow(player) then
		return
	end
	local data = DataService.GetData(player)
	if not data then
		return
	end
	if data.rebirths >= Config.Rebirth.MaxRebirths then
		notifyRemote:FireClient(player, { text = "You've hit the max rebirth. Legend!" })
		return
	end
	if Config.Rebirth.BetweenRoundsOnly and not RoundService.IsShopOpen() then
		notifyRemote:FireClient(player, { text = "Rebirth between rounds!" })
		return
	end
	local cost = Progression.RebirthCost(data.rebirths)
	if data.coins < cost then
		notifyRemote:FireClient(player, { text = `Rebirth needs {cost} coins` })
		return
	end

	-- All in one frame, no yields: spend everything, reset upgrades, bump the counter
	if not CoinService.TrySpend(player, data.coins, "Rebirth") then
		return
	end
	for _, id in Config.Upgrades.Order do
		data.upgrades[id] = 0
	end
	data.rebirths += 1
	data.hammerLevel = HammerStats.HammerLevel(data.upgrades)
	DataService.Sync(player)
	HammerService.Equip(player) -- hammer shrinks back to base size

	RebirthService.Rebirthed:Fire(player, data.rebirths)
	rebirthedRemote:FireAllClients({ userId = player.UserId, name = player.DisplayName, rebirths = data.rebirths })
end

function RebirthService.Init()
	notifyRemote = Net.Get(Constants.Remotes.Notify)
	rebirthedRemote = Net.Get(Constants.Remotes.Rebirthed)
end

function RebirthService.Start()
	CoinService.RegisterMultiplier("Rebirth", function(player, _amount, reason)
		if not Config.Blocklings.BonusReasons[reason] then
			return 1
		end
		local data = DataService.GetData(player)
		return if data then Progression.RebirthMultiplier(data.rebirths) else 1
	end)
	Net.Get(Constants.Remotes.RebirthRequest).OnServerEvent:Connect(onRebirthRequest)
end

return RebirthService
