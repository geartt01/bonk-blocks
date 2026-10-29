# Draws the Bonk Blocks store art with GDI+ (no downloads):
#   marketing\icon.png       512 x 512   game icon
#   marketing\logo.png       1400 x 700  transparent wordmark
#   marketing\thumbnail.png  1920 x 1080 store thumbnail
# Run: powershell -ExecutionPolicy Bypass -File tools\marketing.ps1
param([string]$Out = (Join-Path $PSScriptRoot '..\marketing'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $Out | Out-Null

function C([int]$r, [int]$g, [int]$b, [int]$a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }
function Lighten($c, [float]$t) { C ([int]($c.R + (255 - $c.R) * $t)) ([int]($c.G + (255 - $c.G) * $t)) ([int]($c.B + (255 - $c.B) * $t)) }
function Darken($c, [float]$t) { C ([int]($c.R * (1 - $t))) ([int]($c.G * (1 - $t))) ([int]($c.B * (1 - $t))) }
function Brush($c) { New-Object System.Drawing.SolidBrush($c) }
function P([float]$x, [float]$y) { New-Object System.Drawing.PointF($x, $y) }
function Rect([float]$x, [float]$y, [float]$w, [float]$h) { New-Object System.Drawing.RectangleF($x, $y, $w, $h) }
function Grad([float]$x, [float]$y, [float]$w, [float]$h, $c1, $c2, [float]$angle = 90) {
	New-Object System.Drawing.Drawing2D.LinearGradientBrush((Rect $x $y $w $h), $c1, $c2, [single]$angle, $true)
}
function New-Pen($c, [float]$w) {
	$pen = New-Object System.Drawing.Pen($c, [single]$w)
	$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
	$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
	$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
	$pen
}

$INK = C 34 24 66
$PINK = C 255 110 170
$ORANGE = C 255 150 50
$GOLD = C 255 210 60
$SKY = C 90 200 255
$GREEN = C 110 220 110
$LETTERS = @($PINK, $ORANGE, $GOLD, $SKY, (C 255 255 255))

# Font: the first chunky one installed
$installed = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }
$fontName = @('Fredoka One', 'Fredoka', 'Luckiest Guy', 'Lilita One', 'Segoe UI Black', 'Arial Black', 'Impact') |
	Where-Object { $installed -contains $_ } | Select-Object -First 1
$family = New-Object System.Drawing.FontFamily($fontName)
$style = if ($family.IsStyleAvailable([System.Drawing.FontStyle]::Bold)) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
Write-Output "font: $fontName ($style)"

function New-Canvas([int]$w, [int]$h) {
	$bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
	$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
	$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
	$g.Clear([System.Drawing.Color]::Transparent)
	@($bmp, $g)
}

function New-RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
	$p = New-Object System.Drawing.Drawing2D.GraphicsPath
	$d = [Math]::Max(1, $r * 2)
	$p.AddArc($x, $y, $d, $d, 180, 90)
	$p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
	$p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
	$p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
	$p.CloseFigure()
	$p
}

# Text outline path, visually centered on (cx, cy), optionally rotated
function New-TextPath([string]$text, [float]$size, [float]$cx, [float]$cy, [float]$angle = 0) {
	$p = New-Object System.Drawing.Drawing2D.GraphicsPath
	$p.AddString($text, $family, [int]$style, [single]$size, (P 0 0), [System.Drawing.StringFormat]::GenericTypographic)
	$b = $p.GetBounds()
	$m = New-Object System.Drawing.Drawing2D.Matrix
	$m.Translate([single]($cx - $b.X - $b.Width / 2), [single]($cy - $b.Y - $b.Height / 2))
	$p.Transform($m)
	if ($angle -ne 0) {
		$r = New-Object System.Drawing.Drawing2D.Matrix
		$r.RotateAt([single]$angle, (P $cx $cy))
		$p.Transform($r)
	}
	$p
}

# Thick ink outline + drop shadow + fill
function Draw-Chunky($g, $path, $fill, [float]$outline, [float]$shadow) {
	if ($shadow -gt 0) {
		$sp = [System.Drawing.Drawing2D.GraphicsPath]$path.Clone()
		$m = New-Object System.Drawing.Drawing2D.Matrix
		$m.Translate([single]($shadow * 0.45), [single]$shadow)
		$sp.Transform($m)
		$g.DrawPath((New-Pen $INK $outline), $sp)
		$g.FillPath((Brush $INK), $sp)
	}
	$g.DrawPath((New-Pen $INK $outline), $path)
	$g.FillPath($fill, $path)
	# glossy top highlight inside the letters
	$b = $path.GetBounds()
	$state = $g.Save()
	$g.SetClip($path)
	$g.FillRectangle((Brush (C 255 255 255 70)), $b.X, $b.Y, $b.Width, $b.Height * 0.38)
	$g.Restore($state)
}

# A word with one color per letter (gentle wave + alternating tilt)
function Draw-Word($g, [string]$word, [float]$size, [float]$cx, [float]$cy, $colors, [float]$outline, [float]$spacing, [float]$tilt) {
	$widths = @()
	foreach ($ch in $word.ToCharArray()) { $widths += (New-TextPath ([string]$ch) $size 0 0).GetBounds().Width }
	$total = ($widths | Measure-Object -Sum).Sum + $spacing * ($word.Length - 1)
	$x = $cx - $total / 2
	for ($i = 0; $i -lt $word.Length; $i++) {
		$w = $widths[$i]
		$ly = $cy + [Math]::Sin($i * 1.4) * $size * 0.05
		$angle = if ($i % 2 -eq 0) { -$tilt } else { $tilt }
		$p = New-TextPath ([string]$word[$i]) $size ($x + $w / 2) $ly $angle
		$col = $colors[$i % $colors.Count]
		$b = $p.GetBounds()
		Draw-Chunky $g $p (Grad $b.X ($b.Y - 1) $b.Width ($b.Height + 2) (Lighten $col 0.5) $col) $outline ($size * 0.07)
		$x += $w + $spacing
	}
}

function Draw-Burst($g, [float]$cx, [float]$cy, [float]$r1, [float]$r2, [int]$n, $fill, [float]$rot, [float]$inkWidth) {
	$pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
	for ($i = 0; $i -lt $n * 2; $i++) {
		$r = if ($i % 2 -eq 0) { $r1 } else { $r2 }
		$a = ($i / ($n * 2)) * [Math]::PI * 2 + $rot
		$pts.Add((P ($cx + [Math]::Cos($a) * $r) ($cy + [Math]::Sin($a) * $r)))
	}
	$arr = $pts.ToArray()
	$g.FillPolygon($fill, $arr)
	if ($inkWidth -gt 0) { $g.DrawPolygon((New-Pen $INK $inkWidth), $arr) }
}

function Draw-Sparkle($g, [float]$cx, [float]$cy, [float]$r) {
	Draw-Burst $g $cx $cy $r ($r * 0.28) 4 (Brush (C 255 255 255 235)) 0 0
}

function Draw-Coin($g, [float]$cx, [float]$cy, [float]$r, [float]$squash) {
	$w = $r * 2 * $squash; $h = $r * 2
	$g.FillEllipse((Brush (C 200 125 20)), [single]($cx - $w / 2 + $r * 0.14), [single]($cy - $h / 2 + $r * 0.08), [single]$w, [single]$h)
	$g.FillEllipse((Brush (C 255 205 50)), [single]($cx - $w / 2), [single]($cy - $h / 2), [single]$w, [single]$h)
	$g.DrawEllipse((New-Pen $INK ($r * 0.16)), [single]($cx - $w / 2), [single]($cy - $h / 2), [single]$w, [single]$h)
	$g.FillEllipse((Brush (C 255 235 130)), [single]($cx - $w * 0.3), [single]($cy - $h * 0.3), [single]($w * 0.6), [single]($h * 0.6))
	$g.FillEllipse((Brush (C 255 255 255 210)), [single]($cx - $w * 0.26), [single]($cy - $h * 0.3), [single]($w * 0.18), [single]($h * 0.18))
}

function Draw-Shadow($g, [float]$cx, [float]$cy, [float]$w) {
	$g.FillEllipse((Brush (C 40 20 90 70)), [single]($cx - $w / 2), [single]($cy - $w * 0.09), [single]$w, [single]($w * 0.18))
}

# Pseudo-3D cartoon block. mark = text on the front ("?"), face = Blockling eyes + smile
function Draw-Cube($g, [float]$cx, [float]$cy, [float]$s, $col, [float]$angle, [string]$mark, [bool]$cracked, [bool]$face) {
	$state = $g.Save()
	$g.TranslateTransform([single]$cx, [single]$cy)
	$g.RotateTransform([single]$angle)
	$h = $s / 2; $d = $s * 0.26
	$edgePen = New-Pen $INK ($s * 0.045)
	[System.Drawing.PointF[]]$top = @((P (-$h) (-$h)), (P (-$h + $d) (-$h - $d)), (P ($h + $d) (-$h - $d)), (P $h (-$h)))
	[System.Drawing.PointF[]]$side = @((P $h (-$h)), (P ($h + $d) (-$h - $d)), (P ($h + $d) ($h - $d)), (P $h $h))
	$g.FillPolygon((Brush (Lighten $col 0.38)), $top); $g.DrawPolygon($edgePen, $top)
	$g.FillPolygon((Brush (Darken $col 0.3)), $side); $g.DrawPolygon($edgePen, $side)
	$front = New-RoundRect (-$h) (-$h) $s $s ($s * 0.07)
	$g.FillPath((Grad (-$h) (-$h) $s $s (Lighten $col 0.15) (Darken $col 0.12)), $front)
	$g.FillPath((Brush (C 255 255 255 80)), (New-RoundRect (-$h + $s * 0.08) (-$h + $s * 0.07) ($s * 0.52) ($s * 0.12) ($s * 0.06)))
	$g.DrawPath($edgePen, $front)
	if ($cracked) {
		$crack = New-Pen $INK ($s * 0.028)
		$g.DrawLines($crack, [System.Drawing.PointF[]]@((P ($h * 0.98) (-$h * 0.55)), (P ($h * 0.55) (-$h * 0.42)), (P ($h * 0.66) (-$h * 0.12)), (P ($h * 0.3) ($h * 0.02)), (P ($h * 0.42) ($h * 0.34))))
		$g.DrawLines($crack, [System.Drawing.PointF[]]@((P ($h * 0.15) (-$h * 0.98)), (P ($h * 0.02) (-$h * 0.68)), (P ($h * 0.28) (-$h * 0.52))))
	}
	if ($mark) {
		$tp = New-TextPath $mark ($s * 0.6) 0 ($s * 0.04)
		Draw-Chunky $g $tp (Brush (C 255 255 255)) ($s * 0.07) ($s * 0.035)
	}
	if ($face) {
		foreach ($ex in @(-0.36, 0.36)) {
			$er = $s * 0.13
			$x = $h * $ex
			$y = -$h * 0.08
			$g.FillEllipse((Brush (C 255 255 255)), [single]($x - $er), [single]($y - $er * 1.15), [single]($er * 2), [single]($er * 2.3))
			$g.DrawEllipse((New-Pen $INK ($s * 0.03)), [single]($x - $er), [single]($y - $er * 1.15), [single]($er * 2), [single]($er * 2.3))
			$pr = $er * 0.62
			$g.FillEllipse((Brush $INK), [single]($x - $pr + $er * 0.15), [single]($y - $pr + $er * 0.1), [single]($pr * 2), [single]($pr * 2.2))
			$g.FillEllipse((Brush (C 255 255 255)), [single]($x - $pr * 0.1), [single]($y - $pr * 0.55), [single]($pr * 0.7), [single]($pr * 0.7))
			$g.FillEllipse((Brush (C 255 120 160 150)), [single]($x * 1.55 - $s * 0.08), [single]($h * 0.22), [single]($s * 0.16), [single]($s * 0.09))
		}
		$g.DrawArc((New-Pen $INK ($s * 0.04)), [single](-$h * 0.26), [single]($h * 0.05), [single]($h * 0.52), [single]($h * 0.42), [single]15, [single]150)
		# sprout on top
		$sx = $d * 0.5; $sy = -$h - $d * 0.5
		$g.DrawLine((New-Pen (C 60 150 70) ($s * 0.035)), [single]$sx, [single]$sy, [single]$sx, [single]($sy - $s * 0.16))
		foreach ($lx in @(-1, 1)) {
			$g.FillEllipse((Brush $GREEN), [single]($sx + $lx * $s * 0.09 - $s * 0.08), [single]($sy - $s * 0.24), [single]($s * 0.16), [single]($s * 0.1))
			$g.DrawEllipse((New-Pen $INK ($s * 0.02)), [single]($sx + $lx * $s * 0.09 - $s * 0.08), [single]($sy - $s * 0.24), [single]($s * 0.16), [single]($s * 0.1))
		}
	}
	$g.Restore($state)
}

# Cartoon hammer; (cx, cy) = head center, the handle points "up" before rotation
function Draw-Hammer($g, [float]$cx, [float]$cy, [float]$k, [float]$angle) {
	$state = $g.Save()
	$g.TranslateTransform([single]$cx, [single]$cy)
	$g.RotateTransform([single]$angle)
	$edgePen = New-Pen $INK (9 * $k)
	$hw = 50 * $k; $hl = 640 * $k
	$handle = New-RoundRect (-$hw / 2) (-$hl) $hw $hl ($hw / 2)
	$g.FillPath((Grad (-$hw / 2) (-$hl) $hw $hl (C 235 165 95) (C 165 100 50) 0), $handle)
	$g.DrawPath($edgePen, $handle)
	for ($i = 0; $i -lt 3; $i++) {
		$band = New-RoundRect (-$hw / 2 - 3 * $k) (-$hl + (70 + $i * 46) * $k) ($hw + 6 * $k) (24 * $k) (8 * $k)
		$g.FillPath((Brush (C 130 95 255)), $band)
		$g.DrawPath((New-Pen $INK (6 * $k)), $band)
	}
	$W = 310 * $k; $H = 176 * $k
	$head = New-RoundRect (-$W / 2) (-$H / 2) $W $H (38 * $k)
	$g.FillPath((Grad (-$W / 2) (-$H / 2) $W $H (C 255 135 160) (C 215 45 85)), $head)
	$g.DrawPath($edgePen, $head)
	foreach ($side in @(-1, 1)) {
		$capX = if ($side -lt 0) { -$W / 2 - 12 * $k } else { $W / 2 - 40 * $k }
		$cap = New-RoundRect $capX (-$H / 2 - 12 * $k) (52 * $k) ($H + 24 * $k) (20 * $k)
		$g.FillPath((Grad $capX (-$H / 2 - 12 * $k) (52 * $k) ($H + 24 * $k) (C 245 245 255) (C 160 165 195)), $cap)
		$g.DrawPath($edgePen, $cap)
	}
	$g.FillPath((Brush (C 255 255 255 90)), (New-RoundRect (-$W * 0.3) (-$H * 0.36) ($W * 0.5) ($H * 0.16) ($H * 0.08)))
	$g.Restore($state)
}

function Draw-Rays($g, [float]$cx, [float]$cy, [float]$R, [int]$n, $c) {
	for ($i = 0; $i -lt $n; $i += 2) {
		$g.FillPie((Brush $c), [single]($cx - $R), [single]($cy - $R), [single]($R * 2), [single]($R * 2), [single]($i * 360 / $n), [single](360 / $n))
	}
}

function Draw-Vignette($g, [int]$w, [int]$h, [int]$alpha) {
	$path = New-Object System.Drawing.Drawing2D.GraphicsPath
	$path.AddEllipse([single](-$w * 0.25), [single](-$h * 0.25), [single]($w * 1.5), [single]($h * 1.5))
	$pg = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
	$pg.CenterColor = C 0 0 0 0
	$pg.SurroundColors = [System.Drawing.Color[]]@((C 20 10 50 $alpha))
	$pg.FocusScales = New-Object System.Drawing.PointF(0.55, 0.55)
	$g.FillRectangle($pg, 0, 0, $w, $h)
}

function Save($bmp, [string]$name) {
	$path = Join-Path $Out $name
	$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
	Write-Output "saved $path"
}

# --- Icon 512 ---------------------------------------------------------------------
$bmp, $g = New-Canvas 512 512
$g.FillRectangle((Grad 0 0 512 512 (C 150 110 255) (C 64 36 160)), 0, 0, 512, 512)
Draw-Rays $g 256 270 600 20 (C 255 255 255 26)
Draw-Shadow $g 245 432 270
Draw-Cube $g 238 300 236 $PINK -8 '?' $true $false
Draw-Burst $g 330 170 70 36 9 (Brush (C 255 230 70)) 0.2 7
Draw-Burst $g 330 170 38 20 9 (Brush (C 255 255 210)) 0.5 0
Draw-Hammer $g 382 112 0.48 38
foreach ($c in @(@(78, 170, 22, 0.9), @(432, 300, 20, 0.6), @(120, 86, 16, 1), @(446, 410, 17, 0.8), @(70, 360, 15, 0.7))) { Draw-Coin $g $c[0] $c[1] $c[2] $c[3] }
Draw-Sparkle $g 190 120 18; Draw-Sparkle $g 460 230 14; Draw-Sparkle $g 60 260 12
Draw-Word $g 'BONK!' 128 256 452 $LETTERS 14 2 5
Draw-Vignette $g 512 512 70
Save $bmp 'icon.png'
$g.Dispose(); $bmp.Dispose()

# --- Logo (transparent) -----------------------------------------------------------
$bmp, $g = New-Canvas 1400 700
Draw-Burst $g 700 360 520 330 14 (Brush (C 255 220 90 60)) 0.1 0
Draw-Word $g 'BONK' 300 700 230 $LETTERS 26 10 6
$tp = New-TextPath 'BLOCKS' 205 700 505 2
$b = $tp.GetBounds()
Draw-Chunky $g $tp (Grad $b.X $b.Y $b.Width $b.Height (C 255 240 150) (C 255 185 30)) 24 15
Draw-Sparkle $g 230 120 34; Draw-Sparkle $g 1190 160 28; Draw-Sparkle $g 1230 560 22; Draw-Sparkle $g 170 580 20
Save $bmp 'logo.png'
$g.Dispose(); $bmp.Dispose()

# --- Thumbnail 1920 x 1080 --------------------------------------------------------
$W = 1920; $H = 1080
$bmp, $g = New-Canvas $W $H
$g.FillRectangle((Grad 0 0 $W 560 (C 95 175 255) (C 200 228 255)), 0, 0, $W, 560)
Draw-Rays $g 1250 470 1800 28 (C 255 255 255 22)
foreach ($cl in @(@(260, 110, 1.1), @(980, 70, 0.8), @(1560, 130, 1.0))) {
	$x = $cl[0]; $y = $cl[1]; $k = $cl[2]
	foreach ($e in @(@(0, 20, 150, 70), @(50, -10, 120, 90), @(110, 15, 140, 70), @(-50, 30, 110, 55))) {
		$g.FillEllipse((Brush (C 255 255 255 225)), [single]($x + $e[0] * $k), [single]($y + $e[1] * $k), [single]($e[2] * $k), [single]($e[3] * $k))
	}
}

# Floor: perspective lilac checkerboard (matches the in-game court)
$horizon = 470; $F = 900; $Z0 = 1.6
$camH = ($H - $horizon) * $Z0 / $F
function Project([float]$x, [float]$z) { P ($W / 2 + $x * $F / ($z + $Z0)) ($horizon + $camH * $F / ($z + $Z0)) }
$g.FillRectangle((Brush (C 160 140 226)), 0, 540, $W, $H - 540)
$T = 0.42; $gap = 0.018
for ($row = 0; $row * $T -lt 10; $row++) {
	$z1 = $row * $T; $z2 = $z1 + $T
	$halfUnits = ($W / 2) * ($z2 + $Z0) / $F + $T
	$cols = [Math]::Ceiling($halfUnits / $T)
	for ($col = -$cols; $col -lt $cols; $col++) {
		$x1 = $col * $T; $x2 = $x1 + $T
		[System.Drawing.PointF[]]$quad = @((Project ($x1 + $gap) ($z1 + $gap)), (Project ($x2 - $gap) ($z1 + $gap)), (Project ($x2 - $gap) ($z2 - $gap)), (Project ($x1 + $gap) ($z2 - $gap)))
		$tile = if ((($row + $col) % 2 + 2) % 2 -eq 0) { C 238 233 255 } else { C 214 203 252 }
		$g.FillPolygon((Brush $tile), $quad)
	}
}

# Stands + crowd + wall along the horizon
$standColors = @((C 255 140 175), (C 255 215 90), (C 120 200 255), (C 170 140 255))
for ($r = 0; $r -lt 4; $r++) {
	$y = 312 + $r * 30
	$g.FillRectangle((Brush $standColors[$r]), 0, $y, $W, 30)
	$rng = New-Object System.Random(11 + $r)
	for ($x = 8 + $r * 9; $x -lt $W; $x += 26 + $rng.Next(0, 10)) {
		$head = $LETTERS[$rng.Next(0, 4)]
		$g.FillEllipse((Brush (Darken $head 0.15)), [single]$x, [single]($y - 9), 18, 18)
		$g.DrawEllipse((New-Pen $INK 2.5), [single]$x, [single]($y - 9), 18, 18)
	}
}
$g.FillRectangle((Grad 0 432 $W 112 (C 130 100 240) (C 80 58 175)), 0, 432, $W, 112)
$g.FillRectangle((Brush $GOLD), 0, 424, $W, 12)
$penColors = @($PINK, $GOLD, $SKY, $GREEN)
for ($i = 0; $i * 64 -lt $W; $i++) {
	$x = $i * 64
	[System.Drawing.PointF[]]$flag = @((P $x 436), (P ($x + 52) 436), (P ($x + 26) 478))
	$g.FillPolygon((Brush $penColors[$i % 4]), $flag)
	$g.DrawPolygon((New-Pen $INK 3), $flag)
}
$g.FillRectangle((Brush (C 255 255 255)), 0, 536, $W, 12)
$g.FillRectangle((Grad 0 548 $W 120 (C 255 255 255 120) (C 255 255 255 0)), 0, 548, $W, 120)

# Floating blocks in the sky
Draw-Cube $g 1790 300 90 $SKY 14 '?' $false $false
Draw-Cube $g 1010 150 64 $GREEN -12 '?' $false $false

# Hero: the hammer bonks a giant mystery block, coins explode out
Draw-Shadow $g 1160 892 520
Draw-Shadow $g 1690 978 300
Draw-Shadow $g 650 905 200
Draw-Shadow $g 335 1000 150
Draw-Cube $g 1690 840 240 $GREEN 9 '?' $false $false
Draw-Cube $g 1150 670 400 $PINK -6 '?' $true $false
Draw-Burst $g 1300 452 150 82 11 (Brush (C 255 228 70)) 0.15 10
Draw-Burst $g 1300 452 86 48 11 (Brush (C 255 252 200)) 0.45 0
Draw-Hammer $g 1430 330 1.02 36
$bonk = New-TextPath 'BONK!' 92 1300 456 -10
Draw-Chunky $g $bonk (Brush $PINK) 12 7
foreach ($c in @(@(905, 420, 34, 0.9), @(1010, 300, 28, 0.6), @(1560, 575, 38, 1), @(1640, 455, 26, 0.5), @(1470, 720, 30, 0.8), @(870, 610, 24, 0.7), @(1120, 215, 22, 1), @(1600, 660, 22, 0.6), @(990, 880, 28, 0.9), @(1405, 890, 26, 0.7), @(800, 470, 20, 0.6), @(1520, 300, 24, 0.85))) {
	Draw-Coin $g $c[0] $c[1] $c[2] $c[3]
}

# Blocklings cheering
Draw-Cube $g 650 812 170 $ORANGE -7 '' $false $true
Draw-Cube $g 335 930 128 $SKY 8 '' $false $true

# Logo + ribbon
Draw-Word $g 'BONK' 215 500 165 $LETTERS 20 8 6
$tp = New-TextPath 'BLOCKS' 150 500 345 2
$b = $tp.GetBounds()
Draw-Chunky $g $tp (Grad $b.X $b.Y $b.Width $b.Height (C 255 240 150) (C 255 185 30)) 18 11
$ribbon = New-RoundRect 330 448 340 74 37
$g.FillPath((Grad 330 448 340 74 (C 150 110 255) (C 100 70 220)), $ribbon)
$g.DrawPath((New-Pen $INK 8), $ribbon)
$now = New-TextPath 'OUT NOW!' 48 500 486 0
Draw-Chunky $g $now (Brush $GOLD) 8 4

foreach ($sp in @(@(150, 80, 30), @(860, 250, 22), @(1180, 330, 26), @(1480, 170, 24), @(1850, 600, 20), @(780, 700, 18), @(1060, 980, 22))) { Draw-Sparkle $g $sp[0] $sp[1] $sp[2] }
Draw-Vignette $g $W $H 90
Save $bmp 'thumbnail.png'
$g.Dispose(); $bmp.Dispose()
