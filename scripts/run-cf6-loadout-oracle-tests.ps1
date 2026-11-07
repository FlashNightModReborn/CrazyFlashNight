[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/apply-loadout-plan.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-loadout-oracle.py')
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-loadout-oracle' `
    -TemplateRelativePath 'scripts/test-runners/cf6-loadout-oracle/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/item/equipment/Cf6LoadoutOracleTest.as') `
    -SuiteFqns @('org.flashNight.arki.item.equipment.Cf6LoadoutOracleTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as','scripts/类定义/org/flashNight/arki/item/equipment/EquipmentCalculator.as','scripts/类定义/org/flashNight/arki/item/equipment/TagManager.as','scripts/类定义/org/flashNight/arki/item/equipment/ModRegistry.as') `
    -ExpectedTracePatterns @('(?m)^Cf6LoadoutOracleTest Tests Passed: [1-9][0-9]*\r?$','(?m)^Cf6LoadoutOracleTest Tests Failed: 0\r?$','(?m)^Cf6LoadoutOracle counts expanded=145 sidearms=124 carbineEligibleSlots=\d+\r?$') `
    -SuccessSummary 'All 282 real equipment slots: ordered menu/install admission, derived power, slots and unchanged projectile/action budget' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds 600
exit $LASTEXITCODE
