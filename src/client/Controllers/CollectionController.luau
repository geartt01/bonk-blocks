--[[
	CollectionController: the Blocklings collection.
		- "PETS" menu button (badge when you found something new)
		- collection panel: every species as a card with a 3D portrait, rarity, level,
		  coin bonus and Equip/Unequip (not-yet-found species show as dark silhouettes)
		- drop reveal: the Blockling pops out of the block in the world, hops to you,
		  then a card shows what you got
	Sends only EquipRequest(speciesId, equip); the server validates ownership and slots.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))

local Util = script.Parent.Parent:WaitForChild("Util")
local BlocklingModel = require(Util:WaitForChild("BlocklingModel"))
local Ui = require(Util:WaitForChild("Ui"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local player = Players.LocalPlayer
local Colors = Ui.Colors

type Card = {
	portrait: Frame,
	viewport: ViewportFrame?,
	owned: boolean?,
	name: TextLabel,
	info: TextLabel,
	bonus: TextLabel,
	equip: TextButton,
	equipLabel: TextLabel,
}

local CollectionController = {}

local refs: { [string]: any } = {}
local cards: { [string]: Card } = {}
local panelOpen = false
local equipRemote
local revealToken = 0
local revealModel: Model? = nil
local revealQueue: { any } = {}
local revealShowing = false

local function rarityColor(rarity: string): Color3
	local def = Config.Blocklings.Rarities[rarity]
	return if def then def.Color else Colors.Text
end

local function percent(value: number): string
	return `{math.floor(value * 100 + 0.5)}%`
end

-- Collection panel ----------------------------------------------------------------

local function refreshCard(id: string)
	local card = cards[id]
	local species = Progression.Species(id)
	if not (card and species) then
		return
	end
	local count = ClientState.BlocklingCount(id)
	local owned = count > 0
	if card.owned ~= owned then
		if card.viewport then
			card.viewport:Destroy()
		end
		card.viewport = BlocklingModel.Viewport(card.portrait, id, not owned)
		card.owned = owned
	end
	local equipped = table.find(ClientState.Equipped(), id) ~= nil
	local mutation = ClientState.Mutation(id)
	local mutationDef = mutation and Config.Blocklings.Mutations.Defs[mutation]
	card.name.Text = if not owned then "???" elseif mutation then `{mutation} {species.Name}` else species.Name
	card.name.TextColor3 = if owned and mutationDef then mutationDef.Color else Colors.Text
	card.info.Text = if owned then `{species.Rarity} | Lv {Progression.Level(count)}/{Config.Blocklings.MaxLevel}` else species.Rarity
	card.info.TextColor3 = rarityColor(species.Rarity)
	card.bonus.Text = if owned then `+{percent(Progression.Bonus(id, count, mutation))} coins` else ""
	card.equip.Visible = owned
	card.equip.BackgroundColor3 = if equipped then Colors.Bad else Colors.Good
	card.equipLabel.Text = if equipped then "UNEQUIP" else "EQUIP"
end

local function refreshAll()
	local found = 0
	local owned: { [string]: number } = {}
	local mutations: { [string]: string } = {}
	for _, species in Progression.AllSpecies() do
		local count = ClientState.BlocklingCount(species.Id)
		owned[species.Id] = count
		mutations[species.Id] = ClientState.Mutation(species.Id)
		if count > 0 then
			found += 1
		end
		refreshCard(species.Id)
	end
	local equipped = ClientState.Equipped()
	local total = Progression.TotalBonus(equipped, owned, mutations) + Progression.SetBonus(owned)
	refs.summary.Text = `Found {found}/{#Progression.AllSpecies()}  |  Slots {#equipped}/{ClientState.Slots()}  |  Sets {Progression.CompletedSets(owned)}/{#Config.Blocklings.RarityOrder}  |  +{percent(total)} coins`
end

local function buildCard(parent: Instance, species: Progression.Species, order: number)
	local card = Ui.new("Frame", {
		Name = species.Id,
		LayoutOrder = order,
		BackgroundColor3 = Colors.PanelLight,
		Parent = parent,
	}, { Ui.corner(12) })
	local stroke = Ui.stroke(3, rarityColor(species.Rarity))
	stroke.Parent = card
	local portrait = Ui.new("Frame", {
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 0, 62),
		BackgroundTransparency = 1,
		Parent = card,
	})
	local name = Ui.label({ Position = UDim2.fromOffset(6, 66), Size = UDim2.new(1, -12, 0, 18), Parent = card })
	local info = Ui.label({ Position = UDim2.fromOffset(6, 84), Size = UDim2.new(1, -12, 0, 15), Parent = card })
	local bonus = Ui.label({
		Position = UDim2.fromOffset(6, 100),
		Size = UDim2.new(1, -12, 0, 15),
		TextColor3 = Colors.Gold,
		Parent = card,
	})
	local equip = Ui.new("TextButton", {
		Position = UDim2.new(0, 6, 1, -46),
		Size = UDim2.new(1, -12, 0, 40),
		Text = "",
		Parent = card,
	}, { Ui.corner(10), Ui.stroke(3) })
	local equipLabel = Ui.label({ Position = UDim2.fromOffset(6, 8), Size = UDim2.new(1, -12, 1, -16), Parent = equip })

	equip.Activated:Connect(function()
		local isEquipped = table.find(ClientState.Equipped(), species.Id) ~= nil
		if not isEquipped and #ClientState.Equipped() >= ClientState.Slots() then
			SoundController.Play("Denied")
			Ui.shake(equip)
			HudController.Toast("All slots full! Unequip one, or rebirth for more slots", Colors.Bad)
			return
		end
		equipRemote:FireServer(species.Id, not isEquipped)
	end)

	cards[species.Id] = {
		portrait = portrait,
		viewport = nil,
		owned = nil,
		name = name,
		info = info,
		bonus = bonus,
		equip = equip,
		equipLabel = equipLabel,
	}
end

function CollectionController.SetOpen(open: boolean)
	panelOpen = open
	refs.panel.Visible = open
	if open then
		HudController.PanelOpened("Collection", function()
			CollectionController.SetOpen(false)
		end)
		refs.badge.Visible = false
		Ui.pop(refs.panelPop, 0.1)
		refreshAll()
	else
		HudController.PanelClosed("Collection")
	end
end

local function buildPanel(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "CollectionPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(600, 350),
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
	Ui.label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -80, 0, 32), Text = "BLOCKLINGS", Parent = panel })
	refs.summary = Ui.label({
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -80, 0, 20),
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
		CollectionController.SetOpen(false)
	end)

	local scroll = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 72),
		Size = UDim2.new(1, -24, 1, -84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	})
	Ui.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(132, 170),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	Ui.new("UIPadding", { PaddingBottom = UDim.new(0, 8), Parent = scroll })
	for index, species in Progression.AllSpecies() do
		buildCard(scroll, species, index)
	end
	refs.panel = holder
end

local function buildMenuButton()
	local _holder, button, badge = HudController.AddMenuButton("PetsButton", 2, Color3.fromRGB(50, 165, 140), "PETS")
	local icon = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(56, 54),
		BackgroundTransparency = 1,
		Parent = button,
	})
	BlocklingModel.Viewport(icon, Progression.AllSpecies()[1].Id)
	refs.badge = badge
	button.Activated:Connect(function()
		CollectionController.SetOpen(not panelOpen)
	end)
end

-- Reveal ------------------------------------------------------------------------

local function buildReveal(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "BlocklingReveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(300, 290),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	Ui.scaled(holder)
	local card = Ui.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		AutoButtonColor = false,
		Text = "",
		Parent = holder,
	}, { Ui.corner(20) })
	refs.revealStroke = Ui.stroke(5)
	refs.revealStroke.Parent = card
	refs.revealPop = Ui.new("UIScale", { Parent = card })
	refs.revealTitle = Ui.label({ Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 30), Parent = card })
	refs.revealPortrait = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.fromOffset(170, 140),
		BackgroundTransparency = 1,
		Parent = card,
	})
	refs.revealName = Ui.label({ Position = UDim2.fromOffset(12, 186), Size = UDim2.new(1, -24, 0, 34), Parent = card })
	refs.revealInfo = Ui.label({ Position = UDim2.fromOffset(12, 222), Size = UDim2.new(1, -24, 0, 20), Parent = card })
	refs.revealBonus = Ui.label({
		Position = UDim2.fromOffset(12, 246),
		Size = UDim2.new(1, -24, 0, 22),
		TextColor3 = Colors.Gold,
		Parent = card,
	})
	refs.reveal = holder
	card.Activated:Connect(function()
		revealToken += 1
		refs.reveal.Visible = false
	end)
end

local showNextReveal

local function showReveal(payload)
	local species = Progression.Species(payload.speciesId)
	if not species then
		return
	end
	revealShowing = true
	revealToken += 1
	local token = revealToken
	local color = rarityColor(species.Rarity)

	local mutation = if typeof(payload.mutation) == "string" then payload.mutation else nil
	local mutationDef = mutation and Config.Blocklings.Mutations.Defs[mutation]
	if payload.newMutation and mutationDef then
		refs.revealTitle.Text = `{string.upper(mutation :: string)}!`
		refs.revealTitle.TextColor3 = mutationDef.Color
	else
		refs.revealTitle.Text = if payload.isNew then "NEW BLOCKLING!" else "LEVEL UP!"
		refs.revealTitle.TextColor3 = color
	end
	refs.revealStroke.Color = if mutationDef then mutationDef.Color else color
	refs.revealName.Text = if mutation then `{mutation} {species.Name}` else species.Name
	refs.revealInfo.Text = `{species.Rarity} | Lv {Progression.Level(payload.count)}/{Config.Blocklings.MaxLevel}`
	refs.revealInfo.TextColor3 = color
	refs.revealBonus.Text = `+{percent(Progression.Bonus(species.Id, payload.count, mutation))} coins`
		.. (if payload.equipped then "  (equipped!)" else "")
	for _, child in refs.revealPortrait:GetChildren() do
		child:Destroy()
	end
	local _, model = BlocklingModel.Viewport(refs.revealPortrait, species.Id)
	revealModel = model

	refs.reveal.Visible = true
	Ui.pop(refs.revealPop, 0.3)
	SoundController.Play("Blockling")
	task.delay(3.2, function()
		if revealToken == token then
			refs.reveal.Visible = false
		end
		revealShowing = false
		showNextReveal()
	end)
end

showNextReveal = function()
	if revealShowing then
		return
	end
	local nextPayload = table.remove(revealQueue, 1)
	if nextPayload then
		showReveal(nextPayload)
	end
end

-- The Blockling pops out of the block, then hops to the player
local function popOut(speciesId: string, position: Vector3)
	local model = BlocklingModel.Build(speciesId, 0.85, false, ClientState.Mutation(speciesId))
	model:PivotTo(CFrame.new(position))
	model.Parent = workspace
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if t < 0.5 then
			local up = math.sin(t / 0.5 * math.pi / 2) * 5
			model:PivotTo(CFrame.new(position + Vector3.new(0, up, 0)) * CFrame.Angles(0, t * 12, 0))
		elseif root and t < 1.1 then
			local alpha = (t - 0.5) / 0.6
			local from = position + Vector3.new(0, 5, 0)
			local arc = math.sin(alpha * math.pi) * 3
			model:PivotTo(CFrame.new(from:Lerp(root.Position, alpha) + Vector3.new(0, arc, 0)) * CFrame.Angles(0, t * 12, 0))
		else
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

local function onBlocklingFound(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.speciesId) ~= "string" then
		return
	end
	if typeof(payload.position) == "Vector3" then
		popOut(payload.speciesId, payload.position)
	end
	if payload.isNew then
		refs.badge.Visible = not panelOpen
	end
	table.insert(revealQueue, payload)
	task.delay(if typeof(payload.position) == "Vector3" then 0.9 else 0, showNextReveal)
	if panelOpen then
		refreshAll()
	end
end

-- Lifecycle -------------------------------------------------------------------

function CollectionController.Init()
	equipRemote = Net.Get(Constants.Remotes.EquipRequest)
	local gui = HudController.Gui :: ScreenGui
	buildMenuButton()
	buildPanel(gui)
	buildReveal(gui)
end

function CollectionController.Start()
	Net.Get(Constants.Remotes.BlocklingFound).OnClientEvent:Connect(onBlocklingFound)
	ClientState.Changed:Connect(function(key)
		local blocklingKey = string.sub(key, 1, 3) == "Bl_" or string.sub(key, 1, 4) == "BlM_"
		if panelOpen and (blocklingKey or key == Constants.PlayerAttr.Equipped or key == Constants.PlayerAttr.Slots) then
			refreshAll()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.P then
			CollectionController.SetOpen(not panelOpen)
		end
	end)
	-- Gentle spin on the reveal portrait
	RunService.RenderStepped:Connect(function(dt)
		if revealModel and revealModel.Parent and refs.reveal.Visible then
			revealModel:PivotTo(revealModel:GetPivot() * CFrame.Angles(0, dt * 1.5, 0))
		end
	end)
end

return CollectionController
