[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'bookshelf' `
    -TemplateRelativePath 'scripts/test-runners/bookshelf/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/BookRunRulesTest.as', 'scripts/类定义/org/flashNight/arki/ui/BookshelfPanelServiceTest.as', 'scripts/类定义/org/flashNight/arki/scene/BookIterationTest.as', 'scripts/类定义/org/flashNight/arki/scene/BookComicServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.BookRunRulesTest', 'org.flashNight.arki.ui.BookshelfPanelServiceTest', 'org.flashNight.arki.scene.BookIterationTest', 'org.flashNight.arki.scene.BookComicServiceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/BookDefinition.as', 'scripts/类定义/org/flashNight/arki/scene/BookRunService.as', 'scripts/类定义/org/flashNight/arki/ui/BookshelfPanelService.as', 'scripts/类定义/org/flashNight/arki/scene/BookComicService.as', 'scripts/类定义/org/flashNight/arki/scene/BookRunClock.as') `
    -ExpectedTracePatterns @('(?m)^BookRunRulesTest Tests Passed: 59\r?$', '(?m)^BookRunRulesTest Tests Failed: 0\r?$', '(?m)^BookshelfPanelServiceTest Tests Passed: 86\r?$', '(?m)^BookshelfPanelServiceTest Tests Failed: 0\r?$', '(?m)^BookIterationTest Tests Passed: 22\r?$', '(?m)^BookIterationTest Tests Failed: 0\r?$', '(?m)^BookComicServiceTest Tests Passed: 34\r?$', '(?m)^BookComicServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '201/201 assertions; fixture storage, no physical save claim' -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
