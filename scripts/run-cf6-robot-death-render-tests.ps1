param([Parameter(Mandatory=$true)][ValidateSet('headbot','elder','bladebot')][string]$Family,[int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-headbot-assets/build-death-render-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$domain='cf6-robot-death-'+$Family
$template='scripts/test-runners/cf6-robot-death-render/TestLoader-'+$Family+'.as.template'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId $domain -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6RobotDeathRenderTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6RobotDeathRenderTest' -AdditionalAsRelativePaths 'scripts/test-runners/cf6-robot-death-render/DeathFixture.as' -ExpectedTracePatterns @('Cf6RobotDeathRenderTest: \d+ passed, 0 failed; 8 draw points') -SuccessSummary '选定的机器人死亡关键帧已原生绘制' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
