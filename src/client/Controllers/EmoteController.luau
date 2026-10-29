--[[
	EmoteController: procedural emotes for every player (no uploaded animations).

	Reads the server-validated character attributes Emote / EmoteAt and, every
	RunService.Stepped (after the Animator ran), overrides R15 Motor6D.Transform with a
	pose function of time. Poses blend in/out over 0.2s; walking cancels your own emote.

	Input: EMOTE button next to BONK opens a picker; PC keys 1-5 play emotes, G toggles
	the picker. R6 rigs are skipped (emotes need R15, Roblox's default).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Net = require(Shared:WaitForChild("Net"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local player = Players.LocalPlayer
local rad, sin, abs = math.rad, math.sin, math.abs
local BLEND = 0.2

type Pose = { [string]: CFrame }
type Joints = { [string]: Motor6D }
type ActiveEmote = { id: string, startedAt: number, endedAt: number? }

local EmoteController = {}

-- Poses: joint -> Transform. Axes are the torso's: +X right, +Y up, -Z forward.
-- Shoulder Z+ raises the right arm sideways (Z- for the left); X+ raises an arm/leg forward.
local POSES: { [string]: (t: number, duration: number) -> Pose } = {
	Wave = function(t)
		local w = sin(t * 10)
		return {
			RightShoulder = CFrame.Angles(0, 0, rad(150 + w * 15)),
			RightElbow = CFrame.Angles(0, 0, rad(25 + w * 20)),
			Neck = CFrame.Angles(0, 0, rad(sin(t * 3) * 8)),
		}
	end,
	Cheer = function(t)
		local pump = sin(t * 9)
		return {
			Root = CFrame.new(0, abs(sin(t * 6)) * 0.45, 0),
			RightShoulder = CFrame.Angles(0, 0, rad(165 + pump * 12)),
			LeftShoulder = CFrame.Angles(0, 0, -rad(165 - pump * 12)),
			Neck = CFrame.Angles(rad(15), 0, 0),
		}
	end,
	Flex = function(t)
		local pulse = sin(t * 7) * 8
		return {
			RightShoulder = CFrame.Angles(0, 0, rad(90)),
			LeftShoulder = CFrame.Angles(0, 0, -rad(90)),
			RightElbow = CFrame.Angles(0, 0, rad(95 + pulse)),
			LeftElbow = CFrame.Angles(0, 0, -rad(95 + pulse)),
			Waist = CFrame.Angles(0, rad(sin(t * 3.5) * 12), 0),
		}
	end,
	Spin = function(t, duration)
		local alpha = math.clamp(t / duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 2
		return {
			Root = CFrame.new(0, sin(alpha * math.pi) * 1.2, 0) * CFrame.Angles(0, eased * math.pi * 4, 0),
			RightShoulder = CFrame.Angles(0, 0, rad(85)),
			LeftShoulder = CFrame.Angles(0, 0, -rad(85)),
		}
	end,
	BonkDance = function(t)
		local beat = t * math.pi * 4 -- two beats per second
		local s = sin(beat)
		return {
			Root = CFrame.new(0, abs(s) * 0.25, 0) * CFrame.Angles(0, sin(beat / 2) * 0.35, s * 0.08),
			RightShoulder = CFrame.Angles(rad(60 + s * 50), 0, rad(15)),
			LeftShoulder = CFrame.Angles(rad(60 - s * 50), 0, -rad(15)),
			RightElbow = CFrame.Angles(rad(45), 0, 0),
			LeftElbow = CFrame.Angles(rad(45), 0, 0),
			RightHip = CFrame.Angles(rad(s * 18), 0, 0),
			LeftHip = CFrame.Angles(rad(-s * 18), 0, 0),
			Neck = CFrame.Angles(rad(sin(beat * 2) * 8), 0, 0),
		}
	end,
}

local JOINT_PATHS = {
	Root = { "LowerTorso", "Root" },
	Waist = { "UpperTorso", "Waist" },
	Neck = { "Head", "Neck" },
	RightShoulder = { "RightUpperArm", "RightShoulder" },
	LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
	RightElbow = { "RightLowerArm", "RightElbow" },
	LeftElbow = { "LeftLowerArm", "LeftElbow" },
	RightHip = { "RightUpperLeg", "RightHip" },
	LeftHip = { "LeftUpperLeg", "LeftHip" },
}
local JOINT_COUNT = 9

local durations: { [string]: number } = {}
for _, emote in Config.Emotes.List do
	durations[emote.Id] = emote.Duration
end

local jointCache: { [Model]: Joints } = setmetatable({}, { __mode = "k" }) :: any
local active: { [Model]: ActiveEmote } = setmetatable({}, { __mode = "k" }) :: any
local requestRemote
local picker: Frame
local warnedR6 = false

local function jointsOf(character: Model): Joints?
	local cached = jointCache[character]
	if cached then
		return cached
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local joints: Joints = {}
	local found = 0
	for name, path in JOINT_PATHS do
		local part = character:FindFirstChild(path[1])
		local motor = part and part:FindFirstChild(path[2])
		if motor and motor:IsA("Motor6D") then
			joints[name] = motor
			found += 1
		end
	end
	if found == JOINT_COUNT then
		jointCache[character] = joints -- only cache a fully loaded rig
	end
	return joints
end

function EmoteController.Play(emoteId: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		if not warnedR6 then
			warnedR6 = true
			HudController.Toast("Emotes need an R15 avatar", Ui.Colors.Bad)
		end
		return
	end
	requestRemote:FireServer(emoteId)
	SoundController.Play("Emote")
	picker.Visible = false
end

local function step()
	local now = workspace:GetServerTimeNow()
	for _, target in Players:GetPlayers() do
		local character = target.Character
		if not character then
			continue
		end
		local emoteId = character:GetAttribute("Emote")
		local startedAt = character:GetAttribute("EmoteAt")
		local entry = active[character]

		if typeof(emoteId) == "string" and emoteId ~= "" and typeof(startedAt) == "number" and POSES[emoteId] then
			if not entry or entry.startedAt ~= startedAt then
				entry = { id = emoteId, startedAt = startedAt, endedAt = nil }
				active[character] = entry
			end
		elseif entry and not entry.endedAt then
			entry.endedAt = now -- server cleared it: fade out
		end
		if not entry then
			continue
		end

		local t = now - entry.startedAt
		-- Walking cancels your own emote (others see it end when the server clears it)
		if target == player and not entry.endedAt and t > 0.35 then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
				entry.endedAt = now
				requestRemote:FireServer("")
			end
		end

		local weight = math.clamp(t / BLEND, 0, 1)
		if entry.endedAt then
			weight *= 1 - math.clamp((now - entry.endedAt) / BLEND, 0, 1)
			if weight <= 0 then
				active[character] = nil
				continue
			end
		end

		local joints = jointsOf(character)
		if not joints then
			continue
		end
		local pose = POSES[entry.id](t, durations[entry.id] or 3)
		for name, transform in pose do
			local motor = joints[name]
			if motor and motor.Parent then
				motor.Transform = if weight >= 1 then transform else motor.Transform:Lerp(transform, weight)
			end
		end
	end
end

-- UI ----------------------------------------------------------------------------

local function buildButtons()
	local swingButton = (HudController.Gui :: ScreenGui):WaitForChild("SwingButton") :: GuiObject
	local button = Ui.new("TextButton", {
		Name = "EmoteButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0, -10, 1, 0),
		Size = UDim2.fromScale(0.5, 0.5), -- follows the BONK button's size
		BackgroundColor3 = Ui.Colors.Purple,
		Text = "",
		Parent = swingButton,
	}, { Ui.round(), Ui.stroke(3) })
	Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.4),
		Text = "EMOTE",
		Parent = button,
	})

	picker = Ui.new("Frame", {
		Name = "EmotePicker",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 0, -10),
		Size = UDim2.fromOffset(#Config.Emotes.List * 76, 70),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = button,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = picker,
	})
	for index, emote in Config.Emotes.List do
		local option = Ui.new("TextButton", {
			LayoutOrder = index,
			Size = UDim2.fromOffset(70, 70),
			BackgroundColor3 = Ui.Colors.Panel,
			Text = "",
			Parent = picker,
		}, { Ui.corner(14), Ui.stroke(3, Ui.Colors.Purple) })
		Ui.label({ Position = UDim2.fromOffset(4, 6), Size = UDim2.new(1, -8, 0, 16), Text = tostring(index), TextColor3 = Ui.Colors.Muted, Parent = option })
		Ui.label({ Position = UDim2.fromOffset(4, 24), Size = UDim2.new(1, -8, 1, -32), Text = emote.Name, TextWrapped = true, Parent = option })
		option.Activated:Connect(function()
			EmoteController.Play(emote.Id)
		end)
	end
	button.Activated:Connect(function()
		picker.Visible = not picker.Visible
	end)
end

local NUMBER_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

function EmoteController.Init()
	requestRemote = Net.Get(Constants.Remotes.EmoteRequest)
	buildButtons()
end

function EmoteController.Start()
	RunService.Stepped:Connect(step)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			picker.Visible = not picker.Visible
			return
		end
		local index = table.find(NUMBER_KEYS, input.KeyCode)
		local emote = index and Config.Emotes.List[index]
		if emote then
			EmoteController.Play(emote.Id)
		end
	end)
end

return EmoteController
