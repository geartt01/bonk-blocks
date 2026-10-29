--[[
	RebirthController:
		- rebirth strip at the bottom of the upgrade panel + a confirm modal that spells
		  out what you lose/keep/gain
		- "REBIRTH N" tags over everyone who has rebirthed
		- announcements when anyone rebirths
	Sends only RebirthRequest(); cost and state are checked on the server.
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
local State = Constants.RoundState

local RebirthController = {}

local refs: { [string]: any } = {}
local modalOpen = false
local hintedAffordable = false
local requestRemote

local function canRebirth(): (boolean, string?)
	local rebirths = ClientState.Rebirths()
	if rebirths >= Config.Rebirth.MaxRebirths then
		return false, "Max rebirth reached"
	end
	if Config.Rebirth.BetweenRoundsOnly and ClientState.State() == State.Active then
		return false, "Rebirth between rounds"
	end
	local cost = Progression.RebirthCost(rebirths)
	if ClientState.Coins() < cost then
		return false, `Need {MathUtil.formatNumber(cost - ClientState.Coins())} more coins`
	end
	return true, nil
end

local function multiplierText(rebirths: number): string
	return string.format("x%.2f", Progression.RebirthMultiplier(rebirths))
end

local function refresh()
	local rebirths = ClientState.Rebirths()
	local cost = Progression.RebirthCost(rebirths)
	local ok, reason = canRebirth()

	refs.stripLabel.Text = `Rebirth {rebirths} > {rebirths + 1}: coins {multiplierText(rebirths)} > {multiplierText(rebirths + 1)} forever`
	refs.stripButton.BackgroundColor3 = if ok then Colors.Gold else Colors.Disabled
	refs.stripButtonLabel.Text = `{MathUtil.formatNumber(cost)}`

	if modalOpen then
		local slotsNow, slotsNext = Progression.BlocklingSlots(rebirths), Progression.BlocklingSlots(rebirths + 1)
		refs.modalCost.Text = `Cost: {MathUtil.formatNumber(cost)} coins (you have {MathUtil.formatNumber(ClientState.Coins())})`
		refs.modalGain.Text = `Gain: coins {multiplierText(rebirths)} > {multiplierText(rebirths + 1)} forever`
			.. (if slotsNext > slotsNow then `, +1 Blockling slot ({slotsNext})` else "")
		refs.confirm.BackgroundColor3 = if ok then Colors.Good else Colors.Disabled
		refs.confirmLabel.Text = if ok then "REBIRTH!" else (reason or "Not yet")
	end

	if ok and not hintedAffordable then
		hintedAffordable = true
		HudController.Toast("Rebirth is ready! Check the Upgrade panel.", Colors.Gold)
	elseif not ok and ClientState.Coins() < cost then
		hintedAffordable = false
	end
end

function RebirthController.SetModalOpen(open: boolean)
	modalOpen = open
	refs.modal.Visible = open
	if open then
		HudController.PanelOpened("Rebirth", function()
			RebirthController.SetModalOpen(false)
		end)
		Ui.pop(refs.modalPop, 0.12)
	else
		HudController.PanelClosed("Rebirth")
	end
	refresh()
end

local function textButton(parent: Instance, props: { [string]: any }, color: Color3): (TextButton, TextLabel)
	props.BackgroundColor3 = color
	props.Text = ""
	props.Parent = parent
	local button = Ui.new("TextButton", props, { Ui.corner(12), Ui.stroke(3) })
	local label = Ui.label({ Position = UDim2.fromOffset(8, 7), Size = UDim2.new(1, -16, 1, -14), Parent = button })
	return button, label
end

local function buildStrip(gui: ScreenGui)
	-- Lives inside the upgrade panel's bottom 56px (ShopController reserves it)
	local shopPanel = gui:WaitForChild("UpgradePanel"):FindFirstChildOfClass("Frame") :: Frame
	local strip = Ui.new("Frame", {
		Name = "RebirthStrip",
		Position = UDim2.new(0, 16, 1, -58),
		Size = UDim2.new(1, -32, 0, 48),
		BackgroundColor3 = Colors.PanelLight,
		Parent = shopPanel,
	}, { Ui.corner(12), Ui.stroke(3, Colors.Gold) })
	refs.stripLabel = Ui.label({
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -170, 1, -20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = strip,
	})
	refs.stripButton, refs.stripButtonLabel = textButton(strip, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(150, 42),
	}, Colors.Gold)
	refs.stripButton.Activated:Connect(function()
		RebirthController.SetModalOpen(true)
	end)
end

local function buildModal(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "RebirthModal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(440, 290),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	Ui.scaled(holder)
	local card = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		Parent = holder,
	}, { Ui.corner(18), Ui.stroke(4, Colors.Gold) })
	refs.modalPop = Ui.new("UIScale", { Parent = card })
	Ui.label({ Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 36), Text = "REBIRTH?", TextColor3 = Colors.Gold, Parent = card })
	refs.modalCost = Ui.label({ Position = UDim2.fromOffset(16, 56), Size = UDim2.new(1, -32, 0, 22), Parent = card })
	Ui.label({
		Position = UDim2.fromOffset(16, 84),
		Size = UDim2.new(1, -32, 0, 20),
		Text = "Lose: all coins and hammer upgrades",
		TextColor3 = Colors.Bad,
		Parent = card,
	})
	Ui.label({
		Position = UDim2.fromOffset(16, 108),
		Size = UDim2.new(1, -32, 0, 20),
		Text = "Keep: Blocklings, crush count, daily streak",
		TextColor3 = Colors.Muted,
		Parent = card,
	})
	refs.modalGain = Ui.label({
		Position = UDim2.fromOffset(16, 132),
		Size = UDim2.new(1, -32, 0, 40),
		TextColor3 = Colors.Good,
		TextWrapped = true,
		Parent = card,
	})
	local cancel, cancelLabel = textButton(card, {
		Position = UDim2.new(0, 16, 1, -72),
		Size = UDim2.new(0.5, -24, 0, 56),
	}, Colors.Disabled)
	cancelLabel.Text = "CANCEL"
	cancel.Activated:Connect(function()
		RebirthController.SetModalOpen(false)
	end)
	refs.confirm, refs.confirmLabel = textButton(card, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 1, -72),
		Size = UDim2.new(0.5, -24, 0, 56),
	}, Colors.Good)
	refs.confirm.Activated:Connect(function()
		local ok, reason = canRebirth()
		if not ok then
			SoundController.Play("Denied")
			Ui.shake(refs.confirm)
			HudController.Toast(reason or "Can't rebirth yet", Colors.Bad)
			return
		end
		requestRemote:FireServer()
		RebirthController.SetModalOpen(false)
	end)
	refs.modal = holder
end

-- Overhead tags -----------------------------------------------------------------

local function updateTag(target: Player)
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local rebirths = target:GetAttribute(Constants.PlayerAttr.Rebirths) or 0
	local tag = head:FindFirstChild("BonkRebirthTag") :: BillboardGui?
	if rebirths <= 0 then
		if tag then
			tag:Destroy()
		end
		return
	end
	if not tag then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "BonkRebirthTag"
		billboard.Size = UDim2.fromOffset(130, 26)
		billboard.StudsOffset = Vector3.new(0, 2.6, 0)
		billboard.MaxDistance = 80
		billboard.LightInfluence = 0
		billboard.Adornee = head
		Ui.label({ Name = "Text", Size = UDim2.fromScale(1, 1), TextColor3 = Colors.Gold, TextStrokeTransparency = 0, Parent = billboard })
		billboard.Parent = head
		tag = billboard
	end
	((tag :: BillboardGui):FindFirstChild("Text") :: TextLabel).Text = `REBIRTH {rebirths}`
end

local function watchTags(target: Player)
	target:GetAttributeChangedSignal(Constants.PlayerAttr.Rebirths):Connect(function()
		updateTag(target)
	end)
	target.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 5)
		updateTag(target)
	end)
	updateTag(target)
end

-- Lifecycle -------------------------------------------------------------------

function RebirthController.Init()
	requestRemote = Net.Get(Constants.Remotes.RebirthRequest)
	local gui = HudController.Gui :: ScreenGui
	buildStrip(gui)
	buildModal(gui)
end

function RebirthController.Start()
	ClientState.Changed:Connect(function(key)
		if key == Constants.PlayerAttr.Coins or key == Constants.PlayerAttr.Rebirths or key == Constants.GameAttr.State then
			refresh()
		end
	end)
	Net.Get(Constants.Remotes.Rebirthed).OnClientEvent:Connect(function(info)
		if typeof(info) ~= "table" then
			return
		end
		if info.userId == player.UserId then
			SoundController.Play("Rebirth")
			HudController.Banner(`REBIRTH {info.rebirths}!`, `Coins {multiplierText(info.rebirths)} forever`, Colors.Gold, 3)
		else
			HudController.Toast(`{info.name} reached Rebirth {info.rebirths}!`, Colors.Gold)
		end
	end)
	Players.PlayerAdded:Connect(watchTags)
	for _, other in Players:GetPlayers() do
		watchTags(other)
	end
	refresh()
end

return RebirthController
