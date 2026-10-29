--[[
	Net: one place to get remotes.
	The server creates them on first require; clients wait for them.

		local Net = require(Shared.Net)
		Net.Get(Constants.Remotes.SwingRequest):FireServer(block)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent:WaitForChild("Constants"))

local FOLDER_NAME = "BonkRemotes"
local IS_SERVER = RunService:IsServer()

local Net = {}

local folder: Instance
if IS_SERVER then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) or Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local function ensure(name: string, className: string)
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in Constants.Remotes do
		ensure(name, "RemoteEvent")
	end
	for _, name in Constants.UnreliableRemotes do
		ensure(name, "UnreliableRemoteEvent")
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Net.Get(name: string): any
	local remote = if IS_SERVER then folder:FindFirstChild(name) else folder:WaitForChild(name, 10)
	assert(remote, `[Net] Unknown remote "{name}"`)
	return remote
end

return Net
