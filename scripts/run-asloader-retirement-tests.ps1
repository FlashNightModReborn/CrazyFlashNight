[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 900, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'asloader-retirement' `
    -TemplateRelativePath 'scripts/test-runners/asloader-retirement/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/interaction/NativeTooltipBridgeTest.as','scripts/类定义/org/flashNight/arki/item/InventoryTooltipProjectionTest.as') `
    -SuiteFqns @('org.flashNight.arki.interaction.NativeTooltipBridgeTest','org.flashNight.arki.item.InventoryTooltipProjectionTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/gesh/tooltip/TooltipInputProjection.as','scripts/类定义/org/flashNight/gesh/tooltip/NativeTooltipBridge.as') `
    -ExpectedTracePatterns @('(?m)^--- NativeTooltipBridgeTest: (?<bridge>[1-9][0-9]*)/\k<bridge> passed, 0 failed ---\r?$','(?m)^InventoryTooltipProjectionTest Tests Passed: [1-9]\d*\r?$','(?m)^InventoryTooltipProjectionTest Tests Failed: 0\r?$') `
    -SuccessSummary 'native owner/anchor lifecycle and real instance input projection; content rules tested by Launcher TS' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
