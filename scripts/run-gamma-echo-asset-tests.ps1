param([int]$TimeoutSeconds = 180, [int]$AsyncBehaviorTimeoutSeconds = 120, [switch]$ExportDeathFrames, [switch]$ExportConnectionFrames)
$ErrorActionPreference = 'Stop'
if ($ExportDeathFrames) {
    if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 900 }
    if (-not $PSBoundParameters.ContainsKey('AsyncBehaviorTimeoutSeconds')) { $AsyncBehaviorTimeoutSeconds = 900 }
}
if ($ExportDeathFrames -and $ExportConnectionFrames) { throw 'Select one diagnostic export per run.' }
if ($ExportConnectionFrames) {
    if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 1200 }
    if (-not $PSBoundParameters.ContainsKey('AsyncBehaviorTimeoutSeconds')) { $AsyncBehaviorTimeoutSeconds = 1200 }
}
$gammaTemplate = if ($ExportDeathFrames) { 'scripts/test-runners/gamma-echo/TestLoader-death-preview.as.template' } elseif ($ExportConnectionFrames) { 'scripts/test-runners/gamma-echo/TestLoader-connections.as.template' } else { 'scripts/test-runners/gamma-echo/TestLoader.as.template' }
$gammaPatterns = @('GammaEchoAssetTest: \d+ passed, 0 failed; 28 actual timeline cases','(?m)^\[GAMMA_IMAGE_END\] stabilized-native\r?$','(?m)^\[GAMMA_IMAGE_END\] full-power-native\r?$')
if ($ExportDeathFrames) { $gammaPatterns += '(?m)^\[GAMMA_DEATH_EXPORT_COMPLETE\] frames=76\r?$' }
if ($ExportConnectionFrames) { $gammaPatterns += '(?m)^\[GAMMA_CONNECTION_EXPORT_COMPLETE\] frames=28\r?$' }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId gamma-echo -TemplateRelativePath $gammaTemplate -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/GammaEchoAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.GammaEchoAssetTest' -ExpectedTracePatterns $gammaPatterns -SuccessSummary 'γ-ECHO 双版本原生时间轴与私有决策专项通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
