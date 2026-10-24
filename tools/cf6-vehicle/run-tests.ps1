[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$vehicleRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
python -X utf8 (Join-Path $PSScriptRoot 'prepare_runtime.py') --check
if($LASTEXITCODE -ne 0) { throw 'Vehicle runtime preparation check failed.' }
python -X utf8 (Join-Path $PSScriptRoot 'prepare_tests.py') --check --bind-native
if($LASTEXITCODE -ne 0) { throw 'Vehicle native fixture preparation check failed.' }
& (Join-Path $vehicleRoot 'scripts/test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-vehicle' `
    -CompileTargetRelativePath 'scripts/tmp-cf6-vehicle-host/Cf6VehicleNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6VehicleNativeHost.swf' `
    -TemplateRelativePath 'tools/cf6-vehicle/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6VehicleTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6VehicleTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6VehicleTestData.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleRules.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleData.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleTimeline.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleActorAdapter.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleCombat.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6VehicleTest Tests Passed: 99\r?$', '(?m)^Cf6VehicleTest Tests Failed: 0\r?$', '(?m)^VehicleInputEvidence: controlled_intent; native_key_mapping=source_fixture_only\r?$') `
    -SuccessSummary '99 native assertions: source art, controlled intent, hit boundaries, clocks, ordnance, audio, real damage and same-actor death/respawn' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
