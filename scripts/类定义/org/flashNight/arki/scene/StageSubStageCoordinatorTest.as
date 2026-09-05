import org.flashNight.arki.scene.WarlordSubStageRunner;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.merc.ArenaCalibrationService;

/** Warlord outer wire、不可复活终态与去重的 focused regression。 */
class org.flashNight.arki.scene.StageSubStageCoordinatorTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var cases:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        cases = 0;
        trace("=== StageSubStageCoordinatorTest start ===");

        testStartEnvelopeAndFailure(); cases++;
        testSynchronousResultWinsTransportReturn(); cases++;
        testPlayerPortraitUsesSavedAuthorityProjection(); cases++;
        testAttemptFencing(); cases++;
        testBusinessTerminalFencing(); cases++;
        testFrozenCannotReopen(); cases++;
        testStageRunIdentityProjection(); cases++;
        testRecoverySurfaceRemoved(); cases++;
        testSmallRosterFormationProjection(); cases++;
        testArenaDistanceProjection(); cases++;

        trace("StageSubStageCoordinatorTest Tests Passed: " + passed);
        trace("StageSubStageCoordinatorTest Tests Failed: " + failed);
        if (failed > 0 || passed != 78 || cases != 10) {
            throw new Error("StageSubStageCoordinatorTest failed: " + failed
                + " failures, " + passed + "/78 assertions, " + cases + "/10 cases");
        }
        trace("StageSubStageCoordinatorTest Cases Passed: 10/10");
        trace("=== StageSubStageCoordinatorTest end ===");
    }

    private static function testStartEnvelopeAndFailure():Void {
        var observer:Object = makeObserver();
        var transport:Object = makeTransport(true);
        var runner:WarlordSubStageRunner = new WarlordSubStageRunner(
            "run.1", "sub.1", "scenario.1", observer, transport);
        var before:Object = runner.getBindingSnapshot();
        check(before.schema == "warlord.stage-outer-binding.v1"
                && before.revision == 0,
            "C02 binding starts at exact v1 revision zero");
        check(before.runId == "run.1" && before.subStageId == "sub.1"
                && before.scenarioRef == "scenario.1"
                && String(before.callId).indexOf("warlord.stage.") == 0,
            "C02 binding carries stable opaque identity plus generated callId");
        check(runner.start() && runner.getPhase() == "awaiting_terminal",
            "C02 successful send enters awaiting_terminal");
        check(transport.calls.length == 1
                && transport.calls[0].task == "warlord_stage_start"
                && transport.calls[0].extra == null,
            "C02 AS2 uses the frozen generic task transport shape");
        check(countOwnKeys(transport.calls[0].payload) == 2
                && sameBinding(before, transport.calls[0].payload.binding),
            "C02 outbound payload nests the exact six-key outer binding");
        var portrait:Object = transport.calls[0].payload.playerAvatarPortrait;
        check(countOwnKeys(portrait) == 5
                && portrait.schema == "warlord.player-avatar-portrait.v1"
                && (portrait.gender == "男" || portrait.gender == "女"),
            "C02 player portrait uses the fixed white-list tuple");
        check(countOwnKeys(portrait.equipment) == 6
                && portrait.equipment.primary == undefined
                && portrait.equipment.secondary == undefined,
            "C02 player portrait never projects weapon or tactical slots");
        check(runner.publishOuterCancellation("stage.parent-restart")
                && transport.calls.length == 2
                && transport.calls[1].task == "warlord_stage_outer_cancelled"
                && transport.calls[1].extra == null,
            "C02 restart publishes the dedicated outer cancellation task");
        var outerCancel:Object = transport.calls[1].payload;
        check(countOwnKeys(outerCancel) == 3
                && outerCancel.schema == "warlord.stage-outer-cancellation.v1"
                && outerCancel.reasonCode == "stage.parent-restart"
                && sameBinding(before, outerCancel.binding),
            "C02 outer cancellation carries the exact six-key binding");
        outerCancel.binding.callId = "mutated.cancel";
        check(runner.getBindingSnapshot().callId == before.callId,
            "C02 outer cancellation transport receives an isolated binding clone");
        check(runner.publishOuterCancellation("stage.parent-setup-failed")
                && transport.calls.length == 3
                && transport.calls[2].payload.reasonCode
                    == "stage.parent-setup-failed",
            "C02 setup failure can best-effort publish the same exact owner");
        check(!runner.publishOuterCancellation("")
                && transport.calls.length == 3,
            "C02 invalid cancellation reason has zero transport effect");
        transport.calls[0].payload.binding.callId = "mutated";
        check(runner.getBindingSnapshot().callId == before.callId,
            "C02 transport receives a clone and cannot rewrite authority");
        runner.dispose();

        var unavailable:Object = makeTransport(false);
        var retryRunner:WarlordSubStageRunner = new WarlordSubStageRunner(
            "run.2", "sub.2", "scenario.2", observer, unavailable);
        var retryBinding:Object = retryRunner.getBindingSnapshot();
        check(!retryRunner.start() && retryRunner.getPhase() == "terminal",
            "C02 send=false becomes a terminal startup failure");
        check(unavailable.calls.length == 1
                && sameBinding(retryBinding, unavailable.calls[0].payload.binding),
            "C02 failed send attempted the original binding once");
        check(observer.startFailureCount == 1
                && observer.lastStartFailure.result == "not_started"
                && observer.lastStartFailure.schema
                    == "warlord.stage-outer-attempt.v1"
                && sameOuterIdentity(retryBinding, observer.lastStartFailure),
            "C02 failed send reports one exact not_started startup failure");
        check(typeof retryRunner["retrySameBinding"] != "function",
            "C02 startup failure exposes no player retry method");
        retryRunner.dispose();

        var throwing:Object = makeTransport(true);
        throwing.throwNext = true;
        var throwRunner:WarlordSubStageRunner = new WarlordSubStageRunner(
            "run.3", "sub.3", "scenario.3", observer, throwing);
        var throwBinding:Object = throwRunner.getBindingSnapshot();
        check(!throwRunner.start() && throwRunner.getPhase() == "terminal",
            "C02 transport throw is contained as startup failure");
        check(throwing.calls.length == 0
                && sameBinding(throwBinding, throwRunner.getBindingSnapshot()),
            "C02 transport throw does not advance or mutate binding");
        check(observer.startFailureCount == 2,
            "C02 transport throw reports exactly one additional startup failure");
        throwRunner.dispose();
    }

    private static function testSynchronousResultWinsTransportReturn():Void {
        var startObserver:Object = makeObserver();
        var startTransport:Object = {calls:[]};
        var startRunner:WarlordSubStageRunner;
        startTransport.sendTaskToNode = function(
                task:String, payload:Object, extra:Object):Boolean {
            this.calls.push({task:task, payload:payload, extra:extra});
            var binding:Object = payload.binding;
            startRunner.handleResult({
                schema:"warlord.stage-outer-attempt.v1",
                runId:binding.runId, subStageId:binding.subStageId,
                scenarioRef:binding.scenarioRef, callId:binding.callId,
                revision:binding.revision, result:"not_started",
                reasonCode:"warlord.stage.not-started"
            });
            return false;
        };
        startRunner = new WarlordSubStageRunner(
            "run.sync.start", "sub.sync.start", "scenario.sync.start",
            startObserver, startTransport);
        check(startRunner.start()
                && startRunner.getPhase() == "terminal",
            "C02 synchronous start result wins over transport false");
        check(startObserver.startFailureCount == 1
                && startTransport.calls.length == 1,
            "C02 synchronous not_started reports startup failure exactly once");
        var late:Object = startRunner.handleResult(makeTerminal(
            startRunner.getBindingSnapshot(), "CompleteSubStage",
            "warlord.stage.player-victory"));
        check(!late.accepted && late.reasonCode == "late_event",
            "C02 terminal cannot resurrect a startup-failed runner");
        startRunner.dispose();

        var terminalObserver:Object = makeObserver();
        var terminalTransport:Object = {calls:[]};
        var terminalRunner:WarlordSubStageRunner;
        terminalTransport.sendTaskToNode = function(
                task:String, payload:Object, extra:Object):Boolean {
            this.calls.push({task:task, payload:payload, extra:extra});
            var binding:Object = payload.binding;
            terminalRunner.handleResult({
                schema:"warlord.stage-outer-terminal.v1",
                runId:binding.runId, subStageId:binding.subStageId,
                scenarioRef:binding.scenarioRef, callId:binding.callId,
                revision:binding.revision, terminal:"CompleteSubStage",
                reasonCode:"warlord.stage.player-victory"
            });
            throw new Error("throw after synchronous terminal");
            return false;
        };
        terminalRunner = new WarlordSubStageRunner(
            "run.sync.terminal", "sub.sync.terminal", "scenario.sync.terminal",
            terminalObserver, terminalTransport);
        var terminalBinding:Object = terminalRunner.getBindingSnapshot();
        check(terminalRunner.start() && terminalRunner.getPhase() == "terminal",
            "C02 synchronous business terminal wins over transport throw");
        check(terminalObserver.terminalCount == 1
                && sameBinding(terminalBinding, terminalRunner.getBindingSnapshot()),
            "C02 synchronous terminal keeps the exact binding and commits once");
        terminalRunner.dispose();
    }

    private static function testPlayerPortraitUsesSavedAuthorityProjection():Void {
        var oldWorld:Object = _root.gameworld;
        var oldTarget:Object = _root.控制目标;
        var oldGender:Object = _root.性别;
        var oldFace:Object = _root.脸型;
        var oldHair:Object = _root.发型;
        var oldBody:Object = _root.上装装备;
        var oldLeg:Object = _root.下装装备;
        var oldFoot:Object = _root.脚部装备;
        var oldInventory:Object = _root.物品栏;
        _root.gameworld = {transient:{性别:"女", 脸型:"女变装-基本脸型", 发型:"临时女发型",
            上装装备:"临时女上装", 下装装备:"临时女下装", 脚部装备:"临时女鞋"}};
        _root.控制目标 = "transient";
        _root.性别 = "男";
        _root.脸型 = "男变装-基本脸型";
        _root.发型 = "发型-男式-平头";
        _root.上装装备 = "过期根上装";
        _root.下装装备 = "过期根下装";
        _root.脚部装备 = "过期根鞋";
        _root.物品栏 = {装备栏:{
            getNameString:function(slot:String):String {
                if (slot == "上装装备") return "主角重装上衣";
                if (slot == "下装装备") return "主角重装裤";
                if (slot == "脚部装备") return "主角重装靴";
                return "";
            }
        }};

        var transport:Object = makeTransport(true);
        var runner:WarlordSubStageRunner = new WarlordSubStageRunner(
            "run.portrait", "sub.portrait", "scenario.portrait", makeObserver(), transport);
        check(runner.start() && transport.calls.length == 1,
            "C02 player portrait projection can start with a transient control target");
        var portrait:Object = transport.calls[0].payload.playerAvatarPortrait;
        check(portrait.gender == "男" && portrait.face == "男变装-基本脸型"
                && portrait.hair == "发型-男式-平头",
            "C02 player portrait gender and appearance use the saved root projection");
        check(portrait.equipment.body == "主角重装上衣"
                && portrait.equipment.leg == "主角重装裤"
                && portrait.equipment.foot == "主角重装靴",
            "C02 player portrait equipment uses inventory over transient and stale root gear");
        runner.dispose();

        _root.gameworld = oldWorld;
        _root.控制目标 = oldTarget;
        _root.性别 = oldGender;
        _root.脸型 = oldFace;
        _root.发型 = oldHair;
        _root.上装装备 = oldBody;
        _root.下装装备 = oldLeg;
        _root.脚部装备 = oldFoot;
        _root.物品栏 = oldInventory;
    }

    private static function testAttemptFencing():Void {
        var observer:Object = makeObserver();
        var transport:Object = makeTransport(true);
        var runner:WarlordSubStageRunner = new WarlordSubStageRunner(
            "run.attempt", "sub.attempt", "scenario.attempt", observer, transport);
        runner.start();
        var binding:Object = runner.getBindingSnapshot();
        var malformed:Object = makeAttempt(binding, "warlord.stage.not-started");
        malformed.extra = true;
        var result:Object = runner.handleResult(malformed);
        check(!result.accepted && result.reasonCode == "invalid_contract",
            "C03 attempt with an extra key is rejected");
        check(runner.getPhase() == "awaiting_terminal"
                && observer.startFailureCount == 0,
            "C03 malformed attempt has zero state/callback effect");

        result = runner.handleResult(makeAttempt(binding, "warlord.stage.not-started"));
        check(result.accepted && result.disposition == "not_started_failed",
            "C03 exact not_started attempt is accepted as startup failure");
        check(runner.getPhase() == "terminal" && observer.startFailureCount == 1
                && observer.terminalCount == 0 && observer.frozenCount == 0,
            "C03 not_started invokes only the startup-failure observer");
        result = runner.handleResult(makeAttempt(binding, "warlord.stage.not-started"));
        check(!result.accepted && result.reasonCode == "late_event"
                && transport.calls.length == 1,
            "C03 startup failure cannot be replayed into a retry");

        var stale:Object = makeAttempt(binding, "warlord.stage.stale");
        stale.revision = -1;
        result = runner.handleResult(stale);
        check(!result.accepted && result.reasonCode == "invalid_contract",
            "C03 invalid negative revision fails schema validation");
        var future:Object = makeAttempt(binding, "warlord.stage.future");
        future.revision = 1;
        result = runner.handleResult(future);
        check(!result.accepted && result.reasonCode == "identity_drift",
            "C03 higher revision is rejected as identity drift");
        var foreign:Object = makeAttempt(binding, "warlord.stage.foreign");
        foreign.callId = "foreign.call";
        result = runner.handleResult(foreign);
        check(!result.accepted && result.reasonCode == "identity_drift",
            "C03 foreign callId is rejected as identity drift");
        runner.dispose();
    }

    private static function testBusinessTerminalFencing():Void {
        var observer:Object = makeObserver();
        var transport:Object = makeTransport(true);
        var runner:WarlordSubStageRunner = new WarlordSubStageRunner(
            "run.complete", "sub.complete", "scenario.complete", observer, transport);
        runner.start();
        var binding:Object = runner.getBindingSnapshot();
        var complete:Object = makeTerminal(binding, "CompleteSubStage",
            "warlord.stage.player-victory");
        var result:Object = runner.handleResult(complete);
        check(result.accepted && result.disposition == "accepted"
                && runner.getPhase() == "terminal",
            "C04 CompleteSubStage becomes the accepted business terminal");
        check(observer.terminalCount == 1 && observer.lastTerminal.terminal == "CompleteSubStage",
            "C04 CompleteSubStage reaches the terminal observer once");
        result = runner.handleResult(makeTerminal(binding, "CompleteSubStage",
            "warlord.stage.player-victory"));
        check(result.accepted && result.disposition == "duplicate"
                && observer.terminalCount == 1,
            "C04 identical terminal replay is idempotent");
        result = runner.handleResult(makeTerminal(binding, "FailStage",
            "warlord.stage.conflict"));
        check(!result.accepted && result.reasonCode == "terminal_conflict"
                && observer.terminalCount == 1,
            "C04 conflicting terminal is rejected without a second callback");
        result = runner.handleResult(makeAttempt(binding, "warlord.stage.late"));
        check(!result.accepted && result.reasonCode == "late_event",
            "C04 attempt after terminal is late");
        runner.dispose();
        result = runner.handleResult(complete);
        check(!result.accepted && result.reasonCode == "late_event",
            "C04 disposed runner rejects late results");

        var failObserver:Object = makeObserver();
        var failRunner:WarlordSubStageRunner = new WarlordSubStageRunner(
            "run.fail", "sub.fail", "scenario.fail", failObserver, transport);
        failRunner.start();
        result = failRunner.handleResult(makeTerminal(failRunner.getBindingSnapshot(),
            "FailStage", "warlord.stage.rule-terminal-failure"));
        check(result.accepted && failObserver.terminalCount == 1
                && failObserver.lastTerminal.terminal == "FailStage",
            "C04 FailStage alone reaches the failure terminal observer");
        failRunner.dispose();
    }

    private static function testFrozenCannotReopen():Void {
        var observer:Object = makeObserver();
        var transport:Object = makeTransport(true);
        var runner:WarlordSubStageRunner = new WarlordSubStageRunner(
            "run.freeze", "sub.freeze", "scenario.freeze", observer, transport);
        runner.start();
        var generationZero:Object = runner.getBindingSnapshot();
        var suspended:Object = makeTerminal(generationZero, "Suspended",
            "warlord.stage.user-close");
        var result:Object = runner.handleResult(suspended);
        check(result.accepted && runner.getPhase() == "frozen",
            "C05 Suspended freezes the current generation");
        check(observer.frozenCount == 1 && observer.terminalCount == 0
                && observer.lastFrozen.terminal == "Suspended",
            "C05 Suspended never invokes the business terminal observer");
        check(runner.getBindingSnapshot().revision == 0
                && runner.getBindingSnapshot().callId == generationZero.callId,
            "C05 entering frozen does not silently advance binding");
        result = runner.handleResult(makeTerminal(generationZero, "Suspended",
            "warlord.stage.user-close"));
        check(result.accepted && result.disposition == "duplicate"
                && observer.frozenCount == 1,
            "C05 identical frozen terminal replay is idempotent");
        result = runner.handleResult(makeTerminal(generationZero, "Unknown",
            "warlord.stage.technical-unknown"));
        check(!result.accepted && result.reasonCode == "terminal_conflict"
                && observer.frozenCount == 1,
            "C05 a different terminal cannot rewrite frozen authority");
        check(typeof runner["reopenFrozen"] != "function"
                && typeof runner["canReopen"] != "function",
            "C05 frozen runner exposes no resurrection surface");
        check(sameBinding(generationZero, runner.getBindingSnapshot())
                && transport.calls.length == 1,
            "C05 frozen authority cannot advance callId or revision");
        runner.dispose();

        var unknownObserver:Object = makeObserver();
        var unknownRunner:WarlordSubStageRunner = new WarlordSubStageRunner(
            "run.unknown", "sub.unknown", "scenario.unknown", unknownObserver, transport);
        unknownRunner.start();
        result = unknownRunner.handleResult(makeTerminal(unknownRunner.getBindingSnapshot(),
            "Unknown", "warlord.stage.technical-unknown"));
        check(result.accepted && unknownRunner.getPhase() == "frozen"
                && unknownObserver.terminalCount == 0 && unknownObserver.frozenCount == 1,
            "C05 Unknown also freezes without failure mapping");
        check(typeof unknownRunner["reopenFrozen"] != "function",
            "C05 Unknown cannot create a recovery generation");
        unknownRunner.dispose();
    }

    private static function testStageRunIdentityProjection():Void {
        StageRunSession.testOnlyReset();
        check(StageRunSession.getCurrentRunId() == "",
            "C07 no active StageRunSession exposes no runId");
        check(StageRunSession.begin("军阀战术演习", "普通", ""),
            "C07 StageRunSession begins the outer GameStage authority");
        var snapshot:Object = StageRunSession.testOnlySnapshot();
        check(StageRunSession.getCurrentRunId() == snapshot.runId
                && String(snapshot.runId).indexOf("run.") == 0,
            "C07 coordinator receives the exact active StageRunSession runId");
        StageRunSession.testOnlyReset();
        check(StageRunSession.getCurrentRunId() == "",
            "C07 restart/return cleanup removes the projected runId");
    }

    private static function testRecoverySurfaceRemoved():Void {
        var originalServer:Object = _root.server;
        var originalReturn:Function = _root.返回基地;
        StageRunSession.testOnlyReset();
        StageRunSession.install();

        var server:Object = {isSocketConnected:true, calls:[]};
        server.sendTaskToNode = function(
                task:String, payload:Object, extra:Object):Boolean {
            this.calls.push({task:task, payload:payload, extra:extra});
            return true;
        };
        _root.server = server;
        check(StageRunSession.begin("军阀旁路移除", "普通", ""),
            "C08 test owns one active StageRunSession");
        check(typeof _root.gameCommands.warlordStageRecoverySync != "function",
            "C08 recovery sync command is absent");
        var session:Object = StageRunSession.testOnlySnapshot();
        check(session.warlordRecovery == undefined,
            "C08 StageRunSession snapshot contains no recovery projection");

        _root.gameCommands.stageOutcomeSync({
            task:"cmd", action:"stageOutcomeSync", v:1});
        check(server.calls.length == 2
                && server.calls[0].task == "stage_outcome"
                && server.calls[1].task == "stage_outcome",
            "C08 generic stage_outcome v1 projection remains available");

        var returnAttempts:Number = 0;
        _root.返回基地 = function():Boolean {
            returnAttempts++;
            return true;
        };
        _root.gameCommands.stageOutcomeAction({
            task:"cmd", action:"stageOutcomeAction", v:2,
            runId:session.runId, expectedRevision:session.revision,
            intent:"warlord_retry_same_binding", intentId:"removed.intent.1",
            expectedBinding:{schema:"warlord.stage-outer-binding.v1",
                runId:session.runId, subStageId:"sub.removed",
                scenarioRef:"scenario.removed", callId:"call.removed", revision:0}
        });
        var after:Object = StageRunSession.testOnlySnapshot();
        check(returnAttempts == 0 && after.revision == session.revision
                && after.returnRequested !== true,
            "C08 removed v2 intent has zero authority effect");
        var noRecoveryTask:Boolean = true;
        for (var i:Number = 0; i < server.calls.length; i++) {
            if (server.calls[i].task == "warlord_stage_recovery") {
                noRecoveryTask = false;
            }
        }
        check(noRecoveryTask,
            "C08 AS2 never emits the removed recovery task");

        StageRunSession.testOnlyReset();
        _root.server = originalServer;
        _root.返回基地 = originalReturn;
    }

    private static function testSmallRosterFormationProjection():Void {
        var line:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "line", "blue", 4, 570, 431, 54);
        var column:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "column", "blue", 4, 570, 431, 54);
        var wedge:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "wedge", "blue", 4, 570, 431, 54);
        var shield:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "shield", "blue", 4, 570, 431, 54);
        var grid:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "grid", "blue", 4, 570, 431, 54);

        check(positionSignature(line) == "570,431|516,431|462,431|408,431",
            "C09 four-unit line advances by depth on one lane");
        check(positionSignature(column) == "570,350|570,404|570,458|570,512",
            "C09 four-unit column spans four vertical lanes");
        check(positionSignature(wedge) == "570,431|516,404|516,458|462,431",
            "C09 four-unit wedge preserves point, wings and rear point");
        check(positionSignature(shield) == "570,377|570,431|570,485|516,431",
            "C09 four-unit shield keeps three front guards and one rear guard");
        check(positionSignature(grid) == "570,404|570,458|516,404|516,458",
            "C09 four-unit grid remains a two-by-two deployment");
        check(allPositionSignaturesUnique([line, column, wedge, shield, grid]),
            "C09 all five Demo 1 four-unit formations are observably distinct");

        var twoWedge:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "wedge", "blue", 2, 570, 431, 54);
        var twoShield:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "shield", "blue", 2, 570, 431, 54);
        check(positionSignature(twoWedge) == "570,431|516,377"
                && positionSignature(twoShield) == "570,431|516,458",
            "C09 two-unit wedge and shield no longer collapse to line");

        var redWedge:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "wedge", "red", 4, 1220, 431, 54);
        check(positionSignature(redWedge)
                == "1220,431|1274,404|1274,458|1328,431",
            "C09 red formation mirrors depth without changing deterministic lanes");

        var edgeLine:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "line", "blue", 4, 240, 431, 54);
        check(positionSignature(edgeLine) == "240,431|237,431|233,431|230,431",
            "C09 small formations retain the arena X boundary clamp");

        var fiveShield:Array = ArenaCalibrationService.testOnlyProjectFormation(
            "shield", "blue", 5, 570, 431, 54);
        check(positionSignature(fiveShield)
                == "570,323|570,377|570,431|570,485|570,539",
            "C09 five-plus roster shield keeps the established large-roster geometry");
    }

    private static function testArenaDistanceProjection():Void {
        var near:Object = ArenaCalibrationService.testOnlyProjectArenaDeployment(
            180, "line", 4, 54, 895, 430);
        var medium:Object = ArenaCalibrationService.testOnlyProjectArenaDeployment(
            360, "line", 4, 54, 895, 430);
        var far:Object = ArenaCalibrationService.testOnlyProjectArenaDeployment(
            650, "line", 4, 54, 895, 430);

        check(near.spawnDistance == 180 && near.blueX == 805
                && near.redX == 985 && near.y == 430,
            "C10 distance 180 projects exact centered spawn anchors");
        check(medium.spawnDistance == 360 && medium.blueX == 715
                && medium.redX == 1075 && medium.y == 430,
            "C10 distance 360 projects exact centered spawn anchors");
        check(far.spawnDistance == 650 && far.blueX == 570
                && far.redX == 1220 && far.y == 430,
            "C10 distance 650 projects exact centered spawn anchors");

        check(deploymentMatrixValid(180),
            "C10 distance 180 keeps every 2-4 unit formation safe and non-overlapping");
        check(deploymentMatrixValid(360),
            "C10 distance 360 keeps every 2-4 unit formation safe and non-overlapping");
        check(deploymentMatrixValid(650),
            "C10 distance 650 keeps every 2-4 unit formation safe and non-overlapping");
    }

    private static function makeTransport(initialResult:Boolean):Object {
        var value:Object = {calls:[], result:initialResult, throwNext:false};
        value.sendTaskToNode = function(task:String, payload:Object, extra:Object):Boolean {
            if (this.throwNext === true) {
                this.throwNext = false;
                throw new Error("test transport throw");
            }
            this.calls.push({task:task, payload:payload, extra:extra});
            return this.result === true;
        };
        return value;
    }

    private static function makeObserver():Object {
        var value:Object = {terminalCount:0, frozenCount:0,
            startFailureCount:0, lastTerminal:null, lastFrozen:null,
            lastStartFailure:null};
        value.onWarlordSubStageTerminal = function(event:Object):Void {
            this.terminalCount++;
            this.lastTerminal = event;
        };
        value.onWarlordSubStageFrozen = function(event:Object):Void {
            this.frozenCount++;
            this.lastFrozen = event;
        };
        value.onWarlordSubStageStartFailed = function(event:Object):Void {
            this.startFailureCount++;
            this.lastStartFailure = event;
        };
        return value;
    }

    private static function makeTerminal(binding:Object, terminal:String,
            reasonCode:String):Object {
        return {schema:"warlord.stage-outer-terminal.v1",
            runId:binding.runId, subStageId:binding.subStageId,
            scenarioRef:binding.scenarioRef, callId:binding.callId,
            revision:binding.revision, terminal:terminal, reasonCode:reasonCode};
    }

    private static function makeAttempt(binding:Object, reasonCode:String):Object {
        return {schema:"warlord.stage-outer-attempt.v1",
            runId:binding.runId, subStageId:binding.subStageId,
            scenarioRef:binding.scenarioRef, callId:binding.callId,
            revision:binding.revision, result:"not_started", reasonCode:reasonCode};
    }

    private static function sameBinding(left:Object, right:Object):Boolean {
        return left != null && right != null
            && left.schema === right.schema && left.runId === right.runId
            && left.subStageId === right.subStageId
            && left.scenarioRef === right.scenarioRef
            && left.callId === right.callId && left.revision === right.revision;
    }

    private static function sameOuterIdentity(left:Object, right:Object):Boolean {
        return left != null && right != null
            && left.runId === right.runId
            && left.subStageId === right.subStageId
            && left.scenarioRef === right.scenarioRef
            && left.callId === right.callId
            && left.revision === right.revision;
    }

    private static function samePortrait(left:Object, right:Object):Boolean {
        return left != null && right != null
            && left.schema === right.schema && left.gender === right.gender
            && left.face === right.face && left.hair === right.hair
            && left.equipment != null && right.equipment != null
            && left.equipment.head === right.equipment.head
            && left.equipment.body === right.equipment.body
            && left.equipment.hand === right.equipment.hand
            && left.equipment.leg === right.equipment.leg
            && left.equipment.foot === right.equipment.foot
            && left.equipment.neck === right.equipment.neck;
    }

    private static function countOwnKeys(value:Object):Number {
        var count:Number = 0;
        for (var key:String in value) {
            if (Object.prototype.hasOwnProperty.call(value, key)) count++;
        }
        return count;
    }

    private static function deploymentMatrixValid(spawnDistance:Number):Boolean {
        var centers:Array = [230, 895, 1560];
        var spacings:Array = [54, 96];
        var totals:Array = [2, 3, 4];
        var formations:Array = ["line", "column", "wedge", "shield", "grid"];
        for (var c:Number = 0; c < centers.length; c++) {
            for (var s:Number = 0; s < spacings.length; s++) {
                for (var t:Number = 0; t < totals.length; t++) {
                    for (var f:Number = 0; f < formations.length; f++) {
                        var projected:Object = ArenaCalibrationService.testOnlyProjectArenaDeployment(
                            spawnDistance,
                            formations[f],
                            totals[t],
                            spacings[s],
                            centers[c],
                            430);
                        if (projected.spawnDistance != spawnDistance
                                || projected.redX - projected.blueX != spawnDistance
                                || projected.formationSpacing != spacings[s]
                                || projected.blue.length != totals[t]
                                || projected.red.length != totals[t]
                                || !positionsSafeAndUnique(projected.blue)
                                || !positionsSafeAndUnique(projected.red)
                                || positionsOverlap(projected.blue, projected.red)) {
                            return false;
                        }
                    }
                }
            }
        }
        return true;
    }

    private static function positionsSafeAndUnique(positions:Array):Boolean {
        for (var i:Number = 0; i < positions.length; i++) {
            var current:Object = positions[i];
            if (current.x < 230 || current.x > 1560
                    || current.y < 242 || current.y > 620) {
                return false;
            }
            for (var j:Number = i + 1; j < positions.length; j++) {
                if (current.x == positions[j].x && current.y == positions[j].y) {
                    return false;
                }
            }
        }
        return true;
    }

    private static function positionsOverlap(first:Array, second:Array):Boolean {
        for (var i:Number = 0; i < first.length; i++) {
            for (var j:Number = 0; j < second.length; j++) {
                if (first[i].x == second[j].x && first[i].y == second[j].y) {
                    return true;
                }
            }
        }
        return false;
    }

    private static function positionSignature(positions:Array):String {
        var signature:String = "";
        for (var i:Number = 0; i < positions.length; i++) {
            if (i > 0) signature += "|";
            signature += String(positions[i].x) + "," + String(positions[i].y);
        }
        return signature;
    }

    private static function allPositionSignaturesUnique(groups:Array):Boolean {
        for (var i:Number = 0; i < groups.length; i++) {
            var left:String = positionSignature(groups[i]);
            for (var j:Number = i + 1; j < groups.length; j++) {
                if (left == positionSignature(groups[j])) return false;
            }
        }
        return true;
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            passed++;
            trace("[PASS] " + message);
        } else {
            failed++;
            trace("[FAIL] " + message);
        }
    }
}
