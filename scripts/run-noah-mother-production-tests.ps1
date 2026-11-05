[CmdletBinding()]
param([int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') -DomainId 'noah-mother-production' -TemplateRelativePath 'scripts/test-runners/noah-mother-production/TestLoader.as.template' -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/NoahMotherProductionTest.as') -SuiteFqns @('org.flashNight.arki.scene.NoahMotherProductionTest') -ExpectedTracePatterns @('(?m)^NoahMotherProductionTest Tests Passed: 7\r?$','(?m)^NoahMotherProductionTest Tests Failed: 0\r?$') -SuccessSummary '7 published native producer-frame assertions' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds 45
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
