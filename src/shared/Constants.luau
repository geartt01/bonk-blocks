--[[
	Constants: names that must match between server, client and Studio
	(tags, attributes, remotes). Not tunables; those live in Config.
]]

local Constants = {}

-- CollectionService tags you put on Studio parts (see README)
Constants.Tags = {
	BlockSpawnZone = "BlockSpawnZone", -- invisible part above the arena; blocks drop from inside it
	Crusher = "Crusher", -- invisible trigger volume; attribute Team = "Red" | "Blue"
	TeamSpawn = "TeamSpawn", -- spawn pad; attribute Team = "Red" | "Blue" (missing = any team)
	Block = "BonkBlock", -- added by the server to live blocks
	Leaderboard = "Leaderboard", -- optional board part; attribute Face = "Front" (default) etc.
	CrusherVisual = "CrusherVisual", -- optional crusher model parts that "chomp"; attribute Team like the Crusher
}

Constants.RoundState = {
	Waiting = "Waiting",
	Intermission = "Intermission",
	Active = "Active",
	Summary = "Summary",
}

Constants.Mode = {
	Teams = "Teams",
	Coop = "Coop",
}

Constants.TeamIds = { "Red", "Blue", "Crew" }

-- Reliable remotes
Constants.Remotes = {
	SwingRequest = "SwingRequest", -- C->S intent: (blockHint: BasePart?)
	PurchaseRequest = "PurchaseRequest", -- C->S intent: (upgradeId: string)
	SettingsRequest = "SettingsRequest", -- C->S intent: (key: string, value: boolean)
	DebugCommand = "DebugCommand", -- C->S, honored in Studio only: (command: string)
	EquipRequest = "EquipRequest", -- C->S intent: (speciesId: string, equip: boolean)
	RebirthRequest = "RebirthRequest", -- C->S intent: ()
	DailyClaimRequest = "DailyClaimRequest", -- C->S intent: ()
	BlocklingFound = "BlocklingFound", -- S->C: { speciesId, count, isNew, source, position?, equipped }
	Rebirthed = "Rebirthed", -- S->All: { userId, name, rebirths }
	DailyResult = "DailyResult", -- S->C: { ok, code, day?, coins?, streak? }
	QuestClaimRequest = "QuestClaimRequest", -- C->S intent: (index: number)
	EmoteRequest = "EmoteRequest", -- C->S intent: (emoteId: string | "" to stop)
	PlayerBonk = "PlayerBonk", -- S->victim: (launchVelocity: Vector3)
	ClientReady = "ClientReady", -- C->S: intro/release card done (ackRelease: boolean)
	PurchaseResult = "PurchaseResult", -- S->C
	BlockBurst = "BlockBurst", -- S->All: block cracked / crushed / despawned
	RoundSummary = "RoundSummary", -- S->All
	Notify = "Notify", -- S->C toast
}

-- Cosmetic, high-frequency remotes (dropping one is fine)
Constants.UnreliableRemotes = {
	SwingFx = "SwingFx", -- S->All: (player)
	BlockHit = "BlockHit", -- S->All: (part, hitPos, damage, attackerUserId, hp, maxHp)
	PlayerBonkFx = "PlayerBonkFx", -- S->All: (victimUserId, attackerUserId)
}

-- Player attributes (server writes, client reads; the server never trusts them)
Constants.PlayerAttr = {
	Loaded = "DataLoaded",
	Coins = "Coins",
	HammerLevel = "HammerLevel",
	TotalCrushed = "TotalCrushed",
	Rebirths = "Rebirths",
	Equipped = "Equipped", -- comma-separated species ids
	Slots = "BlocklingSlots",
	DailyStreak = "DailyStreak",
	DailyDay = "DailyDay", -- reward day the next claim gives
	DailyNextAt = "DailyNextAt", -- unix time the next claim unlocks (0 = now)
	SeenRelease = "SeenRelease", -- last Config.Release.Version this player dismissed
	ClientReady = "ClientReady", -- true once the intro is done (welcome block waits for it)
}

function Constants.BlocklingAttr(speciesId: string): string
	return "Bl_" .. speciesId
end

-- Best mutation owned for a species ("" | "Shiny" | "Rainbow")
function Constants.MutationAttr(speciesId: string): string
	return "BlM_" .. speciesId
end

-- Quest slot i as "questId:progress:claimed(0/1)"
function Constants.QuestAttr(index: number): string
	return "Quest" .. index
end

function Constants.UpgradeAttr(upgradeId: string): string
	return "Upg_" .. upgradeId
end

-- Player settings saved in the profile (key -> default). Booleans only.
Constants.SettingDefaults = {
	sfx = true,
	shake = true,
	bigui = false, -- accessibility: +20% HUD size
}

function Constants.SettingAttr(key: string): string
	return "Set_" .. key
end

-- Block attributes
Constants.BlockAttr = {
	Id = "BlockId",
	HP = "HP",
	MaxHP = "MaxHP",
	Variant = "Variant",
}

-- Replicated round state (Folder in ReplicatedStorage, values as attributes)
Constants.GameStateName = "BonkGameState"
Constants.GameAttr = {
	State = "State",
	Mode = "Mode",
	EndsAt = "EndsAt", -- workspace:GetServerTimeNow() timestamp
	Round = "Round",
	CoopTarget = "CoopTarget",
	Event = "Event", -- running server-wide event name ("" = none)
	EventEndsAt = "EventEndsAt", -- unix time
}

function Constants.ScoreAttr(teamId: string): string
	return "Score" .. teamId
end

Constants.AssetsFolder = "BonkAssets" -- optional ServerStorage folder for custom hammer/blocks
Constants.BlocksFolder = "BonkBlocks" -- workspace folder for live blocks
Constants.HammerModelName = "BonkHammer"
Constants.GripName = "BonkGrip"

return Constants
