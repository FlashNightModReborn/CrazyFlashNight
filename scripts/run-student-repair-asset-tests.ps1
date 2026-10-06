param([int]$TimeoutSeconds = 240)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId student-repair -TemplateRelativePath 'scripts/test-runners/student-repair/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/StudentRepairAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.StudentRepairAssetTest' -ExpectedTracePatterns 'StudentRepairAssetTest: \d+ passed, 0 failed; 70 actual timeline cases' -SuccessSummary '军阀与黑仔实际时间轴专项通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds 300
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
