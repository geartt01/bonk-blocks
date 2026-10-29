--[[
	OnboardingService: the client says "ready" after the intro + release card.
	Sets the ClientReady player attribute (the welcome block waits for it) and, when the
	player dismissed the RELEASE card, remembers Config.Release.Version in their profile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local OnboardingService = {}

local limiter = RateLimiter.new("ClientReady", { PerSecond = 1, Burst = 3 })

local function onClientReady(player: Player, ackRelease: any)
	if not limiter:Allow(player) then
		return
	end
	player:SetAttribute(Constants.PlayerAttr.ClientReady, true)
	local data = DataService.GetData(player)
	if ackRelease == true and data and data.seenRelease ~= Config.Release.Version then
		data.seenRelease = Config.Release.Version
		DataService.Sync(player)
	end
end

function OnboardingService.Start()
	Net.Get(Constants.Remotes.ClientReady).OnServerEvent:Connect(onClientReady)
end

return OnboardingService
