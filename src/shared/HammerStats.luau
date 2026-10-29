--[[
	HammerStats: pure functions that turn upgrade tiers into hammer stats and costs.
	The server uses them for validation, the client uses the same math for UI.
]]

local Config = require(script.Parent:WaitForChild("Config"))
local Types = require(script.Parent:WaitForChild("Types"))

type Upgrades = Types.Upgrades
type HammerStats = Types.HammerStats

local HammerStats = {}

function HammerStats.MaxTier(upgradeId: string): number
	return #Config.Upgrades.Defs[upgradeId].Tiers
end

function HammerStats.Multiplier(upgradeId: string, tier: number): number
	local def = Config.Upgrades.Defs[upgradeId]
	if tier <= 0 then
		return def.Base
	end
	return def.Tiers[math.min(tier, #def.Tiers)].Value
end

-- Cost of the next tier, or nil if maxed
function HammerStats.NextCost(upgradeId: string, tier: number): number?
	local nextTier = Config.Upgrades.Defs[upgradeId].Tiers[tier + 1]
	return nextTier and nextTier.Cost
end

function HammerStats.Compute(upgrades: Upgrades): HammerStats
	local power = HammerStats.Multiplier("power", upgrades.power or 0)
	local size = HammerStats.Multiplier("size", upgrades.size or 0)
	local knockback = HammerStats.Multiplier("knockback", upgrades.knockback or 0)
	return {
		damage = Config.Hammer.Damage * power,
		reach = Config.Hammer.Reach * size,
		knockback = Config.Hammer.Knockback * knockback,
		scale = size,
		cooldown = Config.Hammer.Cooldown,
	}
end

function HammerStats.TotalTiers(upgrades: Upgrades): number
	local total = 0
	for _, id in Config.Upgrades.Order do
		total += upgrades[id] or 0
	end
	return total
end

function HammerStats.HammerLevel(upgrades: Upgrades): number
	return 1 + HammerStats.TotalTiers(upgrades)
end

function HammerStats.CheapestNextCost(upgrades: Upgrades): number?
	local cheapest: number? = nil
	for _, id in Config.Upgrades.Order do
		local cost = HammerStats.NextCost(id, upgrades[id] or 0)
		if cost and (cheapest == nil or cost < cheapest) then
			cheapest = cost
		end
	end
	return cheapest
end

-- Human-readable stat for the shop card ("14", "8.1", "x1.20")
function HammerStats.StatText(upgradeId: string, tier: number): string
	local mult = HammerStats.Multiplier(upgradeId, tier)
	if upgradeId == "power" then
		return tostring(math.floor(Config.Hammer.Damage * mult + 0.5))
	elseif upgradeId == "size" then
		return string.format("%.1f", Config.Hammer.Reach * mult)
	end
	return string.format("x%.2f", mult)
end

return HammerStats
