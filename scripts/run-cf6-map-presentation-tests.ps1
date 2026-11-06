[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
 -DomainId 'cf6-map-presentation' `
 -TemplateRelativePath 'scripts/test-runners/cf6-map-presentation/TestLoader.as.template' `
 -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MapPresentationTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanismTest.as') `
 -SuiteFqns @('org.flashNight.arki.scene.Cf6MapPresentationTest','org.flashNight.arki.scene.Cf6MapMechanismTest') `
 -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MapPresentation.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/StageManager.as','scripts/类定义/org/flashNight/arki/scene/BookDefinition.as') `
 -ExpectedTracePatterns @('(?m)^Cf6MapPresentationTest Tests Passed: 37\r?$','(?m)^Cf6MapPresentationTest Tests Failed: 0\r?$','(?m)^Cf6MapMechanismTest Tests Passed: 272\r?$','(?m)^Cf6MapMechanismTest Tests Failed: 0\r?$') `
 -SuccessSummary '287 assertions: native map transforms, nonzero debug-start identity, pixels and lifecycle; no full chapter claim' `
 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
