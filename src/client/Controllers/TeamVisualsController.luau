--[[
	TeamVisualsController: team-colored outlines on every character during a
	live Teams round, so Red vs Blue reads at a glance on a phone screen.
	Local-only Highlights (8 players is far under the 31-highlight limit).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))

local TeamVisualsController = {}

local highlights: { [Player]: Highlight } = {}

local function teamIdOf(player: Player): string?
	local team = player.Team
	if not team then
		return nil
	end
	for teamId, def in Config.Teams do
		if def.DisplayName == team.Name then
			return teamId
		end
	end
	return nil
end

local function refresh()
	local show = Config.Vfx.TeamOutlines
		and ClientState.Mode() == Constants.Mode.Teams
		and ClientState.State() == Constants.RoundState.Active

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local teamId = teamIdOf(player)
		local def = teamId and teamId ~= "Crew" and Config.Teams[teamId]
		local highlight = highlights[player]
		if show and character and def then
			if not highlight or highlight.Parent ~= character then
				if highlight then
					highlight:Destroy()
				end
				highlight = Instance.new("Highlight")
				highlight.Name = "BonkTeamOutline"
				highlight.FillTransparency = 1
				highlight.OutlineTransparency = 0.15
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = character
				highlights[player] = highlight
			end
			(highlight :: Highlight).OutlineColor = def.Color
		elseif highlight then
			highlight:Destroy()
			highlights[player] = nil
		end
	end

	for player, highlight in highlights do
		if player.Parent ~= Players then
			highlight:Destroy()
			highlights[player] = nil
		end
	end
end

function TeamVisualsController.Start()
	ClientState.Changed:Connect(function(key)
		if key == Constants.GameAttr.State or key == Constants.GameAttr.Mode or key == "Team" then
			refresh()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
	-- Catches respawns and other players' team changes without per-player wiring
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
end

return TeamVisualsController
