--[[
	ShopController: upgrade button + panel, and the onboarding arrow that points at
	the first upgrade as soon as the player can afford it (the 30s hook).
	Sends only PurchaseRequest(upgradeId); the server decides everything else.
	PC shortcut: U toggles the panel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local HammerStats = require(Shared:WaitForChild("HammerStats"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local Net = require(Shared:WaitForChild("Net"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local Colors = Ui.Colors
local State = Constants.RoundState

local ShopController = {}

type Card = {
	card: Frame,
	level: TextLabel,
	stat: TextLabel,
	buy: TextButton,
	buyLabel: TextLabel,
	pop: UIScale,
}

local refs: { [string]: any } = {}
local cards: { [string]: Card } = {}
local pending: { [string]: boolean } = {}
local panelOpen = false
local arrowShown = false
local arrowTween: Tween? = nil
local hintedFirstUpgrade = false
local purchaseRemote

-- Build -------------------------------------------------------------------------

local function buildHammerIcon(parent: Instance)
	local icon = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(46, 46),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.42, 0.58),
		Size = UDim2.fromOffset(8, 38),
		Rotation = 45,
		BackgroundColor3 = Color3.fromRGB(150, 95, 55),
		Parent = icon,
	}, { Ui.corner(4), Ui.stroke(2) })
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.64, 0.34),
		Size = UDim2.fromOffset(34, 18),
		Rotation = 45,
		BackgroundColor3 = Color3.fromRGB(255, 120, 170),
		Parent = icon,
	}, { Ui.corner(5), Ui.stroke(2) })
end

local function buildArrow(parent: Instance)
	local arrow = Ui.new("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 14, 0.5, 0),
		Size = UDim2.fromOffset(110, 70),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	Ui.new("Frame", { -- head (diamond, left tip is the point)
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(20, 24),
		Size = UDim2.fromOffset(30, 30),
		Rotation = 45,
		BackgroundColor3 = Colors.Gold,
		Parent = arrow,
	}, { Ui.stroke(3) })
	Ui.new("Frame", { -- shaft
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.fromOffset(52, 16),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		Parent = arrow,
	})
	Ui.label({
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.fromOffset(110, 24),
		Text = "UPGRADE!",
		TextColor3 = Colors.Gold,
		Parent = arrow,
	})
	refs.arrow = arrow
end

local function buildOpenButton(_gui: ScreenGui)
	local holder, button, badge = HudController.AddMenuButton("UpgradeButton", 1, Colors.Purple, "UPGRADE")
	refs.openPop = Ui.new("UIScale", { Parent = button })
	buildHammerIcon(button)
	refs.badge = badge

	button.Activated:Connect(function()
		ShopController.SetOpen(not panelOpen)
	end)
	buildArrow(holder)
end

local function buildCard(parent: Instance, upgradeId: string, order: number): Card
	local def = Config.Upgrades.Defs[upgradeId]
	local card = Ui.new("Frame", {
		Name = upgradeId,
		LayoutOrder = order,
		Size = UDim2.fromOffset(170, 196),
		BackgroundColor3 = Colors.PanelLight,
		Parent = parent,
	}, { Ui.corner(14), Ui.stroke(3) })
	local pop = Ui.new("UIScale", { Parent = card })

	Ui.label({ Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 26), Text = def.DisplayName, Parent = card })
	local level = Ui.label({
		Position = UDim2.fromOffset(8, 34),
		Size = UDim2.new(1, -16, 0, 18),
		TextColor3 = Colors.Gold,
		Parent = card,
	})
	local stat = Ui.label({ Position = UDim2.fromOffset(8, 56), Size = UDim2.new(1, -16, 0, 22), Parent = card })
	Ui.label({
		Position = UDim2.fromOffset(8, 82),
		Size = UDim2.new(1, -16, 0, 40),
		Text = def.Description,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Parent = card,
	})

	local buy = Ui.new("TextButton", {
		Name = "Buy",
		Position = UDim2.new(0, 8, 1, -62),
		Size = UDim2.new(1, -16, 0, 54),
		BackgroundColor3 = Colors.Good,
		AutoButtonColor = true,
		Text = "",
		Parent = card,
	}, { Ui.corner(12), Ui.stroke(3) })
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Colors.Gold,
		Parent = buy,
	}, { Ui.round(), Ui.stroke(2, Colors.GoldDark) })
	local buyLabel = Ui.label({
		Position = UDim2.fromOffset(42, 9),
		Size = UDim2.new(1, -52, 1, -18),
		Parent = buy,
	})

	buy.Activated:Connect(function()
		ShopController.Buy(upgradeId)
	end)

	return { card = card, level = level, stat = stat, buy = buy, buyLabel = buyLabel, pop = pop }
end

local function buildPanel(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "UpgradePanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(580, 352), -- bottom 56px: rebirth strip (RebirthController)
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	Ui.scaled(holder)
	local panel = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		Parent = holder,
	}, { Ui.corner(18), Ui.stroke(4) })
	refs.panelPop = Ui.new("UIScale", { Parent = panel })

	Ui.label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -80, 0, 34), Text = "HAMMER UPGRADES", Parent = panel })
	refs.status = Ui.label({
		Position = UDim2.fromOffset(16, 46),
		Size = UDim2.new(1, -80, 0, 22),
		TextColor3 = Colors.Muted,
		Parent = panel,
	})

	local close = Ui.new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = Colors.Bad,
		Text = "",
		Parent = panel,
	}, { Ui.corner(12), Ui.stroke(3) })
	Ui.label({ Size = UDim2.fromScale(1, 1), Text = "X", Parent = close })
	close.Activated:Connect(function()
		ShopController.SetOpen(false)
	end)

	local row = Ui.new("Frame", {
		Position = UDim2.fromOffset(16, 84),
		Size = UDim2.new(1, -32, 1, -148),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for index, upgradeId in Config.Upgrades.Order do
		cards[upgradeId] = buildCard(row, upgradeId, index)
	end
	refs.panel = holder
end

-- Logic -----------------------------------------------------------------------

local function setArrowVisible(visible: boolean)
	if visible == arrowShown then
		return
	end
	arrowShown = visible
	refs.arrow.Visible = visible
	if arrowTween then
		arrowTween:Cancel()
		arrowTween = nil
	end
	if visible then
		refs.arrow.Position = UDim2.new(1, 14, 0.5, 0)
		local tween = TweenService:Create(
			refs.arrow,
			TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.new(1, 30, 0.5, 0) }
		)
		tween:Play()
		arrowTween = tween
		if not hintedFirstUpgrade then
			hintedFirstUpgrade = true
			HudController.Toast("You can afford your first upgrade!", Colors.Gold)
		end
	end
end

function ShopController.Refresh()
	local loaded = ClientState.IsLoaded()
	local coins = ClientState.Coins()
	local upgrades = ClientState.Upgrades()
	local open = ClientState.IsShopOpenForMe()

	for upgradeId, card in cards do
		local def = Config.Upgrades.Defs[upgradeId]
		local tier = upgrades[upgradeId] or 0
		local cost = HammerStats.NextCost(upgradeId, tier)
		card.level.Text = `Lv {tier}/{HammerStats.MaxTier(upgradeId)}`
		local current = HammerStats.StatText(upgradeId, tier)
		card.stat.Text = if cost
			then `{def.Stat} {current} > {HammerStats.StatText(upgradeId, tier + 1)}`
			else `{def.Stat} {current} (MAX)`

		local canBuy = loaded and open and cost ~= nil and coins >= cost and not pending[upgradeId]
		card.buy.BackgroundColor3 = if canBuy then Colors.Good else Colors.Disabled
		card.buyLabel.Text = if pending[upgradeId] then "..." elseif cost then MathUtil.formatNumber(cost) else "MAX"
	end

	if not loaded then
		refs.status.Text = "Loading your save..."
	elseif ClientState.State() == State.Active and not Config.Upgrades.ShopOpenDuringRound then
		refs.status.Text = if open
			then "Your FIRST upgrade can be bought right now!"
			else `Shop opens between rounds ({MathUtil.formatTime(ClientState.TimeLeft())})`
	else
		refs.status.Text = "Shop is open!"
	end

	local cheapest = HammerStats.CheapestNextCost(upgrades)
	local affordable = loaded and open and cheapest ~= nil and coins >= cheapest
	refs.badge.Visible = affordable
	setArrowVisible(affordable and HammerStats.TotalTiers(upgrades) == 0 and not panelOpen)
end

function ShopController.SetOpen(open: boolean)
	panelOpen = open
	refs.panel.Visible = open
	if open then
		HudController.PanelOpened("Shop", function()
			ShopController.SetOpen(false)
		end)
		Ui.pop(refs.panelPop, 0.12)
	else
		HudController.PanelClosed("Shop")
	end
	ShopController.Refresh()
end

function ShopController.Buy(upgradeId: string)
	if pending[upgradeId] then
		return
	end
	local card = cards[upgradeId]
	local cost = HammerStats.NextCost(upgradeId, ClientState.Upgrades()[upgradeId] or 0)
	if not cost then
		return
	end
	if not ClientState.IsShopOpenForMe() then
		SoundController.Play("Denied")
		Ui.shake(card.buy)
		HudController.Toast("The shop opens between rounds!", Colors.Bad)
		return
	end
	local coins = ClientState.Coins()
	if coins < cost then
		SoundController.Play("Denied")
		Ui.shake(card.buy)
		HudController.Toast(`Need {MathUtil.formatNumber(cost - coins)} more coins`, Colors.Bad)
		return
	end

	pending[upgradeId] = true
	purchaseRemote:FireServer(upgradeId)
	ShopController.Refresh()
	task.delay(3, function() -- safety net if the reply is lost
		if pending[upgradeId] then
			pending[upgradeId] = nil
			ShopController.Refresh()
		end
	end)
end

local FAIL_MESSAGES = {
	NotEnoughCoins = "Not enough coins!",
	ShopClosed = "The shop opens between rounds!",
	Maxed = "Already maxed!",
	Loading = "Still loading your save...",
}

local function onPurchaseResult(result: any)
	if typeof(result) ~= "table" then
		return
	end
	if typeof(result.upgradeId) == "string" then
		pending[result.upgradeId] = nil
	end
	if result.ok then
		local def = Config.Upgrades.Defs[result.upgradeId]
		SoundController.Play("Purchase")
		HudController.Toast(`{if def then def.DisplayName else "Hammer"} upgraded to Lv {result.tier}!`, Colors.Good)
		local card = cards[result.upgradeId]
		if card then
			Ui.pop(card.pop, 0.12)
		end
	else
		SoundController.Play("Denied")
		HudController.Toast(FAIL_MESSAGES[result.code] or "Purchase failed", Colors.Bad)
	end
	ShopController.Refresh()
end

-- Lifecycle -------------------------------------------------------------------

function ShopController.Init()
	purchaseRemote = Net.Get(Constants.Remotes.PurchaseRequest)
	local gui = HudController.Gui :: ScreenGui
	buildOpenButton(gui)
	buildPanel(gui)
end

function ShopController.Start()
	Net.Get(Constants.Remotes.PurchaseResult).OnClientEvent:Connect(onPurchaseResult)
	ClientState.Changed:Connect(function()
		ShopController.Refresh()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.U then
			ShopController.SetOpen(not panelOpen)
		end
	end)
	ShopController.Refresh()

	-- Keep the "opens in 1:23" countdown fresh while the panel is open
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panelOpen then
				ShopController.Refresh()
			end
		end
	end)
end

return ShopController
