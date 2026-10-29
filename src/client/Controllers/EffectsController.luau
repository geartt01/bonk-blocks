--[[
	EffectsController: all the juice, client-only and purely cosmetic.
		- hit sparks, dust, damage numbers
		- crack stages (local tint + optional crack decals)
		- burst: shards, coin fountain that flies to each earner, "+N" popup, screen shake
	Nothing here affects the economy; the server already paid out before BlockBurst fires.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local Net = require(Shared:WaitForChild("Net"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local player = Players.LocalPlayer
local BlockAttr = Constants.BlockAttr
local rng = Random.new()

local GRAVITY = Vector3.new(0, -70, 0)
local COIN_FLIGHT = 0.55
local COIN_HOME = 0.35
local COIN_COLOR = Color3.fromRGB(255, 200, 40)

local EffectsController = {}

type CoinFx = {
	part: BasePart,
	origin: Vector3,
	velocity: Vector3,
	born: number,
	spin: number,
	target: Player?,
	flightEnd: Vector3?,
}

type BlockVisual = {
	baseColor: Color3,
	stage: number,
	decals: { Decal },
	connection: RBXScriptConnection,
	shadow: Part?,
	falling: boolean,
	fallSpeed: number,
	bar: BillboardGui?,
	fill: Frame?,
}

local LAND_FX_MIN_SPEED = 45 -- only real drops thud, not knockback hops

local fxFolder: Folder
local fxAttachment: Attachment
local sparkEmitter: ParticleEmitter
local dustEmitter: ParticleEmitter
local sparkleEmitter: ParticleEmitter
local coins: { CoinFx } = {}
local visuals: { [BasePart]: BlockVisual } = {}
local lastPredictedAt = 0

-- Particles ---------------------------------------------------------------------

local function makeEmitter(props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.LockedToPart = false
	emitter.SpreadAngle = Vector2.new(180, 180)
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = fxAttachment
	return emitter
end

local function emitAt(emitter: ParticleEmitter, position: Vector3, count: number)
	fxAttachment.WorldPosition = position
	emitter:Emit(count)
end

-- Floating text -----------------------------------------------------------------

local function floatingText(position: Vector3, text: string, color: Color3, height: number, rise: number, duration: number)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position + Vector3.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6))
	attachment.Parent = workspace.Terrain

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(height * 4, height)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 160
	billboard.Adornee = attachment
	billboard.Parent = attachment

	local label = Ui.label({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = color,
		TextStrokeTransparency = 0,
		Parent = billboard,
	})

	TweenService:Create(billboard, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, rise, 0),
	}):Play()
	TweenService:Create(
		label,
		TweenInfo.new(duration * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, duration * 0.6),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	Debris:AddItem(attachment, duration + 0.1)
end

-- Crack stages ------------------------------------------------------------------

local function stageFor(hp: number, maxHp: number): number
	local fraction = hp / maxHp
	local stage = 0
	for index, threshold in Config.Blocks.CrackStages do
		if fraction <= threshold then
			stage = index
		end
	end
	return stage
end

local function refreshStage(part: BasePart)
	local visual = visuals[part]
	if not visual then
		return
	end
	local hp, maxHp = part:GetAttribute(BlockAttr.HP), part:GetAttribute(BlockAttr.MaxHP)
	if typeof(hp) ~= "number" or typeof(maxHp) ~= "number" or maxHp <= 0 then
		return
	end
	local stage = stageFor(hp, maxHp)
	if stage == visual.stage then
		return
	end
	visual.stage = stage

	-- Local-only cosmetic override; the server never changes block color after spawn
	part.Color = visual.baseColor:Lerp(Color3.new(0, 0, 0), stage * 0.2)
	for _, decal in visual.decals do
		decal:Destroy()
	end
	table.clear(visual.decals)
	local textureId = Config.Vfx.CrackTextures[stage]
	if textureId and textureId ~= "" then
		for _, face in Enum.NormalId:GetEnumItems() do
			local decal = Instance.new("Decal")
			decal.Texture = textureId
			decal.Face = face
			decal.Parent = part
			table.insert(visual.decals, decal)
		end
	end
	if stage > 0 then
		emitAt(dustEmitter, part.Position, 10)
	end
end

-- Drop shadows & landing ----------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis (X) pointing up

local function makeShadow(): Part
	local shadow = Instance.new("Part")
	shadow.Name = "DropShadow"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Size = Vector3.new(0.05, 1, 1)
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Transparency = 1
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CastShadow = false
	shadow.Parent = fxFolder
	return shadow
end

local function onLanded(part: BasePart, fallSpeed: number)
	if fallSpeed < LAND_FX_MIN_SPEED then
		return
	end
	local bottom = part.Position - Vector3.new(0, part.Size.Y / 2, 0)
	emitAt(dustEmitter, bottom, math.clamp(math.floor(part.Size.X * 2), 8, 30))
	SoundController.PlayAt("Land", bottom)
	local shake = Config.Vfx.Shake.Land
	CameraController.ShakeAt(bottom, shake[1] * part.Size.X / 6, shake[2])
end

-- Shows where a falling block will land; also fires the landing thud.
local function updateDrops()
	if next(visuals) == nil then
		return
	end
	local filter: { Instance } = { fxFolder }
	local blocksFolder = workspace:FindFirstChild(Constants.BlocksFolder)
	if blocksFolder then
		table.insert(filter, blocksFolder)
	end
	rayParams.FilterDescendantsInstances = filter

	for part, visual in visuals do
		local velocityY = part.AssemblyLinearVelocity.Y
		if velocityY < -8 then
			visual.falling = true
			visual.fallSpeed = math.max(visual.fallSpeed, -velocityY)
		elseif visual.falling and velocityY > -2 then
			visual.falling = false
			onLanded(part, visual.fallSpeed)
			visual.fallSpeed = 0
		end

		local shadow = visual.shadow
		if not shadow then
			continue
		end
		local result = visual.falling and workspace:Raycast(part.Position, Vector3.new(0, -300, 0), rayParams)
		if result then
			local height = part.Position.Y - result.Position.Y
			local diameter = part.Size.X * math.clamp(1.2 - height / 80, 0.4, 1.1)
			shadow.Size = Vector3.new(0.05, diameter, diameter)
			shadow.CFrame = CFrame.new(result.Position + Vector3.new(0, 0.06, 0)) * FLAT
			shadow.Transparency = math.clamp(0.4 + height / 120, 0.4, 0.85)
		else
			shadow.Transparency = 1
		end
	end
end

-- Health bars -------------------------------------------------------------------
-- Hidden until the first hit, so a fresh drop stays clean.

local function makeHealthBar(part: BasePart): (BillboardGui, Frame)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BonkHealth"
	billboard.Adornee = part
	billboard.Size = UDim2.new(math.max(3, part.Size.X * 0.8), 0, 0.55, 0) -- studs
	billboard.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	billboard.Enabled = false
	local back = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.Colors.Stroke,
		Parent = billboard,
	}, { Ui.round(), Ui.stroke(2) })
	local fill = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.Colors.Good,
		Parent = back,
	}, { Ui.round() })
	billboard.Parent = fxFolder
	return billboard, fill
end

local function refreshHealthBar(part: BasePart)
	local visual = visuals[part]
	local bar, fill = visual and visual.bar, visual and visual.fill
	if not (bar and fill) then
		return
	end
	local hp, maxHp = part:GetAttribute(BlockAttr.HP), part:GetAttribute(BlockAttr.MaxHP)
	if typeof(hp) ~= "number" or typeof(maxHp) ~= "number" or maxHp <= 0 then
		return
	end
	local fraction = math.clamp(hp / maxHp, 0, 1)
	bar.Enabled = fraction < 1
	fill.BackgroundColor3 = if fraction > 0.5 then Ui.Colors.Good elseif fraction > 0.25 then Ui.Colors.Gold else Ui.Colors.Bad
	Ui.tween(fill, 0.15, { Size = UDim2.fromScale(fraction, 1) })
end

-- Block tracking ----------------------------------------------------------------

local function onBlockAdded(instance: Instance)
	if not instance:IsA("BasePart") or visuals[instance] then
		return
	end
	local part = instance :: BasePart
	local bar, fill
	if Config.Vfx.HealthBars then
		bar, fill = makeHealthBar(part)
	end
	visuals[part] = {
		baseColor = part.Color,
		stage = 0,
		decals = {},
		connection = part:GetAttributeChangedSignal(BlockAttr.HP):Connect(function()
			refreshStage(part)
			refreshHealthBar(part)
		end),
		shadow = if Config.Vfx.DropShadow then makeShadow() else nil,
		falling = false,
		fallSpeed = 0,
		bar = bar,
		fill = fill,
	}
	refreshStage(part)
	refreshHealthBar(part)
end

local function onBlockRemoved(instance: Instance)
	local visual = visuals[instance :: BasePart]
	if visual then
		visual.connection:Disconnect()
		if visual.shadow then
			visual.shadow:Destroy()
		end
		if visual.bar then
			visual.bar:Destroy()
		end
		visuals[instance :: BasePart] = nil
	end
end

-- Shards & coins ----------------------------------------------------------------

local function spawnShards(origin: Vector3, size: number, color: Color3)
	local edge = math.clamp(size * 0.22, 0.6, 3)
	for _ = 1, Config.Vfx.ShardCount do
		local shard = Instance.new("Part")
		shard.Size = Vector3.one * edge * rng:NextNumber(0.6, 1.1)
		shard.Color = color
		shard.Material = Enum.Material.SmoothPlastic
		shard.TopSurface = Enum.SurfaceType.Smooth
		shard.BottomSurface = Enum.SurfaceType.Smooth
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0.3, 0.4) -- can't shove the player
		shard.CFrame = CFrame.new(origin + rng:NextUnitVector() * size * 0.3)
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0)
		shard.Parent = fxFolder
		shard.AssemblyLinearVelocity = rng:NextUnitVector() * rng:NextNumber(15, 35) + Vector3.new(0, 25, 0)
		shard.AssemblyAngularVelocity = rng:NextUnitVector() * 12
		TweenService:Create(
			shard,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1),
			{ Transparency = 1 }
		):Play()
		Debris:AddItem(shard, 1.6)
	end
end

local function coinFountain(origin: Vector3, count: number, target: Player?)
	local now = os.clock()
	for i = 1, count do
		local coin = Instance.new("Part")
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.22, 1.1, 1.1)
		coin.Color = COIN_COLOR
		coin.Material = Enum.Material.SmoothPlastic
		coin.Reflectance = 0.15
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		coin.CastShadow = false
		coin.CFrame = CFrame.new(origin)
		coin.Parent = fxFolder

		local angle = rng:NextNumber(0, math.pi * 2)
		local speed = rng:NextNumber(6, 16)
		table.insert(coins, {
			part = coin,
			origin = origin,
			velocity = Vector3.new(math.cos(angle) * speed, rng:NextNumber(22, 34), math.sin(angle) * speed),
			born = now + (i - 1) * 0.012,
			spin = rng:NextNumber(8, 14),
			target = target,
		})
	end
end

local function updateCoins()
	if #coins == 0 then
		return
	end
	local now = os.clock()
	for i = #coins, 1, -1 do
		local coin = coins[i]
		local t = now - coin.born
		if t < 0 then
			continue
		end

		local position: Vector3
		local finished = false
		if t <= COIN_FLIGHT or not coin.target then
			position = coin.origin + coin.velocity * t + GRAVITY * (0.5 * t * t)
			finished = coin.target == nil and t > 1.2
		else
			if not coin.flightEnd then
				coin.flightEnd = coin.origin + coin.velocity * COIN_FLIGHT + GRAVITY * (0.5 * COIN_FLIGHT * COIN_FLIGHT)
			end
			local character = coin.target.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local alpha = math.min(1, (t - COIN_FLIGHT) / COIN_HOME)
				position = (coin.flightEnd :: Vector3):Lerp(root.Position + Vector3.new(0, 1.5, 0), alpha * alpha)
				finished = alpha >= 1
			else
				position = coin.flightEnd :: Vector3
				finished = true
			end
		end

		if finished then
			coin.part:Destroy()
			table.remove(coins, i)
		else
			coin.part.CFrame = CFrame.new(position) * CFrame.Angles(0, t * coin.spin, 0)
		end
	end
end

-- Impact frames -------------------------------------------------------------------
-- The anime "impact frame": one desaturated high-contrast frame + white pop + FOV punch.

local impactCorrection: ColorCorrectionEffect
local impactFlash: Frame
local impactGui: ScreenGui -- only Enabled during a flash, so it can never swallow clicks
local impactToken = 0
local baseFov: number? = nil

local function impactFrame(strength: number)
	if not Config.Vfx.ImpactFrames or player:GetAttribute("Set_shake") == false then
		return
	end
	impactToken += 1
	local token = impactToken
	impactCorrection.Saturation = -1
	impactCorrection.Contrast = 0.5 * strength
	impactCorrection.Brightness = 0.08 * strength
	impactGui.Enabled = true
	impactFlash.BackgroundTransparency = 1 - math.min(0.5, 0.3 * strength)
	local camera = workspace.CurrentCamera
	if camera then
		baseFov = baseFov or camera.FieldOfView
		camera.FieldOfView = (baseFov :: number) + 5 * strength
		TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = baseFov,
		}):Play()
	end
	task.delay(0.05 * strength, function()
		if impactToken ~= token then
			return
		end
		TweenService:Create(impactCorrection, TweenInfo.new(0.2), { Saturation = 0, Contrast = 0, Brightness = 0 }):Play()
		TweenService:Create(impactFlash, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		task.delay(0.2, function()
			if impactToken == token then
				impactGui.Enabled = false
			end
		end)
	end)
end

-- Crusher chomp -------------------------------------------------------------------

local visualHomes: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function crusherChomp(position: Vector3, teamId: string?)
	-- Parts tagged CrusherVisual dip and spring back (local-only CFrame tween)
	for _, instance in CollectionService:GetTagged(Constants.Tags.CrusherVisual) do
		if instance:IsA("BasePart") then
			local partTeam = instance:GetAttribute("Team")
			if partTeam == nil or teamId == nil or teamId == "Crew" or partTeam == teamId then
				local home = visualHomes[instance] or instance.CFrame
				visualHomes[instance] = home
				instance.CFrame = home * CFrame.new(0, -1.2, 0)
				TweenService:Create(instance, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					CFrame = home,
				}):Play()
			end
		end
	end
	-- Dust along the crusher volume that ate the block
	for _, instance in CollectionService:GetTagged(Constants.Tags.Crusher) do
		if instance:IsA("BasePart") and MathUtil.isInsideBox(instance.CFrame, instance.Size, position) then
			local half = instance.Size / 2
			for _ = 1, 6 do
				local point = Vector3.new(rng:NextNumber(-half.X, half.X), -half.Y + 1, rng:NextNumber(-half.Z, half.Z))
				emitAt(dustEmitter, instance.CFrame:PointToWorldSpace(point), 6)
			end
			emitAt(sparkleEmitter, instance.CFrame:PointToWorldSpace(Vector3.new(0, -half.Y + 2, 0)), 25)
			break
		end
	end
end

-- Remote handlers -------------------------------------------------------------

local function onBlockHit(part: any, hitPosition: any, dealt: any, attackerId: any)
	if typeof(hitPosition) ~= "Vector3" then
		return
	end
	local mine = attackerId == player.UserId
	-- Our own swing already got a predicted spark/shake: don't double up
	if not (mine and os.clock() - lastPredictedAt < 0.6) then
		emitAt(sparkEmitter, hitPosition, 14)
		emitAt(dustEmitter, hitPosition, 5)
		SoundController.PlayAt("Hit", hitPosition)
		if mine then
			CameraController.Shake(Config.Vfx.Shake.Hit[1], Config.Vfx.Shake.Hit[2])
		end
	end
	if Config.Vfx.DamageNumbers and typeof(dealt) == "number" and dealt > 0 then
		floatingText(
			hitPosition,
			tostring(math.floor(dealt + 0.5)),
			if mine then Color3.new(1, 1, 1) else Color3.fromRGB(200, 200, 220),
			if mine then 34 else 24,
			3,
			0.8
		)
	end
	if typeof(part) == "Instance" and part:IsA("BasePart") then
		refreshStage(part)
	end
end

local function onBurst(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.position) ~= "Vector3" then
		return
	end
	local position: Vector3 = payload.position
	local size: number = if typeof(payload.size) == "number" then payload.size else 6
	local color: Color3 = if typeof(payload.color) == "Color3" then payload.color else Color3.new(1, 1, 1)
	local reason = payload.reason

	if reason == "Despawn" then
		emitAt(dustEmitter, position, 20)
		SoundController.PlayAt("Poof", position)
		return
	end

	if reason == "Crush" then
		crusherChomp(position, if typeof(payload.teamId) == "string" then payload.teamId else nil)
	end
	spawnShards(position, size, color)
	emitAt(sparkEmitter, position, 30)
	emitAt(dustEmitter, position, 18)
	emitAt(sparkleEmitter, position, 20)
	SoundController.PlayAt(if reason == "Crush" then "Crush" else "Crack", position)
	local shake = if reason == "Crush" then Config.Vfx.Shake.Crush else Config.Vfx.Shake.Crack
	CameraController.ShakeAt(position, shake[1], shake[2])

	local payouts = if typeof(payload.payouts) == "table" then payload.payouts else {}
	local total = 0
	for _, payout in payouts do
		total += payout.coins
	end
	local visualCount = math.clamp(math.floor(total / 3), 6, Config.Vfx.CoinFountainMax)
	if #payouts == 0 then
		coinFountain(position, 6, nil)
	end
	for _, payout in payouts do
		local count = math.max(2, math.floor(visualCount * payout.coins / math.max(total, 1)))
		coinFountain(position, count, Players:GetPlayerByUserId(payout.userId))
		if payout.userId == player.UserId and payout.coins > 0 then
			if payload.kind ~= "Meteor" then
				impactFrame(if payload.kind == "Mega" then 1.8 else 1)
			end
			floatingText(position + Vector3.new(0, size * 0.6, 0), "+" .. MathUtil.formatNumber(payout.coins), Ui.Colors.Gold, 56, 5, 1.3)
			task.delay(COIN_FLIGHT + COIN_HOME, function()
				SoundController.Play("Coin")
			end)
		end
	end

	if reason == "Crush" and typeof(payload.teamId) == "string" then
		local def = Config.Teams[payload.teamId]
		local text = if typeof(payload.points) == "number" then `+{payload.points} CRUSHED!` else "CRUSHED!"
		floatingText(position + Vector3.new(0, size, 0), text, if def then def.Color else Ui.Colors.Text, 64, 7, 1.4)
	end
end

-- Victory confetti over the local character when their team (or the crew) wins
local confettiEmitter: ParticleEmitter

local function onRoundSummary(summary: any)
	if not Config.Vfx.VictoryConfetti or typeof(summary) ~= "table" then
		return
	end
	local myTeam
	for _, entry in summary.players or {} do
		if entry.userId == player.UserId then
			myTeam = entry.teamId
		end
	end
	if not myTeam or summary.winner ~= myTeam then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	for i = 0, 2 do
		task.delay(i * 0.35, function()
			fxAttachment.WorldPosition = root.Position + Vector3.new(0, 8, 0)
			confettiEmitter:Emit(60)
		end)
	end
	SoundController.Play("RoundStart")
end

-- Local prediction for our own swing (instant feedback before the server answers)
function EffectsController.PredictImpact(part: BasePart, fromPosition: Vector3)
	lastPredictedAt = os.clock()
	local hitPosition = MathUtil.closestPointOnBox(part.CFrame, part.Size, fromPosition)
	emitAt(sparkEmitter, hitPosition, 14)
	emitAt(dustEmitter, hitPosition, 5)
	SoundController.PlayAt("Hit", hitPosition)
	CameraController.Shake(Config.Vfx.Shake.Hit[1], Config.Vfx.Shake.Hit[2])
end

-- Lifecycle -------------------------------------------------------------------

function EffectsController.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "BonkFx"
	fxFolder.Parent = workspace

	fxAttachment = Instance.new("Attachment")
	fxAttachment.Name = "BonkFxEmitter"
	fxAttachment.Parent = workspace.Terrain

	impactCorrection = Instance.new("ColorCorrectionEffect")
	impactCorrection.Name = "BonkImpact"
	impactCorrection.Parent = Lighting
	local flashGui = Instance.new("ScreenGui")
	flashGui.Name = "BonkImpactFlash"
	flashGui.IgnoreGuiInset = true
	flashGui.ResetOnSpawn = false
	flashGui.DisplayOrder = 5
	flashGui.Enabled = false
	impactGui = flashGui
	impactFlash = Instance.new("Frame")
	impactFlash.Size = UDim2.fromScale(1, 1)
	impactFlash.BackgroundColor3 = Color3.new(1, 1, 1)
	impactFlash.BackgroundTransparency = 1
	impactFlash.BorderSizePixel = 0
	impactFlash.Active = false
	impactFlash.Parent = flashGui
	flashGui.Parent = player:WaitForChild("PlayerGui")

	sparkEmitter = makeEmitter({
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 245, 200)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.25, 0.45),
		Speed = NumberRange.new(18, 30),
		Drag = 6,
	})
	dustEmitter = makeEmitter({
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(235, 225, 205)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(4, 10),
		Drag = 3,
	})
	sparkleEmitter = makeEmitter({
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(COIN_COLOR),
		LightEmission = 0.8,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(8, 16),
		Acceleration = Vector3.new(0, -20, 0),
	})
	confettiEmitter = makeEmitter({
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 140)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 210, 60)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 230, 120)),
		}),
		Size = NumberSequence.new(0.7),
		Lifetime = NumberRange.new(1.4, 2.2),
		Speed = NumberRange.new(12, 22),
		RotSpeed = NumberRange.new(-300, 300),
		Rotation = NumberRange.new(0, 360),
		Acceleration = Vector3.new(0, -14, 0),
		Drag = 1.5,
	})
end

function EffectsController.Start()
	CollectionService:GetInstanceAddedSignal(Constants.Tags.Block):Connect(onBlockAdded)
	CollectionService:GetInstanceRemovedSignal(Constants.Tags.Block):Connect(onBlockRemoved)
	for _, instance in CollectionService:GetTagged(Constants.Tags.Block) do
		onBlockAdded(instance)
	end

	Net.Get(Constants.UnreliableRemotes.BlockHit).OnClientEvent:Connect(onBlockHit)
	Net.Get(Constants.Remotes.BlockBurst).OnClientEvent:Connect(onBurst)
	Net.Get(Constants.Remotes.RoundSummary).OnClientEvent:Connect(onRoundSummary)

	-- Player bonks: "BONK!" over the victim, sparks, and a shake if it was us
	Net.Get(Constants.UnreliableRemotes.PlayerBonkFx).OnClientEvent:Connect(function(victimId, attackerId)
		local victim = typeof(victimId) == "number" and Players:GetPlayerByUserId(victimId)
		local character = victim and victim.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if not head then
			return
		end
		local position = head.Position + Vector3.new(0, 1.5, 0)
		emitAt(sparkEmitter, head.Position, 18)
		SoundController.PlayAt("Hit", head.Position)
		floatingText(position, "BONK!", Color3.fromRGB(255, 120, 170), 48, 4, 0.9)
		if victimId == player.UserId then
			CameraController.Shake(Config.Vfx.Shake.Crack[1], Config.Vfx.Shake.Crack[2])
		elseif attackerId == player.UserId then
			CameraController.Shake(Config.Vfx.Shake.Hit[1], Config.Vfx.Shake.Hit[2])
		end
	end)
	RunService.RenderStepped:Connect(function()
		updateCoins()
		updateDrops()
	end)
end

return EffectsController
