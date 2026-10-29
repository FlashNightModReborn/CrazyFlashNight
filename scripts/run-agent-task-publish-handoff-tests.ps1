[CmdletBinding()]
param(
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 300,
    [switch]$SkipCompile
)
$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'agent-task-publish-handoff'
    TemplateRelativePath = 'scripts\test-runners\agent-task-publish-handoff\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\task\AgentTaskPublishHandoffTest.as'
    )
    SuiteFqns = @('org.flashNight.arki.task.AgentTaskPublishHandoffTest')
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\task\AgentTaskPublishHandoff.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^AgentTaskPublishHandoffTest Tests Passed: 58\r?$',
        '(?m)^AgentTaskPublishHandoffTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'Agent task publish handoff 58/58 covering validation, version gate, reload, token idempotency and fallback tips'
    TimeoutSeconds = $TimeoutSeconds
    AsyncBehaviorTimeoutSeconds = 90
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
exit $LASTEXITCODE
