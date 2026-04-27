param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    [string]$OutputDir = "launcher/web/assets/cursor/native/review/vectorized-v1",
    [string]$AssetDir = "launcher/web/assets/cursor/native",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$sourceFullPath = Resolve-Path $SourcePath
$outputFullPath = Join-Path $projectRoot $OutputDir
$assetFullPath = Join-Path $projectRoot $AssetDir
New-Item -ItemType Directory -Force -Path $outputFullPath | Out-Null

$states = @(
    @{ name="normal";    kind="hand";    cell=@(17,125,359,481);   anchor=@(94,204);   scale=0.125; shift=@(0,0) },
    @{ name="click";     kind="hand";    cell=@(382,125,349,481);  anchor=@(488,229);  scale=0.130; shift=@(0,0) },
    @{ name="hoverGrab"; kind="hand";    cell=@(737,125,349,481);  anchor=@(823,219);  scale=0.118; shift=@(0,0) },
    @{ name="grab";      kind="hand";    cell=@(1093,125,349,481); anchor=@(1224,257); scale=0.130; shift=@(0,0) },
    @{ name="attack";    kind="generic"; cell=@(1448,125,350,481); anchor=@(1620,379); scale=0.140; shift=@(7,10) },
    @{ name="openDoor";  kind="generic"; cell=@(1804,125,348,481); anchor=@(1907,187); scale=0.114; shift=@(0,0) }
)

function Get-Max3([System.Drawing.Color]$c) {
    return [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
}

function Get-Min3([System.Drawing.Color]$c) {
    return [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
}

function Test-SeedPixel([System.Drawing.Color]$c) {
    $max = Get-Max3 $c
    $min = Get-Min3 $c
    $range = $max - $min
    if ($max -lt 118) { return $true }
    if ($range -gt 24 -and $max -lt 248 -and $min -lt 235) { return $true }
    return $false
}

function Test-LightNeutral([System.Drawing.Color]$c) {
    $max = Get-Max3 $c
    $min = Get-Min3 $c
    $range = $max - $min
    return ($max -ge 145 -and $max -le 246 -and $min -ge 120 -and $range -le 52)
}

function Test-GenericArtwork([System.Drawing.Color]$c) {
    $max = Get-Max3 $c
    $min = Get-Min3 $c
    $range = $max - $min
    if ($max -gt 222 -and $range -lt 18) { return $false }
    if ($range -lt 8 -and $max -gt 120) { return $false }
    if ($max -lt 118) { return $true }
    if ($range -gt 22) { return $true }
    return $false
}

function Test-WarmSkin([System.Drawing.Color]$c) {
    return ($c.R -gt 130 -and $c.G -gt 85 -and $c.B -gt 58 -and
        $c.R -gt ($c.G + 10) -and $c.G -ge ($c.B - 8))
}

function Test-BrightNeutral([System.Drawing.Color]$c) {
    $max = Get-Max3 $c
    $min = Get-Min3 $c
    return ($max -gt 132 -and ($max - $min) -lt 78)
}

function Test-CuffInterior($name, [int]$x, [int]$y) {
    switch ($name) {
        "normal"    { return ($x -ge 26 -and $x -le 43 -and $y -ge 46 -and $y -le 57) }
        "click"     { return ($x -ge 25 -and $x -le 40 -and $y -ge 46 -and $y -le 57) }
        "hoverGrab" { return ($x -ge 27 -and $x -le 42 -and $y -ge 44 -and $y -le 56) }
        "grab"      { return ($x -ge 17 -and $x -le 35 -and $y -ge 43 -and $y -le 55) }
        default     { return $false }
    }
}

function Get-PaletteColor([System.Drawing.Color]$c) {
    $max = Get-Max3 $c
    $min = Get-Min3 $c
    $range = $max - $min
    $lum = [int](0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B)

    if ($c.R -gt 125 -and $c.R -gt ($c.G + 35) -and $c.R -gt ($c.B + 35)) {
        if ($lum -gt 130) { return [System.Drawing.Color]::FromArgb(255, 232, 50, 34) }
        return [System.Drawing.Color]::FromArgb(255, 120, 18, 16)
    }

    if (Test-WarmSkin $c) {
        if ($lum -gt 185) { return [System.Drawing.Color]::FromArgb(255, 220, 190, 158) }
        if ($lum -gt 145) { return [System.Drawing.Color]::FromArgb(255, 174, 134, 103) }
        return [System.Drawing.Color]::FromArgb(255, 92, 62, 50)
    }

    if ($c.B -gt 78 -and $c.G -gt 65 -and $c.R -lt 165 -and ($c.B -ge $c.R -or $c.G -ge $c.R)) {
        if ($lum -gt 145) { return [System.Drawing.Color]::FromArgb(255, 124, 155, 165) }
        if ($lum -gt 95) { return [System.Drawing.Color]::FromArgb(255, 72, 99, 110) }
        return [System.Drawing.Color]::FromArgb(255, 31, 49, 58)
    }

    if ($max -gt 150 -and $range -lt 80) {
        if ($lum -gt 200) { return [System.Drawing.Color]::FromArgb(255, 216, 216, 205) }
        return [System.Drawing.Color]::FromArgb(255, 146, 146, 138)
    }

    if ($lum -gt 132) { return [System.Drawing.Color]::FromArgb(255, 92, 92, 88) }
    if ($lum -gt 84) { return [System.Drawing.Color]::FromArgb(255, 54, 55, 54) }
    if ($lum -gt 42) { return [System.Drawing.Color]::FromArgb(255, 31, 33, 33) }
    return [System.Drawing.Color]::FromArgb(255, 14, 16, 17)
}

function Remove-TinyComponents([System.Drawing.Bitmap]$bmp, [int]$minArea) {
    $w = $bmp.Width
    $h = $bmp.Height
    $visited = New-Object 'bool[,]' $w,$h
    $dirs = @(@(1,0),@(-1,0),@(0,1),@(0,-1),@(1,1),@(-1,-1),@(1,-1),@(-1,1))
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            if ($visited[$x,$y] -or $bmp.GetPixel($x,$y).A -eq 0) { continue }
            $queue = New-Object System.Collections.Generic.List[object]
            $pixels = New-Object System.Collections.Generic.List[object]
            $queue.Add(@($x,$y))
            $visited[$x,$y] = $true
            for ($qi = 0; $qi -lt $queue.Count; $qi++) {
                $p = $queue[$qi]
                $px = [int]$p[0]
                $py = [int]$p[1]
                $pixels.Add($p)
                foreach ($d in $dirs) {
                    $nx = $px + [int]$d[0]
                    $ny = $py + [int]$d[1]
                    if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $w -or $ny -ge $h) { continue }
                    if ($visited[$nx,$ny]) { continue }
                    $visited[$nx,$ny] = $true
                    if ($bmp.GetPixel($nx,$ny).A -gt 0) { $queue.Add(@($nx,$ny)) }
                }
            }
            if ($pixels.Count -lt $minArea) {
                foreach ($p in $pixels) {
                    $bmp.SetPixel([int]$p[0], [int]$p[1], [System.Drawing.Color]::FromArgb(0,0,0,0))
                }
            }
        }
    }
}

function Remove-SourceGuideMarks([System.Drawing.Bitmap]$bmp) {
    # The generated review sheet contains a pale hotspot cross in the upper-left
    # of each cell. It becomes very visible after posterization, so remove only
    # neutral guide-colored pixels in that source-cell area before vectorizing.
    for ($y = 24; $y -le [Math]::Min($bmp.Height - 1, 88); $y++) {
        for ($x = 20; $x -le [Math]::Min($bmp.Width - 1, 86); $x++) {
            $c = $bmp.GetPixel($x,$y)
            if ($c.A -eq 0) { continue }
            $max = Get-Max3 $c
            $min = Get-Min3 $c
            $range = $max - $min
            if ($range -lt 24 -and -not (Test-WarmSkin $c)) {
                $bmp.SetPixel($x,$y,[System.Drawing.Color]::FromArgb(0,0,0,0))
            }
        }
    }
}

function Extract-HandMask($source, $spec) {
    $cell = $spec.cell
    $w = $cell[2]
    $h = $cell[3]
    $seed = New-Object 'bool[,]' $w,$h
    $mask = New-Object 'bool[,]' $w,$h
    $bmp = New-Object System.Drawing.Bitmap $w,$h,([System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)

    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $c = $source.GetPixel($cell[0] + $x, $cell[1] + $y)
            if (Test-SeedPixel $c) {
                $seed[$x,$y] = $true
                $mask[$x,$y] = $true
            }
        }
    }

    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            if ($mask[$x,$y]) { continue }
            $c = $source.GetPixel($cell[0] + $x, $cell[1] + $y)
            if (-not (Test-LightNeutral $c)) { continue }
            $isWristZone = ($y -gt 215 -and $x -gt 90)
            if (-not $isWristZone) { continue }
            $neighbors = 0
            for ($yy = [Math]::Max(0, $y - 4); $yy -le [Math]::Min($h - 1, $y + 4); $yy++) {
                for ($xx = [Math]::Max(0, $x - 4); $xx -le [Math]::Min($w - 1, $x + 4); $xx++) {
                    if ($seed[$xx,$yy]) { $neighbors++ }
                }
            }
            if ($neighbors -ge 5) { $mask[$x,$y] = $true }
        }
    }

    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            if ($mask[$x,$y]) {
                $c = $source.GetPixel($cell[0] + $x, $cell[1] + $y)
                $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $c.R, $c.G, $c.B))
            }
        }
    }
    Remove-SourceGuideMarks $bmp
    Remove-TinyComponents $bmp 16
    return $bmp
}

function Extract-GenericMask($source, $spec) {
    $cell = $spec.cell
    $bmp = New-Object System.Drawing.Bitmap $cell[2],$cell[3],([System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    for ($y = 0; $y -lt $cell[3]; $y++) {
        for ($x = 0; $x -lt $cell[2]; $x++) {
            $c = $source.GetPixel($cell[0] + $x, $cell[1] + $y)
            if (Test-GenericArtwork $c) {
                $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $c.R, $c.G, $c.B))
            }
        }
    }
    Remove-SourceGuideMarks $bmp
    Remove-TinyComponents $bmp 10
    return $bmp
}

function Vectorize-HighRes($bmp) {
    $out = New-Object System.Drawing.Bitmap $bmp.Width,$bmp.Height,([System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            $c = $bmp.GetPixel($x,$y)
            if ($c.A -gt 0) { $out.SetPixel($x,$y,(Get-PaletteColor $c)) }
        }
    }
    return $out
}

function Render-State($mask, $spec) {
    $cell = $spec.cell
    $anchorX = $spec.anchor[0] - $cell[0]
    $anchorY = $spec.anchor[1] - $cell[1]
    $scale = [double]$spec.scale
    $dx = [Math]::Round(16 - ($anchorX * $scale)) + [int]$spec.shift[0]
    $dy = [Math]::Round(16 - ($anchorY * $scale)) + [int]$spec.shift[1]
    $dw = [Math]::Round($mask.Width * $scale)
    $dh = [Math]::Round($mask.Height * $scale)
    $dst = New-Object System.Drawing.Bitmap 64,64,([System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.Clear([System.Drawing.Color]::FromArgb(0,0,0,0))
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($mask, [System.Drawing.Rectangle]::new([int]$dx,[int]$dy,[int]$dw,[int]$dh), 0,0,$mask.Width,$mask.Height,[System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    if ($dst.GetPixel(16,16).A -lt 16) {
        $dst.SetPixel(16,16,[System.Drawing.Color]::FromArgb(80,20,20,20))
    }
    return $dst
}

function Add-Outline($bmp) {
    $out = $bmp.Clone()
    $outline = [System.Drawing.Color]::FromArgb(220, 10, 12, 13)
    for ($y = 0; $y -lt 64; $y++) {
        for ($x = 0; $x -lt 64; $x++) {
            $c = $bmp.GetPixel($x,$y)
            if ($c.A -eq 0) { continue }
            $near = $false
            for ($yy = [Math]::Max(0,$y-1); $yy -le [Math]::Min(63,$y+1); $yy++) {
                for ($xx = [Math]::Max(0,$x-1); $xx -le [Math]::Min(63,$x+1); $xx++) {
                    if ($bmp.GetPixel($xx,$yy).A -eq 0) { $near = $true }
                }
            }
            if ($near -and -not (Test-WarmSkin $c)) {
                $out.SetPixel($x,$y,$outline)
            } elseif ($near -and (Test-WarmSkin $c)) {
                $out.SetPixel($x,$y,[System.Drawing.Color]::FromArgb($c.A, 80, 58, 48))
            }
        }
    }
    return $out
}

function Has-TransparentNeighbor($img, [int]$x, [int]$y, [int]$r) {
    for ($yy = [Math]::Max(0,$y-$r); $yy -le [Math]::Min(63,$y+$r); $yy++) {
        for ($xx = [Math]::Max(0,$x-$r); $xx -le [Math]::Min(63,$x+$r); $xx++) {
            if ($img.GetPixel($xx,$yy).A -eq 0) { return $true }
        }
    }
    return $false
}

function Clean-Halo($name, $src) {
    $dst = $src.Clone()
    for ($y = 0; $y -lt 64; $y++) {
        for ($x = 0; $x -lt 64; $x++) {
            $c = $src.GetPixel($x,$y)
            if ($c.A -eq 0) { continue }
            if (Test-WarmSkin $c) { continue }
            if (-not (Test-BrightNeutral $c)) { continue }
            $edge1 = Has-TransparentNeighbor $src $x $y 1
            $edge2 = Has-TransparentNeighbor $src $x $y 2
            $interior = Test-CuffInterior $name $x $y
            if ($edge1) {
                if ($interior) {
                    $dst.SetPixel($x,$y,[System.Drawing.Color]::FromArgb([Math]::Min($c.A,170),[Math]::Min($c.R,150),[Math]::Min($c.G,150),[Math]::Min($c.B,150)))
                } else {
                    $dst.SetPixel($x,$y,[System.Drawing.Color]::FromArgb(0,0,0,0))
                }
            } elseif ($edge2 -and -not $interior) {
                $dst.SetPixel($x,$y,[System.Drawing.Color]::FromArgb($c.A,[Math]::Min($c.R,42),[Math]::Min($c.G,46),[Math]::Min($c.B,52)))
            }
        }
    }
    return $dst
}

function Image-Stats($img) {
    $minX=64; $minY=64; $maxX=-1; $maxY=-1; $visible=0
    for ($y = 0; $y -lt 64; $y++) {
        for ($x = 0; $x -lt 64; $x++) {
            if ($img.GetPixel($x,$y).A -gt 0) {
                if ($x -lt $minX) { $minX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -gt $maxY) { $maxY = $y }
                $visible++
            }
        }
    }
    return [pscustomobject]@{
        bounds = "$minX,$minY,$maxX,$maxY"
        visible = $visible
        hotspot = $img.GetPixel(16,16).A
    }
}

function Save-ContactSheet($names, $dir, $fileName) {
    $scale = 4
    $cell = 64 * $scale
    $sheet = New-Object System.Drawing.Bitmap ($names.Count * ($cell + 24) + 24),($cell * 2 + 72),([System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $g = [System.Drawing.Graphics]::FromImage($sheet)
    $g.Clear([System.Drawing.Color]::FromArgb(255,32,32,32))
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255,90,90,90)),1
    for ($i = 0; $i -lt $names.Count; $i++) {
        $img = [System.Drawing.Bitmap]::FromFile((Join-Path $dir ($names[$i] + ".png")))
        foreach ($row in @(0,1)) {
            $x = 24 + $i * ($cell + 24)
            $y = 24 + $row * ($cell + 24)
            if ($row -eq 0) { $g.FillRectangle([System.Drawing.Brushes]::Black,$x,$y,$cell,$cell) }
            else { $g.FillRectangle([System.Drawing.Brushes]::White,$x,$y,$cell,$cell) }
            $g.DrawImage($img,[System.Drawing.Rectangle]::new($x,$y,$cell,$cell),0,0,64,64,[System.Drawing.GraphicsUnit]::Pixel)
            $g.DrawRectangle($pen,$x,$y,$cell,$cell)
        }
        $img.Dispose()
    }
    $pen.Dispose()
    $g.Dispose()
    $sheet.Save((Join-Path $dir $fileName), [System.Drawing.Imaging.ImageFormat]::Png)
    $sheet.Dispose()
}

$source = [System.Drawing.Bitmap]::FromFile($sourceFullPath)
$stats = @()
foreach ($spec in $states) {
    $mask = if ($spec.kind -eq "hand") { Extract-HandMask $source $spec } else { Extract-GenericMask $source $spec }
    $vector = Vectorize-HighRes $mask
    $mask.Dispose()
    $rendered = Render-State $vector $spec
    $vector.Dispose()
    $outlined = Add-Outline $rendered
    $rendered.Dispose()
    $clean = Clean-Halo $spec.name $outlined
    $outlined.Dispose()
    $outPath = Join-Path $outputFullPath ($spec.name + ".png")
    $clean.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $st = Image-Stats $clean
    $stats += [pscustomobject]@{ state=$spec.name; bounds=$st.bounds; visible=$st.visible; hotspot=$st.hotspot }
    $clean.Dispose()
}
$source.Dispose()

Save-ContactSheet @("normal","click","hoverGrab","grab","attack","openDoor") $outputFullPath "edge-audit-vectorized.png"

if ($Apply) {
    foreach ($spec in $states) {
        Copy-Item -LiteralPath (Join-Path $outputFullPath ($spec.name + ".png")) -Destination (Join-Path $assetFullPath ($spec.name + ".png")) -Force
    }
}

$stats | Format-Table -AutoSize
