[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-map-mechanism' `
    -TemplateRelativePath 'scripts/test-runners/cf6-map-mechanism/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanismTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6MapMechanismTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6MapMechanismTest Tests Passed: 153\r?$', '(?m)^Cf6MapMechanismTest Tests Failed: 0\r?$') `
    -SuccessSummary '153/153 assertions (r15 static count 145+8 turret wiring, confirm on fresh run); real AVM1 mechanism and MovieClip lifecycle, no full chapter claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
