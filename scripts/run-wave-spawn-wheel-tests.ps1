[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'wave-spawn-wheel' `
    -TemplateRelativePath 'scripts/test-runners/wave-spawn-wheel/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheelTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.WaveSpawnWheelTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheel.as') `
    -ExpectedTracePatterns @('(?m)^WaveSpawnWheelTest Tests Passed: 18\r?$', '(?m)^WaveSpawnWheelTest Tests Failed: 0\r?$') `
    -SuccessSummary '18/18 scheduler assertions; real AVM1 wheel with capacity/rejection contract fixture; no full game claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
