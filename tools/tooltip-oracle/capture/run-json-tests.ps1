param([Parameter(Mandatory=$true)][string]$BaselineRoot)
$ErrorActionPreference = 'Stop'
$candidateRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$baseline = (Resolve-Path -LiteralPath $BaselineRoot).Path
if ($baseline -ieq $candidateRoot) { throw 'Capture JSON tests require an isolated baseline.' }
if (-not (Test-Path -LiteralPath (Join-Path $baseline '.git') -PathType Leaf)) {
    throw 'Use a linked isolated baseline worktree, not the primary checkout.'
}
foreach ($marker in @('compile_state_uncertain.marker','testloader_scratch_inflight.marker','testplayer_control.cfg')) {
    if (Test-Path -LiteralPath (Join-Path $baseline ('scripts\' + $marker))) {
        throw ('Unresolved baseline state blocks fixture installation: ' + $marker)
    }
}
$expectedCommit = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json).sourceCommit
if ((git -C $baseline rev-parse HEAD) -cne $expectedCommit) { throw 'Unexpected baseline commit.' }
$suiteRelative = 'scripts/类定义/org/flashNight/gesh/tooltip/test/TooltipCaptureJson.as'
$fixtureRelative = 'tmp/tooltip-capture-json/TestLoader.as.template'
$fixture = Join-Path $baseline $fixtureRelative
New-Item -ItemType Directory -Path (Split-Path -Parent $fixture) -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'as2\org\flashNight\gesh\tooltip\test\TooltipCaptureJson.as') -Destination (Join-Path $baseline $suiteRelative) -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'json-TestLoader.as.template') -Destination $fixture -Force
$parameters = @{
    DomainId = 'tooltip-capture-json'
    TemplateRelativePath = $fixtureRelative
    SuiteRelativePaths = @($suiteRelative)
    SuiteFqns = @('org.flashNight.gesh.tooltip.test.TooltipCaptureJson')
    ExpectedTracePatterns = @('CAPTURE_JSON_MATCH\|true')
    SuccessSummary = 'Capture JSON matches baseline LiteJSON in fresh AVM1 execution.'
    TimeoutSeconds = 240
}
& (Join-Path $baseline 'scripts\test-runners\run-focused-testloader.ps1') @parameters
exit $LASTEXITCODE
