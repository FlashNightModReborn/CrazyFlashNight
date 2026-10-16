param([int]$TimeoutSeconds = 180, [int]$AsyncBehaviorTimeoutSeconds = 180, [switch]$Capture)
$ErrorActionPreference = 'Stop'
if ($Capture -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 600 }
if ($Capture -and -not $PSBoundParameters.ContainsKey('AsyncBehaviorTimeoutSeconds')) { $AsyncBehaviorTimeoutSeconds = 600 }
$template = if ($Capture) { 'scripts/test-runners/cf6-guard/TestLoader-capture.as.template' } else { 'scripts/test-runners/cf6-guard/TestLoader.as.template' }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-guard -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6GuardAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6GuardAssetTest' -ExpectedTracePatterns @('Cf6GuardAssetTest: \d+ passed, 0 failed; 22 actual timeline cases') -SuccessSummary '光头保安原生动作、散弹枪口、暂停和生命周期通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
