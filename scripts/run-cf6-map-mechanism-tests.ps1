[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-map-mechanism' `
    -TemplateRelativePath 'scripts/test-runners/cf6-map-mechanism/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanismTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6MapMechanismTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/StageManager.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskState.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskPresentation.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalRules.as','scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as','scripts/类定义/org/flashNight/arki/pause/PauseManager.as','scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6MapMechanismTest Tests Passed: 213\r?$', '(?m)^Cf6MapMechanismTest Tests Failed: 0\r?$') `
    -SuccessSummary '213 assertions including production traversal and exact asset closure cases; real AVM1 mechanism and MovieClip lifecycle, no full chapter claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
