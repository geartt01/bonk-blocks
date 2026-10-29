--[[
	PolishController: one consistent "glossy cartoon" look for the whole HUD, applied
	automatically (Config.Visuals.UiPolish):
		- rounded, mostly opaque Frames/TextButtons get a soft top-to-bottom shading gradient
		- big panels get a drop shadow
	Runs last and also polishes UI created later (toasts, cards). Elements that already
	have a UIGradient (e.g. the BONK cooldown fill) are left alone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HudController = require(script.Parent:WaitForChild("HudController"))

local PolishController = {}

local GLOSS = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(198, 198, 212))
local SHADOWED = {
	UpgradePanel = true,
	CollectionPanel = true,
	DailyPopup = true,
	RebirthModal = true,
	Summary = true,
	BlocklingReveal = true,
	SettingsPanel = true,
	ReleaseCard = true,
}

local function gloss(object: GuiObject)
	if object:FindFirstChildOfClass("UIGradient") or not object:FindFirstChildOfClass("UICorner") then
		return
	end
	if object.BackgroundTransparency > 0.3 then
		return
	end
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Gloss"
	gradient.Color = GLOSS
	gradient.Rotation = 90
	gradient.Parent = object
end

local function shadow(holder: Instance)
	if holder:FindFirstChild("Shadow") then
		return
	end
	for _, child in holder:GetChildren() do
		local corner = child:FindFirstChildOfClass("UICorner")
		if (child:IsA("Frame") or child:IsA("TextButton")) and corner then
			local card = child :: GuiObject
			local drop = Instance.new("Frame")
			drop.Name = "Shadow"
			drop.AnchorPoint = card.AnchorPoint
			drop.Position = card.Position + UDim2.fromOffset(6, 7)
			drop.Size = card.Size
			drop.BackgroundColor3 = Color3.new(0, 0, 0)
			drop.BackgroundTransparency = 0.55
			drop.BorderSizePixel = 0
			drop.ZIndex = math.max(0, card.ZIndex - 1)
			corner:Clone().Parent = drop
			drop.Parent = holder
			return
		end
	end
end

local function polish(instance: Instance)
	if instance:IsA("Frame") or instance:IsA("TextButton") then
		if instance.Name ~= "Shadow" then
			gloss(instance)
		end
		if SHADOWED[instance.Name] then
			shadow(instance)
		end
	end
end

function PolishController.Start()
	if not Config.Visuals.UiPolish then
		return
	end
	local gui = HudController.Gui :: ScreenGui
	for _, descendant in gui:GetDescendants() do
		polish(descendant)
	end
	gui.DescendantAdded:Connect(function(descendant)
		task.defer(polish, descendant)
	end)
	-- the intro screen lives in its own ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local intro = playerGui:FindFirstChild("BonkIntro")
	if intro then
		for _, descendant in intro:GetDescendants() do
			polish(descendant)
		end
	end
end

return PolishController
