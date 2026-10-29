--[[
	BlockService: spawns mystery blocks, owns their HP and physics, detects crushers,
	and pays contributors exactly once per block.

	"Crack for cash, crush for points":
		Crack  HP hits 0 in the open -> coins to contributors (split by damage dealt)
		Crush  block center enters a Crusher volume -> team score (RoundService)
		       + coins, with CrusherCoinMultiplier for contributors on that team
		Despawn fell out / idle too long / round cleanup -> nothing

	Blocks are server-owned physics (SetNetworkOwner(nil)) so clients can't fling them.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local MathUtil = require(Shared.MathUtil)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local ArenaService = require(script.Parent.ArenaService)
local CoinService = require(script.Parent.CoinService)
local DataService = require(script.Parent.DataService)
local TeamService = require(script.Parent.TeamService)

local BlockAttr = Constants.BlockAttr
local BlockConfig = Config.Blocks

export type BlockState = {
	id: number,
	part: BasePart,
	maxHp: number,
	hp: number,
	coins: number,
	points: number,
	heft: number,
	variant: string,
	damageBy: { [number]: number }, -- userId -> effective damage dealt
	spawnedAt: number,
	lastHitAt: number,
	resolved: boolean,
	welcome: boolean,
	kind: string?, -- nil = regular round block; "Mega" / "Meteor" = event blocks
}

type SpawnOptions = {
	progress: number?,
	position: Vector3?,
	welcome: boolean?,
	kind: string?,
	variantId: string?, -- force a variant ("Golden", ...)
	custom: { size: number, health: number, coins: number, points: number, heft: number }?,
	color: Color3?, -- procedural blocks only
	label: string?, -- procedural blocks only
}

type PayoutResult = { player: Player, userId: number, coins: number }

local BlockService = {}
BlockService.BlockHit = Signal.new() -- (state, attacker: Player, damageDealt: number)
BlockService.BlockResolved = Signal.new() -- (state, reason, scoringTeam: string?, payouts: { PayoutResult })

local blocksFolder: Folder
local byPart: { [BasePart]: BlockState } = {}
local active: { BlockState } = {}
local nextId = 0
local spawnerToken = 0
local rng = Random.new()
local burstRemote, hitRemote, notifyRemote

-- RoundService replaces this: maps a crusher's Team attribute to the team that scores.
local crusherTeamMapper: (rawTeam: string?) -> string? = function(rawTeam)
	return rawTeam
end

function BlockService.SetCrusherTeamMapper(fn: (rawTeam: string?) -> string?)
	crusherTeamMapper = fn
end

-- EventService sets this (Golden Rain): return a variant Id to force on new regular blocks
local variantOverride: (() -> string?)? = nil

function BlockService.SetVariantOverride(fn: (() -> string?)?)
	variantOverride = fn
end

local function variantById(id: string?)
	if not id then
		return nil
	end
	for _, variant in BlockConfig.Variants do
		if variant.Id == id then
			return variant
		end
	end
	return nil
end

-- Helpers ---------------------------------------------------------------------

local function eased(progress: number): number
	return math.clamp(progress, 0, 1) ^ BlockConfig.ScaleCurve
end

local function getTemplate(variantId: string): BasePart?
	local assets = ServerStorage:FindFirstChild(Constants.AssetsFolder)
	local blocks = assets and assets:FindFirstChild("Blocks")
	local template = blocks and (blocks:FindFirstChild(variantId) or blocks:FindFirstChild("Default"))
	if template and template:IsA("BasePart") then
		return template
	end
	return nil
end

-- Cartoon "?" on all six faces (procedural blocks only)
local function decorate(part: BasePart, label: string, color: Color3)
	for _, face in Enum.NormalId:GetEnumItems() do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 25
		gui.LightInfluence = 0.6

		local border = Instance.new("Frame")
		border.BackgroundTransparency = 1
		border.Size = UDim2.fromScale(1, 1)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 8
		stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.35)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = border
		border.ZIndex = 4
		border.Parent = gui

		-- Glossy toy-block look: soft shade toward the bottom + a shine highlight top-left
		local shade = Instance.new("Frame")
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BorderSizePixel = 0
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 1
		local shadeGradient = Instance.new("UIGradient")
		shadeGradient.Rotation = 90
		shadeGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 0.72),
		})
		shadeGradient.Parent = shade
		shade.Parent = gui

		local shine = Instance.new("Frame")
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BackgroundTransparency = 0.6
		shine.BorderSizePixel = 0
		shine.Position = UDim2.fromScale(0.09, 0.08)
		shine.Size = UDim2.fromScale(0.3, 0.1)
		shine.ZIndex = 2
		local shineCorner = Instance.new("UICorner")
		shineCorner.CornerRadius = UDim.new(1, 0)
		shineCorner.Parent = shine
		shine.Parent = gui

		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.AnchorPoint = Vector2.new(0.5, 0.5)
		text.Position = UDim2.fromScale(0.5, 0.5)
		text.Size = UDim2.fromScale(0.8, 0.8)
		text.Text = label
		text.TextScaled = true
		text.Font = Enum.Font.FredokaOne
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeColor3 = color:Lerp(Color3.new(0, 0, 0), 0.5)
		text.TextStrokeTransparency = 0
		text.ZIndex = 3
		text.Parent = gui

		gui.Parent = part
	end
end

local function removeFromRegistry(state: BlockState)
	byPart[state.part] = nil
	local index = table.find(active, state)
	if index then
		table.remove(active, index)
	end
end

-- Spawning --------------------------------------------------------------------

function BlockService.Spawn(options: SpawnOptions): BlockState?
	local progress = eased(options.progress or 0)
	local variant = MathUtil.weightedPick(BlockConfig.Variants, rng)
	if options.welcome then
		variant = BlockConfig.Variants[1]
	elseif options.variantId then
		variant = variantById(options.variantId) or variant
	elseif variantOverride then
		variant = variantById(variantOverride()) or variant
	end
	local size, health, coins, points, heft

	if options.welcome then
		local welcome = BlockConfig.Welcome
		size, health, coins, points, heft = welcome.Size, welcome.Health, welcome.Coins, 1, 1
	elseif options.custom then
		local custom = options.custom
		size, health, points, heft = custom.size, custom.health, custom.points, custom.heft
		coins = custom.coins * variant.CoinMultiplier
	else
		local playerCount = math.max(1, #Players:GetPlayers())
		size = MathUtil.range(BlockConfig.Size, progress)
		health = MathUtil.range(BlockConfig.Health, progress)
			* (1 + (playerCount - 1) * BlockConfig.HealthPerExtraPlayer)
		coins = MathUtil.range(BlockConfig.Coins, progress) * variant.CoinMultiplier
		points = math.floor(MathUtil.range(BlockConfig.Points, progress) + 0.5)
		heft = MathUtil.range(BlockConfig.Heft, progress)
	end
	health = math.max(1, math.floor(health + 0.5))

	local position = options.position or ArenaService.RandomDropPosition(size, rng)
	if not position then
		return nil
	end

	local part: BasePart
	local template = getTemplate(variant.Id)
	if template then
		part = template:Clone()
		local longest = math.max(template.Size.X, template.Size.Y, template.Size.Z)
		part.Size = template.Size * (size / longest)
	else
		local color = options.color or variant.Color or BlockConfig.Palette[rng:NextInteger(1, #BlockConfig.Palette)]
		local newPart = Instance.new("Part")
		newPart.Size = Vector3.one * size
		newPart.Color = color
		newPart.Material = variant.Material or Enum.Material.SmoothPlastic
		newPart.TopSurface = Enum.SurfaceType.Smooth
		newPart.BottomSurface = Enum.SurfaceType.Smooth
		decorate(newPart, options.label or variant.Label or "?", color)
		part = newPart
	end

	local elasticity = variant.Elasticity or BlockConfig.Elasticity
	part.Name = "BonkBlock"
	part.Anchored = false
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CustomPhysicalProperties = PhysicalProperties.new(
		BlockConfig.Density,
		BlockConfig.Friction,
		elasticity,
		1,
		if variant.Elasticity then 100 else 1
	)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)

	nextId += 1
	part:SetAttribute(BlockAttr.Id, nextId)
	part:SetAttribute(BlockAttr.HP, health)
	part:SetAttribute(BlockAttr.MaxHP, health)
	part:SetAttribute(BlockAttr.Variant, variant.Id)
	if options.kind then
		part:SetAttribute("Kind", options.kind)
	end
	part.Parent = blocksFolder
	part:SetNetworkOwner(nil)
	CollectionService:AddTag(part, Constants.Tags.Block)

	local now = os.clock()
	local state: BlockState = {
		id = nextId,
		part = part,
		maxHp = health,
		hp = health,
		coins = coins,
		points = math.max(1, points),
		heft = heft,
		variant = variant.Id,
		damageBy = {},
		spawnedAt = now,
		lastHitAt = now,
		resolved = false,
		welcome = options.welcome == true,
		kind = options.kind,
	}
	byPart[part] = state
	table.insert(active, state)
	return state
end

-- Drops a soft starter block right in front of a new player (the 30s hook).
function BlockService.SpawnWelcome(player: Player): BlockState?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local welcome = BlockConfig.Welcome
	local look = MathUtil.flat(root.CFrame.LookVector)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	local position = ArenaService.ClampToZones(root.Position + look.Unit * welcome.Distance, welcome.Size)
	if not position then
		return nil
	end
	return BlockService.Spawn({ welcome = true, position = position })
end

function BlockService.CountRegular(): number
	local count = 0
	for _, state in active do
		if not state.welcome and state.kind == nil then
			count += 1
		end
	end
	return count
end

function BlockService.CountKind(kind: string): number
	local count = 0
	for _, state in active do
		if state.kind == kind then
			count += 1
		end
	end
	return count
end

-- mode "Round": scales with getProgress(); mode "Warmup": slow drops of round-start blocks.
function BlockService.StartSpawner(mode: "Round" | "Warmup", getProgress: (() -> number)?)
	spawnerToken += 1
	local token = spawnerToken
	task.spawn(function()
		while spawnerToken == token do
			local progress = if getProgress then getProgress() else 0
			local cap, interval
			if mode == "Warmup" then
				cap = BlockConfig.WarmupMaxActive
				interval = BlockConfig.WarmupInterval
			else
				local players = #Players:GetPlayers()
				cap = math.min(
					BlockConfig.MaxActiveCap,
					math.floor(BlockConfig.MaxActiveBase + players * BlockConfig.MaxActivePerPlayer)
				)
				interval = MathUtil.range(BlockConfig.SpawnInterval, progress)
			end
			if BlockService.CountRegular() < cap then
				BlockService.Spawn({ progress = progress })
			end
			task.wait(interval)
		end
	end)
end

function BlockService.StopSpawner()
	spawnerToken += 1
end

-- Round transitions keep an event Mega Block alive; pass true to clear everything.
function BlockService.ClearAll(includeMega: boolean?)
	for _, state in table.clone(active) do
		if includeMega or state.kind ~= "Mega" then
			BlockService.Resolve(state, "Despawn")
		end
	end
end

-- Targeting & hits ------------------------------------------------------------

function BlockService.GetState(part: Instance): BlockState?
	return byPart[part :: any]
end

-- Picks the block a swing from `origin` hits. `hint` is the client's guess; it only
-- breaks ties and is held to exactly the same distance/arc rules as any other block.
function BlockService.FindTarget(origin: CFrame, maxReach: number, hint: Instance?): BlockState?
	local look = MathUtil.flat(origin.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)

	local function reachOf(state: BlockState): number?
		if state.resolved then
			return nil
		end
		local part = state.part
		local distance = MathUtil.distanceToBox(part.CFrame, part.Size, origin.Position)
		if distance > maxReach then
			return nil
		end
		local toBlock = MathUtil.flat(part.Position - origin.Position)
		if distance > 1.5 and toBlock.Magnitude > 0.1 and look:Dot(toBlock.Unit) < Config.Hammer.ArcDot then
			return nil
		end
		return distance
	end

	if hint then
		local hinted = byPart[hint :: any]
		if hinted and reachOf(hinted) then
			return hinted
		end
	end

	local best: BlockState? = nil
	local bestDistance = math.huge
	for _, state in active do
		local distance = reachOf(state)
		if distance and distance < bestDistance then
			best, bestDistance = state, distance
		end
	end
	return best
end

function BlockService.ApplyHit(
	state: BlockState,
	attacker: Player,
	damage: number,
	knockback: number,
	fromPosition: Vector3
)
	if state.resolved then
		return
	end
	local part = state.part
	local dealt = math.min(damage, state.hp)
	state.hp = math.max(0, state.hp - damage)
	state.damageBy[attacker.UserId] = (state.damageBy[attacker.UserId] or 0) + dealt
	state.lastHitAt = os.clock()
	part:SetAttribute(BlockAttr.HP, state.hp)

	local hitPosition = MathUtil.closestPointOnBox(part.CFrame, part.Size, fromPosition)
	hitRemote:FireAllClients(part, hitPosition, dealt, attacker.UserId, state.hp, state.maxHp)
	BlockService.BlockHit:Fire(state, attacker, dealt)

	if state.hp <= 0 then
		BlockService.Resolve(state, "Crack")
		return
	end

	-- Smash-style knockback: the more damaged, the farther it flies
	local push = MathUtil.flat(part.Position - fromPosition)
	if push.Magnitude < 0.05 then
		push = Vector3.new(0, 0, -1)
	end
	push = push.Unit
	local direction = (push + Vector3.yAxis * Config.Hammer.UpwardBias).Unit
	local damagedFraction = 1 - state.hp / state.maxHp
	local speed = knockback * (1 + damagedFraction * BlockConfig.DamageKnockbackBonus) / state.heft
	local mass = part.AssemblyMass
	part:ApplyImpulse(direction * speed * mass)

	-- Tumble forward (rolling axis = up x push)
	local inertia = mass * part.Size.X * part.Size.X / 6
	part:ApplyAngularImpulse(Vector3.yAxis:Cross(push) * inertia * Config.Hammer.Spin)
end

-- Resolution (the only place coins come from blocks) ---------------------------

local function payContributors(state: BlockState, reason: string, scoringTeam: string?): { PayoutResult }
	local entries = {}
	local total = 0
	for userId, dealt in state.damageBy do
		local player = Players:GetPlayerByUserId(userId)
		if player and dealt > 0 and DataService.IsLoaded(player) then
			table.insert(entries, { player = player, dealt = dealt })
			total += dealt
		end
	end

	local results: { PayoutResult } = {}
	if total <= 0 then
		return results
	end

	local coinReason = if reason == "Crush" then "BlockCrush" else "BlockCrack"
	for _, entry in entries do
		local share = state.coins * entry.dealt / total
		if reason == "Crush" and scoringTeam and TeamService.GetTeamId(entry.player) == scoringTeam then
			share *= BlockConfig.CrusherCoinMultiplier
		end

		local data = DataService.GetData(entry.player)
		local firstEver = data ~= nil and data.totalBlocksCrushed == 0

		local granted = CoinService.Add(entry.player, math.max(1, share), coinReason)
		if firstEver and Config.Coins.FirstCrackBonus > 0 then
			local bonus = CoinService.Add(
				entry.player,
				Config.Coins.FirstCrackBonus,
				"FirstCrackBonus",
				{ ignoreMultipliers = true }
			)
			granted += bonus
			if bonus > 0 then
				notifyRemote:FireClient(entry.player, { text = `First bonk bonus! +{bonus} coins`, kind = "Gold" })
			end
		end
		DataService.Increment(entry.player, "totalBlocksCrushed", 1)
		table.insert(results, { player = entry.player, userId = entry.player.UserId, coins = granted })
	end
	return results
end

function BlockService.Resolve(state: BlockState, reason: "Crack" | "Crush" | "Despawn", scoringTeam: string?)
	-- Single exit: the flag is set before anything else, and nothing below yields,
	-- so a block can never pay out twice (crack + crush in the same frame, etc.)
	if state.resolved then
		return
	end
	state.resolved = true
	removeFromRegistry(state)

	local part = state.part
	local position = part.Position
	local color = part.Color
	local size = math.max(part.Size.X, part.Size.Y, part.Size.Z)
	part:Destroy()

	local payouts: { PayoutResult } = {}
	if reason ~= "Despawn" then
		payouts = payContributors(state, reason, scoringTeam)
	end
	BlockService.BlockResolved:Fire(state, reason, scoringTeam, payouts)

	local clientPayouts: { Types.Payout } = {}
	for _, payout in payouts do
		table.insert(clientPayouts, { userId = payout.userId, coins = payout.coins })
	end
	local payload: Types.BurstPayload = {
		position = position,
		size = size,
		color = color,
		reason = reason,
		teamId = scoringTeam,
		kind = state.kind,
		points = if reason == "Crush" and scoringTeam then state.points else nil,
		payouts = clientPayouts,
	}
	burstRemote:FireAllClients(payload)
end

-- Lifecycle -------------------------------------------------------------------

local MONITOR_INTERVAL = 0.1
local monitorAccumulator = 0

local function monitor(dt: number)
	monitorAccumulator += dt
	if monitorAccumulator < MONITOR_INTERVAL then
		return
	end
	monitorAccumulator = 0

	local now = os.clock()
	for _, state in table.clone(active) do
		if state.resolved then
			continue
		end
		local part = state.part
		if not part:IsDescendantOf(workspace) then
			BlockService.Resolve(state, "Despawn")
			continue
		end
		local position = part.Position
		if position.Y < BlockConfig.KillY then
			BlockService.Resolve(state, "Despawn")
			continue
		end
		local crusher, rawTeam = ArenaService.FindCrusherAt(position)
		if crusher then
			BlockService.Resolve(state, "Crush", crusherTeamMapper(rawTeam))
		elseif now - state.lastHitAt > BlockConfig.IdleDespawnTime then
			BlockService.Resolve(state, "Despawn")
		end
	end
end

function BlockService.Init()
	blocksFolder = workspace:FindFirstChild(Constants.BlocksFolder) :: Folder
	if not blocksFolder then
		blocksFolder = Instance.new("Folder")
		blocksFolder.Name = Constants.BlocksFolder
		blocksFolder.Parent = workspace
	end
	burstRemote = Net.Get(Constants.Remotes.BlockBurst)
	notifyRemote = Net.Get(Constants.Remotes.Notify)
	hitRemote = Net.Get(Constants.UnreliableRemotes.BlockHit)
end

function BlockService.Start()
	RunService.Heartbeat:Connect(monitor)
end

return BlockService
