# Focused release-policy wiring and read-only stale-output regression for the
# generated legacy material dictionary.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $projectRoot 'tools\validate-launcher-release-policy.ps1'
$producerRelativePath = 'tools\derive-material-catalog.py'
$infrastructureRelativePath = 'data\infrastructure\infrastructure.xml'
$pythonCommand = Get-Command python.exe, python3.exe, python -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $pythonCommand) { throw 'Python executable is required for the material catalog release-policy test.' }
$python = $pythonCommand.Source
$equipmentTuningMatches = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'scripts') `
    -Recurse -File -Filter 'EquipmentTuningService.as')
if ($equipmentTuningMatches.Count -ne 1) {
    throw "Expected exactly one EquipmentTuningService.as, found $($equipmentTuningMatches.Count)."
}
$equipmentTuningRelativePath = $equipmentTuningMatches[0].FullName.Substring($projectRoot.Length).TrimStart('\')
$infrastructureUiMatches = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'flashswf\UI') `
    -Recurse -File -Filter '*.xml' | Where-Object {
        $source = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
        $source.Contains('_root.getRequirementFromTask(this.') -and
            $source.Contains('_root.itemSubmit(itemArr)')
    })
if ($infrastructureUiMatches.Count -ne 1) {
    throw "Expected exactly one InfrastructureUpgradeUI evidence file, found $($infrastructureUiMatches.Count)."
}
$infrastructureUiRelativePath = $infrastructureUiMatches[0].FullName.Substring($projectRoot.Length).TrimStart('\')
$testBase = [IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp\material-catalog-release-policy-tests')).TrimEnd('\')
$fixtureRoot = Join-Path $testBase ([Guid]::NewGuid().ToString('N'))
$checks = 0

function Assert-Cf7MaterialPolicy {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    $script:checks++
}

function Copy-Cf7MaterialPolicyFile {
    param([string]$RelativePath)
    $source = Join-Path $projectRoot $RelativePath
    $target = Join-Path $fixtureRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Fixture source is missing: $RelativePath"
    }
    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
}

function Copy-Cf7MaterialPolicyTree {
    param([string]$RelativePath)
    $source = Join-Path $projectRoot $RelativePath
    $target = Join-Path $fixtureRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Fixture source directory is missing: $RelativePath"
    }
    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
}

function Invoke-Cf7MaterialProducerCheck {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $python '-X' 'utf8' (Join-Path $fixtureRoot $producerRelativePath) '--check' 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
    throw "Release policy validator is missing: $validatorPath"
}
$validatorSource = [IO.File]::ReadAllText($validatorPath, [Text.Encoding]::UTF8)
Assert-Cf7MaterialPolicy ($validatorSource.Contains("`$python = Resolve-Cf7Executable -Names @('python.exe', 'python3.exe', 'python')")) `
    'production policy must resolve a Python host for data closure checks'
Assert-Cf7MaterialPolicy ($validatorSource.Contains("New-Cf7CommandCheck -Name 'material-catalog-current'")) `
    'production policy must register the named material catalog check'
Assert-Cf7MaterialPolicy ($validatorSource.Contains("'tools\derive-material-catalog.py'), '--check'")) `
    'production policy must invoke the producer in read-only --check mode'
Assert-Cf7MaterialPolicy (-not $validatorSource.Contains("'tools\derive-material-catalog.py'), 'derive'")) `
    'production policy must never invoke the material producer write mode'
Assert-Cf7MaterialPolicy ($validatorSource.Contains("New-Cf7CommandCheck -Name 'material-enemy-portrait-coverage'")) `
    'production policy must gate the dynamic material enemy portrait exact set'
Assert-Cf7MaterialPolicy ($validatorSource.Contains("'tools\test-material-enemy-portrait-coverage.py'")) `
    'production policy must invoke the material enemy portrait coverage gate'
Assert-Cf7MaterialPolicy ($validatorSource.Contains("New-Cf7CommandCheck -Name 'shop-portrait-assets'")) `
    'production policy must gate the active shop portrait asset closure'
Assert-Cf7MaterialPolicy ($validatorSource.Contains("'modules\shop-portrait-resolver.js', 'assets\shop-portraits\manifest.json'")) `
    'production web payload must contain the shop resolver and its exact manifest'
Assert-Cf7MaterialPolicy ($validatorSource.Contains("New-Cf7CommandCheck -Name 'enemy-portrait-resolver-runtime'") -and
    $validatorSource.Contains("'tools\test-portrait-resolver-runtime.js'")) `
    'production policy must keep the shared enemy portrait resolver runtime gate'
Assert-Cf7MaterialPolicy ($validatorSource.Contains("New-Cf7CommandCheck -Name 'shop-portrait-resolver-runtime'") -and
    $validatorSource.Contains("'tools\test-shop-portrait-resolver-runtime.js'")) `
    'production policy must execute the shop portrait resolver runtime gate'
Assert-Cf7MaterialPolicy ($validatorSource.Contains("New-Cf7CommandCheck -Name 'workbench-lazy-portrait-closure'") -and
    $validatorSource.Contains("'tools\test-inventory-workbench-lazy-closure.js'")) `
    'production policy must execute the exact crafting portrait lazy closure gate'

$resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
Assert-Cf7MaterialPolicy ($resolvedFixture.StartsWith($testBase + '\', [StringComparison]::OrdinalIgnoreCase)) `
    'fixture root must stay below the dedicated temporary test root'
New-Item -ItemType Directory -Path $resolvedFixture -Force | Out-Null
try {
    Copy-Cf7MaterialPolicyFile $producerRelativePath
    Copy-Cf7MaterialPolicyTree 'data\items'
    Copy-Cf7MaterialPolicyTree 'data\crafting'
    Copy-Cf7MaterialPolicyFile 'data\dictionaries\material_catalog.xml'
    Copy-Cf7MaterialPolicyFile 'data\dictionaries\material_dictionary.xml'
    Copy-Cf7MaterialPolicyFile 'data\dictionaries\material_dictionary.generated.json'
    Copy-Cf7MaterialPolicyFile 'data\equipment\equipment_config.xml'
    Copy-Cf7MaterialPolicyFile $equipmentTuningRelativePath
    Copy-Cf7MaterialPolicyFile $infrastructureRelativePath
    Copy-Cf7MaterialPolicyFile $infrastructureUiRelativePath

    $dictionaryPath = Join-Path $fixtureRoot 'data\dictionaries\material_dictionary.xml'
    $sidecarPath = Join-Path $fixtureRoot 'data\dictionaries\material_dictionary.generated.json'
    $dictionaryBytesBefore = [IO.File]::ReadAllBytes($dictionaryPath)
    $dictionaryHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $dictionaryPath).Hash
    $sidecarBytesBefore = [IO.File]::ReadAllBytes($sidecarPath)
    $sidecarHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $sidecarPath).Hash
    $dictionaryWriteBefore = (Get-Item -LiteralPath $dictionaryPath).LastWriteTimeUtc.Ticks
    $sidecarWriteBefore = (Get-Item -LiteralPath $sidecarPath).LastWriteTimeUtc.Ticks

    $passRun = Invoke-Cf7MaterialProducerCheck
    Assert-Cf7MaterialPolicy ($passRun.ExitCode -eq 0) `
        "current generated closure must pass; output=$($passRun.Output)"
    Assert-Cf7MaterialPolicy ($passRun.Output -match '\[material-catalog\] check PASS materials=224 legacy=58') `
        'passing check must report the current material/legacy closure'
    Assert-Cf7MaterialPolicy ((Get-FileHash -Algorithm SHA256 -LiteralPath $dictionaryPath).Hash -eq $dictionaryHashBefore) `
        'passing --check must not rewrite the legacy dictionary'
    Assert-Cf7MaterialPolicy ((Get-FileHash -Algorithm SHA256 -LiteralPath $sidecarPath).Hash -eq $sidecarHashBefore) `
        'passing --check must not rewrite the generated sidecar'
    Assert-Cf7MaterialPolicy ((Get-Item -LiteralPath $dictionaryPath).LastWriteTimeUtc.Ticks -eq $dictionaryWriteBefore) `
        'passing --check must preserve dictionary mtime'
    Assert-Cf7MaterialPolicy ((Get-Item -LiteralPath $sidecarPath).LastWriteTimeUtc.Ticks -eq $sidecarWriteBefore) `
        'passing --check must preserve sidecar mtime'

    $staleBytes = [IO.File]::ReadAllBytes($dictionaryPath) + [byte[]](10)
    [IO.File]::WriteAllBytes($dictionaryPath, $staleBytes)
    $staleHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $dictionaryPath).Hash
    $staleWriteBefore = (Get-Item -LiteralPath $dictionaryPath).LastWriteTimeUtc.Ticks
    $staleRun = Invoke-Cf7MaterialProducerCheck
    Assert-Cf7MaterialPolicy ($staleRun.ExitCode -eq 1) `
        'stale legacy dictionary must fail the production check'
    Assert-Cf7MaterialPolicy ($staleRun.Output -match 'material_dictionary\.xml is stale; run derive explicitly') `
        "stale failure must be actionable; output=$($staleRun.Output)"
    Assert-Cf7MaterialPolicy ((Get-FileHash -Algorithm SHA256 -LiteralPath $dictionaryPath).Hash -eq $staleHashBefore) `
        'failing --check must not repair or further mutate the stale dictionary'
    Assert-Cf7MaterialPolicy ((Get-Item -LiteralPath $dictionaryPath).LastWriteTimeUtc.Ticks -eq $staleWriteBefore) `
        'failing --check must preserve stale dictionary mtime'
    Assert-Cf7MaterialPolicy ((Get-FileHash -Algorithm SHA256 -LiteralPath $sidecarPath).Hash -eq $sidecarHashBefore) `
        'failing --check must not rewrite the sidecar'

    [IO.File]::WriteAllBytes($dictionaryPath, $dictionaryBytesBefore)
    $staleSidecarBytes = $sidecarBytesBefore + [byte[]](10)
    [IO.File]::WriteAllBytes($sidecarPath, $staleSidecarBytes)
    $staleSidecarHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $sidecarPath).Hash
    $staleSidecarWriteBefore = (Get-Item -LiteralPath $sidecarPath).LastWriteTimeUtc.Ticks
    $staleSidecarRun = Invoke-Cf7MaterialProducerCheck
    Assert-Cf7MaterialPolicy ($staleSidecarRun.ExitCode -eq 1) `
        'stale generated sidecar must fail the production check'
    Assert-Cf7MaterialPolicy ($staleSidecarRun.Output -match 'material_dictionary\.generated\.json is stale; run derive explicitly') `
        "stale sidecar failure must be actionable; output=$($staleSidecarRun.Output)"
    Assert-Cf7MaterialPolicy ((Get-FileHash -Algorithm SHA256 -LiteralPath $sidecarPath).Hash -eq $staleSidecarHashBefore) `
        'failing --check must not repair or further mutate the stale sidecar'
    Assert-Cf7MaterialPolicy ((Get-Item -LiteralPath $sidecarPath).LastWriteTimeUtc.Ticks -eq $staleSidecarWriteBefore) `
        'failing --check must preserve stale sidecar mtime'
    Assert-Cf7MaterialPolicy ((Get-FileHash -Algorithm SHA256 -LiteralPath $dictionaryPath).Hash -eq $dictionaryHashBefore) `
        'sidecar failure must not rewrite the restored dictionary'

    [IO.File]::WriteAllBytes($sidecarPath, $sidecarBytesBefore)
    $infrastructurePath = Join-Path $fixtureRoot $infrastructureRelativePath
    $infrastructureText = [IO.File]::ReadAllText($infrastructurePath, [Text.Encoding]::UTF8)
    $mutatedInfrastructureText = $infrastructureText.Replace('<Value>1</Value>', '<Value>2</Value>')
    Assert-Cf7MaterialPolicy ($mutatedInfrastructureText -ne $infrastructureText) `
        'fixture must contain a mutable infrastructure material quantity'
    [IO.File]::WriteAllBytes(
        $infrastructurePath,
        [Text.Encoding]::UTF8.GetBytes($mutatedInfrastructureText))
    $infrastructureDriftHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $infrastructurePath).Hash
    $inputDriftRun = Invoke-Cf7MaterialProducerCheck
    Assert-Cf7MaterialPolicy ($inputDriftRun.ExitCode -eq 1) `
        'infrastructure requirement drift must fail the production check'
    Assert-Cf7MaterialPolicy ($inputDriftRun.Output -match 'material_dictionary\.generated\.json is stale; run derive explicitly') `
        "infrastructure drift failure must identify the stale sidecar; output=$($inputDriftRun.Output)"
    Assert-Cf7MaterialPolicy ((Get-FileHash -Algorithm SHA256 -LiteralPath $infrastructurePath).Hash -eq $infrastructureDriftHash) `
        'failing --check must not rewrite infrastructure input data'
    Assert-Cf7MaterialPolicy ((Get-FileHash -Algorithm SHA256 -LiteralPath $sidecarPath).Hash -eq $sidecarHashBefore) `
        'infrastructure drift check must not rewrite the restored sidecar'
    Assert-Cf7MaterialPolicy ((Get-FileHash -Algorithm SHA256 -LiteralPath $dictionaryPath).Hash -eq $dictionaryHashBefore) `
        'infrastructure drift check must not rewrite the legacy dictionary'

    Write-Host "[MaterialCatalogReleasePolicyTest] OK checks=$checks" -ForegroundColor Green
} finally {
    if ($resolvedFixture.StartsWith($testBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedFixture -PathType Container)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
