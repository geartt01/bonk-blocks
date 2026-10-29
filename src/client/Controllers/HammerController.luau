--[[
	HammerController: the big BONK button, input (tap / click / E / F / gamepad R2),
	local cooldown prediction, the swing animation and SwingRequest.

	Swing animation is swappable:
		Config.Hammer.SwingAnimationId = ""          -> tween the grip weld (default, no assets)
		Config.Hammer.SwingAnimationId = "rbxassetid://..." -> play that Animation instead
	(Animations on your own character replicate automatically, so remote players
	only run the tween fallback.)

	Hold the button/key to keep swinging at the cooldown rate.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local HammerPose = require(Shared:WaitForChild("HammerPose"))
local HammerStats = require(Shared:WaitForChild("HammerStats"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local Net = require(Shared:WaitForChild("Net"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local EffectsController = require(script.Parent:WaitForChild("EffectsController"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local player = Players.LocalPlayer

local SWING_KEYS = {
	[Enum.KeyCode.E] = true,
	[Enum.KeyCode.F] = true,
	[Enum.KeyCode.ButtonR2] = true,
	[Enum.KeyCode.ButtonX] = true,
}

local HammerController = {}

local swingRemote
local readyAt = 0
local cooldownLength = Config.Hammer.Cooldown
local held: { [any]: boolean } = {}
local button: TextButton
local gradient: UIGradient
local keyHint: TextLabel
local buttonPop: UIScale
local swingTokens: { [Weld]: {} } = setmetatable({}, { __mode = "k" }) :: any
local animationTrack: AnimationTrack? = nil
local trackOwner: Model? = nil
local firstHitHint: TextLabel
local landedFirstHit = false

-- Animation -------------------------------------------------------------------

local function getGrip(character: Model): Weld?
	local model = character:FindFirstChild(Constants.HammerModelName)
	local handle = model and (model :: Model).PrimaryPart
	local grip = handle and handle:FindFirstChild(Constants.GripName)
	return if grip and grip:IsA("Weld") then grip else nil
end

local function tweenSwing(grip: Weld)
	local token = {}
	swingTokens[grip] = token
	local isR6 = grip:GetAttribute("R6") == true

	local function step(angle: number, duration: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): boolean
		if swingTokens[grip] ~= token or not grip.Parent then
			return false
		end
		local tween = TweenService:Create(grip, TweenInfo.new(duration, style, direction), {
			C0 = HammerPose.C0(isR6, angle),
		})
		tween:Play()
		tween.Completed:Wait()
		return true
	end

	task.spawn(function()
		if not step(HammerPose.Windup, Config.Hammer.Windup, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) then
			return
		end
		if not step(HammerPose.Smash, HammerPose.SmashTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In) then
			return
		end
		task.wait(0.06)
		step(HammerPose.Idle, HammerPose.RecoverTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
end

local function playAnimation(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	if trackOwner ~= character or not animationTrack then
		local animation = Instance.new("Animation")
		animation.AnimationId = Config.Hammer.SwingAnimationId
		animationTrack = animator:LoadAnimation(animation)
		trackOwner = character
	end
	(animationTrack :: AnimationTrack):Play(0.05)
	return true
end

-- Swoosh ribbon on the hammer head, created locally on first swing
local trailUntil: { [Trail]: number } = setmetatable({}, { __mode = "k" }) :: any

local function getTrail(character: Model): Trail?
	local model = character:FindFirstChild(Constants.HammerModelName)
	if not model then
		return nil
	end
	local existing = model:FindFirstChild("BonkTrail", true)
	if existing and existing:IsA("Trail") then
		return existing
	end
	local head = model:FindFirstChild("Head", true) or (model :: Model).PrimaryPart
	if not (head and head:IsA("BasePart")) then
		return nil
	end
	local half = head.Size.Y / 2
	local top = Instance.new("Attachment")
	top.Name = "BonkTrailTop"
	top.Position = Vector3.new(0, half, 0)
	top.Parent = head
	local bottom = Instance.new("Attachment")
	bottom.Name = "BonkTrailBottom"
	bottom.Position = Vector3.new(0, -half, 0)
	bottom.Parent = head

	local trail = Instance.new("Trail")
	trail.Name = "BonkTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.18
	trail.MinLength = 0.05
	trail.LightEmission = 0.4
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 160, 200))
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.Enabled = false
	trail.Parent = head
	return trail
end

local function flashTrail(character: Model)
	if not Config.Vfx.SwingTrail then
		return
	end
	local trail = getTrail(character)
	if not trail then
		return
	end
	local duration = HammerPose.ImpactDelay() + 0.12
	trailUntil[trail] = os.clock() + duration
	trail.Enabled = true
	task.delay(duration, function()
		-- a newer swing may have extended the window
		if trail.Parent and os.clock() >= (trailUntil[trail] or 0) then
			trail.Enabled = false
		end
	end)
end

function HammerController.PlaySwingFor(character: Model, isLocal: boolean)
	flashTrail(character)
	if Config.Hammer.SwingAnimationId ~= "" then
		if isLocal then
			playAnimation(character)
		end
		return -- remote players' animations replicate on their own
	end
	local grip = getGrip(character)
	if grip then
		tweenSwing(grip)
	end
end

-- Swinging --------------------------------------------------------------------

local function findTarget(root: BasePart, reach: number): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, instance in CollectionService:GetTagged(Constants.Tags.Block) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			local distance = MathUtil.distanceToBox(instance.CFrame, instance.Size, root.Position)
			if distance <= reach and distance < bestDistance then
				best, bestDistance = instance, distance
			end
		end
	end
	return best
end

function HammerController.TrySwing()
	local now = os.clock()
	if now < readyAt then
		return
	end
	if not ClientState.IsLoaded() or not ClientState.IsCombatOpen() then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (character and humanoid and root) or humanoid.Health <= 0 then
		return
	end

	local stats = HammerStats.Compute(ClientState.Upgrades())
	cooldownLength = stats.cooldown
	readyAt = now + stats.cooldown

	local target = findTarget(root, stats.reach + 1)
	if target and Config.Hammer.AutoFaceTarget then
		local flatTarget = Vector3.new(target.Position.X, root.Position.Y, target.Position.Z)
		if (flatTarget - root.Position).Magnitude > 0.5 then
			root.CFrame = CFrame.lookAt(root.Position, flatTarget)
		end
	end

	HammerController.PlaySwingFor(character, true)
	SoundController.Play("Swing")
	Ui.pop(buttonPop, -0.12)

	task.delay(HammerPose.ImpactDelay(), function()
		swingRemote:FireServer(target)
		if target and target:IsDescendantOf(workspace) then
			EffectsController.PredictImpact(target, root.Position)
		end
	end)
end

-- UI --------------------------------------------------------------------------

local function layoutButton()
	local camera = workspace.CurrentCamera
	if not camera or not button then
		return
	end
	local viewport = camera.ViewportSize
	local minAxis = math.min(viewport.X, viewport.Y)
	local size = math.clamp(minAxis * 0.28, 96, 170) * (if Ui.isBig() then 1.25 else 1)
	button.Size = UDim2.fromOffset(size, size)
	if UserInputService.TouchEnabled then
		-- Sit left of Roblox's touch jump button
		local jumpReserve = if minAxis <= 500 then 110 else 190
		button.Position = UDim2.new(1, -jumpReserve, 1, -12)
	else
		button.Position = UDim2.new(1, -24, 1, -24)
	end
end

local function updateKeyHint()
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		keyHint.Text = ""
	elseif last.Name:find("Gamepad") then
		keyHint.Text = "R2"
	else
		keyHint.Text = "Click / E"
	end
end

local function buildButton(gui: ScreenGui)
	button = Ui.new("TextButton", {
		Name = "SwingButton",
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		Parent = gui,
	}, { Ui.round(), Ui.stroke(5, Color3.new(1, 1, 1)) })
	buttonPop = Ui.new("UIScale", { Parent = button })

	-- Cooldown fill: bottom half bright, top half dim, boundary slides with Offset
	local dim = Color3.fromRGB(130, 70, 30)
	local bright = Ui.Colors.Accent
	gradient = Ui.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, dim),
			ColorSequenceKeypoint.new(0.499, dim),
			ColorSequenceKeypoint.new(0.5, bright),
			ColorSequenceKeypoint.new(1, bright),
		}),
		Offset = Vector2.new(0, -0.5),
		Parent = button,
	})

	Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.8, 0.36),
		Text = "BONK!",
		Parent = button,
	})
	keyHint = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromScale(0.7, 0.14),
		TextColor3 = Color3.fromRGB(255, 235, 200),
		Parent = button,
	})

	-- First-timer hint (hidden after the first confirmed hit)
	firstHitHint = Ui.label({
		Name = "FirstHitHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromScale(1.7, 0.3),
		Text = if UserInputService.TouchEnabled then "TAP TO BONK!" else "CLICK TO BONK!",
		TextColor3 = Ui.Colors.Gold,
		TextStrokeTransparency = 0,
		Visible = false,
		Parent = button,
	})
	TweenService:Create(
		firstHitHint,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.new(0.5, 0, 0, -20) }
	):Play()

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			held[input] = true
			HammerController.TrySwing()
			-- Track the touch itself: InputEnded on the button won't fire if the finger slides off
			local connection
			connection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
					held[input] = nil
					connection:Disconnect()
				end
			end)
		end
	end)

	layoutButton()
	updateKeyHint()
end

local function updateFirstHitHint()
	local isNewPlayer = player:GetAttribute(Constants.PlayerAttr.TotalCrushed) == 0
	firstHitHint.Visible = not landedFirstHit
		and isNewPlayer
		and ClientState.IsLoaded()
		and ClientState.IsCombatOpen()
end

local function onRender()
	if not button then
		return
	end
	local remaining = math.clamp((readyAt - os.clock()) / cooldownLength, 0, 1)
	gradient.Offset = Vector2.new(0, remaining - 0.5)
	if next(held) and os.clock() >= readyAt then
		HammerController.TrySwing()
	end
end

-- Lifecycle -------------------------------------------------------------------

function HammerController.Init()
	swingRemote = Net.Get(Constants.Remotes.SwingRequest)
	buildButton(HudController.Gui :: ScreenGui)
end

function HammerController.Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or SWING_KEYS[input.KeyCode] then
			local key = if input.UserInputType == Enum.UserInputType.MouseButton1 then "Mouse" else input.KeyCode
			held[key] = true
			HammerController.TrySwing()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			held["Mouse"] = nil
		elseif SWING_KEYS[input.KeyCode] then
			held[input.KeyCode] = nil
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(held) -- alt-tab while holding shouldn't auto-swing forever
	end)
	UserInputService.LastInputTypeChanged:Connect(updateKeyHint)
	Ui.ScaleChanged:Connect(layoutButton)

	-- Someone bonked us: we own our character's physics, so the launch is applied here
	Net.Get(Constants.Remotes.PlayerBonk).OnClientEvent:Connect(function(velocity)
		if typeof(velocity) ~= "Vector3" or velocity.Magnitude > 80 then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = velocity
		end
	end)

	-- Other players' swings (cosmetic)
	Net.Get(Constants.UnreliableRemotes.SwingFx).OnClientEvent:Connect(function(swinger)
		if typeof(swinger) == "Instance" and swinger ~= player and swinger:IsA("Player") and swinger.Character then
			HammerController.PlaySwingFor(swinger.Character, false)
		end
	end)

	Net.Get(Constants.UnreliableRemotes.BlockHit).OnClientEvent:Connect(function(_part, _position, _dealt, attackerId)
		if attackerId == player.UserId and not landedFirstHit then
			landedFirstHit = true
			updateFirstHitHint()
		end
	end)
	ClientState.Changed:Connect(function(key)
		-- a debug "Reset me" makes us a new player again
		if key == Constants.PlayerAttr.TotalCrushed and player:GetAttribute(key) == 0 then
			landedFirstHit = false
		end
		updateFirstHitHint()
	end)
	updateFirstHitHint()

	player.CharacterAdded:Connect(function()
		animationTrack = nil
		trackOwner = nil
		table.clear(held)
	end)

	RunService.RenderStepped:Connect(onRender)
end

return HammerController
