--[[
	BlocklingModel: builds a Blockling as a small anchored Model (client-side only).
	Body cube + googly eyes + mouth + feet + an optional accessory from Config.
	Front faces -Z. Use Viewport() for UI portraits.

	Swap in real art later: if ReplicatedStorage.BonkAssets.Blocklings.<Id> exists
	(a Model with PrimaryPart), it's cloned instead of the procedural one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 70)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 230, 120)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 110, 255)),
})

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(20, 18, 30)
local SILHOUETTE = Color3.fromRGB(30, 26, 48)

local BlocklingModel = {}

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	if props then
		for key, value in props do
			(p :: any)[key] = value
		end
	end
	p.Parent = model
	return p
end

local function addAccessory(model: Model, accessory: string, s: number)
	if accessory == "Leaf" then
		part(model, "Leaf", Vector3.new(0.5, 0.1, 0.9) * s, CFrame.new(0.1 * s, 0.82 * s, 0) * CFrame.Angles(0, 0.6, 0.35), Color3.fromRGB(90, 200, 80))
	elseif accessory == "Horns" then
		for _, x in { -0.5, 0.5 } do
			part(model, "Horn", Vector3.new(0.22, 0.5, 0.22) * s, CFrame.new(x * s, 0.95 * s, 0) * CFrame.Angles(0, 0, -x * 0.6), Color3.fromRGB(250, 240, 220))
		end
	elseif accessory == "Spikes" then
		for _, z in { -0.45, 0, 0.45 } do
			part(model, "Spike", Vector3.one * 0.32 * s, CFrame.new(0, 0.78 * s, z * s) * CFrame.Angles(0, math.rad(45), math.rad(45)), Color3.fromRGB(240, 240, 255), { Material = Enum.Material.Glass })
		end
	elseif accessory == "Crown" then
		local gold = Color3.fromRGB(255, 210, 60)
		part(model, "CrownBase", Vector3.new(1.0, 0.22, 1.0) * s, CFrame.new(0, 0.82 * s, 0), gold, { Material = Enum.Material.Foil })
		for _, x in { -0.38, 0, 0.38 } do
			part(model, "CrownTip", Vector3.one * 0.24 * s, CFrame.new(x * s, 1.02 * s, -0.38 * s) * CFrame.Angles(0, 0, math.rad(45)), gold, { Material = Enum.Material.Foil })
		end
	elseif accessory == "Halo" then
		part(model, "Halo", Vector3.new(0.08, 1.2, 1.2) * s, CFrame.new(0, 1.25 * s, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 245, 170), {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
		})
	end
end

-- Sparkles + sheen for mutations. ViewportFrames don't render particles, so UI shows the
-- mutation as text; in the world, Rainbow bodies are color-cycled by PetController.
local function addMutation(body: BasePart, mutation: string, s: number)
	local def = Config.Blocklings.Mutations.Defs[mutation]
	if not def then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = if mutation == "Rainbow" then 14 else 8
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(1, 2.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * s), NumberSequenceKeypoint.new(1, 0) })
	emitter.LightEmission = 1
	emitter.Color = if mutation == "Rainbow" then RAINBOW else ColorSequence.new(def.Color)
	emitter.Parent = body
	body.Reflectance = 0.25
	if mutation == "Rainbow" then
		body:SetAttribute("Rainbow", true)
	end
end

-- silhouette = dark, featureless shape for not-yet-found species
function BlocklingModel.Build(speciesId: string, scale: number, silhouette: boolean?, mutation: string?): Model
	local assets = ReplicatedStorage:FindFirstChild("BonkAssets")
	local custom = assets and assets:FindFirstChild("Blocklings") and assets.Blocklings:FindFirstChild(speciesId)
	if not silhouette and custom and custom:IsA("Model") and custom.PrimaryPart then
		local clone = custom:Clone()
		clone:ScaleTo(clone:GetScale() * scale)
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		return clone
	end

	local species = Progression.Species(speciesId)
	local s = scale
	local model = Instance.new("Model")
	model.Name = "Blockling_" .. speciesId
	local color = if silhouette or not species then SILHOUETTE else species.Color
	local body = part(model, "Body", Vector3.new(1.6, 1.4, 1.6) * s, CFrame.new(), color, {
		Material = if silhouette or not species then Enum.Material.SmoothPlastic else species.Material,
	})
	model.PrimaryPart = body
	if silhouette or not species then
		return model
	end

	for _, x in { -0.36, 0.36 } do
		part(model, "Eye", Vector3.one * 0.46 * s, CFrame.new(x * s, 0.18 * s, -0.76 * s), WHITE, { Shape = Enum.PartType.Ball })
		part(model, "Pupil", Vector3.one * 0.22 * s, CFrame.new(x * s, 0.15 * s, -0.97 * s), BLACK, { Shape = Enum.PartType.Ball })
	end
	part(model, "Mouth", Vector3.new(0.46, 0.08, 0.05) * s, CFrame.new(0, -0.26 * s, -0.81 * s), BLACK)
	for _, x in { -0.45, 0.45 } do
		part(model, "Foot", Vector3.new(0.46, 0.25, 0.56) * s, CFrame.new(x * s, -0.8 * s, -0.1 * s), color:Lerp(BLACK, 0.3))
	end
	if species.Accessory then
		addAccessory(model, species.Accessory, s)
	end
	if mutation then
		addMutation(body, mutation, s)
	end
	return model
end

-- Distance from the model's pivot to the bottom of its feet (for ground placement)
function BlocklingModel.FootOffset(scale: number): number
	return 0.93 * scale
end

-- Portrait inside a GuiObject. Returns the ViewportFrame and the model (spin it if you like).
function BlocklingModel.Viewport(parent: GuiObject, speciesId: string, silhouette: boolean?): (ViewportFrame, Model)
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(190, 190, 200)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1, 1)
	local model = BlocklingModel.Build(speciesId, 1, silhouette)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(Vector3.new(1.7, 1.1, -3.8), Vector3.new(0, 0.15, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent
	return viewport, model
end

return BlocklingModel
