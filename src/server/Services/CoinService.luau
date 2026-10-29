--[[
	CoinService: the ONLY code allowed to change a player's coins.

		CoinService.Add(player, amount, reason) -> granted amount (0 on failure)
		CoinService.TrySpend(player, amount, reason) -> boolean

	Week 2 hooks:
		CoinService.RegisterMultiplier("Rebirth", function(player, amount, reason) return 1.5 end)
		CoinService.Changed:Connect(function(player, balance, delta, reason) ... end) -- analytics, quests
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

local DataService = require(script.Parent.DataService)

type Multiplier = (player: Player, amount: number, reason: string) -> number

local CoinService = {}
CoinService.Changed = Signal.new() -- (player, newBalance, delta, reason)

local multipliers: { [string]: Multiplier } = {}

local function isValidAmount(amount: any): boolean
	return typeof(amount) == "number" and amount == amount and amount > 0 and amount < math.huge
end

local function isPlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

function CoinService.RegisterMultiplier(name: string, fn: Multiplier)
	multipliers[name] = fn
end

function CoinService.RemoveMultiplier(name: string)
	multipliers[name] = nil
end

function CoinService.Get(player: Player): number
	local data = DataService.GetData(player)
	return if data then data.coins else 0
end

function CoinService.Add(player: Player, amount: number, reason: string, options: { ignoreMultipliers: boolean? }?): number
	if not isPlayer(player) or not isValidAmount(amount) or typeof(reason) ~= "string" then
		warn(`[CoinService] Rejected Add({player}, {amount}, {reason})`)
		return 0
	end
	local data = DataService.GetData(player)
	if not data then
		return 0
	end

	local final = amount
	if not (options and options.ignoreMultipliers) then
		for name, fn in multipliers do
			local ok, mult = pcall(fn, player, amount, reason)
			if ok and isValidAmount(mult) then
				final *= mult
			elseif not ok then
				warn(`[CoinService] Multiplier "{name}" errored: {mult}`)
			end
		end
	end

	final = math.floor(math.min(final, Config.Coins.MaxSingleGrant) + 0.5)
	if final <= 0 then
		return 0
	end

	data.coins += final
	DataService.Sync(player)
	CoinService.Changed:Fire(player, data.coins, final, reason)
	return final
end

function CoinService.TrySpend(player: Player, amount: number, reason: string): boolean
	if not isPlayer(player) or not isValidAmount(amount) or typeof(reason) ~= "string" then
		return false
	end
	local data = DataService.GetData(player)
	amount = math.floor(amount)
	if not data or data.coins < amount then
		return false
	end
	data.coins -= amount
	DataService.Sync(player)
	CoinService.Changed:Fire(player, data.coins, -amount, reason)
	return true
end

function CoinService.Start()
	local debugCoins = Config.Debug.StudioStartingCoins
	if RunService:IsStudio() and debugCoins > 0 then
		DataService.ProfileLoaded:Connect(function(player)
			if player.Parent == Players then
				CoinService.Add(player, debugCoins, "DebugGrant", { ignoreMultipliers = true })
			end
		end)
	end
end

return CoinService
