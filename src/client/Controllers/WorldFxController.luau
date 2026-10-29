--[[
	WorldFxController: last-layer world VFX, all client-side (nothing here replicates).
		- soft pastel sparkles drifting up over the court (Config.Vfx.AmbientSparkles)
		- fireworks over the stadium when a round ends, in the winning team's color
		  (rainbow for co-op wins and draws) (Config.Vfx.Fireworks)
	Uses Roblox's built-in sparkle texture, so no uploaded assets are needed.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Net = require(Shared:WaitForChild("Net"))

local WorldFxController = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 170)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 215, 60)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 130, 255)),
})
local rng = Random.new()

-- The court: the block spawn zone hovers 38 studs over the floor (see DevArena)
local function court(): (Vector3?, Vector3?)
	local zone = CollectionService:GetTagged(Constants.Tags.BlockSpawnZone)[1]
	if zone and zone:IsA("BasePart") then
		return zone.Position - Vector3.new(0, 38, 0), zone.Size
	end
	return nil, nil
end

local function localPart(name: string, size: Vector3, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.Position = position
	part.Parent = workspace
	return part
end

local function buildSparkles()
	local floor, size = court()
	if not floor or not size then
		return
	end
	local part = localPart("BonkSparkles", Vector3.new(size.X, 1, size.Z), floor + Vector3.new(0, 4, 0))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = RAINBOW
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.25)
	emitter.Lifetime = NumberRange.new(5, 8)
	emitter.Rate = 28
	emitter.Speed = NumberRange.new(1, 3)
	emitter.Acceleration = Vector3.new(0, 1.2, 0)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Parent = part
end

local function firework(target: Vector3, color: ColorSequence)
	local rocket = localPart("BonkFirework", Vector3.one * 1.4, target - Vector3.new(0, 55, 0))
	rocket.Shape = Enum.PartType.Ball
	rocket.Material = Enum.Material.Neon
	rocket.Color = Color3.new(1, 1, 1)
	rocket.Transparency = 0
	local attachment = Instance.new("Attachment")
	attachment.Parent = rocket

	local trail = Instance.new("ParticleEmitter")
	trail.Texture = SPARKLE
	trail.LightEmission = 1
	trail.Size = NumberSequence.new(0.8, 0)
	trail.Lifetime = NumberRange.new(0.4, 0.7)
	trail.Rate = 70
	trail.Speed = NumberRange.new(0, 1)
	trail.Parent = attachment

	local burst = Instance.new("ParticleEmitter")
	burst.Texture = SPARKLE
	burst.Color = color
	burst.LightEmission = 1
	burst.LightInfluence = 0
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) })
	burst.Lifetime = NumberRange.new(1.3, 2.1)
	burst.Speed = NumberRange.new(32, 52)
	burst.Drag = 2.4
	burst.Acceleration = Vector3.new(0, -14, 0)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 0
	burst.Parent = attachment

	local light = Instance.new("PointLight")
	light.Range = 45
	light.Brightness = 0
	light.Color = color.Keypoints[1].Value
	light.Parent = rocket

	local rise = 0.9
	TweenService:Create(rocket, TweenInfo.new(rise, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
	task.delay(rise, function()
		if not rocket.Parent then
			return
		end
		trail.Enabled = false
		rocket.Transparency = 1
		burst:Emit(90)
		light.Brightness = 6
		TweenService:Create(light, TweenInfo.new(0.7), { Brightness = 0 }):Play()
	end)
	Debris:AddItem(rocket, rise + 3)
end

local function onRoundSummary(summary: any)
	if typeof(summary) ~= "table" then
		return
	end
	local floor, size = court()
	if not floor or not size then
		return
	end
	local team = Config.Teams[summary.winner]
	local color = if team then ColorSequence.new(team.Color, Color3.new(1, 1, 1)) else RAINBOW
	for i = 0, 7 do
		task.delay(i * 0.28, function()
			local offset = Vector3.new(rng:NextNumber(-0.45, 0.45) * size.X, rng:NextNumber(65, 95), rng:NextNumber(-0.45, 0.45) * size.Z)
			firework(floor + offset, color)
		end)
	end
end

function WorldFxController.Start()
	if Config.Vfx.AmbientSparkles ~= false then
		task.spawn(function()
			-- the arena is built by the server; wait for its spawn zone to replicate
			local deadline = os.clock() + 15
			while not court() and os.clock() < deadline do
				task.wait(0.5)
			end
			buildSparkles()
		end)
	end
	if Config.Vfx.Fireworks ~= false then
		Net.Get(Constants.Remotes.RoundSummary).OnClientEvent:Connect(onRoundSummary)
	end
end

return WorldFxController
