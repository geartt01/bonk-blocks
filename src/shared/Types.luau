--[[
	Types: shared Luau type definitions. Usage:
		local Types = require(Shared.Types)
		type PlayerData = Types.PlayerData
]]

export type Upgrades = { [string]: number } -- upgradeId -> tier (0 = not bought)

export type PlayerData = {
	coins: number,
	hammerLevel: number, -- 1 + sum of upgrade tiers (handy for matchmaking/leaderboards)
	upgrades: Upgrades,
	rebirths: number, -- week 2
	totalBlocksCrushed: number, -- blocks this player helped break (crack or crush)
	lastLogin: number, -- os.time() of this session's start
	settings: { [string]: boolean }, -- see Constants.SettingDefaults
	-- week 2
	blocklings: { [string]: number }, -- speciesId -> owned count (level = min(count, MaxLevel))
	equippedBlocklings: { string },
	mutations: { [string]: string }, -- speciesId -> best mutation ("Shiny" | "Rainbow")
	blocksSinceBlockling: number, -- pity counter
	daily: { lastClaim: number, streak: number },
	quests: { day: number, list: { { id: string, progress: number, claimed: boolean } } },
	seenRelease: string, -- Config.Release.Version last dismissed
}

export type HammerStats = {
	damage: number,
	reach: number,
	knockback: number,
	scale: number,
	cooldown: number,
}

export type Payout = { userId: number, coins: number }

export type BurstPayload = {
	position: Vector3,
	size: number,
	color: Color3,
	reason: string, -- "Crack" | "Crush" | "Despawn"
	teamId: string?, -- team that scored (Crush during a live round only)
	points: number?, -- score added, when teamId is set
	kind: string?, -- "Mega" / "Meteor" for event blocks
	payouts: { Payout },
}

export type SummaryEntry = {
	userId: number,
	name: string,
	teamId: string?,
	damage: number,
	cracks: number,
	crushes: number,
	coins: number,
}

export type RoundSummary = {
	round: number,
	mode: string,
	winner: string, -- "Red" | "Blue" | "Crew" | "Draw" | "None"
	scores: { [string]: number },
	coopTarget: number,
	players: { SummaryEntry },
	mvpUserId: number?,
}

export type PurchaseResult = {
	ok: boolean,
	code: string, -- "Purchased" | "NotEnoughCoins" | "ShopClosed" | "Maxed" | "Loading"
	upgradeId: string?,
	tier: number?,
}

return {}
