--[[
	SoundController: plays sounds by Config.Sounds key. Unset ids are skipped silently,
	so the game runs fine with placeholder ids.

		SoundController.Play("Coin")              -- 2D (UI)
		SoundController.PlayAt("Hit", position)   -- 3D, in the world
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SoundController = {}

local player = game:GetService("Players").LocalPlayer

local function getDef(name: string)
	if player:GetAttribute("Set_sfx") == false then
		return nil -- muted in Settings
	end
	local def = Config.Sounds[name]
	if not def or def.Id == "" or def.Id == "rbxassetid://0" then
		return nil
	end
	return def
end

local function makeSound(def, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume or 1
	sound.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.12 -- slight pitch variety
	sound.Parent = parent
	return sound
end

function SoundController.Play(name: string)
	local def = getDef(name)
	if not def then
		return
	end
	local sound = makeSound(def, SoundService)
	sound:Play()
	Debris:AddItem(sound, 6)
end

function SoundController.PlayAt(name: string, position: Vector3)
	local def = getDef(name)
	if not def then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local sound = makeSound(def, attachment)
	sound.RollOffMaxDistance = 150
	sound:Play()
	Debris:AddItem(attachment, 6)
end

return SoundController
