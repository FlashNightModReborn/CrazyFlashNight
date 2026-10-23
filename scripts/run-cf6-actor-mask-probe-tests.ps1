[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-actor-mask-probe' `
    -TemplateRelativePath 'scripts/test-runners/cf6-actor-mask-probe/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskProbeTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6ActorMaskProbeTest') `
    -ExpectedTracePatterns @('(?m)^Cf6ActorMaskProbeTest Tests Passed: 6\r?$', '(?m)^Cf6ActorMaskProbeTest Tests Failed: 0\r?$', '(?m)^Cf6ActorMaskProbe UnknownActorMaskSafe: (true|false)\r?$') `
    -SuccessSummary '6/6 in-memory fixture checks; read UnknownActorMaskSafe separately before any proxy decision' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile