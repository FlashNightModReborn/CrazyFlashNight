param([int]$TimeoutSeconds=240,[int]$AsyncBehaviorTimeoutSeconds=600,[switch]$Capture)
$ErrorActionPreference='Stop'
$template=if($Capture){'scripts/test-runners/cf2-tank-boss/VisualProbe-capture.as.template'}else{'scripts/test-runners/cf2-tank-boss/VisualProbe.as.template'}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId cf2-tank-visual `
    -TemplateRelativePath $template `
    -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf2TankBossVisualProbe.as' `
    -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf2TankBossVisualProbe' `
    -ExpectedTracePatterns @('Cf2TankBossVisualProbe: 8 passed, 0 failed') `
    -SuccessSummary '大机器人轻量原生图形诊断完成（不代替正式伤害与碎片验证）' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
