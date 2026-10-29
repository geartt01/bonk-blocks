--[[
	AmbientController: makes the world feel alive, client-side only (anchored parts).
		tag "Spin"  attributes SpinSpeed (deg/s), SpinAxis ("Y" = world up, default = the part's own X axis)
		tag "Bob"   attributes BobHeight (studs), BobSpeed (cycles/s)
		tag "Orbit" attributes OrbitCenter (Vector3), OrbitSpeed (deg/s): circles the center around world up
	Crusher rollers spin, floating mystery blocks bob and turn, the blimp circles the stadium.
	Multi-part props (sky islands, blimp) are one anchored root with the rest welded to it,
	so moving the root moves the whole prop. The server never moves these.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local AmbientController = {}

type Entry = { base: CFrame, phase: number }
local entries: { [BasePart]: Entry } = {}

local function add(instance: Instance)
	if instance:IsA("BasePart") and not entries[instance] then
		entries[instance] = { base = instance.CFrame, phase = math.random() * 10 }
	end
end

local function update()
	local t = os.clock()
	for part, entry in entries do
		if not part.Parent then
			entries[part] = nil
			continue
		end
		local cframe = entry.base
		if CollectionService:HasTag(part, "Bob") then
			local height = part:GetAttribute("BobHeight") or 2
			local speed = part:GetAttribute("BobSpeed") or 0.5
			cframe += Vector3.new(0, math.sin((t + entry.phase) * speed * math.pi * 2) * height, 0)
		end
		if CollectionService:HasTag(part, "Spin") then
			local angle = (t * math.rad(part:GetAttribute("SpinSpeed") or 30)) % (math.pi * 2)
			if part:GetAttribute("SpinAxis") == "Y" then
				cframe = CFrame.new(cframe.Position) * CFrame.Angles(0, angle, 0) * (cframe - cframe.Position)
			else
				cframe *= CFrame.Angles(angle, 0, 0)
			end
		end
		if CollectionService:HasTag(part, "Orbit") then
			local center = part:GetAttribute("OrbitCenter")
			if typeof(center) == "Vector3" then
				local angle = (t * math.rad(part:GetAttribute("OrbitSpeed") or 5)) % (math.pi * 2)
				cframe = CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(-center) * cframe
			end
		end
		part.CFrame = cframe
	end
end

function AmbientController.Start()
	for _, tag in { "Spin", "Bob", "Orbit" } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(add)
		for _, instance in CollectionService:GetTagged(tag) do
			add(instance)
		end
	end
	RunService.RenderStepped:Connect(update)
end

return AmbientController
