--[[
	IntroController: the first thing a player sees.
		1. fade from black, letterbox bars slide in, the camera swoops in from high and far
		   and settles into an orbit of Bonk Stadium
		2. the logo builds itself: B-O-N-K pop in one by one (then wave), BLOCKS slams down
		   with a UI shake, sunburst rays spin behind it, mystery blocks float up the screen
		3. PLAY (or auto after Config.Intro.AutoContinueSeconds): a "LET'S BONK!" stinger wipes
		   the screen, the camera cuts behind the player and settles in
		4. the RELEASE!! card if this version is new to them (ReleaseController)
		5. ClientReady -> the server drops the welcome block (the 30-second hook starts here)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Net = require(Shared:WaitForChild("Net"))

local Ui = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Ui"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local ReleaseController = require(script.Parent:WaitForChild("ReleaseController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local player = Players.LocalPlayer
local Colors = Ui.Colors
local rng = Random.new()

local LETTER_COLORS = {
	Color3.fromRGB(255, 110, 170), -- B pink
	Color3.fromRGB(255, 150, 50), -- O orange
	Color3.fromRGB(255, 215, 60), -- N gold
	Color3.fromRGB(90, 200, 255), -- K sky
}
local LETTER_WIDTH = 112

local IntroController = {}

local refs: { [string]: any } = {}
local readyRemote
local finished = false
local orbit: RBXScriptConnection? = nil
local baseFov = 70

local function arenaCenter(): Vector3
	local zone = CollectionService:GetTagged(Constants.Tags.BlockSpawnZone)[1]
	if zone and zone:IsA("BasePart") then
		return Vector3.new(zone.Position.X, zone.Position.Y - 38, zone.Position.Z)
	end
	return Vector3.new(0, 10, 0)
end

-- Text with a thick cartoon outline and a dark drop shadow behind it
local function chunkyText(parent: Instance, props: { [string]: any }, outline: number): TextLabel
	props.TextStrokeTransparency = 1
	props.Parent = parent
	local shadowProps = table.clone(props)
	shadowProps.Position = (props.Position or UDim2.new()) + UDim2.fromOffset(4, 7)
	shadowProps.TextColor3 = Colors.Stroke
	shadowProps.ZIndex = (props.ZIndex or 2) - 1
	local shadow = Ui.label(shadowProps)
	Ui.new("UIStroke", { Thickness = outline, Color = Colors.Stroke, Parent = shadow })
	local label = Ui.label(props)
	Ui.new("UIStroke", { Thickness = outline, Color = Colors.Stroke, Parent = label })
	return label
end

local function afterIntro()
	-- Know whether this release was seen (max 5s wait for the profile)
	local deadline = os.clock() + 5
	while not ClientState.IsLoaded() and os.clock() < deadline do
		task.wait(0.1)
	end
	if ReleaseController.NeedsShow() then
		ReleaseController.Show(function()
			readyRemote:FireServer(true)
		end)
	else
		readyRemote:FireServer(false)
	end
end

-- Screen covered by the stinger: swap the intro for the game underneath
local function cutToGame(): (Camera?, BasePart?)
	if orbit then
		orbit:Disconnect()
		orbit = nil
	end
	refs.scene.Visible = false
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if camera then
		camera.FieldOfView = baseFov
		if root then
			local high = root.Position - root.CFrame.LookVector * 34 + Vector3.new(0, 22, 0)
			camera.CFrame = CFrame.lookAt(high, root.Position)
		end
	end
	local hud = HudController.Gui :: ScreenGui
	hud.Enabled = true
	return camera, root
end

local function endIntro()
	if finished then
		return
	end
	finished = true
	SoundController.Play("RoundStart")

	-- Stinger: a slanted pink band sweeps across, the game appears behind it
	local band = refs.stinger :: Frame
	band.Position = UDim2.fromScale(-1.1, 0.5)
	band.Visible = true
	Ui.tween(band, 0.32, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.wait(0.34)
	local camera, root = cutToGame()
	task.wait(0.22)
	Ui.tween(band, 0.34, { Position = UDim2.fromScale(2.1, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	-- ...while the camera settles in behind the player
	if camera and root then
		local behind = root.Position - root.CFrame.LookVector * 14 + Vector3.new(0, 8, 0)
		local tween = TweenService:Create(camera, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(behind, root.Position),
		})
		tween:Play()
		tween.Completed:Wait()
	else
		task.wait(0.36)
	end
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	refs.gui.Enabled = false
	afterIntro()
end

-- Build ---------------------------------------------------------------------------

local function buildRays(parent: Instance)
	local rays = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = parent,
	})
	for index = 0, 7 do
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(70, 1100),
			Rotation = index * 22.5,
			BackgroundColor3 = if index % 2 == 0 then Colors.Gold else Color3.fromRGB(255, 150, 200),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = rays,
		}, {
			Ui.new("UIGradient", { -- fade out toward both ends
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.2),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end
	TweenService:Create(rays, TweenInfo.new(24, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
	refs.rays = rays
end

local function buildLogo(content: Frame)
	refs.letters, refs.letterHomes, refs.letterPops = {}, {}, {}
	local word = "BONK"
	local left = (640 - LETTER_WIDTH * #word) / 2
	for index = 1, #word do
		local home = UDim2.fromOffset(left + (index - 1) * LETTER_WIDTH, 0)
		local slot = Ui.new("Frame", {
			Position = home,
			Size = UDim2.fromOffset(LETTER_WIDTH, 120),
			BackgroundTransparency = 1,
			Rotation = (index % 2 == 0) and 5 or -5,
			ZIndex = 3,
			Parent = content,
		})
		chunkyText(slot, {
			Size = UDim2.fromScale(1, 1),
			Text = string.sub(word, index, index),
			TextColor3 = LETTER_COLORS[index],
			ZIndex = 4,
		}, 5)
		refs.letterPops[index] = Ui.new("UIScale", { Scale = 0, Parent = slot })
		refs.letters[index] = slot
		refs.letterHomes[index] = home
	end

	local blocks = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, 104),
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundTransparency = 1,
		Rotation = 2,
		Visible = false,
		ZIndex = 3,
		Parent = content,
	})
	chunkyText(blocks, { Size = UDim2.fromScale(1, 1), Text = "BLOCKS", TextColor3 = Colors.Gold, ZIndex = 4 }, 5)
	refs.blocks = blocks
	refs.blocksPop = Ui.new("UIScale", { Parent = blocks })

	refs.tagline = Ui.label({
		Position = UDim2.fromOffset(0, 200),
		Size = UDim2.new(1, 0, 0, 28),
		Text = "Bonk. Crack. Crush. Collect!",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		ZIndex = 3,
		Parent = content,
	})
end

local function buildPlay(content: Frame)
	local holder = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 240),
		Size = UDim2.fromOffset(280, 84),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = content,
	})
	refs.playPop = Ui.new("UIScale", { Scale = 0, Parent = holder })
	local play = Ui.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Good,
		Text = "",
		ZIndex = 3,
		Parent = holder,
	}, { Ui.corner(26) })
	Ui.animatedStroke(Ui.new("UIStroke", { Thickness = 5, Parent = play }), Ui.Rainbow, 2.5)
	chunkyText(play, { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -24), Text = "PLAY", ZIndex = 5 }, 4)
	Ui.shine(play, 1.6)
	local pulse = Ui.new("UIScale", { Parent = play })
	TweenService:Create(pulse, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.08 }):Play()
	play.Activated:Connect(function()
		task.spawn(endIntro)
	end)
end

local function buildStinger(gui: ScreenGui)
	local band = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-1.1, 0.5),
		Size = UDim2.fromScale(1.6, 2.2), -- covers the whole screen at 12 degrees
		Rotation = 12,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, {
		Ui.new("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 110, 170), Color3.fromRGB(130, 90, 255)),
		}),
	})
	local text = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.12),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = band,
	})
	chunkyText(text, { Size = UDim2.fromScale(1, 1), Text = "LET'S BONK!", TextColor3 = Colors.Gold, ZIndex = 22 }, 6)
	refs.stinger = band
end

local function build()
	local gui = Ui.new("ScreenGui", {
		Name = "BonkIntro",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	refs.gui = gui
	-- Everything except the stinger lives in "scene", hidden in one go at the cut
	local scene = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, Parent = gui })
	refs.scene = scene

	refs.floaters = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, Parent = scene })

	local holder = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 340),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = scene,
	})
	Ui.scaled(holder)
	local content = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = holder })
	refs.content = content
	buildRays(content)
	buildLogo(content)
	buildPlay(content)

	-- Cinematic letterbox bars (slide in at the start)
	refs.bars = {}
	for _, top in { true, false } do
		table.insert(
			refs.bars,
			Ui.new("Frame", {
				AnchorPoint = Vector2.new(0, if top then 0 else 1),
				Position = UDim2.fromScale(0, if top then 0 else 1),
				Size = UDim2.fromScale(1, 0),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = scene,
			})
		)
	end
	Ui.label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -12),
		Size = UDim2.fromOffset(120, 22),
		Text = `v{Config.Release.Version}`,
		TextColor3 = Colors.Muted,
		ZIndex = 6,
		Parent = scene,
	})
	refs.fade = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = scene,
	})
	buildStinger(gui)
end

-- Sequences -------------------------------------------------------------------------

-- Mystery blocks drifting up behind the logo until the intro ends
local function floatBlocks()
	local palette = Config.Blocks.Palette
	while not finished do
		local size = rng:NextInteger(26, 54)
		local color = palette[rng:NextInteger(1, #palette)]
		local spin = rng:NextNumber(-40, 40)
		local block = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(rng:NextNumber(0.04, 0.96), 0, 1.1, 0),
			Size = UDim2.fromOffset(size, size),
			Rotation = spin,
			BackgroundColor3 = color,
			BackgroundTransparency = 0.1,
			ZIndex = 1,
			Parent = refs.floaters,
		}, { Ui.corner(math.floor(size * 0.2)), Ui.stroke(3) })
		Ui.label({
			Size = UDim2.fromScale(1, 1),
			Text = "?",
			ZIndex = 1,
			Parent = block,
		})
		local seconds = rng:NextNumber(5, 8)
		Ui.tween(block, seconds, {
			Position = UDim2.new(block.Position.X.Scale, 0, -0.15, 0),
			Rotation = spin + rng:NextNumber(-140, 140),
		}, Enum.EasingStyle.Linear)
		task.delay(seconds, block.Destroy, block)
		task.wait(0.35)
	end
end

local function playLogo()
	task.wait(0.6)
	for _, pop in refs.letterPops do
		Ui.tween(pop, 0.38, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		SoundController.Play("Hit")
		task.wait(0.13)
	end
	task.wait(0.2)
	-- BLOCKS slams down from big to normal, then the logo shakes
	refs.blocksPop.Scale = 2.8
	refs.blocks.Visible = true
	Ui.tween(refs.blocksPop, 0.2, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(0.2)
	SoundController.Play("Crush")
	Ui.shake(refs.content)
	Ui.tween(refs.tagline, 0.4, { TextTransparency = 0, TextStrokeTransparency = 0.25 })
	task.wait(0.3)
	Ui.tween(refs.playPop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

function IntroController.Init()
	readyRemote = Net.Get(Constants.Remotes.ClientReady)
	build()
end

function IntroController.Start()
	local skip = not Config.Intro.Enabled or (RunService:IsStudio() and Config.Debug.SkipIntro == true)
	if skip then
		finished = true
		task.spawn(afterIntro)
		return
	end

	local hud = HudController.Gui :: ScreenGui
	hud.Enabled = false
	refs.gui.Enabled = true
	Ui.tween(refs.fade, 0.9, { BackgroundTransparency = 1 })
	for _, bar in refs.bars do
		Ui.tween(bar, 0.6, { Size = UDim2.fromScale(1, 0.11) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
	task.spawn(playLogo)
	task.spawn(floatBlocks)

	local camera = workspace.CurrentCamera
	if camera then
		baseFov = camera.FieldOfView
	end
	local center = arenaCenter()
	local started = os.clock()
	local angle = 0.6
	orbit = RunService.RenderStepped:Connect(function(dt)
		local current = workspace.CurrentCamera
		if not current then
			return
		end
		current.CameraType = Enum.CameraType.Scriptable
		local t = os.clock() - started
		-- Swoop: start 1.7x farther and 2.2x higher, ease into the orbit over ~4.5s
		local settle = 1 - (1 - math.min(t / 4.5, 1)) ^ 3
		angle += dt * (0.09 + 0.3 * (1 - settle))
		local radius = Config.Intro.OrbitRadius * (1.7 - 0.7 * settle)
		local height = Config.Intro.OrbitHeight * (2.2 - 1.2 * settle) + math.sin(t * 0.5) * 6
		local position = center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		current.CFrame = CFrame.lookAt(position, center + Vector3.new(0, 6, 0))
		current.FieldOfView = 62
		-- Logo letters wave once they're in
		for index, slot in refs.letters do
			slot.Position = refs.letterHomes[index] + UDim2.fromOffset(0, math.sin(t * 3 + index * 0.7) * 5)
		end
	end)
	task.delay(Config.Intro.AutoContinueSeconds, endIntro)
end

return IntroController
