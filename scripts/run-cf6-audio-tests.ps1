param([int]$TimeoutSeconds=180)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-audio/build-test-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-audio -TemplateRelativePath 'scripts/test-runners/cf6-audio/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6AudioTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6AudioTest' -AdditionalAsRelativePaths 'scripts/test-runners/cf6-audio/AudioFixture.as' -ExpectedTracePatterns @('Cf6AudioTest: \d+ passed, 0 failed; 81 actual sound routes; libraries=8') -SuccessSummary '八个实际SWF的原生音效调用和新增触发暂停边界通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
