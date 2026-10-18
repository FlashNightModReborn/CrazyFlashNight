param([int]$TimeoutSeconds=180)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-audio/build-legacy-test-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-audio-legacy -TemplateRelativePath 'scripts/test-runners/cf6-audio/TestLoader-legacy.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6AudioTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6AudioTest' -AdditionalAsRelativePaths 'scripts/test-runners/cf6-audio/LegacyAudioFixture.as' -ExpectedTracePatterns @('Cf6AudioTest: \d+ passed, 0 failed; 8 actual sound routes; libraries=4') -SuccessSummary '三个既有克隆兽和旧女特工的原生音效调用通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
