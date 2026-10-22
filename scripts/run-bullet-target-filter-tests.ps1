[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'bullet-target-filter' `
    -TemplateRelativePath 'scripts/test-runners/bullet-target-filter/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletTargetFilterTest.as') `
    -SuiteFqns @('org.flashNight.arki.bullet.BulletComponent.Queue.BulletTargetFilterTest') `
    -ExpectedTracePatterns @('(?m)^BulletTargetFilterTest Tests Passed: 17?$', '(?m)^BulletTargetFilterTest Tests Failed: 0?$') `
    -SuccessSummary '17/17 assertions (static count r18, confirm on fresh run); injectHit fail-closed + real processQueue main-loop fixture (probe + contract stubs)' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
