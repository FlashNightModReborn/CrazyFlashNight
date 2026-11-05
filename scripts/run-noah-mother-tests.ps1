[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=3600)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') -DomainId 'noah-mother' -TemplateRelativePath 'scripts/test-runners/noah-mother/TestLoader.as.template' -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/NoahMotherEncounterTest.as') -SuiteFqns @('org.flashNight.arki.scene.NoahMotherEncounterTest') -ExpectedTracePatterns @('(?m)^NoahMotherEncounterTest Tests Passed: 115\r?$','(?m)^NoahMotherEncounterTest Tests Failed: 0\r?$','(?m)^NoahMotherEncounterTest Native Asset Loaded: true\r?$') -SuccessSummary 'Noah mother population, production, liquids, lifecycle and actual published vector art' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds 45
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
