param([int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Get-Content -LiteralPath (Join-Path $root 'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as') -Raw -Encoding UTF8
$source=$source.Replace("`r`n","`n")
$match=[regex]::Match($source,'_root\.敌人函数\.被击移动 = function[\s\S]*?\n};')
if(-not $match.Success){throw 'Canonical knockback function not found.'}
$canonical=$match.Value.Replace('_root.敌人函数.被击移动','_root.cf6PressureKnockback')
$template=Get-Content -LiteralPath (Join-Path $root 'scripts/test-runners/cf6-shield-separation/TestLoader.as.template') -Raw -Encoding UTF8
if(-not $template.Replace("`r`n","`n").Contains($canonical)){throw 'Shield separation fixture needs regeneration from current knockback source.'}
& python -X utf8 -B (Join-Path $root 'tools/cf6-elder-assets/build-playtest-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-shield-separation -TemplateRelativePath 'scripts/test-runners/cf6-shield-separation/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ShieldSeparationTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6ShieldSeparationTest' -AdditionalAsRelativePaths 'scripts/test-runners/cf6-playtest/PlaytestFixture.as' -ExpectedTracePatterns @('Cf6ShieldSeparationTest: \d+ passed, 0 failed; 24 standard-impact cases') -SuccessSummary '标准冲击、碰撞和免疫下的盾击间距验证完成；不代替完整玩家控制器或真人体验' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
