--[[
	ClientState: read-only mirror of server state (player attributes + BonkGameState).
	Display only: the server never reads these values back.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local HammerStats = require(Shared:WaitForChild("HammerStats"))
local Signal = require(Shared:WaitForChild("Signal"))

local player = Players.LocalPlayer
local PlayerAttr = Constants.PlayerAttr
local GameAttr = Constants.GameAttr
local State = Constants.RoundState

local ClientState = {}
ClientState.Changed = Signal.new() -- (key: string) attribute name, or "Team"

local gameState: Instance

function ClientState.IsLoaded(): boolean
	return player:GetAttribute(PlayerAttr.Loaded) == true
end

function ClientState.Coins(): number
	return player:GetAttribute(PlayerAttr.Coins) or 0
end

function ClientState.Upgrades(): { [string]: number }
	local upgrades = {}
	for _, id in Config.Upgrades.Order do
		upgrades[id] = player:GetAttribute(Constants.UpgradeAttr(id)) or 0
	end
	return upgrades
end

function ClientState.State(): string
	return gameState:GetAttribute(GameAttr.State) or State.Waiting
end

function ClientState.Mode(): string
	return gameState:GetAttribute(GameAttr.Mode) or Constants.Mode.Coop
end

function ClientState.TimeLeft(): number
	local endsAt = gameState:GetAttribute(GameAttr.EndsAt) or 0
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

function ClientState.Score(teamId: string): number
	return gameState:GetAttribute(Constants.ScoreAttr(teamId)) or 0
end

function ClientState.CoopTarget(): number
	return gameState:GetAttribute(GameAttr.CoopTarget) or 0
end

function ClientState.TeamId(): string?
	local team = player.Team
	if not team then
		return nil
	end
	for teamId, def in Config.Teams do
		if def.DisplayName == team.Name then
			return teamId
		end
	end
	return nil
end

function ClientState.IsCombatOpen(): boolean
	local state = ClientState.State()
	return state == State.Active or state == State.Intermission
end

-- Mirrors UpgradeService.IsShopOpenFor (the server re-checks)
function ClientState.IsShopOpenForMe(): boolean
	if Config.Upgrades.ShopOpenDuringRound or ClientState.State() ~= State.Active then
		return true
	end
	return Config.Upgrades.FirstPurchaseAnytime
		and ClientState.Rebirths() == 0
		and HammerStats.TotalTiers(ClientState.Upgrades()) == 0
end

-- Week 2 ------------------------------------------------------------------------

function ClientState.Rebirths(): number
	return player:GetAttribute(PlayerAttr.Rebirths) or 0
end

function ClientState.BlocklingCount(speciesId: string): number
	return player:GetAttribute(Constants.BlocklingAttr(speciesId)) or 0
end

function ClientState.Equipped(target: Player?): { string }
	local value = (target or player):GetAttribute(PlayerAttr.Equipped)
	if typeof(value) ~= "string" or value == "" then
		return {}
	end
	return string.split(value, ",")
end

function ClientState.Slots(): number
	return player:GetAttribute(PlayerAttr.Slots) or Config.Blocklings.BaseSlots
end

-- Daily: claimable now? (server unix time vs the replicated unlock time)
function ClientState.DailyClaimable(): boolean
	return ClientState.IsLoaded() and workspace:GetServerTimeNow() >= (player:GetAttribute(PlayerAttr.DailyNextAt) or 0)
end

function ClientState.DailySecondsLeft(): number
	return math.max(0, (player:GetAttribute(PlayerAttr.DailyNextAt) or 0) - workspace:GetServerTimeNow())
end

function ClientState.DailyDay(): number
	return player:GetAttribute(PlayerAttr.DailyDay) or 1
end

-- Best mutation owned for a species (nil = none); works for any player
function ClientState.Mutation(speciesId: string, target: Player?): string?
	local value = (target or player):GetAttribute(Constants.MutationAttr(speciesId))
	return if typeof(value) == "string" and value ~= "" then value else nil
end

-- Server-wide event currently running ("" = none) and when it ends (unix time)
function ClientState.Event(): string
	return gameState:GetAttribute(GameAttr.Event) or ""
end

function ClientState.EventEndsAt(): number
	return gameState:GetAttribute(GameAttr.EventEndsAt) or 0
end

function ClientState.Init()
	gameState = ReplicatedStorage:WaitForChild(Constants.GameStateName)
end

function ClientState.Start()
	player.AttributeChanged:Connect(function(name)
		ClientState.Changed:Fire(name)
	end)
	gameState.AttributeChanged:Connect(function(name)
		ClientState.Changed:Fire(name)
	end)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		ClientState.Changed:Fire("Team")
	end)
end

return ClientState
