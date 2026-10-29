--[[
	Progression: pure math for Blocklings, Rebirth and Daily rewards.
	Shared so the server (authority), the UI and the unit tests use identical numbers.
]]

local Config = require(script.Parent:WaitForChild("Config"))

export type Species = {
	Id: string,
	Name: string,
	Rarity: string,
	CoinBonus: number,
	Color: Color3,
	Material: Enum.Material,
	Accessory: string?,
}

export type DailyData = { lastClaim: number, streak: number }

local Progression = {}

local speciesById: { [string]: Species } = {}
local speciesByRarity: { [string]: { Species } } = {}
for _, species in Config.Blocklings.Species do
	speciesById[species.Id] = species
	speciesByRarity[species.Rarity] = speciesByRarity[species.Rarity] or {}
	table.insert(speciesByRarity[species.Rarity], species)
end

-- Blocklings ----------------------------------------------------------------------

function Progression.Species(id: string): Species?
	return speciesById[id]
end

function Progression.AllSpecies(): { Species }
	return Config.Blocklings.Species
end

function Progression.SpeciesOfRarity(rarity: string): { Species }
	return speciesByRarity[rarity] or {}
end

function Progression.RarityIndex(rarity: string): number
	return table.find(Config.Blocklings.RarityOrder, rarity) or 1
end

function Progression.Level(count: number): number
	return math.clamp(math.floor(count), 0, Config.Blocklings.MaxLevel)
end

-- 0 = none, 1 = Shiny, 2 = Rainbow (index in Mutations.Order)
function Progression.MutationRank(mutation: string?): number
	if not mutation or mutation == "" then
		return 0
	end
	return table.find(Config.Blocklings.Mutations.Order, mutation) or 0
end

function Progression.MutationMultiplier(mutation: string?): number
	local def = mutation and Config.Blocklings.Mutations.Defs[mutation]
	return if def then def.Multiplier else 1
end

-- Coin bonus of one species at a given owned count (0 if not owned), x its mutation
function Progression.Bonus(id: string, count: number, mutation: string?): number
	local species = speciesById[id]
	local level = Progression.Level(count)
	if not species or level <= 0 then
		return 0
	end
	return species.CoinBonus
		* (1 + (level - 1) * Config.Blocklings.LevelBonusStep)
		* Progression.MutationMultiplier(mutation)
end

function Progression.TotalBonus(equipped: { string }, owned: { [string]: number }, mutations: { [string]: string }?): number
	local total = 0
	for _, id in equipped do
		total += Progression.Bonus(id, owned[id] or 0, mutations and mutations[id])
	end
	return total
end

-- Collection sets: own at least one of every species in a rarity
function Progression.IsSetComplete(rarity: string, owned: { [string]: number }): boolean
	local pool = speciesByRarity[rarity]
	if not pool or #pool == 0 then
		return false
	end
	for _, species in pool do
		if (owned[species.Id] or 0) < 1 then
			return false
		end
	end
	return true
end

function Progression.CompletedSets(owned: { [string]: number }): number
	local count = 0
	for _, rarity in Config.Blocklings.RarityOrder do
		if Progression.IsSetComplete(rarity, owned) then
			count += 1
		end
	end
	return count
end

function Progression.SetBonus(owned: { [string]: number }): number
	return Progression.CompletedSets(owned) * Config.Blocklings.SetBonusPerRarity
end

function Progression.BlocklingSlots(rebirths: number): number
	local slots = Config.Blocklings.BaseSlots
	for _, threshold in Config.Blocklings.SlotRebirths do
		if rebirths >= threshold then
			slots += 1
		end
	end
	return slots
end

-- Rebirth -----------------------------------------------------------------------

function Progression.RebirthCost(rebirths: number): number
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ rebirths)
end

function Progression.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.Rebirth.CoinBonusPerRebirth
end

-- Daily -------------------------------------------------------------------------

-- Returns claimable, the streak value after claiming, the reward day (1..#Rewards), and
-- the unix time the next claim unlocks.
function Progression.DailyState(daily: DailyData, now: number): (boolean, number, number, number)
	local cooldown = Config.Daily.CooldownHours * 3600
	local expire = Config.Daily.StreakExpireHours * 3600
	local last = daily.lastClaim or 0
	if last <= 0 then
		return true, 1, 1, 0
	end
	local elapsed = now - last
	local nextStreak = if elapsed > expire then 1 else (daily.streak or 0) + 1
	local day = ((nextStreak - 1) % #Config.Daily.Rewards) + 1
	return elapsed >= cooldown, nextStreak, day, last + cooldown
end

function Progression.DailyCoins(day: number, rebirths: number): number
	local reward = Config.Daily.Rewards[day]
	return math.floor(reward.Coins * (1 + rebirths * Config.Daily.RebirthScale))
end

-- Events --------------------------------------------------------------------------

export type EventSchedule = {
	current: string?, -- event running right now (by the clock)
	currentEndsAt: number,
	nextName: string,
	nextAt: number, -- unix time the next event starts
}

-- Pure function of time: every server and every client computes the same schedule.
function Progression.EventSchedule(now: number): EventSchedule
	local events = Config.Events
	local interval = events.IntervalMinutes * 60

	-- Weekly party overrides the rotation while it runs
	local party = events.WeeklyParty
	if party and party.Enabled then
		local clock = os.date("!*t", math.floor(now)) :: any
		if clock.wday == party.WeekdayUTC and clock.hour == party.HourUTC and clock.min < party.DurationMinutes then
			local partyEnd = math.floor(now) - clock.min * 60 - clock.sec + party.DurationMinutes * 60
			local afterSlot = math.ceil(partyEnd / interval)
			return {
				current = "BonkParty",
				currentEndsAt = partyEnd,
				nextName = events.Rotation[(afterSlot % #events.Rotation) + 1],
				nextAt = afterSlot * interval,
			}
		end
	end

	local slot = math.floor(now / interval)
	local slotStart = slot * interval
	local currentName = events.Rotation[(slot % #events.Rotation) + 1]
	local def = events.Defs[currentName]
	local running = def ~= nil and now < slotStart + def.Duration
	local nextSlot = slot + 1
	return {
		current = if running then currentName else nil,
		currentEndsAt = if running then slotStart + def.Duration else 0,
		nextName = events.Rotation[(nextSlot % #events.Rotation) + 1],
		nextAt = nextSlot * interval,
	}
end

-- Mega Block numbers for a given player count
function Progression.MegaStats(playerCount: number): (number, number)
	local mega = Config.Events.Mega
	local players = math.max(1, playerCount)
	return mega.HealthBase + mega.HealthPerPlayer * players, mega.CoinsBase + mega.CoinsPerPlayer * players
end

-- Quests ------------------------------------------------------------------------

export type QuestDef = { Id: string, Text: string, Event: string, Target: number, Coins: number }

local questById: { [string]: QuestDef } = {}
for _, quest in Config.Quests.Pool do
	questById[quest.Id] = quest
end

function Progression.Quest(id: string): QuestDef?
	return questById[id]
end

function Progression.QuestCoins(id: string, rebirths: number): number
	local quest = questById[id]
	if not quest then
		return 0
	end
	return math.floor(quest.Coins * (1 + rebirths * Config.Quests.RebirthScale))
end

-- UTC day number; quests reroll when it changes
function Progression.DayKey(now: number): number
	return math.floor(now / 86400)
end

-- "id:progress:claimed" (the replicated attribute format) -> parts
function Progression.ParseQuestAttr(value: any): (string?, number, boolean)
	if typeof(value) ~= "string" or value == "" then
		return nil, 0, false
	end
	local parts = string.split(value, ":")
	return parts[1], tonumber(parts[2]) or 0, parts[3] == "1"
end

return Progression
