[CmdletBinding()]
param([int]$TimeoutSeconds = 600, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'array-inventory-query-benchmark' `
    -TemplateRelativePath 'scripts/test-runners/array-inventory-query-benchmark/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/dev/ArrayInventoryQueryBenchmark.as') `
    -SuiteFqns @('org.flashNight.dev.ArrayInventoryQueryBenchmark') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/dev/ArrayInventoryTreeBaseline.as', 'scripts/类定义/org/flashNight/dev/ArrayInventoryLinearProbe.as', 'scripts/类定义/org/flashNight/dev/ArrayInventoryCachedProbe.as', 'scripts/类定义/org/flashNight/dev/ArrayInventoryIncrementalProbe.as', 'scripts/逻辑系统分区/商店系统_兼容.as') `
    -ExpectedTracePatterns @('(?m)^ArrayInventoryQueryBenchmark rows=184 passed=2024 failed=0\r?$') `
    -SuccessSummary '184 AVM1 query/churn scenarios, 5 rotated repeats, semantic equality and raw timing rows' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
