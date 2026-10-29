--[[
	SocialService (Bonk Blocks, not Roblox's SocialService): friends-in-server coin boost.
	Friendship is checked on the server with Player:IsFriendsWith (cached per pair), the
	count is replicated as the "FriendsHere" player attribute, and the boost is a
	CoinService multiplier on earned coins (block + round rewards only).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local CoinService = require(script.Parent.CoinService)

local SocialService = {}

local friendCache: { [string]: boolean } = {}

local function pairKey(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

local function areFriends(a: Player, b: Player): boolean
	local key = pairKey(a.UserId, b.UserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	local value = ok and result == true
	friendCache[key] = value
	return value
end

local function recount()
	local players = Players:GetPlayers()
	for _, player in players do
		local count = 0
		for _, other in players do
			if other ~= player and other.Parent == Players and areFriends(player, other) then
				count += 1
			end
		end
		if player.Parent == Players then
			player:SetAttribute("FriendsHere", count)
		end
	end
end

function SocialService.BoostFor(player: Player): number
	local friends = math.min(player:GetAttribute("FriendsHere") or 0, Config.Social.MaxFriends)
	return 1 + friends * Config.Social.BonusPerFriend
end

function SocialService.Start()
	CoinService.RegisterMultiplier("Friends", function(player, _amount, reason)
		if not Config.Blocklings.BonusReasons[reason] then
			return 1
		end
		return SocialService.BoostFor(player)
	end)
	Players.PlayerAdded:Connect(function()
		task.spawn(recount)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(recount)
	end)
	task.spawn(recount)
end

return SocialService
