# Prepare deterministic, tracked Launcher release assets before a runtime producer is
# allowed to build.  This script intentionally owns generators only; product policy
# audits belong to validate-launcher-release-policy.ps1.

[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$ReleaseTreeOid = 'HEAD',
    [string]$SaveSchemaSource
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')

function Invoke-Cf7PrepareCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory=$true)][string]$WorkingDirectory
    )

    if (-not (Get-Command $FilePath -ErrorAction SilentlyContinue)) {
        throw "Prepare step '$Name' cannot find executable: $FilePath"
    }

    Write-Host "[Prepare] $Name" -ForegroundColor Yellow
    Push-Location $WorkingDirectory
    try {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $FilePath @Arguments
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
    } finally {
        Pop-Location
    }
    if ($exitCode -ne 0) {
        throw "Prepare step '$Name' failed with exit code $exitCode."
    }
}

function Resolve-Cf7ReleaseTree {
    param([string]$Revision)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $resolved = @(& git -C $ProjectRoot rev-parse --verify "$Revision`^{tree}" 2>&1)
        $gitExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($gitExit -ne 0 -or $resolved.Count -ne 1 -or $resolved[0] -notmatch '^[0-9a-f]{40,64}$') {
        throw "Cannot resolve release tree '$Revision': $($resolved -join ' ')"
    }
    return ([string]$resolved[0]).Trim().ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) {
    # Worktrees use a .git file, so Test-Path without PathType is intentional.
    throw "ProjectRoot is not a Git worktree: $ProjectRoot"
}

$releaseTree = Resolve-Cf7ReleaseTree -Revision $ReleaseTreeOid
$node = (Get-Command node.exe -ErrorAction SilentlyContinue)
if (-not $node) { $node = Get-Command node -ErrorAction SilentlyContinue }
if (-not $node) { throw 'Node.js is required to prepare Launcher release assets.' }
$nodePath = $node.Source

$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
if (-not $npm) { throw 'npm is required to prepare Launcher release assets.' }
$npmPath = $npm.Source

$npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
if (-not $npx) { $npx = Get-Command npx -ErrorAction SilentlyContinue }
if (-not $npx) { throw 'npx is required to compile Launcher TypeScript assets.' }
$npxPath = $npx.Source

$tsDir = Join-Path $ProjectRoot 'launcher\scripts'
if (-not (Test-Path -LiteralPath (Join-Path $tsDir 'tsconfig.json') -PathType Leaf)) {
    throw "TypeScript project missing: $tsDir\tsconfig.json"
}
Invoke-Cf7PrepareCommand -Name 'restore locked TypeScript build dependencies' -FilePath $npmPath `
    -Arguments @('ci', '--ignore-scripts') -WorkingDirectory $tsDir
Invoke-Cf7PrepareCommand -Name 'compile Launcher V8 TypeScript bundle' -FilePath $npxPath `
    -Arguments @('tsc', '--project', 'tsconfig.json') -WorkingDirectory $tsDir

$nodeSteps = @(
    @{ Name = 'derive task NPC registry'; Script = 'tools\derive-task-npc-registry.js' },
    @{ Name = 'derive map catalog'; Script = 'tools\derive-map-catalog.js' },
    @{ Name = 'derive native HUD map data'; Script = 'tools\export-maphud-data.js' },
    @{ Name = 'derive task catalog'; Script = 'tools\derive-task-catalog.js' },
    @{ Name = 'derive achievement catalog'; Script = 'tools\derive-achievement-catalog.js' },
    @{ Name = 'derive arena meta teams'; Script = 'tools\derive-arena-meta-teams.js' },
    @{ Name = 'derive arena faction metadata'; Script = 'tools\derive-arena-factions.js' },
    @{ Name = 'derive arena unit catalog'; Script = 'tools\derive-arena-unit-catalog.js' },
    @{ Name = 'derive arena unit parameter presets'; Script = 'tools\derive-arena-unit-param-presets.js' },
    @{ Name = 'derive arena custom presets'; Script = 'tools\derive-arena-custom-presets.js' }
)
foreach ($step in $nodeSteps) {
    $scriptPath = Join-Path $ProjectRoot $step.Script
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Prepare generator missing: $($step.Script)"
    }
    Invoke-Cf7PrepareCommand -Name $step.Name -FilePath $nodePath -Arguments @($scriptPath) `
        -WorkingDirectory $ProjectRoot
}

$fontCtl = Join-Path $ProjectRoot 'tools\fontctl\cli.js'
if (-not (Test-Path -LiteralPath $fontCtl -PathType Leaf)) {
    throw "Font catalog generator missing: $fontCtl"
}
Invoke-Cf7PrepareCommand -Name 'derive Gate E font runtime projections' -FilePath $nodePath `
    -Arguments @($fontCtl, 'generate', '--json') -WorkingDirectory $ProjectRoot

$repairDictDir = Join-Path $ProjectRoot 'tools\cf7-save-repair-dict-build'
if (-not (Test-Path -LiteralPath (Join-Path $repairDictDir 'package.json') -PathType Leaf)) {
    throw "Save repair dictionary generator missing: $repairDictDir"
}
Invoke-Cf7PrepareCommand -Name 'restore locked save repair dictionary dependencies' -FilePath $npmPath `
    -Arguments @('ci', '--ignore-scripts') -WorkingDirectory $repairDictDir
Invoke-Cf7PrepareCommand -Name 'derive save repair dictionary' -FilePath $npmPath `
    -Arguments @('run', 'build', '--silent') -WorkingDirectory $repairDictDir

# save_schema.json is currently derived from a developer-selected healthy save and its
# generator embeds generatedAt.  Never silently bind a release to whichever private save
# happens to exist on a builder.  An explicit source keeps this exceptional/manual input
# visible until the project gains a deterministic, tracked canonical source.
if (-not [string]::IsNullOrWhiteSpace($SaveSchemaSource)) {
    $saveSchemaSourcePath = [IO.Path]::GetFullPath($SaveSchemaSource)
    if (-not (Test-Path -LiteralPath $saveSchemaSourcePath -PathType Leaf)) {
        throw "Explicit save schema source missing: $saveSchemaSourcePath"
    }
    $extractSaveSchema = Join-Path $ProjectRoot 'tools\extract-save-schema.js'
    if (-not (Test-Path -LiteralPath $extractSaveSchema -PathType Leaf)) {
        throw "Save schema generator missing: $extractSaveSchema"
    }
    Invoke-Cf7PrepareCommand -Name 'derive save schema from explicit canonical source' `
        -FilePath $nodePath -Arguments @($extractSaveSchema, '--source', $saveSchemaSourcePath) `
        -WorkingDirectory $ProjectRoot
} else {
    Write-Host '[Prepare] save schema: preserved (pass -SaveSchemaSource to regenerate explicitly).' -ForegroundColor DarkYellow
}

$generatedOutputs = @(
    'launcher/scripts/dist/hit-number-bundle.js',
    'data/map/task_npc_registry.json',
    'data/map/map_catalog.json',
    'launcher/data/map_hud_data.json',
    'launcher/web/modules/tasks/task-catalog.json',
    'launcher/web/modules/tasks/achievement-catalog.json',
    'data/arena/arena_calibrated_rosters.json',
    'data/arena/meta_teams.json',
    'launcher/web/modules/arena-meta-rosters.js',
    'launcher/web/modules/arena-factions.js',
    'launcher/web/modules/arena-unit-catalog.js',
    'launcher/web/modules/arena-unit-param-presets.js',
    'launcher/web/modules/arena-custom-presets.js',
    'launcher/data/save_repair_dict.json',
    'launcher/data/save_schema.json',
    'launcher/web/generated/font-catalog.json',
    'launcher/web/generated/font-catalog.css',
    'launcher/web/generated/font-catalog.js',
    'launcher/web/assets/fonts/font-pack-manifest.json'
)

$stale = @()
foreach ($relativePath in $generatedOutputs) {
    $treeProbe = @(& git -C $ProjectRoot ls-tree -r --name-only $releaseTree -- $relativePath)
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect release tree path: $relativePath" }
    if (-not (@($treeProbe | Where-Object { ([string]$_).Replace('\', '/') -eq $relativePath }).Count -gt 0)) {
        $stale += "$relativePath (not tracked by release tree)"
        continue
    }
    $fullPath = Join-Path $ProjectRoot ($relativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $stale += "$relativePath (missing after prepare)"
        continue
    }
    & git -C $ProjectRoot diff --quiet --no-ext-diff $releaseTree -- $relativePath
    if ($LASTEXITCODE -eq 1) {
        $stale += "$relativePath (generated bytes differ from release tree)"
    } elseif ($LASTEXITCODE -ne 0) {
        throw "Cannot compare generated output with release tree: $relativePath"
    }
}

if ($stale.Count -gt 0) {
    Write-Host '[Prepare] FAIL: generated release assets are stale or absent from the target tree:' -ForegroundColor Red
    foreach ($item in $stale) { Write-Host "  - $item" -ForegroundColor Red }
    Write-Host 'Commit the generated outputs, then prepare the resulting immutable release tree again.' -ForegroundColor Yellow
    exit 1
}

Write-Host "[Prepare] OK: $($generatedOutputs.Count) tracked outputs match releaseTreeOid=$releaseTree" -ForegroundColor Green
