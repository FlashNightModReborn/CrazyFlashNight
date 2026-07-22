$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$assertions = 0

function Read-RepoText([string]$RelativePath) {
    return [System.IO.File]::ReadAllText((Join-Path $projectRoot $RelativePath))
}

function Assert-True([bool]$Condition, [string]$Label) {
    $script:assertions++
    if (-not $Condition) { throw ("[FAIL #{0}] {1}" -f $script:assertions, $Label) }
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Label) {
    Assert-True ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) $Label
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Label) {
    Assert-True ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) $Label
}

function Assert-Before([string]$Text, [string]$First, [string]$Second, [string]$Label) {
    $firstIndex = $Text.IndexOf($First, [StringComparison]::Ordinal)
    $secondIndex = $Text.IndexOf($Second, [StringComparison]::Ordinal)
    Assert-True ($firstIndex -ge 0 -and $secondIndex -ge 0 -and $firstIndex -lt $secondIndex) $Label
}

function Get-Section([string]$Text, [string]$StartNeedle, [string]$EndNeedle) {
    $start = $Text.IndexOf($StartNeedle, [StringComparison]::Ordinal)
    if ($start -lt 0) { return "" }
    $end = $Text.IndexOf($EndNeedle, $start + $StartNeedle.Length,
        [StringComparison]::Ordinal)
    if ($end -lt 0) { return $Text.Substring($start) }
    return $Text.Substring($start, $end - $start)
}

$rootLogic = Read-RepoText "scripts\逻辑\关卡系统\关卡系统_lsy_地图元件.as"
$rootCallbacks = Read-RepoText "scripts\逻辑\关卡系统\关卡系统_lsy_资源箱回调.as"
$interaction = Read-RepoText "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\InteractionHandler.as"
$arbiter = Read-RepoText "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\BoxInteractionArbiter.as"
$arbiterTest = Read-RepoText "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\BoxInteractionArbiterTest.as"
$sceneManager = Read-RepoText "scripts\类定义\org\flashNight\arki\scene\SceneManager.as"
$service = Read-RepoText "scripts\类定义\org\flashNight\arki\scene\ChestSessionService.as"
$serviceTest = Read-RepoText "scripts\类定义\org\flashNight\arki\scene\ChestSessionServiceTest.as"
$socketBridge = Read-RepoText "scripts\类定义\org\flashNight\arki\scene\ChestS0SocketBridge.as"
$socketBridgeTest = Read-RepoText "scripts\类定义\org\flashNight\arki\scene\ChestS0SocketBridgeTest.as"
$serverManager = Read-RepoText "scripts\类定义\org\flashNight\neur\Server\ServerManager.as"
$flashWiringTest = Read-RepoText `
    "scripts\类定义\org\flashNight\arki\scene\ChestS0FlashWiringTest.as"
$productionFlashWiringTest = Read-RepoText `
    "scripts\类定义\org\flashNight\arki\scene\ChestS0ProductionFlashWiringTest.as"
$suite = Read-RepoText "scripts\类定义\org\flashNight\arki\scene\ChestS0TestSuite.as"
$runnerTemplate = Read-RepoText "scripts\test-runners\chest-s0\TestLoader.as.template"
$runner = Read-RepoText "scripts\run-chest-s0-tests.ps1"
$browserHarnessHtml = Read-RepoText `
    "launcher\web\modules\minigames\lockbox\dev\s0-harness.html"
$browserHarnessJs = Read-RepoText `
    "launcher\web\modules\minigames\lockbox\dev\s0-harness.js"
$browserHarnessRunner = Read-RepoText "tools\run-lockbox-chest-s0-harness.js"

Assert-Contains $rootLogic '#include "../逻辑/关卡系统/关卡系统_lsy_资源箱回调.as"' `
    "map entry includes the canonical chest callback source"
$openStart = $rootCallbacks.IndexOf("_root.地图元件.资源箱开启脚本", [StringComparison]::Ordinal)
$breakStart = $rootCallbacks.IndexOf("_root.地图元件.资源箱破碎脚本", [StringComparison]::Ordinal)
Assert-True ($openStart -ge 0 -and $breakStart -gt $openStart) `
    "root chest callback boundaries are discoverable"
$openSection = $rootCallbacks.Substring($openStart, $breakStart - $openStart)
$breakSection = $rootCallbacks.Substring($breakStart)

Assert-Before $openSection "ChestSessionService.handleOpenFrame(target)" `
    "LootContainerService.guardOpenGridFixture(target)" `
    "open-frame S0 guard precedes the Web-only loot authority path"
Assert-Before $breakSection "ChestSessionService.handleBreakFrame(target)" "target.掉落物判定()" `
    "break-frame S0 guard precedes direct-drop delivery"
Assert-NotContains $rootCallbacks "掉落物转换为物品栏" `
    "root callbacks never restore the removed Flash grid renderer"
Assert-NotContains $rootCallbacks "回退Web战利品到旧界面" `
    "root callbacks never recover Web loot through Flash UI"
Assert-Contains $openSection "if (chestS0Result.handled) {" `
    "root open callback enters the handled S0 fail-closed block"
Assert-Before $openSection "ChestS0SocketBridge.handleAuthorityTransition(chestS0Result)" `
    "return;" "root open callback forwards authority transition before failing closed"
Assert-Contains $breakSection "if (chestS0Result.handled) {" `
    "root break callback enters the handled S0 fail-closed block"
Assert-Before $breakSection "ChestS0SocketBridge.handleAuthorityTransition(chestS0Result)" `
    "return;" "root break callback forwards authority transition before failing closed"

Assert-Contains $interaction "BoxInteractionArbiter.register(target, _root.gameworld)" `
    "box initialization registers the central arbiter"
Assert-True ([regex]::IsMatch($interaction,
    'if\s*\(BoxInteractionArbiter\.isBoxPreset\(target\.presetName\)\)\s*\{\s*return BoxInteractionArbiter\.register\(target, _root\.gameworld\);\s*\}')) `
    "recognized boxes fail closed when central arbiter registration fails"
Assert-Contains $arbiterTest "testA03FRegistrationFailureNeverFallsBack" `
    "A03F covers central registration failure without per-target fallback"
Assert-Before $interaction "ChestSessionService.beginFixture(" "InteractionHandler.executePickup(target)" `
    "the exact S0 fixture check occurs before ordinary pickup dispatch"
Assert-Before $interaction "ChestS0SocketBridge.observeLocalFixture(target);" `
    "var s0Result:Object = ChestSessionService.beginFixture(" `
    "interaction submission refreshes the exact per-target gate before begin"
Assert-Contains $interaction 'target.dispatcher.subscribe("death", deathFunc, target)' `
    "death invalidation hook is wired"
Assert-Contains $interaction 'subscribeTargetEvent(' "individual target unload hook is wired"
Assert-Contains $interaction "BoxInteractionArbiter.forget(this)" `
    "individual unload forgets strong arbiter target references"
Assert-Contains $interaction "__cf7InteractionHandlerDispatcher === target.dispatcher" `
    "idempotence is scoped to dispatcher identity"
Assert-Before $interaction "if (!initialized)" `
    "target.__cf7InteractionHandlerInitialized = true" `
    "interaction subscriptions commit initialized state only after all setup succeeds"
Assert-Contains $serviceTest "partial subscription failure rolls back handlers" `
    "A13 covers transactional initialization rollback"

Assert-Contains $arbiter 'presetName === "保险柜"' "arbiter allow-list contains safe"
Assert-Contains $arbiter 'presetName === "隐藏资源点"' "arbiter allow-list contains hidden resource"
Assert-Contains $arbiter "public static function forget(target:Object)" `
    "arbiter exposes unload-only forget path"
Assert-Contains $arbiter "if (sceneCurrent != null || !hero) return false;" `
    "scene interaction retains priority over boxes"

Assert-Before $sceneManager "ChestS0SocketBridge.handleSceneUnload()" "gameworld.dispatcher.destroy()" `
    "scene actual-wire tombstone handling precedes dispatcher destruction"
Assert-Before $sceneManager "BoxInteractionArbiter.cleanup(gameworld)" "gameworld.dispatcher.destroy()" `
    "arbiter cleanup precedes dispatcher destruction"
Assert-Before $sceneManager "ObjectUtil.cloneParameters(inst, info.Parameters);" `
    "ChestS0SocketBridge.observeLocalFixture(inst);" `
    "SceneManager observes authored markers only after XML parameters are cloned"

Assert-Contains $service 'FIXTURE_ID:String = "insurance-safe-s0-v1"' `
    "fixture identity is frozen"
Assert-Contains $service 'AS2_GATE_ID:String = "local-as2-dev-s0-v1"' `
    "the authored AS2 per-target gate identity is frozen"
Assert-Contains $service 'SOURCE_ID:String = "as2-chest-s0"' "source identity is frozen"
Assert-Contains $service 'if (!hasExactLocalGate(target)) {' `
    "an exact fixture cannot enter S0 without its own exact local gate"
Assert-Contains $service 'target.chestS0As2GateId === AS2_GATE_ID' `
    "truthy and wrong-string target gates fail closed"
Assert-Contains $service 'hasOwnAuthoredField(target, "chestS0FixtureId")' `
    "the fixture marker must be an authored own field, never a prototype value"
Assert-Contains $service 'hasOwnAuthoredField(target, "chestS0As2GateId")' `
    "the per-target gate must be an authored own field, never a prototype value"
Assert-Contains $service `
    'value >= 1 && value <= 2147483647 && Math.floor(value) == value' `
    "service fixture shape matches the positive Int32 XML/socket domain"
Assert-Contains $socketBridge 'LOCAL_GATE_ID:String = ChestSessionService.AS2_GATE_ID' `
    "socket observation and authority share one canonical authored gate identity"
Assert-Contains $socketBridge 'target.hasOwnProperty("chestS0FixtureId")' `
    "socket observation rejects a prototype-inherited fixture marker"
Assert-Contains $socketBridge 'target.hasOwnProperty("chestS0As2GateId")' `
    "socket observation rejects a prototype-inherited per-target gate"
Assert-Contains $serviceTest `
    "each exact fixture requires its own exact string AS2 gate even after development is enabled" `
    "service regression covers missing, wrong, and truthy per-target gates"
Assert-Contains $socketBridgeTest `
    'started.error == "development_disabled"' `
    "socket regression prevents global development enable from leaking across targets"
Assert-Contains $socketBridgeTest `
    "S01 double gate, bootstrap-before-marker activation, dedicated schema, and synchronous AS2 pause acquisition fail closed" `
    "socket regression freezes bootstrap-before-marker activation without global gate leakage"
Assert-Contains $service 'typeof _requestOpenAction != "function"' `
    "adapter values are runtime validated"
Assert-Contains $service "killDispatchInProgress" "own-kill proof is bounded to synchronous dispatch"
Assert-Contains $service "resolveKnownNoWrite" "fresh no-write proof has an atomic revoke path"
Assert-Contains $service 'revokeSession(session, "known_no_write")' `
    "known-no-write releases the old attempt"
Assert-Contains $service "MAX_FLOW_CALL_ID:Number = 1" `
    "S0 AS2 flow call id domain is frozen to the single call id"
Assert-Contains $service "releaseSessionTarget(session)" `
    "terminal sessions release strong target references"
$openFrameSection = Get-Section $service `
    "public static function handleOpenFrame" "public static function handleTargetInvalid"
Assert-Contains $openFrameSection "var spySessionId:String = String(session.sessionId);" `
    "open-frame spy snapshots the exact old session identity before external reentry"
Assert-Contains $openFrameSection "var spyTarget:Object = target;" `
    "open-frame spy snapshots the exact old target before external reentry"
Assert-Contains $openFrameSection "var spyAuthorityEpoch:Number = _authorityEpoch;" `
    "open-frame spy snapshots the authority generation before external reentry"
Assert-Contains $openFrameSection "var spyWriteGeneration:Number = _writeEpoch;" `
    "open-frame spy snapshots the write generation before external reentry"
Assert-Before $openFrameSection "if (exactOldCompletion)" `
    'expireSession(session, "open_frame_spy_failed");' `
    "spy exception expires the old target only after exact identity/generation revalidation"
Assert-Contains $openFrameSection "releaseSessionTarget(session);" `
    "spy reentry mismatch releases only the old tombstone strong reference"
Assert-Contains $serviceTest `
    "A20 reentrant spy failure preserves the newer exact session and target generation" `
    "service regression protects a newer same-target session from old spy exception cleanup"
Assert-Before $serverManager "ChestS0SocketBridge.isDedicatedHostAction(response.action)" `
    "handleGameCommand(response.action, response)" `
    "AS2 dedicated socket actions fail closed before ordinary gameCommands"
$socketCloseSection = Get-Section $serverManager `
    "public function onSocketClose():Void" "public function sendSocketMessage"
Assert-Before $socketCloseSection "ChestS0SocketBridge.handleSocketClosed()" `
    "for (var k:String in _pendingCallbacks)" `
    "AS2 bridge observes transport loss before callback teardown"
Assert-Contains $socketBridge "hasRecoveryTombstone" `
    "AS2 reconnect bootstrap can use a retained authority tombstone"
Assert-Contains $socketBridge "validateOrAdoptFlowCommand" `
    "AS2 reconnect can causally restore its exact flow identity"
Assert-Contains $socketBridge '"source", "fixture", "resumeActive"' `
    "AS2 bootstrap exact schema includes the explicit resumeActive discriminator"
Assert-Contains $socketBridge 'typeof command.resumeActive != "boolean"' `
    "AS2 bootstrap rejects a missing or mistyped resumeActive discriminator"
Assert-Contains $socketBridge "resumeActive: binding.resumeActive" `
    "AS2 bootstrap ack echoes the exact resumeActive discriminator"
Assert-NotContains $socketBridge `
    'if (_flow !== undefined && _flow !== null) return;' `
    "fresh Host bootstrap is not unconditionally rejected while a tombstone exists"
Assert-Contains $socketBridgeTest `
    "S03 capability is one-shot, while a fresh Host bootstrap authorizes the next attempt" `
    "S03 covers fresh capability rotation and a second begin"
Assert-Contains $socketBridgeTest `
    "S06 disconnect preserves authority; fresh generation bootstrap and causal query recover it" `
    "S06 covers real reconnect bootstrap without re-observing the fixture"
Assert-Contains $socketBridgeTest `
    "S06 pre-result target expiry emits the legal zero-watermark EXPIRED terminal" `
    "S06 freezes zero-watermark EXPIRED as a legal cross-stack terminal"
Assert-Contains $socketBridgeTest `
    "S07 normal bootstrap proves known-no-write and settles begin-in-flight orphan" `
    "S07 covers begin-in-flight disconnect recovery while Host remained idle"
Assert-Contains $socketBridgeTest `
    "S07 settled orphan releases authority and permits one fresh tracked begin" `
    "S07 proves orphan settlement permits one fresh tracked begin"
Assert-Contains $socketBridgeTest "ChestS0SocketBridgeTest Cases Passed: 10/10" `
    "socket bridge suite emits the exact S01-S10 completion sentinel"
Assert-Contains $socketBridge `
    'if (_flow !== undefined && _flow !== null) return validateFlowCommand(command);' `
    "an established AS2 flow cannot fall through into identity adoption"
Assert-Contains $socketBridgeTest "testS09BoundFlowIdentityCannotBeReadopted" `
    "S09 rejects same-session commands that try to replace an established exact identity"
Assert-Contains $socketBridge "matchesExactBeginResponseFlow(sessionId, response)" `
    "late begin success must exactly match an already adopted flow identity"
Assert-Contains $socketBridge `
    "_flow.flowHandle === response.flowHandle" `
    "late begin success compares the exact adopted flow handle"
Assert-Contains $socketBridge `
    "_flow.panelInstanceId === response.panelInstanceId" `
    "late begin success compares the exact adopted panel instance"
Assert-Contains $socketBridgeTest "testS10LateBeginResponseCannotReplaceAdoptedIdentity" `
    "S10 covers a late begin response racing an earlier Host flow adoption"
Assert-Contains $socketBridgeTest `
    "S10 the originally adopted exact identity remains able to complete after mismatch" `
    "S10 proves mismatched callback consumption does not poison the original authority"
Assert-Contains $socketBridgeTest `
    "S10 matching late begin response confirms the exact flow without duplicate terminal" `
    "S10 proves a matching late callback is idempotent"
Assert-Contains (Get-Section $socketBridge `
        "private static function activateBootstrapIfReady" `
        "private static function sendBootstrapAck") `
    "_bootstrap.consumed === true" `
    "consumed or suspended bootstrap cannot be reactivated by a later fixture observation"
Assert-Contains $socketBridgeTest "testS08ConsumedBootstrapCannotReactivateAfterSuspend" `
    "S08 covers consumed bootstrap reactivation failure and fresh bootstrap recovery"

Assert-Contains $suite "BoxInteractionArbiterTest.runAllTests()" "suite runs A01-A12 plus A03F"
Assert-Contains $suite "ChestSessionServiceTest.runAllTests()" "suite runs A13-A25"
Assert-Contains $suite "ChestS0SocketBridgeTest.runAllTests()" `
    "suite runs the S01-S10 actual socket bridge contract"
Assert-Contains $suite "ChestS0FlashWiringTest.runAllTests()" `
    "suite runs the supplemental P01-P04 preflight"
Assert-Contains $suite "ChestS0ProductionFlashWiringTest.runAllTests()" `
    "suite runs the production-path F01-F04 smoke"
Assert-Contains $suite "A01-A25/A03F/S01-S10/P01-P04 supplemental preflight/F01-F04" `
    "suite labels the aggregate with the exact A/S/P/F scope"
Assert-Contains $flashWiringTest "new LifecycleEventDispatcher(target)" `
    "supplemental preflight uses a local lifecycle dispatcher"
Assert-Contains $flashWiringTest `
    "target.chestS0As2GateId = ChestSessionService.AS2_GATE_ID;" `
    "supplemental fixture carries the exact authored per-target AS2 gate"
Assert-Contains $flashWiringTest "testP01LocalDispatcherSuccessPath" `
    "supplemental preflight declares P01"
Assert-Contains $flashWiringTest "testP02KnownNonSuccessRevokesWithoutKill" `
    "supplemental preflight declares P02"
Assert-Contains $flashWiringTest "testP03SyntheticDeathAndDirectSceneHookExpire" `
    "supplemental preflight declares P03"
Assert-Contains $flashWiringTest "testP04GuardModelAndMarkerRollback" `
    "supplemental preflight declares P04"
Assert-Contains $flashWiringTest "ChestS0SupplementalPreflight Cases Passed: 4/4" `
    "preflight emits an exact non-F completion sentinel"
Assert-NotContains $flashWiringTest 'trace("ChestS0FlashWiringTest' `
    "preflight traces do not describe themselves as production wiring evidence"
Assert-True (-not [regex]::IsMatch($flashWiringTest, '\bF0[1-4]\b|F01-F04')) `
    "supplemental preflight never claims frozen F01-F04 evidence"
Assert-True ([regex]::IsMatch($flashWiringTest,
    'cleanupWiring\(\);\s*\}\s*finally\s*\{\s*try\s*\{\s*ChestS0SocketBridge\.__testOnlyReset\(\);\s*\}\s*finally\s*\{\s*_root\.gameworld = _oldWorld;')) `
    "preflight cleanup nests finally blocks through bridge reset and root restoration"
Assert-Contains $productionFlashWiringTest "ChestS0ProductionFlashWiring Cases Passed: 4/4" `
    "production-path smoke emits the exact F01-F04 completion sentinel"
Assert-Contains $productionFlashWiringTest `
    "target.chestS0As2GateId = ChestSessionService.AS2_GATE_ID;" `
    "production-path exact fixture models the authored per-target AS2 gate"
foreach ($caseId in @("F01", "F02", "F03", "F04")) {
    Assert-True ([regex]::IsMatch($productionFlashWiringTest,
        ('"' + $caseId + ' PASS: [^"\r\n]+"'))) `
        "production-path smoke emits a concrete $caseId causal assertion"
}
Assert-Contains $productionFlashWiringTest '_world.dispatcher.publishGlobal("interactionKeyDown")' `
    "F smoke drives the real global interaction input"
Assert-Contains $productionFlashWiringTest "KillEventComponent.initialize(target)" `
    "F smoke drives the production kill component"
Assert-Contains $productionFlashWiringTest "SceneManager.getInstance()" `
    "F smoke drives the production scene manager"
Assert-Contains $productionFlashWiringTest "_root.地图元件.资源箱开启脚本" `
    "F smoke reaches the canonical root open callback"
Assert-Contains $productionFlashWiringTest "_root.地图元件.资源箱破碎脚本" `
    "F smoke reaches the canonical root break callback"
Assert-NotContains $productionFlashWiringTest "掉落物转换为物品栏" `
    "F smoke observes session/direct-drop wiring without replacing the removed Flash grid renderer"
Assert-True ([regex]::IsMatch($productionFlashWiringTest,
    'cleanupWiring\(\);\s*ChestS0SocketBridge\.__testOnlyReset\(\);\s*\}\s*finally\s*\{\s*restoreRootState\(\);')) `
    "production-path cleanup clears bridge authorization before restoring root state"

Assert-Contains $runnerTemplate "import org.flashNight.arki.scene.*;" `
    "scratch TestLoader uses the required frame-script wildcard import"
Assert-NotContains $runnerTemplate "import org.flashNight.arki.scene.ChestS0TestSuite;" `
    "scratch frame script has no concrete class import"
Assert-Contains $runnerTemplate "ChestS0TestSuite.runAllTests();" `
    "scratch TestLoader invokes the aggregate suite"
Assert-True (([regex]::Matches($runnerTemplate,
    [regex]::Escape('__CHEST_S0_RUN_ID__'))).Count -eq 2) `
    "scratch TestLoader has exact start/end runId placeholders"
Assert-Contains $runnerTemplate "ChestS0TestRunId Start: __CHEST_S0_RUN_ID__" `
    "scratch TestLoader traces the runId start sentinel"
Assert-Contains $runnerTemplate "ChestS0TestRunId Complete: __CHEST_S0_RUN_ID__" `
    "scratch TestLoader traces the runId completion sentinel"
Assert-Contains $runner "finally" "runner restores TestLoader scratch state in finally"
Assert-Contains $runner "Local\CF7_ChestS0Tests_" `
    "runner mutex is repository-scoped in the local process namespace"
Assert-Contains $runner '$runMutex.WaitOne(0)' `
    "runner fails fast instead of waiting on a conflicting repository run"
Assert-Contains $runner "AbandonedMutexException" `
    "runner fails closed on an abandoned repository mutex"
Assert-Contains $runner "must contain exactly two runId placeholders" `
    "runner validates runId injection shape"
Assert-Contains $runner "ChestS0TestRunId Complete: `$runIdPattern" `
    "runner requires the exact current runId completion trace"
Assert-NotContains $runner "SkipCompile" `
    "runner has no zero-test success switch"
Assert-Contains $runner "scripts/flashlog.txt was not refreshed by this run" `
    "runner rejects stale Flash trace"
Assert-Contains $runner "ChestSessionServiceTest Cases Passed: 13/13" `
    "runner requires the exact A13-A25 completion sentinel"
Assert-Contains $runner "ChestS0SocketBridgeTest Cases Passed: 10/10" `
    "runner requires the exact S01-S10 socket completion sentinel"
Assert-Contains $runner "ChestS0SocketBridgeTest Tests Failed: 0" `
    "runner rejects any failed S assertion"
Assert-Contains $runner "ChestS0SupplementalPreflight Cases Passed: 4/4" `
    "runner requires the exact P01-P04 preflight sentinel"
Assert-Contains $runner "ChestS0ProductionFlashWiring Cases Passed: 4/4" `
    "runner requires the exact F01-F04 production-path sentinel"
Assert-Contains $runner "ChestS0ProductionFlashWiring Tests Failed: 0" `
    "runner rejects any failed F assertion"
Assert-Contains $runner "ChestS0TestSuite .*F01-F04.* complete" `
    "runner requires an aggregate completion sentinel with explicit F01-F04 scope"
Assert-Contains $runner "[1-9][0-9]* assertions passed" `
    "runner rejects a vacuous zero-assertion arbiter summary"
Assert-Contains $runner "scripts/compiler_errors.txt was not refreshed by this run" `
    "runner rejects stale compiler diagnostics"
Assert-True ([regex]::IsMatch(
    ($productionFlashWiringTest + $suite + $runnerTemplate + $runner), '\bF0[1-4]\b|F01-F04')) `
    "production smoke, suite, template, and runner retain explicit F01-F04 scope"
Assert-Contains $browserHarnessHtml `
    '<script src="modules/minigames/lockbox/chest-s0-adapter.js"></script>' `
    "S0 adapter is loaded by the dedicated dev-only Browser harness"
Assert-Contains $browserHarnessHtml `
    '<script src="modules/lazy-loader.js"></script>' `
    "Browser harness loads the production lazy-loader"
Assert-Contains $browserHarnessHtml `
    '<script src="modules/panels-lazy-registry.js"></script>' `
    "Browser harness loads the production panel lazy registry"
Assert-NotContains $browserHarnessHtml `
    '<script src="modules/minigames/lockbox/lockbox-panel.js"></script>' `
    "Browser harness never preloads the Lockbox panel"
Assert-NotContains $browserHarnessHtml `
    '<script src="modules/minigames/lockbox/lockbox-core.js"></script>' `
    "Browser harness never preloads the Lockbox core"
Assert-Contains $browserHarnessJs 'kind: "browser-host-shim"' `
    "Browser evidence names the causal Host shim"
Assert-Contains $browserHarnessJs "actualCrossStack: false" `
    "Browser evidence cannot claim an actual cross-stack run"
Assert-Contains $browserHarnessJs `
    'lockboxPanelLazyLoaded: LazyLoader.isLoaded(PANEL_SCRIPT)' `
    "Browser boot evidence records that the panel was not preloaded"
Assert-Contains $browserHarnessJs `
    "api.assert(flow.domActiveSequence < flow.bindSendSequence" `
    "Browser W04 proves committed DOM precedes exact bind"
Assert-Contains $browserHarnessJs `
    "api.assert(opened.flow.bindSendSequence < opened.flow.readySequence" `
    "Browser W04 proves exact bind precedes puzzle ready"
Assert-Contains $browserHarnessJs "current.adapter.markBindUnknown()" `
    "Browser bind timeout reaches the adapter through inbound dispatch"
Assert-Contains $browserHarnessJs 'record("host.open_busy_before_allocation"' `
    "Browser W05 rejects same-name open before identity allocation"
Assert-Contains $browserHarnessJs 'code: "harness_teardown_only"' `
    "Browser teardown is explicitly separated from production close"
Assert-Contains $browserHarnessJs "authorityReleased: false" `
    "Browser teardown cannot masquerade as authority release"
Assert-Contains $browserHarnessRunner 'const expectedTotal = args.caseId ? 1 : 2;' `
    "Browser runner requires the exact W04/W05 case count"
Assert-Contains $browserHarnessRunner 'const expectedIds = args.caseId ? [args.caseId] : ["W04", "W05"];' `
    "Browser runner requires the exact W04/W05 identities and order"
Assert-Contains $browserHarnessRunner 'page.on("pageerror"' `
    "Browser runner fails on page exceptions"
Assert-Contains $browserHarnessRunner 'page.on("requestfailed"' `
    "Browser runner fails on resource request failures"
Assert-Contains $browserHarnessRunner "if (response.status() >= 400)" `
    "Browser runner fails on HTTP resource errors"
Assert-Contains $browserHarnessRunner 'if (message.type() === "error") consoleErrors.push(line);' `
    "Browser runner fails on console errors"
Assert-Contains $browserHarnessRunner "shimEvidence.actualCrossStack !== false" `
    "Browser runner rejects ambiguous cross-stack evidence"
Assert-Contains $browserHarnessRunner "validatePanelCommandLogs(panelCommandLogs)" `
    "Browser runner dynamically validates captured S0 panel command logs"
Assert-Contains $browserHarnessRunner 'payload.initData !== "[redacted]"' `
    "Browser runner requires whole-initData redaction in the emitted console log"

$asFiles = @(
    "scripts\类定义\org\flashNight\arki\scene\ChestSessionService.as",
    "scripts\类定义\org\flashNight\arki\scene\ChestSessionServiceTest.as",
    "scripts\类定义\org\flashNight\arki\scene\ChestS0FlashWiringTest.as",
    "scripts\类定义\org\flashNight\arki\scene\ChestS0ProductionFlashWiringTest.as",
    "scripts\类定义\org\flashNight\arki\scene\ChestS0SocketBridge.as",
    "scripts\类定义\org\flashNight\arki\scene\ChestS0SocketBridgeTest.as",
    "scripts\类定义\org\flashNight\arki\scene\ChestS0TestSuite.as",
    "scripts\类定义\org\flashNight\arki\scene\SceneManager.as",
    "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\BoxInteractionArbiter.as",
    "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\InteractionHandler.as",
    "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\BoxInteractionArbiterTest.as",
    "scripts\类定义\org\flashNight\neur\Server\ServerManager.as",
    "scripts\逻辑\关卡系统\关卡系统_lsy_地图元件.as",
    "scripts\逻辑\关卡系统\关卡系统_lsy_资源箱回调.as",
    "scripts\test-runners\chest-s0\TestLoader.as.template"
)
foreach ($relativePath in $asFiles) {
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $projectRoot $relativePath))
    Assert-True ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) "UTF-8 BOM: $relativePath"
}

$productionMarkers = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "data\stages") `
    -Recurse -File -Filter "*.xml" | Select-String -SimpleMatch "insurance-safe-s0-v1")
Assert-True ($productionMarkers.Count -eq 0) "no S0 fixture marker exists in production stage XML"

$coordinator = Read-RepoText "launcher\src\Guardian\DevLockboxS0Coordinator.cs"
$hostRuntime = Read-RepoText "launcher\src\Guardian\DevLockboxS0Runtime.cs"
$program = Read-RepoText "launcher\src\Program.cs"
$xmlSocketServer = Read-RepoText "launcher\src\Bus\XmlSocketServer.cs"
$panelHost = Read-RepoText "launcher\src\Guardian\PanelHostController.cs"
$webOverlay = Read-RepoText "launcher\src\Guardian\WebOverlayForm.cs"
$hostRuntimeTests = Read-RepoText "launcher\tests\Guardian\DevLockboxS0RuntimeTests.cs"
$adapterTest = Read-RepoText "tools\test-lockbox-chest-s0-adapter.js"
$actualWireTest = Read-RepoText "tools\test-lockbox-chest-s0-actual-wire.js"
$crossStackVerifier = Read-RepoText "tools\verify-lockbox-chest-s0-cross-stack.js"
$crossStackVerifierTest = Read-RepoText "tools\test-lockbox-chest-s0-cross-stack-verifier.js"

$hostRuntimeTypes = @(
    "PanelHostController",
    "WebOverlayForm",
    "LauncherCommandRouter",
    "TaskRegistry",
    "MessageRouter",
    "GuardianForm"
)
$coordinatorRuntimeDependencies = @($hostRuntimeTypes | Where-Object {
    $coordinator.IndexOf($_, [StringComparison]::Ordinal) -ge 0
})
Assert-True ($coordinatorRuntimeDependencies.Count -eq 0) `
    "pure Host coordinator has no direct production runtime dependencies"

Assert-Contains $coordinator 'RequiredEnvironmentValue = "1"' `
    "Host actual wire uses the exact one-value environment gate"
Assert-Contains $program 'Environment.GetEnvironmentVariable("CF7_DEV_LOCKBOX_S0")' `
    "Program injects only the approved explicit dev gate"
Assert-Contains $program "SteamOwnershipCheck.IsDevRepository(projectRoot)" `
    "Program requires a dev repository before actual-wire arming"
Assert-Contains $program "processManager.FlashProcess" `
    "Program binds actual-wire capability to the real Flash process"
Assert-Contains $program "socketServer.SetDedicatedJsonHandler(devLockboxS0.TryHandleSocketJson)" `
    "Program wires the S0 task only through the dedicated XMLSocket handler"
Assert-Contains $program "OnClientReadyForGeneration += devLockboxS0.OnSocketReady" `
    "Program binds socket readiness to an exact connection generation"
Assert-Contains $program "OnClientDisconnectedForGeneration += devLockboxS0.OnSocketDisconnected" `
    "Program binds disconnect handling to an exact connection generation"
Assert-Contains $program "webOverlay.SetDevLockboxS0Runtime(devLockboxS0)" `
    "Program injects the narrow S0 Web control handler"
Assert-Contains $program "panelHost.SetPanelOpenGate(devLockboxS0.AllowRegularPanelOpen)" `
    "Program installs global panel serialization while S0 holds pause"
Assert-Contains $program `
    "panelHost.OrchestrationSettled += devLockboxS0.OnPanelHostOrchestrationSettled" `
    "Program wires the post-pump idle edge used for a fresh arm retry"
Assert-Before $xmlSocketServer "DedicatedJsonHandler dedicatedHandler = _dedicatedJsonHandler" `
    'string response = _router.ProcessMessage(message' `
    "dedicated S0 socket traffic is consumed before MessageRouter"

$unexpectedHostTaskRoutes = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "launcher\src") `
    -Recurse -File -Filter "*.cs" | Where-Object {
        $_.Name -notin @("DevLockboxS0Runtime.cs", "Program.cs")
    } | Select-String -Pattern 'dev_lockbox_s0|CF7_DEV_LOCKBOX_S0')
Assert-True ($unexpectedHostTaskRoutes.Count -eq 0) `
    "the S0 task and gate are absent from generic Host/HTTP/Web task registrations"

Assert-Contains $hostRuntime 'HasExactKeys(message, "task", "callId", "payload")' `
    "Host begin accepts only the exact socket envelope"
Assert-Contains $hostRuntime 'HasExactKeys(payload, "action", "protocolVersion", "capability",' `
    "Host begin accepts only the exact capability payload"
Assert-Contains $hostRuntime "BuildTrackedOpenInit" `
    "Host passes the exact frozen nine-field tracked open payload"
Assert-Contains $hostRuntime "reconnect_bootstrap_sent" `
    "Host emits structured fresh reconnect-bootstrap evidence"
Assert-Contains $hostRuntime '["resumeActive"] = binding.ResumeActive' `
    "Host bootstrap forwards the explicit active-authority discriminator"
Assert-Contains $hostRuntime 'TryReadBoolean(payload, "resumeActive", out resumeActive)' `
    "Host bootstrap ack type-checks the active-authority discriminator"
Assert-Contains $hostRuntime 'resumeActive == binding.ResumeActive' `
    "Host bootstrap ack validates the exact active-authority discriminator"
Assert-Contains $hostRuntime 'reason=reconnect' `
    "Host reconnect query evidence is causally labelled"
Assert-Contains $hostRuntime 'terminal == "EXPIRED"' `
    "Host distinguishes the legal zero-watermark EXPIRED terminal"
Assert-Contains $hostRuntimeTests `
    "ResultPendingDisconnect_RecordsFirstExactCloseAndReleasesAfterNewGenerationQuery" `
    "Host regression covers reconnect bootstrap/query/release"
Assert-Contains $hostRuntimeTests `
    "AuthorityExpiredBeforeResult_AcceptsZeroWatermarkAndClosesExactly" `
    "Host regression covers pre-result zero-watermark expiry"
Assert-Contains $hostRuntimeTests `
    "LostWebCloseAck_IsQueriedUntilExactAckArrives" `
    "Host regression recovers a lost exact close ack without releasing pause early"
Assert-Contains $hostRuntime 'Log("close_query", "panelDigest="' `
    "Host emits structured causal close-query evidence"
Assert-Contains $hostRuntimeTests `
    "BindQueryDeliveryLoss_ReconcileTickRetriesUntilExactBoundReply" `
    "Host regression retries an uncertain bind from OpenBindUnknown"
Assert-Contains $hostRuntimeTests `
    "ResultWriteDeliveryUnknown_HostQueriesWithoutDependingOnWebQueryDelivery" `
    "Host regression queries AS2 directly after unknown result delivery"
Assert-Contains $hostRuntimeTests `
    "LostTerminalProjection_IsReplayedBeforeExactCloseQuery" `
    "Host regression replays cached terminal projection before exact close query"
Assert-Contains $hostRuntimeTests `
    "ResultAppliedTerminalPoll_PreservesTerminalKindWithoutReplayingTheWrite" `
    "Host regression polls ResultApplied authority without write replay"
Assert-Contains $hostRuntimeTests `
    "NativeExactClose_FirstFailureIsRetriedByReconcileTick" `
    "Host regression retries a failed native exact close"
Assert-Contains $hostRuntimeTests `
    "AuthorityActionInFlight_BlocksReleaseAndFreshIdentitySubstitution" `
    "Host regression freezes authority identity through completion and pause release"
Assert-Contains $hostRuntimeTests `
    "MalformedAuthorityBinding_DoesNotLeakInFlightOrBlockValidTerminalRelease" `
    "Host regression rejects malformed exact-key authority without leaking in-flight state"
Assert-Contains $hostRuntimeTests 'List<JObject> malformedPayloads' `
    "Host malformed-authority regression exercises a schema mutation matrix"
Assert-Contains $hostRuntimeTests 'MutatedAuthority(resultAck, "authorityTerminal", new JValue(1))' `
    "Host malformed-authority regression rejects result-ack boolean type confusion"
Assert-Contains $hostRuntimeTests 'MutatedAuthority(queryReply, "observedCallWatermark", new JValue("1"))' `
    "Host malformed-authority regression rejects query watermark type confusion"
Assert-Contains $hostRuntimeTests 'MutatedAuthority(revocationAck, "observedCallWatermark", new JValue("1"))' `
    "Host malformed-authority regression rejects revocation watermark type confusion"
Assert-Contains $hostRuntimeTests 'MutatedAuthority(terminalBase, "observedCallWatermark", new JValue(false))' `
    "Host malformed-authority regression rejects terminal watermark type confusion"
Assert-Contains $hostRuntimeTests `
    "GenericUnpauseWrite_IsLinearizedBeforeTrackedBegin" `
    "Host regression linearizes generic unpause with tracked begin"
Assert-Contains $hostRuntimeTests `
    "PendingGenericUnpause_MustSucceedBeforeFreshArm" `
    "Host regression blocks fresh arm until reconnect unpause delivery succeeds"
Assert-Contains $hostRuntimeTests `
    "LateTrackedOpenCompletion_CannotPolluteFreshArmOrSendOldFailure" `
    "Host regression rejects late tracked-open completion after identity reset"
Assert-Contains $hostRuntimeTests `
    "PauseReleaseFailure_RetainsTerminalFlowAndRetriesBeforeFreshArm" `
    "Host regression retains terminal flow when the external pause callback fails"
Assert-Contains $hostRuntimeTests `
    "ResultQueryFromPanelBound_EntersNoWriteReconcileWithoutApplyingOrReplayingResult" `
    "Host regression treats a Web result timeout as unknown delivery without inventing an enum"
Assert-Contains $hostRuntimeTests `
    "PanelQueueSettled_RetriesFreshArmAfterFastFailureRelease" `
    "Host regression retries fresh arm only after PanelHost clears its processing bit"
Assert-Contains $hostRuntimeTests `
    "PauseRelease_RetriesGenerationAdoptedInsideOldGenerationCallback" `
    "Host regression covers socket adoption occurring inside the old-generation release callback"
Assert-Contains $hostRuntimeTests `
    "SuccessfulOldReleaseRetriesAdoptedGenerationBeforeFreshArm" `
    "Host regression revalidates a reentrantly adopted generation even after an old send succeeds"
Assert-Contains $hostRuntimeTests `
    "SuccessfulOldReleaseCannotResetWhenAdoptedGenerationReleaseFails" `
    "Host regression retains authority when the adopted-generation release cannot be proved"
Assert-Contains $hostRuntimeTests `
    "WebArmAcceptedButUnobserved_TimesOutToFreshCapability" `
    "Host regression burns an unobserved Web arm and retries with a fresh capability"
Assert-Contains $hostRuntimeTests `
    "BootstrapAckLost_TimesOutAndRecoversThroughFreshArmAndCapability" `
    "Host regression burns an unacknowledged AS2 bootstrap and recovers through a fresh arm"
Assert-Contains $hostRuntimeTests `
    "MinigameTelemetryBoundary_AcceptsOnlyExactFourFieldAllowList" `
    "Host regression freezes the S0 telemetry defense-in-depth boundary"
Assert-Contains $hostRuntime '"web_arm_ack_timeout"' `
    "Host applies a bounded acknowledgement timeout to the Web arm"
Assert-Contains $hostRuntime '"as2_bootstrap_ack_timeout"' `
    "Host applies a bounded acknowledgement timeout to the AS2 bootstrap"
$bindingAckTimerSection = Get-Section $hostRuntime `
    "private bool StartBindingAckTimer" "private void DisposeBindingAckTimer"
Assert-Contains $bindingAckTimerSection 'ReferenceEquals(_binding, binding)' `
    "binding acknowledgement timeout is scoped to the exact capability object"
Assert-Contains $bindingAckTimerSection 'binding.State == expectedState' `
    "binding acknowledgement timeout is scoped to the expected protocol phase"
Assert-Contains $bindingAckTimerSection 'ReferenceEquals(binding.AckTimer, timer)' `
    "binding acknowledgement callback owns only its exact per-binding timer"
Assert-Contains $bindingAckTimerSection 'binding.AckTimer = timer;' `
    "binding acknowledgement timer is published on the exact capability binding"
Assert-Contains $bindingAckTimerSection '_binding = null;' `
    "a timed-out binding is removed before recovery"
Assert-Contains $bindingAckTimerSection 'TryIssueActiveReconnectBootstrap(retryGeneration)' `
    "a timed-out resume binding recovers only through a fresh reconnect bootstrap"
Assert-Contains $bindingAckTimerSection 'TryIssueWebArm();' `
    "a timed-out normal binding recovers only through a fresh Web arm"
Assert-Before $bindingAckTimerSection 'binding.AckTimer = timer;' `
    'timer.Change(_bindingAckTimeoutMilliseconds, Timeout.Infinite)' `
    "binding timer is installed under lock before its one-shot countdown starts"
$reconnectBootstrapSection = Get-Section $hostRuntime `
    "private void TryIssueActiveReconnectBootstrap" "private string ValidateArmPrerequisites"
Assert-Contains $reconnectBootstrapSection 'ReferenceEquals(_activeIdentity, expectedIdentity)' `
    "reconnect bootstrap rechecks the exact active authority identity before assignment"
Assert-Contains $reconnectBootstrapSection '_activeProcessBinding.Value.Equals(expected.Value)' `
    "reconnect bootstrap rechecks the exact process binding before assignment"
Assert-Contains $reconnectBootstrapSection '&& _binding == null)' `
    "reconnect bootstrap cannot overwrite a binding installed by a reentrant edge"
Assert-Before $reconnectBootstrapSection '_binding = binding;' `
    'sent = SendAs2Bootstrap(binding);' `
    "reconnect bootstrap assignment and exact-generation send remain linearized"
Assert-Contains $reconnectBootstrapSection 'Log("reconnect_bootstrap_superseded"' `
    "a superseded reconnect bootstrap emits bounded structured evidence"
Assert-Contains $hostRuntime 'Log("reconcile_tick", "state="' `
    "Host emits state-driven reconcile tick evidence"
Assert-Contains $hostRuntime 'SendAuthorityQuery(identity, "host_detected_unknown")' `
    "Host directly queries AS2 when result delivery becomes unknown"
Assert-Contains $hostRuntime 'SendAuthorityQuery(identity, "terminal_poll")' `
    "Host performs read-only ResultApplied terminal polling"
Assert-Contains $hostRuntime 'ResendLastWebAuthorityProjection()' `
    "Host retries the last exact authority projection"
$pauseReleaseSection = Get-Section $hostRuntime "private void TryReleasePauseAndReset" `
    "private bool TryValidateWebIdentity"
Assert-Contains $pauseReleaseSection '_pauseReleaseInProgress = true;' `
    "Host serializes external pause-release callback attempts"
Assert-Before $pauseReleaseSection 'Log("gate_rejected", "code=pause_release_failed origin=socket gen="' `
    'StartReconcileTick(identity)' `
    "Host schedules KnownTerminal retry after external pause callback failure"
Assert-Before $pauseReleaseSection `
    'callbackReleased = _releaseTrackedPause(attemptedGeneration);' `
    '_coordinator.TryReleaseGlobalPauseAndReset()' `
    "Host releases only the runtime-adopted generation before resetting authority"
Assert-Contains $pauseReleaseSection 'adoptedGeneration != attemptedGeneration' `
    "Host detects every different socket generation adopted during an in-flight release"
Assert-Before $pauseReleaseSection 'Log("pause_release_generation_retry",' `
    'continue;' `
    "Host chases the adopted generation while the release window remains closed"
Assert-Contains $pauseReleaseSection 'MaximumImmediateReleaseGenerationRetries' `
    "Host bounds pathological reentrant generation churn"
Assert-Contains $hostRuntimeTests `
    "NavigationPending_InvalidatesUnusedCapabilityAndRearmsFreshAfterCompletion" `
    "Host regression invalidates an idle arm across navigation and rearms fresh"
Assert-Contains $hostRuntimeTests `
    "ResumeActiveCapability_CannotBeConsumedByBeginAndStillAcceptsAuthority" `
    "Host regression reserves resumeActive capability for authority convergence"
Assert-Contains $hostRuntime '|| binding.ResumeActive' `
    "Host begin rejects resumeActive reconnect capabilities"
$beginSection = Get-Section $hostRuntime "private string HandleBegin" `
    "private bool ExecuteOpenGate"
Assert-True ([regex]::IsMatch($beginSection,
    'lock \(_sync\)[\s\S]*binding\.State = CapabilityState\.Consumed;[\s\S]*_coordinator\.TryBegin\([\s\S]*_activeIdentity = identity;')) `
    "Host consumes capability, reserves flow, and publishes active identity atomically"
Assert-Contains $beginSection 'if (_webNavigationPending)' `
    "Host begin fails closed under the same navigation-pending lock"
Assert-Contains $beginSection `
    'TryReadBoolean(payload, "pauseAcquired", out as2PauseAcquired)' `
    "Host type-checks the synchronous AS2 pause proof"
Assert-Contains $beginSection '|| !as2PauseAcquired' `
    "Host rejects begin without the synchronous AS2 pause proof"
Assert-Contains $hostRuntime 'pauseAcquired=true' `
    "Host structured begin evidence records the synchronous AS2 pause proof"
Assert-Contains $socketBridge 'if (!acquireS0WebPanelPause()) return false;' `
    "AS2 refuses to send begin until it synchronously acquires the webpanel lease"
$requestTrackedOpenSection = Get-Section $socketBridge `
    "private static function requestTrackedOpen" `
    "private static function handleBeginResponse"
Assert-Before $requestTrackedOpenSection 'if (!acquireS0WebPanelPause()) return false;' `
    'pauseAcquired: true' `
    "AS2 obtains the real pause lease before attesting begin"
$pauseAcquireSection = Get-Section $socketBridge `
    "private static function acquireS0WebPanelPause" `
    "private static function releaseS0WebPanelPause"
Assert-Before $pauseAcquireSection '_root.gameCommands["webPanelPause"]();' `
    'acquired = _root._webPanelPauseLease !== undefined;' `
    "AS2 proves the synchronous pause call actually established the lease"
Assert-Contains $pauseAcquireSection 'acquired = _root._webPanelPauseLease !== undefined;' `
    "AS2 verifies the pause lease state instead of trusting a call return"
$executeGateSection = Get-Section $hostRuntime "private bool ExecuteOpenGate" `
    "private void OnTrackedOpenCompleted"
Assert-Contains $executeGateSection '&& !_webNavigationPending' `
    "Host execution-time gate fails closed while Web navigation is pending"

Assert-Before $panelHost "if (cmd.TrackedExecutionGate == null || !cmd.TrackedExecutionGate())" `
    "if (!DoOpen(cmd.Name, cmd.InitDataJson, cmd.ReservedPanelInstanceId, true," `
    "PanelHost rechecks tracked authority immediately before DOM/open side effects"
Assert-Contains $panelHost "TryCloseTrackedPanelExact" `
    "PanelHost exposes exact tracked-instance close"
Assert-Contains $panelHost "_trackedLeaseInstanceId != null" `
    "PanelHost blocks generic close while a tracked S0 lease exists"
Assert-Contains $panelHost "public event Action OrchestrationSettled;" `
    "PanelHost exposes a post-pump orchestration-settled edge"
$settledSection = Get-Section $panelHost "private void NotifyOrchestrationSettledIfIdle" `
    "private void ExecuteCommand"
Assert-Contains $settledSection `
    '!_processing && _queue.Count == 0 && _activePanel == null' `
    "PanelHost emits settled only after processing, queue, and active panel are all clear"
Assert-Contains $settledSection `
    '&& !_trackedOpenReserved && _trackedLeaseInstanceId == null' `
    "PanelHost never emits settled while a tracked reservation or lease remains"
Assert-Before $settledSection 'lock (_queueLock)' 'try { settled(); }' `
    "PanelHost captures the callback under lock and invokes it outside the queue lock"
$enqueueSection = Get-Section $panelHost "private bool EnqueueAndPump" `
    "private void ScheduleNextPump"
Assert-Contains $enqueueSection 'else if (_trackedOpenReserved || _trackedLeaseInstanceId != null)' `
    "PanelHost rejects every generic command while a tracked reservation or lease exists"
Assert-Contains $enqueueSection 'if (cmd.IsTrackedClose)' `
    "PanelHost keeps exact tracked close as the only close path through the tracked gate"
$genericOpenSection = Get-Section $panelHost `
    "public bool TryOpenPanel" "public bool TryOpenTrackedPanel"
Assert-Contains $genericOpenSection 'return EnqueueAndPump(new PanelCommand(' `
    "generic open cannot bypass the tracked queue gate"
$genericCloseSection = Get-Section $panelHost "public void ClosePanel()" `
    "public void SetPanelOpenGate"
Assert-Contains $genericCloseSection `
    'EnqueueAndPump(new PanelCommand(PanelCommandKind.Close, null, null))' `
    "generic close cannot bypass the tracked queue gate"
$beginInvokeFailureSection = Get-Section $enqueueSection `
    'catch (Exception ex)' 'return true;'
Assert-Before $beginInvokeFailureSection `
    'FailPendingPumpDispatch(true);' 'return false;' `
    "synchronous BeginInvoke failure drains queued followers and returns enqueue failure"
$delayedPumpSection = Get-Section $panelHost `
    "private void DelayedKickOnHandleCreated" "private void FailPendingPumpDispatch"
Assert-Contains $delayedPumpSection 'FailPendingPumpDispatch(false);' `
    "delayed BeginInvoke failure reports failure to every queued tracked command"
$trackedOpenExecutionSection = Get-Section $panelHost `
    "private void ExecuteTrackedOpen" "private void ExecuteTrackedClose"
Assert-Before $trackedOpenExecutionSection 'try { ResetToClosedState(); }' `
    'outcome = webPostAccepted' `
    "tracked-open exception resets native state before classifying Web post delivery"
Assert-Contains $trackedOpenExecutionSection `
    '? TrackedOpenOutcome.PostAcceptedThenFailed' `
    "tracked-open exception preserves a post-accepted DOM uncertainty outcome"
Assert-Contains $trackedOpenExecutionSection `
    ': TrackedOpenOutcome.PostNotDelivered;' `
    "tracked-open exception distinguishes a provably undelivered Web post"
$trackedOpenSection = Get-Section $panelHost `
    "private bool DoOpen(string name" "private void RebindActivePanel"
Assert-Before $trackedOpenSection '_web.AssertWebPanelPause()' `
    'CaptureBackdrop(anchor)' `
    "tracked open acquires global pause before backdrop capture"
Assert-Before $trackedOpenSection '_web.AssertWebPanelPause()' `
    '_web.ResumeForPanel(panelRect)' `
    "tracked open acquires global pause before Web/native visual resume"
Assert-Before $trackedOpenSection '_web.AssertWebPanelPause()' `
    '_web.TryPostToWeb(payload)' `
    "tracked open acquires global pause before Web open delivery"
Assert-Contains $webOverlay 'public bool AssertWebPanelPause()' `
    "Web overlay exposes the real pause-delivery result"
Assert-Contains $webOverlay 'return TrySendGameCommand("webPanelPause");' `
    "Web overlay does not convert a failed pause send into success"
Assert-Before $beginSection '_acquireTrackedPause(binding.ConnectionGeneration)' `
    '_panel.TryOpenTracked' `
    "runtime synchronously acquires global pause before enqueueing tracked open"
Assert-Contains $beginSection 'Log("pause_acquire", "delivered=" + Lower(pauseAcquired)' `
    "runtime emits generation- and panel-bound pause acquisition evidence"
Assert-Contains $hostRuntime '?? throw new ArgumentNullException(nameof(acquireTrackedPause))' `
    "runtime cannot silently bypass tracked pause acquisition"
Assert-Contains $hostRuntime '?? throw new ArgumentNullException(nameof(releaseTrackedPause))' `
    "runtime cannot silently bypass tracked pause release"
Assert-Before $beginSection '_coordinator.CancelQueuedOpenExact(identity.RequestToken);' `
    'SendOpenFailed(identity, sessionId, "pre_execution_rejected")' `
    "pause-acquire failure revokes the queued identity before reporting open failure"
$trackedCompletionSection = Get-Section $hostRuntime `
    "private void OnTrackedOpenCompleted" "private void StartBindTimer"
$ordinaryFailureCompletionSection = Get-Section $trackedCompletionSection `
    'bool accepted;' 'private void StartBindTimer'
Assert-Before $ordinaryFailureCompletionSection 'if (!accepted)' `
    'RecordNativePanelClosed(identity,' `
    "Host accepts the exact coordinator transition before recording native close proof"
$staleCompletionSection = Get-Section $trackedCompletionSection `
    'if (!accepted)' '// PanelHost guarantees'
Assert-Contains $staleCompletionSection 'return;' `
    "stale tracked-open completion returns without advancing proof state"
Assert-NotContains $staleCompletionSection 'RecordNativePanelClosed(identity,' `
    "stale tracked-open completion cannot record native close proof"
Assert-Contains $hostRuntimeTests `
    "PauseAcquireDeliveryFailure_RevokesBeforeEnqueueAndNeverReportsOpenSuccess" `
    "Host regression freezes pause-acquire failure before tracked open enqueue"
Assert-Contains $hostRuntimeTests `
    "ResultAppliedTerminalPoll_PreservesTerminalKindWithoutReplayingTheWrite" `
    "Host regression preserves COMPLETED_NO_REWARD versus EXPIRED terminal projection"
Assert-Contains $hostRuntimeTests `
    "SuccessAuthorityStateMapping_RejectsRevokedAckAndTerminalPoll" `
    "Host regression rejects contradictory success/REVOKED authority evidence"
Assert-Contains $hostRuntimeTests `
    "InFlightReconcile_CannotEmitOldIdentityAfterFreshArm" `
    "Host regression prevents an old reconcile tick from crossing a fresh arm"
$reconcileSection = Get-Section $hostRuntime `
    "private void RunReconcileTick" "private void StopReconcileTick"
Assert-Contains $reconcileSection '_reconcileActionsInFlight += 1;' `
    "Host registers reconcile side effects as in-flight"
Assert-Contains $reconcileSection 'IsReconcileActionCurrent(identity, retryGeneration)' `
    "Host revalidates reconcile identity and generation before side effects"
Assert-Before $reconcileSection '_reconcileActionsInFlight -= 1;' `
    'TryReleasePauseAndReset()' `
    "Host clears in-flight reconcile state before retrying pause release"
Assert-Contains $pauseReleaseSection '_reconcileActionsInFlight != 0' `
    "Host defers pause release while reconcile actions are in flight"
Assert-Contains $pauseReleaseSection '_authorityActionsInFlight != 0' `
    "Host defers pause release while an identity-bound authority action is in flight"
$socketHandlerSection = Get-Section $hostRuntime `
    "public bool TryHandleSocketJson" "public bool TryHandleWebMessage"
Assert-Before $socketHandlerSection 'if (releaseInProgress)' `
    'JObject payload = message["payload"] as JObject;' `
    "socket authority traffic is rejected while external pause release is in progress"
$webHandlerSection = Get-Section $hostRuntime `
    "public bool TryHandleWebMessage" "public void OnWebDocumentNavigationStarting"
Assert-Before $webHandlerSection 'if (_pauseReleaseInProgress)' `
    'if (!TryReadString(message, "cmd", out command))' `
    "Web authority traffic is rejected while external pause release is in progress"
$authorityBindingSection = Get-Section $hostRuntime `
    "private bool TryEnterAuthorityBinding" "private void ExitAuthorityAction"
Assert-Before $authorityBindingSection 'identity = _activeIdentity;' `
    '_authorityActionsInFlight += 1;' `
    "authority handlers capture the exact active identity before registering in-flight work"
Assert-Before $authorityBindingSection '_authorityActionsInFlight += 1;' `
    'bool transferredToCaller = false;' `
    "authority binding installs exception-safe ownership after registering in-flight work"
Assert-Contains $authorityBindingSection `
    '&& SameIdentity(identity, _activeIdentity);' `
    "authority validation rechecks the captured identity after process inspection"
Assert-NotContains $hostRuntime 'payload.Value<int?>(' `
    "untrusted S0 payloads do not use throwing nullable-int coercion"
Assert-NotContains $hostRuntime 'payload.Value<long?>(' `
    "untrusted S0 payloads do not use throwing nullable-long coercion"
Assert-NotContains $hostRuntime 'payload.Value<bool?>(' `
    "untrusted S0 payloads do not use throwing nullable-bool coercion"
Assert-Before $authorityBindingSection 'catch' 'finally' `
    "malformed authority binding conversions fail closed inside the runtime"
Assert-Contains $authorityBindingSection `
    'Log("gate_rejected", "code=authority_binding_malformed origin=socket")' `
    "malformed authority binding uses the frozen structured rejection event"
Assert-Before $authorityBindingSection 'if (!transferredToCaller)' `
    'ExitAuthorityAction();' `
    "failed authority binding always returns its in-flight ownership"
$authorityExitSection = Get-Section $hostRuntime `
    "private void ExitAuthorityAction" "private JObject BuildArmPayload"
Assert-Before $authorityExitSection '_authorityActionsInFlight -= 1;' `
    'TryReleasePauseAndReset();' `
    "authority completion clears in-flight state before attempting pause release"
$socketDisconnectSection = Get-Section $hostRuntime `
    "public void OnSocketDisconnected" "public bool TryHandleSocketJson"
Assert-Contains $socketDisconnectSection `
    'EnsureNativePanelClosed(identity, "socket_disconnected")' `
    "socket disconnect uses the same idempotent exact native-close path"
$nativeCloseSection = Get-Section $hostRuntime `
    "private void EnsureNativePanelClosed" "private void RecordNativePanelClosed"
Assert-Contains $nativeCloseSection '_nativeCloseInProgress' `
    "Host suppresses duplicate native exact-close attempts while one is in flight"
Assert-Before $nativeCloseSection '_nativeCloseInProgress = true;' `
    '_panel.TryCloseExact' `
    "Host marks exact native close in flight before queueing PanelHost work"
$nativeProofSection = Get-Section $hostRuntime `
    "private void RecordNativePanelClosed" "private void TryReleasePauseAndReset"
Assert-Contains $nativeProofSection '&& !_nativePanelClosed' `
    "Host records the first exact native-close proof only once"
$genericPauseSection = Get-Section $hostRuntime "public bool TryReleaseGenericPause" `
    "public void OnPanelHostClosed"
Assert-Contains $genericPauseSection '_genericUnpausePending = !delivered;' `
    "Host retains a failed generic unpause for reconnect retry"
$socketReadySection = Get-Section $hostRuntime "public void OnSocketReady" `
    "public void OnWebReady"
Assert-Contains $socketReadySection `
    '_liveGeneration > 0 && connectionGeneration < _liveGeneration' `
    "Host rejects only a strictly lower socket-ready generation"
Assert-Contains $socketReadySection `
    'Log("gate_rejected", "code=stale_socket_ready origin=socket gen="' `
    "Host emits positive generation-bound evidence for a stale ready edge"
Assert-Before $socketReadySection 'if (staleReady)' `
    'Log("socket_ready", "gen=" + connectionGeneration);' `
    "a stale socket-ready returns before mutating accepted ready evidence"
Assert-Contains $socketReadySection `
    'if (retryGeneric && !TryReleaseGenericPause()) return;' `
    "socket reconnect cannot fresh-arm before a pending generic unpause succeeds"
Assert-Contains $hostRuntimeTests `
    "StaleSocketReadyCannotRollBackGenerationOrCancelFreshBindingTimeout" `
    "Host regression freezes monotonic generation adoption and preserves the fresh binding timer"
$webReadySection = Get-Section $hostRuntime "public void OnWebReady" `
    "public void OnSocketDisconnected"
Assert-Contains $webReadySection `
    'if (retryGeneric && !TryReleaseGenericPause()) return;' `
    "Web readiness cannot fresh-arm before a pending generic unpause succeeds"
$scheduleReconcileSection = Get-Section $hostRuntime `
    "private void ScheduleReconcileTick" "private void RunReconcileTick"
Assert-Before $scheduleReconcileSection `
    'if (_disposed || retryGeneration != _reconcileGeneration' `
    'newTimer = new Timer' `
    "Host validates reconcile identity and generation before constructing a timer"
Assert-Contains $scheduleReconcileSection `
    'current = ReferenceEquals(_reconcileTimer, newTimer)' `
    "stale reconcile callbacks cannot publish work for a replaced timer"
Assert-Before $scheduleReconcileSection 'oldTimer = _reconcileTimer;' `
    '_reconcileTimer = newTimer;' `
    "reconcile timer replacement publishes the exact new timer under the runtime lock"
Assert-Before $webOverlay "type == DevLockboxS0Runtime.WebControlType" `
    'else if (type == "task")' `
    "Web S0 control/business messages are intercepted before the generic task bridge"
$navigationStartSection = Get-Section $webOverlay `
    '_webView.CoreWebView2.NavigationStarting +=' `
    '_webView.CoreWebView2.ContentLoading +='
Assert-Before $navigationStartSection '_webReady = false;' `
    'runtime.OnWebDocumentNavigationStarting(args.NavigationId)' `
    "top-level navigation invalidates Web readiness before runtime navigation handling"
Assert-Contains $webOverlay "runtime.OnWebDocumentNavigationStarting(args.NavigationId)" `
    "Web overlay forwards the exact top-level NavigationId at navigation start"
Assert-Contains $webOverlay "runtime.OnWebDocumentContentLoading(args.NavigationId)" `
    "Web overlay proves that the matching navigation loaded a new document"
Assert-Contains $webOverlay `
    "runtime.OnWebDocumentNavigationCompleted(args.NavigationId, args.IsSuccess)" `
    "Web overlay forwards matching NavigationId and success at navigation completion"
$runtimeNavigationStartSection = Get-Section $hostRuntime `
    "public void OnWebDocumentNavigationStarting" "public void OnWebDocumentContentLoading"
Assert-Before $runtimeNavigationStartSection 'invalidatedBinding = _binding;' `
    '_binding = null;' `
    "navigation start captures and invalidates an unused idle capability under the runtime lock"
Assert-Contains $runtimeNavigationStartSection `
    'DisposeBindingAckTimer(invalidatedBinding);' `
    "navigation start disposes only the exact invalidated idle binding timer"
Assert-Contains $hostRuntime 'if (!isSuccess || !loadedNewDocument)' `
    "failed or same-document navigation cannot prove old-document teardown"
Assert-Contains $hostRuntime 'Log("document_epoch_advance", "navigationId=" + navigationId' `
    "document epoch evidence is bound to the exact WebView2 NavigationId"
Assert-Contains $hostRuntime 'Log("bind_query_reply", "accepted=" + Lower(applied) + " binding=" + binding' `
    "bind-query evidence records the exact accepted conclusion"
Assert-Contains $hostRuntime '" panelDigest=" + Digest(identity.PanelInstanceId)' `
    "Host structured recovery evidence carries a redacted panel identity"
Assert-Contains $hostRuntime 'Log("query_reply", "flowCallId=1 watermark=" + watermark' `
    "authority-query evidence records the exact S0 call identity and watermark"
Assert-Contains $hostRuntime 'Log("panel_exact_close", "closed=false reason=panel_host_unavailable"' `
    "unavailable PanelHost exact-close failures remain structured evidence"
Assert-Contains $webOverlay "return runtime.TryReleaseGenericPause();" `
    "generic Web close uses the runtime-linearized unpause gate"
Assert-Contains $hostRuntime 'public static bool TryNormalizeMinigameTelemetry' `
    "Host owns a second exact telemetry allow-list boundary"
Assert-Contains $webOverlay 'code=non_allowlisted_minigame_session' `
    "Host drops raw Lockbox session payloads without serializing them while S0 is active"
$minigameTelemetrySection = Get-Section $webOverlay `
    'case "minigame_session":' "private void RespondPanelDomainError"
Assert-Before $minigameTelemetrySection `
    'TryLogS0MinigameSession(payload,' `
    'string game = (string)payload["game"];' `
    "S0 intercepts every minigame session before trusting a missing or forged game field"
$s0TelemetryLogSection = Get-Section $webOverlay `
    "internal static bool TryLogS0MinigameSession" `
    "internal static bool IsValidSkillCloseEnvelope"
Assert-Before $s0TelemetryLogSection `
    'DevLockboxS0Runtime.TryNormalizeMinigameTelemetry(' `
    'if (!holdsGlobalPause' `
    "S0 helper applies the exact telemetry allow-list before classifying late non-S0 sessions"
Assert-Contains $s0TelemetryLogSection `
    'code=non_allowlisted_minigame_session' `
    "malformed S0 telemetry crosses logging only as a fixed rejection category"
Assert-Contains $webOverlay `
    'cmd=minigame_session payload=redacted' `
    "the outer panel routing log redacts every generic minigame envelope"
Assert-NotContains $coordinator "TelemetryEventCategory" `
    "coordinator no longer carries a conflicting telemetry category schema"
Assert-NotContains $coordinator "CreateSanitizedTelemetry" `
    "coordinator no longer exposes an unused telemetry normalization path"

Assert-Contains $adapterTest `
    "pre-result authoritative EXPIRED is terminal and permits one exact close ack" `
    "Web adapter regression freezes legal pre-result EXPIRED close semantics"
Assert-Contains $adapterTest `
    "CLOSED remains an exact proof tombstone across replay delivery failures" `
    "Web adapter regression retains exact closed proof after send-true uncertainty"
Assert-Contains $actualWireTest `
    "send-true close proof is replayable after fresh rearm without closing the new DOM" `
    "actual wire retains old close proof independently of a fresh active flow"
Assert-Contains $actualWireTest `
    "send-true teardown proof replays by old identity without disturbing a fresh flow" `
    "actual wire retains old teardown proof independently of a fresh active flow"
Assert-Contains $actualWireTest `
    "S0 suppresses raw Lockbox sessions and emits only four-field telemetry" `
    "actual wire regression prevents raw minigame-session telemetry escape"
Assert-Contains $actualWireTest `
    "send-true result silence times out into query without replaying the write" `
    "actual wire treats send-true result delivery as unknown until an authority ack"
Assert-Contains $actualWireTest `
    "cancel send-false immediately starts causal query and never replays cancel" `
    "actual wire immediately reconciles a provably failed cancel send without replay"
Assert-Contains $crossStackVerifier "reconnect_bootstrap_sent" `
    "actual verifier requires a fresh reconnect bootstrap"
Assert-Contains $crossStackVerifier 'panel_queue_idle: req("pauseHeld")' `
    "actual verifier admits only the exact PanelHost settled evidence schema"
Assert-Contains $crossStackVerifier `
    'pause_release_generation_retry: req("oldGen", "newGen")' `
    "actual verifier freezes the reentrant pause-release generation schema"
Assert-Contains $crossStackVerifier 'reconnect_bootstrap_superseded: req("gen")' `
    "actual verifier freezes bounded superseded-bootstrap evidence"
Assert-Contains $crossStackVerifier 'telemetry_dropped: req("code")' `
    "actual verifier admits only a bounded telemetry-drop category"
Assert-Contains $hostRuntime 'Log("tracked_open_stale", "markedBindUnknown="' `
    "Host logs stale tracked-open settlement without raw identity material"
Assert-Contains $crossStackVerifier `
    'tracked_open_stale: req("markedBindUnknown", "panelDigest")' `
    "actual verifier admits the exact stale tracked-open settlement schema"
$safeRejectionsSection = Get-Section $crossStackVerifier `
    "const SAFE_REJECTIONS" "const RECONCILE_STATES"
Assert-Contains $safeRejectionsSection '"stale_socket_ready"' `
    "actual verifier classifies a proven lower-generation ready edge as a safe rejection"
Assert-Contains $crossStackVerifier `
    'generation >= highestReadyGeneration' `
    "actual verifier rejects rollback in accepted socket-ready generations"
Assert-Contains $crossStackVerifier `
    'highestReadyGeneration > staleGeneration' `
    "actual verifier requires stale-ready evidence to follow a strictly higher adopted generation"
Assert-Contains $crossStackVerifier 'fields.resumeActive === "false"' `
    "actual verifier requires ordinary bootstrap to settle, not resume, authority"
Assert-Contains $crossStackVerifier 'fields.resumeActive === "true"' `
    "actual verifier requires reconnect bootstrap to resume active authority"
Assert-Contains $crossStackVerifier `
    "independently prove Web force-close and native PanelHost close" `
    "actual verifier never treats native PanelHost close as Web DOM self-attestation"
Assert-Contains $crossStackVerifier "lost terminal projection/close ack" `
    "actual verifier requires cached projection and causal close-query recovery"
Assert-Contains $crossStackVerifier "state-driven reconcile tick" `
    "actual verifier requires timed recovery after a Host-to-Web delivery loss"
Assert-Contains $crossStackVerifier 'reason === "host_detected_unknown"' `
    "actual verifier requires a Host-direct AS2 query for unknown write delivery"
Assert-Contains $crossStackVerifier 'reason === "timer_reconcile"' `
    "actual verifier requires timer-driven AS2 query retry"
Assert-Contains $crossStackVerifier 'state === "resultapplied"' `
    "actual verifier requires the ResultApplied terminal-poll state"
Assert-Contains $crossStackVerifier "authority_projection_retry" `
    "actual verifier requires exact authority projection replay evidence"
Assert-Contains $crossStackVerifier "exact native close failure was not retried" `
    "actual verifier rejects unrecovered native close failure"
Assert-Contains $crossStackVerifier "reserve resumeActive capability" `
    "actual verifier forbids consuming reconnect capability as a new begin"
Assert-Contains $crossStackVerifier "pause release failure did not retain KnownTerminal" `
    "actual verifier requires terminal-flow retention after pause callback failure"
Assert-Contains $crossStackVerifier "document epoch teardown must reconcile AS2 authority" `
    "actual verifier requires authority convergence after document replacement"
Assert-Contains $crossStackVerifierTest `
    "native PanelHost close cannot self-attest that Web DOM/current was cleared" `
    "verifier regression rejects local-only close proof"
Assert-Contains $crossStackVerifierTest `
    "successful completion without matching ContentLoading cannot prove document teardown" `
    "verifier regression rejects same-document navigation as teardown proof"
Assert-Contains $crossStackVerifierTest `
    "resumeActive reconnect capability cannot be consumed by a new begin" `
    "verifier regression rejects reconnect capability consumption"
Assert-Contains $crossStackVerifierTest `
    "pause callback failure must retain KnownTerminal and retry before fresh arm" `
    "verifier regression rejects early reset/rearm after pause callback failure"
Assert-Contains $crossStackVerifierTest `
    "pause callback failure forbids fresh Web arm before release succeeds" `
    "verifier regression explicitly rejects an early Web re-arm"
Assert-Contains $crossStackVerifierTest `
    "unknown query replies still require a valid identity and authority tuple" `
    "verifier regression rejects malformed unknown authority replies"
Assert-Contains $crossStackVerifierTest `
    "bind-query evidence must match the reserved panel identity" `
    "verifier regression rejects cross-panel bind-query evidence"
Assert-Contains $crossStackVerifierTest `
    "document epoch evidence must match the starting NavigationId" `
    "verifier regression rejects sequential-only navigation correlation"
Assert-Contains $crossStackVerifierTest `
    "a dangling reserved attempt cannot coexist with otherwise valid evidence" `
    "verifier regression requires every reserved attempt to converge"
Assert-Contains $crossStackVerifierTest `
    "a rejected old-document teardown invalidates an otherwise clean capture" `
    "verifier regression rejects failed teardown evidence globally"
Assert-Contains $crossStackVerifierTest `
    "authority acknowledgement watermarks stay in the single-call domain" `
    "verifier regression freezes the S0 authority watermark domain"
Assert-Contains $crossStackVerifierTest `
    "pause release evidence must match its reserved panel identity" `
    "verifier regression binds pause release to the reserved panel"
Assert-Contains $crossStackVerifierTest `
    "success query disposition cannot claim revoked authority" `
    "verifier regression rejects success/authority-state contradictions"
Assert-Contains $crossStackVerifierTest `
    "cancel query disposition cannot claim expired authority" `
    "verifier regression rejects non-success/authority-state contradictions"
Assert-Contains $crossStackVerifierTest `
    "LOCK_PENDING cannot appear as an authority acknowledgement" `
    "verifier regression rejects impossible authority acknowledgements"
Assert-Contains $crossStackVerifierTest `
    "result-forward failure reasons are a closed producer domain" `
    "verifier regression freezes result-forward failure reasons"
Assert-Contains $crossStackVerifierTest `
    "pause release cannot weaken any of its three proofs" `
    "verifier regression requires terminal, DOM, and native close proofs"
Assert-Contains $crossStackVerifierTest `
    "reconnect bootstrap always reserves active-authority semantics" `
    "verifier regression freezes reconnect bootstrap semantics"
Assert-Contains $crossStackVerifierTest `
    "generic unpause blocks identify the active S0 lease" `
    "verifier regression freezes generic-unpause rejection identity"
Assert-Contains $crossStackVerifierTest `
    "document epoch advances exactly once per matching navigation" `
    "verifier regression freezes single-step document epoch advance"
Assert-Contains $crossStackVerifierTest `
    "every reserved attempt acquires the exact global pause before enqueue" `
    "verifier regression requires exact pause acquisition for each reservation"
Assert-Contains $crossStackVerifierTest `
    "pause acquisition cannot occur after tracked-open enqueue" `
    "verifier regression freezes pause-before-enqueue ordering"
Assert-Contains $crossStackVerifierTest `
    "pause acquisition uses the begin binding generation" `
    "verifier regression rejects cross-generation pause acquisition"
Assert-Contains $crossStackVerifierTest `
    "failed pause delivery cannot count as tracked-open acquisition" `
    "verifier regression rejects failed pause delivery"
Assert-Contains $crossStackVerifierTest `
    "pause acquisition cannot exist without a reserved attempt" `
    "verifier regression rejects stray pause acquisition"
Assert-Contains $crossStackVerifierTest `
    "pause release cannot precede reservation acquisition and enqueue" `
    "verifier regression freezes release after pause acquisition and enqueue"
Assert-Contains $crossStackVerifierTest `
    "Host begin evidence requires the synchronous AS2 pause lease proof" `
    "verifier regression rejects begin without AS2 pause acquisition proof"
Assert-Contains $crossStackVerifierTest `
    "binding-timeout and reentrant-generation recovery events use the frozen safe schema" `
    "verifier regression admits bounded timeout/reentrant recovery evidence"
Assert-Contains $crossStackVerifierTest `
    "new recovery fields retain exact types and generation semantics" `
    "verifier regression rejects malformed recovery event fields"
Assert-Contains $crossStackVerifierTest `
    "telemetry drops and optional rejection/result fields stay in closed producer domains" `
    "verifier regression freezes new optional fields and telemetry categories"
Assert-Contains $crossStackVerifierTest `
    "stale socket-ready is safe only below an earlier monotonically adopted generation" `
    "verifier regression rejects non-positive, equal, future, and regressing socket generations"

$overlayPath = Join-Path $projectRoot "launcher\web\overlay.html"
$bootstrapPath = Join-Path $projectRoot `
    "launcher\web\modules\minigames\lockbox\chest-s0-dev-bootstrap.js"
$adapterPath = Join-Path $projectRoot `
    "launcher\web\modules\minigames\lockbox\chest-s0-adapter.js"
$actualWirePath = Join-Path $projectRoot `
    "launcher\web\modules\minigames\lockbox\chest-s0-actual-wire.js"
$webS0AllowList = @(
    $overlayPath,
    $bootstrapPath,
    $adapterPath,
    $actualWirePath,
    (Join-Path $projectRoot "launcher\web\modules\minigames\lockbox\dev\s0-harness.html"),
    (Join-Path $projectRoot "launcher\web\modules\minigames\lockbox\dev\s0-harness.js")
)
$overlay = Read-RepoText "launcher\web\overlay.html"
$bootstrap = Read-RepoText `
    "launcher\web\modules\minigames\lockbox\chest-s0-dev-bootstrap.js"
$actualWire = Read-RepoText `
    "launcher\web\modules\minigames\lockbox\chest-s0-actual-wire.js"
$adapter = Read-RepoText `
    "launcher\web\modules\minigames\lockbox\chest-s0-adapter.js"
$panels = Read-RepoText "launcher\web\modules\panels.js"
Assert-Contains $overlay `
    '<script src="modules/minigames/lockbox/chest-s0-dev-bootstrap.js"></script>' `
    "production overlay loads only the dormant S0 bootstrap"
Assert-NotContains $overlay "chest-s0-adapter.js" `
    "production overlay never eagerly loads the S0 adapter"
Assert-NotContains $overlay "chest-s0-actual-wire.js" `
    "production overlay never eagerly loads the actual wire"
Assert-Contains $bootstrap 'var state = "DORMANT";' `
    "S0 production bootstrap is dormant by default"
Assert-Contains $bootstrap 'locationValue.protocol === "https:"' `
    "S0 bootstrap requires the exact HTTPS overlay origin"
Assert-Contains $bootstrap 'locationValue.hostname === "overlay.local"' `
    "S0 bootstrap requires the exact overlay.local host"
Assert-Contains $bootstrap 'locationValue.pathname === "/overlay.html"' `
    "S0 bootstrap requires the exact production overlay path"
Assert-Contains $bootstrap "hasExactKeys(value, ARM_KEYS)" `
    "S0 bootstrap rejects non-exact seven-field arm payloads"
Assert-Contains $bootstrap "LazyLoader.load([ADAPTER_SCRIPT, ACTUAL_WIRE_SCRIPT])" `
    "S0 adapter and actual wire load only after an accepted arm"
Assert-True (-not [regex]::IsMatch(($bootstrap + $actualWire),
    'randomUUID|Math\.random|crypto\.getRandomValues')) `
    "Web S0 wire never generates its own capability"
Assert-Contains $actualWire 'var OPEN_KEYS = ARM_KEYS.concat(["flowHandle", "panelInstanceId"]);' `
    "actual Web open schema is the exact frozen nine fields"
Assert-Contains $actualWire 'if (!hasOwn(value, OPEN_KEYS[i])) return false;' `
    "unmarked S0 candidates require a complete protocol and identity shape"
Assert-Contains $actualWire 'value.source === S0.SOURCE || value.fixture === S0.FIXTURE' `
    "dedicated S0 source or fixture markers remain fail-closed even on malformed envelopes"
Assert-Contains $actualWire "rejectedOpenCloseToken !== token" `
    "rejected non-armed S0 visual cleanup is bound to its exact open token"
Assert-Contains $actualWire 'record("panel_cleanup_exception", "rejected_open_local_close")' `
    "rejected-open cleanup exceptions cannot strand the visual or leak exception text"
Assert-Contains $actualWire 'checked.arm.capability === arm.capability' `
    "actual wire rejects a duplicate current arm before superseding it"
Assert-Contains $actualWire "hostEvidenceRequired: true" `
    "Web evidence declares that Host evidence is mandatory"
Assert-Contains $actualWire "selfAttestedCrossStack: false" `
    "Web self-report cannot claim cross-stack evidence"
Assert-Contains $actualWire "selfAttestedProductionHost: false" `
    "Web self-report cannot claim production Host evidence"
Assert-Contains $actualWire "disableForbiddenControls(el)" `
    "actual wire disables forbidden reroll/export/hint/profile/HUD controls"
Assert-Contains $actualWire 'completeForcedTeardown("force_close")' `
    "actual wire converts Host force-close into an independent DOM teardown proof"
Assert-Contains $actualWire 'record("panel_cleanup_exception", "original_on_close")' `
    "tracked exact close observes original onClose failure without leaking exception text"
Assert-Contains $actualWire 'record("panel_cleanup_exception", "original_on_force_close")' `
    "tracked force close observes original onForceClose failure without losing teardown"
Assert-Contains $bootstrap 'sendControl("teardown_ack", payload)' `
    "dormant bootstrap forwards the exact Web DOM teardown acknowledgement"
Assert-Contains $actualWireTest `
    "force close proves Web DOM teardown independently and clears current for fresh rearm" `
    "actual-wire regression separates Web DOM teardown from native PanelHost close"
Assert-Contains $actualWireTest `
    "a fresh Host arm supersedes an unused one-shot arm after a panel-busy begin rejection" `
    "actual-wire regression preserves a valid arm across duplicate and delayed capability failures"
Assert-Contains $actualWireTest `
    "single and partial S0 field collisions remain ordinary Lockbox open and rebind data" `
    "actual-wire regression keeps partial S0-name collisions on the ordinary Lockbox path"
Assert-Contains $actualWireTest "malformedDedicatedSource" `
    "actual-wire regression rejects a partial envelope carrying the dedicated S0 source"
Assert-Contains $actualWireTest "malformedDedicatedFixture" `
    "actual-wire regression rejects a partial envelope carrying the dedicated S0 fixture"
Assert-Contains $actualWireTest "ordinaryTakeoverAfterRejectedOpen" `
    "actual-wire regression preserves a newer ordinary rebind against stale rejected-open cleanup"
Assert-Contains $actualWireTest `
    "real ordinary PanelHost init remains untouched after an exact S0 close reaches IDLE" `
    "actual-wire regression keeps the real ordinary PanelHost shape intact after S0 settles"
Assert-Contains $actualWireTest `
    "pre-result EXPIRED crosses the actual wire and emits one exact close ack" `
    "actual-wire regression carries legal pre-result expiry through the real Web wire"
Assert-Contains $adapter "closed_after_retry" `
    "Web adapter exposes the exact lost-close-ack recovery state"
Assert-Contains $adapterTest `
    "a lost close ack is retried with the same exact identity before pause release" `
    "Web adapter regression freezes same-identity close retry semantics"
Assert-Contains $actualWireTest `
    "close_query recovers a lost exact close ack without reopening the DOM" `
    "actual-wire regression recovers close ack loss without DOM replay"
Assert-Contains $actualWireTest `
    "production-order onClose exception cannot strand exact close proof" `
    "actual-wire regression preserves exact close proof across panel cleanup failure"
Assert-Contains $actualWireTest `
    "production force teardown survives both cleanup callbacks throwing" `
    "actual-wire regression preserves teardown proof across both cleanup failures"
Assert-Contains $panels "isLockboxS0OpenLog(data)" `
    "generic panel logger detects S0 open before serializing initData"
Assert-Contains $panels "__lockboxChestS0" `
    "generic panel logger recognizes the nested browser-host-shim S0 envelope"
Assert-Contains $actualWireTest `
    "S0 panel logging replaces the complete production initData with one constant" `
    "actual-wire Node regression proves S0 log identity redaction and ordinary log compatibility"
Assert-Contains $actualWireTest `
    "nested browser-host-shim S0 identity receives the same whole-initData redaction" `
    "actual-wire Node regression covers the nested Browser harness envelope"
Assert-Contains $adapterTest `
    "bind query delivery loss remains retryable with the same exact identity" `
    "Web adapter regression keeps uncertain bind query retryable"
Assert-Contains $actualWireTest `
    "lost forced-teardown proof is retained and resent by an exact Host query" `
    "actual-wire regression retains DOM teardown proof until Host delivery succeeds"
Assert-Contains $actualWireTest `
    "a locally unknown result query retries until Host reconciliation is received" `
    "actual-wire regression keeps Web query advisory while Host owns AS2 convergence"
Assert-Contains $actualWire "pendingTeardown" `
    "actual wire retains an undelivered DOM teardown proof"
Assert-Contains $actualWire "scheduleTeardownRetry" `
    "actual wire retries an undelivered teardown acknowledgement"

$webS0References = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "launcher\web") `
    -Recurse -File | Where-Object { $_.Extension -in @(".js", ".html") } |
    Select-String -Pattern 'chest-s0-(?:adapter|actual-wire|dev-bootstrap)\.js|LockboxChestS0(?:Adapter|ActualWire|DevBootstrap)|lockbox_chest_s0')
$unexpectedWebS0References = @($webS0References | Where-Object {
    $candidatePath = $_.Path
    -not @($webS0AllowList | Where-Object {
        [String]::Equals($_, $candidatePath, [StringComparison]::OrdinalIgnoreCase)
    }).Count
})
Assert-True ($unexpectedWebS0References.Count -eq 0) `
    "S0 Web references are confined to the frozen actual-wire and dev-harness allow-list"
$ordinaryLockboxS0References = @(Get-ChildItem -LiteralPath `
    (Join-Path $projectRoot "launcher\web\modules\minigames\lockbox") -Recurse -File |
    Where-Object {
        $_.Name -in @("lockbox-panel.js", "lockbox-core.js") -or
        $_.Name -eq "panels-lazy-registry.js"
    } | Select-String -Pattern 'lockbox_chest_s0|LockboxChestS0|chest-s0-')
Assert-True ($ordinaryLockboxS0References.Count -eq 0) `
    "ordinary Lockbox and lazy-registry code remain free of S0 wire references"

# These are executable cross-stack safety contracts, not cosmetic source preferences.  Keep all
# findings in one fail-closed assertion so a static run reports every known convergence gap.
$actualContractIssues = @()
if ($hostRuntimeTests.IndexOf('"resumeActive"', [StringComparison]::Ordinal) -lt 0) {
    $actualContractIssues += "Host bootstrap regression does not echo and distinguish resumeActive=false/true"
}
$disconnectSection = Get-Section $hostRuntime `
    "public void OnSocketDisconnected" "public bool TryHandleSocketJson"
if ($disconnectSection.IndexOf("_coordinator.RecordExactCloseAck",
        [StringComparison]::Ordinal) -ge 0) {
    $actualContractIssues += "disconnect PanelHost close self-attests Web DOM close"
}
$forceCloseSection = Get-Section $actualWire `
    "wrapped.onForceClose = function()" "return wrapped;"
if (($forceCloseSection.IndexOf('completeForcedTeardown("force_close")',
        [StringComparison]::Ordinal) -lt 0) -or
    ($bootstrap.IndexOf('sendControl("teardown_ack", payload)',
        [StringComparison]::Ordinal) -lt 0)) {
    $actualContractIssues += "Web force_close does not independently prove DOM teardown and clear current"
}
$armRejectedSection = Get-Section $hostRuntime `
    "private void HandleWebArmRejected" "private bool SendAs2Bootstrap"
if ($armRejectedSection.IndexOf("CapabilityState.WebArmPending",
        [StringComparison]::Ordinal) -lt 0) {
    $actualContractIssues += "runtime rejection can clear a consumed/active Host binding"
}
if (-not [regex]::IsMatch($hostRuntimeTests,
        'public void \w*(?:Document|Navigation)\w*(?:Release|Converg|Terminal)\w*\s*\(')) {
    $actualContractIssues += "active document navigation has no authority-convergence regression"
}
if (-not [regex]::IsMatch($hostRuntimeTests,
        'public void \w*Panel\w*Busy\w*(?:Rearm|Retry|Fresh)\w*\s*\(')) {
    $actualContractIssues += "panel-busy begin rejection has no fresh re-arm/retry regression"
}
if (-not [regex]::IsMatch(($hostRuntimeTests + $socketBridgeTest),
        '(?:Begin|begin)\w*(?:InFlight|Pending|Response)\w*(?:Disconnect|SocketClose)\w*(?:Rearm|Retry|Fresh|Recover)')) {
    $actualContractIssues += "begin-in-flight disconnect with Host still idle has no recovery regression"
}
$savedErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = "Continue"
    $adapterContractOutput = @(& node (Join-Path $projectRoot `
        "tools\test-lockbox-chest-s0-adapter.js") 2>&1)
    $adapterContractExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $savedErrorAction
}
if ($adapterContractExit -ne 0) {
    $actualContractIssues += "Web adapter rejects legal pre-result EXPIRED/close (B12)"
}
$savedErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = "Continue"
    $actualWireContractOutput = @(& node (Join-Path $projectRoot `
        "tools\test-lockbox-chest-s0-actual-wire.js") 2>&1)
    $actualWireContractExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $savedErrorAction
}
if ($actualWireContractExit -ne 0) {
    $actualContractIssues += "Web actual-wire convergence regressions failed"
}
$as2ProductionAdapterCalls = @(& rg -l --glob '*.as' --glob '!**/*Test.as' `
    --glob '!**/ChestSessionService.as' --glob '!test-runners/**' `
    'ChestSessionService\.(setDevelopmentEnabled|configureAdapters)\s*\(' `
    (Join-Path $projectRoot "scripts"))
$as2AdapterScanExit = $LASTEXITCODE
Assert-True ($as2AdapterScanExit -eq 0 -or $as2AdapterScanExit -eq 1) `
    "AS2 production adapter scan completed"
$expectedAs2AdapterOwner = [System.IO.Path]::GetFullPath((Join-Path $projectRoot `
    "scripts\类定义\org\flashNight\arki\scene\ChestS0SocketBridge.as"))
Assert-True ($as2ProductionAdapterCalls.Count -eq 1 -and
        [System.IO.Path]::GetFullPath([string]$as2ProductionAdapterCalls[0]) -eq
            $expectedAs2AdapterOwner) `
    "ChestSession dev gate/adapters have exactly one production owner: ChestS0SocketBridge"

Assert-True ($actualContractIssues.Count -eq 0) `
    ("actual-wire convergence contracts: " + ($actualContractIssues -join "; "))

Write-Output ("[PASS] chest-s0 static wiring: {0} assertions" -f $assertions)
