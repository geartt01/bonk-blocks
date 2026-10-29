--[[
	DataService: ProfileStore sessions (session-locked), one profile per player.

	- Only this service touches ProfileStore.
	- Coins are changed ONLY through CoinService; other numeric stats through Increment().
	- After any change, call DataService.Sync(player) to push attributes/leaderstats.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local HammerStats = require(Shared.HammerStats)
local Progression = require(Shared.Progression)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

type PlayerData = Types.PlayerData

local function loadProfileStore()
	local packages = ServerScriptService:FindFirstChild("ServerPackages")
	local module = packages and packages:FindFirstChild("ProfileStore")
	if not (module and module:IsA("ModuleScript")) then
		error(
			"[DataService] ProfileStore not found. Download ProfileStore.luau from the official "
				.. "MadStudioRoblox/ProfileStore GitHub release and put it in the ServerPackages/ folder (see README).",
			0
		)
	end
	return require(module) :: any
end

local ProfileStore = loadProfileStore()

local TEMPLATE: PlayerData = {
	coins = 0,
	hammerLevel = 1,
	upgrades = { power = 0, size = 0, knockback = 0 },
	rebirths = 0,
	totalBlocksCrushed = 0,
	lastLogin = 0,
	settings = table.clone(Constants.SettingDefaults),
	blocklings = {},
	equippedBlocklings = {},
	mutations = {},
	blocksSinceBlockling = 0,
	daily = { lastClaim = 0, streak = 0 },
	quests = { day = -1, list = {} },
	seenRelease = "",
}

local DataService = {}
DataService.ProfileLoaded = Signal.new() -- (player: Player, data: PlayerData)
DataService.ProfileReleased = Signal.new() -- (player: Player)

local store: any
local profiles: { [Player]: any } = {}
local previousLogin: { [Player]: number } = {}
local releasedByUs: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Public API ------------------------------------------------------------------

function DataService.GetData(player: Player): PlayerData?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

function DataService.IsLoaded(player: Player): boolean
	return DataService.GetData(player) ~= nil
end

-- Calls back once the player's data is loaded (immediately if it already is).
function DataService.WhenLoaded(player: Player, callback: (data: PlayerData) -> ())
	local data = DataService.GetData(player)
	if data then
		task.spawn(callback, data)
		return
	end
	local connection
	connection = DataService.ProfileLoaded:Connect(function(loadedPlayer, loadedData)
		if loadedPlayer == player then
			connection:Disconnect()
			callback(loadedData)
		end
	end)
end

-- lastLogin from BEFORE this session (week 2: daily rewards / offline income)
function DataService.GetPreviousLogin(player: Player): number?
	return previousLogin[player]
end

-- Generic numeric stat bump. Coins must go through CoinService.
function DataService.Increment(player: Player, field: string, amount: number)
	local data = DataService.GetData(player) :: any
	if not data or field == "coins" or typeof(data[field]) ~= "number" then
		return
	end
	data[field] += amount
	DataService.Sync(player)
end

-- Push saved data to replicated attributes + leaderstats (display only).
function DataService.Sync(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	player:SetAttribute(Constants.PlayerAttr.Coins, data.coins)
	player:SetAttribute(Constants.PlayerAttr.HammerLevel, data.hammerLevel)
	player:SetAttribute(Constants.PlayerAttr.TotalCrushed, data.totalBlocksCrushed)
	for _, id in Config.Upgrades.Order do
		player:SetAttribute(Constants.UpgradeAttr(id), data.upgrades[id] or 0)
	end
	for key, default in Constants.SettingDefaults do
		local value = data.settings[key]
		player:SetAttribute(Constants.SettingAttr(key), if value == nil then default else value)
	end

	-- week 2
	player:SetAttribute(Constants.PlayerAttr.Rebirths, data.rebirths)
	player:SetAttribute(Constants.PlayerAttr.Slots, Progression.BlocklingSlots(data.rebirths))
	player:SetAttribute(Constants.PlayerAttr.Equipped, table.concat(data.equippedBlocklings, ","))
	for _, species in Progression.AllSpecies() do
		player:SetAttribute(Constants.BlocklingAttr(species.Id), data.blocklings[species.Id] or 0)
		player:SetAttribute(Constants.MutationAttr(species.Id), data.mutations[species.Id] or "")
	end
	local _, _, day, nextAt = Progression.DailyState(data.daily, os.time())
	player:SetAttribute(Constants.PlayerAttr.DailyStreak, data.daily.streak)
	player:SetAttribute(Constants.PlayerAttr.DailyDay, day)
	player:SetAttribute(Constants.PlayerAttr.DailyNextAt, nextAt)
	player:SetAttribute(Constants.PlayerAttr.SeenRelease, data.seenRelease)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
	if coinsValue then
		(coinsValue :: IntValue).Value = data.coins
	end
	player:SetAttribute(Constants.PlayerAttr.Loaded, true)
end

-- Internals -------------------------------------------------------------------

-- Guard against corrupted or hand-edited saves.
local function sanitize(data: any)
	for key, default in TEMPLATE :: any do
		if typeof(default) == "number" then
			local value = data[key]
			if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
				data[key] = default
			end
		end
	end
	if typeof(data.upgrades) ~= "table" then
		data.upgrades = table.clone(TEMPLATE.upgrades)
	end
	for _, id in Config.Upgrades.Order do
		local tier = data.upgrades[id]
		if typeof(tier) ~= "number" or tier ~= tier then
			tier = 0
		end
		data.upgrades[id] = math.clamp(math.floor(tier), 0, HammerStats.MaxTier(id))
	end
	data.coins = math.max(0, math.floor(data.coins))
	data.hammerLevel = HammerStats.HammerLevel(data.upgrades)
	if typeof(data.settings) ~= "table" then
		data.settings = {}
	end
	for key, default in Constants.SettingDefaults do
		if typeof(data.settings[key]) ~= "boolean" then
			data.settings[key] = default
		end
	end

	-- week 2: Blocklings (drop unknown species, keep positive integer counts)
	local owned = {}
	if typeof(data.blocklings) == "table" then
		for id, count in data.blocklings do
			if Progression.Species(id) and typeof(count) == "number" and count >= 1 then
				owned[id] = math.floor(count)
			end
		end
	end
	data.blocklings = owned
	local mutations = {}
	if typeof(data.mutations) == "table" then
		for id, mutation in data.mutations do
			if owned[id] and typeof(mutation) == "string" and Progression.MutationRank(mutation) > 0 then
				mutations[id] = mutation
			end
		end
	end
	data.mutations = mutations
	local equipped = {}
	if typeof(data.equippedBlocklings) == "table" then
		local slots = Progression.BlocklingSlots(data.rebirths)
		for _, id in data.equippedBlocklings do
			if typeof(id) == "string" and owned[id] and not table.find(equipped, id) and #equipped < slots then
				table.insert(equipped, id)
			end
		end
	end
	data.equippedBlocklings = equipped
	data.rebirths = math.clamp(math.floor(data.rebirths), 0, Config.Rebirth.MaxRebirths)
	data.blocksSinceBlockling = math.max(0, math.floor(data.blocksSinceBlockling))
	if typeof(data.daily) ~= "table" then
		data.daily = { lastClaim = 0, streak = 0 }
	end
	if typeof(data.daily.lastClaim) ~= "number" or data.daily.lastClaim > os.time() then
		data.daily.lastClaim = 0
	end
	if typeof(data.daily.streak) ~= "number" or data.daily.streak < 0 then
		data.daily.streak = 0
	end

	-- quests: keep only well-formed entries for known quests
	local quests = if typeof(data.quests) == "table" then data.quests else {}
	local list = {}
	if typeof(quests.list) == "table" then
		for _, quest in quests.list do
			local def = typeof(quest) == "table" and Progression.Quest(quest.id)
			if def and typeof(quest.progress) == "number" and #list < Config.Quests.PerDay then
				table.insert(list, {
					id = quest.id,
					progress = math.clamp(math.floor(quest.progress), 0, def.Target),
					claimed = quest.claimed == true,
				})
			end
		end
	end
	data.quests = { day = if typeof(quests.day) == "number" then quests.day else -1, list = list }
	if typeof(data.seenRelease) ~= "string" then
		data.seenRelease = ""
	end
end

local function createLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = folder
	folder.Parent = player
end

-- Studio without "Enable Studio Access to API Services" (or an unpublished place)
-- has no DataStore access: fall back to the in-memory Mock so testing still works.
local storeResolved = false
local function resolveStudioStore()
	if storeResolved then
		return
	end
	if not RunService:IsStudio() or Config.Data.UseMockInStudio then
		storeResolved = true
		return
	end
	local deadline = os.clock() + 6
	while ProfileStore.DataStoreState == "NotReady" and os.clock() < deadline do
		task.wait(0.1)
	end
	if not storeResolved then
		storeResolved = true
		if ProfileStore.DataStoreState ~= "Access" then
			store = store.Mock
			warn(
				"[DataService] No DataStore access in Studio. Publish the place and enable "
					.. "'Studio Access to API Services' to test saving. Using ProfileStore.Mock for now."
			)
		end
	end
end

local function onPlayerAdded(player: Player)
	resolveStudioStore()
	local profile = store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- Player left while loading, or the server is shutting down
		if player.Parent == Players then
			player:Kick("Bonk Blocks couldn't load your data. Please rejoin!")
		end
		return
	end

	profile:AddUserId(player.UserId) -- GDPR
	profile:Reconcile() -- fill fields added to TEMPLATE since the last save

	profile.OnSessionEnd:Connect(function()
		if profiles[player] == profile then
			profiles[player] = nil
			previousLogin[player] = nil
			DataService.ProfileReleased:Fire(player)
		end
		-- Session ended by someone else (another server stole the lock): kick to prevent dupes
		if player.Parent == Players and not releasedByUs[player] then
			player:Kick("Your data was opened on another server. Please rejoin!")
		end
	end)

	if player.Parent ~= Players then
		releasedByUs[player] = true
		profile:EndSession()
		return
	end

	sanitize(profile.Data)
	previousLogin[player] = profile.Data.lastLogin
	profile.Data.lastLogin = os.time()
	profiles[player] = profile

	createLeaderstats(player)
	DataService.Sync(player)
	DataService.ProfileLoaded:Fire(player, profile.Data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		releasedByUs[player] = true
		profile:EndSession() -- final save + releases the session lock
	end
end

-- Lifecycle -------------------------------------------------------------------

function DataService.Init()
	store = ProfileStore.New(Config.Data.StoreName, TEMPLATE)
	if RunService:IsStudio() and Config.Data.UseMockInStudio then
		store = store.Mock
		warn("[DataService] Using ProfileStore.Mock: Studio data will NOT persist")
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- ProfileStore also finishes saves on shutdown itself. Ending every session here
	-- makes the final save start immediately and keeps cleanup explicit.
	game:BindToClose(function()
		for player, profile in table.clone(profiles) do
			releasedByUs[player] = true
			if profile:IsActive() then
				profile:EndSession()
			end
		end
	end)
end

return DataService
