--[[
	UpgradeService: validates and applies hammer upgrade purchases.
	The client sends only the upgrade id; cost, tier and shop state are server-side.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local HammerStats = require(Shared.HammerStats)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local CoinService = require(script.Parent.CoinService)
local DataService = require(script.Parent.DataService)
local RoundService = require(script.Parent.RoundService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local UpgradeService = {}
UpgradeService.Upgraded = Signal.new() -- (player, upgradeId, newTier)

local limiter = RateLimiter.new("PurchaseRequest", Config.RateLimits.PurchaseRequest)
local resultRemote

function UpgradeService.IsShopOpenFor(data: Types.PlayerData): boolean
	if Config.Upgrades.ShopOpenDuringRound or RoundService.IsShopOpen() then
		return true
	end
	-- Lets a brand-new player buy their very first upgrade mid-round (30s hook).
	-- Not after a rebirth: rebirthed players know the shop.
	return Config.Upgrades.FirstPurchaseAnytime and data.rebirths == 0 and HammerStats.TotalTiers(data.upgrades) == 0
end

local function reply(player: Player, ok: boolean, code: string, upgradeId: string?, tier: number?)
	local result: Types.PurchaseResult = { ok = ok, code = code, upgradeId = upgradeId, tier = tier }
	resultRemote:FireClient(player, result)
end

local function onPurchaseRequest(player: Player, upgradeId: any)
	if not limiter:Allow(player) then
		return
	end
	if typeof(upgradeId) ~= "string" or Config.Upgrades.Defs[upgradeId] == nil then
		RateLimiter.Reject(player, "PurchaseRequest", "bad upgrade id")
		return
	end
	local data = DataService.GetData(player)
	if not data then
		reply(player, false, "Loading", upgradeId)
		return
	end

	local tier = data.upgrades[upgradeId] or 0
	local cost = HammerStats.NextCost(upgradeId, tier)
	if not cost then
		reply(player, false, "Maxed", upgradeId, tier)
		return
	end
	if not UpgradeService.IsShopOpenFor(data) then
		reply(player, false, "ShopClosed", upgradeId, tier)
		return
	end
	-- TrySpend + tier bump happen in the same frame with no yield: no double-buy.
	if not CoinService.TrySpend(player, cost, "Upgrade:" .. upgradeId) then
		reply(player, false, "NotEnoughCoins", upgradeId, tier)
		return
	end

	data.upgrades[upgradeId] = tier + 1
	data.hammerLevel = HammerStats.HammerLevel(data.upgrades)
	DataService.Sync(player)
	UpgradeService.Upgraded:Fire(player, upgradeId, tier + 1)
	reply(player, true, "Purchased", upgradeId, tier + 1)
end

function UpgradeService.Init()
	resultRemote = Net.Get(Constants.Remotes.PurchaseResult)
end

function UpgradeService.Start()
	Net.Get(Constants.Remotes.PurchaseRequest).OnServerEvent:Connect(onPurchaseRequest)
end

return UpgradeService
