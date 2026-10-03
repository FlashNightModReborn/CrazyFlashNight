[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'choice-rewards' `
    -TemplateRelativePath 'scripts/test-runners/choice-rewards/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/item/ChoiceRewardServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.item.ChoiceRewardServiceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/item/ChoiceRewardDefinition.as', 'scripts/类定义/org/flashNight/arki/item/ChoiceRewardStore.as', 'scripts/类定义/org/flashNight/arki/item/ChoiceRewardService.as') `
    -ExpectedTracePatterns @('(?m)^ChoiceRewardServiceTest Tests Passed: 41\r?$', '(?m)^ChoiceRewardServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '41/41 choice reward assertions; isolated fixture storage' -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
