param([int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-elder-assets/build-playtest-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-bladebot-assets/build-knockback-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-elder -TemplateRelativePath 'scripts/test-runners/cf6-elder/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6ElderAssetTest' -ExpectedTracePatterns @('Cf6ElderAssetTest: \d+ passed, 0 failed; 46 actual timeline cases; 13 phase cases') -SuccessSummary '老头双形态原生攻击、死亡与连续阶段交接通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
