[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$projectRoot=Split-Path -Parent $PSScriptRoot
$fixturePath=& node (Join-Path $projectRoot 'tools/prepare-settings-sol-fixture.js')
if($LASTEXITCODE -ne 0){throw 'Owned SOL fixture preparation failed'}
$fixture=Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ('Owned SOL evidence: '+$fixture.evidenceDirectory)
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId 'settings-sol-boundary' `
    -TemplateRelativePath 'scripts/test-runners/settings-sol-boundary/TestLoader.as.template' `
    -SuiteRelativePaths 'scripts/类定义/org/flashNight/neur/Server/test/SettingsOwnedSolTest.as' `
    -SuiteFqns 'org.flashNight.neur.Server.test.SettingsOwnedSolTest' `
    -ExpectedTracePatterns '(?m)^SettingsOwnedSolTest Tests Passed: 20\r?$','(?m)^SettingsOwnedSolTest Tests Failed: 0\r?$', `
        '(?m)^WeaponAmmoOwnedSolTest Tests Passed: 5\r?$','(?m)^WeaponAmmoOwnedSolTest Tests Failed: 0\r?$', `
        ('(?m)^SettingsOwnedSolTest NativeRawKnownTerminal: '+[regex]::Escape($fixture.slot)+'\r?$') `
    -SuccessSummary 'native raw confirmation; synthetic business; unique owned SOL retained for cold read' `
    -TimeoutSeconds $TimeoutSeconds -OwnedDisposableSolHost -SolFixtureConfigPath $fixturePath
