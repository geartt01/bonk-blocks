--[[
	AchievementService: awards Roblox badges (Config.Badges) from existing signals.
	Badges show on player profiles and the game page: free, permanent reasons to return.
	Ids of 0 are skipped, so this is safe to ship before the badges exist.
]]

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)

local BlockService = require(script.Parent.BlockService)
local BlocklingService = require(script.Parent.BlocklingService)
local DataService = require(script.Parent.DataService)
local RebirthService = require(script.Parent.RebirthService)
local RoundService = require(script.Parent.RoundService)

local AchievementService = {}

local awarded: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

function AchievementService.Award(player: Player, badgeKey: string)
	local badgeId = Config.Badges[badgeKey]
	if typeof(badgeId) ~= "number" or badgeId <= 0 then
		return
	end
	local mine = awarded[player] or {}
	awarded[player] = mine
	if mine[badgeKey] then
		return
	end
	mine[badgeKey] = true
	task.spawn(function()
		pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, badgeId) then
				BadgeService:AwardBadge(player.UserId, badgeId)
			end
		end)
	end)
end

function AchievementService.Start()
	BlockService.BlockResolved:Connect(function(state, reason, _team, payouts)
		if reason == "Despawn" then
			return
		end
		for _, payout in payouts do
			AchievementService.Award(payout.player, "FirstCrack")
			if state.kind == "Mega" then
				AchievementService.Award(payout.player, "MegaBlock")
			end
		end
	end)

	BlocklingService.Granted:Connect(function(player, _speciesId, _count, _source, mutation)
		AchievementService.Award(player, "FirstBlockling")
		if mutation == "Rainbow" then
			AchievementService.Award(player, "Rainbow")
		end
		local data = DataService.GetData(player)
		if data then
			local complete = true
			for _, species in Progression.AllSpecies() do
				if (data.blocklings[species.Id] or 0) < 1 then
					complete = false
					break
				end
			end
			if complete then
				AchievementService.Award(player, "FullCollection")
			end
		end
	end)

	RebirthService.Rebirthed:Connect(function(player)
		AchievementService.Award(player, "FirstRebirth")
	end)

	RoundService.RoundFinished:Connect(function(summary)
		for _, entry in summary.players do
			if entry.teamId ~= nil and entry.teamId == summary.winner then
				local player = Players:GetPlayerByUserId(entry.userId)
				if player then
					AchievementService.Award(player, "FirstWin")
				end
			end
		end
	end)
end

return AchievementService
