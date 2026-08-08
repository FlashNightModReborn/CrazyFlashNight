[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'

$focusedRun = @{
    DomainId = 'kshop-checkout'
    TemplateRelativePath = 'scripts\test-runners\kshop-checkout\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\KShopCheckoutServiceTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.item.KShopCheckoutServiceTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\逻辑系统分区\商城系统_WebView.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^KShopCheckoutServiceTest Tests Passed: 28\r?$'
        '(?m)^KShopCheckoutServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'KShopCheckoutServiceTest 28/28'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
