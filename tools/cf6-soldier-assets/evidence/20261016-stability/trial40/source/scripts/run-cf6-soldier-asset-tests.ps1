param([int]$TimeoutSeconds = 180, [int]$AsyncBehaviorTimeoutSeconds = 180, [switch]$Capture, [switch]$CaptureShield)
$ErrorActionPreference = 'Stop'
if (($Capture -or $CaptureShield) -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 600 }
if (($Capture -or $CaptureShield) -and -not $PSBoundParameters.ContainsKey('AsyncBehaviorTimeoutSeconds')) { $AsyncBehaviorTimeoutSeconds = 600 }
# Build the same RSL linkage scope used by the game; separate loadMovie libraries cannot share weapons.
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-soldier-assets/build-test-consumer.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$template = if ($CaptureShield) { 'scripts/test-runners/cf6-soldier/TestLoader-shield-capture.as.template' } elseif ($Capture) { 'scripts/test-runners/cf6-soldier/TestLoader-capture.as.template' } else { 'scripts/test-runners/cf6-soldier/TestLoader.as.template' }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-soldier -CompileTargetRelativePath scripts/Cf6SoldierNativeHost/Cf6SoldierNativeHost.xfl -CompileSwfRelativePath scripts/Cf6SoldierNativeHost.swf -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6SoldierAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6SoldierAssetTest' -ExpectedTracePatterns @('Cf6SoldierAssetTest: \d+ passed, 0 failed; 66 actual timeline cases') -SuccessSummary '特种兵两阶段原生动作、装备、暴击斩杀和死亡边界通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
