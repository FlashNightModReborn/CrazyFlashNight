param([int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-elder-assets/build-playtest-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-headbot -TemplateRelativePath 'scripts/test-runners/cf6-headbot/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6HeadbotAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6HeadbotAssetTest' -ExpectedTracePatterns @('Cf6HeadbotAssetTest: \d+ passed, 0 failed; 24 actual timeline cases') -SuccessSummary '大头机器人原生动作、双光束、伸缩冲击与机械死亡生命周期通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
