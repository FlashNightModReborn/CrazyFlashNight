[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Assert-Contains(
        [string]$Text, [string]$Needle, [string]$Message) {
    if (-not $Text.Contains($Needle)) { throw $Message }
}

function Assert-Matches(
        [string]$Text, [string]$Pattern, [string]$Message) {
    if (-not [regex]::IsMatch(
            $Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        throw $Message
    }
}

function Assert-NotMatches(
        [string]$Text, [string]$Pattern, [string]$Message) {
    if ([regex]::IsMatch(
            $Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        throw $Message
    }
}

function Get-SourceSection(
        [string]$Text, [string]$StartNeedle, [string]$EndNeedle) {
    $start = $Text.IndexOf($StartNeedle, [System.StringComparison]::Ordinal)
    $end = $Text.IndexOf($EndNeedle, $start + $StartNeedle.Length,
        [System.StringComparison]::Ordinal)
    if ($start -lt 0 -or $end -le $start) {
        throw "Source boundary missing: $StartNeedle -> $EndNeedle"
    }
    return $Text.Substring($start, $end - $start)
}

$projectDir = Split-Path -Parent $PSScriptRoot
$sceneDir = Join-Path $PSScriptRoot '类定义\org\flashNight\arki\scene'
$stageManagerPath = Join-Path $sceneDir 'StageManager.as'
$runSessionPath = Join-Path $sceneDir 'StageRunSession.as'
$warlordRunnerPath = Join-Path $sceneDir 'WarlordSubStageRunner.as'
$actionServicePath = Join-Path $sceneDir 'WarlordActionEncounterService.as'
$coordinatorTestPath = Join-Path $sceneDir 'StageSubStageCoordinatorTest.as'
$legacyCoordinatorPath = Join-Path $sceneDir 'StageSubStageCoordinator.as'
$legacyActionRunnerPath = Join-Path $sceneDir 'ActionEncounterRunner.as'
$arenaCalibrationPath = Join-Path $PSScriptRoot `
    '类定义\org\flashNight\arki\merc\ArenaCalibrationService.as'
$xmlParserPath = Join-Path $PSScriptRoot '通信\通信_fs_lsy_XML数据解析.as'
$stageXmlPath = Join-Path $projectDir 'data\stages\副本任务\军阀战术演习.xml'
$stageListPath = Join-Path $projectDir 'data\stages\副本任务\__list__.xml'

foreach ($legacyPath in @($legacyCoordinatorPath, $legacyActionRunnerPath)) {
    if (Test-Path -LiteralPath $legacyPath) {
        throw "PREFER_B forbids the retired lifecycle owner: $legacyPath"
    }
}

$stageManager = Read-Utf8 $stageManagerPath
$runSession = Read-Utf8 $runSessionPath
$warlordRunner = Read-Utf8 $warlordRunnerPath
$actionService = Read-Utf8 $actionServicePath
$coordinatorTest = Read-Utf8 $coordinatorTestPath
$arenaCalibration = Read-Utf8 $arenaCalibrationPath
$xmlParser = Read-Utf8 $xmlParserPath

# StageManager owns both the outer runner and the one inner Action slot. No
# coordinator or Action runner may sit between it and canonical frame-209.
foreach ($sentinel in @(
        'private var warlordRunner:WarlordSubStageRunner',
        'private var warlordActionSlot:Object',
        'new WarlordSubStageRunner(',
        'warlordRunner.start()',
        'public function onWarlordSubStageTerminal(',
        'public function onWarlordSubStageFrozen(',
        'public function onWarlordSubStageStartFailed(',
        'public function beginWarlordActionEncounter(')) {
    Assert-Contains $stageManager $sentinel `
        "StageManager direct-owner sentinel missing: $sentinel"
}
foreach ($text in @($stageManager, $warlordRunner, $actionService)) {
    Assert-NotMatches $text '\b(ActionEncounterRunner|StageSubStageCoordinator)\b' `
        'A retired Warlord lifecycle owner is still referenced.'
}

$driverValidation = Get-SourceSection $stageManager `
    'private function validateStageDrivers' `
    'private static function isValidWarlordActionBinding'
foreach ($sentinel in @(
        'stageMode = "action"',
        'stageMode = "warlord"',
        'mixed or multi-Warlord GameStage is not supported',
        'invalid exact Warlord SubStage contract')) {
    Assert-Contains $driverValidation $sentinel `
        "StageManager driver split sentinel missing: $sentinel"
}
if (-not $stageManager.Contains('stageInfoList[i] = new StageInfo(data[i]);') -or
        -not $stageManager.Contains('stageInfoList = [null];') -or
        -not $stageManager.Contains('Warlord SubStage does not accept TimePools')) {
    throw 'Action StageInfo and no-TimePool Warlord initialization boundaries drifted.'
}
$initStage = Get-SourceSection $stageManager `
    'public function initStage():Void' `
    'private function initializeStageWorld'
$warlordBranch = $initStage.IndexOf(
    'if (stageMode == "warlord")', [System.StringComparison]::Ordinal)
$normalWorldInit = $initStage.IndexOf(
    'initializeStageWorld(stageInfoList[currentStage], false)',
    [System.StringComparison]::Ordinal)
if ($warlordBranch -lt 0 -or $normalWorldInit -le $warlordBranch) {
    throw 'Warlord outer start must branch before normal StageInfo world setup.'
}
if (-not $stageManager.Contains('StageRunSession.getCurrentRunId()') -or
        -not $runSession.Contains('public static function getCurrentRunId():String')) {
    throw 'Warlord outer binding no longer fences to the active parent runId.'
}

# WarlordSubStageRunner is the only outer wire owner.
foreach ($sentinel in @(
        'warlord_stage_start',
        'warlord_stage_result',
        'warlord_stage_outer_cancelled',
        'warlord.stage-outer-binding.v1',
        'warlord.stage-outer-terminal.v1',
        'warlord.stage-outer-attempt.v1',
        'warlord.stage-outer-cancellation.v1',
        'target.sendTaskToNode(START_TASK, {',
        'playerAvatarPortrait:clonePlayerAvatarPortrait(',
        '_root.gameCommands[RESULT_ACTION] = resultHandler',
        'command.action !== RESULT_ACTION',
        'notifyObserver("onWarlordSubStageTerminal"',
        'notifyObserver("onWarlordSubStageFrozen"',
        'notifyObserver("onWarlordSubStageStartFailed"',
        'public function publishOuterCancellation(',
        'private function failNotStarted(')) {
    Assert-Contains $warlordRunner $sentinel `
        "WarlordSubStageRunner wire sentinel missing: $sentinel"
}
$outerCancellationBody = Get-SourceSection $warlordRunner `
    'public function publishOuterCancellation(reasonCode:String):Boolean' `
    'public function dispose():Void'
Assert-Matches $outerCancellationBody `
    'sendTaskToNode\(OUTER_CANCELLATION_TASK,\s*\{\s*schema:OUTER_CANCELLATION_SCHEMA,\s*binding:cloneBinding\(binding\),\s*reasonCode:reasonCode\s*\},\s*null\)\s*===\s*true' `
    'Outer cancellation must send exactly schema, cloned six-key binding, and reasonCode.'
foreach ($forbiddenPattern in @(
        'public\s+function\s+retrySameBinding\s*\(',
        'public\s+function\s+reopenFrozen\s*\(',
        'public\s+function\s+canRetry\s*\(',
        'public\s+function\s+canReopen\s*\(',
        '_root\.gameCommands\["warlord_stage_(retry|reopen)"\]')) {
    Assert-NotMatches $warlordRunner $forbiddenPattern `
        "Outer runner regained a removed resurrection surface: $forbiddenPattern"
}

# A synchronous bridge callback is authoritative over send=false/throw. start
# preclaims awaiting; a true transport miss becomes a terminal startup failure
# without another generation or player-visible retry.
$startBody = Get-SourceSection $warlordRunner `
    'public function start():Boolean' `
    'public function handleResult(payload:Object):Object'
$startAwait = $startBody.IndexOf('phase = "awaiting_terminal";',
    [System.StringComparison]::Ordinal)
$startSend = $startBody.IndexOf('sendBinding(binding)',
    [System.StringComparison]::Ordinal)
$startWinner = $startBody.IndexOf(
    'if (delivered || phase != "awaiting_terminal") return true;',
    [System.StringComparison]::Ordinal)
$startFailure = $startBody.IndexOf(
    'failNotStarted("stage.transport-not-started", null);',
    [System.StringComparison]::Ordinal)
if ($startAwait -lt 0 -or $startSend -le $startAwait -or
        $startWinner -le $startSend -or $startFailure -le $startWinner) {
    throw 'start() must preclaim awaiting, preserve a synchronous result, then fail a true transport miss.'
}
$failureBody = Get-SourceSection $warlordRunner `
    'private function failNotStarted(reasonCode:String, attempt:Object):Void' `
    'private static function createBinding'
foreach ($sentinel in @(
        'phase = "terminal";',
        'result:"not_started"',
        'notifyObserver("onWarlordSubStageStartFailed", failure);',
        'removeResultHandler();')) {
    Assert-Contains $failureBody $sentinel `
        "Terminal startup-failure sentinel missing: $sentinel"
}

# not_started fails the parent run. Suspended/Unknown preserve their technical
# frozen fact but expose no retry/reopen lifecycle.
$frozenBody = Get-SourceSection $stageManager `
    'public function onWarlordSubStageFrozen' `
    'public function onWarlordSubStageStartFailed'
if ($frozenBody.Contains('reopenFrozen()') -or
        $frozenBody.Contains('retrySameBinding()')) {
    throw 'Suspended/Unknown must not create a reopen or retry loop.'
}
$startFailedBody = Get-SourceSection $stageManager `
    'public function onWarlordSubStageStartFailed' `
    'public function beginWarlordActionEncounter'
foreach ($sentinel in @(
        'isFailed = true;',
        'StageRunSession.finish("failure");',
        'hideNativeStageUiBestEffort();')) {
    Assert-Contains $startFailedBody $sentinel `
        "not_started parent-failure sentinel missing: $sentinel"
}
Assert-NotMatches $stageManager `
    '\b(retryWarlordSubStage|reopenWarlordSubStage|requestWarlordRecovery)\b' `
    'StageManager regained a removed recovery entry point.'

# Canonical parent return-base authorizes clear in StageRunSession, after which
# every inner Action phase is cancelled through one phase-independent slot branch.
$clearBody = Get-SourceSection $stageManager `
    'public function clear():Void' `
    'public function getTimePoolValidationError'
$clearGate = $clearBody.IndexOf('StageRunSession.canClearStageManager()',
    [System.StringComparison]::Ordinal)
$clearCancel = $clearBody.IndexOf('.cancelForStageExit()', $clearGate,
    [System.StringComparison]::Ordinal)
$clearNull = $clearBody.IndexOf('warlordActionSlot = null;', $clearCancel,
    [System.StringComparison]::Ordinal)
if ($clearGate -lt 0 -or $clearCancel -le $clearGate -or
        $clearNull -le $clearCancel) {
    throw 'Authorized clear must cancel and clear the one inner Action slot.'
}
if ($clearBody.Substring($clearGate, $clearNull - $clearGate).Contains(
        'warlordActionSlot.phase')) {
    throw 'entering/active/returning slots must all use the canonical clear path.'
}
Assert-Contains $clearBody `
    'publishWarlordActionCancellation("parent_return_base")' `
    'A present Action slot must still receive its independent cancellation.'
Assert-Matches $clearBody `
    'retireWarlordRunnerBestEffort\(\s*clearedWarlordRunner,\s*"stage\.parent-return-base"\s*\);' `
    'Clear must publish outer cancellation even when no Action slot exists.'

$retireBody = Get-SourceSection $stageManager `
    'private function retireWarlordRunnerBestEffort(' `
    'private function leaveTimePoolBestEffort'
$outerSend = $retireBody.IndexOf('runner.publishOuterCancellation(reasonCode)',
    [System.StringComparison]::Ordinal)
$runnerDispose = $retireBody.IndexOf('runner.dispose();',
    [System.StringComparison]::Ordinal)
if ($outerSend -lt 0 -or $runnerDispose -le $outerSend) {
    throw 'StageManager must best-effort publish exact outer cancellation before runner disposal.'
}

$failureCleanup = Get-SourceSection $stageManager `
    'private function finalizeInitStageFailureCleanup():Void' `
    'private function preserveFailedStageForReturnRetry():Void'
Assert-Matches $failureCleanup `
    'retireWarlordRunnerBestEffort\(\s*failedWarlordRunner,\s*"stage\.parent-setup-failed"\s*\);' `
    'Setup-failure cleanup must retire the exact outer owner.'
$disposeBody = Get-SourceSection $stageManager `
    'public function dispose():Void' `
    'public function reset():Void'
Assert-Matches $disposeBody `
    'retireWarlordRunnerBestEffort\(\s*disposedWarlordRunner,\s*"stage\.parent-restart"\s*\);' `
    'Restart disposal must retire the exact outer owner.'

# StageRunSession retains only generic stage_outcome v1; neither outer Warlord
# recovery nor an inner Action sub-session owns another lifecycle.
foreach ($forbidden in @(
        'warlord.stage-recovery-projection.v1',
        'warlordStageRecoverySync',
        'warlord_stage_recovery',
        'validateWarlordRecoveryAction',
        'requestWarlordRecoveryReturnBaseLocal',
        'reserveActionEncounter',
        'markActionEncounterWorldStarted',
        'releaseActionEncounterNotStarted',
        'abandonActionEncounterNotStarted',
        'completeActionEncounterTeardown',
        '_actionEncounterLease',
        'hasActiveActionEncounter',
        'getActionEncounterSnapshot',
        'testOnlyReleaseStageExitSafeFrozenActionEncounter')) {
    if ($runSession.Contains($forbidden)) {
        throw "StageRunSession regained inner Action authority: $forbidden"
    }
}

if (-not $xmlParser.Contains('data.TimePools == null') -or
        -not $xmlParser.Contains('managerInitialized = stageManager.initialize(') -or
        -not $xmlParser.Contains('data.SubStage, timePoolData, stageStartToken,')) {
    throw 'GameStage XML loader no longer passes direct SubStage data to StageManager.'
}

[xml]$stageXml = Read-Utf8 $stageXmlPath
if ($stageXml.DocumentElement.Name -ne 'GameStage') {
    throw 'Warlord tutorial fixture root must be GameStage.'
}
$subStages = @($stageXml.SelectNodes('/GameStage/SubStage'))
if ($subStages.Count -ne 1) {
    throw 'Warlord tutorial GameStage must contain one direct SubStage.'
}
$subStage = $subStages[0]
$attributeNames = @($subStage.Attributes | ForEach-Object { $_.Name } | Sort-Object)
if (($attributeNames -join ',') -ne 'driver,id,scenarioRef' -or
        $subStage.GetAttribute('id') -cne 'warlord_tutorial' -or
        $subStage.GetAttribute('driver') -cne 'Warlord' -or
        $subStage.GetAttribute('scenarioRef') -cne 'warlord_tutorial_v1' -or
        $stageXml.SelectSingleNode('/GameStage/TimePools') -ne $null) {
    throw 'Warlord tutorial fixture must remain the exact no-TimePool contract.'
}

[xml]$stageList = Read-Utf8 $stageListPath
$listEntries = @($stageList.SelectNodes(
    "/Stages/StageInfo[Name='军阀战术演习']"))
if ($listEntries.Count -ne 1 -or
        $listEntries[0].Type -ne '无限过图' -or
        $listEntries[0].FadeTransitionFrame -ne 'wuxianguotu_1') {
    throw 'Warlord tutorial fixture must have one normal GameStage list entry.'
}

foreach ($testSentinel in @(
        'passed != 78',
        'restart publishes the dedicated outer cancellation task',
        'outer cancellation carries the exact six-key binding',
        'setup failure can best-effort publish the same exact owner',
        'synchronous start result wins over transport false',
        'synchronous business terminal wins over transport throw',
        'startup failure cannot be replayed into a retry',
        'frozen runner exposes no resurrection surface',
        'Unknown cannot create a recovery generation',
        'recovery sync command is absent',
        'generic stage_outcome v1 projection remains available',
        'removed v2 intent has zero authority effect',
        'AS2 never emits the removed recovery task',
        'all five Demo 1 four-unit formations are observably distinct',
        'distance 180 keeps every 2-4 unit formation safe and non-overlapping',
        'distance 650 keeps every 2-4 unit formation safe and non-overlapping',
        'onWarlordSubStageTerminal',
        'onWarlordSubStageFrozen',
        'onWarlordSubStageStartFailed')) {
    Assert-Contains $coordinatorTest $testSentinel `
        "Warlord substage regression sentinel missing: $testSentinel"
}
if (-not $arenaCalibration.Contains(
        'public static function testOnlyProjectFormation') -or
        -not $arenaCalibration.Contains(
            'public static function testOnlyProjectArenaDeployment') -or
        -not $arenaCalibration.Contains('total >= 2 && total <= 4')) {
    throw 'Small-roster formation projection test surface drifted.'
}

$commonRunner = Join-Path $PSScriptRoot `
    'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'warlord-substage'
    TemplateRelativePath = `
        'scripts\test-runners\warlord-substage\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\scene\StageSubStageCoordinatorTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.scene.StageSubStageCoordinatorTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\scene\WarlordSubStageRunner.as'
        'scripts\类定义\org\flashNight\arki\scene\WarlordActionEncounterService.as'
        'scripts\类定义\org\flashNight\arki\scene\StageRunSession.as'
        'scripts\类定义\org\flashNight\arki\scene\StageManager.as'
        'scripts\类定义\org\flashNight\arki\merc\ArenaCalibrationService.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^StageSubStageCoordinatorTest Tests Passed: 78\r?$'
        '(?m)^StageSubStageCoordinatorTest Tests Failed: 0\r?$'
        '(?m)^StageSubStageCoordinatorTest Cases Passed: 10/10\r?$'
    )
    SuccessSummary = '78/78 assertions, 10/10 cases'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
