--[[
	BlocklingService: collectible critters that pop out of broken blocks.

	Drops: every contributor to a cracked/crushed block rolls once
	(Config.Blocklings.DropChance x variant x crush x event multipliers). A player's first
	Blockling is guaranteed by their FirstGuaranteedAt-th block, and a pity counter
	guarantees one every PityBlocks blocks. Mega Block contributors always get one
	(at least Config.Events.Mega.MinRarity). Duplicates level the species up.

	Mutations (Shiny / Rainbow) roll on every grant; a species keeps its best one,
	which multiplies its bonus. Equipped Blocklings + completed sets boost earned coins
	through CoinService.RegisterMultiplier; clients render pets from player attributes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local MathUtil = require(Shared.MathUtil)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local Signal = require(Shared.Signal)

local BlockService = require(script.Parent.BlockService)
local CoinService = require(script.Parent.CoinService)
local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local BlocklingService = {}
BlocklingService.Granted = Signal.new() -- (player, speciesId, newCount, source, mutation: string?)

local BL = Config.Blocklings
local Mutations = BL.Mutations
local rng = Random.new()
local limiter = RateLimiter.new("EquipRequest", { PerSecond = 5, Burst = 8 })
local foundRemote, notifyRemote

-- EventService plugs in here (Bonanza): returns dropMultiplier, mutationMultiplier
local eventBoost: () -> (number, number) = function()
	return 1, 1
end

function BlocklingService.SetEventBoost(fn: () -> (number, number))
	eventBoost = fn
end

local function notify(player: Player, text: string, kind: string?)
	notifyRemote:FireClient(player, { text = text, kind = kind })
end

-- Random species id; minRarity (e.g. "Rare") cuts off the lower rarities.
function BlocklingService.Roll(minRarity: string?): string
	local order = BL.RarityOrder
	local minIndex = if minRarity then Progression.RarityIndex(minRarity) else 1
	local entries = {}
	for index = minIndex, #order do
		local rarity = order[index]
		if #Progression.SpeciesOfRarity(rarity) > 0 then
			table.insert(entries, { Weight = BL.Rarities[rarity].Weight, rarity = rarity })
		end
	end
	local rarity = MathUtil.weightedPick(entries, rng).rarity
	local pool = Progression.SpeciesOfRarity(rarity)
	return pool[rng:NextInteger(1, #pool)].Id
end

-- Rarest mutation first; nil = no mutation
function BlocklingService.RollMutation(): string?
	local _, mutationMultiplier = eventBoost()
	for index = #Mutations.Order, 1, -1 do
		local name = Mutations.Order[index]
		if rng:NextNumber() < Mutations.Defs[name].Chance * mutationMultiplier then
			return name
		end
	end
	return nil
end

local function ownedTotal(data): number
	local total = 0
	for _, count in data.blocklings do
		total += count
	end
	return total
end

-- Gives a Blockling (duplicates raise its count/level). Auto-equips into a free slot.
function BlocklingService.Grant(player: Player, speciesId: string, source: string, position: Vector3?): boolean
	local data = DataService.GetData(player)
	local species = Progression.Species(speciesId)
	if not data or not species then
		return false
	end

	local setWasComplete = Progression.IsSetComplete(species.Rarity, data.blocklings)
	local count = (data.blocklings[speciesId] or 0) + 1
	data.blocklings[speciesId] = count
	data.blocksSinceBlockling = 0

	-- Mutation: keep the best one this species has ever rolled
	local mutation = BlocklingService.RollMutation()
	local mutationUpgraded = false
	if mutation and Progression.MutationRank(mutation) > Progression.MutationRank(data.mutations[speciesId]) then
		data.mutations[speciesId] = mutation
		mutationUpgraded = true
	end

	local equipped = false
	if
		#data.equippedBlocklings < Progression.BlocklingSlots(data.rebirths)
		and not table.find(data.equippedBlocklings, speciesId)
	then
		table.insert(data.equippedBlocklings, speciesId)
		equipped = true
	end

	DataService.Sync(player)
	foundRemote:FireClient(player, {
		speciesId = speciesId,
		count = count,
		isNew = count == 1,
		source = source,
		position = position,
		equipped = equipped,
		mutation = if mutationUpgraded then mutation else data.mutations[speciesId],
		newMutation = mutationUpgraded,
	})
	BlocklingService.Granted:Fire(player, speciesId, count, source, if mutationUpgraded then mutation else nil)

	if mutationUpgraded and Progression.MutationRank(mutation) >= #Mutations.Order then
		-- Rainbow: tell the whole server (a clip-worthy moment)
		notifyRemote:FireAllClients({ text = `{player.DisplayName} found a RAINBOW {species.Name}!`, kind = "Gold" })
	elseif count == 1 and Progression.RarityIndex(species.Rarity) >= Progression.RarityIndex("Epic") then
		-- First-ever Epic/Legendary: server-wide shout too (rare pulls are what gets clipped)
		notifyRemote:FireAllClients({ text = `{player.DisplayName} found a {string.upper(species.Rarity)} {species.Name}!`, kind = "Gold" })
	end
	if not setWasComplete and Progression.IsSetComplete(species.Rarity, data.blocklings) then
		task.delay(3.5, function() -- after the reveal card
			if player.Parent == Players then
				notify(player, `{species.Rarity} set complete! +{math.floor(BL.SetBonusPerRarity * 100)}% coins forever`, "Gold")
			end
		end)
	end
	return true
end

local function rollDrop(player: Player, variant: string, reason: string, position: Vector3)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	data.blocksSinceBlockling += 1

	local dropMultiplier = eventBoost()
	local chance = BL.DropChance * (BL.VariantMultipliers[variant] or 1) * dropMultiplier
	if reason == "Crush" then
		chance *= BL.CrushMultiplier
	end
	local firstGuaranteed = ownedTotal(data) == 0 and data.totalBlocksCrushed >= BL.FirstGuaranteedAt
	local pity = data.blocksSinceBlockling >= BL.PityBlocks
	if firstGuaranteed or pity or rng:NextNumber() < chance then
		BlocklingService.Grant(player, BlocklingService.Roll(nil), "Block", position)
	end
end

local function onEquipRequest(player: Player, speciesId: any, equip: any)
	if not limiter:Allow(player) then
		return
	end
	if typeof(speciesId) ~= "string" or not Progression.Species(speciesId) or typeof(equip) ~= "boolean" then
		RateLimiter.Reject(player, "EquipRequest", "bad args")
		return
	end
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local index = table.find(data.equippedBlocklings, speciesId)
	if equip then
		if index then
			return
		end
		if (data.blocklings[speciesId] or 0) < 1 then
			notify(player, "You haven't found that Blockling yet!")
			return
		end
		local slots = Progression.BlocklingSlots(data.rebirths)
		if #data.equippedBlocklings >= slots then
			notify(player, `All {slots} slot(s) are full. Unequip one first (rebirth for more slots)`)
			return
		end
		table.insert(data.equippedBlocklings, speciesId)
	elseif index then
		table.remove(data.equippedBlocklings, index)
	end
	DataService.Sync(player)
end

function BlocklingService.Init()
	foundRemote = Net.Get(Constants.Remotes.BlocklingFound)
	notifyRemote = Net.Get(Constants.Remotes.Notify)
end

function BlocklingService.Start()
	CoinService.RegisterMultiplier("Blocklings", function(player, _amount, reason)
		if not BL.BonusReasons[reason] then
			return 1
		end
		local data = DataService.GetData(player)
		if not data then
			return 1
		end
		return 1
			+ Progression.TotalBonus(data.equippedBlocklings, data.blocklings, data.mutations)
			+ Progression.SetBonus(data.blocklings)
	end)

	BlockService.BlockResolved:Connect(function(state, reason, _scoringTeam, payouts)
		if reason == "Despawn" then
			return
		end
		local position = state.part.Position
		for _, payout in payouts do
			if payout.player.Parent == Players then
				if state.kind == "Mega" then
					BlocklingService.Grant(payout.player, BlocklingService.Roll(Config.Events.Mega.MinRarity), "Mega", position)
				else
					rollDrop(payout.player, state.variant, reason, position)
				end
			end
		end
	end)

	Net.Get(Constants.Remotes.EquipRequest).OnServerEvent:Connect(onEquipRequest)
end

return BlocklingService
