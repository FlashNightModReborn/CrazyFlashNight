[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'tooltip-book-shop-filter' `
    -TemplateRelativePath 'scripts/test-runners/tooltip-book-shop-filter/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/gesh/tooltip/TooltipBookShopFilterTest.as') `
    -SuiteFqns @('org.flashNight.gesh.tooltip.TooltipBookShopFilterTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/gesh/tooltip/TooltipInputProjection.as', 'scripts/类定义/org/flashNight/arki/item/obtain/ItemObtainIndex.as', 'scripts/类定义/org/flashNight/arki/item/ItemUtil.as') `
    -ExpectedTracePatterns @('(?m)^TooltipBookShopFilterTest Tests Passed: 4\r?$', '(?m)^TooltipBookShopFilterTest Tests Failed: 0\r?$') `
    -SuccessSummary '4/4 tooltip source filters; all book shops hidden, ordinary NPC sources preserved' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
