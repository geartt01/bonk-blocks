--[[
	SmokeTest: Studio-only, runs once at server start (Config.Debug.SmokeTest).
	Drives the real block pipeline without any players:
		arena tags -> Spawn -> ApplyHit (damage + knockback) -> Crack -> Crusher detection -> Despawn
	and prints PASS/FAIL lines to Output. The fake attacker (UserId -1) never earns coins.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local SmokeTest = {}

type Result = { name: string, ok: boolean, detail: string? }

function SmokeTest.Run(services: { [string]: any })
	local ArenaService = services.ArenaService
	local BlockService = services.BlockService

	task.spawn(function()
		local results: { Result } = {}
		local function check(name: string, ok: boolean, detail: any?)
			table.insert(results, { name = name, ok = ok, detail = if detail ~= nil then tostring(detail) else nil })
		end
		local fakeAttacker = { UserId = -1 } :: any

		check("BlockSpawnZone tagged", #ArenaService.GetSpawnZones() > 0)
		check("Crusher tagged", #ArenaService.GetCrushers() > 0)
		check("TeamSpawn tagged", #ArenaService.GetTeamSpawns(nil) > 0)

		-- Spawn + hit + crack
		local spawnOk, state = pcall(BlockService.Spawn, { progress = 0 })
		check("block spawns", spawnOk and state ~= nil, if spawnOk then nil else state)
		if spawnOk and state then
			task.wait(0.2)
			local part = state.part
			local before = state.hp
			local hitOk, hitErr = pcall(BlockService.ApplyHit, state, fakeAttacker, 1, Config.Hammer.Knockback, part.Position + Vector3.new(0, 0, 4))
			check("hit deals damage", hitOk and state.hp == before - 1, if hitOk then `hp {state.hp}/{state.maxHp}` else hitErr)
			check("HP attribute replicated", part:GetAttribute("HP") == state.hp)
			local crackOk, crackErr = pcall(BlockService.ApplyHit, state, fakeAttacker, state.hp + 1, 0, part.Position)
			check("crack resolves block", crackOk and state.resolved and part.Parent == nil, crackErr)
		end

		-- Crusher detection through the real 10 Hz monitor
		local crusher = ArenaService.GetCrushers()[1]
		if crusher then
			local reason: string? = nil
			local crushState = BlockService.Spawn({ progress = 0, position = crusher.Position })
			local connection = BlockService.BlockResolved:Connect(function(resolved, resolvedReason)
				if resolved == crushState then
					reason = resolvedReason
				end
			end)
			local deadline = os.clock() + 2
			while crushState and not crushState.resolved and os.clock() < deadline do
				task.wait(0.1)
			end
			connection:Disconnect()
			check("crusher crushes a block", reason == "Crush", `got {reason}`)
		end

		-- Despawn path
		local despawnState = BlockService.Spawn({ progress = 0 })
		if despawnState then
			local despawnOk, despawnErr = pcall(BlockService.Resolve, despawnState, "Despawn")
			check("despawn cleans up", despawnOk and despawnState.part.Parent == nil, despawnErr)
		end

		-- Event block path (Mega Block / meteors use custom stats + a Kind attribute)
		local eventOk, eventState = pcall(BlockService.Spawn, {
			kind = "Meteor",
			label = "!!",
			custom = { size = 4, health = 25, coins = 1, points = 1, heft = 2 },
		})
		check(
			"event block spawns with custom stats",
			eventOk and eventState ~= nil and eventState.maxHp == 25 and eventState.part:GetAttribute("Kind") == "Meteor",
			if eventOk then nil else eventState
		)
		if eventOk and eventState then
			BlockService.Resolve(eventState, "Despawn")
		end

		-- Blockling rolls (week 2)
		local BlocklingService = services.BlocklingService
		if BlocklingService then
			local Progression = require(ReplicatedStorage.Shared.Progression)
			local anyOk = true
			for _ = 1, 200 do
				if not Progression.Species(BlocklingService.Roll(nil)) then
					anyOk = false
				end
			end
			check("Blockling rolls are valid species", anyOk)
			local floorOk = true
			for _ = 1, 100 do
				local species = Progression.Species(BlocklingService.Roll("Epic"))
				if not species or Progression.RarityIndex(species.Rarity) < Progression.RarityIndex("Epic") then
					floorOk = false
				end
			end
			check("min-rarity rolls respect the floor", floorOk)
		end

		local passed = 0
		for _, result in results do
			if result.ok then
				passed += 1
			else
				warn(`[SmokeTest] FAIL {result.name}{if result.detail then " (" .. result.detail .. ")" else ""}`)
			end
		end
		local summary = `[SmokeTest] {passed}/{#results} passed`
		if passed == #results then
			print(summary)
		else
			warn(summary)
		end
	end)
end

return SmokeTest
