[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$scenePrepRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
# Invoke only AFTER the user releases the shared CS6 session. This script does
# not probe, clear or take over another chat's locks, scratch or processes.
& (Join-Path $scenePrepRoot 'scripts/test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-scene-completion' `
    -TemplateRelativePath 'tools/cf6-scene-completion/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6SceneCompletionTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalLifecycleTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6DoorAdvanceTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6SceneCompletionTest','org.flashNight.arki.scene.Cf6TraversalLifecycleTest','org.flashNight.arki.scene.Cf6DoorAdvanceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/StageManager.as','scripts/类定义/org/flashNight/arki/scene/PlayerResourceTransferBridge.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskState.as','scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskPresentation.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalRules.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as','scripts/类定义/org/flashNight/arki/pause/PauseManager.as','scripts/类定义/org/flashNight/arki/scene/Cf6ElevatorRules.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleRules.as') `
    -ExpectedTracePatterns @('(?m)^Cf6SceneCompletionTest Tests Passed: 51\r?$', '(?m)^Cf6SceneCompletionTest Tests Failed: 0\r?$', '(?m)^Cf6TraversalLifecycleTest Tests Passed: 70\r?$', '(?m)^Cf6TraversalLifecycleTest Tests Failed: 0\r?$', '(?m)^Cf6DoorAdvanceTest Tests Passed: 70\r?$', '(?m)^Cf6DoorAdvanceTest Tests Failed: 0\r?$') `
    -SuccessSummary '51 rules + 70 lifecycle + 70 standard authority handoff assertions; no full chapter acceptance claim' `
    -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
