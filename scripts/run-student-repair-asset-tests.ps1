param([int]$TimeoutSeconds = 240, [int]$AsyncBehaviorTimeoutSeconds = 300, [switch]$ExportBitmaps)
$ErrorActionPreference = 'Stop'
if ($ExportBitmaps -and -not $PSBoundParameters.ContainsKey('AsyncBehaviorTimeoutSeconds')) { $AsyncBehaviorTimeoutSeconds=900 }
$studentPatterns = @('StudentRepairAssetTest: \d+ passed, 0 failed; 74 actual timeline cases')
if ($ExportBitmaps) { $studentPatterns += '(?m)^StudentRepairBitmapExport: [1-9][0-9]+ images, [1-9][0-9]+ rows\r?$' }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId student-repair -TemplateRelativePath 'scripts/test-runners/student-repair/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/StudentRepairAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.StudentRepairAssetTest' -ExpectedTracePatterns $studentPatterns -SuccessSummary '军阀与黑仔实际时间轴专项通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds -OwnedReadOnlyHost -ExportAssetBitmaps:$ExportBitmaps
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
