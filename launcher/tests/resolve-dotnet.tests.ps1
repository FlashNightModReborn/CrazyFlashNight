$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$testsDir = $PSScriptRoot
$launcherDir = Split-Path -Parent $testsDir
$projectRoot = Split-Path -Parent $launcherDir

. (Join-Path $launcherDir 'resolve-dotnet.ps1')

$script:passed = 0

function Assert-Cf7Equal {
    param(
        [Parameter(Mandatory=$false)]$Actual,
        [Parameter(Mandatory=$false)]$Expected,
        [Parameter(Mandatory=$true)][string]$Case
    )

    if ($Actual -ne $Expected) {
        throw "[$Case] expected '$Expected', got '$Actual'"
    }
    $script:passed++
}

function Assert-Cf7Throws {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [Parameter(Mandatory=$true)][string]$Case
    )

    try {
        & $Action
    } catch {
        $script:passed++
        return
    }
    throw "[$Case] expected a fail-closed exception"
}

$required = [Version]'10.0.300'

$selected = Select-Cf7DotnetSdkVersion `
    -RequiredVersion $required `
    -RollForward 'disable' `
    -InstalledVersions @([Version]'10.0.300')
Assert-Cf7Equal -Actual ([string]$selected) -Expected '10.0.300' -Case 'exact-only'

$selected = Select-Cf7DotnetSdkVersion `
    -RequiredVersion $required `
    -RollForward 'disable' `
    -InstalledVersions @([Version]'10.0.301')
Assert-Cf7Equal -Actual $selected -Expected $null -Case 'only-10.0.301'

$selected = Select-Cf7DotnetSdkVersion `
    -RequiredVersion $required `
    -RollForward 'disable' `
    -InstalledVersions @([Version]'10.0.301', [Version]'10.0.300')
Assert-Cf7Equal -Actual ([string]$selected) -Expected '10.0.300' -Case 'exact-plus-10.0.301'

$selected = Select-Cf7DotnetSdkVersion `
    -RequiredVersion $required `
    -RollForward 'disable' `
    -InstalledVersions @([Version]'10.0.400')
Assert-Cf7Equal -Actual $selected -Expected $null -Case 'only-10.0.400'

Assert-Cf7Throws -Case 'unsupported-policy' -Action {
    Select-Cf7DotnetSdkVersion `
        -RequiredVersion $required `
        -RollForward 'latestPatch' `
        -InstalledVersions @([Version]'10.0.300')
}

Assert-Cf7Throws -Case 'missing-policy' -Action {
    Select-Cf7DotnetSdkVersion `
        -RequiredVersion $required `
        -RollForward '' `
        -InstalledVersions @([Version]'10.0.300')
}

$contract = Get-Cf7DotnetSdkContract -ProjectRoot $projectRoot
$dotnet = Resolve-Cf7Dotnet -ProjectRoot $projectRoot
Push-Location -LiteralPath $projectRoot
try {
    $actualVersion = ([string](& $dotnet --version)).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "[repo-root-integration] dotnet --version exited $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
if ($contract.RollForward -ne 'disable') {
    throw "[repo-root-integration] expected rollForward=disable, got '$($contract.RollForward)'"
}
Assert-Cf7Equal `
    -Actual $actualVersion `
    -Expected $contract.VersionText `
    -Case 'repo-root-integration'

if ($script:passed -ne 7) {
    throw "Resolver contract suite count drift: expected 7, got $script:passed"
}
Write-Host "[resolve-dotnet-tests] 7/7 passed; repo-root SDK=$actualVersion" -ForegroundColor Green
