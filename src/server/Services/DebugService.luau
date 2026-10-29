--[[
	DebugService: playtest shortcuts, honored ONLY when the server runs in Studio.
	On a live server every DebugCommand is ignored (and logged when
	Config.Debug.LogRejectedRemotes is on), so shipping it is harmless.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)

local BlockService = require(script.Parent.BlockService)
local BlocklingService = require(script.Parent.BlocklingService)
local CoinService = require(script.Parent.CoinService)
local DailyService = require(script.Parent.DailyService)
local EventService = require(script.Parent.EventService)
local QuestService = require(script.Parent.QuestService)
local DataService = require(script.Parent.DataService)
local HammerService = require(script.Parent.HammerService)
local RoundService = require(script.Parent.RoundService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local DebugService = {}

local limiter = RateLimiter.new("DebugCommand", { PerSecond = 4, Burst = 4 })

local COMMANDS: { [string]: (player: Player) -> () } = {
	coins = function(player)
		CoinService.Add(player, 500, "Debug", { ignoreMultipliers = true })
	end,
	coins10k = function(player)
		CoinService.Add(player, 10000, "Debug", { ignoreMultipliers = true })
	end,
	blockling = function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		BlocklingService.Grant(player, BlocklingService.Roll(nil), "Debug", if root then root.Position + Vector3.new(0, 4, -6) else nil)
	end,
	daily = function(player)
		DailyService.DebugMakeClaimable(player)
	end,
	quests = function(player)
		QuestService.DebugCompleteAll(player)
	end,
	event = function()
		EventService.DebugStartNext()
	end,
	skip = function()
		RoundService.SkipPhase()
	end,
	block = function(player)
		BlockService.SpawnWelcome(player)
	end,
	-- Back to a brand-new player, so the 30s hook can be re-tested without wiping the DataStore
	reset = function(player)
		local data = DataService.GetData(player)
		if not data then
			return
		end
		if data.coins > 0 then
			CoinService.TrySpend(player, data.coins, "DebugReset")
		end
		for _, id in Config.Upgrades.Order do
			data.upgrades[id] = 0
		end
		data.hammerLevel = 1
		data.totalBlocksCrushed = 0
		data.rebirths = 0
		data.blocklings = {}
		data.equippedBlocklings = {}
		data.mutations = {}
		data.blocksSinceBlockling = 0
		data.daily = { lastClaim = 0, streak = 0 }
		data.quests = { day = -1, list = {} } -- rerolled on next progress
		DataService.Sync(player)
		HammerService.Equip(player)
		RoundService.ResetWelcome(player)
		QuestService.Refresh(player)
	end,
}

local function onDebugCommand(player: Player, command: any)
	if not RunService:IsStudio() then
		RateLimiter.Reject(player, "DebugCommand", "not in Studio")
		return
	end
	if not limiter:Allow(player) or typeof(command) ~= "string" then
		return
	end
	local handler = COMMANDS[command]
	if handler then
		print(`[Debug] {player.Name}: {command}`)
		handler(player)
	end
end

function DebugService.Start()
	Net.Get(Constants.Remotes.DebugCommand).OnServerEvent:Connect(onDebugCommand)
end

return DebugService
