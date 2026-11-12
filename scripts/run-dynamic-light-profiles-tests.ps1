[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 300, [switch]$SkipCompile, [string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null

$focusedRun = @{
    DomainId = 'dynamic-light-profiles'
    TemplateRelativePath = 'scripts\test-runners\dynamic-light-profiles\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\render\DynamicLightProfilesTest.as')
    SuiteFqns = @('org.flashNight.arki.render.DynamicLightProfilesTest')
    ExpectedTracePatterns = @('(?m)^DynamicLightProfilesTest invalid=23\r?$','(?m)^DynamicLightProfilesTest Tests Failed: 0\r?$')
    SuccessSummary = '光效配置校验和 23 个错误输入'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$project=Split-Path -Parent $PSScriptRoot
if (-not $EvidenceDirectory) {
    $EvidenceDirectory=Join-Path $project ('tmp/light-authoring/'+[guid]::NewGuid().ToString('N'))
}
& python -B -X utf8 (Join-Path $project 'tools/combat-fx-assets/verify_light_authoring.py') `
    --test-swf (Join-Path $PSScriptRoot 'TestLoader.swf') --compile-trace (Join-Path $PSScriptRoot 'flashlog.txt') --output $EvidenceDirectory
exit $LASTEXITCODE
