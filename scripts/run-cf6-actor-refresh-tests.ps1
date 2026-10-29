[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
 -DomainId 'cf6-actor-refresh' `
 -TemplateRelativePath 'scripts/test-runners/cf6-actor-refresh/TestLoader.as.template' `
 -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ActorRefreshPolicyTest.as') `
 -SuiteFqns @('org.flashNight.arki.scene.Cf6ActorRefreshPolicyTest') `
 -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ActorRefreshPolicy.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as','scripts/类定义/org/flashNight/gesh/depth/DepthManager.as') `
 -ExpectedTracePatterns @('(?m)^Cf6ActorRefreshPolicyTest Tests Passed: 18\r?$','(?m)^Cf6ActorRefreshPolicyTest Tests Failed: 0\r?$') `
 -SuccessSummary 'Real AVM1 depth-conflict reproduction and read-only equipment admission; no save or full-route claim' `
 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
