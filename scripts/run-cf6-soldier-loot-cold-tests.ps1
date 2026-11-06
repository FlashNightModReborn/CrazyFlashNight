[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/prepare-loot-cold-host.py')
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-soldier-loot-cold' `
    -CompileTargetRelativePath 'scripts/tmp-cf6-loot-cold-host/Cf6SoldierLootColdProbe.xfl' `
    -CompileSwfRelativePath 'Cf6SoldierLootColdProbe.swf' `
    -TemplateRelativePath 'scripts/test-runners/cf6-soldier-loot-cold/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6SoldierLootColdProbeTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6SoldierLootColdProbeTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsFixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6SoldierLootFixture.as') `
    -ExpectedTracePatterns @('(?m)^Cf6SoldierLootColdProbeTest ready\r?$') `
    -SuccessSummary 'Cold read probe compiled and ready; no persistence acceptance until independent-process driver completes' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds 60 -SkipCompile:$SkipCompile
exit $LASTEXITCODE
