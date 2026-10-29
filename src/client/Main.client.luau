--[[
	Client entry point. Same pattern as the server: require all, Init() all, Start() all.
	Init builds UI/state, Start connects events. Order matters.
]]

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"ClientState",
	"SoundController",
	"CameraController",
	"HudController",
	"TeamVisualsController",
	"EffectsController",
	"HammerController",
	"EmoteController",
	"ShopController",
	"PetController",
	"CollectionController",
	"RebirthController",
	"DailyController",
	"SettingsController",
	"SocialController",
	"ReleaseController",
	"IntroController",
	"AmbientController",
	"DebugController",
	"UiFxController", -- press juice, coins fly into the counter, shine sweeps, confetti, edge glow
	"WorldFxController", -- court sparkles, round-end fireworks
	"PolishController", -- last: styles every UI element built above
}

-- Each step is isolated: one broken controller warns with its name and a traceback
-- instead of stopping every controller after it (no more blank HUD from one bug).
local loaded = {}
for _, name in ORDER do
	local ok, result = xpcall(require, debug.traceback, Controllers:WaitForChild(name))
	if ok then
		loaded[name] = result
	else
		warn(`[BonkBlocks] client: {name} failed to load:\n{result}`)
	end
end

for _, phase in { "Init", "Start" } do
	for _, name in ORDER do
		local controller = loaded[name]
		if controller and controller[phase] then
			local ok, err = xpcall(controller[phase], debug.traceback)
			if not ok then
				warn(`[BonkBlocks] client: {name}.{phase} failed:\n{err}`)
			end
		end
	end
end
