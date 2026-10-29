--[[
	UiFxController: UI juice on top of PolishController's look (Config.Visuals.UiFx).
		- every HUD button squashes when pressed and springs back (and grows on mouse hover)
		- earned coins burst out of your character and fly into the coin counter,
		  which pops and shines when they land
		- the BONK button gets a shine sweep every few seconds
		- paper confetti bursts: a new Blockling (center), a rebirth or a round win (bottom corners)
		- screen-edge glow: a red heartbeat in the last 10 seconds of a round, and a flash in
		  the event's color when a server event starts
	All cosmetic and local.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Net = require(Shared:WaitForChild("Net"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local HudController = require(script.Parent:WaitForChild("HudController"))

local player = Players.LocalPlayer
local Colors = Ui.Colors
local rng = Random.new()

local UiFxController = {}

local MAX_FLYING = 40
local HOVER_SCALE = 1.06

local fxGui: ScreenGui
local flying = 0
local lastCoins: number? = nil
local quietUntil = 0 -- no coin bursts right after the profile loads
local lastBurstAt = 0

-- Press juice -------------------------------------------------------------------

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function juice(button: GuiButton)
	-- A button with its own UIScale is already animated by its owner (pulse / pop)
	if button:GetAttribute("NoJuice") or button:FindFirstChildOfClass("UIScale") then
		return
	end
	local scale = Ui.new("UIScale", { Name = "Press", Parent = button })
	local hovering, pressed = false, false
	local function to(value: number, seconds: number, style: Enum.EasingStyle)
		TweenService:Create(scale, TweenInfo.new(seconds, style, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	local function release()
		pressed = false
		to(if hovering then HOVER_SCALE else 1, 0.35, Enum.EasingStyle.Back)
	end
	button.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
			hovering = true
			if not pressed then
				to(HOVER_SCALE, 0.12, Enum.EasingStyle.Quad)
			end
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		pressed = false
		to(1, 0.15, Enum.EasingStyle.Quad)
	end)
	button.InputBegan:Connect(function(input)
		if isPress(input) then
			pressed = true
			to(0.9, 0.06, Enum.EasingStyle.Quad)
		end
	end)
	button.InputEnded:Connect(function(input)
		if pressed and isPress(input) then
			release()
		end
	end)
	button.Activated:Connect(function()
		if pressed then
			release()
		end
	end)
end

local function watchButtons(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") then
			juice(descendant)
		end
	end
	root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") then
			task.defer(juice, descendant) -- after its builder has added its own UIScale, if any
		end
	end)
end

-- Coins fly into the counter ------------------------------------------------------

local function coinHolder(): GuiObject?
	return (HudController.Gui :: ScreenGui):FindFirstChild("Coins") :: GuiObject?
end

-- Center of the coin icon at the left end of the coin pill
local function coinTarget(): Vector2?
	local holder = coinHolder()
	if not holder then
		return nil
	end
	local height = holder.AbsoluteSize.Y
	return holder.AbsolutePosition + Vector2.new(height * 0.5, height * 0.5)
end

local function coinPill(): GuiObject?
	local holder = coinHolder()
	if not holder then
		return nil
	end
	for _, child in holder:GetChildren() do
		if child:IsA("Frame") and child.Size == UDim2.fromScale(1, 1) and child:FindFirstChildOfClass("UICorner") then
			return child
		end
	end
	return nil
end

local function burstOrigin(): Vector2
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if camera and root then
		local point, onScreen = camera:WorldToScreenPoint(root.Position + Vector3.new(0, 2, 0))
		if onScreen then
			return Vector2.new(point.X, point.Y)
		end
	end
	local size = fxGui.AbsoluteSize
	return Vector2.new(size.X * 0.5, size.Y * 0.55)
end

local function landed()
	local pill = coinPill()
	if not pill then
		return
	end
	local pop = pill:FindFirstChildOfClass("UIScale")
	if pop then
		Ui.pop(pop, 0.12)
	end
	Ui.shine(pill)
end

local function flyCoins(count: number)
	local target = coinTarget()
	if not target then
		return
	end
	local origin = burstOrigin()
	local first = true
	for index = 1, count do
		if flying >= MAX_FLYING then
			break
		end
		flying += 1
		local size = rng:NextInteger(20, 28)
		local coin = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Colors.Gold,
			Rotation = rng:NextNumber(-30, 30),
			Parent = fxGui,
		}, { Ui.round(), Ui.stroke(2.5, Colors.GoldDark) })
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 240, 160),
			Parent = coin,
		}, { Ui.round() })

		local angle = rng:NextNumber(0, math.pi * 2)
		local spread = rng:NextNumber(36, 96)
		local burst = origin + Vector2.new(math.cos(angle) * spread, math.sin(angle) * spread * 0.7 - 24)
		task.spawn(function()
			Ui.tween(coin, 0.22, { Position = UDim2.fromOffset(burst.X, burst.Y) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			task.wait(0.22 + index * 0.035)
			local finish = coinTarget() or target
			Ui.tween(coin, 0.42, {
				Position = UDim2.fromOffset(finish.X, finish.Y),
				Size = UDim2.fromOffset(size * 0.6, size * 0.6),
				Rotation = coin.Rotation + 180,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.42)
			coin:Destroy()
			flying -= 1
			if first then
				first = false
				landed()
			end
		end)
	end
end

local function onCoinsChanged()
	local coins = ClientState.Coins()
	local previous = lastCoins
	lastCoins = coins
	if not ClientState.IsLoaded() or previous == nil or os.clock() < quietUntil then
		return
	end
	local delta = coins - previous
	if delta <= 0 or os.clock() - lastBurstAt < 0.12 or not (HudController.Gui :: ScreenGui).Enabled then
		return
	end
	lastBurstAt = os.clock()
	flyCoins(math.clamp(math.floor(math.log(delta, 2)) + 2, 3, 10))
end

-- Confetti --------------------------------------------------------------------------

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 110, 170),
	Color3.fromRGB(255, 215, 60),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(110, 220, 110),
	Color3.fromRGB(170, 130, 255),
	Color3.new(1, 1, 1),
}
local MAX_CONFETTI = 180
local GRAVITY = 1400 -- px/s^2

type Piece = {
	frame: Frame,
	position: Vector2,
	velocity: Vector2,
	width: number,
	spin: number,
	flip: number,
	age: number,
	life: number,
}
local pieces: { Piece } = {}

-- Paper confetti from a screen point. aim = degrees from straight up (+ = right),
-- spread = +/- degrees around it, power = launch speed in px/s.
local function confetti(origin: Vector2, count: number, power: number, aim: number, spread: number)
	for _ = 1, count do
		if #pieces >= MAX_CONFETTI then
			return
		end
		local width, height = rng:NextInteger(8, 14), rng:NextInteger(12, 20)
		local frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			Size = UDim2.fromOffset(width, height),
			BackgroundColor3 = CONFETTI_COLORS[rng:NextInteger(1, #CONFETTI_COLORS)],
			BorderSizePixel = 0,
			Rotation = rng:NextNumber(0, 360),
			Parent = fxGui,
		})
		local angle = math.rad(aim + rng:NextNumber(-spread, spread))
		local speed = rng:NextNumber(0.55, 1) * power
		table.insert(pieces, {
			frame = frame,
			position = origin,
			velocity = Vector2.new(math.sin(angle) * speed, -math.cos(angle) * speed),
			width = width,
			spin = rng:NextNumber(-540, 540),
			flip = rng:NextNumber(6, 12),
			age = 0,
			life = rng:NextNumber(1.6, 2.4),
		})
	end
end

local function stepConfetti(dt: number)
	for index = #pieces, 1, -1 do
		local piece = pieces[index]
		piece.age += dt
		piece.velocity = Vector2.new(piece.velocity.X * (1 - 1.5 * dt), piece.velocity.Y + GRAVITY * dt)
		piece.position += piece.velocity * dt
		local frame = piece.frame
		frame.Position = UDim2.fromOffset(piece.position.X, piece.position.Y)
		frame.Rotation += piece.spin * dt
		-- paper flutter: the width flips like a spinning card
		frame.Size = UDim2.fromOffset(math.max(2, piece.width * math.abs(math.cos(piece.age * piece.flip))), frame.Size.Y.Offset)
		frame.BackgroundTransparency = math.clamp((piece.age - piece.life + 0.4) / 0.4, 0, 1)
		if piece.age >= piece.life then
			frame:Destroy()
			table.remove(pieces, index)
		end
	end
end

-- Two cannons from the bottom corners, aimed at the middle of the screen
local function celebrate(count: number)
	local size = fxGui.AbsoluteSize
	confetti(Vector2.new(0, size.Y), count, 1500, 28, 14)
	confetti(Vector2.new(size.X, size.Y), count, 1500, -28, 14)
end

-- Screen-edge glow ----------------------------------------------------------------------

local edges: { Frame } = {}
local flashColor = Colors.Gold
local flashUntil = 0
local FLASH_SECONDS = 1.5

local function buildEdgeGlow()
	local glowGui = Ui.new("ScreenGui", {
		Name = "BonkEdgeGlow",
		ResetOnSpawn = false,
		IgnoreGuiInset = true, -- reach the very edges of the screen
		DisplayOrder = 4,
		Parent = player:WaitForChild("PlayerGui"),
	})
	-- { position, size, gradient rotation (the opaque side faces the screen edge) }
	for _, edge in {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.16), 90 },
		{ UDim2.fromScale(0, 0.84), UDim2.fromScale(1, 0.16), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.1, 1), 0 },
		{ UDim2.fromScale(0.9, 0), UDim2.fromScale(0.1, 1), 180 },
	} do
		table.insert(
			edges,
			Ui.new("Frame", {
				Position = edge[1],
				Size = edge[2],
				BackgroundColor3 = Colors.Bad,
				BorderSizePixel = 0,
				Visible = false,
				Parent = glowGui,
			}, {
				Ui.new("UIGradient", {
					Rotation = edge[3],
					Transparency = NumberSequence.new(0.2, 1),
				}),
			})
		)
	end
end

local function stepGlow()
	local strength, color = 0, Colors.Bad
	if ClientState.State() == Constants.RoundState.Active then
		local left = ClientState.TimeLeft()
		if left > 0 and left <= 10 then
			-- a heartbeat on every second tick, stronger as time runs out
			local beat = (left % 1) ^ 2
			strength = beat * (0.45 + 0.55 * (1 - left / 10))
		end
	end
	local flash = (flashUntil - os.clock()) / FLASH_SECONDS
	if flash > strength then
		strength, color = flash, flashColor
	end
	for _, frame in edges do
		frame.Visible = strength > 0.02
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 1 - math.clamp(strength, 0, 1) * 0.8
	end
end

local function onEventChanged()
	local name = ClientState.Event()
	if name == "" then
		return
	end
	local def = Config.Events.Defs[name]
	flashColor = if def and def.Color then def.Color else Colors.Gold
	flashUntil = os.clock() + FLASH_SECONDS
end

local function onRoundSummary(summary: any)
	if typeof(summary) ~= "table" then
		return
	end
	for _, entry in summary.players or {} do
		if entry.userId == player.UserId and entry.teamId ~= nil and entry.teamId == summary.winner then
			celebrate(45)
			return
		end
	end
end

-- Lifecycle -----------------------------------------------------------------------

function UiFxController.Init()
	fxGui = Ui.new("ScreenGui", {
		Name = "BonkUiFx",
		ResetOnSpawn = false,
		IgnoreGuiInset = false, -- same space as the HUD, so AbsolutePositions line up
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5, -- above the HUD, below the intro
		Parent = player:WaitForChild("PlayerGui"),
	})
end

function UiFxController.Start()
	if Config.Visuals.UiFx == false then
		return
	end
	local hud = HudController.Gui :: ScreenGui
	watchButtons(hud)

	lastCoins = if ClientState.IsLoaded() then ClientState.Coins() else nil
	quietUntil = os.clock() + 2
	ClientState.Changed:Connect(function(key)
		if key == Constants.PlayerAttr.Loaded then
			lastCoins = ClientState.Coins()
			quietUntil = os.clock() + 2
		elseif key == Constants.PlayerAttr.Coins then
			onCoinsChanged()
		end
	end)

	local swing = hud:FindFirstChild("SwingButton", true)
	if swing and swing:IsA("GuiObject") then
		Ui.shine(swing, 3.5)
	end

	-- Confetti: new Blockling / better mutation (center), rebirth and round wins (corners)
	Net.Get(Constants.Remotes.BlocklingFound).OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		local size = fxGui.AbsoluteSize
		local big = payload.isNew == true or payload.newMutation == true
		confetti(Vector2.new(size.X * 0.5, size.Y * 0.45), if big then 60 else 20, if big then 1000 else 700, 0, 180)
	end)
	Net.Get(Constants.Remotes.RoundSummary).OnClientEvent:Connect(onRoundSummary)
	local rebirths = ClientState.Rebirths()
	ClientState.Changed:Connect(function(key)
		if key == Constants.PlayerAttr.Rebirths then
			local now = ClientState.Rebirths()
			if now > rebirths and ClientState.IsLoaded() and os.clock() >= quietUntil then -- not the profile load
				celebrate(70)
			end
			rebirths = now
		elseif key == Constants.GameAttr.Event then
			onEventChanged()
		end
	end)

	buildEdgeGlow()
	RunService.RenderStepped:Connect(function(dt)
		if #pieces > 0 then
			stepConfetti(dt)
		end
		stepGlow()
	end)
end

return UiFxController
