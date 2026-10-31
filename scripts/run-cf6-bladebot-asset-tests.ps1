param([int]$TimeoutSeconds = 180, [int]$AsyncBehaviorTimeoutSeconds = 180, [switch]$Capture)
$ErrorActionPreference = 'Stop'
if ($Capture -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 600 }
if ($Capture -and -not $PSBoundParameters.ContainsKey('AsyncBehaviorTimeoutSeconds')) { $AsyncBehaviorTimeoutSeconds = 600 }
$template = if ($Capture) { 'scripts/test-runners/cf6-bladebot/TestLoader-capture.as.template' } else { 'scripts/test-runners/cf6-bladebot/TestLoader.as.template' }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-bladebot -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6BladebotAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6BladebotAssetTest' -ExpectedTracePatterns @('Cf6BladebotAssetTest: \d+ passed, 0 failed; 30 actual timeline cases') -SuccessSummary '大刀机器人原生动作、近战判定、影子和生命周期通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
