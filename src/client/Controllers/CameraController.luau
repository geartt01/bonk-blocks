--[[
	CameraController: screen shake layered on top of the default camera.
	Runs right after the camera scripts each frame, so offsets never accumulate.
	Respects the player's Reduce Motion setting where available.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local MAX_INTENSITY = 2.5

local CameraController = {}

local shakes: { { magnitude: number, duration: number, started: number } } = {}

local function motionScale(): number
	local ok, reduced = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return if ok and reduced == true then 0.25 else 1
end

function CameraController.Shake(magnitude: number, duration: number)
	if player:GetAttribute("Set_shake") == false then
		return -- turned off in Settings
	end
	if #shakes >= 8 then
		table.remove(shakes, 1)
	end
	table.insert(shakes, { magnitude = magnitude * motionScale(), duration = duration, started = os.clock() })
end

-- Shake that fades with distance from the local character
function CameraController.ShakeAt(position: Vector3, magnitude: number, duration: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if root then root.Position else camera.Focus.Position
	local falloff = 1 - math.clamp((position - from).Magnitude / Config.Vfx.ShakeFalloffDistance, 0, 1)
	if falloff > 0.05 then
		CameraController.Shake(magnitude * falloff, duration)
	end
end

local function onRender()
	if #shakes == 0 then
		return
	end
	local now = os.clock()
	local intensity = 0
	for i = #shakes, 1, -1 do
		local shake = shakes[i]
		local alpha = (now - shake.started) / shake.duration
		if alpha >= 1 then
			table.remove(shakes, i)
		else
			intensity += shake.magnitude * (1 - alpha) ^ 2
		end
	end
	local camera = workspace.CurrentCamera
	if intensity <= 0.001 or not camera then
		return
	end
	intensity = math.min(intensity, MAX_INTENSITY)
	local t = now * 25
	local x = math.noise(t, 1.3) * intensity
	local y = math.noise(2.7, t) * intensity
	local roll = math.noise(t, t * 0.5, 4.1) * intensity * 0.04
	camera.CFrame = camera.CFrame * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, roll)
end

function CameraController.Start()
	RunService:BindToRenderStep("BonkCameraShake", Enum.RenderPriority.Camera.Value + 1, onRender)
end

return CameraController
