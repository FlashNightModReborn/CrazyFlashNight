[CmdletBinding()]
param([int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'infrastructure-debt' `
    -TemplateRelativePath 'scripts/test-runners/infrastructure-debt/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/dev/InfrastructureDebtTest.as', 'scripts/类定义/org/flashNight/dev/InventorySortDebtTest.as', 'scripts/类定义/org/flashNight/dev/ProductionDomainDebtTest.as') `
    -SuiteFqns @('org.flashNight.dev.InfrastructureDebtTest', 'org.flashNight.dev.InventorySortDebtTest', 'org.flashNight.dev.ProductionDomainDebtTest') `
    -ExpectedTracePatterns @('(?m)^InfrastructureDebtTest passed=10 failed=0\r?$', '(?m)^InventorySortDebtTest passed=[1-9][0-9]* failed=0\r?$', '(?m)^ProductionDomainDebtTest passed=[1-9][0-9]* failed=0\r?$') `
    -SuccessSummary 'Infrastructure dependency tests and real Flash scheduler baseline' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile -AutoStopReadOnlyPlayer
