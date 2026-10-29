--[[
	SettingsService: saves per-player toggles (sound, screen shake) in the profile.
	Only keys in Constants.SettingDefaults with boolean values are accepted.
	The new value reaches the client through the Set_<key> attribute (DataService.Sync).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local SettingsService = {}

local limiter = RateLimiter.new("SettingsRequest", { PerSecond = 4, Burst = 6 })

local function onSettingsRequest(player: Player, key: any, value: any)
	if not limiter:Allow(player) then
		return
	end
	if typeof(key) ~= "string" or Constants.SettingDefaults[key] == nil or typeof(value) ~= "boolean" then
		RateLimiter.Reject(player, "SettingsRequest", "bad key/value")
		return
	end
	local data = DataService.GetData(player)
	if not data or data.settings[key] == value then
		return
	end
	data.settings[key] = value
	DataService.Sync(player)
end

function SettingsService.Start()
	Net.Get(Constants.Remotes.SettingsRequest).OnServerEvent:Connect(onSettingsRequest)
end

return SettingsService
