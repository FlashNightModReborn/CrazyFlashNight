[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-fixed-actions-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-fixed-actions' `
    -TemplateRelativePath 'scripts/test-runners/cf6-fixed-actions/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6FixedActionsTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsFixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6SoldierActions.as','scripts/类定义/org/flashNight/arki/scene/Cf6SoldierSignals.as','scripts/类定义/org/flashNight/arki/scene/Cf6SoldierPairs.as','scripts/类定义/org/flashNight/arki/scene/Cf6DamageGroups.as','tools/cf6-soldier-assets/FixedActionRules.as','tools/cf6-soldier-assets/FixedActionTriggers.as') `
    -ExpectedTracePatterns @('(?m)^Cf6FixedActionsTest: \d+ passed, 0 failed; 22 same-source cycles and native ownership\r?$') `
    -SuccessSummary 'Same-source fixed action rules and native lifecycle ownership verified; no gameplay acceptance claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE
