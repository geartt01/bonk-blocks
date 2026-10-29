--[[
	EventService: server-wide events on the real clock (Config.Events).

	Progression.EventSchedule(os.time()) decides what runs, so every server runs the
	same event at the same minute and clients can show "MEGA BLOCK in 4:12" without
	any remote. The running event is also replicated on BonkGameState (Event, EventEndsAt)
	for forced/debug events.

		MegaBlock     a giant co-op boss block; every contributor gets a guaranteed Blockling
		GoldenRain    every new block is Golden (x3 coins)
		MoonGravity   workspace.Gravity drops for big air
		Bonanza       Blockling drop x3, mutation x2
		MeteorShower  tiny fast blocks rain down
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local Signal = require(Shared.Signal)

local ArenaService = require(script.Parent.ArenaService)
local BlockService = require(script.Parent.BlockService)
local BlocklingService = require(script.Parent.BlocklingService)
local CoinService = require(script.Parent.CoinService)
local RoundService = require(script.Parent.RoundService)

local Events = Config.Events
local GameAttr = Constants.GameAttr

local EventService = {}
EventService.Started = Signal.new() -- (name)
EventService.Ended = Signal.new() -- (name)

local gameState: Instance
local notifyRemote
local current: string? = nil
local forced: { name: string, endsAt: number }? = nil
local megaState: any = nil
local megaPending = false
local megaReadyAt = 0
local meteorToken = 0
local defaultGravity = 196.2

function EventService.Current(): string?
	return current
end

local function notifyAll(text: string)
	notifyRemote:FireAllClients({ text = text, kind = "Gold" })
end

local function spawnMega()
	local zone = ArenaService.GetSpawnZones()[1]
	if not zone then
		return
	end
	local mega = Events.Mega
	local health, coins = Progression.MegaStats(#Players:GetPlayers())
	local position = ArenaService.ClampToZones(zone.Position, mega.Size)
	if not position then
		return
	end
	megaState = BlockService.Spawn({
		kind = "Mega",
		position = position,
		variantId = "Mystery", -- never Golden: the Mega has its own payout
		color = Events.Defs.MegaBlock.Color,
		label = "!!",
		custom = { size = mega.Size, health = health, coins = coins, points = mega.Points, heft = mega.Heft },
	})
end

local function startMeteors()
	meteorToken += 1
	local token = meteorToken
	local meteor = Events.Meteor
	task.spawn(function()
		while meteorToken == token do
			if RoundService.IsCombatOpen() and BlockService.CountKind("Meteor") < meteor.MaxActive then
				BlockService.Spawn({
					kind = "Meteor",
					custom = { size = meteor.Size, health = meteor.Health, coins = meteor.Coins, points = 1, heft = 0.6 },
				})
			end
			task.wait(meteor.Interval)
		end
	end)
end

local function startEvent(name: string, endsAt: number)
	local def = Events.Defs[name]
	if not def then
		return
	end
	current = name
	gameState:SetAttribute(GameAttr.EventEndsAt, endsAt)
	gameState:SetAttribute(GameAttr.Event, name) -- last: clients react to this
	if name == "MegaBlock" or name == "BonkParty" then
		megaPending = true
		megaReadyAt = 0
	elseif name == "MoonGravity" then
		workspace.Gravity = def.Gravity
	elseif name == "MeteorShower" then
		startMeteors()
	end
	EventService.Started:Fire(name)
end

local function endEvent(name: string)
	if name == "MoonGravity" then
		workspace.Gravity = defaultGravity
	elseif name == "MeteorShower" then
		meteorToken += 1
	elseif name == "MegaBlock" or name == "BonkParty" then
		megaPending = false
		if megaState and not megaState.resolved then
			BlockService.Resolve(megaState, "Despawn") -- clients show "escaped"
		end
		megaState = nil
	end
	current = nil
	gameState:SetAttribute(GameAttr.Event, "")
	gameState:SetAttribute(GameAttr.EventEndsAt, 0)
	EventService.Ended:Fire(name)
end

local function tick()
	local now = os.time()
	local desired: string?, endsAt = nil, 0
	if forced and now < forced.endsAt then
		desired, endsAt = forced.name, forced.endsAt
	else
		forced = nil
		local schedule = Progression.EventSchedule(now)
		desired, endsAt = schedule.current, schedule.currentEndsAt
	end
	if not Events.Enabled or #Players:GetPlayers() == 0 then
		desired = nil
	end

	if desired ~= current then
		if current then
			endEvent(current)
		end
		if desired then
			startEvent(desired, endsAt)
		end
	end

	-- The Mega waits for combat to be open (not during the results screen)
	-- During the weekly party a new Mega drops 15s after each one is destroyed
	if current == "BonkParty" and not megaPending and (megaState == nil or megaState.resolved) then
		megaPending = true
		megaReadyAt = os.clock() + 15
	end
	local megaEvent = current == "MegaBlock" or current == "BonkParty"
	if megaEvent and megaPending and os.clock() >= megaReadyAt and RoundService.IsCombatOpen() then
		megaPending = false
		spawnMega()
		if megaState then
			notifyAll("MEGA BLOCK incoming! Everyone to the middle!")
		end
	end
end

-- Debug: run the next event in the rotation right now
function EventService.DebugStartNext()
	local schedule = Progression.EventSchedule(os.time())
	local name = if current then schedule.nextName else (schedule.current or schedule.nextName)
	if current == name then
		local index = table.find(Events.Rotation, name) or 0
		name = Events.Rotation[(index % #Events.Rotation) + 1]
	end
	forced = { name = name, endsAt = os.time() + Events.Defs[name].Duration }
end

function EventService.Init()
	gameState = ReplicatedStorage:WaitForChild(Constants.GameStateName)
	gameState:SetAttribute(GameAttr.Event, "")
	gameState:SetAttribute(GameAttr.EventEndsAt, 0)
	notifyRemote = Net.Get(Constants.Remotes.Notify)
	defaultGravity = workspace.Gravity

	BlockService.SetVariantOverride(function()
		if current == "GoldenRain" then
			return "Golden"
		elseif current == "BouncyHour" then
			return "Bouncy"
		end
		return nil
	end)
	-- Any event def with CoinMultiplier / DropMultiplier / MutationMultiplier applies it
	-- (CoinFrenzy, Bonanza, and the weekly BonkParty)
	CoinService.RegisterMultiplier("EventCoins", function(_player, _amount, reason)
		local def = current and Events.Defs[current]
		if def and def.CoinMultiplier and Config.Blocklings.BonusReasons[reason] then
			return def.CoinMultiplier
		end
		return 1
	end)
	BlocklingService.SetEventBoost(function()
		local def = current and Events.Defs[current]
		if def and def.DropMultiplier then
			return def.DropMultiplier, def.MutationMultiplier or 1
		end
		return 1, 1
	end)
end

function EventService.Start()
	-- (Mega destroyed / escaped banners are drawn by clients from BlockBurst kind = "Mega")
	task.spawn(function()
		while true do
			tick()
			task.wait(0.25)
		end
	end)
end

return EventService
