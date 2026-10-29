--[[
	Ui: tiny instance builder + responsive scaling for the HUD.

	Ui.scaled(frame) adds a UIScale that follows the viewport, so every widget is
	designed once at "phone landscape" size and grows on tablets/PC.
	Pop/bounce effects use a second, inner UIScale (UIScales multiply).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

local Ui = {}

Ui.Font = Enum.Font.FredokaOne
Ui.Colors = {
	Panel = Color3.fromRGB(38, 32, 64),
	PanelLight = Color3.fromRGB(62, 54, 104),
	Stroke = Color3.fromRGB(18, 14, 34),
	Text = Color3.new(1, 1, 1),
	Muted = Color3.fromRGB(170, 165, 200),
	Gold = Color3.fromRGB(255, 205, 60),
	GoldDark = Color3.fromRGB(190, 130, 20),
	Good = Color3.fromRGB(80, 210, 100),
	Bad = Color3.fromRGB(255, 90, 90),
	Disabled = Color3.fromRGB(90, 85, 115),
	Accent = Color3.fromRGB(255, 140, 40),
	Purple = Color3.fromRGB(120, 95, 255),
}

Ui.ScaleChanged = Signal.new() -- (scale)

function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Ui.corner(radius: number | UDim): UICorner
	return Ui.new("UICorner", {
		CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius :: number),
	})
end

function Ui.round(): UICorner
	return Ui.corner(UDim.new(0.5, 0))
end

function Ui.stroke(thickness: number, color: Color3?): UIStroke
	return Ui.new("UIStroke", {
		Thickness = thickness,
		Color = color or Ui.Colors.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Ui.Font,
		TextScaled = true,
		TextColor3 = Ui.Colors.Text,
		TextStrokeColor3 = Ui.Colors.Stroke,
		TextStrokeTransparency = 0.25,
		Text = "",
	}
	for key, value in props do
		defaults[key] = value
	end
	return Ui.new("TextLabel", defaults)
end

-- Responsive scale --------------------------------------------------------------

local scaleTargets: { UIScale } = {}
local currentScale = 1

local localPlayer = game:GetService("Players").LocalPlayer

-- "Big buttons" setting (saved in the profile, replicated as an attribute)
function Ui.isBig(): boolean
	return localPlayer ~= nil and localPlayer:GetAttribute("Set_bigui") == true
end

local function computeScale(): number
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 450), 0.7, 1.6)
	return if Ui.isBig() then scale * 1.2 else scale
end

local function refreshScale()
	currentScale = computeScale()
	for _, uiScale in scaleTargets do
		if uiScale.Parent then
			uiScale.Scale = currentScale
		end
	end
	Ui.ScaleChanged:Fire(currentScale)
end

function Ui.scaled(guiObject: GuiObject): UIScale
	local uiScale = Ui.new("UIScale", { Scale = currentScale, Parent = guiObject })
	table.insert(scaleTargets, uiScale)
	return uiScale
end

function Ui.getScale(): number
	return currentScale
end

local cameraConnection: RBXScriptConnection? = nil
local function bindCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	end
	refreshScale()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()
if localPlayer then
	localPlayer:GetAttributeChangedSignal("Set_bigui"):Connect(refreshScale)
end

-- Tweens ----------------------------------------------------------------------

function Ui.tween(
	instance: Instance,
	duration: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- Bounce an inner UIScale (not one created by Ui.scaled)
function Ui.pop(uiScale: UIScale, amount: number?)
	uiScale.Scale = 1 + (amount or 0.18)
	Ui.tween(uiScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Quick horizontal shake for "denied" feedback
function Ui.shake(guiObject: GuiObject)
	local origin = guiObject.Position
	task.spawn(function()
		for _, dx in { 8, -8, 6, -6, 3, 0 } do
			guiObject.Position = origin + UDim2.fromOffset(dx, 0)
			task.wait(0.03)
		end
		guiObject.Position = origin
	end)
end

-- Effects -----------------------------------------------------------------------

Ui.Rainbow = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 170)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 160, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 225, 70)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(110, 230, 120)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 190, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 110, 170)),
})
Ui.GoldShimmer = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 205, 60)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 250, 215)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 205, 60)),
	ColorSequenceKeypoint.new(0.85, Color3.fromRGB(200, 120, 20)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 205, 60)),
})

-- Diagonal light sweep across a rounded button/panel, every `period` seconds (nil = once).
-- It's a child Frame, so it works on objects that already have a UIGradient (gloss, cooldown).
function Ui.shine(guiObject: GuiObject, period: number?): Frame
	local shine = Ui.new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = guiObject.ZIndex,
	})
	local corner = guiObject:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = shine
	end
	local gradient = Ui.new("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.4),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0), -- parked off the left edge = invisible
		Parent = shine,
	})
	shine.Parent = guiObject
	task.spawn(function()
		while shine.Parent do
			gradient.Offset = Vector2.new(-1, 0)
			Ui.tween(gradient, 0.65, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			task.wait(0.7)
			if not period then
				shine:Destroy()
				break
			end
			task.wait(period)
		end
	end)
	return shine
end

-- Spinning multi-color border on a UIStroke (Ui.Rainbow, Ui.GoldShimmer, ...)
function Ui.animatedStroke(stroke: UIStroke, colors: ColorSequence?, seconds: number?): UIGradient
	stroke.Color = Color3.new(1, 1, 1) -- the gradient tints a white stroke
	local gradient = Ui.new("UIGradient", { Color = colors or Ui.Rainbow, Parent = stroke })
	TweenService:Create(
		gradient,
		TweenInfo.new(seconds or 3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Rotation = 360 }
	):Play()
	return gradient
end

return Ui
