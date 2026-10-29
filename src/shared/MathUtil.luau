--[[
	MathUtil: small helpers shared by server and client.
]]

local MathUtil = {}

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Lerp a { Start, Finish } range from Config
function MathUtil.range(range: { Start: number, Finish: number }, t: number): number
	return range.Start + (range.Finish - range.Start) * t
end

function MathUtil.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Closest point on an oriented box (a Part) to a world point
function MathUtil.closestPointOnBox(boxCFrame: CFrame, boxSize: Vector3, point: Vector3): Vector3
	local rel = boxCFrame:PointToObjectSpace(point)
	local half = boxSize / 2
	local clamped = Vector3.new(
		math.clamp(rel.X, -half.X, half.X),
		math.clamp(rel.Y, -half.Y, half.Y),
		math.clamp(rel.Z, -half.Z, half.Z)
	)
	return boxCFrame:PointToWorldSpace(clamped)
end

-- Distance from a world point to the surface of an oriented box (0 if inside)
function MathUtil.distanceToBox(boxCFrame: CFrame, boxSize: Vector3, point: Vector3): number
	return (MathUtil.closestPointOnBox(boxCFrame, boxSize, point) - point).Magnitude
end

function MathUtil.isInsideBox(boxCFrame: CFrame, boxSize: Vector3, point: Vector3): boolean
	local rel = boxCFrame:PointToObjectSpace(point)
	local half = boxSize / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

-- Pick from a list of { Weight = number, ... }
function MathUtil.weightedPick<T>(list: { T }, rng: Random): T
	local total = 0
	for _, item in list do
		total += (item :: any).Weight
	end
	local roll = rng:NextNumber(0, total)
	for _, item in list do
		roll -= (item :: any).Weight
		if roll <= 0 then
			return item
		end
	end
	return list[#list]
end

-- 1234567 -> "1.2M", 12345 -> "12,345"
function MathUtil.formatNumber(n: number): string
	n = math.floor(n)
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	end
	local formatted = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function MathUtil.formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return MathUtil
