[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'sleep-panel' `
    -TemplateRelativePath 'scripts/test-runners/sleep-panel/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/ui/SleepPanelServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.ui.SleepPanelServiceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/ui/SleepPanelService.as', 'scripts/类定义/org/flashNight/arki/weather/WeatherSystem.as') `
    -ExpectedTracePatterns @('(?m)^SleepPanelServiceTest Tests Passed: 33\r?$', '(?m)^SleepPanelServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '33/33 assertions' -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
