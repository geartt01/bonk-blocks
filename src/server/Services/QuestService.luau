--[[
	QuestService: Config.Quests.PerDay quests per UTC day, rolled from Config.Quests.Pool.
	Progress comes from existing signals (no remotes carry progress):
		Crack / Crush / Golden  <- BlockService.BlockResolved
		Damage                  <- BlockService.BlockHit
		Swing                   <- HammerService.Swung
		Win                     <- RoundService.RoundFinished
		Blockling               <- BlocklingService.Granted
		Upgrade                 <- UpgradeService.Upgraded
	Claiming (QuestClaimRequest) pays coins once per quest. Replicated as Quest1..N attributes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)

local BlockService = require(script.Parent.BlockService)
local BlocklingService = require(script.Parent.BlocklingService)
local CoinService = require(script.Parent.CoinService)
local DataService = require(script.Parent.DataService)
local HammerService = require(script.Parent.HammerService)
local RoundService = require(script.Parent.RoundService)
local UpgradeService = require(script.Parent.UpgradeService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local QuestService = {}

local rng = Random.new()
local limiter = RateLimiter.new("QuestClaimRequest", { PerSecond = 3, Burst = 5 })
local notifyRemote

local function today(): number
	return Progression.DayKey(os.time())
end

local function sync(player: Player, data)
	for index = 1, Config.Quests.PerDay do
		local quest = data.quests.list[index]
		player:SetAttribute(
			Constants.QuestAttr(index),
			if quest then `{quest.id}:{quest.progress}:{if quest.claimed then 1 else 0}` else ""
		)
	end
end

-- Rolls fresh quests when the UTC day changed. Returns true if it rerolled.
local function ensureToday(data): boolean
	if data.quests.day == today() and #data.quests.list > 0 then
		return false
	end
	local pool = table.clone(Config.Quests.Pool)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local list = {}
	for i = 1, math.min(Config.Quests.PerDay, #pool) do
		table.insert(list, { id = pool[i].Id, progress = 0, claimed = false })
	end
	data.quests = { day = today(), list = list }
	return true
end

function QuestService.Progress(player: Player, event: string, amount: number)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local changed = ensureToday(data)
	for _, quest in data.quests.list do
		local def = Progression.Quest(quest.id)
		if def and def.Event == event and quest.progress < def.Target then
			quest.progress = math.min(def.Target, quest.progress + amount)
			changed = true
			if quest.progress >= def.Target then
				notifyRemote:FireClient(player, { text = `Quest complete: {def.Text}! Claim it in DAILY`, kind = "Gold" })
			end
		end
	end
	if changed then
		sync(player, data)
	end
end

local function onClaimRequest(player: Player, index: any)
	if not limiter:Allow(player) then
		return
	end
	if typeof(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > Config.Quests.PerDay then
		RateLimiter.Reject(player, "QuestClaimRequest", "bad index")
		return
	end
	local data = DataService.GetData(player)
	if not data then
		return
	end
	if ensureToday(data) then
		sync(player, data) -- the day rolled over; the old quest is gone
		return
	end
	local quest = data.quests.list[index]
	local def = quest and Progression.Quest(quest.id)
	if not (quest and def) or quest.claimed or quest.progress < def.Target then
		return
	end
	quest.claimed = true -- before paying: a second request can't double-claim
	local coins = CoinService.Add(player, Progression.QuestCoins(quest.id, data.rebirths), "Quest", { ignoreMultipliers = true })
	sync(player, data)
	notifyRemote:FireClient(player, { text = `+{coins} coins: {def.Text}`, kind = "Gold" })
end

function QuestService.Refresh(player: Player)
	local data = DataService.GetData(player)
	if data then
		ensureToday(data)
		sync(player, data)
	end
end

-- Debug: finish every quest so claiming can be tested
function QuestService.DebugCompleteAll(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	ensureToday(data)
	for _, quest in data.quests.list do
		local def = Progression.Quest(quest.id)
		if def then
			quest.progress = def.Target
		end
	end
	sync(player, data)
end

function QuestService.Init()
	notifyRemote = Net.Get(Constants.Remotes.Notify)
end

function QuestService.Start()
	DataService.ProfileLoaded:Connect(QuestService.Refresh)
	for _, player in Players:GetPlayers() do
		QuestService.Refresh(player) -- profiles that loaded before Start
	end

	BlockService.BlockResolved:Connect(function(state, reason, _team, payouts)
		if reason == "Despawn" then
			return
		end
		for _, payout in payouts do
			QuestService.Progress(payout.player, reason, 1) -- "Crack" or "Crush"
			if state.kind == "Mega" then
				QuestService.Progress(payout.player, "Mega", 1)
			end
			if state.variant == "Golden" then
				QuestService.Progress(payout.player, "Golden", 1)
			end
		end
	end)
	BlockService.BlockHit:Connect(function(_state, player, dealt)
		QuestService.Progress(player, "Damage", dealt)
	end)
	HammerService.Swung:Connect(function(player)
		QuestService.Progress(player, "Swing", 1)
	end)
	HammerService.PlayerBonked:Connect(function(attacker)
		QuestService.Progress(attacker, "PlayerBonk", 1)
	end)
	RoundService.RoundFinished:Connect(function(summary)
		for _, entry in summary.players do
			if entry.teamId ~= nil and entry.teamId == summary.winner then
				local player = Players:GetPlayerByUserId(entry.userId)
				if player then
					QuestService.Progress(player, "Win", 1)
				end
			end
		end
	end)
	BlocklingService.Granted:Connect(function(player)
		QuestService.Progress(player, "Blockling", 1)
	end)
	UpgradeService.Upgraded:Connect(function(player)
		QuestService.Progress(player, "Upgrade", 1)
	end)

	Net.Get(Constants.Remotes.QuestClaimRequest).OnServerEvent:Connect(onClaimRequest)

	-- Roll over at UTC midnight for players who stay online
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local data = DataService.GetData(player)
				if data and ensureToday(data) then
					sync(player, data)
				end
			end
		end
	end)
end

return QuestService
