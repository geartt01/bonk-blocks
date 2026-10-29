--[[
	ReleaseController: the "RELEASE!!" card (Config.Release). Shown once per Version
	after the intro (IntroController calls Show) and any time from the UPDATES button
	under INVITE. Doubles as a how-to-play for brand-new players.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local player = Players.LocalPlayer
local Colors = Ui.Colors
local Release = Config.Release
local DOT_COLORS = {
	Color3.fromRGB(255, 120, 170),
	Color3.fromRGB(120, 230, 160),
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(120, 160, 255),
	Color3.fromRGB(255, 150, 70),
}

local ReleaseController = {}

local refs: { [string]: any } = {}
local onClosed: (() -> ())? = nil

function ReleaseController.NeedsShow(): boolean
	return player:GetAttribute(Constants.PlayerAttr.SeenRelease) ~= Release.Version
end

function ReleaseController.Hide()
	if not refs.holder.Visible then
		return
	end
	refs.holder.Visible = false
	HudController.PanelClosed("Release")
	local callback = onClosed
	onClosed = nil
	if callback then
		callback()
	end
end

function ReleaseController.Show(callback: (() -> ())?)
	onClosed = callback
	refs.holder.Visible = true
	HudController.PanelOpened("Release", ReleaseController.Hide)
	Ui.pop(refs.pop, 0.25)
	SoundController.Play("RoundStart")
end

local function build(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "ReleaseCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(580, 200 + #Release.Items * 40), -- header 88 + rows + how-to/button 112
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	Ui.scaled(holder)
	local card = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		ZIndex = 10,
		Parent = holder,
	}, { Ui.corner(22) })
	Ui.animatedStroke(Ui.new("UIStroke", { Thickness = 5, Parent = card }), Ui.GoldShimmer, 4)
	refs.pop = Ui.new("UIScale", { Parent = card })

	local title = Ui.label({
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -32, 0, 56),
		Text = Release.Title,
		TextColor3 = Colors.Gold,
		TextStrokeTransparency = 0,
		ZIndex = 11,
		Parent = card,
	})
	title.Rotation = -2
	TweenService:Create(title, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 2 }):Play()

	local version = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(64, 28),
		BackgroundColor3 = Colors.Purple,
		ZIndex = 11,
		Parent = card,
	}, { Ui.corner(10) })
	Ui.label({ Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), Text = `v{Release.Version}`, ZIndex = 12, Parent = version })

	Ui.label({
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.new(1, -32, 0, 20),
		Text = Release.Subtitle,
		TextColor3 = Colors.Muted,
		ZIndex = 11,
		Parent = card,
	})

	local list = Ui.new("Frame", {
		Position = UDim2.fromOffset(16, 88),
		Size = UDim2.new(1, -32, 0, #Release.Items * 40),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = card,
	})
	Ui.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	for index, item in Release.Items do
		local row = Ui.new("Frame", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = Colors.PanelLight,
			ZIndex = 11,
			Parent = list,
		}, { Ui.corner(10) })
		Ui.new("Frame", {
			Position = UDim2.fromOffset(8, 7),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = DOT_COLORS[((index - 1) % #DOT_COLORS) + 1],
			ZIndex = 12,
			Parent = row,
		}, { Ui.round(), Ui.stroke(2) })
		Ui.label({
			Position = UDim2.fromOffset(38, 2),
			Size = UDim2.new(1, -46, 0, 17),
			Text = item.Title,
			TextColor3 = Colors.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 12,
			Parent = row,
		})
		Ui.label({
			Position = UDim2.fromOffset(38, 19),
			Size = UDim2.new(1, -46, 0, 14),
			Text = item.Text,
			TextColor3 = Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 12,
			Parent = row,
		})
	end

	local howTo = Ui.new("Frame", {
		Position = UDim2.new(0, 16, 1, -96),
		Size = UDim2.new(1, -32, 0, 30),
		BackgroundColor3 = Colors.Accent,
		ZIndex = 11,
		Parent = card,
	}, { Ui.corner(10) })
	Ui.label({ Position = UDim2.fromOffset(8, 5), Size = UDim2.new(1, -16, 1, -10), Text = Release.HowTo, ZIndex = 12, Parent = howTo })

	local button = Ui.new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(280, 54),
		BackgroundColor3 = Colors.Good,
		Text = "",
		ZIndex = 11,
		Parent = card,
	}, { Ui.corner(16), Ui.stroke(4) })
	Ui.label({ Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 1, -16), Text = Release.Button, ZIndex = 12, Parent = button })
	Ui.shine(button, 2.2)
	local pulse = Ui.new("UIScale", { Parent = button })
	TweenService:Create(pulse, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()
	button.Activated:Connect(ReleaseController.Hide)

	refs.holder = holder
end

local function buildUpdatesButton(gui: ScreenGui)
	-- Child of the (scaled) INVITE holder so the two always stack cleanly
	local anchor = gui:WaitForChild("Invite", 5)
	if not anchor then
		return
	end
	local button = Ui.new("TextButton", {
		Name = "UpdatesButton",
		Position = UDim2.new(0, 0, 1, 6),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = Colors.Purple,
		Text = "",
		Parent = anchor,
	}, { Ui.corner(10), Ui.stroke(3) })
	Ui.label({ Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), Text = "UPDATES", Parent = button })
	button.Activated:Connect(function()
		if refs.holder.Visible then
			ReleaseController.Hide()
		else
			ReleaseController.Show(nil)
		end
	end)
end

function ReleaseController.Init()
	local gui = HudController.Gui :: ScreenGui
	build(gui)
	buildUpdatesButton(gui)
end

return ReleaseController
