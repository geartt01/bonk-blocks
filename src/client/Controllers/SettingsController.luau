--[[
	SettingsController: gear button (next to the coin counter) + a small panel of
	toggles. Sends SettingsRequest(key, value); the saved value comes back as the
	Set_<key> player attribute, which SoundController/CameraController read.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Net = require(Shared:WaitForChild("Net"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local player = Players.LocalPlayer
local Colors = Ui.Colors

local ROWS = {
	{ key = "sfx", label = "Sound effects" },
	{ key = "shake", label = "Screen shake" },
	{ key = "bigui", label = "Big buttons" },
}

local SettingsController = {}

local panel: Frame
local panelPop: UIScale
local toggles: { [string]: { button: TextButton, label: TextLabel } } = {}
local requestRemote

local function isOn(key: string): boolean
	local value = player:GetAttribute(Constants.SettingAttr(key))
	if value == nil then
		return Constants.SettingDefaults[key] == true
	end
	return value == true
end

local function refresh()
	for key, toggle in toggles do
		local on = isOn(key)
		toggle.button.BackgroundColor3 = if on then Colors.Good else Colors.Disabled
		toggle.label.Text = if on then "ON" else "OFF"
	end
end

local function build(gui: ScreenGui)
	-- Children of the (already scaled) coin pill, so they scale and move with it
	local anchor = gui:WaitForChild("Coins") :: Frame
	anchor.ZIndex = 5 -- the dropdown below the coin pill must draw over the left menu
	local gearHolder = Ui.new("Frame", {
		Name = "SettingsButton",
		Position = UDim2.new(1, 8, 0, 0),
		Size = UDim2.fromOffset(50, 50),
		BackgroundTransparency = 1,
		Parent = anchor,
	})
	local gear = Ui.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		Text = "",
		Parent = gearHolder,
	}, { Ui.corner(14), Ui.stroke(3) })
	-- Simple gear: a ring with a dot
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.56),
		BackgroundTransparency = 1,
		Parent = gear,
	}, { Ui.round(), Ui.stroke(5, Colors.Muted) })
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.18, 0.18),
		BackgroundColor3 = Colors.Muted,
		Parent = gear,
	}, { Ui.round() })

	local holder = Ui.new("Frame", {
		Name = "SettingsPanel",
		Position = UDim2.new(0, 0, 1, 8),
		Size = UDim2.fromOffset(260, 40 + #ROWS * 58),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = anchor,
	})
	local card = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		Parent = holder,
	}, { Ui.corner(16), Ui.stroke(4) })
	panelPop = Ui.new("UIScale", { Parent = card })
	Ui.label({ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 26), Text = "SETTINGS", Parent = card })

	for index, row in ROWS do
		local y = 40 + (index - 1) * 58
		Ui.label({
			Position = UDim2.fromOffset(14, y + 12),
			Size = UDim2.new(1, -120, 0, 26),
			Text = row.label,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		local button = Ui.new("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, y + 4),
			Size = UDim2.fromOffset(88, 46),
			Text = "",
			Parent = card,
		}, { Ui.corner(12), Ui.stroke(3) })
		local label = Ui.label({ Position = UDim2.fromOffset(6, 8), Size = UDim2.new(1, -12, 1, -16), Parent = button })
		toggles[row.key] = { button = button, label = label }
		button.Activated:Connect(function()
			local value = not isOn(row.key)
			requestRemote:FireServer(row.key, value)
			if row.key == "sfx" and value then
				task.delay(0.3, SoundController.Play, "Purchase") -- audible confirmation once unmuted
			end
		end)
	end

	panel = holder
	gear.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			Ui.pop(panelPop, 0.1)
		end
	end)
	refresh()
end

function SettingsController.Init()
	requestRemote = Net.Get(Constants.Remotes.SettingsRequest)
	build(HudController.Gui :: ScreenGui)
end

function SettingsController.Start()
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 4) == "Set_" then
			refresh()
		end
	end)
end

return SettingsController
