--[[
	DevArena: builds "Bonk Stadium", a complete, correctly tagged map for up to 12 players,
	when no part is tagged BlockSpawnZone or Crusher. Replace it any time by tagging your
	own arena (see README); set Config.Arena.BuildDevArenaIfMissing = false to disable.

	Layout (top view, floor top at Y = 10):
		[Blue trough | Blue crusher]   court 240 x 180   [Red crusher | Red trough]
		     X = -136 .. -120        X = -120 .. 120        X = 120 .. 136
	Red pushes blocks toward +X (spawns on the -X half), Blue toward -X.
	The court is a lilac checkerboard with team chevrons pointing at each crusher. There is no
	grass anywhere: template terrain is cleared and the island is pastel paving. Around the
	court: a paved plaza, bleachers, leaderboards, a giant sign, giant hammer statues, a ring
	of giant candy-colored trees, mystery-block towers, and floating blocks. In the sky:
	floating islands, a rainbow, a circling blimp and volumetric clouds.
	The template Baseplate/SpawnLocation are removed.
	Parts tagged "Spin" / "Bob" are animated client-side (AmbientController).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)

local FLOOR_TOP = 10
local HALF_X, HALF_Z = 120, 90 -- court half-extents (240 x 180 field)
local TROUGH = 16 -- crusher trough length (X)
local TILE = 20 -- floor tiles: a 12 x 9 checkerboard
local PLAZA_X, PLAZA_Z = HALF_X + TROUGH + 56, HALF_Z + 64 -- paved plaza half-extents
local LINE_COLOR = Color3.fromRGB(128, 104, 236)

local DevArena = {}

local function makePart(parent: Instance, name: string, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

local function decor(parent: Instance, name: string, props: { [string]: any }): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return makePart(parent, name, props)
end

local function trigger(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	return makePart(parent, name, {
		Size = size,
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
end

local function sign(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, heightScale: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0.2
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.95, heightScale or 0.6)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = color:Lerp(Color3.new(0, 0, 0), 0.6)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = parent
end

local function questionFaces(part: BasePart, color: Color3)
	for _, face in Enum.NormalId:GetEnumItems() do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 10
		gui.LightInfluence = 0.5
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.75, 0.75)
		label.Text = "?"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeColor3 = color:Lerp(Color3.new(0, 0, 0), 0.5)
		label.TextStrokeTransparency = 0
		label.Parent = gui
		gui.Parent = part
	end
end

-- Pitch -------------------------------------------------------------------------

-- A painted line on the floor (no collision, sits just above the tiles)
local function paint(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3?)
	return decor(model, name, {
		Size = Vector3.new(size.X, 0.08, size.Z),
		CFrame = cframe + Vector3.new(0, FLOOR_TOP + 0.04 - cframe.Position.Y, 0),
		Color = color or LINE_COLOR,
		CastShadow = false,
	})
end

-- A painted ">" on the floor pointing along dir (+1 = +X)
local function chevron(model: Model, x: number, z: number, dir: number, color: Color3)
	local tip = Vector3.new(x + dir * 3.5, FLOOR_TOP, z)
	for _, side in { -1, 1 } do
		local tail = Vector3.new(x - dir * 3.5, FLOOR_TOP, z + side * 7)
		paint(model, "Chevron", Vector3.new(2, 0, (tip - tail).Magnitude + 1), CFrame.lookAt((tip + tail) / 2, tip), color)
	end
end

local function ring(model: Model, center: Vector3, radius: number, width: number, segments: number)
	for i = 0, segments - 1 do
		local angle = (i / segments) * math.pi * 2
		local length = 2 * math.pi * radius / segments + 0.2
		paint(model, "Ring", Vector3.new(width, 0, length), CFrame.new(center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)) * CFrame.Angles(0, -angle, 0))
	end
end

local function buildPitch(model: Model)
	-- Party-court floor: a soft lilac checkerboard. It matches the purple/gold UI and keeps the
	-- bright mystery blocks readable. The base shows through the gaps as grout lines.
	makePart(model, "FloorBase", {
		Size = Vector3.new(HALF_X * 2, 4, HALF_Z * 2),
		Position = Vector3.new(0, FLOOR_TOP - 2.2, 0), -- 0.2 below the tiles: no z-fighting from far away
		Color = Color3.fromRGB(160, 140, 226),
	})
	local light, dark = Color3.fromRGB(238, 233, 255), Color3.fromRGB(214, 203, 252)
	for i = 0, (HALF_X * 2) / TILE - 1 do
		for j = 0, (HALF_Z * 2) / TILE - 1 do
			makePart(model, "Tile", {
				Size = Vector3.new(TILE - 0.5, 1, TILE - 0.5),
				Position = Vector3.new(-HALF_X + TILE / 2 + i * TILE, FLOOR_TOP - 0.5, -HALF_Z + TILE / 2 + j * TILE),
				Color = if (i + j) % 2 == 0 then light else dark,
			})
		end
	end

	-- Markings: boundary, halfway line, center circle, boxes in front of each crusher
	local line = 1
	paint(model, "Touchline", Vector3.new(HALF_X * 2, 0, line), CFrame.new(0, 0, HALF_Z - 2))
	paint(model, "Touchline", Vector3.new(HALF_X * 2, 0, line), CFrame.new(0, 0, -HALF_Z + 2))
	paint(model, "Halfway", Vector3.new(line, 0, HALF_Z * 2 - 4), CFrame.new(0, 0, 0))
	ring(model, Vector3.zero, 24, line, 44)
	-- Center badge where the Mega Block lands
	local badge = decor(model, "CenterBadge", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 34, 34), -- top sits above the halfway line (no z-fighting)
		CFrame = CFrame.new(0, FLOOR_TOP + 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(255, 130, 185),
		CastShadow = false,
	})
	local badgeGui = Instance.new("SurfaceGui")
	badgeGui.Face = Enum.NormalId.Right -- the cylinder's axis points up after the rotation
	badgeGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	badgeGui.PixelsPerStud = 10
	badgeGui.LightInfluence = 0.4
	local badgeText = Instance.new("TextLabel")
	badgeText.BackgroundTransparency = 1
	badgeText.AnchorPoint = Vector2.new(0.5, 0.5)
	badgeText.Position = UDim2.fromScale(0.5, 0.5)
	badgeText.Size = UDim2.fromScale(0.62, 0.32)
	badgeText.Text = "BONK!"
	badgeText.TextScaled = true
	badgeText.Font = Enum.Font.FredokaOne
	badgeText.TextColor3 = Color3.new(1, 1, 1)
	badgeText.TextStrokeColor3 = Color3.fromRGB(150, 40, 100)
	badgeText.TextStrokeTransparency = 0
	badgeText.Parent = badgeGui
	badgeGui.Parent = badge
	for _, x in { -1, 1 } do
		local edge = x * (HALF_X - 2)
		local boxDepth, boxWidth = 30, HALF_Z * 1.1
		paint(model, "BoxFront", Vector3.new(line, 0, boxWidth), CFrame.new(edge - x * boxDepth, 0, 0))
		for _, z in { -1, 1 } do
			paint(model, "BoxSide", Vector3.new(boxDepth, 0, line), CFrame.new(edge - x * boxDepth / 2, 0, z * boxWidth / 2))
		end
		paint(model, "GoalLine", Vector3.new(line, 0, HALF_Z * 2 - 4), CFrame.new(edge, 0, 0))

		-- Team chevrons ">>>" pointing at that team's crusher (Red = +X, Blue = -X).
		-- Two rows only: the middle is kept clear for the other team's spawn pad.
		local teamColor = Config.Teams[if x > 0 then "Red" else "Blue"].Color
		for _, z in { -HALF_Z * 0.55, HALF_Z * 0.55 } do
			for k = 0, 2 do
				chevron(model, x * (HALF_X - 44 - k * 10), z, x, teamColor)
			end
		end
	end

	-- Team end zones: painted color + big team name in front of each crusher
	for _, info in { { team = "Red", x = 1 }, { team = "Blue", x = -1 } } do
		local def = Config.Teams[info.team]
		local zone = paint(
			model,
			info.team .. "EndZone",
			Vector3.new(14, 0, HALF_Z * 2 - 6),
			CFrame.new(info.x * (HALF_X - 10), 0, 0),
			def.Color
		)
		zone.Transparency = 0.15
		zone.CFrame += Vector3.new(0, 0.03, 0) -- above the box lines it crosses
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 8
		gui.LightInfluence = 0.4
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.AnchorPoint = Vector2.new(0.5, 0.5)
		text.Position = UDim2.fromScale(0.5, 0.5)
		-- Box sized for the rotated orientation so the letters fill the long strip
		text.Size = UDim2.fromOffset((HALF_Z * 2 - 6) * 8 * 0.85, 14 * 8 * 0.8)
		text.Rotation = if info.x > 0 then 90 else -90 -- reads facing the crusher
		text.Text = def.ShortName
		text.TextScaled = true
		text.Font = Enum.Font.FredokaOne
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextTransparency = 0.15
		text.Parent = gui
		gui.Parent = zone
	end
	for _, side in { -1, 1 } do
		-- bumper rail + glass wall on the long sides
		makePart(model, "Bumper", {
			Size = Vector3.new(HALF_X * 2 + TROUGH * 2 + 4, 3, 2),
			Position = Vector3.new(0, FLOOR_TOP + 1.5, side * (HALF_Z + 1)),
			Color = Color3.fromRGB(255, 255, 255),
		})
		decor(model, "Trim", {
			Size = Vector3.new(HALF_X * 2 + TROUGH * 2 + 4, 0.4, 2.2),
			Position = Vector3.new(0, FLOOR_TOP + 3.1, side * (HALF_Z + 1)),
			Color = Color3.fromRGB(255, 200, 60),
			Material = Enum.Material.Neon,
		})
		makePart(model, "GlassWall", {
			Size = Vector3.new(HALF_X * 2 + TROUGH * 2 + 4, 20, 1),
			Position = Vector3.new(0, FLOOR_TOP + 13, side * (HALF_Z + 1.5)),
			Color = Color3.fromRGB(190, 225, 255),
			Transparency = 0.7,
			CastShadow = false,
		})
		makePart(model, "WallBase", { -- seals the trough sides below the floor
			Size = Vector3.new(HALF_X * 2 + TROUGH * 2 + 4, 10, 2),
			Position = Vector3.new(0, FLOOR_TOP - 5, side * (HALF_Z + 1)),
			Color = Color3.fromRGB(90, 80, 120),
		})
	end
end

-- Crushers ------------------------------------------------------------------------

local function buildCrusher(model: Model, team: string, x: number)
	local def = Config.Teams[team]
	local dark = def.Color:Lerp(Color3.new(0, 0, 0), 0.45)
	local centerX = x * (HALF_X + TROUGH / 2)

	makePart(model, team .. "TroughFloor", {
		Size = Vector3.new(TROUGH, 2, HALF_Z * 2),
		Position = Vector3.new(centerX, FLOOR_TOP - 7, 0),
		Color = dark,
		Material = Enum.Material.DiamondPlate,
	})
	local endWall = makePart(model, team .. "EndWall", {
		Size = Vector3.new(2, 26, HALF_Z * 2 + 4),
		Position = Vector3.new(x * (HALF_X + TROUGH + 1), FLOOR_TOP + 4, 0),
		Color = def.Color,
	})
	sign(endWall, if x > 0 then Enum.NormalId.Left else Enum.NormalId.Right, def.ShortName .. " CRUSHER", def.Color, 0.35)
	decor(model, team .. "EndTrim", {
		Size = Vector3.new(2.4, 0.6, HALF_Z * 2 + 4),
		Position = Vector3.new(x * (HALF_X + TROUGH + 1), FLOOR_TOP + 17, 0),
		Color = def.Color,
		Material = Enum.Material.Neon,
	})

	-- Machine look: two spinning rollers + teeth (cosmetic, no collision)
	for index, offset in { 4.5, 11.5 } do
		local roller = decor(model, team .. "Roller", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(HALF_Z * 2 - 2, 4, 4),
			CFrame = CFrame.new(x * (HALF_X + offset), FLOOR_TOP - 4, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Color = if index == 1 then Color3.fromRGB(70, 70, 85) else def.Color,
			Material = Enum.Material.Metal,
		})
		roller:SetAttribute("SpinSpeed", if index == 1 then 220 else -220)
		CollectionService:AddTag(roller, "Spin")
	end
	for z = -HALF_Z + 6, HALF_Z - 6, 8 do
		local tooth = decor(model, team .. "Tooth", {
			Size = Vector3.new(2.4, 2.4, 2.4),
			CFrame = CFrame.new(x * (HALF_X + 1.5), FLOOR_TOP - 4.8, z) * CFrame.Angles(0, math.rad(45), math.rad(45)),
			Color = Color3.fromRGB(250, 248, 240),
		})
		tooth:SetAttribute("Team", team)
		CollectionService:AddTag(tooth, Constants.Tags.CrusherVisual)
	end

	-- The actual crusher: a block whose center enters this volume is crushed for this team
	local zone = trigger(model, team .. "CrusherZone", Vector3.new(TROUGH, 26, HALF_Z * 2), Vector3.new(centerX, FLOOR_TOP - 6 + 13, 0))
	zone:SetAttribute("Team", team)
	CollectionService:AddTag(zone, Constants.Tags.Crusher)

	-- Team spawn on the far half, so the natural push direction is toward your crusher
	local pad = decor(model, team .. "Spawn", {
		Size = Vector3.new(12, 0.2, HALF_Z * 0.7),
		Position = Vector3.new(-x * HALF_X * 0.62, FLOOR_TOP + 0.1, 0),
		Color = def.Color,
		Transparency = 0.35,
		Material = Enum.Material.Neon,
	})
	pad:SetAttribute("Team", team)
	CollectionService:AddTag(pad, Constants.Tags.TeamSpawn)
end

-- Stands, boards, sign ------------------------------------------------------------

local function buildStands(model: Model)
	local colors = { Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 210, 80), Color3.fromRGB(90, 190, 255), Color3.fromRGB(140, 110, 255) }
	for _, side in { -1, 1 } do
		for step = 0, 4 do
			makePart(model, "Bleacher", {
				Size = Vector3.new(HALF_X * 2 + 20, 2 + step * 2.5, 5),
				Position = Vector3.new(0, FLOOR_TOP + (step * 2.5) / 2, side * (HALF_Z + 5 + step * 5)),
				Color = colors[(step % #colors) + 1],
			})
		end
	end
	-- Leaderboards on the +Z stands (Front face = -Z, toward the pitch)
	local boardX = HALF_X * 0.45
	local crushers = makePart(model, "Leaderboard", {
		Size = Vector3.new(30, 18, 1),
		Position = Vector3.new(-boardX, FLOOR_TOP + 24, HALF_Z + 30),
		Color = Color3.fromRGB(38, 32, 64),
	})
	CollectionService:AddTag(crushers, Constants.Tags.Leaderboard)
	local rebirths = makePart(model, "RebirthLeaderboard", {
		Size = Vector3.new(30, 18, 1),
		Position = Vector3.new(boardX, FLOOR_TOP + 24, HALF_Z + 30),
		Color = Color3.fromRGB(38, 32, 64),
	})
	rebirths:SetAttribute("Stat", "Rebirths")
	CollectionService:AddTag(rebirths, Constants.Tags.Leaderboard)
	for _, x in { -boardX, boardX } do
		makePart(model, "BoardPost", {
			Size = Vector3.new(2, 18, 2),
			Position = Vector3.new(x, FLOOR_TOP + 9, HALF_Z + 30.5),
			Color = Color3.fromRGB(70, 60, 100),
		})
	end

	-- Giant title sign over the -Z stands, drawn on its Back (+Z) face toward the pitch
	local title = makePart(model, "TitleSign", {
		Size = Vector3.new(80, 22, 2),
		Position = Vector3.new(0, FLOOR_TOP + 32, -(HALF_Z + 32)),
		Color = Color3.fromRGB(255, 120, 170),
	})
	sign(title, Enum.NormalId.Back, "BONK BLOCKS", Color3.fromRGB(255, 120, 170), 0.8)
	decor(model, "TitleTrim", {
		Size = Vector3.new(82, 1, 2.4),
		Position = Vector3.new(0, FLOOR_TOP + 21, -(HALF_Z + 32)),
		Color = Color3.fromRGB(255, 220, 80),
		Material = Enum.Material.Neon,
	})
	for _, x in { -36, 36 } do
		makePart(model, "SignPost", {
			Size = Vector3.new(3, 26, 3),
			Position = Vector3.new(x, FLOOR_TOP + 10, -(HALF_Z + 32)),
			Color = Color3.fromRGB(70, 60, 100),
		})
	end
end

-- Dressing: light towers, corner flags, bunting -----------------------------------

local function buildDressing(model: Model)
	local center = Vector3.new(0, FLOOR_TOP, 0)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			-- Floodlight tower aimed at the field
			local base = Vector3.new(sx * (HALF_X + TROUGH + 18), FLOOR_TOP - 2, sz * (HALF_Z + 32))
			makePart(model, "LightPole", {
				Size = Vector3.new(3, 56, 3),
				Position = base + Vector3.new(0, 28, 0),
				Color = Color3.fromRGB(80, 75, 110),
				Material = Enum.Material.Metal,
			})
			local headPosition = base + Vector3.new(0, 58, 0)
			decor(model, "Floodlight", {
				Size = Vector3.new(16, 8, 2),
				CFrame = CFrame.lookAt(headPosition, center),
				Color = Color3.fromRGB(255, 250, 225),
				Material = Enum.Material.Neon,
			})
			decor(model, "FloodlightFrame", {
				Size = Vector3.new(17, 9, 1.5),
				CFrame = CFrame.lookAt(headPosition, center) * CFrame.new(0, 0, 1.2),
				Color = Color3.fromRGB(60, 55, 85),
			})

			-- Corner flag in the color of the crusher at that end
			local def = Config.Teams[if sx > 0 then "Red" else "Blue"]
			local corner = Vector3.new(sx * (HALF_X - 3), FLOOR_TOP, sz * (HALF_Z - 3))
			decor(model, "FlagPole", {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(7, 0.35, 0.35),
				CFrame = CFrame.new(corner + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Color = Color3.new(1, 1, 1),
			})
			decor(model, "Flag", {
				Size = Vector3.new(0.15, 1.8, 2.6),
				Position = corner + Vector3.new(0, 6.1, 1.3),
				Color = def.Color,
			})
		end
	end

	-- Pennant bunting along the top of both glass walls
	local colors = { Color3.fromRGB(255, 110, 140), Color3.fromRGB(255, 215, 70), Color3.fromRGB(90, 190, 255), Color3.fromRGB(130, 230, 130) }
	for _, side in { -1, 1 } do
		local index = 0
		for x = -(HALF_X + TROUGH), HALF_X + TROUGH, 6 do
			index += 1
			decor(model, "Pennant", {
				Size = Vector3.new(0.3, 1.7, 1.7),
				CFrame = CFrame.new(x, FLOOR_TOP + 21.5, side * (HALF_Z + 1.5)) * CFrame.Angles(math.rad(45), 0, 0),
				Color = colors[(index % #colors) + 1],
				CastShadow = false,
			})
		end
	end
end

-- Island, trees, floating blocks -------------------------------------------------

local function buildIsland()
	local terrain = workspace.Terrain
	-- Start from empty terrain: a template's own terrain (e.g. Flat Terrain's grass plane)
	-- would otherwise show around and under the map
	terrain:Clear()
	local terrainAny: any = terrain
	pcall(function()
		terrainAny.Decoration = false -- no grass blades anywhere
	end)
	terrain:FillBlock(CFrame.new(0, -4, 0), Vector3.new(2048, 8, 2048), Enum.Material.Water)
	terrain:FillCylinder(CFrame.new(0, 2, 0), 8, 430, Enum.Material.Sand) -- beach ring
	-- No grass anywhere: the island top is pastel paving (top at Y = 8, just under the plaza)
	terrain:FillCylinder(CFrame.new(0, 3, 0), 10, 400, Enum.Material.Pavement)
	-- Keep the crusher troughs open
	for _, x in { -1, 1 } do
		terrain:FillBlock(CFrame.new(x * (HALF_X + TROUGH / 2), FLOOR_TOP, 0), Vector3.new(TROUGH, 16, HALF_Z * 2), Enum.Material.Air)
	end
	terrain:SetMaterialColor(Enum.Material.Pavement, Color3.fromRGB(232, 224, 248))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(250, 228, 176))
end

-- Welds a decor part to an anchored root, so the client moves the whole prop by its root
local function attach(root: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

-- Paved plaza around the stadium, so the arena sits on a clean pad instead of grass.
-- Built as 4 slabs around the court + troughs (a single slab would fill the troughs).
local function buildPlaza(model: Model)
	local outerX = HALF_X + TROUGH + 2 -- outside face of the crusher end walls
	local innerZ = HALF_Z + 2 -- outside face of the side walls
	local paving = Color3.fromRGB(226, 218, 246)
	local function slab(sizeX: number, sizeZ: number, x: number, z: number)
		makePart(model, "Plaza", {
			Size = Vector3.new(sizeX, 4, sizeZ),
			Position = Vector3.new(x, FLOOR_TOP - 3, z), -- top at FLOOR_TOP - 1, flush with the bleachers
			Color = paving,
		})
	end
	for _, side in { -1, 1 } do
		slab(PLAZA_X * 2, PLAZA_Z - innerZ, 0, side * (innerZ + PLAZA_Z) / 2)
		slab(PLAZA_X - outerX, innerZ * 2, side * (outerX + PLAZA_X) / 2, 0)
		-- white curb along the plaza edge
		-- (4 tall so it reaches down into the grass outside, 1 stud above the paving)
		decor(model, "Curb", {
			Size = Vector3.new(PLAZA_X * 2 + 6, 4, 3),
			Position = Vector3.new(0, FLOOR_TOP - 2, side * (PLAZA_Z + 1.5)),
			Color = Color3.new(1, 1, 1),
		})
		decor(model, "Curb", {
			Size = Vector3.new(3, 4, PLAZA_Z * 2),
			Position = Vector3.new(side * (PLAZA_X + 1.5), FLOOR_TOP - 2, 0),
			Color = Color3.new(1, 1, 1),
		})
	end
	-- Under the court edge: closes the field side of each trough below the floor
	for _, x in { -1, 1 } do
		makePart(model, "TroughInnerWall", {
			Size = Vector3.new(1, 4, HALF_Z * 2),
			Position = Vector3.new(x * (HALF_X - 0.5), FLOOR_TOP - 6, 0),
			Color = Color3.fromRGB(90, 80, 120),
		})
	end
end

-- Candy-colored canopies: green, blossom pink, mint, lilac
local CANOPIES = {
	{ Color3.fromRGB(90, 200, 110), Color3.fromRGB(125, 222, 120), Color3.fromRGB(70, 176, 96) },
	{ Color3.fromRGB(255, 165, 205), Color3.fromRGB(255, 196, 222), Color3.fromRGB(242, 140, 188) },
	{ Color3.fromRGB(140, 228, 196), Color3.fromRGB(178, 242, 216), Color3.fromRGB(112, 206, 176) },
	{ Color3.fromRGB(186, 158, 255), Color3.fromRGB(212, 192, 255), Color3.fromRGB(160, 132, 240) },
}
local FLOWERS = { Color3.fromRGB(255, 110, 170), Color3.fromRGB(255, 215, 70), Color3.fromRGB(90, 200, 255), Color3.new(1, 1, 1) }

-- Cartoon tree, optionally in a white round planter ringed with flowers. Returns its parts.
local function buildTree(parent: Instance, position: Vector3, scale: number, rng: Random, planter: boolean): { BasePart }
	local parts = {}
	local trunkHeight = 10 * scale
	table.insert(parts, decor(parent, "Trunk", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 2.4 * scale, 2.4 * scale),
		CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(150, 98, 60),
		Material = Enum.Material.Wood,
	}))
	local colors = CANOPIES[rng:NextInteger(1, #CANOPIES)]
	for i = 1, 4 do
		local size = if i == 4 then 7 * scale else rng:NextNumber(8, 12) * scale
		local offset = if i == 4
			then Vector3.new(0, trunkHeight + 7.5 * scale, 0)
			else Vector3.new(rng:NextNumber(-2, 2) * scale, trunkHeight + (i - 1) * 2.5 * scale, rng:NextNumber(-2, 2) * scale)
		table.insert(parts, decor(parent, "Leaves", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			Position = position + offset,
			Color = colors[((i - 1) % 3) + 1],
		}))
	end
	if planter then
		table.insert(parts, decor(parent, "Planter", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2 * scale, 9 * scale, 9 * scale),
			CFrame = CFrame.new(position + Vector3.new(0, scale, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.new(1, 1, 1),
		}))
		for f = 1, 6 do
			local angle = f / 6 * math.pi * 2
			table.insert(parts, decor(parent, "Flower", {
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.6 * scale,
				Position = position + Vector3.new(math.cos(angle) * 3 * scale, 2.2 * scale, math.sin(angle) * 3 * scale),
				Color = FLOWERS[(f % #FLOWERS) + 1],
			}))
		end
	end
	return parts
end

-- Stack of giant mystery blocks with a smaller one hovering and turning on top
local function buildBlockTower(parent: Instance, base: Vector3, rng: Random)
	local palette = Config.Blocks.Palette
	local y = base.Y
	for _, size in { 30, 24, 19 } do
		local color = palette[rng:NextInteger(1, #palette)]
		local block = decor(parent, "TowerBlock", {
			Size = Vector3.one * size,
			CFrame = CFrame.new(base.X + rng:NextNumber(-1.5, 1.5), y + size / 2, base.Z + rng:NextNumber(-1.5, 1.5))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-4, 4))),
			Color = color,
		})
		questionFaces(block, color)
		y += size
	end
	local color = palette[rng:NextInteger(1, #palette)]
	local crown = decor(parent, "TowerCrown", {
		Size = Vector3.one * 13,
		CFrame = CFrame.new(base.X, y + 12, base.Z) * CFrame.Angles(math.rad(20), 0, math.rad(20)),
		Color = color,
	})
	questionFaces(crown, color)
	crown:SetAttribute("BobHeight", 3)
	crown:SetAttribute("BobSpeed", 0.35)
	crown:SetAttribute("SpinSpeed", 25)
	crown:SetAttribute("SpinAxis", "Y")
	CollectionService:AddTag(crown, "Bob")
	CollectionService:AddTag(crown, "Spin")
end

-- Giant hammer smashed into the plaza, handle leaning away from the court
local function buildHammerStatue(parent: Instance, position: Vector3, color: Color3, lean: number)
	local base = CFrame.new(position) * CFrame.Angles(0, 0, lean) * CFrame.Angles(0, math.pi / 2, 0)
	decor(parent, "StatueHead", { Size = Vector3.new(36, 18, 18), CFrame = base, Color = color })
	for _, side in { -1, 1 } do
		decor(parent, "StatueCap", {
			Size = Vector3.new(4, 21, 21),
			CFrame = base * CFrame.new(side * 17, 0, 0),
			Color = Color3.fromRGB(225, 228, 240),
			Material = Enum.Material.Metal,
		})
	end
	decor(parent, "StatueHandle", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(74, 6, 6),
		CFrame = base * CFrame.new(0, 9 + 37, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(205, 140, 80),
		Material = Enum.Material.Wood,
	})
	for i = 0, 2 do
		decor(parent, "StatueGrip", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 6.8, 6.8),
			CFrame = base * CFrame.new(0, 9 + 58 + i * 5, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(130, 95, 255),
		})
	end
end

local function buildScenery(model: Model)
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = model
	local rng = Random.new(42)
	local function outsidePlaza(position: Vector3, margin: number): boolean
		return math.abs(position.X) > PLAZA_X + margin or math.abs(position.Z) > PLAZA_Z + margin
	end

	-- A ring of giant trees around the plaza (gaps on the diagonals for the block towers)
	local giants = 16
	for i = 0, giants - 1 do
		local angle = (i + 0.5) / giants * math.pi * 2 + rng:NextNumber(-0.06, 0.06)
		local radius = rng:NextNumber(270, 320)
		local position = Vector3.new(math.cos(angle) * radius, 8, math.sin(angle) * radius)
		if outsidePlaza(position, 14) then
			buildTree(scenery, position, rng:NextNumber(3.2, 4.4), rng, true)
		end
	end
	-- Smaller trees between the giants and the beach
	for _ = 1, 28 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(335, 385)
		buildTree(scenery, Vector3.new(math.cos(angle) * radius, 8, math.sin(angle) * radius), rng:NextNumber(1.2, 2), rng, false)
	end
	-- Mystery-block towers on the diagonals
	for _, degrees in { 45, 135, 225, 315 } do
		local angle = math.rad(degrees)
		buildBlockTower(scenery, Vector3.new(math.cos(angle) * 300, 8, math.sin(angle) * 300), rng)
	end
	-- A giant team-colored hammer behind each crusher
	for _, info in { { team = "Red", x = 1 }, { team = "Blue", x = -1 } } do
		buildHammerStatue(scenery, Vector3.new(info.x * 170, FLOOR_TOP + 6, 0), Config.Teams[info.team].Color, -info.x * math.rad(18))
	end

	local palette = Config.Blocks.Palette
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2 + 0.3
		local size = rng:NextNumber(14, 24)
		local color = palette[(i % #palette) + 1]
		local block = decor(scenery, "FloatingBlock", {
			Size = Vector3.one * size,
			CFrame = CFrame.new(math.cos(angle) * (HALF_X + 130), 45 + rng:NextNumber(0, 25), math.sin(angle) * (HALF_Z + 125))
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
			Color = color,
		})
		questionFaces(block, color)
		block:SetAttribute("BobHeight", rng:NextNumber(2, 4))
		block:SetAttribute("BobSpeed", rng:NextNumber(0.4, 0.8))
		block:SetAttribute("SpinSpeed", rng:NextNumber(6, 14))
		block:SetAttribute("SpinAxis", "Y") -- turn around world up (rollers spin on their own axis)
		CollectionService:AddTag(block, "Bob")
		CollectionService:AddTag(block, "Spin")
	end
end

-- Sky: floating islands, a rainbow, a blimp ---------------------------------------

-- A floating island (pastel top, rocky underside tapering to a point) carrying a giant
-- mystery block or a tree. One anchored root, the rest welded, so it bobs as one piece.
local function buildSkyIsland(parent: Instance, position: Vector3, scale: number, rng: Random)
	local radius = 30 * scale
	local root = decor(parent, "SkyIsland", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4 * scale, radius * 2, radius * 2),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(236, 228, 250),
	})
	root:SetAttribute("BobHeight", 4 + scale * 2)
	root:SetAttribute("BobSpeed", rng:NextNumber(0.05, 0.1))
	CollectionService:AddTag(root, "Bob")

	local y = position.Y - 2 * scale
	for index, color in { Color3.fromRGB(176, 156, 214), Color3.fromRGB(152, 132, 198), Color3.fromRGB(128, 110, 180) } do
		local height = 9 * scale
		local r = radius * (1 - index * 0.26)
		attach(root, decor(parent, "SkyRock", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, r * 2, r * 2),
			CFrame = CFrame.new(position.X, y - height / 2, position.Z) * CFrame.Angles(0, 0, math.pi / 2),
			Color = color,
		}))
		y -= height
	end

	local top = position + Vector3.new(0, 2 * scale, 0)
	if rng:NextNumber() < 0.5 then
		local palette = Config.Blocks.Palette
		local color = palette[rng:NextInteger(1, #palette)]
		local block = decor(parent, "SkyBlock", {
			Size = Vector3.one * 16 * scale,
			CFrame = CFrame.new(top + Vector3.new(0, 8 * scale, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Color = color,
		})
		questionFaces(block, color)
		attach(root, block)
	else
		for _, part in buildTree(parent, top, 1.8 * scale, rng, false) do
			attach(root, part)
		end
	end
end

-- A big rainbow arching out of the sea behind the title sign
local function buildRainbow(parent: Instance)
	local colors = {
		Color3.fromRGB(255, 90, 120),
		Color3.fromRGB(255, 150, 60),
		Color3.fromRGB(255, 220, 70),
		Color3.fromRGB(90, 210, 110),
		Color3.fromRGB(70, 160, 255),
		Color3.fromRGB(150, 100, 255),
	}
	local center = Vector3.new(0, FLOOR_TOP - 30, -(PLAZA_Z + 300))
	local segments = 30
	for band, color in colors do
		local radius = 330 - (band - 1) * 13
		local length = math.pi * radius / segments + 1
		for i = 0, segments - 1 do
			local angle = (i + 0.5) / segments * math.pi
			decor(parent, "Rainbow", {
				Size = Vector3.new(length, 13, 3),
				CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0))
					* CFrame.Angles(0, 0, angle + math.pi / 2),
				Color = color,
				Material = Enum.Material.Neon,
				Transparency = 0.15,
				CastShadow = false,
			})
		end
	end
end

-- A pink "BONK BLOCKS" blimp circling high over the stadium (AmbientController "Orbit")
local function buildBlimp(parent: Instance)
	local center = Vector3.new(0, FLOOR_TOP + 150, 0)
	local pink = Color3.fromRGB(255, 120, 175)
	-- the envelope's axis (X) points along the direction of travel; the nose is +X
	local root = decor(parent, "Blimp", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(44, 20, 20),
		CFrame = CFrame.new(center + Vector3.new(230, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0),
		Color = pink,
	})
	root:SetAttribute("OrbitCenter", center)
	root:SetAttribute("OrbitSpeed", 3)
	CollectionService:AddTag(root, "Orbit")
	local base = root.CFrame
	local function piece(name: string, offset: CFrame, props: { [string]: any }): BasePart
		props.CFrame = base * offset
		local part = decor(parent, name, props)
		attach(root, part)
		return part
	end
	for _, side in { -1, 1 } do
		piece("BlimpEnd", CFrame.new(side * 22, 0, 0), { Shape = Enum.PartType.Ball, Size = Vector3.one * 20, Color = pink })
		piece("BlimpFin", CFrame.new(-31, side * 8, 0), { Size = Vector3.new(10, 10, 1.2), Color = Color3.fromRGB(255, 215, 70) })
		piece("BlimpFin", CFrame.new(-31, 0, side * 8), { Size = Vector3.new(10, 1.2, 10), Color = Color3.fromRGB(255, 215, 70) })
		local banner = piece("BlimpBanner", CFrame.new(0, 1, side * 9.7), { Size = Vector3.new(30, 7, 0.4), Color = Color3.new(1, 1, 1) })
		sign(banner, if side > 0 then Enum.NormalId.Back else Enum.NormalId.Front, "BONK BLOCKS", pink, 0.8)
	end
	piece("Gondola", CFrame.new(0, -12, 0), { Size = Vector3.new(12, 5, 6), Color = Color3.fromRGB(130, 95, 255) })
end

local function buildSky(model: Model)
	local sky = Instance.new("Folder")
	sky.Name = "Sky"
	sky.Parent = model
	local rng = Random.new(99)
	for i = 1, 5 do
		local angle = (i / 5) * math.pi * 2 + 0.4
		local radius = rng:NextNumber(560, 640)
		local position = Vector3.new(math.cos(angle) * radius, FLOOR_TOP + rng:NextNumber(100, 160), math.sin(angle) * radius)
		buildSkyIsland(sky, position, rng:NextNumber(1.2, 1.7), rng)
	end
	buildRainbow(sky)
	buildBlimp(sky)
end

-- Lighting ----------------------------------------------------------------------
-- Bright cartoon daylight. For the best look also set Lighting.Technology = Future in Studio
-- (scripts can't change Technology).

function DevArena.ApplyLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 15 -- afternoon: warm light, long-ish cartoon shadows
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(95, 95, 115)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 170)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.ExposureCompensation = 0.1

	local function ensure(className: string, name: string): Instance
		-- reuse the template's own Atmosphere/Bloom/etc: two of a kind would conflict
		local existing = Lighting:FindFirstChild(name) or Lighting:FindFirstChildOfClass(className)
		if existing and existing.ClassName == className then
			return existing
		end
		local instance = Instance.new(className)
		instance.Name = name
		instance.Parent = Lighting
		return instance
	end
	local atmosphere = ensure("Atmosphere", "BonkAtmosphere") :: Atmosphere
	-- Dreamy pastel sky: lilac haze toward the horizon, a big soft sun
	atmosphere.Density = 0.24
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(214, 206, 255)
	atmosphere.Decay = Color3.fromRGB(160, 122, 200)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.4
	local sky: any = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	sky.SunAngularSize = 18
	sky.MoonAngularSize = 12
	sky.StarCount = 1500
	-- Volumetric clouds drifting over the stadium
	local clouds: any = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = workspace.Terrain
	end
	clouds.Cover = 0.55
	clouds.Density = 0.5
	clouds.Color = Color3.fromRGB(255, 244, 252)
	local bloom = ensure("BloomEffect", "BonkBloom") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.6
	local grade = ensure("ColorCorrectionEffect", "BonkGrade") :: ColorCorrectionEffect
	grade.Saturation = 0.15
	grade.Contrast = 0.08
	grade.TintColor = Color3.fromRGB(255, 250, 245)
	local rays = ensure("SunRaysEffect", "BonkSunRays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.6
end

-- Build -------------------------------------------------------------------------

function DevArena.Build(): Model
	-- The template's grey Baseplate and its SpawnLocation would show around/under the island
	for _, name in { "Baseplate", "SpawnLocation" } do
		local leftover = workspace:FindFirstChild(name)
		if leftover and leftover:IsA("BasePart") then
			leftover:Destroy()
		end
	end

	local model = Instance.new("Model")
	model.Name = "DevArena"

	buildIsland()
	buildPlaza(model)
	buildPitch(model)
	buildCrusher(model, "Red", 1)
	buildCrusher(model, "Blue", -1)
	buildStands(model)
	buildDressing(model)
	buildScenery(model)
	buildSky(model)

	local spawnZone = trigger(model, "BlockSpawnZone", Vector3.new(HALF_X * 2 - 40, 1, HALF_Z * 2 - 20), Vector3.new(0, FLOOR_TOP + 38, 0))
	CollectionService:AddTag(spawnZone, Constants.Tags.BlockSpawnZone)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DevSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(0, FLOOR_TOP + 0.5, -HALF_Z + 10)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = model

	model.Parent = workspace
	return model
end

return DevArena
