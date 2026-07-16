param(
    [string]$Page = 'all',
    [ValidateRange(1, 8)]
    [double]$Zoom = 1,
    [string[]]$Asset = @()
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null

$projectRoot = Split-Path -Parent $PSScriptRoot
$ffdecCli = Join-Path $projectRoot 'tools\ffdec\ffdec-cli.exe'
$sourceSwf = Join-Path $projectRoot 'flashswf\UI\地图界面.swf'
$tempExportDir = Join-Path $projectRoot 'tmp_ffdec_map_composite_export'
$webpConverter = Join-Path $projectRoot 'tools\convert-map-assets-webp.py'

if (!(Test-Path -LiteralPath $ffdecCli)) {
    throw "Missing FFDec CLI: $ffdecCli"
}

if (!(Test-Path -LiteralPath $sourceSwf)) {
    throw "Missing source SWF: $sourceSwf"
}

if (!(Test-Path -LiteralPath $webpConverter)) {
    throw "Missing lossless WebP converter: $webpConverter"
}

$pages = @{
    base = @{
        OutputDir = 'launcher\web\assets\map\composite\base'
        Exports = @(
            @{ Name = 'base-roof.webp'; SpriteId = 173 }
            @{ Name = 'base-lobby.webp'; SpriteId = 122 }
            @{ Name = 'base-entrance.webp'; SpriteId = 147 }
            @{ Name = 'base-garage.webp'; SpriteId = 154 }
            @{ Name = 'merc-bar.webp'; SpriteId = 89 }
            @{ Name = 'infirmary.webp'; SpriteId = 109 }
            @{ Name = 'dormitory.webp'; SpriteId = 102 }
            @{ Name = 'basement1.webp'; SpriteId = 73 }
            @{ Name = 'gym.webp'; SpriteId = 66 }
            @{ Name = 'armory.webp'; SpriteId = 52 }
            @{ Name = 'cafeteria.webp'; SpriteId = 23 }
            @{ Name = 'corridor.webp'; SpriteId = 30 }
            @{ Name = 'lab.webp'; SpriteId = 37 }
            @{ Name = 'underground-water.webp'; SpriteId = 16 }
        )
    }
    faction = @{
        OutputDir = 'launcher\web\assets\map\composite\faction'
        Exports = @(
            @{ Name = 'warlord-base.webp'; SpriteId = 299 }
            @{ Name = 'warlord-tent.webp'; SpriteId = 314 }
            @{ Name = 'firing-range.webp'; SpriteId = 321 }
            @{ Name = 'rock-park.webp'; SpriteId = 264 }
            @{ Name = 'rock-rehearsal.webp'; SpriteId = 271 }
            @{ Name = 'blackiron-training.webp'; SpriteId = 237 }
            @{ Name = 'blackiron-pavilion.webp'; SpriteId = 245 }
            @{ Name = 'fallen-bar.webp'; SpriteId = 201 }
            @{ Name = 'fallen-street.webp'; SpriteId = 208 }
        )
    }
    defense = @{
        OutputDir = 'launcher\web\assets\map\composite\defense'
        Exports = @(
            @{ Name = 'first-defense.webp'; SpriteId = 354 }
            @{ Name = 'alliance-dock.webp'; SpriteId = 361 }
            @{ Name = 'alliance-corridor.webp'; SpriteId = 368 }
        )
    }
    school = @{
        OutputDir = 'launcher\web\assets\map\composite\school'
        Exports = @(
            @{ Name = 'workshop.webp'; SpriteId = 394 }
            @{ Name = 'union-university.webp'; SpriteId = 398 }
            @{ Name = 'university-interior.webp'; SpriteId = 405 }
            @{ Name = 'university-playground.webp'; SpriteId = 409 }
            @{ Name = 'dorm-downstairs.webp'; SpriteId = 413 }
            @{ Name = 'school-dormitory.webp'; SpriteId = 417 }
            @{ Name = 'office.webp'; SpriteId = 421 }
            @{ Name = 'kendo-club.webp'; SpriteId = 425 }
            @{ Name = 'science-class.webp'; SpriteId = 429 }
            @{ Name = 'arts-class.webp'; SpriteId = 430 }
            @{ Name = 'teaching-interior.webp'; SpriteId = 434 }
            @{ Name = 'teaching-right.webp'; SpriteId = 438 }
        )
    }
}

if ($Page -eq 'all') {
    $pageIds = @('base', 'faction', 'defense', 'school')
} elseif ($pages.ContainsKey($Page)) {
    $pageIds = @($Page)
} else {
    throw "Unsupported page '$Page'. Use one of: all, $($pages.Keys -join ', ')"
}

$requestedAssets = @{}
foreach ($assetArgument in $Asset) {
    foreach ($assetName in ($assetArgument -split ',')) {
        $normalizedName = $assetName.Trim()
        if ([string]::IsNullOrWhiteSpace($normalizedName)) {
            continue
        }
        if (![System.IO.Path]::HasExtension($normalizedName)) {
            $normalizedName += '.webp'
        }
        $requestedAssets[$normalizedName.ToLowerInvariant()] = $true
    }
}

$selectedExportsByPage = @{}
$matchedAssets = @{}
foreach ($pageId in $pageIds) {
    $selectedExports = @(
        $pages[$pageId].Exports | Where-Object {
            if ($requestedAssets.Count -eq 0) {
                return $true
            }

            $normalizedName = ([string]$_.Name).ToLowerInvariant()
            if ($requestedAssets.ContainsKey($normalizedName)) {
                $matchedAssets[$normalizedName] = $true
                return $true
            }
            return $false
        }
    )
    $selectedExportsByPage[$pageId] = $selectedExports
}

if ($requestedAssets.Count -gt 0) {
    $unmatchedAssets = @($requestedAssets.Keys | Where-Object { !$matchedAssets.ContainsKey($_) } | Sort-Object)
    if ($unmatchedAssets.Count -gt 0) {
        throw "Unknown or out-of-page asset(s): $($unmatchedAssets -join ', ')"
    }
}

$spriteIdLookup = @{}
foreach ($pageId in $pageIds) {
    foreach ($entry in $selectedExportsByPage[$pageId]) {
        $spriteIdLookup[[string]$entry.SpriteId] = $true
    }
}

if ($spriteIdLookup.Count -eq 0) {
    throw 'No composite assets selected for export.'
}

$spriteIds = @($spriteIdLookup.Keys | Sort-Object {[int]$_})
$selectIdArg = [string]::Join(',', $spriteIds)

if (Test-Path -LiteralPath $tempExportDir) {
    Remove-Item -LiteralPath $tempExportDir -Recurse -Force
}

Write-Host ("[map-composite] exporting sprite ids: {0} zoom={1}" -f $selectIdArg, $Zoom)
& $ffdecCli -zoom $Zoom -format sprite:png -selectid $selectIdArg -export sprite $tempExportDir $sourceSwf
if ($LASTEXITCODE -ne 0) {
    throw "FFDec export failed with exit code $LASTEXITCODE"
}

foreach ($pageId in $pageIds) {
    $pageConfig = $pages[$pageId]
    $outputDir = Join-Path $projectRoot $pageConfig.OutputDir
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    Write-Host ("[map-composite] page={0}" -f $pageId)
    foreach ($entry in $selectedExportsByPage[$pageId]) {
        $sourcePng = Join-Path $tempExportDir ("DefineSprite_{0}\1.png" -f $entry.SpriteId)
        if (!(Test-Path -LiteralPath $sourcePng)) {
            throw "Missing exported sprite image: $sourcePng"
        }

        $targetPath = Join-Path $outputDir $entry.Name
        & python $webpConverter --pair $sourcePng $targetPath
        if ($LASTEXITCODE -ne 0) {
            throw "Lossless WebP conversion failed with exit code $LASTEXITCODE for $sourcePng"
        }
        Write-Host ("converted {0} <- Sprite {1} (lossless WebP)" -f $entry.Name, $entry.SpriteId)
    }
}
