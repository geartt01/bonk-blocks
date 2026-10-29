--[[
	Config: every tunable value lives here. Shared by server and client.

	The server is the authority. The client only reads Config to draw UI and
	to predict its own cooldown; the server re-checks everything.
	Sound/texture ids of "" or "rbxassetid://0" are treated as "not set".
]]

local Config = {}

-- Rounds ----------------------------------------------------------------------

Config.Round = {
	FirstIntermission = 4, -- countdown when the first player arrives on an empty server
	IntermissionTime = 15, -- lobby countdown between rounds (shop open, warm-up blocks)
	RoundTime = 180, -- 3-minute rounds
	SummaryTime = 8, -- results screen
	TeamModeMinPlayers = 4, -- fewer players than this => co-op vs the timer
}

Config.Coop = {
	TargetBase = 6, -- crusher points needed with 1 player
	TargetPerExtraPlayer = 4, -- + this per extra player
}

Config.Teams = {
	Red = {
		DisplayName = "Red Bonkers",
		ShortName = "RED",
		TeamColor = BrickColor.new("Bright red"),
		Color = Color3.fromRGB(255, 86, 86),
	},
	Blue = {
		DisplayName = "Blue Bonkers",
		ShortName = "BLUE",
		TeamColor = BrickColor.new("Bright blue"),
		Color = Color3.fromRGB(70, 150, 255),
	},
	Crew = {
		DisplayName = "Bonk Crew",
		ShortName = "CREW",
		TeamColor = BrickColor.new("Bright yellow"),
		Color = Color3.fromRGB(255, 205, 60),
	},
}

-- Blocks ----------------------------------------------------------------------
-- Values with Start/Finish are lerped over the round (progress 0 -> 1, eased by ScaleCurve).

Config.Blocks = {
	MaxActiveBase = 3,
	MaxActivePerPlayer = 0.75,
	MaxActiveCap = 14, -- Bonk Stadium fits 12 players
	SpawnInterval = { Start = 4.5, Finish = 2.25 }, -- seconds between drops
	WarmupInterval = 6,
	WarmupMaxActive = 2,

	Size = { Start = 6, Finish = 12 }, -- studs (cube edge)
	Health = { Start = 30, Finish = 260 },
	Coins = { Start = 10, Finish = 55 }, -- coin pool split between contributors
	Points = { Start = 1, Finish = 4 }, -- team score when crushed
	Heft = { Start = 1, Finish = 2 }, -- knockback resistance (divides launch speed)
	ScaleCurve = 1.25,
	HealthPerExtraPlayer = 0.12, -- +12% HP per player beyond the first

	Density = 0.6,
	Friction = 0.5,
	Elasticity = 0.15,

	CrackStages = { 0.66, 0.33 }, -- HP fractions where crack visuals kick in
	DamageKnockbackBonus = 1.2, -- a nearly-dead block flies (1 + this)x farther
	CrusherCoinMultiplier = 1.5, -- bonus for contributors on the crusher's team
	KillY = -50, -- blocks below this world Y vanish (no reward)
	IdleDespawnTime = 60, -- untouched this long => poof

	Palette = { -- random colors for the plain mystery block
		Color3.fromRGB(255, 120, 170),
		Color3.fromRGB(140, 110, 255),
		Color3.fromRGB(80, 200, 255),
		Color3.fromRGB(255, 160, 60),
	},
	Variants = {
		{ Id = "Mystery", Weight = 78, CoinMultiplier = 1, Label = "?", Material = Enum.Material.SmoothPlastic },
		{
			Id = "Bouncy",
			Weight = 14,
			CoinMultiplier = 1.5,
			Label = "!",
			Color = Color3.fromRGB(120, 230, 120),
			Material = Enum.Material.SmoothPlastic,
			Elasticity = 0.85,
		},
		{
			Id = "Golden",
			Weight = 8,
			CoinMultiplier = 3,
			Label = "$",
			Color = Color3.fromRGB(255, 215, 70),
			Material = Enum.Material.Foil,
		},
	},

	-- The 30-second hook: a small, soft block dropped right in front of a new player.
	Welcome = {
		Enabled = true,
		Delay = 1.5, -- seconds after the character spawns (and data is loaded)
		Distance = 9, -- studs in front of the player
		Size = 6,
		Health = 18, -- 2 bonks with a starter hammer
		Coins = 20,
	},
}

-- Hammer ----------------------------------------------------------------------

Config.Hammer = {
	Cooldown = 0.45,
	CooldownTolerance = 0.1, -- server accepts a swing this much early (network jitter)
	Damage = 10,
	Reach = 7, -- studs from HumanoidRootPart to the block's surface
	ReachTolerance = 3.5, -- extra studs the server allows (latency)
	ArcDot = -0.25, -- min dot(look, dirToBlock); -0.25 is about a 200 degree cone
	Knockback = 30, -- velocity change (studs/s) on a fresh, heft-1 block
	UpwardBias = 0.55,
	Spin = 3, -- rad/s of tumble added per hit
	Windup = 0.12, -- client: time from press to the top of the swing
	AutoFaceTarget = true, -- client turns the character toward the nearest block
	SwingAnimationId = "", -- "rbxassetid://..." to use an Animation instead of the tween

	-- Swing with no block in reach -> launch the nearest player in front (cartoon, no damage)
	PlayerBonk = {
		Enabled = true,
		Force = 42, -- studs/s launch speed (scaled up a little by Knockback upgrades)
		MaxForce = 60, -- stays below Config.AntiCheat.MaxHorizontalSpeed
		UpwardBias = 0.6,
		ReachBonus = 1.5, -- extra studs (players are measured center to center)
		VictimCooldown = 2.5, -- one bonk per victim per 2.5s: no stun-lock
		SpawnProtection = 45, -- seconds after spawning you can't be bonked (protects the 30s hook)
		TeamsEnemiesOnly = true, -- in Teams mode only enemies can be bonked
	},
	ModelName = "Hammer", -- optional ServerStorage.BonkAssets.Hammer (Model with PrimaryPart)
}

-- Upgrades --------------------------------------------------------------------
-- Value is a multiplier on the matching Hammer stat. Tier 0 uses Base.

Config.Upgrades = {
	ShopOpenDuringRound = false, -- spec: buy between rounds
	FirstPurchaseAnytime = true, -- exception so the 30s "first upgrade" hook works mid-round
	Order = { "power", "size", "knockback" },
	Defs = {
		power = {
			DisplayName = "Power",
			Stat = "Damage",
			Description = "Bonk harder. Crack blocks faster.",
			Base = 1,
			Tiers = {
				{ Cost = 25, Value = 1.4 },
				{ Cost = 150, Value = 1.9 },
				{ Cost = 450, Value = 2.6 },
				{ Cost = 1200, Value = 3.5 },
				{ Cost = 3000, Value = 4.8 },
			},
		},
		size = {
			DisplayName = "Size",
			Stat = "Reach",
			Description = "Bigger hammer, longer reach.",
			Base = 1,
			Tiers = {
				{ Cost = 40, Value = 1.15 },
				{ Cost = 200, Value = 1.3 },
				{ Cost = 600, Value = 1.45 },
				{ Cost = 1500, Value = 1.6 },
				{ Cost = 3600, Value = 1.8 },
			},
		},
		knockback = {
			DisplayName = "Knockback",
			Stat = "Launch",
			Description = "Send blocks flying into the crusher.",
			Base = 1,
			Tiers = {
				{ Cost = 35, Value = 1.2 },
				{ Cost = 175, Value = 1.45 },
				{ Cost = 500, Value = 1.75 },
				{ Cost = 1300, Value = 2.1 },
				{ Cost = 3200, Value = 2.5 },
			},
		},
	},
}

-- Economy ---------------------------------------------------------------------

Config.Coins = {
	FirstCrackBonus = 25, -- one-time, the first block a player ever helps break
	ParticipationBonus = 10, -- end of round, players who dealt damage
	WinBonus = 30, -- end of round, winning team / successful crew
	MaxSingleGrant = 1_000_000, -- sanity cap for one CoinService.Add call
}

-- Blocklings (week 2) -----------------------------------------------------------
-- Original cartoon critters that pop out of broken blocks. Each equipped Blockling adds
-- a coin bonus; duplicates level a species up (max MaxLevel) for a bigger bonus.

Config.Blocklings = {
	DropChance = 0.05, -- per contributor, per broken block
	CrushMultiplier = 1.5, -- crushed blocks drop more often than cracked ones
	VariantMultipliers = { Golden = 3, Bouncy = 1.5 }, -- by block variant Id
	FirstGuaranteedAt = 2, -- a player's first Blockling is guaranteed by their 2nd broken block (inside the 3-min bounce window)
	PityBlocks = 40, -- guaranteed drop after this many blocks without one
	BaseSlots = 1, -- equip slots
	SlotRebirths = { 1, 3 }, -- +1 slot at each of these rebirth counts (max 3 slots)
	MaxLevel = 5,
	LevelBonusStep = 0.25, -- each level past 1 adds +25% of the species bonus
	SetBonusPerRarity = 0.05, -- own every species of a rarity: +5% earned coins forever (equipped or not)

	-- Mutations: every drop rolls for one (rarest first). A species keeps its best mutation,
	-- which multiplies that species' bonus. Bonanza events multiply the chances.
	Mutations = {
		Order = { "Shiny", "Rainbow" }, -- worst -> best
		Defs = {
			Shiny = { Chance = 1 / 20, Multiplier = 2, Color = Color3.fromRGB(255, 240, 150) },
			Rainbow = { Chance = 1 / 150, Multiplier = 3, Color = Color3.fromRGB(255, 120, 255) },
		},
	},
	BonusReasons = { BlockCrack = true, BlockCrush = true, RoundBonus = true }, -- coin reasons boosted

	RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" },
	Rarities = {
		Common = { Weight = 62, Color = Color3.fromRGB(200, 200, 210) },
		Uncommon = { Weight = 25, Color = Color3.fromRGB(110, 220, 120) },
		Rare = { Weight = 9, Color = Color3.fromRGB(80, 170, 255) },
		Epic = { Weight = 3.2, Color = Color3.fromRGB(190, 110, 255) },
		Legendary = { Weight = 0.8, Color = Color3.fromRGB(255, 200, 50) },
	},

	-- Accessory: nil | "Leaf" | "Horns" | "Spikes" | "Crown" | "Halo" (built procedurally)
	Species = {
		{ Id = "Pebbit", Name = "Pebbit", Rarity = "Common", CoinBonus = 0.03, Color = Color3.fromRGB(160, 160, 170), Material = Enum.Material.Slate },
		{ Id = "Brickle", Name = "Brickle", Rarity = "Common", CoinBonus = 0.03, Color = Color3.fromRGB(190, 90, 70), Material = Enum.Material.SmoothPlastic },
		{ Id = "Mossy", Name = "Mossy", Rarity = "Common", CoinBonus = 0.03, Color = Color3.fromRGB(110, 170, 80), Material = Enum.Material.Grass, Accessory = "Leaf" },
		{ Id = "Puddle", Name = "Puddle", Rarity = "Uncommon", CoinBonus = 0.06, Color = Color3.fromRGB(80, 160, 255), Material = Enum.Material.Glass },
		{ Id = "Toasty", Name = "Toasty", Rarity = "Uncommon", CoinBonus = 0.06, Color = Color3.fromRGB(240, 170, 90), Material = Enum.Material.SmoothPlastic, Accessory = "Horns" },
		{ Id = "Bubblegum", Name = "Bubblegum", Rarity = "Uncommon", CoinBonus = 0.06, Color = Color3.fromRGB(255, 140, 200), Material = Enum.Material.SmoothPlastic },
		{ Id = "Quartzy", Name = "Quartzy", Rarity = "Rare", CoinBonus = 0.12, Color = Color3.fromRGB(200, 170, 255), Material = Enum.Material.Glass, Accessory = "Spikes" },
		{ Id = "Frostcube", Name = "Frostcube", Rarity = "Rare", CoinBonus = 0.12, Color = Color3.fromRGB(170, 230, 255), Material = Enum.Material.Ice },
		{ Id = "Sparky", Name = "Sparky", Rarity = "Epic", CoinBonus = 0.2, Color = Color3.fromRGB(255, 230, 60), Material = Enum.Material.Neon, Accessory = "Spikes" },
		{ Id = "Lavalump", Name = "Lavalump", Rarity = "Epic", CoinBonus = 0.2, Color = Color3.fromRGB(255, 100, 40), Material = Enum.Material.CrackedLava, Accessory = "Horns" },
		{ Id = "Goldie", Name = "Goldie", Rarity = "Legendary", CoinBonus = 0.35, Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Foil, Accessory = "Crown" },
		{ Id = "Cosmo", Name = "Cosmo", Rarity = "Legendary", CoinBonus = 0.35, Color = Color3.fromRGB(120, 80, 220), Material = Enum.Material.Neon, Accessory = "Halo" },
	},
}

-- Rebirth (week 2) --------------------------------------------------------------
-- Reset coins + hammer upgrades for a permanent coin multiplier and Blockling slots.

Config.Rebirth = {
	BaseCost = 10000, -- coins needed for the first rebirth
	CostGrowth = 2, -- each rebirth costs this much more
	CoinBonusPerRebirth = 0.25, -- +25% earned coins per rebirth, forever
	MaxRebirths = 50,
	BetweenRoundsOnly = true,
}

-- Daily rewards (week 2) ----------------------------------------------------------

Config.Daily = {
	CooldownHours = 20, -- claim once per ~day (20h so a daily habit doesn't slip by an hour)
	StreakExpireHours = 48, -- miss this window and the streak restarts at day 1
	RebirthScale = 0.5, -- coin rewards x(1 + rebirths * this)
	Rewards = { -- one entry per day; the cycle repeats after the last
		{ Coins = 50 },
		{ Coins = 100 },
		{ Coins = 150 },
		{ Coins = 250 },
		{ Coins = 400 },
		{ Coins = 600 },
		{ Coins = 800, Blockling = "Rare" }, -- + a Blockling of at least this rarity
	},
}

-- Daily quests (week 2) -----------------------------------------------------------
-- PerDay quests are rolled from Pool each UTC day. Event names are fired by QuestService.

Config.Quests = {
	PerDay = 3,
	RebirthScale = 0.5, -- coin rewards x(1 + rebirths * this)
	Pool = {
		{ Id = "crack5", Text = "Crack 5 blocks", Event = "Crack", Target = 5, Coins = 150 },
		{ Id = "crush3", Text = "Crush 3 blocks", Event = "Crush", Target = 3, Coins = 200 },
		{ Id = "damage600", Text = "Deal 600 damage", Event = "Damage", Target = 600, Coins = 150 },
		{ Id = "swing120", Text = "Swing 120 times", Event = "Swing", Target = 120, Coins = 100 },
		{ Id = "win1", Text = "Win a round", Event = "Win", Target = 1, Coins = 250 },
		{ Id = "golden1", Text = "Break a Golden block", Event = "Golden", Target = 1, Coins = 300 },
		{ Id = "blockling1", Text = "Find a Blockling", Event = "Blockling", Target = 1, Coins = 200 },
		{ Id = "upgrade1", Text = "Buy a hammer upgrade", Event = "Upgrade", Target = 1, Coins = 100 },
		{ Id = "mega1", Text = "Help destroy a Mega Block", Event = "Mega", Target = 1, Coins = 350 },
		{ Id = "bonk5", Text = "Bonk other players 5 times", Event = "PlayerBonk", Target = 5, Coins = 150 },
	},
}

-- Server-wide events --------------------------------------------------------------
-- Scheduled on the real clock (os.time), so EVERY server runs the same event at the
-- same moment ("Mega Block at :00, :10, :20..."). That's an appointment players come
-- back for, and a moment worth clipping. Rotation repeats.

Config.Events = {
	Enabled = true,
	IntervalMinutes = 10, -- an event starts every 10 minutes on the clock
	WarningSeconds = 60, -- countdown banner before it starts
	Rotation = {
		"MegaBlock",
		"GoldenRain",
		"MoonGravity",
		"MegaBlock",
		"Bonanza",
		"MeteorShower",
		"MegaBlock",
		"CoinFrenzy",
		"BouncyHour",
	},
	Defs = {
		MegaBlock = {
			Name = "MEGA BLOCK",
			Description = "A giant block is falling. Everyone, BONK IT!",
			Duration = 120,
			Color = Color3.fromRGB(255, 80, 120),
		},
		GoldenRain = {
			Name = "GOLDEN RAIN",
			Description = "Every block is Golden: x3 coins!",
			Duration = 60,
			Color = Color3.fromRGB(255, 215, 70),
		},
		MoonGravity = {
			Name = "MOON GRAVITY",
			Description = "Low gravity: huge jumps, huge launches!",
			Duration = 60,
			Color = Color3.fromRGB(160, 170, 255),
			Gravity = 60, -- default is 196.2
		},
		Bonanza = {
			Name = "BLOCKLING BONANZA",
			Description = "Blockling drops x3, mutations x2!",
			Duration = 90,
			Color = Color3.fromRGB(80, 220, 160),
			DropMultiplier = 3,
			MutationMultiplier = 2,
		},
		MeteorShower = {
			Name = "METEOR SHOWER",
			Description = "Tiny blocks rain from the sky. Bonk them all!",
			Duration = 45,
			Color = Color3.fromRGB(255, 140, 60),
		},
		CoinFrenzy = {
			Name = "COIN FRENZY",
			Description = "All earned coins x2!",
			Duration = 60,
			Color = Color3.fromRGB(255, 200, 40),
			CoinMultiplier = 2,
		},
		BouncyHour = {
			Name = "BOUNCY HOUR",
			Description = "Every block is super bouncy. Launch them!",
			Duration = 60,
			Color = Color3.fromRGB(120, 230, 120),
		},
		BonkParty = { -- weekly, see WeeklyParty (not in Rotation)
			Name = "BONK PARTY",
			Description = "Weekly party! Mega Blocks, x2 coins, x3 Blocklings!",
			Duration = 1800,
			Color = Color3.fromRGB(255, 110, 200),
			CoinMultiplier = 2,
			DropMultiplier = 3,
			MutationMultiplier = 2,
		},
	},
	-- Every week at WeekdayUTC/HourUTC a party overrides the rotation on every server.
	-- Top 2025-26 games set their CCU records on weekly Saturday events. wday: 1 = Sunday ... 7 = Saturday
	WeeklyParty = { Enabled = true, WeekdayUTC = 7, HourUTC = 18, DurationMinutes = 30 },
	Mega = {
		Size = 24,
		HealthBase = 500,
		HealthPerPlayer = 600, -- scales so 1 or 8 players both get a ~30-60s fight
		CoinsBase = 300,
		CoinsPerPlayer = 100,
		Points = 10, -- if someone manages to crush it
		Heft = 8, -- barely moves
		MinRarity = "Uncommon", -- every contributor gets a Blockling of at least this rarity
	},
	Meteor = {
		Interval = 0.5,
		MaxActive = 14,
		Size = 3,
		Health = 10,
		Coins = 5,
	},
}

-- Presentation --------------------------------------------------------------------

Config.Visuals = {
	ApplyLighting = true, -- bright cartoon daylight, atmosphere, bloom, color grade (server, replicates)
	UiPolish = true, -- glossy gradients + drop shadows on HUD panels and buttons
	UiFx = true, -- button press squash, coins flying into the counter, shine sweeps
}

Config.Intro = {
	Enabled = true, -- camera flies over the stadium with the logo + PLAY button
	AutoContinueSeconds = 12, -- starts the game anyway if nobody presses PLAY
	OrbitRadius = 290, -- sized for the 240 x 180 court + plaza
	OrbitHeight = 110,
}

-- The "RELEASE!!" card: shown once per Version after the intro (and from the UPDATES
-- button). Bump Version with every update so returning players see what's new.
Config.Release = {
	Version = "1.0",
	Title = "RELEASE!!",
	Subtitle = "Bonk Blocks is OUT! Here's what's inside:",
	Items = {
		{ Title = "BONK giant mystery blocks", Text = "Crack them for coins. Knock them into YOUR crusher for team points." },
		{ Title = "12 Blocklings to collect", Text = "Pets that boost your coins. Hunt for Shiny and Rainbow ones!" },
		{ Title = "MEGA BLOCK every 30 minutes", Text = "Plus Golden Rain, Moon Gravity, Coin Frenzy... same time on every server!" },
		{ Title = "BONK PARTY every Saturday", Text = "18:00 UTC: Mega Blocks nonstop, x2 coins, x3 Blocklings for 30 minutes!" },
		{ Title = "Upgrade, Rebirth, Dailies", Text = "Bigger hammer, permanent multipliers, daily rewards and quests." },
		{ Title = "Play with friends", Text = "Every friend in your server gives +10% coins (up to +50%)." },
	},
	HowTo = "TAP BONK to swing  |  Break blocks for coins  |  Push them into your crusher",
	Button = "LET'S BONK!",
}

-- Social ------------------------------------------------------------------------
-- Playing with friends pays: the cheapest real growth lever on Roblox.

Config.Social = {
	BonusPerFriend = 0.1, -- +10% earned coins per friend in your server
	MaxFriends = 5, -- capped at +50% (what top 2025-26 games use)
}

-- Badges ------------------------------------------------------------------------
-- Create badges on the Creator Dashboard (a few free per day) and paste their ids.
-- 0 = not set up yet (skipped silently).

Config.Badges = {
	FirstCrack = 0, -- broke your first block
	FirstBlockling = 0,
	MegaBlock = 0, -- helped destroy a Mega Block
	FirstWin = 0,
	FirstRebirth = 0,
	Rainbow = 0, -- found a Rainbow Blockling
	FullCollection = 0, -- every species
}

-- Emotes ------------------------------------------------------------------------
-- Procedural (no uploaded animations needed): every client poses the R15 joints of
-- anyone emoting. Original moves only (no copyrighted game/TikTok dances).

Config.Emotes = {
	List = {
		{ Id = "Wave", Name = "Wave", Duration = 3 },
		{ Id = "Cheer", Name = "Cheer", Duration = 3 },
		{ Id = "Flex", Name = "Flex", Duration = 3 },
		{ Id = "Spin", Name = "Spin", Duration = 1.6 },
		{ Id = "BonkDance", Name = "Bonk Dance", Duration = 8 },
	},
	VictoryEmote = "BonkDance", -- the winning team dances during the results screen
	VictoryDuration = 7,
	Cooldown = 0.5,
}

-- Security --------------------------------------------------------------------

Config.RateLimits = {
	SwingRequest = { PerSecond = 6, Burst = 6 },
	PurchaseRequest = { PerSecond = 3, Burst = 5 },
	KickAfterDrops = 120, -- dropped requests within DropWindow seconds => kick (0 = never kick)
	DropWindow = 10,
}

Config.AntiCheat = {
	MaxHorizontalSpeed = 70, -- studs/s; default walk is 16, so this only catches teleports/speed hacks
	SampleInterval = 0.25,
	PenaltySeconds = 1.5, -- swings refused this long after a violation
	LogViolations = true,
}

Config.Leaderboard = {
	Enabled = true,
	StoreName = "BonkBlocks_TopCrushers_v1", -- OrderedDataStore (Stat = "Crushed")
	RebirthStoreName = "BonkBlocks_TopRebirths_v1", -- OrderedDataStore (Stat = "Rebirths")
	Size = 10,
	RefreshSeconds = 60,
}

-- Data ------------------------------------------------------------------------

Config.Data = {
	StoreName = "BonkBlocks_Players_v1",
	UseMockInStudio = false, -- true => Studio never touches the real DataStore
}

-- Arena -----------------------------------------------------------------------

Config.Arena = {
	BuildDevArenaIfMissing = true, -- no tagged spawn zone + crusher found => build a test arena
	SpawnHeightOffset = 3,
}

-- Juice -----------------------------------------------------------------------

Config.Vfx = {
	Shake = { -- { magnitude (studs), duration (s) }
		Hit = { 0.25, 0.12 },
		Crack = { 0.9, 0.35 },
		Crush = { 1.4, 0.5 },
		Land = { 0.5, 0.25 }, -- scaled by block size (a 6-stud block = 1x)
	},
	ShakeFalloffDistance = 70,
	DropShadow = true, -- shadow under falling blocks shows where they'll land
	SwingTrail = true, -- swoosh ribbon on the hammer head
	HealthBars = true, -- HP bar over a block once it's been hit
	TeamOutlines = true, -- team-colored character outlines during Teams rounds
	ComboWindow = 1.6, -- seconds between your hits to keep a combo going (cosmetic)
	ComboMinShown = 3, -- combo counter appears from this many hits
	FrenzyCombo = 8, -- anime speed lines from this combo (off when Screen shake is off)
	ImpactFrames = true, -- 1-frame high-contrast flash + FOV punch when your bonk breaks a block
	VictoryConfetti = true,
	Fireworks = true, -- fireworks over the stadium when a round ends
	AmbientSparkles = true, -- soft pastel sparkles drifting over the court
	CoinFountainMax = 24,
	ShardCount = 10,
	DamageNumbers = true,
	CrackTextures = { "", "" }, -- optional Decal texture ids for crack stage 1 / 2
}

Config.Sounds = { -- placeholder ids: paste Creator Store audio ids here
	Swing = { Id = "rbxassetid://0", Volume = 0.6 },
	Hit = { Id = "rbxassetid://0", Volume = 0.8 },
	Crack = { Id = "rbxassetid://0", Volume = 1 },
	Crush = { Id = "rbxassetid://0", Volume = 1 },
	Poof = { Id = "rbxassetid://0", Volume = 0.5 },
	Land = { Id = "rbxassetid://0", Volume = 0.8 },
	Coin = { Id = "rbxassetid://0", Volume = 0.7 },
	Purchase = { Id = "rbxassetid://0", Volume = 0.8 },
	Denied = { Id = "rbxassetid://0", Volume = 0.6 },
	Countdown = { Id = "rbxassetid://0", Volume = 0.6 },
	RoundStart = { Id = "rbxassetid://0", Volume = 0.9 },
	RoundEnd = { Id = "rbxassetid://0", Volume = 0.9 },
	Blockling = { Id = "rbxassetid://0", Volume = 1 }, -- a Blockling was found
	Rebirth = { Id = "rbxassetid://0", Volume = 1 },
	Daily = { Id = "rbxassetid://0", Volume = 0.9 },
	Event = { Id = "rbxassetid://0", Volume = 1 }, -- server-wide event starts
	Emote = { Id = "rbxassetid://0", Volume = 0.6 },
}

-- Debug (Studio only) ---------------------------------------------------------

Config.Debug = {
	ForceMode = nil :: string?, -- "Teams" or "Coop" to test team mode with 2 clients
	RoundTime = nil :: number?, -- e.g. 45 for quick test rounds
	StudioStartingCoins = 0, -- grant this many coins on join (Studio only)
	LogRejectedRemotes = false,
	LogFunnel = true, -- print onboarding funnel steps in Studio output
	SmokeTest = true, -- on Studio server start: spawn/hit/crack/crush self-test, PASS/FAIL in Output
	SkipIntro = false, -- true = skip the intro flyover in Studio (faster test loops)
}

return Config
