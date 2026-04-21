param(
    [string]$Page = 'all'
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null

$projectRoot = Split-Path -Parent $PSScriptRoot
$ffdecCli = Join-Path $projectRoot 'tools\ffdec\ffdec-cli.exe'
$sourceSwf = Join-Path $projectRoot 'flashswf\UI\地图界面.swf'
$tempExportDir = Join-Path $projectRoot 'tmp_ffdec_map_composite_export'

if (!(Test-Path -LiteralPath $ffdecCli)) {
    throw "Missing FFDec CLI: $ffdecCli"
}

if (!(Test-Path -LiteralPath $sourceSwf)) {
    throw "Missing source SWF: $sourceSwf"
}

$pages = @{
    base = @{
        OutputDir = 'launcher\web\assets\map\composite\base'
        Exports = @(
            @{ Name = 'base-roof.png'; SpriteId = 173 }
            @{ Name = 'base-lobby.png'; SpriteId = 122 }
            @{ Name = 'base-entrance.png'; SpriteId = 147 }
            @{ Name = 'base-garage.png'; SpriteId = 154 }
            @{ Name = 'merc-bar.png'; SpriteId = 89 }
            @{ Name = 'infirmary.png'; SpriteId = 109 }
            @{ Name = 'dormitory.png'; SpriteId = 102 }
            @{ Name = 'basement1.png'; SpriteId = 73 }
            @{ Name = 'gym.png'; SpriteId = 66 }
            @{ Name = 'armory.png'; SpriteId = 52 }
            @{ Name = 'cafeteria.png'; SpriteId = 23 }
            @{ Name = 'corridor.png'; SpriteId = 30 }
            @{ Name = 'lab.png'; SpriteId = 37 }
            @{ Name = 'underground-water.png'; SpriteId = 16 }
        )
    }
    faction = @{
        OutputDir = 'launcher\web\assets\map\composite\faction'
        Exports = @(
            @{ Name = 'warlord-base.png'; SpriteId = 299 }
            @{ Name = 'warlord-tent.png'; SpriteId = 314 }
            @{ Name = 'firing-range.png'; SpriteId = 321 }
            @{ Name = 'rock-park.png'; SpriteId = 264 }
            @{ Name = 'rock-rehearsal.png'; SpriteId = 271 }
            @{ Name = 'blackiron-training.png'; SpriteId = 237 }
            @{ Name = 'blackiron-pavilion.png'; SpriteId = 245 }
            @{ Name = 'fallen-bar.png'; SpriteId = 201 }
            @{ Name = 'fallen-street.png'; SpriteId = 208 }
        )
    }
    defense = @{
        OutputDir = 'launcher\web\assets\map\composite\defense'
        Exports = @(
            @{ Name = 'first-defense.png'; SpriteId = 354 }
            @{ Name = 'alliance-dock.png'; SpriteId = 361 }
            @{ Name = 'alliance-corridor.png'; SpriteId = 368 }
        )
    }
    school = @{
        OutputDir = 'launcher\web\assets\map\composite\school'
        Exports = @(
            @{ Name = 'workshop.png'; SpriteId = 394 }
            @{ Name = 'union-university.png'; SpriteId = 398 }
            @{ Name = 'university-interior.png'; SpriteId = 405 }
            @{ Name = 'university-playground.png'; SpriteId = 409 }
            @{ Name = 'dorm-downstairs.png'; SpriteId = 413 }
            @{ Name = 'school-dormitory.png'; SpriteId = 417 }
            @{ Name = 'office.png'; SpriteId = 421 }
            @{ Name = 'kendo-club.png'; SpriteId = 425 }
            @{ Name = 'science-class.png'; SpriteId = 429 }
            @{ Name = 'arts-class.png'; SpriteId = 430 }
            @{ Name = 'teaching-interior.png'; SpriteId = 434 }
            @{ Name = 'teaching-right.png'; SpriteId = 438 }
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

$spriteIdLookup = @{}
foreach ($pageId in $pageIds) {
    foreach ($entry in $pages[$pageId].Exports) {
        $spriteIdLookup[[string]$entry.SpriteId] = $true
    }
}

$spriteIds = @($spriteIdLookup.Keys | Sort-Object {[int]$_})
$selectIdArg = [string]::Join(',', $spriteIds)

if (Test-Path -LiteralPath $tempExportDir) {
    Remove-Item -LiteralPath $tempExportDir -Recurse -Force
}

Write-Host ("[map-composite] exporting sprite ids: {0}" -f $selectIdArg)
& $ffdecCli -format sprite:png -selectid $selectIdArg -export sprite $tempExportDir $sourceSwf
if ($LASTEXITCODE -ne 0) {
    throw "FFDec export failed with exit code $LASTEXITCODE"
}

foreach ($pageId in $pageIds) {
    $pageConfig = $pages[$pageId]
    $outputDir = Join-Path $projectRoot $pageConfig.OutputDir
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    Write-Host ("[map-composite] page={0}" -f $pageId)
    foreach ($entry in $pageConfig.Exports) {
        $sourcePng = Join-Path $tempExportDir ("DefineSprite_{0}\1.png" -f $entry.SpriteId)
        if (!(Test-Path -LiteralPath $sourcePng)) {
            throw "Missing exported sprite image: $sourcePng"
        }

        $targetPath = Join-Path $outputDir $entry.Name
        Copy-Item -LiteralPath $sourcePng -Destination $targetPath -Force
        Write-Host ("copied {0} <- Sprite {1}" -f $entry.Name, $entry.SpriteId)
    }
}
