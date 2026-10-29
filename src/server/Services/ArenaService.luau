--[[
	ArenaService: finds the Studio-built arena pieces through CollectionService tags.

		BlockSpawnZone  invisible part above the arena; blocks drop from a random point inside it
		Crusher         invisible volume; attribute Team = "Red" | "Blue"
		TeamSpawn       spawn pad; attribute Team = "Red" | "Blue" (no attribute = any team)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local MathUtil = require(Shared.MathUtil)

local DevArena = require(script.Parent.Parent.Util.DevArena)

local Tags = Constants.Tags

local ArenaService = {}

local function tagged(tag: string): { BasePart }
	local list = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(list, instance)
		end
	end
	return list
end

function ArenaService.GetSpawnZones(): { BasePart }
	return tagged(Tags.BlockSpawnZone)
end

function ArenaService.GetCrushers(): { BasePart }
	return tagged(Tags.Crusher)
end

-- Spawn pads for a team; falls back to every pad if the team has none.
function ArenaService.GetTeamSpawns(teamId: string?): { BasePart }
	local all = tagged(Tags.TeamSpawn)
	if teamId == nil or teamId == "Crew" then
		return all
	end
	local matching = {}
	for _, pad in all do
		local padTeam = pad:GetAttribute("Team")
		if padTeam == nil or padTeam == teamId then
			table.insert(matching, pad)
		end
	end
	return if #matching > 0 then matching else all
end

-- Random drop point inside a spawn zone (weighted by area), inset so the block fits.
function ArenaService.RandomDropPosition(blockSize: number, rng: Random): Vector3?
	local zones = ArenaService.GetSpawnZones()
	if #zones == 0 then
		return nil
	end
	local totalArea = 0
	for _, zone in zones do
		totalArea += zone.Size.X * zone.Size.Z
	end
	local roll = rng:NextNumber(0, totalArea)
	local zone = zones[#zones]
	for _, candidate in zones do
		roll -= candidate.Size.X * candidate.Size.Z
		if roll <= 0 then
			zone = candidate
			break
		end
	end
	local halfX = math.max(0, zone.Size.X / 2 - blockSize / 2)
	local halfZ = math.max(0, zone.Size.Z / 2 - blockSize / 2)
	return zone.CFrame:PointToWorldSpace(Vector3.new(rng:NextNumber(-halfX, halfX), 0, rng:NextNumber(-halfZ, halfZ)))
end

-- Nearest drop point (at spawn-zone height) to a desired XZ position.
function ArenaService.ClampToZones(position: Vector3, blockSize: number): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, zone in ArenaService.GetSpawnZones() do
		local rel = zone.CFrame:PointToObjectSpace(position)
		local halfX = math.max(0, zone.Size.X / 2 - blockSize / 2)
		local halfZ = math.max(0, zone.Size.Z / 2 - blockSize / 2)
		local clamped = zone.CFrame:PointToWorldSpace(
			Vector3.new(math.clamp(rel.X, -halfX, halfX), 0, math.clamp(rel.Z, -halfZ, halfZ))
		)
		local distance = (MathUtil.flat(clamped) - MathUtil.flat(position)).Magnitude
		if distance < bestDistance then
			best, bestDistance = clamped, distance
		end
	end
	return best
end

-- Returns the crusher containing this point and its raw Team attribute.
function ArenaService.FindCrusherAt(position: Vector3): (BasePart?, string?)
	for _, crusher in ArenaService.GetCrushers() do
		if MathUtil.isInsideBox(crusher.CFrame, crusher.Size, position) then
			local team = crusher:GetAttribute("Team")
			return crusher, if typeof(team) == "string" then team else nil
		end
	end
	return nil, nil
end

function ArenaService.Init()
	if Config.Visuals.ApplyLighting then
		DevArena.ApplyLighting()
	end
	-- A DevArena saved into the place (copied out of a play session) is an old version:
	-- its tags would stop the current one from being built, so replace it.
	local stale = workspace:FindFirstChild("DevArena")
	if Config.Arena.BuildDevArenaIfMissing and stale and stale:IsA("Model") then
		stale:Destroy()
		warn("[ArenaService] Removed an old saved DevArena from the place; building the current one.")
	end
	if
		Config.Arena.BuildDevArenaIfMissing
		and #ArenaService.GetSpawnZones() == 0
		and #ArenaService.GetCrushers() == 0
	then
		DevArena.Build()
		print("[ArenaService] No tagged arena found: built DevArena. Tag your own parts to replace it.")
	end
end

function ArenaService.Start()
	if #ArenaService.GetSpawnZones() == 0 then
		warn(`[ArenaService] No part tagged "{Tags.BlockSpawnZone}". Blocks cannot spawn.`)
	end
	local crushers = ArenaService.GetCrushers()
	if #crushers == 0 then
		warn(`[ArenaService] No part tagged "{Tags.Crusher}". Nothing can be crushed.`)
	end
	for _, crusher in crushers do
		local team = crusher:GetAttribute("Team")
		if team ~= "Red" and team ~= "Blue" then
			warn(`[ArenaService] Crusher {crusher:GetFullName()} needs a string attribute Team = "Red" or "Blue"`)
		end
	end
	if #ArenaService.GetTeamSpawns(nil) == 0 then
		warn(`[ArenaService] No part tagged "{Tags.TeamSpawn}". Players will use default SpawnLocations.`)
	end
end

return ArenaService
