[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'ground-target-motion' `
    -TemplateRelativePath 'scripts/test-runners/ground-target-motion/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/spatial/move/GroundTargetMotionTest.as') `
    -SuiteFqns @('org.flashNight.arki.spatial.move.GroundTargetMotionTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/spatial/move/GroundTargetMotion.as') `
    -ExpectedTracePatterns @('(?m)^GroundTargetMotionTest Tests Passed: 786\r?$', '(?m)^GroundTargetMotionTest Tests Failed: 0\r?$') `
    -SuccessSummary 'Real AVM1 ground motion, replacement identity and collision assertions' `
    -TimeoutSeconds $TimeoutSeconds
