[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$CandidateRoot = ''
$validator = Join-Path $PSScriptRoot 'validate-launcher-release-policy.ps1'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($validator, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Invalid release policy source' }
# Load definitions only; never run the release receipt/promotion entry point.
foreach ($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
    Invoke-Expression $definition.Extent.Text
}
$production = @(Get-Cf7ProductionChecks)
$fixture = Join-Path $ProjectRoot ('tmp/scene-transition-policy-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$checks = 0
foreach ($name in @('required-web-runtime-assets','required-launcher-data-assets')) {
    $check = $production | Where-Object Name -eq $name
    if (@($check).Count -ne 1) { throw "Missing production resource check: $name" }
    $required = if ($name -eq 'required-web-runtime-assets') {
        @('scene-transition.html','modules\scene-transition.js','css\scene-transition.css','generated\scene-transition-catalog.js')
    } else { @('scene-transition\catalog.manifest.json') }
    $check.Root = Join-Path $fixture $name
    foreach ($relative in $check.Paths) {
        $file = Join-Path $check.Root $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
        [IO.File]::WriteAllText($file, '')
    }
    if (-not (Invoke-Cf7PolicyCheck $check).passed) { throw "Complete resource fixture rejected: $name" }
    $checks++
    foreach ($relative in $required) {
        if ($relative -cnotin $check.Paths) { throw "Production check omitted: $relative" }
        $file = Join-Path $check.Root $relative
        Move-Item -LiteralPath $file -Destination ($file + '.held')
        try {
            if ((Invoke-Cf7PolicyCheck $check).passed) { throw "Missing resource accepted: $relative" }
            $checks++
        } finally { Move-Item -LiteralPath ($file + '.held') -Destination $file }
    }
}
$fresh = $production | Where-Object Name -eq 'scene-transition-catalog-current'
if (@($fresh).Count -ne 1 -or '--check' -cnotin $fresh.Arguments) { throw 'Catalog freshness is not a read-only production gate' }
$catalog = Get-Content -LiteralPath (Join-Path $ProjectRoot 'launcher/data/scene-transition/catalog.manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$paths = @('tools/generate-scene-transition-catalog.js','launcher/web/assets/bg/manifest.json',
    'flashswf/UI/加载背景/LIBRARY/加载背景 1024&#042576.xml','scripts/类定义/org/flashNight/arki/ui/SceneTransitionService.as',
    'launcher/web/generated/scene-transition-catalog.js','launcher/src/Tasks/SceneTransitionCatalog.Generated.cs',
    'launcher/data/scene-transition/catalog.manifest.json')
foreach ($entry in $catalog.images) { $paths += @($entry.source, ('launcher/web/' + $entry.asset)) }
foreach ($relative in $paths) {
    $target = Join-Path $fixture $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ProjectRoot $relative) -Destination $target
}
$fresh.WorkingDirectory = $fixture
$fresh.Arguments = @((Join-Path $fixture 'tools/generate-scene-transition-catalog.js'), '--check')
if (-not (Invoke-Cf7PolicyCheck $fresh).passed) { throw 'Pristine catalog fixture rejected' }
$checks++
foreach ($relative in @('launcher/web/generated/scene-transition-catalog.js',
    'launcher/src/Tasks/SceneTransitionCatalog.Generated.cs','launcher/data/scene-transition/catalog.manifest.json',
    ('launcher/web/' + $catalog.images[0].asset))) {
    $file = Join-Path $fixture $relative
    [IO.File]::AppendAllText($file, 'corrupt')
    if ((Invoke-Cf7PolicyCheck $fresh).passed) { throw "Stale or altered catalog asset accepted: $relative" }
    Copy-Item -LiteralPath (Join-Path $ProjectRoot $relative) -Destination $file -Force
    $checks++
}
Write-Output "Scene transition production policy checks passed: $checks (isolated negative fixtures; no release)"
