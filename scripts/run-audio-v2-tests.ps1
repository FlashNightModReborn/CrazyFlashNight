[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$projectRoot = Split-Path -Parent $PSScriptRoot

$bridgePath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\audio\AudioBridge.as'
$managerPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\audio\SoundEffectManager.as'
$serverPath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\neur\Server\ServerManager.as'
$messageRouterPath = Join-Path $projectRoot `
    'launcher\src\Bus\MessageRouter.cs'
$suitePath = Join-Path $projectRoot `
    'scripts\类定义\org\flashNight\arki\audio\test\AudioBridgeV2Test.as'

$bridgeSource = [System.IO.File]::ReadAllText($bridgePath)
$managerSource = [System.IO.File]::ReadAllText($managerPath)
$serverSource = [System.IO.File]::ReadAllText($serverPath)
$messageRouterSource = [System.IO.File]::ReadAllText($messageRouterPath)
$suiteSource = [System.IO.File]::ReadAllText($suitePath)

$forbiddenWireTokens = @(
    '"bgm_play"',
    '"bgm_stop"',
    '"bgm_vol"',
    '"bgm_loop"',
    '"master_vol"'
)
foreach ($token in $forbiddenWireTokens) {
    if ($bridgeSource.Contains($token) -or $managerSource.Contains($token)) {
        throw "audio-v2 source policy rejected legacy wire token: $token"
    }
}
if ($bridgeSource -notmatch '_sm\.sendTaskToNode\("audio", request, null\)') {
    throw 'audio-v2 source policy requires ServerManager.sendTaskToNode + FastJSON'
}
if ($bridgeSource -notmatch '"S2\|"') {
    throw 'audio-v2 source policy requires the strict S2 frame prefix'
}
if ($bridgeSource -match '\bconnectionGeneration\s*[:=]' -or
        $managerSource -match '\bconnectionGeneration\s*[:=]') {
    throw 'audio-v2 source policy rejected transport generation in audio state/wire'
}
if ($messageRouterSource -notmatch 'DuplicatePropertyNameHandling\.Error') {
    throw 'audio-v2 source policy requires duplicate-key fail-closed JSON parsing'
}
if ($serverSource -notmatch 'taskType == "audio"' -or
        $serverSource -notmatch 'message\[key\] = payload\[key\]') {
    throw 'audio-v2 source policy requires audio-only flattened task fields'
}
$assertionCount = [regex]::Matches(
    $suiteSource,
    '(?m)^\s*assert(?:True|False|Equal)\(').Count
if ($assertionCount -ne 110) {
    throw "audio-v2 assertion matrix drift: expected 110, found $assertionCount"
}
Write-Host '[OK] audio-v2 strict source policy passed (110 assertions)'

$focusedRun = @{
    DomainId = 'audio-v2'
    TemplateRelativePath = 'scripts\test-runners\audio-v2\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\audio\test\AudioBridgeV2Test.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.audio.test.AudioBridgeV2Test'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\audio\AudioBridge.as'
        'scripts\类定义\org\flashNight\arki\audio\SoundEffectManager.as'
        'scripts\类定义\org\flashNight\neur\Server\ServerManager.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^AudioBridgeV2Test Tests Passed: 110\r?$'
        '(?m)^AudioBridgeV2Test Tests Failed: 0\r?$'
    )
    SuccessSummary = 'AudioBridgeV2Test 110/110'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
