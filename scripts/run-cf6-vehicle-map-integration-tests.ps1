# Focused Map/Stage/Wave seam tests. Vehicle simulation and loading are explicit memory ports.
[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$draftRepoRoot=Split-Path -Parent $PSScriptRoot
$testPath='scripts/类定义/org/flashNight/arki/scene/Cf6VehicleMapIntegrationTest.as'
$templatePath='scripts/test-runners/cf6-vehicle-map-integration/TestLoader.as.template'
foreach($file in @($testPath,$templatePath)){if(!(Test-Path -LiteralPath (Join-Path $draftRepoRoot $file))){throw "Reviewed source is not installed: $file"}}
& (Join-Path $draftRepoRoot 'scripts/test-runners/run-focused-testloader.ps1') `
 -DomainId 'cf6-vehicle-map-integration' `
 -TemplateRelativePath $templatePath -SuiteRelativePaths @($testPath) `
 -SuiteFqns @('org.flashNight.arki.scene.Cf6VehicleMapIntegrationTest') `
 -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/StageManager.as','scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as','scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheel.as','scripts/类定义/org/flashNight/arki/scene/Cf6VehicleTestData.as') `
 -ExpectedTracePatterns @('(?m)^Cf6VehicleMapIntegrationTest Tests Passed: 51\r?$','(?m)^Cf6VehicleMapIntegrationTest Tests Failed: 0\r?$','(?m)^CF6VehicleMapEvidence: actual MapMechanism/StageManager/WaveSpawner; mocked vehicle/loader/camera/persistence-query/fade ports; no live game claim\r?$') `
 -SuccessSummary 'Actual Map/Stage/Wave seam only; explicit memory ports; no vehicle simulation or full-game acceptance' `
 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE