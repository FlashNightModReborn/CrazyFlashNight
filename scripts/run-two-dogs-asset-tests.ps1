param([int]$TimeoutSeconds = 300, [int]$AsyncBehaviorTimeoutSeconds = 900)
$ErrorActionPreference = 'Stop'
& python -X utf8 (Join-Path $PSScriptRoot '../tools/two-dogs-assets/build-test-host.py') --check
if ($LASTEXITCODE -ne 0) { throw 'Regenerate TwoDogsNativeHost before running the fixture.' }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId two-dogs -CompileTargetRelativePath scripts/TwoDogsNativeHost/TwoDogsNativeHost.xfl -CompileSwfRelativePath scripts/TwoDogsNativeHost.swf -TemplateRelativePath 'scripts/test-runners/two-dogs/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/TwoDogsAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.TwoDogsAssetTest' -ExpectedTracePatterns @('TwoDogsAssetTest: \d+ passed, 0 failed; 24 actual timeline cases','(?m)^\[DOG_IMAGES_COMPLETE\] frames=18\r?$') -SuccessSummary '两犬原生装配、口腔结构、共享导入宿主、继承攻击与死亡专项通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
