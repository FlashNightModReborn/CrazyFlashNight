[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-fixed-actions-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-fixed-chapter-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-soldier-assets/build-fixed-test-consumer.py') --chapter
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-fixed-chapter' `
    -CompileTargetRelativePath 'scripts/Cf6FixedChapterHost/Cf6FixedChapterHost.xfl' `
    -CompileSwfRelativePath 'scripts/Cf6FixedChapterHost.swf' `
    -TemplateRelativePath 'scripts/test-runners/cf6-fixed-chapter/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6FixedChapterNativeTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6FixedChapterNativeTest','org.flashNight.arki.scene.Cf6FixedActionsTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6FixedChapterFixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedSoldierNativeTest.as') `
    -ExpectedTracePatterns @('(?m)^Cf6FixedActionsTest: \d+ passed, 0 failed; 22 same-source cycles and native ownership\r?$','(?m)^Cf6FixedChapterNativeTest: \d+ passed, 0 failed; 158 chapter actors, 12 authored maps\r?$') `
    -SuccessSummary 'Actual runtime chapter and158 native spawn consumers, map collisions, finite support and death-capture integration; controlled wave timing and boss HP' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds 900 -SkipCompile:$SkipCompile
exit $LASTEXITCODE
