--[[
	LeaderboardService: global top-N boards backed by OrderedDataStores.

	Any part tagged "Leaderboard" gets a SurfaceGui. Attributes on the part:
		Stat = "Crushed" (default) | "Rebirths"     which board it shows
		Face = "Front" (default) | "Back" | ...      which face the board is drawn on
	Each stat is pushed every Config.Leaderboard.RefreshSeconds: 2 writes/player/min,
	well inside DataStore budgets. Without DataStore access (Studio, API off) boards say "offline".
]]

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local MathUtil = require(Shared.MathUtil)

local DataService = require(script.Parent.DataService)

type Row = { name: string, value: number }
type Board = { title: string, field: string, storeName: string, store: OrderedDataStore?, rows: { Row }, status: string }

local LeaderboardService = {}

local BOARDS: { [string]: Board } = {
	Crushed = { title = "TOP CRUSHERS", field = "totalBlocksCrushed", storeName = Config.Leaderboard.StoreName, rows = {}, status = "Loading..." },
	Rebirths = { title = "TOP REBIRTHS", field = "rebirths", storeName = Config.Leaderboard.RebirthStoreName, rows = {}, status = "Loading..." },
}

local nameCache: { [number]: string } = {}

local function getName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name
	if player then
		name = player.DisplayName
	else
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok and typeof(result) == "string" then result else `Player {userId}`
	end
	nameCache[userId] = name
	return name
end

local function boardFor(part: BasePart): Board
	local stat = part:GetAttribute("Stat")
	return if typeof(stat) == "string" and BOARDS[stat] then BOARDS[stat] else BOARDS.Crushed
end

local function label(parent: Instance, text: string, y: number, height: number, color: Color3, alignLeft: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Position = UDim2.new(0.05, 0, y, 0)
	item.Size = UDim2.new(0.9, 0, height, 0)
	item.Font = Enum.Font.FredokaOne
	item.TextScaled = true
	item.TextColor3 = color
	item.TextStrokeTransparency = 0.4
	item.TextXAlignment = if alignLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	item.Text = text
	item.Parent = parent
	return item
end

local function getOrBuildGui(part: BasePart, board: Board): SurfaceGui
	local existing = part:FindFirstChild("BonkLeaderboard")
	if existing and existing:IsA("SurfaceGui") then
		return existing
	end
	local faceName = part:GetAttribute("Face")
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BonkLeaderboard"
	gui.Face = if typeof(faceName) == "string" and (Enum.NormalId :: any)[faceName]
		then (Enum.NormalId :: any)[faceName]
		else Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.3

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(38, 32, 64)
	background.Parent = gui

	label(background, board.title, 0.02, 0.14, Color3.fromRGB(255, 205, 60))
	local statusLabel = label(background, "", 0.45, 0.1, Color3.fromRGB(170, 165, 200))
	statusLabel.Name = "Status"
	for rank = 1, Config.Leaderboard.Size do
		local row = label(background, "", 0.17 + (rank - 1) * (0.8 / Config.Leaderboard.Size), 0.07, Color3.new(1, 1, 1), true)
		row.Name = "Row" .. rank
	end
	gui.Parent = part
	return gui
end

local function render()
	for _, instance in CollectionService:GetTagged(Constants.Tags.Leaderboard) do
		if instance:IsA("BasePart") then
			local board = boardFor(instance)
			local frame = getOrBuildGui(instance, board):FindFirstChildOfClass("Frame") :: Frame
			(frame:FindFirstChild("Status") :: TextLabel).Text = board.status
			for rank = 1, Config.Leaderboard.Size do
				local row = frame:FindFirstChild("Row" .. rank) :: TextLabel
				local entry = board.rows[rank]
				row.Text = if entry then `{rank}. {entry.name}  -  {MathUtil.formatNumber(entry.value)}` else ""
			end
		end
	end
end

local function push(board: Board)
	local store = board.store
	if not store then
		return
	end
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player) :: any
		local value = data and data[board.field]
		if typeof(value) == "number" and value > 0 then
			pcall(function()
				store:SetAsync(tostring(player.UserId), math.floor(value))
			end)
		end
	end
end

local function pull(board: Board)
	local store = board.store
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Config.Leaderboard.Size)
	end)
	if not ok then
		board.status = "Leaderboard offline"
		return
	end
	local fresh: { Row } = {}
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(fresh, { name = getName(userId), value = entry.value })
		end
	end
	board.rows = fresh
	board.status = if #fresh == 0 then "Nobody yet. Be the first!" else ""
end

function LeaderboardService.Start()
	if not Config.Leaderboard.Enabled then
		return
	end
	for _, board in BOARDS do
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.storeName)
		end)
		if ok then
			board.store = result
		else
			board.status = "Leaderboard offline"
		end
	end
	CollectionService:GetInstanceAddedSignal(Constants.Tags.Leaderboard):Connect(render)
	render()

	task.spawn(function()
		task.wait(5) -- let profiles load first
		while true do
			for _, board in BOARDS do
				push(board)
				pull(board)
			end
			render()
			task.wait(Config.Leaderboard.RefreshSeconds)
		end
	end)
end

return LeaderboardService
