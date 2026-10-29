--[[
	PetController: renders every player's equipped Blocklings as hopping pets.
	Purely cosmetic and client-side: reads each player's "Equipped" attribute
	(server-validated), so there's no physics or network cost per pet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Progression = require(Shared:WaitForChild("Progression"))

local BlocklingModel = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("BlocklingModel"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local PET_SCALE = 0.85
local SNAP_DISTANCE = 40
-- Root-space offsets per slot (+Z is behind the character)
local OFFSETS = { Vector3.new(2.8, 0, 2.2), Vector3.new(-2.8, 0, 2.2), Vector3.new(0, 0, 3.8) }

type PetSet = { key: string, models: { Model }, positions: { [number]: Vector3 } }

local PetController = {}

local folder: Folder
local pets: { [Player]: PetSet } = {}

local function clear(player: Player)
	local set = pets[player]
	if set then
		for _, model in set.models do
			model:Destroy()
		end
		pets[player] = nil
	end
end

local function rebuild(player: Player)
	local ids = ClientState.Equipped(player)
	local mutations = {}
	for _, id in ids do
		table.insert(mutations, ClientState.Mutation(id, player) or "-")
	end
	local key = table.concat(ids, ",") .. "|" .. table.concat(mutations, ",")
	local existing = pets[player]
	if existing and existing.key == key then
		return -- unchanged: don't respawn pets (DataService re-syncs attributes often)
	end
	clear(player)
	if #ids == 0 then
		return
	end
	local set: PetSet = { key = key, models = {}, positions = {} }
	for _, id in ids do
		if Progression.Species(id) and #set.models < #OFFSETS then
			local model = BlocklingModel.Build(id, PET_SCALE, false, ClientState.Mutation(id, player))
			model.Parent = folder
			table.insert(set.models, model)
		end
	end
	pets[player] = set
end

local function update(dt: number)
	local now = os.clock()
	local alpha = 1 - math.exp(-dt * 7)
	for player, set in pets do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and humanoid) then
			continue
		end
		local hip = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
		local groundY = root.Position.Y - hip - root.Size.Y / 2
		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)

		for index, model in set.models do
			local target = root.CFrame:PointToWorldSpace(OFFSETS[index])
			local current = set.positions[index]
			if not current or (current - target).Magnitude > SNAP_DISTANCE then
				current = target
			else
				current = current:Lerp(target, alpha)
			end
			set.positions[index] = current

			local bob = if moving then math.abs(math.sin(now * 9 + index)) * 0.7 else 0.12 + math.sin(now * 3 + index) * 0.12
			local position = Vector3.new(current.X, groundY + BlocklingModel.FootOffset(PET_SCALE) + bob, current.Z)
			local cframe = if flatLook.Magnitude > 0.01
				then CFrame.lookAt(position, position + flatLook)
				else CFrame.new(position)
			model:PivotTo(cframe)
			local body = model.PrimaryPart
			if body and body:GetAttribute("Rainbow") then
				body.Color = Color3.fromHSV((now * 0.25 + index * 0.13) % 1, 0.65, 1)
			end
		end
	end
end

local function watch(player: Player)
	player.AttributeChanged:Connect(function(name)
		-- rebuild() no-ops when nothing visible changed
		if name == Constants.PlayerAttr.Equipped or string.sub(name, 1, 4) == "BlM_" then
			rebuild(player)
		end
	end)
	player.CharacterAdded:Connect(function()
		local set = pets[player]
		if set then
			table.clear(set.positions) -- snap to the new character
		end
	end)
	rebuild(player)
end

function PetController.Init()
	folder = Instance.new("Folder")
	folder.Name = "BonkPets"
	folder.Parent = workspace
end

function PetController.Start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(clear)
	RunService.RenderStepped:Connect(update)
end

return PetController
