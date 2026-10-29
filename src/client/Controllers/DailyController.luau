--[[
	DailyController: "DAILY" menu button + popup with two tabs:
		REWARDS  7-day streak track and the claim button
		QUESTS   today's quests with progress bars and per-quest claim
	The button badges when a daily reward or a finished quest is waiting.
	Auto-opens once per session for returning players, never during a live round and
	never for brand-new players (it would break the 30-second hook).
	Sends only DailyClaimRequest() / QuestClaimRequest(index); the server owns the clock.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local player = Players.LocalPlayer
local Colors = Ui.Colors
local Rewards = Config.Daily.Rewards

type Tile = { frame: Frame, stroke: UIStroke, amount: TextLabel, status: TextLabel }
type QuestRow = { frame: Frame, text: TextLabel, fill: Frame, progress: TextLabel, claim: TextButton, claimLabel: TextLabel }

local DailyController = {}

local refs: { [string]: any } = {}
local tiles: { Tile } = {}
local questRows: { QuestRow } = {}
local questPending: { [number]: boolean } = {}
local popupOpen = false
local currentTab = "Rewards"
local autoOpened = false
local pending = false
local claimRemote, questRemote

local function formatWait(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%dm %02ds", minutes, math.floor(seconds % 60))
end

type QuestState = { id: string, def: Progression.QuestDef, progress: number, claimed: boolean }

local function questStates(): { [number]: QuestState }
	local states = {}
	for index = 1, Config.Quests.PerDay do
		local id, progress, claimed = Progression.ParseQuestAttr(player:GetAttribute(Constants.QuestAttr(index)))
		local def = id and Progression.Quest(id)
		if id and def then
			states[index] = { id = id, def = def, progress = progress, claimed = claimed }
		end
	end
	return states
end

local function anyQuestClaimable(): boolean
	for _, state in questStates() do
		if not state.claimed and state.progress >= state.def.Target then
			return true
		end
	end
	return false
end

local function refreshTabs()
	refs.rewardsPage.Visible = currentTab == "Rewards"
	refs.questsPage.Visible = currentTab == "Quests"
	refs.rewardsTab.BackgroundColor3 = if currentTab == "Rewards" then Colors.Purple else Colors.PanelLight
	refs.questsTab.BackgroundColor3 = if currentTab == "Quests" then Colors.Purple else Colors.PanelLight
end

local function refresh()
	local dailyReady = ClientState.DailyClaimable()
	local questReady = anyQuestClaimable()
	refs.badge.Visible = dailyReady or questReady
	refs.questsTabBadge.Visible = questReady
	refs.timer.Text = if dailyReady then "READY!" else formatWait(ClientState.DailySecondsLeft())
	refs.timer.TextColor3 = if dailyReady then Colors.Gold else Colors.Text
	if not popupOpen then
		return
	end

	-- Rewards tab
	local rebirths = ClientState.Rebirths()
	local day = ClientState.DailyDay()
	refs.subtitle.Text = `Streak: {player:GetAttribute(Constants.PlayerAttr.DailyStreak) or 0} day(s). Miss {Config.Daily.StreakExpireHours}h and it restarts`
	for index, tile in tiles do
		tile.amount.Text = MathUtil.formatNumber(Progression.DailyCoins(index, rebirths))
		local isToday = index == day
		tile.stroke.Color = if isToday then Colors.Gold else Colors.Stroke
		tile.stroke.Thickness = if isToday then 4 else 2
		tile.frame.BackgroundColor3 = if index < day then Colors.Disabled else Colors.PanelLight
		tile.status.Text = if index < day then "DONE" elseif isToday then (if dailyReady then "TODAY" else "NEXT") else ""
	end
	refs.claim.BackgroundColor3 = if dailyReady and not pending then Colors.Good else Colors.Disabled
	refs.claimLabel.Text = if pending
		then "..."
		elseif dailyReady then "CLAIM!"
		else `Come back in {formatWait(ClientState.DailySecondsLeft())}`

	-- Quests tab
	local states = questStates()
	for index, row in questRows do
		local state = states[index]
		row.frame.Visible = state ~= nil
		if state then
			local target = state.def.Target
			local done = state.progress >= target
			row.text.Text = state.def.Text
			row.fill.Size = UDim2.fromScale(math.clamp(state.progress / target, 0, 1), 1)
			row.fill.BackgroundColor3 = if done then Colors.Good else Colors.Accent
			row.progress.Text = `{MathUtil.formatNumber(state.progress)}/{MathUtil.formatNumber(target)}`
			local coins = MathUtil.formatNumber(Progression.QuestCoins(state.id, rebirths))
			if state.claimed then
				row.claim.BackgroundColor3 = Colors.Disabled
				row.claimLabel.Text = "DONE"
			elseif done then
				row.claim.BackgroundColor3 = if questPending[index] then Colors.Disabled else Colors.Good
				row.claimLabel.Text = if questPending[index] then "..." else `CLAIM {coins}`
			else
				row.claim.BackgroundColor3 = Colors.PanelLight
				row.claimLabel.Text = `+{coins}`
			end
		end
	end
	local secondsToReset = 86400 - (workspace:GetServerTimeNow() % 86400)
	refs.questFooter.Text = `New quests in {formatWait(secondsToReset)}`
end

function DailyController.SetOpen(open: boolean, tab: string?)
	popupOpen = open
	refs.popup.Visible = open
	if open then
		if tab then
			currentTab = tab
		end
		refreshTabs()
		HudController.PanelOpened("Daily", function()
			DailyController.SetOpen(false)
		end)
		Ui.pop(refs.popupPop, 0.12)
	else
		HudController.PanelClosed("Daily")
	end
	refresh()
end

-- Build -------------------------------------------------------------------------

local function buildMenuButton()
	local _holder, button, badge = HudController.AddMenuButton("DailyButton", 3, Color3.fromRGB(240, 130, 60), "DAILY")
	local box = Ui.new("Frame", { -- gift box icon
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(38, 30),
		BackgroundColor3 = Color3.fromRGB(255, 90, 120),
		Parent = button,
	}, { Ui.corner(5), Ui.stroke(2) })
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 8, 1, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		Parent = box,
	})
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(44, 10),
		BackgroundColor3 = Color3.fromRGB(255, 120, 150),
		Parent = box,
	}, { Ui.corner(3), Ui.stroke(2) })
	refs.timer = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.new(1, -8, 0, 14),
		Parent = button,
	})
	refs.badge = badge
	button.Activated:Connect(function()
		if popupOpen then
			DailyController.SetOpen(false)
		else
			-- open where the action is
			local tab = if not ClientState.DailyClaimable() and anyQuestClaimable() then "Quests" else nil
			DailyController.SetOpen(true, tab)
		end
	end)
end

local function tabButton(parent: Instance, text: string, x: number): TextButton
	local button = Ui.new("TextButton", {
		Position = UDim2.fromOffset(x, 48),
		Size = UDim2.fromOffset(150, 36),
		Text = "",
		Parent = parent,
	}, { Ui.corner(10), Ui.stroke(3) })
	Ui.label({ Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 1, -12), Text = text, Parent = button })
	return button
end

local function buildRewardsPage(page: Frame)
	refs.subtitle = Ui.label({
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -32, 0, 18),
		TextColor3 = Colors.Muted,
		Parent = page,
	})
	local row = Ui.new("Frame", {
		Position = UDim2.fromOffset(16, 24),
		Size = UDim2.new(1, -32, 0, 116),
		BackgroundTransparency = 1,
		Parent = page,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for index, reward in Rewards do
		local frame = Ui.new("Frame", {
			LayoutOrder = index,
			Size = UDim2.fromOffset(76, 112),
			BackgroundColor3 = Colors.PanelLight,
			Parent = row,
		}, { Ui.corner(12) })
		local stroke = Ui.stroke(2)
		stroke.Parent = frame
		Ui.label({ Position = UDim2.fromOffset(4, 6), Size = UDim2.new(1, -8, 0, 18), Text = `DAY {index}`, Parent = frame })
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 28),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = Colors.Gold,
			Parent = frame,
		}, { Ui.round(), Ui.stroke(2, Colors.GoldDark) })
		local amount = Ui.label({ Position = UDim2.fromOffset(4, 58), Size = UDim2.new(1, -8, 0, 18), TextColor3 = Colors.Gold, Parent = frame })
		if reward.Blockling then
			Ui.label({
				Position = UDim2.fromOffset(4, 76),
				Size = UDim2.new(1, -8, 0, 14),
				Text = `+{reward.Blockling}+ pet`,
				TextColor3 = Config.Blocklings.Rarities[reward.Blockling].Color,
				Parent = frame,
			})
		end
		local status = Ui.label({ Position = UDim2.fromOffset(4, 92), Size = UDim2.new(1, -8, 0, 16), TextColor3 = Colors.Muted, Parent = frame })
		tiles[index] = { frame = frame, stroke = stroke, amount = amount, status = status }
	end

	local claim = Ui.new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(300, 52),
		BackgroundColor3 = Colors.Good,
		Text = "",
		Parent = page,
	}, { Ui.corner(14), Ui.stroke(3) })
	refs.claimLabel = Ui.label({ Position = UDim2.fromOffset(10, 9), Size = UDim2.new(1, -20, 1, -18), Parent = claim })
	refs.claim = claim
	claim.Activated:Connect(function()
		if pending or not ClientState.DailyClaimable() then
			SoundController.Play("Denied")
			Ui.shake(claim)
			return
		end
		pending = true
		claimRemote:FireServer()
		refresh()
		task.delay(4, function()
			if pending then
				pending = false
				refresh()
			end
		end)
	end)
end

local function buildQuestsPage(page: Frame)
	for index = 1, Config.Quests.PerDay do
		local frame = Ui.new("Frame", {
			Position = UDim2.fromOffset(16, (index - 1) * 60),
			Size = UDim2.new(1, -32, 0, 54),
			BackgroundColor3 = Colors.PanelLight,
			Parent = page,
		}, { Ui.corner(12), Ui.stroke(2) })
		local text = Ui.label({
			Position = UDim2.fromOffset(12, 5),
			Size = UDim2.new(1, -160, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local bar = Ui.new("Frame", {
			Position = UDim2.fromOffset(12, 31),
			Size = UDim2.new(1, -160, 0, 16),
			BackgroundColor3 = Colors.Stroke,
			Parent = frame,
		}, { Ui.corner(8) })
		local fill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Colors.Accent, Parent = bar }, { Ui.corner(8) })
		local progress = Ui.label({ Size = UDim2.fromScale(1, 1), TextStrokeTransparency = 0, ZIndex = 2, Parent = bar })
		local claim = Ui.new("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(132, 44),
			Text = "",
			Parent = frame,
		}, { Ui.corner(10), Ui.stroke(3) })
		local claimLabel = Ui.label({ Position = UDim2.fromOffset(6, 8), Size = UDim2.new(1, -12, 1, -16), Parent = claim })
		claim.Activated:Connect(function()
			local state = questStates()[index]
			if not state or state.claimed or state.progress < state.def.Target or questPending[index] then
				return
			end
			questPending[index] = true
			questRemote:FireServer(index)
			refresh()
			task.delay(3, function()
				questPending[index] = nil
				refresh()
			end)
		end)
		questRows[index] = { frame = frame, text = text, fill = fill, progress = progress, claim = claim, claimLabel = claimLabel }
	end
	refs.questFooter = Ui.label({
		Position = UDim2.new(0, 16, 1, -32),
		Size = UDim2.new(1, -32, 0, 18),
		TextColor3 = Colors.Muted,
		Parent = page,
	})
end

local function buildPopup(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "DailyPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(612, 320),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	Ui.scaled(holder)
	local card = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		Parent = holder,
	}, { Ui.corner(18), Ui.stroke(4) })
	refs.popupPop = Ui.new("UIScale", { Parent = card })
	Ui.label({
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -80, 0, 32),
		Text = "DAILY",
		Parent = card,
	})
	local close = Ui.new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = Colors.Bad,
		Text = "",
		Parent = card,
	}, { Ui.corner(12), Ui.stroke(3) })
	Ui.label({ Size = UDim2.fromScale(1, 1), Text = "X", Parent = close })
	close.Activated:Connect(function()
		DailyController.SetOpen(false)
	end)

	refs.rewardsTab = tabButton(card, "REWARDS", 16)
	refs.questsTab = tabButton(card, "QUESTS", 176)
	refs.questsTabBadge = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Colors.Bad,
		Visible = false,
		Parent = refs.questsTab,
	}, { Ui.round(), Ui.stroke(2) })
	refs.rewardsTab.Activated:Connect(function()
		currentTab = "Rewards"
		refreshTabs()
		refresh()
	end)
	refs.questsTab.Activated:Connect(function()
		currentTab = "Quests"
		refreshTabs()
		refresh()
	end)

	local function page(name: string): Frame
		return Ui.new("Frame", {
			Name = name,
			Position = UDim2.fromOffset(0, 92),
			Size = UDim2.new(1, 0, 1, -92),
			BackgroundTransparency = 1,
			Parent = card,
		})
	end
	refs.rewardsPage = page("RewardsPage")
	refs.questsPage = page("QuestsPage")
	buildRewardsPage(refs.rewardsPage)
	buildQuestsPage(refs.questsPage)
	refs.popup = holder
	refreshTabs()
end

-- Results & auto-open -------------------------------------------------------------

local function onResult(result: any)
	if typeof(result) ~= "table" then
		return
	end
	pending = false
	if result.ok then
		SoundController.Play("Daily")
		HudController.Toast(`Day {result.day} reward: +{MathUtil.formatNumber(result.coins or 0)} coins!`, Colors.Gold)
		if anyQuestClaimable() then
			currentTab = "Quests"
			refreshTabs()
		else
			DailyController.SetOpen(false)
		end
	else
		SoundController.Play("Denied")
		HudController.Toast(if result.code == "NotReady" then "Not ready yet. Come back later!" else "Try again in a moment", Colors.Bad)
	end
	refresh()
end

local function maybeAutoOpen()
	if autoOpened or popupOpen or not ClientState.DailyClaimable() then
		return
	end
	-- not behind the intro / release card
	if player:GetAttribute(Constants.PlayerAttr.ClientReady) ~= true then
		return
	end
	local returning = (player:GetAttribute(Constants.PlayerAttr.TotalCrushed) or 0) > 0
	if returning and ClientState.State() ~= Constants.RoundState.Active then
		autoOpened = true
		DailyController.SetOpen(true, "Rewards")
	end
end

function DailyController.Init()
	claimRemote = Net.Get(Constants.Remotes.DailyClaimRequest)
	questRemote = Net.Get(Constants.Remotes.QuestClaimRequest)
	buildMenuButton()
	buildPopup(HudController.Gui :: ScreenGui)
end

function DailyController.Start()
	Net.Get(Constants.Remotes.DailyResult).OnClientEvent:Connect(onResult)
	ClientState.Changed:Connect(function(key)
		if key == Constants.GameAttr.State or key == Constants.PlayerAttr.Loaded or key == Constants.PlayerAttr.ClientReady then
			task.delay(2, maybeAutoOpen)
		elseif string.sub(key, 1, 5) == "Quest" then
			for index in questPending do
				questPending[index] = nil
			end
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
	task.delay(3, maybeAutoOpen)
end

return DailyController
