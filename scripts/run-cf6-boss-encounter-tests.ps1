[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-boss-encounter' `
    -TemplateRelativePath 'scripts/test-runners/cf6-boss-encounter/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6BossEncounterTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6BossEncounterTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6BossEncounter.as','scripts/类定义/org/flashNight/arki/scene/BookRunRules.as') `
    -ExpectedTracePatterns @('(?m)^Cf6BossEncounterTest Tests Passed: 103\r?$', '(?m)^Cf6BossEncounterTest Tests Failed: 0\r?$') `
    -SuccessSummary '103/103 assertions; late primary birth, native phase identity, real AVM1 finite boss support, focus binding and ownership, no full chapter claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
