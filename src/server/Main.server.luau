--[[
	Server entry point.
	Requires every service, then calls Init() on all (create state, no cross-calls),
	then Start() on all (connect events, start loops). Order matters: a service
	may only use services listed before it during Start().
]]

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"DataService",
	"CoinService",
	"ArenaService",
	"TeamService",
	"BlockService",
	"RoundService",
	"UpgradeService",
	"HammerService",
	"BlocklingService",
	"EventService",
	"RebirthService",
	"DailyService",
	"QuestService",
	"EmoteService",
	"SocialService",
	"AchievementService",
	"OnboardingService",
	"SettingsService",
	"LeaderboardService",
	"FunnelService",
	"DebugService",
}

-- Each step is isolated: a failing service warns with its name and a traceback instead
-- of silently stopping every service after it. (If DataService fails, e.g. ProfileStore
-- is missing, the services that require it fail too: fix the first error listed.)
local loaded = {}
local failures = 0
for _, name in ORDER do
	local ok, result = xpcall(require, debug.traceback, Services:WaitForChild(name))
	if ok then
		loaded[name] = result
	else
		failures += 1
		warn(`[BonkBlocks] server: {name} failed to load:\n{result}`)
	end
end

for _, phase in { "Init", "Start" } do
	for _, name in ORDER do
		local service = loaded[name]
		if service and service[phase] then
			local ok, err = xpcall(service[phase], debug.traceback)
			if not ok then
				failures += 1
				warn(`[BonkBlocks] server: {name}.{phase} failed:\n{err}`)
			end
		end
	end
end

if failures == 0 then
	print("[BonkBlocks] Server ready")
else
	warn(`[BonkBlocks] Server started with {failures} failure(s). Scroll up to the FIRST one.`)
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
if RunService:IsStudio() and Config.Debug.SmokeTest then
	require(script.Parent:WaitForChild("Util"):WaitForChild("SmokeTest")).Run(loaded)
end
