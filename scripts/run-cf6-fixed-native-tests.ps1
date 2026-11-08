[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[ValidateRange(1,3600)][int]$AsyncBehaviorTimeoutSeconds=900,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-firepower-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-fixed-actions-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-fixed-roster-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-soldier-assets/build-fixed-test-consumer.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-fixed-native' `
    -CompileTargetRelativePath 'scripts/Cf6FixedSoldierNativeHost/Cf6FixedSoldierNativeHost.xfl' `
    -CompileSwfRelativePath 'scripts/Cf6FixedSoldierNativeHost.swf' `
    -TemplateRelativePath 'scripts/test-runners/cf6-fixed-native/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6FixedSoldierNativeTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6SoldierFirepowerTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6FixedSoldierNativeTest','org.flashNight.arki.scene.Cf6FixedActionsTest','org.flashNight.arki.scene.Cf6SoldierFirepowerTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6SoldierFirepowerFixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsFixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedRosterFixture.as') `
    -ExpectedTracePatterns @('(?m)^Cf6SoldierFirepowerTest: [1-9]\d* passed, 0 failed; 282 independent slot anchors\r?$','(?m)^Cf6FixedActionsTest: \d+ passed, 0 failed; 22 same-source cycles and native ownership\r?$','(?m)^Cf6FixedSoldierNativeTest: \d+ passed, 0 failed; 158 fixed materializations, 35 native action cases\r?$') `
    -SuccessSummary 'Fixed158 real RSL equipment and native actor/core commit cases; controlled emission fixture' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE
