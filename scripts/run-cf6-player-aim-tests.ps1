param([switch]$Baseline,[int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-elder-assets/build-playtest-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$template=if($Baseline){'scripts/test-runners/cf6-player-aim/TestLoader-baseline.as.template'}else{'scripts/test-runners/cf6-player-aim/TestLoader.as.template'}
$caseCount=if($Baseline){32}else{96}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-player-aim -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6PlayerAimTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6PlayerAimTest' -AdditionalAsRelativePaths 'scripts/test-runners/cf6-playtest/PlaytestFixture.as' -ExpectedTracePatterns @("Cf6PlayerAimTest: \d+ passed, 0 failed; $caseCount player-source cases") -SuccessSummary '玩家来源受击框与实际资源弹道验证完成' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
