[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$regressionRoot=Split-Path -Parent $PSScriptRoot
foreach($regressionCheck in @('tools/cf6-map-runtime/install-as2.py','tools/cf6-scene-completion/install_rules.py','tools/cf6-vehicle/prepare_runtime.py')) {
    python -X utf8 (Join-Path $regressionRoot $regressionCheck) --check
    if($LASTEXITCODE -ne 0) {throw "Prepared source differs: $regressionCheck"}
}
& (Join-Path $PSScriptRoot 'run-cf6-traversal-native-tests.ps1') -PrepareOnly
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-transition-regression' `
    -CompileTargetRelativePath 'scripts/tmp-cf6-traversal-native-host/Cf6TraversalNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6TraversalNativeHost.swf' `
    -TemplateRelativePath 'scripts/test-runners/cf6-transition-regression/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6VehicleMapIntegrationTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6DoorAdvanceTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6SceneCompletionTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalLifecycleTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanismTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6MechanismRevivalTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalNativeTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6VehicleMapIntegrationTest','org.flashNight.arki.scene.Cf6DoorAdvanceTest','org.flashNight.arki.scene.Cf6SceneCompletionTest','org.flashNight.arki.scene.Cf6TraversalLifecycleTest','org.flashNight.arki.scene.Cf6MapMechanismTest','org.flashNight.arki.scene.Cf6MechanismRevivalTest','org.flashNight.arki.scene.Cf6TraversalNativeTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/StageManager.as','scripts/类定义/org/flashNight/arki/scene/PlayerSceneLifecycle.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleActorAdapter.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleService.as','scripts/逻辑/单位函数/单位函数_lsy_主角行走状态机.as','scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalRules.as','scripts/类定义/org/flashNight/arki/scene/StageRunSession.as','scripts/类定义/org/flashNight/arki/pause/PauseManager.as','scripts/类定义/org/flashNight/gesh/depth/DepthManager.as') `
    -ExpectedTracePatterns @('(?m)^Cf6VehicleMapIntegrationTest Tests Passed: 61\r?$','(?m)^Cf6VehicleMapIntegrationTest Tests Failed: 0\r?$','(?m)^Cf6DoorAdvanceTest Tests Passed: 78\r?$','(?m)^Cf6DoorAdvanceTest Tests Failed: 0\r?$','(?m)^Cf6SceneCompletionTest Tests Passed: 51\r?$','(?m)^Cf6SceneCompletionTest Tests Failed: 0\r?$','(?m)^Cf6TraversalLifecycleTest Tests Passed: 70\r?$','(?m)^Cf6TraversalLifecycleTest Tests Failed: 0\r?$','(?m)^Cf6MapMechanismTest Tests Passed: 272\r?$','(?m)^Cf6MapMechanismTest Tests Failed: 0\r?$','(?m)^Cf6MechanismRevivalTest Tests Passed: 112\r?$','(?m)^Cf6MechanismRevivalTest Tests Failed: 0\r?$','(?m)^Cf6TraversalNativeTest Tests Passed: 121\r?$','(?m)^Cf6TraversalNativeTest Tests Failed: 0\r?$') `
    -SuccessSummary '765 directed assertions: ordinary handoff, traversal/vehicle integration, death/revival and actual native player timelines; no full-game acceptance' `
    -AsyncBehaviorTimeoutSeconds 240 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE
