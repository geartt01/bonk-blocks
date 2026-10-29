--[[
	RoundService: the game loop.

		Waiting -> Intermission (lobby countdown, warm-up blocks, shop open)
		        -> Active (3 min, teams or co-op) -> Summary -> Intermission -> ...

	Replicates state through attributes on ReplicatedStorage.BonkGameState so late
	joiners get the current state for free. Timers are absolute server timestamps
	(workspace:GetServerTimeNow()), so clients count down locally without spam.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local BlockService = require(script.Parent.BlockService)
local CoinService = require(script.Parent.CoinService)
local DataService = require(script.Parent.DataService)
local TeamService = require(script.Parent.TeamService)

local State = Constants.RoundState
local Mode = Constants.Mode
local GameAttr = Constants.GameAttr

type RoundStats = { damage: number, cracks: number, crushes: number, coins: number }

local RoundService = {}
RoundService.StateChanged = Signal.new() -- (state, mode)
RoundService.RoundFinished = Signal.new() -- (summary: Types.RoundSummary)

local gameState: Folder
local current = State.Waiting
local mode = Mode.Coop
local roundNumber = 0
local roundStartedAt = 0
local roundDuration = Config.Round.RoundTime
local coopTarget = 0
local scores: { [string]: number } = { Red = 0, Blue = 0, Crew = 0 }
local stats: { [Player]: RoundStats } = {}
local welcomed: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local skipRequested = false
local summaryRemote

-- Queries ---------------------------------------------------------------------

function RoundService.GetState(): string
	return current
end

function RoundService.GetMode(): string
	return mode
end

-- Swinging is allowed during warm-up and the live round
function RoundService.IsCombatOpen(): boolean
	return current == State.Active or current == State.Intermission
end

function RoundService.IsShopOpen(): boolean
	return current ~= State.Active
end

function RoundService.GetProgress(): number
	return math.clamp((os.clock() - roundStartedAt) / roundDuration, 0, 1)
end

-- Internals -------------------------------------------------------------------

local function setState(newState: string, duration: number?)
	current = newState
	gameState:SetAttribute(GameAttr.Mode, mode)
	gameState:SetAttribute(GameAttr.Round, roundNumber)
	gameState:SetAttribute(GameAttr.EndsAt, workspace:GetServerTimeNow() + (duration or 0))
	gameState:SetAttribute(GameAttr.State, newState) -- last: clients react to State changes
	RoundService.StateChanged:Fire(newState, mode)
end

local function setScore(teamId: string, value: number)
	scores[teamId] = value
	gameState:SetAttribute(Constants.ScoreAttr(teamId), value)
end

local function statsFor(player: Player): RoundStats
	local entry = stats[player]
	if not entry then
		entry = { damage = 0, cracks = 0, crushes = 0, coins = 0 }
		stats[player] = entry
	end
	return entry
end

local function playerCount(): number
	return #Players:GetPlayers()
end

-- Waits `seconds`. Returns false early if the server empties; true otherwise
-- (including when shouldStop() returns true).
local function waitFor(seconds: number, shouldStop: (() -> boolean)?): boolean
	local deadline = os.clock() + seconds
	skipRequested = false
	while os.clock() < deadline do
		if playerCount() == 0 then
			return false
		end
		if skipRequested then -- debug: end this phase now
			skipRequested = false
			return true
		end
		if shouldStop and shouldStop() then
			return true
		end
		task.wait(0.2)
	end
	return true
end

local function resetToWaiting()
	BlockService.StopSpawner()
	BlockService.ClearAll(true)
	TeamService.ClearAll()
	mode = Mode.Coop
	setState(State.Waiting)
end

local function runRound(): boolean
	local players = Players:GetPlayers()
	mode = if #players >= Config.Round.TeamModeMinPlayers then Mode.Teams else Mode.Coop
	if RunService:IsStudio() and Config.Debug.ForceMode then
		mode = Config.Debug.ForceMode
	end
	roundDuration = if RunService:IsStudio() and Config.Debug.RoundTime
		then Config.Debug.RoundTime
		else Config.Round.RoundTime

	roundNumber += 1
	table.clear(stats)
	for _, teamId in Constants.TeamIds do
		setScore(teamId, 0)
	end
	coopTarget = Config.Coop.TargetBase + (#players - 1) * Config.Coop.TargetPerExtraPlayer
	gameState:SetAttribute(GameAttr.CoopTarget, coopTarget)

	BlockService.ClearAll()
	TeamService.AssignForRound(players, mode)
	for _, player in players do
		TeamService.SendToSpawn(player)
	end

	roundStartedAt = os.clock()
	setState(State.Active, roundDuration)
	BlockService.StartSpawner("Round", RoundService.GetProgress)

	local stillPlaying = waitFor(roundDuration, function()
		return mode == Mode.Coop and scores.Crew >= coopTarget
	end)
	BlockService.StopSpawner()
	return stillPlaying
end

local function finishRound()
	local winner
	if mode == Mode.Coop then
		winner = if scores.Crew >= coopTarget then "Crew" else "None"
	elseif scores.Red > scores.Blue then
		winner = "Red"
	elseif scores.Blue > scores.Red then
		winner = "Blue"
	else
		winner = "Draw"
	end

	-- Bonuses only for players who actually played (no AFK farming).
	-- State is still Active here, so the Changed listener counts them in round stats.
	for _, player in Players:GetPlayers() do
		local entry = stats[player]
		if entry and entry.damage > 0 then
			local bonus = Config.Coins.ParticipationBonus
			if winner == TeamService.GetTeamId(player) then
				bonus += Config.Coins.WinBonus
			end
			CoinService.Add(player, bonus, "RoundBonus")
		end
	end

	local list: { Types.SummaryEntry } = {}
	for _, player in Players:GetPlayers() do
		local entry = stats[player] or { damage = 0, cracks = 0, crushes = 0, coins = 0 }
		table.insert(list, {
			userId = player.UserId,
			name = player.DisplayName,
			teamId = TeamService.GetTeamId(player),
			damage = math.floor(entry.damage),
			cracks = entry.cracks,
			crushes = entry.crushes,
			coins = entry.coins,
		})
	end
	table.sort(list, function(a, b)
		return a.damage > b.damage
	end)

	local summary: Types.RoundSummary = {
		round = roundNumber,
		mode = mode,
		winner = winner,
		scores = table.clone(scores),
		coopTarget = coopTarget,
		players = list,
		mvpUserId = if list[1] and list[1].damage > 0 then list[1].userId else nil,
	}
	summaryRemote:FireAllClients(summary)
	RoundService.RoundFinished:Fire(summary)
end

local function mainLoop()
	local firstRound = true
	while true do
		if playerCount() == 0 then
			resetToWaiting()
			firstRound = true
			repeat
				task.wait(0.5)
			until playerCount() > 0
		end

		local countdown = if firstRound then Config.Round.FirstIntermission else Config.Round.IntermissionTime
		setState(State.Intermission, countdown)
		BlockService.StartSpawner("Warmup")
		local ok = waitFor(countdown)
		BlockService.StopSpawner()
		if not ok then
			continue
		end
		firstRound = false

		if not runRound() then
			continue -- everyone left mid-round; top of loop resets
		end
		finishRound()

		BlockService.ClearAll()
		setState(State.Summary, Config.Round.SummaryTime)
		waitFor(Config.Round.SummaryTime)
	end
end

-- Welcome block: first spawn of the session gets a block dropped in front of them.
local function scheduleWelcome(player: Player)
	if not Config.Blocks.Welcome.Enabled or welcomed[player] then
		return
	end
	welcomed[player] = true
	task.spawn(function()
		-- Wait for data, open combat, and the client finishing its intro (45s fallback)
		local deadline = os.clock() + 45
		while
			player.Parent == Players
			and os.clock() < deadline
			and not (
				DataService.IsLoaded(player)
				and RoundService.IsCombatOpen()
				and player:GetAttribute(Constants.PlayerAttr.ClientReady) == true
			)
		do
			task.wait(0.25)
		end
		task.wait(Config.Blocks.Welcome.Delay)
		if player.Parent == Players and DataService.IsLoaded(player) and RoundService.IsCombatOpen() then
			BlockService.SpawnWelcome(player)
		end
	end)
end

-- Debug helpers (DebugService, Studio only) ---------------------------------------

function RoundService.SkipPhase()
	skipRequested = true
end

function RoundService.ResetWelcome(player: Player)
	welcomed[player] = nil
	scheduleWelcome(player)
end

local function onPlayerAdded(player: Player)
	if current == State.Active then
		TeamService.AssignLateJoiner(player, mode)
	end
	player.CharacterAdded:Connect(function()
		scheduleWelcome(player)
	end)
	if player.Character then
		scheduleWelcome(player)
	end
end

-- Lifecycle -------------------------------------------------------------------

function RoundService.Init()
	gameState = Instance.new("Folder")
	gameState.Name = Constants.GameStateName
	for _, teamId in Constants.TeamIds do
		gameState:SetAttribute(Constants.ScoreAttr(teamId), 0)
	end
	gameState:SetAttribute(GameAttr.CoopTarget, 0)
	gameState:SetAttribute(GameAttr.Mode, mode)
	gameState:SetAttribute(GameAttr.Round, 0)
	gameState:SetAttribute(GameAttr.EndsAt, 0)
	gameState:SetAttribute(GameAttr.State, State.Waiting)
	gameState.Parent = ReplicatedStorage

	summaryRemote = Net.Get(Constants.Remotes.RoundSummary)

	-- Which team scores when a block enters a crusher
	BlockService.SetCrusherTeamMapper(function(rawTeam)
		if current ~= State.Active then
			return nil -- warm-up crushes pay coins but never score
		elseif mode == Mode.Coop then
			return "Crew" -- every crusher counts for the crew
		elseif rawTeam == "Red" or rawTeam == "Blue" then
			return rawTeam
		end
		return nil
	end)
end

function RoundService.Start()
	BlockService.BlockHit:Connect(function(_state, player, dealt)
		if current == State.Active then
			statsFor(player).damage += dealt
		end
	end)

	BlockService.BlockResolved:Connect(function(state, reason, scoringTeam, payouts)
		if current ~= State.Active then
			return
		end
		if reason == "Crush" and scoringTeam and scores[scoringTeam] ~= nil then
			setScore(scoringTeam, scores[scoringTeam] + state.points)
		end
		for _, payout in payouts do
			local entry = statsFor(payout.player)
			if reason == "Crush" then
				entry.crushes += 1
			elseif reason == "Crack" then
				entry.cracks += 1
			end
		end
	end)

	CoinService.Changed:Connect(function(player, _balance, delta)
		if current == State.Active and delta > 0 and player.Parent == Players then
			statsFor(player).coins += delta
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		stats[player] = nil
	end)

	task.spawn(mainLoop)
end

return RoundService
