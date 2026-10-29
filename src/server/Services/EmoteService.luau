--[[
	EmoteService: validates emote requests and replicates them as character attributes
		Emote   = emote id ("" = none)
		EmoteAt = workspace:GetServerTimeNow() when it started
	Every client animates every emoting character from these (EmoteController), so all
	players see the same moves. The winning team auto-dances on the results screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)

local RoundService = require(script.Parent.RoundService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local EmoteService = {}

local limiter = RateLimiter.new("EmoteRequest", { PerSecond = 2, Burst = 3 })
local durations: { [string]: number } = {}
for _, emote in Config.Emotes.List do
	durations[emote.Id] = emote.Duration
end

function EmoteService.Play(player: Player, emoteId: string, duration: number?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid) or humanoid.Health <= 0 then
		return
	end
	local startedAt = workspace:GetServerTimeNow()
	character:SetAttribute("Emote", emoteId)
	character:SetAttribute("EmoteAt", startedAt)
	task.delay(duration or durations[emoteId] or 3, function()
		if character.Parent and character:GetAttribute("EmoteAt") == startedAt then
			character:SetAttribute("Emote", "")
		end
	end)
end

function EmoteService.Stop(player: Player)
	local character = player.Character
	if character then
		character:SetAttribute("Emote", "")
	end
end

local function onEmoteRequest(player: Player, emoteId: any)
	if not limiter:Allow(player) or typeof(emoteId) ~= "string" then
		return
	end
	if emoteId == "" then
		EmoteService.Stop(player)
	elseif durations[emoteId] then
		EmoteService.Play(player, emoteId)
	else
		RateLimiter.Reject(player, "EmoteRequest", "unknown emote")
	end
end

function EmoteService.Start()
	Net.Get(Constants.Remotes.EmoteRequest).OnServerEvent:Connect(onEmoteRequest)

	-- Winners dance together on the results screen (great for screenshots and clips)
	RoundService.RoundFinished:Connect(function(summary)
		for _, entry in summary.players do
			if entry.teamId ~= nil and entry.teamId == summary.winner then
				local player = Players:GetPlayerByUserId(entry.userId)
				if player then
					EmoteService.Play(player, Config.Emotes.VictoryEmote, Config.Emotes.VictoryDuration)
				end
			end
		end
	end)
end

return EmoteService
