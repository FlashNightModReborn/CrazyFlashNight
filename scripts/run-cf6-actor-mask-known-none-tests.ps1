[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-actor-mask-known-none' `
    -TemplateRelativePath 'scripts/test-runners/cf6-actor-mask-known-none/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskBirthTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskKnownNoneTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6ActorMaskBirthTest','org.flashNight.arki.scene.Cf6ActorMaskKnownNoneTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskState.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskPresentation.as','scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6ActorMaskBirthTest Tests Passed: 21\r?$', '(?m)^Cf6ActorMaskBirthTest Tests Failed: 0\r?$', '(?m)^Cf6ActorMaskKnownNoneTest Tests Passed: 47\r?$', '(?m)^Cf6ActorMaskKnownNoneTest Tests Failed: 0\r?$') `
    -SuccessSummary '21 native birth/forwarding +47 born-known-none geometry/ownership assertions; unknown actor-level masks remain unsupported and are refused' `
    -AsyncBehaviorTimeoutSeconds 120 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
