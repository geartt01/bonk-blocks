param(
	[string]$Root,   # absolute path to the BonkBlocks folder
	[string]$Luau,   # absolute path to luau.exe (official luau-lang/luau release)
	[string]$Work    # throwaway folder: DELETED and recreated each run
)

# Runs tests/*.spec.luau against src/shared outside Roblox.
# Roblox globals used by the shared modules are stubbed on one prepended line.
$prelude = 'local BrickColor = { new = function(name) return { Name = name } end }; ' +
	'local Color3 = { fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end, new = function(r, g, b) return { R = r, G = g, B = b } end }; ' +
	'local Enum = setmetatable({}, { __index = function(_, c) return setmetatable({}, { __index = function(_, i) return c .. "." .. i end }) end }); ' +
	'local task = { spawn = function(f, ...) if type(f) == "thread" then coroutine.resume(f, ...) else coroutine.resume(coroutine.create(f), ...) end end }; ' +
	'local warn = print;'

if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force "$Work\shared", "$Work\tests" | Out-Null

Get-ChildItem "$Root\src\shared" -Filter *.luau | ForEach-Object {
	$body = Get-Content $_.FullName -Raw
	$body = $body -replace 'require\(script\.Parent(?::WaitForChild\("(\w+)"\)|\.(\w+))\)', 'require("./$1$2")'
	# No BOM: luau.exe can't parse a UTF-8 BOM (Windows PowerShell's utf8 adds one)
	[IO.File]::WriteAllText("$Work\shared\$($_.Name)", $prelude + "`n" + $body, (New-Object Text.UTF8Encoding($false)))
}
Get-ChildItem "$Root\tests" -Filter *.spec.luau | ForEach-Object { Copy-Item $_.FullName "$Work\tests\$($_.Name)" }

# Short 8.3 paths: luau.exe isn't long-path aware
$fso = New-Object -ComObject Scripting.FileSystemObject
$shortLuau = $fso.GetFile($Luau).ShortPath
$shortTests = $fso.GetFolder("$Work\tests").ShortPath # folder only: require() needs the real file name
$failed = $false
Get-ChildItem "$Work\tests" -Filter *.spec.luau | ForEach-Object {
	"== $($_.Name)"
	& $shortLuau (Join-Path $shortTests $_.Name)
	if ($LASTEXITCODE -ne 0) { $failed = $true }
}
if ($failed) { exit 1 }
