--[[
	HammerService: welds a hammer to every character and validates swings.

	SwingRequest carries intent only (plus an optional block hint). The server checks:
	rate limit, data loaded, round state, alive character, per-player cooldown,
	and finds the target itself using server-side positions and reach.

	Custom hammer: put a Model named Config.Hammer.ModelName in ServerStorage.BonkAssets.
	Its PrimaryPart is the grip; parts are made non-colliding and massless automatically.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local HammerPose = require(Shared.HammerPose)
local HammerStats = require(Shared.HammerStats)
local MathUtil = require(Shared.MathUtil)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local BlockService = require(script.Parent.BlockService)
local DataService = require(script.Parent.DataService)
local RoundService = require(script.Parent.RoundService)
local TeamService = require(script.Parent.TeamService)
local UpgradeService = require(script.Parent.UpgradeService)
local MovementGuard = require(script.Parent.Parent.Util.MovementGuard)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local HammerService = {}
HammerService.Swung = Signal.new() -- (player) every accepted swing, hit or miss
HammerService.PlayerBonked = Signal.new() -- (attacker, victim)

local limiter = RateLimiter.new("SwingRequest", Config.RateLimits.SwingRequest)
local lastSwing: { [Player]: number } = {}
local spawnedAt: { [Player]: number } = {}
local bonkableAt: { [Player]: number } = {}
local swingFxRemote, bonkRemote, bonkFxRemote

-- Player bonk -------------------------------------------------------------------

local function canBonk(attacker: Player, victim: Player, now: number): boolean
	local rules = Config.Hammer.PlayerBonk
	if victim == attacker or (bonkableAt[victim] or 0) > now then
		return false
	end
	if now - (spawnedAt[victim] or 0) < rules.SpawnProtection then
		return false
	end
	if rules.TeamsEnemiesOnly and RoundService.GetMode() == Constants.Mode.Teams then
		local attackerTeam, victimTeam = TeamService.GetTeamId(attacker), TeamService.GetTeamId(victim)
		if attackerTeam ~= nil and attackerTeam == victimTeam then
			return false
		end
	end
	return true
end

-- Nearest bonkable player in front of the attacker, within reach (center to center)
local function findPlayerTarget(attacker: Player, root: BasePart, reach: number): (Player?, BasePart?)
	local rules = Config.Hammer.PlayerBonk
	local now = os.clock()
	local look = MathUtil.flat(root.CFrame.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local best: Player?, bestRoot: BasePart?, bestDistance = nil, nil, math.huge
	for _, victim in Players:GetPlayers() do
		if not canBonk(attacker, victim, now) then
			continue
		end
		local character = victim.Character
		local victimRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (victimRoot and humanoid) or humanoid.Health <= 0 then
			continue
		end
		local offset = victimRoot.Position - root.Position
		local distance = offset.Magnitude
		local flatOffset = MathUtil.flat(offset)
		local inFront = flatOffset.Magnitude < 0.5 or look:Dot(flatOffset.Unit) >= 0.2
		if distance <= reach + rules.ReachBonus and inFront and distance < bestDistance then
			best, bestRoot, bestDistance = victim, victimRoot, distance
		end
	end
	return best, bestRoot
end

local function bonkPlayer(attacker: Player, root: BasePart, victim: Player, victimRoot: BasePart, knockback: number)
	local rules = Config.Hammer.PlayerBonk
	bonkableAt[victim] = os.clock() + rules.VictimCooldown
	local flatOffset = MathUtil.flat(victimRoot.Position - root.Position)
	local push = if flatOffset.Magnitude > 0.1 then flatOffset.Unit else MathUtil.flat(root.CFrame.LookVector).Unit
	local direction = (push + Vector3.yAxis * rules.UpwardBias).Unit
	local force = math.min(rules.MaxForce, rules.Force * math.sqrt(knockback / Config.Hammer.Knockback))
	MovementGuard.NoteTeleport(victim) -- a server-caused launch is not a speed hack
	bonkRemote:FireClient(victim, direction * force)
	bonkFxRemote:FireAllClients(victim.UserId, attacker.UserId)
	HammerService.PlayerBonked:Fire(attacker, victim)
end

-- Hammer model ------------------------------------------------------------------

local function prepareParts(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CastShadow = false
		end
	end
end

local function weld(a: BasePart, b: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = a
	constraint.Part1 = b
	constraint.Parent = a
end

-- Cartoon mallet built at the requested scale (no ScaleTo needed)
local function buildDefaultHammer(scale: number): Model
	local model = Instance.new("Model")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 4, 0.4) * scale
	handle.Color = Color3.fromRGB(150, 95, 55)
	handle.Material = Enum.Material.Wood
	handle.CFrame = CFrame.new()
	handle.Parent = model

	local headY = 2.2 * scale
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.6, 1.6, 2.6) * scale
	head.Color = Color3.fromRGB(255, 120, 170)
	head.Material = Enum.Material.SmoothPlastic
	head.CFrame = CFrame.new(0, headY, 0)
	head.Parent = model
	weld(handle, head)

	for _, z in { -1.3, 1.3 } do
		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Shape = Enum.PartType.Cylinder
		cap.Size = Vector3.new(0.35, 1.9, 1.9) * scale
		cap.Color = Color3.fromRGB(255, 240, 250)
		cap.Material = Enum.Material.SmoothPlastic
		cap.CFrame = CFrame.new(0, headY, z * scale) * CFrame.Angles(0, math.pi / 2, 0)
		cap.Parent = model
		weld(handle, cap)
	end

	-- Gold band where head meets handle, and a red grip wrap near the hand
	local band = Instance.new("Part")
	band.Name = "Band"
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(0.4, 0.62, 0.62) * scale
	band.Color = Color3.fromRGB(255, 205, 60)
	band.Material = Enum.Material.Foil
	band.CFrame = CFrame.new(0, 1.3 * scale, 0) * CFrame.Angles(0, 0, math.pi / 2)
	band.Parent = model
	weld(handle, band)

	local wrap = Instance.new("Part")
	wrap.Name = "GripWrap"
	wrap.Shape = Enum.PartType.Cylinder
	wrap.Size = Vector3.new(1.3, 0.5, 0.5) * scale
	wrap.Color = Color3.fromRGB(200, 60, 70)
	wrap.Material = Enum.Material.Fabric
	wrap.CFrame = CFrame.new(0, -1.2 * scale, 0) * CFrame.Angles(0, 0, math.pi / 2)
	wrap.Parent = model
	weld(handle, wrap)

	model.PrimaryPart = handle
	return model
end

local function buildHammer(scale: number): Model
	local assets = ServerStorage:FindFirstChild(Constants.AssetsFolder)
	local template = assets and assets:FindFirstChild(Config.Hammer.ModelName)
	if template and template:IsA("Model") and template.PrimaryPart then
		local model = template:Clone()
		if scale ~= 1 then
			model:ScaleTo(model:GetScale() * scale)
		end
		return model
	end
	return buildDefaultHammer(scale)
end

function HammerService.Equip(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local existing = character:FindFirstChild(Constants.HammerModelName)
	if existing then
		existing:Destroy()
	end

	local data = DataService.GetData(player)
	local stats = HammerStats.Compute(if data then data.upgrades else {})
	local model = buildHammer(stats.scale)
	model.Name = Constants.HammerModelName
	prepareParts(model)

	local handle = model.PrimaryPart :: BasePart
	local isR6 = hand.Name == "Right Arm"
	local grip = Instance.new("Weld")
	grip.Name = Constants.GripName
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = HammerPose.C0(isR6, HammerPose.Idle)
	grip.C1 = CFrame.new(0, -(handle.Size.Y / 2 - 0.35 * stats.scale), 0)
	grip:SetAttribute("R6", isR6)
	grip.Parent = handle

	model.Parent = character
end

-- Swings ----------------------------------------------------------------------

local function onSwingRequest(player: Player, hint: any)
	if not limiter:Allow(player) then
		return
	end
	local data = DataService.GetData(player)
	if not data then
		RateLimiter.Reject(player, "SwingRequest", "data not loaded")
		return
	end
	if not RoundService.IsCombatOpen() then
		RateLimiter.Reject(player, "SwingRequest", "combat closed")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (humanoid and root) or humanoid.Health <= 0 then
		return
	end
	if MovementGuard.IsFlagged(player) then
		RateLimiter.Reject(player, "SwingRequest", "movement violation")
		return
	end

	local stats = HammerStats.Compute(data.upgrades)
	local now = os.clock()
	local last = lastSwing[player]
	if last and now - last < stats.cooldown - Config.Hammer.CooldownTolerance then
		RateLimiter.Reject(player, "SwingRequest", "cooldown")
		return
	end
	lastSwing[player] = now
	HammerService.Swung:Fire(player)

	swingFxRemote:FireAllClients(player)

	local hintPart = if typeof(hint) == "Instance" and hint:IsA("BasePart") then hint else nil
	local target = BlockService.FindTarget(root.CFrame, stats.reach + Config.Hammer.ReachTolerance, hintPart)
	if target then
		BlockService.ApplyHit(target, player, stats.damage, stats.knockback, root.Position)
	elseif Config.Hammer.PlayerBonk.Enabled then
		local victim, victimRoot = findPlayerTarget(player, root, stats.reach + Config.Hammer.ReachTolerance)
		if victim and victimRoot then
			bonkPlayer(player, root, victim, victimRoot, stats.knockback)
		end
	end
end

-- Lifecycle -------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local function equipWhenReady()
		DataService.WhenLoaded(player, function()
			HammerService.Equip(player)
		end)
	end
	player.CharacterAdded:Connect(function(character)
		spawnedAt[player] = os.clock() -- spawn protection from player bonks
		character:WaitForChild("Humanoid", 5)
		equipWhenReady()
	end)
	if player.Character then
		spawnedAt[player] = os.clock()
	end
	-- Avatar packages can replace body parts after spawn; re-weld to the final hand.
	player.CharacterAppearanceLoaded:Connect(equipWhenReady)
	if player.Character then
		equipWhenReady()
	end
end

function HammerService.Init()
	swingFxRemote = Net.Get(Constants.UnreliableRemotes.SwingFx)
	bonkRemote = Net.Get(Constants.Remotes.PlayerBonk)
	bonkFxRemote = Net.Get(Constants.UnreliableRemotes.PlayerBonkFx)
end

function HammerService.Start()
	MovementGuard.Start()
	Net.Get(Constants.Remotes.SwingRequest).OnServerEvent:Connect(onSwingRequest)

	UpgradeService.Upgraded:Connect(function(player, upgradeId)
		if upgradeId == "size" then
			HammerService.Equip(player)
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		spawnedAt[player] = nil
		bonkableAt[player] = nil
	end)
end

return HammerService
