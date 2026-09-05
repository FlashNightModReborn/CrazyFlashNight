[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile,
    # 同轮 ControlWireMatrix_ActualParticipantsOwnControl 的八份实际发包。
    [string]$HostWireFixtureDirectory = ''
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

function Assert-OrderedContains(
        [string]$Text, [string[]]$Needles, [string]$Message) {
    $cursor = 0
    foreach ($needle in $Needles) {
        $index = $Text.IndexOf(
            $needle, $cursor, [System.StringComparison]::Ordinal)
        if ($index -lt 0) {
            throw "$Message Missing or out of order: $needle"
        }
        $cursor = $index + $needle.Length
    }
}

$sceneDir = Join-Path $PSScriptRoot '类定义\org\flashNight\arki\scene'
$runSessionPath = Join-Path $sceneDir 'StageRunSession.as'
$stageManagerPath = Join-Path $sceneDir 'StageManager.as'
$actionServicePath = Join-Path $sceneDir 'WarlordActionEncounterService.as'
$warlordRunnerPath = Join-Path $sceneDir 'WarlordSubStageRunner.as'
$actionTestPath = Join-Path $sceneDir 'ActionEncounterRunnerTest.as'
$updateEventPath = Join-Path $PSScriptRoot `
    '类定义\org\flashNight\arki\unit\UnitComponent\Initializer\EventComponent\UpdateEventComponent.as'
$arenaBridgePath = Join-Path $PSScriptRoot '逻辑系统分区\竞技场系统_WebView.as'
$legacyRunnerPath = Join-Path $sceneDir 'ActionEncounterRunner.as'
$legacyCoordinatorPath = Join-Path $sceneDir 'StageSubStageCoordinator.as'

foreach ($legacyPath in @($legacyRunnerPath, $legacyCoordinatorPath)) {
    if (Test-Path -LiteralPath $legacyPath) {
        throw "PREFER_B forbids the retired lifecycle owner: $legacyPath"
    }
}

$runSession = Read-Utf8 $runSessionPath
$stageManager = Read-Utf8 $stageManagerPath
$actionService = Read-Utf8 $actionServicePath
$warlordRunner = Read-Utf8 $warlordRunnerPath
$actionTest = Read-Utf8 $actionTestPath
$updateEvent = Read-Utf8 $updateEventPath
$arenaBridge = Read-Utf8 $arenaBridgePath

# StageManager is the sole physical-scene owner. Its temporary Action slot is
# admitted before the canonical fade and consumed by the normal frame-209 path.
foreach ($sentinel in @(
        'private var warlordRunner:WarlordSubStageRunner',
        'private var warlordActionSlot:Object',
        'new WarlordSubStageRunner(',
        'public function beginWarlordActionEncounter(',
        'WarlordActionEncounterService.prepareCombat(binding, control)',
        '.cancelPreparedCombat(binding)',
        'WarlordActionEncounterService.activateCombat(',
        '.releaseCombatForReturn(binding)',
        '.completeCombatReturn(binding)',
        '.deliverTerminal(terminal)',
        'initializeStageWorld(slot.stageInfo, true)',
        'fade.淡出跳转帧(WARLORD_ACTION_SCENE_LINKAGE)')) {
    Assert-Contains $stageManager $sentinel `
        "StageManager sole-owner sentinel missing: $sentinel"
}
Assert-Matches $stageManager `
    'WARLORD_ACTION_BINDING_KEYS:Array\s*=\s*\[\s*"schema"\s*,\s*"outerRunId"\s*,\s*"encounterId"\s*,\s*"requestId"\s*,\s*"inputDigest"\s*\]' `
    'StageManager must validate the exact five-key Action binding.'
Assert-Matches $stageManager `
    'WARLORD_ACTION_TERMINAL_KEYS:Array\s*=\s*\[\s*"schema"\s*,\s*"outerRunId"\s*,\s*"encounterId"\s*,\s*"requestId"\s*,\s*"inputDigest"\s*,\s*"status"\s*,\s*"reasonCode"\s*,\s*"result"\s*\]' `
    'StageManager must validate the exact eight-key Action terminal.'
Assert-Contains $stageManager `
    '"warlord.action-encounter-cancellation.v1"' `
    'StageManager must own the exact cancellation v1 schema.'
Assert-Contains $stageManager `
    '"warlord_action_encounter_cancelled"' `
    'StageManager must own the exact cancellation transport task.'
Assert-Matches $stageManager `
    'WARLORD_OUTER_BINDING_KEYS:Array\s*=\s*\[\s*"schema"\s*,\s*"runId"\s*,\s*"subStageId"\s*,\s*"scenarioRef"\s*,\s*"callId"\s*,\s*"revision"\s*\]' `
    'StageManager must validate the exact six-key stageOuterBinding v1 identity.'
Assert-Contains $warlordRunner `
    'BINDING_SCHEMA:String = "warlord.stage-outer-binding.v1"' `
    'WarlordSubStageRunner must remain the stageOuterBinding v1 schema owner.'
Assert-Matches $stageManager `
    'var payload:Object\s*=\s*\{\s*schema:WARLORD_ACTION_CANCELLATION_SCHEMA\s*,\s*actionBinding:cloneWarlordActionBinding\(slot\.binding\)\s*,\s*stageOuterBinding:ObjectUtil\.clone\(outerBinding\)\s*,\s*reasonCode:reasonCode\s*\};' `
    'Cancellation v1 payload must have exactly schema, actionBinding, stageOuterBinding, and reasonCode.'
Assert-Matches $stageManager `
    'if \(!sameWarlordOuterBinding\(outerBinding, outerBinding\)\s*\|\|\s*outerBinding\.runId !== slot\.binding\.outerRunId\)' `
    'Cancellation must exact-validate stageOuterBinding v1 and bind it to actionBinding v2.'
Assert-Matches $stageManager `
    'server\.sendTaskToNode\(\s*WARLORD_ACTION_CANCELLATION_TASK\s*,\s*payload\s*,\s*null\s*\) === true' `
    'StageManager cancellation publisher must synchronously send the exact v1 payload.'

$initStart = $stageManager.IndexOf(
    'public function initStage():Void', [System.StringComparison]::Ordinal)
$stageIncrement = $stageManager.IndexOf(
    'currentStage++;', $initStart, [System.StringComparison]::Ordinal)
$actionReentry = $stageManager.IndexOf(
    'if (warlordActionSlot != null)', $initStart,
    [System.StringComparison]::Ordinal)
$actionReentryReturn = $stageManager.IndexOf(
    'return;', $actionReentry, [System.StringComparison]::Ordinal)
if ($initStart -lt 0 -or $actionReentry -le $initStart -or
        $actionReentryReturn -le $actionReentry -or
        $stageIncrement -le $actionReentryReturn) {
    throw 'Inner Action frame-209 reentry must return before currentStage++.'
}

$actionInspectStart = $stageManager.IndexOf(
    'public function inspectWarlordActionEncounter',
    [System.StringComparison]::Ordinal)
$actionStart = $stageManager.IndexOf(
    'public function beginWarlordActionEncounter',
    [System.StringComparison]::Ordinal)
$actionEnd = $stageManager.IndexOf(
    'private function initWarlordActionStage():Void', $actionStart,
    [System.StringComparison]::Ordinal)
if ($actionInspectStart -lt 0 -or $actionStart -le $actionInspectStart `
        -or $actionEnd -le $actionStart) {
    throw 'StageManager Action lifecycle boundary is missing.'
}
$actionInspectBody = $stageManager.Substring(
    $actionInspectStart, $actionStart - $actionInspectStart)
$actionBody = $stageManager.Substring(
    $actionStart, $actionEnd - $actionStart)
foreach ($forbidden in @(
        'currentStage++;',
        'StageRunSession.begin(',
        'reserveActionEncounter',
        'markActionEncounterWorldStarted',
        'completeActionEncounterTeardown')) {
    if ($actionBody.Contains($forbidden)) {
        throw "Inner Action must not create or advance a parent run: $forbidden"
    }
}
$duplicateSlot = $actionInspectBody.IndexOf(
    'if (warlordActionSlot != null)', [System.StringComparison]::Ordinal)
$lastTerminalReplay = $actionInspectBody.IndexOf(
    'if (lastWarlordActionTerminal != null',
    [System.StringComparison]::Ordinal)
$newActionStage = $actionBody.IndexOf(
    'new StageInfo(createWarlordActionStageData())',
    [System.StringComparison]::Ordinal)
if ($duplicateSlot -lt 0 -or $lastTerminalReplay -le $duplicateSlot -or
        $newActionStage -lt 0) {
    throw 'Exact duplicate/terminal replay must return before a new Action StageInfo is built.'
}
Assert-OrderedContains $actionBody @(
    'inspectWarlordActionEncounter(binding)'
    'WarlordActionEncounterService.prepareCombat(binding, control)'
    'warlordActionSlot = {'
    'requestWarlordActionTransition()'
    'warlordActionSlot.transitionCommitted = true;'
    'return acceptedWarlordActionTransition();'
) 'Action begin must inspect, prepare, claim, commit the fade, then report admission.'
Assert-Contains $actionBody `
    'return rollbackWarlordActionStart(' `
    'Pre-commit Action failures must use the single transactional rollback path.'

$lifecycleLogStart = $stageManager.IndexOf(
    'private function publishWarlordActionLifecycle(',
    [System.StringComparison]::Ordinal)
$lifecycleLogEnd = $stageManager.IndexOf(
    'private function validateStageDrivers(', $lifecycleLogStart,
    [System.StringComparison]::Ordinal)
if ($lifecycleLogStart -lt 0 -or $lifecycleLogEnd -le $lifecycleLogStart) {
    throw 'Warlord lifecycle logger boundary is missing.'
}
$lifecycleLogBody = $stageManager.Substring(
    $lifecycleLogStart, $lifecycleLogEnd - $lifecycleLogStart)
Assert-OrderedContains $lifecycleLogBody @(
    'try {'
    'logger.发布服务器消息('
    '} catch (lifecycleError) {'
) 'Lifecycle diagnostics must be best-effort and unable to tear the commit path.'
$rollbackStart = $stageManager.IndexOf(
    'private function rollbackWarlordActionStart(',
    [System.StringComparison]::Ordinal)
$stageDataStart = $stageManager.IndexOf(
    'private function createWarlordActionStageData(', $rollbackStart,
    [System.StringComparison]::Ordinal)
if ($rollbackStart -lt 0 -or $stageDataStart -le $rollbackStart) {
    throw 'Action transactional rollback boundary is missing.'
}
$rollbackBody = $stageManager.Substring(
    $rollbackStart, $stageDataStart - $rollbackStart)
Assert-OrderedContains $rollbackBody @(
    'isWarlordActionTransitionCommitted()'
    'if (exactSlot) warlordActionSlot = null;'
    '.cancelPreparedCombat(binding)'
    'rememberWarlordActionTerminal(binding, terminal);'
) 'Rollback must preserve committed fades and otherwise clear slot/prepared before terminal.'

$activationStart = $stageManager.IndexOf(
    'private function initWarlordActionStage():Void',
    [System.StringComparison]::Ordinal)
$activationEnd = $stageManager.IndexOf(
    'private function continueWarlordActionReturn():Void', $activationStart,
    [System.StringComparison]::Ordinal)
if ($activationStart -lt 0 -or $activationEnd -le $activationStart) {
    throw 'StageManager Action activation boundary is missing.'
}
$activationBody = $stageManager.Substring(
    $activationStart, $activationEnd - $activationStart)
$activationCatch = $activationBody.IndexOf(
    '} catch (activationError) {', [System.StringComparison]::Ordinal)
$activationReturning = $activationBody.IndexOf(
    'slot.phase = "returning";', $activationCatch,
    [System.StringComparison]::Ordinal)
$activationCancel = $activationBody.IndexOf(
    '.cancelPreparedCombat(slot.binding)', $activationCatch,
    [System.StringComparison]::Ordinal)
$activationRelease = $activationBody.IndexOf(
    '.releaseCombatForReturn(slot.binding)', $activationCancel,
    [System.StringComparison]::Ordinal)
if ($activationCatch -lt 0 -or $activationReturning -le $activationCatch -or
        $activationCancel -le $activationReturning -or
        $activationRelease -le $activationCancel) {
    throw 'Activation failure must cancel unconsumed prepared state before release/return.'
}
Assert-NotMatches $stageManager `
    '\b(ActionEncounterRunner|StageSubStageCoordinator)\b' `
    'StageManager must not reference a retired lifecycle owner.'

# Canonical return/clear cancels the one Action slot regardless of entering,
# active, or returning phase. Its independent outer runner cancellation is
# checked below and must also run when this slot is absent.
$clearStart = $stageManager.IndexOf(
    'public function clear():Void', [System.StringComparison]::Ordinal)
$clearEnd = $stageManager.IndexOf(
    'public function getTimePoolValidationError', $clearStart,
    [System.StringComparison]::Ordinal)
if ($clearStart -lt 0 -or $clearEnd -le $clearStart) {
    throw 'StageManager clear boundary is missing.'
}
$clearBody = $stageManager.Substring($clearStart, $clearEnd - $clearStart)
$clearGate = $clearBody.IndexOf('StageRunSession.canClearStageManager()',
    [System.StringComparison]::Ordinal)
$clearCancelCall = $clearBody.IndexOf(
    '.cancelForStageExit()', $clearGate,
    [System.StringComparison]::Ordinal)
$clearCancellation = $clearBody.IndexOf(
    'publishWarlordActionCancellation("parent_return_base")', $clearGate,
    [System.StringComparison]::Ordinal)
$clearNull = $clearBody.IndexOf(
    'warlordActionSlot = null;', $clearCancelCall,
    [System.StringComparison]::Ordinal)
if ($clearGate -lt 0 -or $clearCancellation -le $clearGate -or
        $clearCancelCall -le $clearCancellation -or
        $clearNull -le $clearCancelCall) {
    throw 'Authorized clear must send parent_return_base cancellation before service cancel and slot clear.'
}
$slotClearBody = $clearBody.Substring($clearGate, $clearNull - $clearGate)
if ($slotClearBody.Contains('warlordActionSlot.phase')) {
    throw 'entering/active/returning Action slots must share the same clear path.'
}
Assert-Matches $clearBody `
    'retireWarlordRunnerBestEffort\(\s*clearedWarlordRunner,\s*"stage\.parent-return-base"\s*\);' `
    'Clear must retire the outer owner independently of the Action slot.'

# Every parent-stage destruction path must publish its fixed cancellation while
# the Action slot and outer runner still retain both exact identities.
$failureCleanupStart = $stageManager.IndexOf(
    'private function finalizeInitStageFailureCleanup():Void',
    [System.StringComparison]::Ordinal)
$failureCleanupEnd = $stageManager.IndexOf(
    'private function preserveFailedStageForReturnRetry():Void',
    $failureCleanupStart, [System.StringComparison]::Ordinal)
if ($failureCleanupStart -lt 0 -or $failureCleanupEnd -le $failureCleanupStart) {
    throw 'StageManager failed-initialization cleanup boundary is missing.'
}
$failureCleanupBody = $stageManager.Substring(
    $failureCleanupStart, $failureCleanupEnd - $failureCleanupStart)
Assert-OrderedContains $failureCleanupBody @(
    'publishWarlordActionCancellation("stage_exit")',
    'warlordRunner = null;',
    'warlordActionSlot = null;',
    'retireWarlordRunnerBestEffort(',
    '"stage.parent-setup-failed"',
    '.cancelForStageExit()'
) 'Failure cleanup must cancel Action and outer identities before their owners are disposed.'

$disposeStart = $stageManager.IndexOf(
    'public function dispose():Void', [System.StringComparison]::Ordinal)
$disposeEnd = $stageManager.IndexOf(
    'public function reset():Void', $disposeStart,
    [System.StringComparison]::Ordinal)
if ($disposeStart -lt 0 -or $disposeEnd -le $disposeStart) {
    throw 'StageManager dispose boundary is missing.'
}
$disposeBody = $stageManager.Substring($disposeStart, $disposeEnd - $disposeStart)
Assert-OrderedContains $disposeBody @(
    'publishWarlordActionCancellation("parent_restart")',
    'StageRunSession.resetForRestart()',
    'warlordRunner = null;',
    'warlordActionSlot = null;',
    'retireWarlordRunnerBestEffort(',
    '"stage.parent-restart"',
    '.cancelForStageExit()'
) 'Dispose must cancel Action and outer identities before their owners are disposed.'

$outerRetireStart = $stageManager.IndexOf(
    'private function retireWarlordRunnerBestEffort(',
    [System.StringComparison]::Ordinal)
$outerRetireEnd = $stageManager.IndexOf(
    'private function leaveTimePoolBestEffort', $outerRetireStart,
    [System.StringComparison]::Ordinal)
if ($outerRetireStart -lt 0 -or $outerRetireEnd -le $outerRetireStart) {
    throw 'StageManager outer retirement helper boundary is missing.'
}
$outerRetireBody = $stageManager.Substring(
    $outerRetireStart, $outerRetireEnd - $outerRetireStart)
Assert-OrderedContains $outerRetireBody @(
    'runner.publishOuterCancellation(reasonCode)',
    'runner.dispose();'
) 'Outer cancellation must be attempted before the runner loses its exact binding.'

# The service owns combat logic only: no SceneManager, fade, world destruction,
# parent StageRunSession lease, or MovieClip-backed retry clock.
foreach ($sentinel in @(
        'warlord.action-encounter-binding.v2',
        'warlord.action-encounter-admission.v1',
        'warlord.action-encounter-terminal.v2',
        'warlord_action_encounter_admitted',
        'public static function prepareCombat(',
        'public static function cancelPreparedCombat(',
        'public static function activateCombat(',
        'public static function tick():Void',
        'public static function releaseCombatForReturn(',
        'public static function completeCombatReturn(',
        'public static function cancelForStageExit():Void',
        'public static function deliverTerminal(',
        'public static function retryPendingTerminal():Void')) {
    Assert-Contains $actionService $sentinel `
        "Warlord Action service boundary missing: $sentinel"
}
Assert-Matches $actionService `
    '\[\s*"schema"\s*,\s*"outerRunId"\s*,\s*"encounterId"\s*,\s*"requestId"\s*,\s*"inputDigest"\s*\]' `
    'Service must validate/clone the exact five-key v2 binding.'
Assert-Matches $actionService `
    '\[\s*"schema"\s*,\s*"outerRunId"\s*,\s*"encounterId"\s*,\s*"requestId"\s*,\s*"inputDigest"\s*,\s*"status"\s*,\s*"reasonCode"\s*,\s*"result"\s*\]' `
    'Service must validate/clone the exact eight-key v2 terminal.'
Assert-Matches $actionService `
    'ADMISSION_KEYS:Array\s*=\s*\[\s*"schema"\s*,\s*"binding"\s*,\s*"disposition"\s*,\s*"phase"\s*\]' `
    'Service must validate the exact four-key admission payload.'
Assert-Matches $actionService `
    'return\s*\{schema:ADMISSION_SCHEMA\s*,\s*binding:cloneBinding\(binding\)\s*,\s*disposition:disposition\s*,\s*phase:phase\};' `
    'Admission must carry one cloned exact five-key binding and no flattened identity.'
$handleStart = $actionService.IndexOf(
    'public static function handleStart(command:Object):Void',
    [System.StringComparison]::Ordinal)
$tickStart = $actionService.IndexOf(
    'public static function tick():Void', $handleStart,
    [System.StringComparison]::Ordinal)
if ($handleStart -lt 0 -or $tickStart -le $handleStart) {
    throw 'Action start handler boundary is missing.'
}
$handleStartBody = $actionService.Substring(
    $handleStart, $tickStart - $handleStart)
Assert-OrderedContains $handleStartBody @(
    'traceStartLifecycle("start_received"'
    'getAbsorbingTerminal(binding)'
    'manager.inspectWarlordActionEncounter(binding)'
    'releasePanelPauseForStart()'
    'manager.beginWarlordActionEncounter('
    'createAdmission(binding, outcome)'
    'trySendAdmission(admission)'
) 'Action start must replay terminal and classify duplicates before its one fresh pause release.'
Assert-Contains $handleStartBody `
    'recoverStartAfterFailure(manager, binding,' `
    'Unexpected start throws must re-inspect manager truth before choosing ACK or terminal.'
Assert-Matches $handleStartBody `
    'if\s*\(isRejectedOutcome\(existing\)\)\s*\{[\s\S]*?if\s*\(existing\.reasonCode\s*===\s*"encounter_active"\)\s*\{[\s\S]*?disposition=stale phase=preflight reason=encounter_active[\s\S]*?return;[\s\S]*?freezeFailureTerminal\(binding,\s*"not_started"' `
    'A stale binding rejected by an active encounter must return before freezing terminal state.'

$pauseReleaseStart = $actionService.IndexOf(
    'private static function releasePanelPauseForStart():Object',
    [System.StringComparison]::Ordinal)
$admissionBuilderStart = $actionService.IndexOf(
    'private static function createAdmission(', $pauseReleaseStart,
    [System.StringComparison]::Ordinal)
if ($pauseReleaseStart -lt 0 -or $admissionBuilderStart -le $pauseReleaseStart) {
    throw 'Action pause release boundary is missing.'
}
$pauseReleaseBody = $actionService.Substring(
    $pauseReleaseStart, $admissionBuilderStart - $pauseReleaseStart)
Assert-OrderedContains $pauseReleaseBody @(
    'readPanelPauseLease()'
    'readPauseOwner() !== "webpanel"'
    'releaseExactPanelPauseLease(String(lease))'
    'clearPanelPauseLeaseIfExact(lease)'
    'readPauseState() === true'
) 'Fresh Action must release one exact webpanel lease and prove gameplay unpaused.'
Assert-NotMatches $pauseReleaseBody `
    'webPanelUnpause|LootContainerService|CharacterBuildService|StageRunSession' `
    'Action pause release must not enter generic Loot/Build/navigation authority.'
Assert-Contains $actionService `
    'org.flashNight.arki.pause.PauseManager.releaseLease(lease);' `
    'Product Action pause release must call PauseManager with the captured exact lease.'
Assert-Contains $actionService `
    'sameTerminalIdentity(_absorbingTerminal, frozen)' `
    'First terminal for an exact binding must remain absorbing after local send success.'
$serviceLifecycleStart = $actionService.IndexOf(
    'private static function publishLifecycleDiagnostic(',
    [System.StringComparison]::Ordinal)
$serviceLifecycleEnd = $actionService.IndexOf(
    'private static function applyInitialHp(', $serviceLifecycleStart,
    [System.StringComparison]::Ordinal)
if ($serviceLifecycleStart -lt 0 -or
        $serviceLifecycleEnd -le $serviceLifecycleStart) {
    throw 'Action service lifecycle logger boundary is missing.'
}
$serviceLifecycleBody = $actionService.Substring(
    $serviceLifecycleStart, $serviceLifecycleEnd - $serviceLifecycleStart)
Assert-OrderedContains $serviceLifecycleBody @(
    'try {'
    'logger.发布服务器消息('
    '} catch (lifecycleError) {'
) 'Action service lifecycle diagnostics must also be best-effort.'
Assert-OrderedContains $handleStartBody @(
    'getAbsorbingTerminal(binding)'
    'deliverTerminal(remembered)'
    'manager.inspectWarlordActionEncounter(binding)'
) 'Absorbing service terminal must replay before manager inspection or pause mutation.'
Assert-Matches $actionService `
    'if \(outcome\.disposition === "transition_pending"\)[\s\S]*else if \(outcome\.disposition === "duplicate"[\s\S]*else \{\s*return null;' `
    'Admission builder must reject unknown dispositions and phases rather than coerce them.'
Assert-Contains $actionService `
    'run.world !== _root.gameworld' `
    'A detached or replaced active world must fail closed instead of hanging forever.'
Assert-Contains $actionService `
    'failActiveCombat("action.world-detached")' `
    'World detachment must enter the canonical frozen return path.'
Assert-Contains $actionService `
    'run.cleanupOk = controlReleased === true' `
    'Combat cleanup must preserve a truthful aggregate result.'
$activateCombatStart = $actionService.IndexOf(
    'public static function activateCombat(')
$releaseCombatStart = $actionService.IndexOf(
    'public static function releaseCombatForReturn(')
$completeCombatStart = $actionService.IndexOf(
    'public static function completeCombatReturn(', $releaseCombatStart)
if ($activateCombatStart -lt 0 -or $releaseCombatStart -le $activateCombatStart `
        -or $completeCombatStart -lt 0) {
    throw 'Combat cleanup function boundaries are missing.'
}
$activateCombatBody = $actionService.Substring(
    $activateCombatStart, $releaseCombatStart - $activateCombatStart)
Assert-NotMatches $activateCombatBody `
    '_root\.控制目标\s*=\s*"军阀动作镜头"' `
    'Activation must not replace the player identity while deferred dressup is loading.'
Assert-Contains $activateCombatBody `
    'HorizontalScroller.switchFollowTo(run.camera);' `
    'Activation must move only camera follow while retaining player input identity.'
$releaseCombatBody = $actionService.Substring(
    $releaseCombatStart, $completeCombatStart - $releaseCombatStart)
Assert-Contains $releaseCombatBody `
    '.releaseScene(run.world) === true;' `
    'Combat cleanup must release the exact world from HorizontalScroller.'
Assert-OrderedContains $releaseCombatBody @(
    'if (run.phase == "released") return run.cleanupOk === true;',
    'run.world._parent == undefined',
    'run.cameraReleased = false;',
    'HorizontalScroller',
    '.releaseScene(run.world) === true;',
    'run.phase = "released";',
    'releaseCombatHandles(run);'
) 'Action cleanup must freeze truth and drop MovieClip handles before the fade.'
$cancelStageExitStart = $actionService.IndexOf(
    'public static function cancelForStageExit():Void', $completeCombatStart)
if ($cancelStageExitStart -lt 0) {
    throw 'Stage-exit cleanup boundary is missing.'
}
$completeCombatBody = $actionService.Substring(
    $completeCombatStart, $cancelStageExitStart - $completeCombatStart)
Assert-Contains $completeCombatBody `
    'run.phase == "released"' `
    'frame209 completion must read the cleanup truth frozen before the fade.'
Assert-NotMatches $completeCombatBody `
    '\breleaseCombatForReturn\s*\(' `
    'frame209 must not retry cleanup through a cross-frame MovieClip reference.'
$completeActionStart = $stageManager.IndexOf(
    'public function completeWarlordActionEncounter(')
$freezeActionStart = $stageManager.IndexOf(
    'public function freezeWarlordActionEncounter(', $completeActionStart)
$completeReturnStart = $stageManager.IndexOf(
    'private function completeWarlordActionReturn():Void')
$requestTransitionStart = $stageManager.IndexOf(
    'private function requestWarlordActionTransition():Object', $completeReturnStart)
if ($completeActionStart -lt 0 -or $freezeActionStart -lt 0 -or
        $completeReturnStart -lt 0 -or $requestTransitionStart -lt 0) {
    throw 'StageManager Action terminal boundaries are missing.'
}
$completeActionBody = $stageManager.Substring(
    $completeActionStart, $freezeActionStart - $completeActionStart)
$completeReturnBody = $stageManager.Substring(
    $completeReturnStart, $requestTransitionStart - $completeReturnStart)
Assert-Contains $completeActionBody `
    'warlordActionSlot.combatFact = {' `
    'Combat completion must freeze facts without constructing a terminal.'
Assert-NotMatches $completeActionBody `
    '\bcreateWarlordActionTerminal\s*\(' `
    'Combat completion must not construct an early terminal before frame209.'
Assert-OrderedContains $completeReturnBody @(
    '.completeCombatReturn(binding)',
    'if (!cleanupComplete && terminalStatus === "completed")',
    'terminalReason = "action.cleanup-incomplete"',
    'var terminal:Object = createWarlordActionTerminal(',
    '.deliverTerminal(terminal)'
) 'frame209 must choose cleanup truth before constructing and delivering one terminal.'
if ([regex]::Matches(
        $completeReturnBody, '\bcreateWarlordActionTerminal\s*\(').Count -ne 1) {
    throw 'frame209 must construct the Action terminal exactly once.'
}
Assert-NotMatches $stageManager `
    '(?:warlordActionSlot|slot)\.terminal\s*=' `
    'PREFER_B forbids rewriting a constructed Action terminal.'
$cancelForStageExitStart = $actionService.IndexOf(
    'public static function cancelForStageExit():Void')
$deliverTerminalStart = $actionService.IndexOf(
    'public static function deliverTerminal(', $cancelForStageExitStart)
if ($cancelForStageExitStart -lt 0 -or $deliverTerminalStart -lt 0 -or
        $actionService.Substring(
            $cancelForStageExitStart,
            $deliverTerminalStart - $cancelForStageExitStart
        ).IndexOf('_pendingTerminal = null;') -lt 0) {
    throw 'Parent-stage exit must discard a stale terminal before the next run.'
}
foreach ($forbiddenPattern in @(
        '\bSceneManager\s*\.',
        ':\s*SceneManager\b',
        '\bremoveGameWorld\s*\(',
        '\bbindCurrentWorldLease\s*\(',
        '\bgetWorldTeardownReceipt\s*\(',
        '\bcaptureWorldTransitionReceipt\s*\(',
        '\b淡出跳转帧\s*\(',
        '\b加载共享场景\s*\(',
        '\bswapDepths\s*\(',
        '\bStageRunSession\b',
        '\bonEnterFrame\b',
        '\bsetInterval\s*\(',
        '\bsetTimeout\s*\(',
        '\b_terminalClock\b',
        '\bActionEncounterRunner\b',
        '\bStageSubStageCoordinator\b',
        '\bleaseGeneration\b',
        '\bleaseToken\b',
        '\bworldGeneration\b',
        '\bworldToken\b',
        'warlord_action_encounter_cancelled',
        'warlord\.action-encounter-cancellation\.v1',
        '\bpublishWarlordActionCancellation\b',
        '\bstageOuterBinding\b',
        'warlord\.action-encounter-(binding|terminal)\.v1')) {
    Assert-NotMatches $actionService $forbiddenPattern `
        "Service crossed the PREFER_B ownership boundary: $forbiddenPattern"
}
if ($actionService.Contains('_root.加载我方人物(') -or
        $actionService.Contains('_root.加载主角和战宠(')) {
    throw 'Action service must spawn the isolated avatar, not the normal party.'
}
if ($actionService.Contains('ArenaCalibrationService')) {
    throw 'Product Warlord Action service must not reuse ArenaCalibrationService.'
}

# StageRunSession remains only the outer GameStage authority.
foreach ($forbidden in @(
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
Assert-NotMatches $warlordRunner `
    '\b(ActionEncounterRunner|StageSubStageCoordinator)\b' `
    'WarlordSubStageRunner must remain the outer wire owner only.'
Assert-Contains $arenaBridge `
    'org.flashNight.arki.scene.WarlordActionEncounterService.install();' `
    'Product socket include does not install WarlordActionEncounterService.'

# Every projection carries the hold in attachMovie's initObject. This also
# fences a player avatar if deferred initialization ever misclassifies it as AI.
# The common update path must honor the hold until both sides arm in one tick.
Assert-Matches $updateEvent `
    'if\s*\(target\._warlordActionAiHeld\s*!==\s*true\)\s*\{\s*target\.unitAI\.update\(\);\s*\}' `
    'Unit update must honor the Warlord pre-arm AI hold.'
Assert-OrderedContains $actionService @(
    'init._warlordActionAiHeld = true;'
    '_root.控制目标 = name;'
    '_root.控制目标全自动 = true;'
    'var mc:MovieClip = _root.加载游戏世界人物('
    'mc._warlordActionAiHeld = true;'
) 'Player identity and the AI hold must survive deferred attachMovie initialization.'
foreach ($sentinel in @(
        'Number(mc.操控编号) == 0',
        'mc.hasDressup === true',
        'RuntimeEquipmentProjection.getSlotKeys()',
        'RuntimeEquipmentProjection.getStatus(mc, canonicalRefs)',
        'RuntimeEquipmentProjection.STATUS_ALIGNED')) {
    Assert-Contains $actionService $sentinel `
        "Player readiness gate missing: $sentinel"
}
Assert-OrderedContains $actionService @(
    'if (!bindPlayerControl(run, true)) {'
    'releasePreArmAiHolds(run.blueUnits);'
    'releasePreArmAiHolds(run.redUnits);'
    'primeTargets(run.blueUnits, run.redUnits);'
    'run.primed = true;'
) 'Combat arming must bind control, release both AI holds, prime, then commit.'

foreach ($testSentinel in @(
        'passed != 97',
        'fresh service begins without a second lifecycle owner',
        'product socket accepts the exact canonical v2 envelope',
        'binding is the exact five-key v2 identity',
        'every extra binding field fails the exact five-key identity',
        'player avatar never enters AI prime while allied pets do',
        'return restores the exact outer player globals',
        'all five formations produce distinct tactical geometry',
        'incomplete StaticInitializer latch blocks combat arming',
        'incomplete canonical equipment projection blocks combat arming',
        'avatar misclassified as AI cannot enter combat',
        'undressed avatar cannot enter combat',
        'zero-width paperdoll fails the visual readiness gate',
        'fresh admission releases one exact webpanel lease',
        'non-exclusive pause authority is rejected without release',
        'a later panel lease is preserved and blocks fresh admission',
        'clearing a lease is not accepted while gameplay remains paused',
        'fresh admission satisfies the exact v1 receipt schema',
        'exact duplicate reports its existing phase without rebuilding',
        'invalid outcome and phase fail closed instead of coercing admission',
        'same-binding retry replays the original terminal after send true',
        'absorbing terminal prevents all retry side effects',
        'StageManager terminal replay precedes fresh pause release',
        'duplicate admission never releases a later panel lease',
        'encounter_active stale retry emits no synthetic terminal',
        'encounter_active stale retry creates no absorbing terminal',
        'current terminal remains pending after its first send fails',
        'pending current terminal retries once and remains absorbing',
        'post-commit throw recovers admission instead of false terminal',
        'proven pre-commit throw emits one exact unknown terminal')) {
    Assert-Contains $actionTest $testSentinel `
        "Action encounter regression sentinel missing: $testSentinel"
}

$commonRunner = Join-Path $PSScriptRoot `
    'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'warlord-action-encounter'
    TemplateRelativePath = `
        'scripts\test-runners\warlord-action-encounter\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\scene\ActionEncounterRunnerTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.scene.ActionEncounterRunnerTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\scene\WarlordActionEncounterService.as'
        'scripts\逻辑系统分区\竞技场系统_WebView.as'
        'scripts\类定义\org\flashNight\arki\scene\StageRunSession.as'
        'scripts\类定义\org\flashNight\arki\scene\WarlordSubStageRunner.as'
        'scripts\类定义\org\flashNight\arki\scene\StageManager.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\EventComponent\UpdateEventComponent.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^ActionEncounterRunnerTest Tests Passed: 97\r?$'
        '(?m)^ActionEncounterRunnerTest Tests Failed: 0\r?$'
        '(?m)^ActionEncounterRunnerTest Cases Passed: 4/4\r?$'
    )
    SuccessSummary = '97/97 assertions, 4/4 cases'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
if ($HostWireFixtureDirectory) {
    $caseNames = @(
        'demo1-attack', 'demo1-defend',
        'demo2-troops-attack', 'demo2-troops-defend',
        'demo2-avatar-attack', 'demo2-avatar-defend',
        'demo2-avatar-away-attack', 'demo2-avatar-away-defend'
    )
    $commands = foreach ($caseName in $caseNames) {
        $json = Read-Utf8 (Join-Path $HostWireFixtureDirectory ($caseName + '.json'))
        $parsed = $json | ConvertFrom-Json
        if ($parsed.action -ne 'warlord_action_encounter_start') {
            throw "Unexpected Host wire fixture: $caseName"
        }
        $json
    }
    $projectDir = Split-Path -Parent $PSScriptRoot
    $baseTemplate = Read-Utf8 (Join-Path $projectDir $focusedRun.TemplateRelativePath)
    $wireLiteral = ('[' + ($commands -join ',') + ']').Replace('\', '\\').Replace('"', '\"')
    $wireLiteral = $wireLiteral.Replace("`r", '\r').Replace("`n", '\n')
    $hostCall = 'org.flashNight.arki.scene.ActionEncounterRunnerTest.validateHostCommands("' +
        $wireLiteral + '");'
    # 只生成 scratch 模板，不改共用 runner 或生产源码。保留新鲜 trace 的终结标记在最后。
    $baseTemplate = $baseTemplate.Replace(
        'trace("FocusedTestRunId warlord-action-encounter Complete:',
        $hostCall + "`r`n" + 'trace("FocusedTestRunId warlord-action-encounter Complete:')
    $templateRelative = 'tmp/warlord-host-wire-' + [Guid]::NewGuid().ToString('N') + '.as.template'
    [IO.File]::WriteAllText((Join-Path $projectDir $templateRelative), $baseTemplate,
        [Text.UTF8Encoding]::new($true))
    $focusedRun.TemplateRelativePath = $templateRelative
    $focusedRun.ExpectedTracePatterns += '(?m)^ActionEncounterRunnerTest Host Wire Passed: 16/16\r?$'
    $focusedRun.SuccessSummary += ', Host transport -> AS2 16/16'
}
& $commonRunner @focusedRun
