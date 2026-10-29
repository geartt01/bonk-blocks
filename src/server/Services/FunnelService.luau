--[[
	FunnelService: measures the 30-second hook with Roblox's onboarding funnel
	(Creator Dashboard -> Analytics -> Funnels). Only brand-new players are tracked.

	Steps: Joined -> FirstSwing -> FirstHit -> FirstCrack -> CanAffordUpgrade -> FirstUpgrade -> FinishedRound
	Plus custom events with the seconds-since-join for the two key hook moments.
	Listens to other services' signals; nothing calls into it.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local HammerStats = require(Shared.HammerStats)

local BlockService = require(script.Parent.BlockService)
local CoinService = require(script.Parent.CoinService)
local DataService = require(script.Parent.DataService)
local HammerService = require(script.Parent.HammerService)
local RoundService = require(script.Parent.RoundService)
local UpgradeService = require(script.Parent.UpgradeService)

local STEPS = { "Joined", "FirstSwing", "FirstHit", "FirstCrack", "CanAffordUpgrade", "FirstUpgrade", "FinishedRound" }

local FunnelService = {}

type Tracking = { joinedAt: number, done: { [string]: boolean } }
local tracking: { [Player]: Tracking } = {}

local function log(player: Player, stepName: string)
	local entry = tracking[player]
	if not entry or entry.done[stepName] then
		return
	end
	entry.done[stepName] = true
	local step = table.find(STEPS, stepName) :: number
	local seconds = os.clock() - entry.joinedAt
	if RunService:IsStudio() and Config.Debug.LogFunnel then
		print(`[Funnel] {player.Name} step {step} {stepName} at {string.format("%.1f", seconds)}s`)
	end
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
	if stepName == "FirstCrack" or stepName == "FirstUpgrade" then
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "SecondsTo" .. stepName, math.floor(seconds * 10) / 10)
		end)
	end
end

function FunnelService.Start()
	DataService.ProfileLoaded:Connect(function(player, data)
		-- New player = never broke a block, never bought anything
		if data.totalBlocksCrushed == 0 and HammerStats.TotalTiers(data.upgrades) == 0 then
			tracking[player] = { joinedAt = os.clock(), done = {} }
			log(player, "Joined")
		end
	end)

	HammerService.Swung:Connect(function(player)
		log(player, "FirstSwing")
	end)

	BlockService.BlockHit:Connect(function(_state, player)
		log(player, "FirstHit")
	end)

	BlockService.BlockResolved:Connect(function(_state, reason, _team, payouts)
		if reason == "Despawn" then
			return
		end
		for _, payout in payouts do
			log(payout.player, "FirstCrack")
		end
	end)

	CoinService.Changed:Connect(function(player, balance)
		local entry = tracking[player]
		local data = entry and not entry.done.CanAffordUpgrade and DataService.GetData(player)
		if data then
			local cheapest = HammerStats.CheapestNextCost(data.upgrades)
			if cheapest and balance >= cheapest then
				log(player, "CanAffordUpgrade")
			end
		end
	end)

	UpgradeService.Upgraded:Connect(function(player)
		log(player, "FirstUpgrade")
	end)

	RoundService.StateChanged:Connect(function(state)
		if state == Constants.RoundState.Summary then
			for player in tracking do
				if player.Parent == Players then
					log(player, "FinishedRound")
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		tracking[player] = nil
	end)
end

return FunnelService
