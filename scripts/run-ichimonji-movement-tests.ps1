[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'ichimonji-movement' `
    -TemplateRelativePath 'scripts/test-runners/ichimonji-movement/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/unit/Action/Skill/IchimonjiMovementTest.as') `
    -SuiteFqns @('org.flashNight.arki.unit.Action.Skill.IchimonjiMovementTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/unit/Action/Skill/IchimonjiMovement.as') `
    -ExpectedTracePatterns @('(?m)^IchimonjiMovementTest Tests Passed: 16\r?$', '(?m)^IchimonjiMovementTest Tests Failed: 0\r?$') `
    -SuccessSummary '16 real AVM1 directional movement, map-boundary and thin-wall assertions; no full-game feel claim' `
    -TimeoutSeconds $TimeoutSeconds
