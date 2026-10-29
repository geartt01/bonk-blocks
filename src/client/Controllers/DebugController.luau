--[[
	DebugController: Studio-only playtest buttons (right edge of the screen).
	Never built in a live game; the server also refuses DebugCommand outside Studio.
	F8 hides/shows the panel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Net = require(Shared:WaitForChild("Net"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local HudController = require(script.Parent:WaitForChild("HudController"))

local BUTTONS = {
	{ command = "coins", text = "+500 coins" },
	{ command = "coins10k", text = "+10k coins" },
	{ command = "skip", text = "Skip phase" },
	{ command = "block", text = "Drop block" },
	{ command = "blockling", text = "Get Blockling" },
	{ command = "daily", text = "Daily ready" },
	{ command = "quests", text = "Finish quests" },
	{ command = "event", text = "Start event" },
	{ command = "reset", text = "Reset me" },
}

local DebugController = {}

local holder: Frame? = nil

function DebugController.Init()
	if not RunService:IsStudio() then
		return
	end
	local remote = Net.Get(Constants.Remotes.DebugCommand)
	local frame = Ui.new("Frame", {
		Name = "DebugPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.4, 0),
		Size = UDim2.fromOffset(240, 26 + math.ceil(#BUTTONS / 2) * 42), -- two columns
		BackgroundColor3 = Ui.Colors.Panel,
		BackgroundTransparency = 0.2,
		Parent = HudController.Gui,
	}, { Ui.corner(12), Ui.stroke(2, Ui.Colors.Muted) })
	Ui.scaled(frame)
	Ui.label({
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 0, 18),
		Text = "STUDIO DEBUG (F8)",
		TextColor3 = Ui.Colors.Muted,
		Parent = frame,
	})
	for index, info in BUTTONS do
		local button = Ui.new("TextButton", {
			Position = UDim2.fromOffset(8 + ((index - 1) % 2) * 116, 26 + math.floor((index - 1) / 2) * 42),
			Size = UDim2.fromOffset(108, 36),
			BackgroundColor3 = Ui.Colors.PanelLight,
			Text = "",
			Parent = frame,
		}, { Ui.corner(8) })
		Ui.label({ Position = UDim2.fromOffset(4, 6), Size = UDim2.new(1, -8, 1, -12), Text = info.text, Parent = button })
		button.Activated:Connect(function()
			remote:FireServer(info.command)
		end)
	end
	holder = frame
end

function DebugController.Start()
	if not holder then
		return
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F8 and holder then
			holder.Visible = not holder.Visible
		end
	end)
end

return DebugController
