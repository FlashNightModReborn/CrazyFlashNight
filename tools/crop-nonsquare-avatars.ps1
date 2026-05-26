# Bake 非方形头像 PNG → 标准 44x44 方形 PNG.
#
# 算法: 扫 PNG alpha bbox → 取较长边作正方形 + 8% padding → 居中裁 → resize 到 44x44.
# 透明 padding (Flash 导出 MovieClip wrapper 时常多带) 全部去掉, 内容居中入圆.
#
# 比"按 source-data crop.tx/ty 反推"更稳: 不依赖 Flash metadata 语义假设, 直接
# 让 PNG 自己的边界信息说话. 适用前提: PNG 周围必须是干净透明 (alpha < 16).
#
# 用法:
#   inline via PowerShell tool (auto-mode 禁外调 ps1):
#     foreach 段直接复制到 PowerShell 工具, 或参考 git history 中的 inline 调用.
#   或本地直接跑:
#     powershell -File ./tools/crop-nonsquare-avatars.ps1            # dry-run -> tmp_avatar_crop/
#     powershell -File ./tools/crop-nonsquare-avatars.ps1 -Apply     # 覆盖原 PNG + .bak 备份
#
# 维护: 增删裁剪目标改 $files 数组即可. source-data 里把 assetSize 改 44x44,
# crop 全归零 (scaleX=1 scaleY=1 tx=0 ty=0), 即可消除"web 端拉伸变形"历史遗留.

[CmdletBinding()]
param(
    [string[]]$Files = @('PROPHET头像.png', '阿波头像.png'),
    [int]$AlphaThreshold = 16,
    [double]$PadPct = 0.08,
    [int]$OutSize = 44,
    [switch]$Apply
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$avatarsDir = Join-Path $repoRoot 'launcher/web/assets/map/avatars'
$tmpDir = Join-Path $repoRoot 'tmp_avatar_crop'
if (-not $Apply -and -not (Test-Path $tmpDir)) {
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
}

function Get-AlphaBBox($bmp, $threshold) {
    $w = $bmp.Width; $h = $bmp.Height
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $data.Stride
    $bytes = New-Object byte[] ($stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $stride * $h)
    $bmp.UnlockBits($data)
    $minX = $w; $minY = $h; $maxX = -1; $maxY = -1
    for ($y = 0; $y -lt $h; $y++) {
        $row = $y * $stride
        for ($x = 0; $x -lt $w; $x++) {
            $a = $bytes[$row + $x * 4 + 3]
            if ($a -gt $threshold) {
                if ($x -lt $minX) { $minX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    return @{ MinX=$minX; MinY=$minY; MaxX=$maxX; MaxY=$maxY; W=($maxX-$minX+1); H=($maxY-$minY+1) }
}

foreach ($f in $Files) {
    $srcPath = Join-Path $avatarsDir $f
    if (-not (Test-Path $srcPath)) { Write-Warning "missing: $srcPath"; continue }

    $src = [System.Drawing.Image]::FromFile($srcPath)
    try {
        $srcBmp = New-Object System.Drawing.Bitmap $src
        try {
            $bbox = Get-AlphaBBox $srcBmp $AlphaThreshold
            Write-Host "[$f] PNG=$($src.Width)x$($src.Height) bbox=($($bbox.MinX),$($bbox.MinY))-($($bbox.MaxX),$($bbox.MaxY)) size=$($bbox.W)x$($bbox.H)"
            $cx = ($bbox.MinX + $bbox.MaxX) / 2.0
            $cy = ($bbox.MinY + $bbox.MaxY) / 2.0
            $s = [Math]::Max($bbox.W, $bbox.H) * (1.0 + $PadPct)
            $sx = $cx - $s / 2.0
            $sy = $cy - $s / 2.0

            $bmp = New-Object System.Drawing.Bitmap $OutSize, $OutSize, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.Clear([System.Drawing.Color]::Transparent)
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $destRect = New-Object System.Drawing.RectangleF 0.0, 0.0, ([single]$OutSize), ([single]$OutSize)
                $srcRect = New-Object System.Drawing.RectangleF ([single]$sx), ([single]$sy), ([single]$s), ([single]$s)
                $g.DrawImage($srcBmp, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
            } finally {
                $g.Dispose()
            }

            if ($Apply) {
                $bakPath = $srcPath + '.bak'
                if (-not (Test-Path $bakPath)) {
                    Copy-Item -Path $srcPath -Destination $bakPath
                    Write-Host "  backup -> $bakPath"
                }
                $tmpOut = [System.IO.Path]::GetTempFileName()
                $bmp.Save($tmpOut, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()
                $srcBmp.Dispose()
                $src.Dispose()
                Move-Item -Path $tmpOut -Destination $srcPath -Force
                Write-Host "  applied -> $srcPath"
                continue
            } else {
                $outPath = Join-Path $tmpDir $f
                $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
                Write-Host "  preview -> $outPath"
            }
            $bmp.Dispose()
        } finally {
            $srcBmp.Dispose()
        }
    } finally {
        $src.Dispose()
    }
}

if (-not $Apply) {
    Write-Host ''
    Write-Host "Dry-run preview at: $tmpDir"
}
