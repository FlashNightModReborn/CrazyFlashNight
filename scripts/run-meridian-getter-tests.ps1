[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'meridian-getter-native' `
    -TemplateRelativePath 'scripts/test-runners/player-stat-refresh/GetterProbe.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/ui/MeridianGetterRegistrationTest.as') `
    -SuiteFqns @('org.flashNight.arki.ui.MeridianGetterRegistrationTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/ui/MeridianPanelService.as') `
    -ExpectedTracePatterns @('(?m)^MeridianGetterRegistrationTest Tests Passed: [1-9][0-9]*\r?$','(?m)^MeridianGetterRegistrationTest Tests Failed: 0\r?$') `
    -SuccessSummary 'Actual installed Meridian getter registration and no-charge reads' `
    -TimeoutSeconds $TimeoutSeconds
