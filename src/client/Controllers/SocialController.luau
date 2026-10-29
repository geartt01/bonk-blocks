--[[
	SocialController: INVITE button beside the coin counter. Shows the live friend
	boost ("FRIENDS +20%") once friends are here; always opens Roblox's invite prompt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxSocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local HudController = require(script.Parent:WaitForChild("HudController"))

local player = Players.LocalPlayer

local SocialController = {}

local label: TextLabel
local button: TextButton

local function refresh()
	local friends = math.min(player:GetAttribute("FriendsHere") or 0, Config.Social.MaxFriends)
	if friends > 0 then
		label.Text = `FRIENDS +{math.floor(friends * Config.Social.BonusPerFriend * 100 + 0.5)}%`
		button.BackgroundColor3 = Ui.Colors.Good
	else
		label.Text = `INVITE +{math.floor(Config.Social.BonusPerFriend * 100 + 0.5)}%`
		button.BackgroundColor3 = Color3.fromRGB(60, 140, 255)
	end
end

local function promptInvite()
	local ok, canInvite = pcall(function()
		return RobloxSocialService:CanSendGameInviteAsync(player)
	end)
	if ok and canInvite then
		pcall(function()
			RobloxSocialService:PromptGameInvite(player)
		end)
	else
		HudController.Toast("Invites aren't available right now", Ui.Colors.Bad)
	end
end

function SocialController.Init()
	-- Top-right corner: the only top-row spot that never collides with the centered
	-- scoreboard on a landscape phone
	local holder = Ui.new("Frame", {
		Name = "Invite",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(124, 40),
		BackgroundTransparency = 1,
		Parent = HudController.Gui,
	})
	Ui.scaled(holder)
	button = Ui.new("TextButton", {
		Name = "InviteButton",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Parent = holder,
	}, { Ui.corner(12), Ui.stroke(3) })
	label = Ui.label({ Position = UDim2.fromOffset(6, 7), Size = UDim2.new(1, -12, 1, -14), Parent = button })
	button.Activated:Connect(function()
		task.spawn(promptInvite)
	end)
	refresh()
end

function SocialController.Start()
	player:GetAttributeChangedSignal("FriendsHere"):Connect(refresh)
end

return SocialController
