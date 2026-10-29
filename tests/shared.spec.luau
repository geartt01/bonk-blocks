--[[
	Unit tests for the pure shared modules + Config design rules.
	Runs outside Roblox with luau.exe via tools/test.ps1 (Roblox globals are stubbed).
	Not synced by Rojo.
]]

local Config = require("../shared/Config")
local HammerStats = require("../shared/HammerStats")
local MathUtil = require("../shared/MathUtil")
local Signal = require("../shared/Signal")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL {name}: {err}`)
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

local function near(actual: number, expected: number, label: string?)
	if math.abs(actual - expected) > 1e-6 then
		error(`{label or "value"}: expected ~{expected}, got {actual}`, 2)
	end
end

local ZERO = { power = 0, size = 0, knockback = 0 }

-- MathUtil ----------------------------------------------------------------------

test("formatNumber", function()
	eq(MathUtil.formatNumber(0), "0")
	eq(MathUtil.formatNumber(999), "999")
	eq(MathUtil.formatNumber(1000), "1,000")
	eq(MathUtil.formatNumber(123456), "123,456")
	eq(MathUtil.formatNumber(999999), "999,999")
	eq(MathUtil.formatNumber(1234567), "1.2M")
	eq(MathUtil.formatNumber(2500000000), "2.5B")
	eq(MathUtil.formatNumber(12.7), "12")
end)

test("formatTime", function()
	eq(MathUtil.formatTime(0), "0:00")
	eq(MathUtil.formatTime(59.2), "1:00")
	eq(MathUtil.formatTime(61), "1:01")
	eq(MathUtil.formatTime(180), "3:00")
	eq(MathUtil.formatTime(-5), "0:00")
end)

test("lerp and range", function()
	near(MathUtil.lerp(10, 20, 0.25), 12.5)
	near(MathUtil.range({ Start = 6, Finish = 12 }, 0.5), 9)
	near(MathUtil.range({ Start = 5, Finish = 2.75 }, 1), 2.75)
end)

test("weightedPick follows weights", function()
	local list = { { Weight = 1, Id = "a" }, { Weight = 3, Id = "b" } }
	local roll = 0
	local fakeRng = {
		NextNumber = function(_, lo: number, hi: number)
			return lo + (hi - lo) * roll
		end,
	}
	roll = 0.2 -- 0.8 of 4 -> first bucket (weight 1)
	eq(MathUtil.weightedPick(list, fakeRng :: any).Id, "a")
	roll = 0.5 -- 2.0 of 4 -> second bucket
	eq(MathUtil.weightedPick(list, fakeRng :: any).Id, "b")
	roll = 1
	eq(MathUtil.weightedPick(list, fakeRng :: any).Id, "b")
end)

-- HammerStats -------------------------------------------------------------------

test("base stats at tier 0", function()
	local stats = HammerStats.Compute(ZERO)
	near(stats.damage, Config.Hammer.Damage)
	near(stats.reach, Config.Hammer.Reach)
	near(stats.knockback, Config.Hammer.Knockback)
	near(stats.scale, 1)
	eq(HammerStats.HammerLevel(ZERO), 1)
end)

test("costs, max tier and levels", function()
	local maxPower = HammerStats.MaxTier("power")
	eq(HammerStats.NextCost("power", 0), Config.Upgrades.Defs.power.Tiers[1].Cost)
	eq(HammerStats.NextCost("power", maxPower), nil, "maxed cost")
	eq(HammerStats.TotalTiers({ power = 2, size = 1, knockback = 0 }), 3)
	eq(HammerStats.HammerLevel({ power = 2, size = 1, knockback = 0 }), 4)
	-- multiplier never goes past the last tier
	near(HammerStats.Multiplier("power", maxPower + 10), Config.Upgrades.Defs.power.Tiers[maxPower].Value)
end)

test("cheapest next cost ignores maxed upgrades", function()
	local maxed = {
		power = HammerStats.MaxTier("power"),
		size = HammerStats.MaxTier("size"),
		knockback = 0,
	}
	eq(HammerStats.CheapestNextCost(maxed), Config.Upgrades.Defs.knockback.Tiers[1].Cost)
	maxed.knockback = HammerStats.MaxTier("knockback")
	eq(HammerStats.CheapestNextCost(maxed), nil)
end)

-- Config design rules -------------------------------------------------------------

test("every upgrade: costs and values strictly increase", function()
	for _, id in Config.Upgrades.Order do
		local def = Config.Upgrades.Defs[id]
		assert(def, `missing def for {id}`)
		local lastCost, lastValue = 0, def.Base
		for index, tier in def.Tiers do
			assert(tier.Cost > lastCost, `{id} tier {index} cost must increase`)
			assert(tier.Value > lastValue, `{id} tier {index} value must increase`)
			lastCost, lastValue = tier.Cost, tier.Value
		end
	end
end)

test("30s hook: welcome block + first-crack bonus pays for the first upgrade", function()
	local cheapest = HammerStats.CheapestNextCost(ZERO) :: number
	local earned = Config.Blocks.Welcome.Coins + Config.Coins.FirstCrackBonus
	assert(earned >= cheapest, `first crack pays {earned}, cheapest upgrade costs {cheapest}`)
end)

test("15s hook: welcome block cracks in 3 starter bonks or fewer", function()
	local hits = math.ceil(Config.Blocks.Welcome.Health / Config.Hammer.Damage)
	assert(hits <= 3, `welcome block needs {hits} hits`)
end)

test("round and block config sanity", function()
	assert(Config.Round.RoundTime > 0 and Config.Round.IntermissionTime > 0, "round times must be positive")
	assert(Config.Hammer.CooldownTolerance < Config.Hammer.Cooldown, "tolerance must be below cooldown")
	assert(Config.RateLimits.SwingRequest.PerSecond >= 1 / Config.Hammer.Cooldown, "rate limit below legit swing rate")
	local stages = Config.Blocks.CrackStages
	for i = 2, #stages do
		assert(stages[i] < stages[i - 1], "CrackStages must be descending")
	end
	for _, variant in Config.Blocks.Variants do
		assert(variant.Weight > 0, `variant {variant.Id} needs Weight > 0`)
	end
end)

-- Progression (week 2) ----------------------------------------------------------

local Progression = require("../shared/Progression")

test("every Blockling species is valid", function()
	local seen = {}
	for _, species in Config.Blocklings.Species do
		assert(not seen[species.Id], `duplicate species id {species.Id}`)
		seen[species.Id] = true
		assert(Config.Blocklings.Rarities[species.Rarity], `{species.Id} has unknown rarity {species.Rarity}`)
		assert(species.CoinBonus > 0 and species.CoinBonus < 1, `{species.Id} bonus out of range`)
	end
	for _, rarity in Config.Blocklings.RarityOrder do
		assert(#Progression.SpeciesOfRarity(rarity) > 0, `no species for rarity {rarity}`)
	end
end)

test("Blockling levels and bonuses", function()
	local id = Config.Blocklings.Species[1].Id
	local base = Config.Blocklings.Species[1].CoinBonus
	eq(Progression.Bonus(id, 0), 0, "unowned")
	near(Progression.Bonus(id, 1), base, "level 1")
	near(Progression.Bonus(id, 3), base * (1 + 2 * Config.Blocklings.LevelBonusStep), "level 3")
	near(Progression.Bonus(id, 99), Progression.Bonus(id, Config.Blocklings.MaxLevel), "capped at max level")
	near(Progression.TotalBonus({ id }, { [id] = 1 }), base)
	eq(Progression.Bonus("NotASpecies", 5), 0)
end)

test("collection set bonus", function()
	local owned = {}
	eq(Progression.CompletedSets(owned), 0)
	for _, species in Progression.SpeciesOfRarity("Common") do
		owned[species.Id] = 1
	end
	eq(Progression.IsSetComplete("Common", owned), true)
	eq(Progression.IsSetComplete("Rare", owned), false)
	eq(Progression.CompletedSets(owned), 1)
	near(Progression.SetBonus(owned), Config.Blocklings.SetBonusPerRarity)
end)

test("rebirth cost, multiplier and slots", function()
	eq(Progression.RebirthCost(0), Config.Rebirth.BaseCost)
	assert(Progression.RebirthCost(1) > Progression.RebirthCost(0), "cost must grow")
	near(Progression.RebirthMultiplier(0), 1)
	near(Progression.RebirthMultiplier(2), 1 + 2 * Config.Rebirth.CoinBonusPerRebirth)
	eq(Progression.BlocklingSlots(0), Config.Blocklings.BaseSlots)
	eq(Progression.BlocklingSlots(1000), Config.Blocklings.BaseSlots + #Config.Blocklings.SlotRebirths)
end)

test("first rebirth is reachable (under 2x the full hammer upgrade path)", function()
	local total = 0
	for _, id in Config.Upgrades.Order do
		for _, tier in Config.Upgrades.Defs[id].Tiers do
			total += tier.Cost
		end
	end
	assert(Progression.RebirthCost(0) < total * 2, "first rebirth unreachably expensive")
end)

test("daily: first claim, cooldown, streak and expiry", function()
	local hour = 3600
	local cooldown = Config.Daily.CooldownHours * hour
	local expire = Config.Daily.StreakExpireHours * hour
	local now = 1_000_000_000

	local claimable, streak, day = Progression.DailyState({ lastClaim = 0, streak = 0 }, now)
	eq(claimable, true, "first claim")
	eq(streak, 1)
	eq(day, 1)

	claimable = Progression.DailyState({ lastClaim = now, streak = 1 }, now + cooldown - 1)
	eq(claimable, false, "inside cooldown")

	claimable, streak, day = Progression.DailyState({ lastClaim = now, streak = 1 }, now + cooldown)
	eq(claimable, true, "after cooldown")
	eq(streak, 2)
	eq(day, 2)

	_, streak, day = Progression.DailyState({ lastClaim = now, streak = #Config.Daily.Rewards - 1 }, now + cooldown)
	eq(day, #Config.Daily.Rewards, "last day of the cycle")
	_, streak, day = Progression.DailyState({ lastClaim = now, streak = #Config.Daily.Rewards }, now + cooldown)
	eq(day, 1, "cycle wraps")
	eq(streak, #Config.Daily.Rewards + 1)

	_, streak, day = Progression.DailyState({ lastClaim = now, streak = 5 }, now + expire + 1)
	eq(streak, 1, "expired streak restarts")
	eq(day, 1)
end)

test("daily rewards scale with rebirths and the last day has a Blockling", function()
	eq(Progression.DailyCoins(1, 0), Config.Daily.Rewards[1].Coins)
	assert(Progression.DailyCoins(1, 2) > Progression.DailyCoins(1, 0), "rebirth scaling")
	local last = Config.Daily.Rewards[#Config.Daily.Rewards]
	assert(last.Blockling and Config.Blocklings.Rarities[last.Blockling], "last day should grant a valid-rarity Blockling")
end)

test("quest pool is valid", function()
	local events = { Crack = true, Crush = true, Damage = true, Swing = true, Win = true, Golden = true, Blockling = true, Upgrade = true, Mega = true, PlayerBonk = true }
	local seen = {}
	for _, quest in Config.Quests.Pool do
		assert(not seen[quest.Id], `duplicate quest {quest.Id}`)
		seen[quest.Id] = true
		assert(events[quest.Event], `{quest.Id} uses unknown event {quest.Event} (QuestService never fires it)`)
		assert(quest.Target > 0 and quest.Coins > 0, `{quest.Id} needs Target and Coins > 0`)
	end
	assert(Config.Quests.PerDay <= #Config.Quests.Pool, "PerDay can't exceed the pool size")
end)

test("quest helpers", function()
	local first = Config.Quests.Pool[1]
	eq(Progression.Quest(first.Id), first)
	eq(Progression.QuestCoins(first.Id, 0), first.Coins)
	assert(Progression.QuestCoins(first.Id, 2) > first.Coins, "rebirth scaling")
	eq(Progression.QuestCoins("nope", 0), 0)
	eq(Progression.DayKey(86400 * 3 + 5), 3)
	local id, progress, claimed = Progression.ParseQuestAttr("crack5:4:1")
	eq(id, "crack5")
	eq(progress, 4)
	eq(claimed, true)
	id = Progression.ParseQuestAttr("")
	eq(id, nil)
end)

-- Events, Mega, mutations ----------------------------------------------------------

test("event schedule is a pure function of the clock", function()
	local events = Config.Events
	local interval = events.IntervalMinutes * 60
	local slot = 1000
	local slotStart = slot * interval
	local expected = events.Rotation[(slot % #events.Rotation) + 1]
	local schedule = Progression.EventSchedule(slotStart)
	eq(schedule.current, expected, "current at slot start")
	eq(schedule.nextAt, slotStart + interval, "next slot")
	eq(schedule.nextName, events.Rotation[((slot + 1) % #events.Rotation) + 1], "next name")
	local duration = events.Defs[expected].Duration
	eq(Progression.EventSchedule(slotStart + duration - 1).current, expected, "still running")
	eq(Progression.EventSchedule(slotStart + duration).current, nil, "over")
	eq(Progression.EventSchedule(slotStart + 5).currentEndsAt, slotStart + duration)
end)

test("every event in the rotation exists and fits its slot", function()
	local interval = Config.Events.IntervalMinutes * 60
	for _, name in Config.Events.Rotation do
		local def = Config.Events.Defs[name]
		assert(def, `rotation has unknown event {name}`)
		assert(def.Duration > 0 and def.Duration + Config.Events.WarningSeconds < interval, `{name} overlaps the next slot`)
	end
end)

test("weekly BONK PARTY overrides the rotation on its weekday + hour", function()
	local party = Config.Events.WeeklyParty
	-- 1970-01-03 was a Saturday (wday 7); find the party's start on that day
	local saturday = 2 * 86400
	local start = saturday + party.HourUTC * 3600
	local inside = Progression.EventSchedule(start + 60)
	if party.WeekdayUTC == 7 then
		eq(inside.current, "BonkParty", "party running")
		eq(inside.currentEndsAt, start + party.DurationMinutes * 60, "party end")
		assert(inside.nextAt >= inside.currentEndsAt, "next event comes after the party")
	end
	assert(Config.Events.Defs.BonkParty, "BonkParty def missing")
	local after = Progression.EventSchedule(start + party.DurationMinutes * 60 + 1)
	assert(after.current ~= "BonkParty", "party over")
end)

test("mega block scales with players", function()
	local hp1, coins1 = Progression.MegaStats(1)
	local hp8, coins8 = Progression.MegaStats(8)
	assert(hp8 > hp1 and coins8 > coins1, "should scale")
	local hp0 = Progression.MegaStats(0)
	eq(hp0, hp1, "0 players treated as 1")
	assert(Config.Blocklings.Rarities[Config.Events.Mega.MinRarity], "Mega MinRarity must be a real rarity")
end)

test("mutations rank, multiply and boost bonuses", function()
	eq(Progression.MutationRank(nil), 0)
	eq(Progression.MutationRank(""), 0)
	eq(Progression.MutationRank("Shiny"), 1)
	eq(Progression.MutationRank("Rainbow"), 2)
	eq(Progression.MutationMultiplier(nil), 1)
	local id = Config.Blocklings.Species[1].Id
	near(Progression.Bonus(id, 1, "Shiny"), Progression.Bonus(id, 1) * Config.Blocklings.Mutations.Defs.Shiny.Multiplier)
	assert(Progression.Bonus(id, 1, "Rainbow") > Progression.Bonus(id, 1, "Shiny"), "Rainbow beats Shiny")
	near(Progression.TotalBonus({ id }, { [id] = 1 }, { [id] = "Rainbow" }), Progression.Bonus(id, 1, "Rainbow"))
	for _, name in Config.Blocklings.Mutations.Order do
		local def = Config.Blocklings.Mutations.Defs[name]
		assert(def and def.Chance > 0 and def.Chance < 1, `{name} needs a 0..1 Chance`)
	end
end)

-- Signal ------------------------------------------------------------------------

test("Signal connect, fire, disconnect, once", function()
	local signal = Signal.new()
	local total = 0
	local connection = signal:Connect(function(n)
		total += n
	end)
	signal:Fire(2)
	eq(total, 2)
	connection:Disconnect()
	signal:Fire(5)
	eq(total, 2, "after disconnect")

	local onceCount = 0
	signal:Once(function()
		onceCount += 1
	end)
	signal:Fire()
	signal:Fire()
	eq(onceCount, 1, "Once")
end)

test("Signal disconnect during fire is safe", function()
	local signal = Signal.new()
	local calls = 0
	local first
	first = signal:Connect(function()
		calls += 1
		first:Disconnect()
	end)
	signal:Connect(function()
		calls += 1
	end)
	signal:Fire()
	signal:Fire()
	eq(calls, 3)
end)

print(`{passed} passed, {failed} failed`)
if failed > 0 then
	error("tests failed", 0)
end
