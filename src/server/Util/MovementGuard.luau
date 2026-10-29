--[[
	MovementGuard: cheap teleport/speed sanity check. Samples every character's
	HumanoidRootPart a few times per second; a horizontal speed far above normal
	movement flags the player and their swings are refused for a short penalty.

	Server-initiated moves (spawn teleports) must call MovementGuard.NoteTeleport(player)
	first so they don't count as violations.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

type Sample = { position: Vector3, time: number }

local MovementGuard = {}

local samples: { [Player]: Sample } = {}
local flaggedUntil: { [Player]: number } = {}
local started = false

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function MovementGuard.NoteTeleport(player: Player)
	samples[player] = nil -- next sample starts fresh
end

function MovementGuard.IsFlagged(player: Player): boolean
	local untilTime = flaggedUntil[player]
	return untilTime ~= nil and os.clock() < untilTime
end

local function check(player: Player, now: number)
	local root = rootOf(player)
	if not root then
		samples[player] = nil
		return
	end
	local position = root.Position
	local last = samples[player]
	samples[player] = { position = position, time = now }
	if not last then
		return
	end
	local dt = now - last.time
	if dt <= 0 then
		return
	end
	local delta = position - last.position
	local horizontalSpeed = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
	if horizontalSpeed > Config.AntiCheat.MaxHorizontalSpeed then
		flaggedUntil[player] = now + Config.AntiCheat.PenaltySeconds
		if Config.AntiCheat.LogViolations then
			warn(`[MovementGuard] {player.Name} moved {math.floor(horizontalSpeed)} studs/s; swings paused`)
		end
	end
end

function MovementGuard.Start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(function(player)
		samples[player] = nil
		flaggedUntil[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			MovementGuard.NoteTeleport(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			MovementGuard.NoteTeleport(player)
		end)
	end
	task.spawn(function()
		while true do
			task.wait(Config.AntiCheat.SampleInterval)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				check(player, now)
			end
		end
	end)
end

return MovementGuard
