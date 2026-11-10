param([int]$TimeoutSeconds=300)
$focused=@{
 DomainId='issue205-probe'
 TemplateRelativePath='scripts/test-runners/issue205-probe/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/neur/Server/Issue205SourceProbeTest.as')
 SuiteFqns=@('org.flashNight.neur.Server.Issue205SourceProbeTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/neur/Server/Issue205SourceProbe.as','scripts/类定义/org/flashNight/neur/Server/QualificationConsoleScope.as')
 ExpectedTracePatterns=@('(?m)^Issue205SourceProbeTest Tests Passed: 14\r?$','(?m)^Issue205SourceProbeTest Tests Failed: 0\r?$')
 SuccessSummary='Issue205 root counters, callback order, plain owner isolation and qualification role admission'
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focused
