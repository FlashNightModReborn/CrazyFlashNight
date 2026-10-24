[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$vehicleSharedRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
python -X utf8 (Join-Path $PSScriptRoot 'prepare_shared_consumer.py') --check
if($LASTEXITCODE -ne 0){throw 'Shared consumer fixture is stale'}
& (Join-Path $vehicleSharedRoot 'scripts/test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-vehicle-shared' `
    -CompileTargetRelativePath 'scripts/tmp-cf6-vehicle-shared-host/Cf6VehicleSharedConsumerHost.xfl' `
    -CompileSwfRelativePath 'Cf6VehicleSharedConsumerHost.swf' `
    -TemplateRelativePath 'tools/cf6-vehicle/SharedConsumer.TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6VehicleSharedConsumerTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6VehicleSharedConsumerTest') `
    -ExpectedTracePatterns @('(?m)^Cf6VehicleSharedConsumerTest Tests Passed: 31\r?$','(?m)^Cf6VehicleSharedConsumerTest Tests Failed: 0\r?$') `
    -SuccessSummary '31 actual things-new consumer checks: ten dynamic vehicle exports with source identity and native pixels' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
