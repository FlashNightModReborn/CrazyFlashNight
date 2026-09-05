[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'

$frameTickerPath = Join-Path $PSScriptRoot '通信\通信_fs_帧计时器.as'
$stageManagerPath = Join-Path $PSScriptRoot '类定义\org\flashNight\arki\scene\StageManager.as'
$xmlParserPath = Join-Path $PSScriptRoot '通信\通信_fs_lsy_XML数据解析.as'
$frameTicker = [System.IO.File]::ReadAllText(
    $frameTickerPath,
    [System.Text.Encoding]::UTF8)
$stageManager = [System.IO.File]::ReadAllText(
    $stageManagerPath,
    [System.Text.Encoding]::UTF8)
$xmlParser = [System.IO.File]::ReadAllText(
    $xmlParserPath,
    [System.Text.Encoding]::UTF8)
$waveTickIndex = $frameTicker.IndexOf(
    'WaveSpawner.instance.tick();',
    [System.StringComparison]::Ordinal)
$stageTickIndex = $frameTicker.IndexOf(
    'StageManager.instance.tick();',
    [System.StringComparison]::Ordinal)
if ($waveTickIndex -lt 0 -or $stageTickIndex -le $waveTickIndex) {
    throw 'same-frame arbitration drift: WaveSpawner.tick must precede StageManager.tick.'
}
if (-not $stageManager.Contains(
        'if (!isActive || isCleared || isFinished || isFailed') -or
        -not $stageManager.Contains(
            'if (expiredPoolId != null && !isCleared && !isFinished && !isFailed)')) {
    throw 'same-frame arbitration drift: StageManager terminal guards are missing.'
}
if (-not $xmlParser.Contains('data.TimePools == null') -or
        -not $xmlParser.Contains('managerInitialized = stageManager.initialize(') -or
        -not $xmlParser.Contains('data.SubStage, timePoolData, stageStartToken,')) {
    throw 'GameStage XML TimePools wiring drifted from the focused contract.'
}

$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'stage-time-pool'
    TemplateRelativePath = 'scripts\test-runners\stage-time-pool\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\scene\StageTimePoolControllerTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.scene.StageTimePoolControllerTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^StageTimePoolControllerTest Tests Passed: 46\r?$'
        '(?m)^StageTimePoolControllerTest Tests Failed: 0\r?$'
        '(?m)^StageTimePoolControllerTest Cases Passed: 8/8\r?$'
    )
    SuccessSummary = '46/46 assertions, 8/8 cases'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
