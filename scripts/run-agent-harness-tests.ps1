[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'agent-harness' `
    -TemplateRelativePath 'scripts/test-runners/agent-harness/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/neur/Server/test/AgentHarnessServiceTest.as') `
    -SuiteFqns @('org.flashNight.neur.Server.test.AgentHarnessServiceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/neur/Server/AgentHarnessService.as', 'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as') `
    -ExpectedTracePatterns @(
        '(?m)^AgentHarnessServiceTest Tests Passed: (?<n>[1-9][0-9]*)\r?$',
        '(?m)^AgentHarnessServiceTest Tests Failed: 0\r?$'
    ) `
    -SuccessSummary 'AgentHarnessServiceTest passed' -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
