param([int]$TimeoutSeconds = 180, [int]$AsyncBehaviorTimeoutSeconds = 180, [switch]$Capture, [switch]$ShadowCapture)
$ErrorActionPreference = 'Stop'
# Lossless whole-unit and body captures can require several minutes of real Flash log output.
if (($Capture -or $ShadowCapture) -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 600 }
if (($Capture -or $ShadowCapture) -and -not $PSBoundParameters.ContainsKey('AsyncBehaviorTimeoutSeconds')) { $AsyncBehaviorTimeoutSeconds = 600 }
if ($Capture -and $ShadowCapture) { throw 'Select Capture or ShadowCapture.' }
$template = if ($ShadowCapture) { 'scripts/test-runners/cf6-wings/TestLoader-shadow-capture.as.template' } elseif ($Capture) { 'scripts/test-runners/cf6-wings/TestLoader-capture.as.template' } else { 'scripts/test-runners/cf6-wings/TestLoader.as.template' }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-wings -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6WingsAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6WingsAssetTest' -ExpectedTracePatterns @('Cf6WingsAssetTest: \d+ passed, 0 failed; 32 actual timeline cases') -SuccessSummary 'Wings 原生动作、枪口、死亡与私有 AI 边界通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
