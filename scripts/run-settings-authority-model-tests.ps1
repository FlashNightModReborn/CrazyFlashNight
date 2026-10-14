[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'settings-authority-model' `
    -TemplateRelativePath 'scripts/test-runners/settings-authority-model/TestLoader.as.template' `
    -SuiteRelativePaths 'scripts/类定义/org/flashNight/neur/Server/test/SettingsAuthorityModelTest.as' `
    -SuiteFqns 'org.flashNight.neur.Server.test.SettingsAuthorityModelTest' `
    -ExpectedTracePatterns '(?m)^SettingsAuthorityModelTest Tests Passed: 26\r?$','(?m)^SettingsAuthorityModelTest Tests Failed: 0\r?$' `
    -SuccessSummary '26 in-memory assertions; no SOL or player slot' `
    -TimeoutSeconds $TimeoutSeconds -AutoStopReadOnlyPlayer -OwnedReadOnlyHost
