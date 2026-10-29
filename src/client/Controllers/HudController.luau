--[[
	HudController: the main ScreenGui. Coin counter, round timer, team score,
	banners, toasts and the round-end summary. Other controllers parent their
	widgets to HudController.Gui (the swing button, the upgrade panel).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local player = Players.LocalPlayer
local State = Constants.RoundState
local Mode = Constants.Mode
local Colors = Ui.Colors

local HudController = {}
HudController.Gui = nil :: ScreenGui?

local refs: { [string]: any } = {}
local bannerToken = 0
local toastOrder = 0
local lastState: string? = nil
local lastCountdown = -1

local function teamColor(teamId: string?): Color3
	local def = teamId and Config.Teams[teamId]
	return if def then def.Color else Colors.Text
end

-- Build -------------------------------------------------------------------------

local function scoreBox(parent: Instance, name: string, order: number)
	local box = Ui.new("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(100, 52),
		BackgroundColor3 = Colors.Panel,
		Parent = parent,
	}, { Ui.corner(12) })
	local stroke = Ui.stroke(3)
	stroke.Parent = box
	local caption = Ui.label({
		Size = UDim2.new(1, -8, 0, 15),
		Position = UDim2.fromOffset(4, 4),
		TextColor3 = Color3.new(1, 1, 1), -- sits on a team-colored fill
		Parent = box,
	})
	local value = Ui.label({ Size = UDim2.new(1, -8, 0, 28), Position = UDim2.fromOffset(4, 20), Text = "0", Parent = box })
	return { box = box, stroke = stroke, caption = caption, value = value }
end

local function buildTop(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(360, 84),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.scaled(holder)

	local row = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, Parent = holder })
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	refs.left = scoreBox(row, "LeftScore", 1)

	local timer = Ui.new("Frame", {
		Name = "Timer",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(136, 60),
		BackgroundColor3 = Colors.Panel,
		Parent = row,
	}, { Ui.corner(14), Ui.stroke(3) })
	refs.timerPop = Ui.new("UIScale", { Parent = timer })
	refs.timerCaption = Ui.label({
		Size = UDim2.new(1, -8, 0, 15),
		Position = UDim2.fromOffset(4, 5),
		TextColor3 = Colors.Muted,
		Parent = timer,
	})
	refs.timerValue = Ui.label({
		Size = UDim2.new(1, -8, 0, 34),
		Position = UDim2.fromOffset(4, 21),
		Text = "--:--",
		Parent = timer,
	})

	refs.right = scoreBox(row, "RightScore", 3)

	refs.top = holder

	-- Server-wide event: "Next: MEGA BLOCK in 4:12" / "MEGA BLOCK! 1:05 left"
	refs.eventChip = Ui.label({
		Name = "EventChip",
		Position = UDim2.fromOffset(-60, 84),
		Size = UDim2.new(1, 120, 0, 18),
		TextColor3 = Colors.Muted,
		Visible = Config.Events.Enabled,
		Parent = holder,
	})
	-- Mega Block HP bar (only while one exists)
	local bossBar = Ui.new("Frame", {
		Name = "BossBar",
		Position = UDim2.fromOffset(-40, 106),
		Size = UDim2.new(1, 80, 0, 24),
		BackgroundColor3 = Colors.Stroke,
		Visible = false,
		Parent = holder,
	}, { Ui.corner(12), Ui.stroke(3) })
	refs.bossFill = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Config.Events.Defs.MegaBlock.Color,
		Parent = bossBar,
	}, { Ui.corner(12) })
	refs.bossLabel = Ui.label({
		Position = UDim2.fromOffset(8, 3),
		Size = UDim2.new(1, -16, 1, -6),
		ZIndex = 2,
		Parent = bossBar,
	})
	refs.bossBar = bossBar

	refs.hint = Ui.label({
		Name = "Hint",
		Position = UDim2.fromOffset(-60, 64),
		Size = UDim2.new(1, 120, 0, 18),
		TextColor3 = Colors.Text,
		Parent = holder,
	})
end

local function buildCoins(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "Coins",
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.fromOffset(176, 50),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.scaled(holder)
	local pill = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Panel,
		Parent = holder,
	}, { Ui.corner(25), Ui.stroke(3) })
	refs.coinPop = Ui.new("UIScale", { Parent = pill })

	local icon = Ui.new("Frame", {
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Colors.Gold,
		Parent = pill,
	}, { Ui.round(), Ui.stroke(3, Colors.GoldDark) })
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 235, 140),
		Parent = icon,
	}, { Ui.round() })

	refs.coinValue = Ui.label({
		Position = UDim2.fromOffset(52, 7),
		Size = UDim2.new(1, -62, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "...",
		Parent = pill,
	})
	refs.coinNumber = Ui.new("NumberValue", { Value = 0, Parent = pill })
	refs.coinNumber.Changed:Connect(function(value)
		refs.coinValue.Text = MathUtil.formatNumber(value)
	end)
end

local function buildBanner(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromOffset(620, 100),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.scaled(holder)
	local inner = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = holder })
	refs.bannerPop = Ui.new("UIScale", { Parent = inner })
	refs.bannerTitle = Ui.label({
		Size = UDim2.new(1, 0, 0, 64),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = inner,
	})
	-- Warm top-to-bottom shading on the big title (multiplies the banner's color): cartoon 3D look
	Ui.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 205, 150)),
		Rotation = 90,
		Parent = refs.bannerTitle,
	})
	refs.bannerSub = Ui.label({
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 28),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = inner,
	})
end

local function buildToasts(_gui: ScreenGui)
	-- Child of the scaled top bar: positions don't scale with UIScale, so a separate
	-- holder would overlap the bar on large screens.
	local holder = Ui.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 52), -- below the event chip and boss bar
		Size = UDim2.fromOffset(380, 150),
		BackgroundTransparency = 1,
		Parent = refs.top,
	})
	Ui.new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	refs.toasts = holder
end

local function buildCombo(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "Combo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromOffset(260, 56),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.scaled(holder)
	local inner = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = holder })
	refs.comboPop = Ui.new("UIScale", { Parent = inner })
	refs.comboLabel = Ui.label({
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Colors.Gold,
		TextStrokeTransparency = 0,
		Visible = false,
		Parent = inner,
	})
end

-- Anime speed lines around the screen edge during a frenzy combo
local function buildSpeedLines(gui: ScreenGui)
	local container = Ui.new("Frame", {
		Name = "SpeedLines",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 0,
		Parent = gui,
	})
	refs.speedLines = container
	refs.lines = {}
	local count = 22
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local line = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.56, 0.5 + math.sin(angle) * 0.62),
			Size = UDim2.new(0, 3, 0.3, 0),
			Rotation = math.deg(angle) + 90, -- long axis points at the screen center
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = container,
		})
		table.insert(refs.lines, line)
	end
	RunService.RenderStepped:Connect(function()
		if container.Visible then
			for _, line in refs.lines do
				line.BackgroundTransparency = 0.35 + math.random() * 0.6
			end
		end
	end)
end

-- Cosmetic combo: your hits within Config.Vfx.ComboWindow of each other
local combo = 0
local lastComboHit = 0
local comboToken = 0

local function onOwnHit()
	local now = os.clock()
	combo = if now - lastComboHit <= Config.Vfx.ComboWindow then combo + 1 else 1
	lastComboHit = now
	comboToken += 1
	local token = comboToken
	refs.speedLines.Visible = combo >= Config.Vfx.FrenzyCombo and player:GetAttribute("Set_shake") ~= false
	if combo >= Config.Vfx.ComboMinShown then
		refs.comboLabel.Text = `x{combo} COMBO!`
		refs.comboLabel.TextColor3 = if combo >= 10 then Colors.Bad elseif combo >= 6 then Colors.Accent else Colors.Gold
		refs.comboLabel.Visible = true
		Ui.pop(refs.comboPop, math.min(0.4, 0.1 + combo * 0.02))
	end
	task.delay(Config.Vfx.ComboWindow, function()
		if comboToken == token then
			combo = 0
			refs.comboLabel.Visible = false
			refs.speedLines.Visible = false
		end
	end)
end

local function buildSummary(gui: ScreenGui)
	local holder = Ui.new("Frame", {
		Name = "Summary",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(440, 230),
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
	refs.summaryPop = Ui.new("UIScale", { Parent = card })
	refs.summaryTitle = Ui.label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 44), Parent = card })
	refs.summaryScore = Ui.label({
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.new(1, -32, 0, 26),
		TextColor3 = Colors.Muted,
		Parent = card,
	})
	refs.summaryStats = Ui.label({
		Position = UDim2.fromOffset(16, 92),
		Size = UDim2.new(1, -32, 0, 84),
		TextWrapped = true,
		Parent = card,
	})
	refs.summaryMvp = Ui.label({
		Position = UDim2.fromOffset(16, 184),
		Size = UDim2.new(1, -32, 0, 30),
		TextColor3 = Colors.Gold,
		Parent = card,
	})
	refs.summary = holder
end

local function buildLeftMenu(gui: ScreenGui)
	-- One scaled column so menu buttons never overlap at any UI scale
	local menu = Ui.new("Frame", {
		Name = "LeftMenu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 8),
		Size = UDim2.fromOffset(84, 3 * 84 + 2 * 10),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.scaled(menu)
	Ui.new("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = menu,
	})
	refs.leftMenu = menu
end

-- Public helpers ----------------------------------------------------------------

-- Adds a big square button to the left menu. Returns (holder, button, badge).
-- Put an icon in the top ~56px of the button; the label sits at the bottom.
function HudController.AddMenuButton(name: string, order: number, color: Color3, text: string): (Frame, TextButton, Frame)
	local holder = Ui.new("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(84, 84),
		BackgroundTransparency = 1,
		Parent = refs.leftMenu,
	})
	local button = Ui.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Text = "",
		Parent = holder,
	}, { Ui.corner(18), Ui.stroke(4) })
	Ui.label({
		Position = UDim2.new(0, 4, 1, -26),
		Size = UDim2.new(1, -8, 0, 20),
		Text = text,
		Parent = button,
	})
	local badge = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Colors.Bad,
		Visible = false,
		ZIndex = 3,
		Parent = button,
	}, { Ui.round(), Ui.stroke(3) })
	Ui.label({ Size = UDim2.fromScale(1, 1), Text = "!", ZIndex = 3, Parent = badge })
	return holder, button, badge
end

-- Only one big panel at a time: opening one closes the previous.
local openPanel: { name: string, close: () -> () }? = nil

function HudController.PanelOpened(name: string, close: () -> ())
	local previous = openPanel
	openPanel = { name = name, close = close }
	if previous and previous.name ~= name then
		previous.close()
	end
end

function HudController.PanelClosed(name: string)
	if openPanel and openPanel.name == name then
		openPanel = nil
	end
end

function HudController.Banner(title: string, subtitle: string?, color: Color3?, duration: number?)
	bannerToken += 1
	local token = bannerToken
	refs.bannerTitle.Text = title
	refs.bannerTitle.TextColor3 = color or Colors.Text
	refs.bannerSub.Text = subtitle or ""
	for _, label in { refs.bannerTitle, refs.bannerSub } do
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.2
	end
	Ui.pop(refs.bannerPop, 0.35)
	task.delay(duration or 2.2, function()
		if bannerToken ~= token then
			return
		end
		for _, label in { refs.bannerTitle, refs.bannerSub } do
			Ui.tween(label, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
end

function HudController.Toast(text: string, color: Color3?)
	toastOrder += 1
	local accent = color or Colors.Text
	local toast = Ui.new("Frame", {
		LayoutOrder = toastOrder,
		Size = UDim2.fromOffset(380, 32),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.1,
		Parent = refs.toasts,
	}, { Ui.corner(10) })
	local stroke = Ui.stroke(2, accent)
	stroke.Parent = toast
	local label = Ui.label({
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 1, -8),
		Text = text,
		TextColor3 = accent,
		Parent = toast,
	})

	-- keep at most 3 on screen
	local frames = {}
	for _, child in refs.toasts:GetChildren() do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	table.sort(frames, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #frames - 3 do
		frames[i]:Destroy()
	end

	task.delay(2.6, function()
		if not toast.Parent then
			return
		end
		Ui.tween(toast, 0.35, { BackgroundTransparency = 1 })
		Ui.tween(stroke, 0.35, { Transparency = 1 })
		Ui.tween(label, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.4)
		toast:Destroy()
	end)
end

-- Updates -----------------------------------------------------------------------

local function updateCoins()
	if not ClientState.IsLoaded() then
		refs.coinValue.Text = "..."
		return
	end
	local coins = ClientState.Coins()
	local previous = refs.coinNumber.Value
	if coins ~= previous then
		Ui.tween(refs.coinNumber, 0.35, { Value = coins })
		if coins > previous then
			Ui.pop(refs.coinPop, 0.15)
		end
	end
	refs.coinValue.Text = MathUtil.formatNumber(previous)
end

local function updateScoreboard()
	local mode = ClientState.Mode()
	local state = ClientState.State()
	local left, right = refs.left, refs.right

	if mode == Mode.Teams then
		left.caption.Text = Config.Teams.Red.ShortName
		left.value.Text = tostring(ClientState.Score("Red"))
		left.stroke.Color = Config.Teams.Red.Color:Lerp(Color3.new(1, 1, 1), 0.4)
		left.box.BackgroundColor3 = Config.Teams.Red.Color:Lerp(Color3.new(0, 0, 0), 0.25)
		right.box.Visible = true
		right.caption.Text = Config.Teams.Blue.ShortName
		right.value.Text = tostring(ClientState.Score("Blue"))
		right.stroke.Color = Config.Teams.Blue.Color:Lerp(Color3.new(1, 1, 1), 0.4)
		right.box.BackgroundColor3 = Config.Teams.Blue.Color:Lerp(Color3.new(0, 0, 0), 0.25)
	else
		left.caption.Text = Config.Teams.Crew.ShortName
		left.value.Text = `{ClientState.Score("Crew")}/{ClientState.CoopTarget()}`
		left.stroke.Color = Config.Teams.Crew.Color:Lerp(Color3.new(1, 1, 1), 0.4)
		left.box.BackgroundColor3 = Config.Teams.Crew.Color:Lerp(Color3.new(0, 0, 0), 0.35)
		right.box.Visible = false
	end

	local teamId = ClientState.TeamId()
	if state == State.Active then
		if mode == Mode.Teams and teamId and Config.Teams[teamId] then
			refs.hint.Text = `You're {Config.Teams[teamId].ShortName}! Knock blocks into the {Config.Teams[teamId].ShortName} crusher`
			refs.hint.TextColor3 = teamColor(teamId)
		else
			refs.hint.Text = `Co-op! Crush {ClientState.CoopTarget()} points of blocks in ANY crusher`
			refs.hint.TextColor3 = Config.Teams.Crew.Color
		end
	elseif state == State.Intermission then
		refs.hint.Text = "Warm-up! Bonk blocks for coins. Upgrades are open."
		refs.hint.TextColor3 = Colors.Text
	elseif state == State.Summary then
		refs.hint.Text = "Round over!"
		refs.hint.TextColor3 = Colors.Text
	else
		refs.hint.Text = "Waiting for players..."
		refs.hint.TextColor3 = Colors.Muted
	end
end

local CAPTIONS = {
	[State.Waiting] = "WAITING",
	[State.Intermission] = "NEXT ROUND",
	[State.Active] = "TIME LEFT",
	[State.Summary] = "RESULTS",
}

local function updateTimer()
	local state = ClientState.State()
	refs.timerCaption.Text = CAPTIONS[state] or ""
	if state == State.Waiting then
		refs.timerValue.Text = "--:--"
		return
	end
	local left = ClientState.TimeLeft()
	refs.timerValue.Text = MathUtil.formatTime(left)
	refs.timerValue.TextColor3 = if state == State.Active and left <= 10 then Colors.Bad else Colors.Text

	local seconds = math.ceil(left)
	local window = if state == State.Active then 10 elseif state == State.Intermission then 3 else 0
	if seconds >= 1 and seconds <= window and seconds ~= lastCountdown then
		lastCountdown = seconds
		SoundController.Play("Countdown")
		if state == State.Intermission then
			HudController.Banner(tostring(seconds), nil, Colors.Gold, 0.8)
		else
			Ui.pop(refs.timerPop, 0.15) -- final-10-seconds tension
		end
	elseif seconds > window then
		lastCountdown = -1
	end
end

-- Events ------------------------------------------------------------------------

local warnedForEventAt = 0

local function findMega(): BasePart?
	for _, instance in CollectionService:GetTagged(Constants.Tags.Block) do
		if instance:IsA("BasePart") and instance:GetAttribute("Kind") == "Mega" then
			return instance
		end
	end
	return nil
end

local function updateEvents()
	if not Config.Events.Enabled then
		return
	end
	local now = workspace:GetServerTimeNow()
	local running = ClientState.Event()
	local runningDef = Config.Events.Defs[running]
	if runningDef then
		refs.eventChip.Text = `{runningDef.Name}! {MathUtil.formatTime(ClientState.EventEndsAt() - now)} left`
		refs.eventChip.TextColor3 = runningDef.Color
	else
		local schedule = Progression.EventSchedule(now)
		local nextDef = Config.Events.Defs[schedule.nextName]
		local wait = schedule.nextAt - now
		if nextDef then
			refs.eventChip.Text = `Next: {nextDef.Name} in {MathUtil.formatTime(wait)}`
			refs.eventChip.TextColor3 = Colors.Muted
			if wait <= Config.Events.WarningSeconds and warnedForEventAt ~= schedule.nextAt then
				warnedForEventAt = schedule.nextAt
				HudController.Toast(`{nextDef.Name} starts in {math.ceil(wait)}s!`, nextDef.Color)
			end
		end
	end

	local mega = findMega()
	refs.bossBar.Visible = mega ~= nil
	if mega then
		local hp, maxHp = mega:GetAttribute("HP") or 0, mega:GetAttribute("MaxHP") or 1
		refs.bossFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
		refs.bossLabel.Text = `MEGA BLOCK  {MathUtil.formatNumber(hp)} / {MathUtil.formatNumber(maxHp)}`
	end
end

local function onEventChanged()
	local def = Config.Events.Defs[ClientState.Event()]
	if def then
		SoundController.Play("Event")
		HudController.Banner(def.Name, def.Description, def.Color, 3.5)
	end
end

local function hideSummary()
	refs.summary.Visible = false
end

local function showSummary(summary: any)
	if typeof(summary) ~= "table" then
		return
	end
	local winner = summary.winner
	local title, color
	if summary.mode == Mode.Coop then
		if winner == "Crew" then
			title, color = "CREW WINS!", Config.Teams.Crew.Color
		else
			title, color = "TIME'S UP!", Colors.Muted
		end
		refs.summaryScore.Text = `Crushed {summary.scores.Crew or 0} / {summary.coopTarget} points`
	else
		if winner == "Draw" then
			title, color = "DRAW!", Colors.Text
		else
			local def = Config.Teams[winner]
			title, color = if def then `{def.ShortName} WINS!` else "ROUND OVER", teamColor(winner)
		end
		refs.summaryScore.Text = `RED {summary.scores.Red or 0}  -  {summary.scores.Blue or 0} BLUE`
	end
	refs.summaryTitle.Text = title
	refs.summaryTitle.TextColor3 = color

	local mine, mvp
	for _, entry in summary.players or {} do
		if entry.userId == player.UserId then
			mine = entry
		end
		if entry.userId == summary.mvpUserId then
			mvp = entry
		end
	end
	if mine then
		refs.summaryStats.Text = `You: {mine.damage} damage | {mine.cracks} cracked | {mine.crushes} crushed\n+{MathUtil.formatNumber(mine.coins)} coins this round`
	else
		refs.summaryStats.Text = "You joined late. Next round's yours!"
	end
	refs.summaryMvp.Text = if mvp then `MVP: {mvp.name} ({mvp.damage} damage)` else ""

	refs.summary.Visible = true
	Ui.pop(refs.summaryPop, 0.2)
end

local function onStateChanged()
	local state = ClientState.State()
	if state == lastState then
		return
	end
	local previous = lastState
	lastState = state

	if state == State.Active then
		hideSummary()
		SoundController.Play("RoundStart")
		if ClientState.Mode() == Mode.Teams then
			local teamId = ClientState.TeamId()
			local name = if teamId and Config.Teams[teamId] then Config.Teams[teamId].ShortName else "YOUR"
			HudController.Banner("BONK!", `Knock blocks into the {name} crusher!`, teamColor(teamId))
		else
			HudController.Banner("BONK!", `Crew goal: {ClientState.CoopTarget()} points before time runs out!`, Colors.Gold)
		end
	elseif state == State.Intermission then
		hideSummary()
		if previous ~= nil then
			HudController.Banner("Warm-up!", "Shop's open. Grab an upgrade!", Colors.Text, 1.8)
		end
	elseif state == State.Summary then
		SoundController.Play("RoundEnd")
	elseif state == State.Waiting then
		hideSummary()
	end
end

-- Lifecycle -------------------------------------------------------------------

function HudController.Init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	local gui = Ui.new("ScreenGui", {
		Name = "BonkHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	HudController.Gui = gui

	buildSpeedLines(gui)
	buildTop(gui)
	buildCoins(gui)
	buildLeftMenu(gui)
	buildBanner(gui)
	buildToasts(gui)
	buildCombo(gui)
	buildSummary(gui)
end

function HudController.Start()
	ClientState.Changed:Connect(function(key)
		if key == Constants.PlayerAttr.Coins or key == Constants.PlayerAttr.Loaded then
			updateCoins()
		elseif key == Constants.GameAttr.State then
			onStateChanged()
			updateScoreboard()
		elseif key == Constants.GameAttr.Event then
			onEventChanged()
		else
			updateScoreboard()
		end
	end)

	Net.Get(Constants.Remotes.RoundSummary).OnClientEvent:Connect(showSummary)
	Net.Get(Constants.UnreliableRemotes.BlockHit).OnClientEvent:Connect(function(_part, _position, _dealt, attackerId)
		if attackerId == player.UserId then
			onOwnHit()
		end
	end)
	Net.Get(Constants.Remotes.Notify).OnClientEvent:Connect(function(message)
		if typeof(message) == "table" and typeof(message.text) == "string" then
			HudController.Toast(message.text, if message.kind == "Gold" then Colors.Gold else nil)
		end
	end)

	refs.coinNumber.Value = ClientState.Coins()
	updateCoins()
	lastState = ClientState.State() -- no banner for the state we joined into
	updateScoreboard()

	-- Mega Block destroyed / escaped
	Net.Get(Constants.Remotes.BlockBurst).OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or payload.kind ~= "Mega" then
			return
		end
		if payload.reason == "Despawn" then
			HudController.Banner("IT ESCAPED!", "The Mega Block got away. Next time!", Colors.Muted, 3)
		else
			HudController.Banner("MEGA BLOCK DESTROYED!", "Everyone who helped got a Blockling!", Colors.Gold, 3.5)
		end
	end)

	task.spawn(function()
		while true do
			updateTimer()
			updateEvents()
			task.wait(0.2)
		end
	end)
end

return HudController
