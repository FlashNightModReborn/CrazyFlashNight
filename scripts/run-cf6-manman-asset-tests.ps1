param([int]$TimeoutSeconds = 180, [int]$AsyncBehaviorTimeoutSeconds = 180, [switch]$Capture)
$ErrorActionPreference = 'Stop'
$template = if ($Capture) { 'scripts/test-runners/cf6-manman/TestLoader-capture.as.template' } else { 'scripts/test-runners/cf6-manman/TestLoader.as.template' }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-manman -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ManmanAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6ManmanAssetTest' -ExpectedTracePatterns @('Cf6ManmanAssetTest: \d+ passed, 0 failed; 22 actual timeline cases') -SuccessSummary '蛮蛮原生动作、击溃传参、私有 AI 与中断边界通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
