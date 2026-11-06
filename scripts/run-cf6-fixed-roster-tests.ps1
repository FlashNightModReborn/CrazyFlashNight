[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-fixed-roster-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-fixed-roster' `
    -TemplateRelativePath 'scripts/test-runners/cf6-fixed-roster/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheelTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6SoldierRosterTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.WaveSpawnWheelTest','org.flashNight.arki.scene.Cf6SoldierRosterTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheel.as','scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as','scripts/类定义/org/flashNight/arki/scene/Cf6SoldierRoster.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedRosterFixture.as') `
    -ExpectedTracePatterns @('(?m)^WaveSpawnWheelTest Tests Passed: 36\r?$','(?m)^WaveSpawnWheelTest Tests Failed: 0\r?$','(?m)^Cf6SoldierRosterTest: \d+ passed, 0 failed; 158 materialized, 101 groups\r?$') `
    -SuccessSummary 'Fixed158 native materialization and scheduler retry identities verified; no save or gameplay claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE
