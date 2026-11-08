[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-soldier-loot-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-soldier-loot-host.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-soldier-loot' `
    -CompileTargetRelativePath 'scripts/Cf6SoldierLootHost/Cf6SoldierLootHost.xfl' `
    -CompileSwfRelativePath 'scripts/Cf6SoldierLootHost.swf' `
    -TemplateRelativePath 'scripts/test-runners/cf6-soldier-loot/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6SoldierLootTest.as','scripts/类定义/org/flashNight/arki/item/RewardStashServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6SoldierLootTest','org.flashNight.arki.item.RewardStashServiceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6SoldierLootFixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsFixture.as') `
    -ExpectedTracePatterns @('(?m)^Cf6SoldierLootTest: \d+ passed, 0 failed; isolated real save boundary\r?$','(?m)^RewardStashServiceTest Tests Passed: 137\r?$','(?m)^RewardStashServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary 'Fixed soldier exact loot/save faults and canonical reward stash regression' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE
