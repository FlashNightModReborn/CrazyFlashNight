[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'input-isolation-normal' `
    -TemplateRelativePath 'scripts/test-runners/input-isolation-normal/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/input/IsolatedInputPolicyNormalTest.as') `
    -SuiteFqns @('org.flashNight.arki.input.IsolatedInputPolicyNormalTest') `
    -ExpectedTracePatterns @('(?m)^IsolatedInputPolicyNormalTest Tests Passed: 11\r?$', '(?m)^IsolatedInputPolicyNormalTest Tests Failed: 0\r?$') `
    -SuccessSummary '11/11 normal-driver assertions' -TimeoutSeconds $TimeoutSeconds
