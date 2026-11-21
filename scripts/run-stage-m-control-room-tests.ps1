[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'stage-m-control-room' `
    -TemplateRelativePath 'scripts/test-runners/stage-m-control-room/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/StageMControlRoomTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.StageMControlRoomTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as') `
    -ExpectedTracePatterns @('(?m)^StageMControlRoomTest Tests Passed: 2\r?$', '(?m)^StageMControlRoomTest Tests Failed: 0\r?$') `
    -SuccessSummary '2/2 empty opening assertions against the real AVM1 WaveSpawner clock; no full game claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
