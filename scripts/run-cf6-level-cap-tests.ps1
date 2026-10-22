[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskTemplate = Get-Content -LiteralPath (Join-Path $taskRoot 'scripts/test-runners/cf6-level-cap/TestLoader.as.template') -Raw -Encoding utf8
$taskCapture = $taskTemplate.IndexOf('org.flashNight.arki.scene.Cf6LevelCapTest.captureRoot();')
$taskInclude = $taskTemplate.IndexOf('#include "引擎/引擎_lsy_等级与经验值.as"')
$taskRun = $taskTemplate.IndexOf('org.flashNight.arki.scene.Cf6LevelCapTest.runAllTests();')
if ($taskCapture -lt 0 -or $taskInclude -le $taskCapture -or $taskRun -le $taskInclude) {
    throw 'Fixed-level suite requires captureRoot -> actual production XP include -> runAllTests.'
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-level-cap' `
    -TemplateRelativePath 'scripts/test-runners/cf6-level-cap/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6LevelCapTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6LevelCapTest') `
    -AdditionalAsRelativePaths @('scripts/引擎/引擎_lsy_等级与经验值.as','scripts/类定义/org/flashNight/arki/scene/BookRunService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6LevelCapTest Tests Passed: 52\r?$', '(?m)^Cf6LevelCapTest Tests Failed: 0\r?$') `
    -SuccessSummary '52/52 assertions against included production XP root functions; no real save writes' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
