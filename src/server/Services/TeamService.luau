--[[
	TeamService: Roblox Team objects, round assignment (snake draft by hammer level),
	late joiners, and moving characters to their team's spawn pads.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)

local ArenaService = require(script.Parent.ArenaService)
local DataService = require(script.Parent.DataService)
local MovementGuard = require(script.Parent.Parent.Util.MovementGuard)

local Mode = Constants.Mode

local TeamService = {}

local teamObjects: { [string]: Team } = {}
local assignment: { [Player]: string } = {}
local rng = Random.new()

function TeamService.GetTeamId(player: Player): string?
	return assignment[player]
end

function TeamService.GetMembers(teamId: string): { Player }
	local members = {}
	for player, id in assignment do
		if id == teamId and player.Parent == Players then
			table.insert(members, player)
		end
	end
	return members
end

function TeamService.SetTeam(player: Player, teamId: string?)
	assignment[player] = teamId
	local team = teamId and teamObjects[teamId]
	if team then
		player.Team = team
		player.Neutral = false
	else
		player.Team = nil
		player.Neutral = true
	end
end

function TeamService.ClearAll()
	for player in table.clone(assignment) do
		TeamService.SetTeam(player, nil)
	end
end

-- Snake draft by hammerLevel (R, B, B, R, R, B, B, R) so teams are roughly even.
function TeamService.AssignForRound(players: { Player }, mode: string)
	if mode == Mode.Coop then
		for _, player in players do
			TeamService.SetTeam(player, "Crew")
		end
		return
	end

	local entries = {}
	for _, player in players do
		local data = DataService.GetData(player)
		table.insert(entries, {
			player = player,
			level = if data then data.hammerLevel else 1,
			tiebreak = rng:NextNumber(),
		})
	end
	table.sort(entries, function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		return a.tiebreak < b.tiebreak
	end)

	local first, second = "Red", "Blue"
	if rng:NextInteger(0, 1) == 1 then
		first, second = second, first
	end
	for index, entry in entries do
		local slot = (index - 1) % 4
		TeamService.SetTeam(entry.player, if slot == 0 or slot == 3 then first else second)
	end
end

function TeamService.AssignLateJoiner(player: Player, mode: string)
	if mode == Mode.Coop then
		TeamService.SetTeam(player, "Crew")
		return
	end
	local red, blue = #TeamService.GetMembers("Red"), #TeamService.GetMembers("Blue")
	local teamId
	if red == blue then
		teamId = if rng:NextInteger(0, 1) == 0 then "Red" else "Blue"
	else
		teamId = if red < blue then "Red" else "Blue"
	end
	TeamService.SetTeam(player, teamId)
end

-- Random point on one of the team's spawn pads, facing the team's crusher (or arena center).
function TeamService.GetSpawnCFrame(teamId: string?): CFrame?
	local pads = ArenaService.GetTeamSpawns(teamId)
	if #pads == 0 then
		return nil
	end
	local pad = pads[rng:NextInteger(1, #pads)]
	local half = pad.Size / 2
	local position = pad.CFrame:PointToWorldSpace(Vector3.new(
		rng:NextNumber(-half.X, half.X) * 0.8,
		half.Y + Config.Arena.SpawnHeightOffset,
		rng:NextNumber(-half.Z, half.Z) * 0.8
	))

	local lookAt: Vector3? = nil
	for _, crusher in ArenaService.GetCrushers() do
		if teamId ~= nil and crusher:GetAttribute("Team") == teamId then
			lookAt = crusher.Position
			break
		end
	end
	if not lookAt then
		local zone = ArenaService.GetSpawnZones()[1]
		lookAt = zone and zone.Position
	end
	if lookAt then
		local flatTarget = Vector3.new(lookAt.X, position.Y, lookAt.Z)
		if (flatTarget - position).Magnitude > 1 then
			return CFrame.lookAt(position, flatTarget)
		end
	end
	return CFrame.new(position)
end

function TeamService.SendToSpawn(player: Player)
	local character = player.Character
	if not character or not character:IsDescendantOf(workspace) then
		return
	end
	local cf = TeamService.GetSpawnCFrame(assignment[player])
	if cf then
		MovementGuard.NoteTeleport(player) -- our own teleport isn't a speed hack
		character:PivotTo(cf)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	if not character:IsDescendantOf(workspace) then
		character.AncestryChanged:Wait()
	end
	character:WaitForChild("HumanoidRootPart", 5)
	task.wait() -- let Roblox finish its own spawn placement first
	if player.Character == character then
		TeamService.SendToSpawn(player)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function TeamService.Init()
	for teamId, def in Config.Teams do
		local team = Teams:FindFirstChild(def.DisplayName) :: Team?
		if not team then
			team = Instance.new("Team")
		end
		local t = team :: Team
		t.Name = def.DisplayName
		t.TeamColor = def.TeamColor
		t.AutoAssignable = false
		t.Parent = Teams
		teamObjects[teamId] = t
	end
end

function TeamService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		assignment[player] = nil
	end)
end

return TeamService
