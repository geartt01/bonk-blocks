param(
	[string]$Src,
	[string]$Analyzer,
	[string]$Work,
	[string]$Mode = "nonstrict"
)

# One-line prelude so line numbers shift by exactly 1
$values = @("game","workspace","script","Instance","Vector3","Vector2","CFrame","Color3","BrickColor","Enum","UDim","UDim2",
	"TweenInfo","NumberSequence","NumberSequenceKeypoint","ColorSequence","ColorSequenceKeypoint","NumberRange",
	"PhysicalProperties","RaycastParams","Random","task","warn","Font")
$types = @("Player","BasePart","Part","Model","Folder","Instance","Weld","Trail","Attachment","Highlight","ScreenGui",
	"GuiObject","Frame","TextLabel","TextButton","UIScale","UICorner","UIStroke","UIGradient","BillboardGui","Decal",
	"ParticleEmitter","IntValue","NumberValue","Team","Tween","AnimationTrack","RBXScriptConnection","Vector3","Vector2",
	"CFrame","Color3","UDim","UDim2","Random","RaycastResult","Sound","SurfaceGui","OrderedDataStore","TextBox","ViewportFrame","ScrollingFrame","ColorCorrectionEffect","Motor6D","Humanoid","Atmosphere","BloomEffect","SunRaysEffect","Camera","ColorSequence","GuiButton","InputObject")
$prelude = (($values | ForEach-Object { "local ${_}: any = nil;" }) -join " ") + " " + (($types | ForEach-Object { "type $_ = any;" }) -join " ")

if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force $Work | Out-Null

$files = Get-ChildItem $Src -Recurse -Filter *.luau
foreach ($f in $files) {
	$rel = $f.FullName.Substring($Src.Length).TrimStart('\')
	$dest = Join-Path $Work $rel
	New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
	$body = Get-Content $f.FullName -Raw
	# Rewrite Roblox instance requires into Luau string requires so modules type-check together
	$depth = ($rel.Split('\').Count) - 1
	$shared = if ($rel.StartsWith("shared\")) { "./" } else { ("../" * $depth) + "shared/" }
	$body = $body -replace 'require\(script\.Parent\.Parent(?::WaitForChild\("Util"\)|\.Util)(?::WaitForChild\("(\w+)"\)|\.(\w+))\)', 'require("../Util/$1$2")'
	$body = $body -replace 'require\(script\.Parent(?::WaitForChild\("(\w+)"\)|\.(\w+))\)', 'require("./$1$2")'
	$body = $body -replace 'require\((?:Shared|ReplicatedStorage:WaitForChild\("Shared"\))(?::WaitForChild\("(\w+)"\)|\.(\w+))\)', ('require("' + $shared + '$1$2")')
	[IO.File]::WriteAllText($dest, $prelude + "`n" + $body, (New-Object Text.UTF8Encoding($false))) # no BOM
}

# Short 8.3 paths: luau-analyze isn't long-path aware (MAX_PATH 260)
$fso = New-Object -ComObject Scripting.FileSystemObject
$shortWork = $fso.GetFolder($Work).ShortPath
$shortAnalyzer = $fso.GetFile($Analyzer).ShortPath
$targets = Get-ChildItem $Work -Recurse -Filter *.luau | ForEach-Object { Join-Path $shortWork $_.FullName.Substring($Work.Length).TrimStart('\') }
$out = & $shortAnalyzer --formatter=plain "--mode=$Mode" @targets 2>&1 | ForEach-Object { "$_" }

foreach ($line in $out) {
	# plain format: path:line:col: (W0) Kind: message
	if ($line -match '^(.*?\.luau):(\d+):(\d+)(-\d+)?: (.*)$') {
		$path = $Matches[1].Replace('/', '\')
		$path = $path.Substring([Math]::Min($shortWork.Length, $path.Length)).TrimStart('\')
		$ln = [int]$Matches[2] - 1
		$msg = $Matches[5]
		if ($ln -lt 1) { continue } # prelude itself
		if ($msg -match "Unknown type 'Enum\.") { continue }
		if ($msg -match "^\(W\d+\) UnknownType: Unknown type '") { continue } # typeof(x) == "Instance" etc.
		if ($msg -match "LocalUnused: Variable '(Shared|ReplicatedStorage)'") { continue } # artifact of require rewrite
		"${path}:${ln}: $msg"
	} else {
		$line
	}
}
"--- analyzed $($files.Count) files ($Mode)"
