import org.flashNight.arki.camera.HorizontalScroller;
import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;

/**
 * Warlord 临时 Action 的纯战斗事实服务。
 * StageManager 独占 StageInfo、物理 gameworld 与标准跳帧生命周期；本类只负责
 * 输入校验、投影单位、AI/镜头、战斗结果冻结，以及 terminal 的无时钟投递。
 */
class org.flashNight.arki.scene.WarlordActionEncounterService {
    private static var START_ACTION:String = "warlord_action_encounter_start";
    private static var ADMISSION_TASK:String =
        "warlord_action_encounter_admitted";
    private static var TERMINAL_TASK:String = "warlord_action_encounter_terminal";
    private static var CONTROL_SCHEMA:String = "warlord.action-encounter-control.v2";
    private static var BINDING_SCHEMA:String = "warlord.action-encounter-binding.v2";
    private static var ADMISSION_SCHEMA:String =
        "warlord.action-encounter-admission.v1";
    private static var TERMINAL_SCHEMA:String = "warlord.action-encounter-terminal.v2";
    private static var CENTER_X:Number = 895;
    private static var CENTER_Y:Number = 430;
    private static var XMIN:Number = 230;
    private static var XMAX:Number = 1560;
    private static var YMIN:Number = 242;
    private static var YMAX:Number = 620;
    private static var EDGE_RESERVE:Number = 290;
    private static var MIN_DISTANCE:Number = 180;
    private static var DEFAULT_SPACING:Number = 54;
    private static var MIN_SPACING:Number = 36;
    private static var MAX_SPACING:Number = 96;
    private static var ACTOR_VISUAL_READY_TIMEOUT_FRAMES:Number = 90;
    private static var SCENE_REVEAL_TIMEOUT_FRAMES:Number = 180;
    private static var SCENE_REVEAL_IDLE_FRAME:Number = 36;
    private static var REVEAL_SETTLE_FRAMES:Number = 6;
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;

    private static var OPAQUE_ID_PATTERN:RegExp = new RegExp(
        "^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$", "");
    private static var CANONICAL_DIGEST_PATTERN:RegExp = new RegExp(
        "^sha256:[0-9a-f]{64}$", "");
    private static var PANEL_PAUSE_LEASE_PATTERN:RegExp = new RegExp(
        "^lease[0-9]+$", "");
    private static var COMMAND_KEYS:Array = [
        "task", "action", "binding", "encounter"
    ];
    private static var BINDING_KEYS:Array = [
        "schema", "outerRunId", "encounterId", "requestId", "inputDigest"
    ];
    private static var ADMISSION_KEYS:Array = [
        "schema", "binding", "disposition", "phase"
    ];
    private static var TERMINAL_KEYS:Array = [
        "schema", "outerRunId", "encounterId", "requestId", "inputDigest",
        "status", "reasonCode", "result"
    ];
    private static var CONTROL_KEYS:Array = [
        "schema", "battleId", "blueRoster", "redRoster", "timeoutFrames",
        "spawnDistance", "blueFormation", "redFormation", "formationSpacing",
        "authorityContext", "playerControlledSide"
    ];
    private static var PET_ROSTER_KEYS:Array = [
        "projectionKind", "sourceId", "petId", "identifier", "rosterType",
        "level", "hpPermille", "strategicPromotions"
    ];
    private static var PLAYER_AVATAR_ROSTER_KEYS:Array = [
        "projectionKind", "sourceId", "commanderId", "characterId",
        "factionId", "hpPermille"
    ];

    private static var _installed:Boolean = false;
    private static var _prepared:Object = null;
    private static var _active:Object = null;
    private static var _pendingTerminal:Object = null;
    // send() 成功只证明写入本地 XMLSocket，不是 Host 应用层 ACK。最后一个
    // terminal 必须继续作为 exact binding 的吸收态，直到新 binding 或父关卡退出。
    private static var _absorbingTerminal:Object = null;
    private static var _testPanelPauseAdapter:Object = null;

    public static function install():Void {
        if (_installed) return;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands[START_ACTION] = function(command:Object):Void {
            org.flashNight.arki.scene.WarlordActionEncounterService
                .handleStart(command);
        };
        _installed = true;
    }

    /** ServerManager 把完整 cmd 对象交给 action handler。 */
    public static function handleStart(command:Object):Void {
        handleStartWithManager(command, null);
    }

    private static function handleStartWithManager(
            command:Object, injectedManager:Object):Void {
        if (!isStartEnvelope(command)) {
            trace("[WarlordActionEncounter] rejected malformed start envelope");
            return;
        }
        var binding:Object = cloneBinding(command.binding);
        var control:Object = cloneJson(command.encounter);
        traceStartLifecycle("start_received", binding,
            "battleId=" + String(control.battleId));
        var manager:Object = injectedManager;
        try {
            // terminal 是 binding 级吸收态。即使上次 send() 返回 true，也必须在
            // 任何 pause/StageManager 副作用之前重投，不能重新评估后改判为开战。
            var remembered:Object = getAbsorbingTerminal(binding);
            if (remembered != null) {
                traceStartLifecycle("start_outcome", binding,
                    "disposition=terminal_replay phase=terminal");
                deliverTerminal(remembered);
                return;
            }

            if (manager == null) manager = StageManager.getInstance();
            if (manager == null
                    || typeof manager.inspectWarlordActionEncounter != "function") {
                traceStartLifecycle("start_outcome", binding,
                    "disposition=invalid phase=preflight");
                return;
            }

            // exact duplicate / StageManager terminal 必须先于 unpause 识别。Host 的
            // ACK 重试不得再次触碰随后取得的 panel lease 或其他业务暂停权威。
            var existing:Object = manager.inspectWarlordActionEncounter(binding);
            if (isTerminalOutcome(binding, existing)) {
                traceStartLifecycle("start_outcome", binding,
                    "disposition=" + String(existing.disposition)
                    + " phase=terminal");
                deliverTerminal(existing.terminal);
                return;
            }
            if (isDuplicateOutcome(existing)) {
                sendAdmissionForOutcome(binding, existing);
                return;
            }
            if (!isFreshInspection(existing)) {
                if (isRejectedOutcome(existing)) {
                    // 不同 binding 的迟到 Host retry 可能在同一 socket generation
                    // 内落到新 encounter 之后。当前槽仍属另一个 encounter 时只丢弃
                    // 这条 stale start；为它冻结 terminal 会占住单槽 pending，并阻断
                    // 当前 encounter 的真实完成 terminal。
                    if (existing.reasonCode === "encounter_active") {
                        traceStartLifecycle("start_outcome", binding,
                            "disposition=stale phase=preflight reason=encounter_active");
                        return;
                    }
                    var preflightReason:String = normalizeTerminalReason(
                        existing.reasonCode);
                    traceStartLifecycle("start_outcome", binding,
                        "disposition=not_started phase=terminal reason="
                        + preflightReason);
                    freezeFailureTerminal(binding, "not_started",
                        preflightReason);
                } else {
                    traceStartLifecycle("start_outcome", binding,
                        "disposition=invalid phase=preflight");
                }
                return;
            }
            if (!retirePriorAbsorptionForFreshBinding(binding)) {
                traceStartLifecycle("start_outcome", binding,
                    "disposition=invalid phase=prior_terminal_pending");
                return;
            }

            // 只有第一次 fresh start 才可释放 exact generic webpanel lease；这里
            // 直接使用 PauseManager，绝不进入 Loot/CharacterBuild 的通用 close 路径。
            var pauseOutcome:Object = releasePanelPauseForStart();
            if (pauseOutcome == null || pauseOutcome.released !== true) {
                var pauseReason:String = normalizeTerminalReason(
                    pauseOutcome != null ? pauseOutcome.reasonCode
                        : "action.web-panel-unpause-failed");
                var pauseTerminal:Object = createFailureTerminal(
                    binding, "not_started", pauseReason);
                traceStartLifecycle("start_outcome", binding,
                    "disposition=not_started phase=terminal reason="
                    + pauseReason);
                deliverTerminal(pauseTerminal);
                return;
            }

            var outcome:Object = manager.beginWarlordActionEncounter(
                binding, control);
            if (isTerminalOutcome(binding, outcome)) {
                // exact binding 已有冻结 terminal 时优先重投；绝不重建战斗。
                traceStartLifecycle("start_outcome", binding,
                    "disposition=" + String(outcome.disposition)
                    + " phase=terminal");
                deliverTerminal(outcome.terminal);
                return;
            }
            if (isRejectedOutcome(outcome)) {
                var rejectReason:String = normalizeTerminalReason(
                    outcome.reasonCode);
                traceStartLifecycle("start_outcome", binding,
                    "disposition=not_started phase=terminal reason="
                    + rejectReason);
                freezeFailureTerminal(binding, "not_started", rejectReason);
                return;
            }

            var admission:Object = createAdmission(binding, outcome);
            if (admission == null) {
                traceStartLifecycle("start_outcome", binding,
                    "disposition=invalid phase=begin_outcome");
                recoverStartAfterFailure(manager, binding,
                    "action.start-outcome-invalid", null);
                return;
            }
            traceStartLifecycle("start_outcome", binding,
                "disposition=" + String(admission.disposition)
                + " phase=" + String(admission.phase));
            var admissionSent:Boolean = trySendAdmission(admission);
            traceStartLifecycle("admission_send", binding,
                "success=" + String(admissionSent)
                + " disposition=" + String(admission.disposition)
                + " phase=" + String(admission.phase));
        } catch (startError) {
            recoverStartAfterFailure(manager, binding,
                "action.start-handler-threw", startError);
        }
    }

    public static function tick():Void {
        var run:Object = _active;
        if (run == null || run.phase != "active") return;
        if (run.startupFailure != undefined
                && String(run.startupFailure) != "") {
            failActiveCombat(String(run.startupFailure));
            return;
        }
        if (run.world == null || run.world._parent == undefined
                || run.world !== _root.gameworld) {
            failActiveCombat("action.world-detached");
            return;
        }
        if (_root.暂停 === true) return;
        run.frames++;
        if (run.primed !== true) {
            run.snapshotFrames++;
            var blueReady:Boolean = captureStartSnapshots(
                run.blueUnits,
                run.snapshotFrames >= ACTOR_VISUAL_READY_TIMEOUT_FRAMES,
                run.errors);
            var redReady:Boolean = captureStartSnapshots(
                run.redUnits,
                run.snapshotFrames >= ACTOR_VISUAL_READY_TIMEOUT_FRAMES,
                run.errors);
            if (!blueReady || !redReady) {
                if (run.snapshotFrames >= ACTOR_VISUAL_READY_TIMEOUT_FRAMES) {
                    traceActorReadiness(run.blueUnits, run.world, "hp-timeout");
                    traceActorReadiness(run.redUnits, run.world, "hp-timeout");
                    failActiveCombat("action.hp-snapshot-missing");
                }
                return;
            }

            var actorsReady:Boolean = areActorsVisualReady(
                run.blueUnits, run.world)
                && areActorsVisualReady(run.redUnits, run.world);
            if (!actorsReady) {
                if (run.snapshotFrames >= ACTOR_VISUAL_READY_TIMEOUT_FRAMES) {
                    traceActorReadiness(run.blueUnits, run.world,
                        "visual-timeout");
                    traceActorReadiness(run.redUnits, run.world,
                        "visual-timeout");
                    failActiveCombat("action.actor-visual-not-ready");
                }
                return;
            }

            if (!isSceneRevealReady()) {
                run.revealSettledFrames = 0;
                if (run.snapshotFrames >= SCENE_REVEAL_TIMEOUT_FRAMES) {
                    traceActorReadiness(run.blueUnits, run.world,
                        "reveal-timeout");
                    traceActorReadiness(run.redUnits, run.world,
                        "reveal-timeout");
                    failActiveCombat("action.scene-reveal-not-ready");
                }
                return;
            }

            run.revealSettledFrames++;
            if (run.revealSettledFrames < REVEAL_SETTLE_FRAMES) return;
            if (!bindPlayerControl(run, true)) {
                run.errors.push({code:"player_avatar_control_failed",
                    message:"trusted player avatar could not acquire control"});
                failActiveCombat("action.player-avatar-control-failed");
                return;
            }
            releasePreArmAiHolds(run.blueUnits);
            releasePreArmAiHolds(run.redUnits);
            traceActorReadiness(run.blueUnits, run.world, "armed");
            traceActorReadiness(run.redUnits, run.world, "armed");
            primeTargets(run.blueUnits, run.redUnits);
            run.primed = true;
            publishLifecycleDiagnostic("combat_armed", run,
                "frames=" + run.snapshotFrames
                + " control=" + String(_root.控制目标)
                + " auto=" + String(_root.控制目标全自动));
            updateCamera(true);
            return;
        }
        observeUnits(run.blueUnits);
        observeUnits(run.redUnits);
        updateCamera(false);
        var blueAlive:Number = countAlive(run.blueUnits);
        var redAlive:Number = countAlive(run.redUnits);
        var deathEffectsPending:Boolean = hasPendingDeathEffects(run.blueUnits)
            || hasPendingDeathEffects(run.redUnits);
        if (run.frames >= run.timeoutFrames) finish("timeout", "timeout");
        else if (deathEffectsPending) return;
        else if (blueAlive <= 0 && redAlive <= 0) finish("finished", "draw");
        else if (blueAlive <= 0) finish("finished", "red");
        else if (redAlive <= 0) finish("finished", "blue");
    }

    public static function testOnlyValidateStart(command:Object):Boolean {
        return isStartEnvelope(command) && isValidControl(command.encounter);
    }

    public static function testOnlyProjectDeployment(distance:Number,
            formation:String, total:Number, spacing:Number):Object {
        var origin:Object = resolveOrigin(distance);
        var actualSpacing:Number = normalizeSpacing(spacing);
        var blue:Array = [];
        var red:Array = [];
        var count:Number = Math.floor(Number(total));
        if (isNaN(count) || count < 0) count = 0;
        for (var i:Number = 0; i < count; i++) {
            blue.push(resolveFormationPosition(formation, "blue", i, count,
                origin.blueX, origin.y, actualSpacing));
            red.push(resolveFormationPosition(formation, "red", i, count,
                origin.redX, origin.y, actualSpacing));
        }
        return {spawnDistance:origin.spawnDistance,
            blueX:origin.blueX, redX:origin.redX, y:origin.y,
            formationSpacing:actualSpacing, blue:blue, red:red};
    }

    public static function testOnlyIsAiPrimeCandidate(record:Object):Boolean {
        return isAiPrimeCandidate(record);
    }

    public static function testOnlyPrimeTargets(
            blueUnits:Array, redUnits:Array):Void {
        primeTargets(blueUnits, redUnits);
    }

    public static function testOnlyCountAlive(units:Array):Number {
        return countAlive(units);
    }

    public static function testOnlyHasPendingDeathEffects(units:Array):Boolean {
        return hasPendingDeathEffects(units);
    }

    public static function testOnlySummarizeUnitResults(units:Array):Array {
        return summarizeUnitResults(units);
    }

    public static function testOnlySnapshotGlobals():Object {
        return snapshotGlobals();
    }

    public static function testOnlyApplyEncounterGlobals():Void {
        applyEncounterGlobals();
    }

    public static function testOnlyRestoreGlobals(snapshot:Object):Void {
        restoreGlobals(snapshot);
    }

    public static function testOnlyBindPlayerControl(run:Object):Boolean {
        return bindPlayerControl(run, false);
    }

    public static function testOnlyIsActorVisualReady(
            record:Object, world:Object):Boolean {
        return isActorVisualReady(record, world);
    }

    public static function testOnlyIsSceneRevealReady():Boolean {
        return isSceneRevealReady();
    }

    public static function testOnlySetPreArmAiHold(
            record:Object, held:Boolean):Void {
        setPreArmAiHold(record, held);
    }

    public static function testOnlyReleasePlayerControl(
            run:Object, record:Object):Void {
        releasePlayerControl(run, record, false);
    }

    public static function testOnlyGetActivePhase():String {
        if (_active != null) return String(_active.phase);
        return _prepared == null ? "idle" : "prepared";
    }

    public static function testOnlyResetStartAdmissionState():Void {
        _pendingTerminal = null;
        _absorbingTerminal = null;
        _testPanelPauseAdapter = null;
    }

    public static function testOnlySetPanelPauseAdapter(adapter:Object):Void {
        _testPanelPauseAdapter = adapter;
    }

    public static function testOnlyHandleStartWithManager(
            command:Object, manager:Object):Void {
        handleStartWithManager(command, manager);
    }

    public static function testOnlyGetAbsorbingTerminal(
            binding:Object):Object {
        return getAbsorbingTerminal(binding);
    }

    public static function testOnlyReleasePanelPauseForStart():Object {
        return releasePanelPauseForStart();
    }

    public static function testOnlyBuildAdmission(
            binding:Object, outcome:Object):Object {
        return createAdmission(binding, outcome);
    }

    public static function testOnlyValidateAdmission(value:Object):Boolean {
        return isValidAdmission(value);
    }

    public static function testOnlyTrySendAdmission(value:Object):Boolean {
        return trySendAdmission(value);
    }

    public static function testOnlyBuildFailureTerminal(binding:Object,
            status:String, reasonCode:String):Object {
        return createFailureTerminal(binding, status, reasonCode);
    }

    /** 只校验并冻结输入；不触碰 gameworld 或主时间轴。 */
    public static function prepareCombat(
            binding:Object, control:Object):Object {
        install();
        if (!isValidBinding(binding) || !isValidControl(control)) {
            return combatFailure("action.input-invalid");
        }
        if (_active != null) return combatFailure("action.combat-active");
        if (_prepared != null) {
            if (sameBinding(_prepared.binding, binding)
                    && samePlainValue(_prepared.control, control, 0)) {
                return {success:true, duplicate:true};
            }
            return combatFailure("action.combat-prepared");
        }
        var missing:String = missingCombatDependency();
        if (missing != "") return combatFailure("action." + missing);

        var errors:Array = [];
        var blueRoster:Array = normalizeRoster(
            control.blueRoster, "blue", errors);
        var redRoster:Array = normalizeRoster(
            control.redRoster, "red", errors);
        if (errors.length > 0
                || blueRoster.length != control.blueRoster.length
                || redRoster.length != control.redRoster.length) {
            return {success:false, reasonCode:"action.roster-invalid",
                errors:cloneJson(errors)};
        }
        _prepared = {
            binding:cloneBinding(binding),
            control:cloneJson(control),
            blueRoster:blueRoster,
            redRoster:redRoster,
            globals:snapshotGlobals()
        };
        return {success:true, duplicate:false};
    }

    /** 只有 exact 尚未入场的 preparation 能撤销。 */
    public static function cancelPreparedCombat(binding:Object):Boolean {
        if (_prepared == null || !sameBinding(_prepared.binding, binding)) {
            return false;
        }
        _prepared = null;
        return true;
    }

    /**
     * StageManager 在标准 frame209 初始化完成后交入当前 world。本方法只配置战斗
     * 与生成单位，不创建、销毁或认领物理场景。
     */
    public static function activateCombat(
            world:MovieClip, binding:Object, control:Object):Object {
        var prepared:Object = _prepared;
        if (prepared == null || _active != null
                || !sameBinding(prepared.binding, binding)
                || !isValidControl(control)
                || !samePlainValue(prepared.control, control, 0)) {
            return combatFailure("action.activation-input-drift");
        }
        if (world == null || world._parent !== _root
                || _root.gameworld !== world) {
            return combatFailure("action.stage-world-unavailable");
        }

        var run:Object = {
            phase:"activating",
            binding:cloneBinding(prepared.binding),
            control:cloneJson(prepared.control),
            globals:prepared.globals,
            globalsApplied:false,
            globalsRestored:false,
            world:world,
            frames:0,
            startedMs:getTimer(),
            timeoutFrames:Math.floor(Number(prepared.control.timeoutFrames)),
            primed:false,
            snapshotFrames:0,
            revealSettledFrames:0,
            blueUnits:[],
            redUnits:[],
            errors:[],
            playerAvatar:null,
            playerControlReleased:false,
            camera:null,
            cameraReleased:false,
            cleanupOk:false,
            startupFailure:"",
            frozenResult:null
        };
        _prepared = null;
        _active = run;

        try {
            applyEncounterGlobals();
            run.globalsApplied = true;
            configureCombatWorld(world);
        } catch (configureError) {
            run.errors.push({code:"action_world_configure_failed",
                message:String(configureError)});
            run.startupFailure = "action.world-configure-failed";
        }

        var origin:Object = resolveOrigin(Number(run.control.spawnDistance));
        var spacing:Number = normalizeSpacing(
            Number(run.control.formationSpacing));
        var runKey:String = sanitizeName(String(run.binding.encounterId));
        if (run.errors.length == 0) {
            // blue/red 是本次战斗的攻守侧，不是战略阵营。无主角时旁观
            // 双方 AI 对战；只有主角实际参战才把其所在侧映射为友方。
            var blueIsEnemy:Boolean = String(run.control.playerControlledSide)
                === "red";
            var redIsEnemy:Boolean = String(run.control.playerControlledSide)
                !== "red";
            run.blueUnits = spawnSide(world, prepared.blueRoster, "blue",
                blueIsEnemy, origin.blueX, origin.y, runKey,
                String(run.control.blueFormation), spacing, run.errors);
            run.redUnits = spawnSide(world, prepared.redRoster, "red",
                redIsEnemy, origin.redX, origin.y, runKey,
                String(run.control.redFormation), spacing, run.errors);
        }

        run.requestedSpawnDistance = Number(run.control.spawnDistance);
        run.spawnDistance = origin.spawnDistance;
        run.blueFormation = String(run.control.blueFormation);
        run.redFormation = String(run.control.redFormation);
        run.formationSpacing = spacing;
        run.authorityContext = cloneJson(run.control.authorityContext);
        run.playerControlledSide = String(run.control.playerControlledSide);
        run.camera = world.军阀动作镜头;
        if (run.errors.length > 0
                || run.blueUnits.length != prepared.blueRoster.length
                || run.redUnits.length != prepared.redRoster.length
                || run.blueUnits.length == 0 || run.redUnits.length == 0) {
            run.startupFailure = run.startupFailure != ""
                ? run.startupFailure : "action.roster-spawn-failed";
        } else {
            // 玩家模板不只在 attachMovie 的同步返回栈读取控制目标；嵌套纸娃娃的
            // onLoad、StaticInitializer、DressupInitializer 与操控编号都在后续帧
            // 继续据此选择主角分支。这里必须一直保留玩家实例名，用全自动开关
            // 冻结手动输入；镜头跟随与输入权威彼此独立，不能再借控制目标占位。
            if (run.camera != undefined) {
                HorizontalScroller.switchFollowTo(run.camera);
            }
        }
        run.phase = "active";
        if (run.startupFailure != "") {
            return combatFailure(run.startupFailure);
        }
        publishLifecycleDiagnostic("actors_placed", run,
            "blue=" + run.blueUnits.length + " red=" + run.redUnits.length);
        trace("[WarlordActionEncounter] combat activated encounterId="
            + run.binding.encounterId);
        return {success:true};
    }

    /** 结果已冻结后释放所有战斗强引用；物理 world 由 StageManager 的 fade 清理。 */
    public static function releaseCombatForReturn(binding:Object):Boolean {
        var run:Object = _active;
        if (run == null || !sameBinding(run.binding, binding)) return false;
        if (run.phase == "released") return run.cleanupOk === true;
        var controlReleased:Boolean = false;
        try {
            releasePlayerControl(run, run.playerAvatar, false);
            controlReleased = run.playerAvatar == null
                || String(run.playerControlledSide) === "none"
                || run.playerControlReleased === true
                || run.playerAvatar.controlReleased === true;
        } catch (controlError) {
            controlReleased = false;
            trace("[WarlordActionEncounter] player control release failed: "
                + controlError);
        }
        try {
            // MovieClip 引用不能跨同名 world 的跳帧重建充当身份。只在 fade
            // 提交前、Action world 仍是当前权威场景时做一次 exact 释放；
            // detached/foreign 一律记为清理失败，绝不在 frame209 后重试。
            if (run.world == null) {
                run.cameraReleased = true;
            } else if (run.world._parent == undefined
                    || run.world !== _root.gameworld) {
                run.cameraReleased = false;
            } else {
                run.cameraReleased = HorizontalScroller
                    .releaseScene(run.world) === true;
            }
        } catch (cameraError) {
            run.cameraReleased = false;
            trace("[WarlordActionEncounter] camera release failed: " + cameraError);
        }
        try {
            restoreGlobals(run.globals);
            run.globalsRestored = globalsMatchSnapshot(run.globals);
        } catch (restoreError) {
            run.globalsRestored = false;
            trace("[WarlordActionEncounter] globals restore failed: " + restoreError);
        }
        run.cleanupOk = controlReleased === true
            && run.cameraReleased === true
            && run.globalsRestored === true;
        run.phase = "released";
        // 结果已经冻结；无论清理真值如何，都不允许 MovieClip 句柄越过 fade。
        releaseCombatHandles(run);
        return run.cleanupOk === true;
    }

    /** fresh 战略 world 已由 StageManager 建立；只结束逻辑战斗状态。 */
    public static function completeCombatReturn(binding:Object):Boolean {
        var run:Object = _active;
        if (run == null || !sameBinding(run.binding, binding)) return false;
        // frame209 后只读取 fade 前冻结的清理真值；不得重新解析旧 MovieClip
        // 路径或接触刚重建的同名战略 world。
        var cleanupOk:Boolean = run.phase == "released"
            && run.cleanupOk === true;
        releaseCombatHandles(run);
        _active = null;
        return cleanupOk;
    }

    /** restart/整关退出边界的幂等逻辑清理，不操作 MovieClip 生命周期。 */
    public static function cancelForStageExit():Void {
        _prepared = null;
        _pendingTerminal = null;
        _absorbingTerminal = null;
        var run:Object = _active;
        if (run == null) return;
        releaseCombatForReturn(run.binding);
        releaseCombatHandles(run);
        _active = null;
    }

    /** 冻结 exact v2 terminal，并保留到同 binding start 重投或父关卡退出。 */
    public static function deliverTerminal(terminal:Object):Boolean {
        if (!isValidTerminal(terminal)) {
            trace("[WarlordActionEncounter] rejected malformed terminal");
            return false;
        }
        var frozen:Object = cloneJson(terminal);
        if (_absorbingTerminal != null
                && sameTerminalIdentity(_absorbingTerminal, frozen)) {
            // 同 binding 第一份 terminal 永远获胜；后到的不同事实不得改写 Host
            // 已可能接收的结果，只重投原冻结值。
            if (!samePlainValue(_absorbingTerminal, frozen, 0)) {
                trace("[WarlordActionEncounter] absorbing terminal conflict");
            }
            frozen = cloneJson(_absorbingTerminal);
        } else if (_pendingTerminal != null
                && !sameTerminalIdentity(_pendingTerminal, frozen)) {
            trace("[WarlordActionEncounter] pending terminal binding conflict");
            return false;
        } else {
            _absorbingTerminal = cloneJson(frozen);
        }
        if (_pendingTerminal != null
                && !samePlainValue(_pendingTerminal, frozen, 0)) {
            trace("[WarlordActionEncounter] terminal delivery conflict");
            return false;
        }
        _pendingTerminal = cloneJson(frozen);
        return trySendPendingTerminal();
    }

    /** 由 StageManager 的既有 tick 驱动；本服务不创建额外 MovieClip/Timer。 */
    public static function retryPendingTerminal():Void {
        if (_pendingTerminal != null) trySendPendingTerminal();
    }

    private static function getAbsorbingTerminal(binding:Object):Object {
        if (_absorbingTerminal == null
                || !terminalMatchesBinding(_absorbingTerminal, binding)) {
            return null;
        }
        return cloneJson(_absorbingTerminal);
    }

    /** 新 binding 是 Host 已消费上一 terminal 的隐式证明；未发送完成则仍拒绝越过。 */
    private static function retirePriorAbsorptionForFreshBinding(
            binding:Object):Boolean {
        if (_pendingTerminal != null
                && !terminalMatchesBinding(_pendingTerminal, binding)) {
            return false;
        }
        if (_absorbingTerminal != null
                && !terminalMatchesBinding(_absorbingTerminal, binding)) {
            _absorbingTerminal = null;
        }
        return true;
    }

    private static function isTerminalOutcome(
            binding:Object, outcome:Object):Boolean {
        return outcome != null && isValidTerminal(outcome.terminal)
            && terminalMatchesBinding(outcome.terminal, binding);
    }

    private static function isDuplicateOutcome(outcome:Object):Boolean {
        return outcome != null && outcome.accepted === true
            && outcome.disposition === "duplicate"
            && outcome.terminal == null
            && isAdmissionPhase(outcome.phase);
    }

    private static function isFreshInspection(outcome:Object):Boolean {
        return outcome != null && outcome.accepted === true
            && outcome.disposition === "fresh"
            && outcome.phase === "prepared";
    }

    private static function isRejectedOutcome(outcome:Object):Boolean {
        return outcome != null && outcome.accepted === false
            && outcome.disposition === "rejected"
            && isOpaqueId(outcome.reasonCode);
    }

    private static function sendAdmissionForOutcome(
            binding:Object, outcome:Object):Boolean {
        var admission:Object = createAdmission(binding, outcome);
        if (admission == null) {
            traceStartLifecycle("start_outcome", binding,
                "disposition=invalid phase=admission");
            return false;
        }
        traceStartLifecycle("start_outcome", binding,
            "disposition=" + String(admission.disposition)
            + " phase=" + String(admission.phase));
        var sent:Boolean = trySendAdmission(admission);
        traceStartLifecycle("admission_send", binding,
            "success=" + String(sent)
            + " disposition=" + String(admission.disposition)
            + " phase=" + String(admission.phase));
        return sent;
    }

    private static function freezeFailureTerminal(binding:Object,
            status:String, reasonCode:String):Object {
        var terminal:Object = createFailureTerminal(
            binding, status, reasonCode);
        deliverTerminal(terminal);
        return terminal;
    }

    /**
     * 外层异常后先观察 StageManager 的事实。exact slot/terminal 已存在时只能 ACK
     * 该事实；只有 manager 明确仍为 fresh/rejected，才可冻结 unknown terminal。
     */
    private static function recoverStartAfterFailure(manager:Object,
            binding:Object, reasonCode:String, startError):Void {
        traceStartLifecycle("start_outcome", binding,
            "disposition=recovering phase=inspect reason=" + reasonCode
            + (startError == null ? "" : " error=" + String(startError)));
        var remembered:Object = getAbsorbingTerminal(binding);
        if (remembered != null) {
            deliverTerminal(remembered);
            return;
        }
        if (manager == null) {
            freezeFailureTerminal(binding, "unknown", reasonCode);
            return;
        }
        var inspected:Object;
        try {
            if (typeof manager.inspectWarlordActionEncounter != "function") {
                traceStartLifecycle("start_outcome", binding,
                    "disposition=invalid phase=recovery_missing_inspector");
                return;
            }
            inspected = manager.inspectWarlordActionEncounter(binding);
        } catch (inspectError) {
            traceStartLifecycle("start_outcome", binding,
                "disposition=invalid phase=recovery_inspect_threw error="
                + String(inspectError));
            return;
        }
        if (isTerminalOutcome(binding, inspected)) {
            deliverTerminal(inspected.terminal);
            return;
        }
        if (isDuplicateOutcome(inspected)) {
            sendAdmissionForOutcome(binding, inspected);
            return;
        }
        if (isFreshInspection(inspected) || isRejectedOutcome(inspected)) {
            traceStartLifecycle("start_outcome", binding,
                "disposition=unknown phase=terminal reason=" + reasonCode);
            freezeFailureTerminal(binding, "unknown", reasonCode);
            return;
        }
        // 未知 phase/outcome 不得被折叠成 accepted/entering，也不能在可能已提交
        // 的情况下伪造 terminal；让 Host generation fence 保持 fail closed。
        traceStartLifecycle("start_outcome", binding,
            "disposition=invalid phase=recovery_outcome");
    }

    private static function readPanelPauseLease() {
        if (_testPanelPauseAdapter != null
                && typeof _testPanelPauseAdapter.getLease == "function") {
            return _testPanelPauseAdapter.getLease();
        }
        return _root._webPanelPauseLease;
    }

    private static function readPauseOwner():String {
        if (_testPanelPauseAdapter != null
                && typeof _testPanelPauseAdapter.getOwner == "function") {
            return String(_testPanelPauseAdapter.getOwner());
        }
        return org.flashNight.arki.pause.PauseManager.getObservationOwner();
    }

    private static function readPauseState():Boolean {
        if (_testPanelPauseAdapter != null
                && typeof _testPanelPauseAdapter.isPaused == "function") {
            return _testPanelPauseAdapter.isPaused() === true;
        }
        return org.flashNight.arki.pause.PauseManager.isPaused() === true;
    }

    private static function releaseExactPanelPauseLease(lease:String):Void {
        if (_testPanelPauseAdapter != null
                && typeof _testPanelPauseAdapter.releaseLease == "function") {
            _testPanelPauseAdapter.releaseLease(lease);
            return;
        }
        org.flashNight.arki.pause.PauseManager.releaseLease(lease);
    }

    private static function clearPanelPauseLeaseIfExact(lease):Void {
        if (_testPanelPauseAdapter != null
                && typeof _testPanelPauseAdapter.clearLeaseIfExact
                    == "function") {
            _testPanelPauseAdapter.clearLeaseIfExact(lease);
            return;
        }
        if (_root._webPanelPauseLease === lease) {
            _root._webPanelPauseLease = undefined;
        }
    }

    /**
     * fresh Action 只释放当前 exact generic webpanel lease。不得调用
     * webPanelUnpause：该入口还拥有 Loot/CharacterBuild/关卡导航副作用，
     * ACK duplicate 若重入会越权消费后来状态。
     */
    private static function releasePanelPauseForStart():Object {
        var lease = readPanelPauseLease();
        if (typeof lease != "string"
                || !PANEL_PAUSE_LEASE_PATTERN.test(String(lease))) {
            return {released:false,
                reasonCode:"action.web-panel-lease-missing"};
        }
        if (readPauseOwner() !== "webpanel") {
            return {released:false,
                reasonCode:"action.web-panel-lease-not-exclusive"};
        }
        try {
            releaseExactPanelPauseLease(String(lease));
        } catch (unpauseError) {
            trace("[WarlordActionEncounter] panel lease release threw: "
                + unpauseError);
            return {released:false,
                reasonCode:"action.web-panel-unpause-threw"};
        }
        clearPanelPauseLeaseIfExact(lease);
        if (readPanelPauseLease() != undefined) {
            return {released:false,
                reasonCode:"action.web-panel-unpause-blocked"};
        }
        if (readPauseState() === true || readPauseOwner() !== "none") {
            return {released:false,
                reasonCode:"action.web-panel-still-paused"};
        }
        return {released:true, reasonCode:"released"};
    }

    /** exact payload: schema + nested five-field binding + disposition + phase. */
    private static function createAdmission(
            binding:Object, outcome:Object):Object {
        if (!isValidBinding(binding) || outcome == null
                || outcome.accepted !== true) return null;
        var disposition:String;
        var phase:String;
        if (outcome.disposition === "transition_pending") {
            disposition = "accepted";
            phase = "entering";
        } else if (outcome.disposition === "duplicate"
                && isAdmissionPhase(outcome.phase)) {
            disposition = "duplicate";
            phase = String(outcome.phase);
        } else {
            return null;
        }
        return {schema:ADMISSION_SCHEMA, binding:cloneBinding(binding),
            disposition:disposition, phase:phase};
    }

    private static function trySendAdmission(admission:Object):Boolean {
        if (!isValidAdmission(admission) || _root.server == undefined
                || typeof _root.server.sendTaskToNode != "function") {
            return false;
        }
        try {
            return _root.server.sendTaskToNode(
                ADMISSION_TASK, cloneJson(admission), null) === true;
        } catch (sendError) {
            trace("[WarlordActionEncounter] admission send threw: " + sendError);
            return false;
        }
    }

    private static function createFailureTerminal(binding:Object,
            status:String, reasonCode:String):Object {
        return {schema:TERMINAL_SCHEMA, outerRunId:binding.outerRunId,
            encounterId:binding.encounterId, requestId:binding.requestId,
            inputDigest:binding.inputDigest, status:status,
            reasonCode:normalizeTerminalReason(reasonCode), result:null};
    }

    private static function normalizeTerminalReason(value):String {
        var reason:String = String(value || "");
        return isOpaqueId(reason) ? reason : "action.lifecycle-rejected";
    }

    private static function traceStartLifecycle(code:String,
            binding:Object, detail:String):Void {
        trace("[WarlordActionEncounter] " + code
            + " outerRunId=" + String(binding.outerRunId)
            + " encounterId=" + String(binding.encounterId)
            + " requestId=" + String(binding.requestId)
            + " inputDigest=" + String(binding.inputDigest)
            + " " + detail);
    }

    private static function trySendPendingTerminal():Boolean {
        if (_pendingTerminal == null || _root.server == undefined
                || typeof _root.server.sendTaskToNode != "function") {
            return false;
        }
        try {
            if (_root.server.sendTaskToNode(
                    TERMINAL_TASK, cloneJson(_pendingTerminal), null) !== true) {
                return false;
            }
        } catch (sendError) {
            trace("[WarlordActionEncounter] terminal send threw: " + sendError);
            return false;
        }
        _pendingTerminal = null;
        return true;
    }

    private static function configureCombatWorld(world:MovieClip):Void {
        if (world.军阀动作源 == undefined) world.军阀动作源 = {};
        world.军阀动作源.僵尸型敌人场上实际人数 = 0;
        world.军阀动作源.僵尸型敌人总个数 = 0;
        var camera:MovieClip = world.军阀动作镜头;
        if (camera == undefined) {
            camera = world.createEmptyMovieClip(
                "军阀动作镜头", world.getNextHighestDepth());
        }
        camera._x = CENTER_X;
        camera._y = CENTER_Y;
        _root.控制目标 = "军阀动作镜头";
        HorizontalScroller.onSceneChanged();
        HorizontalScroller.switchFollowTo(camera);
        _global.ASSetPropFlags(world,
            ["军阀动作镜头", "军阀动作源"], 1, false);
    }

    private static function missingCombatDependency():String {
        if (typeof _root.加载游戏世界人物 != "function") {
            return "unit-loader-missing";
        }
        if (_root.宠物库 == undefined) return "pet-catalog-missing";
        return "";
    }

    private static function releaseCombatHandles(run:Object):Void {
        releaseUnitHandles(run.blueUnits);
        releaseUnitHandles(run.redUnits);
        run.blueUnits = [];
        run.redUnits = [];
        run.playerAvatar = null;
        run.camera = undefined;
        run.world = null;
    }

    private static function releaseUnitHandles(units:Array):Void {
        if (!(units instanceof Array)) return;
        for (var i:Number = 0; i < units.length; i++) {
            if (units[i] != null) units[i].mc = undefined;
        }
    }

    private static function combatFailure(reasonCode:String):Object {
        return {success:false, reasonCode:reasonCode};
    }

    private static function finish(status:String, winner:String):Void {
        var run:Object = _active;
        if (run == null || run.phase != "active") return;
        observeUnits(run.blueUnits);
        observeUnits(run.redUnits);
        var result:Object = {
            status:status,
            winner:winner,
            frames:Number(run.frames),
            durationMs:Math.max(0, getTimer() - Number(run.startedMs)),
            batchId:String(run.control.battleId || ""),
            manifestHash:"",
            caseHash:"",
            requestedSpawnDistance:Number(run.requestedSpawnDistance),
            spawnDistance:Number(run.spawnDistance),
            blueFormation:String(run.blueFormation),
            redFormation:String(run.redFormation),
            formationSpacing:Number(run.formationSpacing),
            playerControlledSide:String(run.playerControlledSide),
            authorityContext:cloneJson(run.authorityContext),
            blueUnitResults:summarizeUnitResults(run.blueUnits),
            redUnitResults:summarizeUnitResults(run.redUnits),
            errors:cloneJson(run.errors)
        };
        run.frozenResult = cloneJson(result);
        run.phase = "terminal_pending";
        var outcome:Object;
        try {
            outcome = StageManager.getInstance()
                .completeWarlordActionEncounter(run.binding, result);
        } catch (completionError) {
            outcome = null;
            trace("[WarlordActionEncounter] completion threw: "
                + completionError);
        }
        if (outcome == null || outcome.accepted !== true) {
            failActiveCombat("action.completion-rejected");
        }
    }

    /** 异常只请求 StageManager 冻结事实并走 canonical return，不接管场景。 */
    private static function failActiveCombat(reasonCode:String):Void {
        var run:Object = _active;
        if (run == null) return;
        if (!isOpaqueId(reasonCode)) reasonCode = "action.combat-failed";
        run.phase = "terminal_pending";
        var outcome:Object;
        try {
            outcome = StageManager.getInstance()
                .freezeWarlordActionEncounter(run.binding, reasonCode);
        } catch (freezeError) {
            outcome = null;
            trace("[WarlordActionEncounter] manager freeze threw: "
                + freezeError);
        }
        if (outcome == null || outcome.disposition !== "frozen") {
            run.phase = "frozen";
            trace("[WarlordActionEncounter] combat frozen locally: "
                + reasonCode);
        }
    }

    private static function snapshotGlobals():Object {
        var keys:Array = ["当前为战斗地图", "无限过图模式",
            "敌人同伴数", "敌人总数", "控制目标",
            "控制目标全自动", "斗兽标定禁存档", "_agentCalibrationNoSave",
            "使用药剂", "主角被动技能"];
        var snapshot:Object = {keys:keys, values:{}, present:{}};
        for (var i:Number = 0; i < keys.length; i++) {
            var key:String = String(keys[i]);
            snapshot.present[key] = owns(_root, key);
            snapshot.values[key] = _root[key];
        }
        return snapshot;
    }

    private static function restoreGlobals(snapshot:Object):Void {
        if (snapshot == null || !(snapshot.keys instanceof Array)) return;
        for (var i:Number = 0; i < snapshot.keys.length; i++) {
            var key:String = String(snapshot.keys[i]);
            if (snapshot.present[key] === true) {
                _root[key] = snapshot.values[key];
            } else {
                delete _root[key];
            }
        }
    }

    private static function globalsMatchSnapshot(snapshot:Object):Boolean {
        if (snapshot == null || !(snapshot.keys instanceof Array)) return false;
        for (var i:Number = 0; i < snapshot.keys.length; i++) {
            var key:String = String(snapshot.keys[i]);
            var expectedPresent:Boolean = snapshot.present[key] === true;
            if (owns(_root, key) != expectedPresent) return false;
            if (expectedPresent && _root[key] !== snapshot.values[key]) return false;
        }
        return true;
    }

    private static function applyEncounterGlobals():Void {
        _root.当前为战斗地图 = true;
        _root.无限过图模式 = false;
        _root.敌人同伴数 = 0;
        _root.敌人总数 = 0;
        _root.斗兽标定禁存档 = true;
        _root._agentCalibrationNoSave = true;
        _root.使用药剂 = function():Void {
            // fresh 战术交战只投影主角；禁止消耗全局药剂库存。
        };
        if (_root.主角被动技能 != null
                && typeof _root.主角被动技能 == "object") {
            _root.主角被动技能 = cloneJson(_root.主角被动技能);
        }
    }

    private static function normalizeRoster(
            input:Array, side:String, errors:Array):Array {
        var out:Array = [];
        var seen:Object = {};
        if (!(input instanceof Array) || input.length == 0) {
            errors.push({code:"invalid_case", side:side,
                message:"roster is empty"});
            return out;
        }
        for (var i:Number = 0; i < input.length; i++) {
            var raw:Object = input[i];
            if (!isValidRosterItem(raw)) {
                errors.push({code:"invalid_actor_identity", side:side,
                    message:"roster item violates exact contract"});
                continue;
            }
            var sourceId:String = String(raw.sourceId);
            if (seen[sourceId] === true) {
                errors.push({code:"invalid_pet_identity", side:side,
                    unit:sourceId, message:"sourceId is duplicated"});
                continue;
            }
            seen[sourceId] = true;
            if (raw.projectionKind === "player_avatar") {
                out.push({projectionKind:"player_avatar",
                    sourceId:sourceId,
                    commanderId:String(raw.commanderId),
                    characterId:String(raw.characterId),
                    factionId:String(raw.factionId),
                    hpPermille:Number(raw.hpPermille)});
                continue;
            }
            var petId:Number = Number(raw.petId);
            var petDef:Object = resolvePetDefinition(petId);
            var identifier:String = String(raw.identifier);
            var rosterType:String = String(raw.rosterType);
            var catalogRosterType:String = petDef != undefined
                ? String(petDef.RosterType || "pet") : "";
            if (petDef == undefined
                    || String(petDef.Identifier) !== identifier
                    || catalogRosterType !== rosterType) {
                errors.push({code:"invalid_pet_identity", side:side,
                    petId:petId, identifier:identifier,
                    message:"pet identity does not match pets.xml"});
                continue;
            }
            var promotions:Array = normalizeStrategicPromotions(
                raw.strategicPromotions, petDef, side, petId,
                Number(raw.level), errors);
            if (promotions == undefined) continue;
            out.push({projectionKind:"pet_projection",
                sourceId:sourceId, petId:petId,
                identifier:identifier, rosterType:rosterType,
                level:Number(raw.level), hpPermille:Number(raw.hpPermille),
                strategicPromotions:promotions,
                height:Number(petDef.Height)});
        }
        return out;
    }

    private static function resolvePetDefinition(petId:Number):Object {
        if (_root.宠物库 == undefined || isNaN(petId) || petId < 0) {
            return undefined;
        }
        var direct:Object = _root.宠物库[petId];
        if (direct != undefined
                && (direct.id == undefined || Number(direct.id) == petId)) {
            return direct;
        }
        for (var i:Number = 0; i < _root.宠物库.length; i++) {
            var candidate:Object = _root.宠物库[i];
            if (candidate != undefined && Number(candidate.id) == petId) {
                return candidate;
            }
        }
        return undefined;
    }

    private static function normalizeStrategicPromotions(raw:Object,
            petDef:Object, side:String, petId:Number, level:Number,
            errors:Array):Array {
        if (!(raw instanceof Array) || raw.length > 3) {
            errors.push({code:"invalid_pet_progression", side:side,
                petId:petId,
                message:"strategicPromotions violates the bounded array"});
            return undefined;
        }
        var sourceNames:Array = extractPromotionNames(petDef.Promotion);
        var expected:Array = [];
        for (var i:Number = 0; i < sourceNames.length; i++) {
            var sourceName:String = String(sourceNames[i]);
            if (isStrategicPromotion(sourceName)) expected.push(sourceName);
        }
        if (raw.length > expected.length) {
            errors.push({code:"invalid_pet_progression", side:side,
                petId:petId, message:"progression exceeds pets.xml"});
            return undefined;
        }
        var normalized:Array = [];
        for (var j:Number = 0; j < raw.length; j++) {
            var name:String = String(raw[j]);
            if (!isStrategicPromotion(name) || name !== String(expected[j])
                    || level < strategicPromotionLevel(name)) {
                errors.push({code:"invalid_pet_progression", side:side,
                    petId:petId,
                    message:"progression is not a legal level prefix"});
                return undefined;
            }
            normalized.push(name);
        }
        return normalized;
    }

    private static function extractPromotionNames(promotion:Object):Array {
        if (promotion == undefined) return [];
        if (promotion instanceof Array) return promotion.slice();
        var items:Object = promotion.Item;
        if (items == undefined) return [];
        var out:Array = [];
        if (items instanceof Array) {
            for (var i:Number = 0; i < items.length; i++) {
                out.push(String(items[i]));
            }
        } else {
            out.push(String(items));
        }
        return out;
    }

    private static function isStrategicPromotion(name:String):Boolean {
        return name == "基础训练" || name == "强化药剂"
            || name == "超级血清";
    }

    private static function strategicPromotionLevel(name:String):Number {
        if (name == "基础训练") return 10;
        if (name == "强化药剂") return 25;
        if (name == "超级血清") return 50;
        return Number.POSITIVE_INFINITY;
    }

    private static function buildProjectedPetAttributes(unit:Object):Object {
        var attributes:Object = {
            宠物库数组号:Number(unit.petId),
            战术演习隔离副本:true,
            战旗战略投影:true,
            战旗投影契约:"catalog_identifier+strategic_progression_v1"
        };
        var promotions:Array = unit.strategicPromotions instanceof Array
            ? unit.strategicPromotions : [];
        if (promotions.length == 0) return attributes;
        var training:Object = {次数:0, 启用:true};
        for (var i:Number = 0; i < promotions.length; i++) {
            var name:String = String(promotions[i]);
            if (name == "基础训练") {
                training.基础训练 = true;
                training.次数 = Math.max(Number(training.次数), 1);
            } else if (name == "强化药剂") {
                training.强化药剂 = true;
                training.次数 = Math.max(Number(training.次数), 2);
            } else if (name == "超级血清") {
                training.超级血清 = true;
                training.次数 = Math.max(Number(training.次数), 3);
            }
        }
        attributes.基础训练 = training;
        return attributes;
    }

    private static function spawnSide(world:MovieClip,
            roster:Array, side:String,
            isEnemy:Boolean, x:Number, y:Number, runKey:String,
            formation:String, spacing:Number, errors:Array):Array {
        var out:Array = [];
        for (var i:Number = 0; i < roster.length; i++) {
            var unit:Object = roster[i];
            var position:Object = resolveFormationPosition(
                formation, side, i, roster.length, x, y, spacing);
            var name:String = "军阀动作_" + side + "_" + runKey + "_" + i;
            var init:Object = {};
            var spawnIdentifier:String;
            if (unit.projectionKind === "player_avatar") {
                if (isEnemy) {
                    errors.push({code:"player_avatar_side_mismatch", side:side,
                        unit:String(unit.sourceId),
                        message:"player avatar cannot spawn on the hostile side"});
                    continue;
                }
                var runtimeLevel:Number = Number(_root.等级);
                if (!isWhole(runtimeLevel) || runtimeLevel < 1
                        || runtimeLevel > 9999) {
                    errors.push({code:"player_avatar_profile_missing", side:side,
                        unit:String(unit.sourceId),
                        message:"runtime player level is unavailable"});
                    continue;
                }
                spawnIdentifier = (_root.特殊操作单位 != null
                        && String(_root.特殊操作单位) != "")
                    ? String(_root.特殊操作单位) : "主角-男";
                unit.runtimeLevel = runtimeLevel;
                unit.runtimeIdentifier = spawnIdentifier;
                init.等级 = runtimeLevel;
                init.身高 = _root.身高;
                init.名字 = _root.角色名;
                init.性别 = _root.性别;
                init.respawn = true;
                init.斗兽标定隔离 = true;
                init.战术演习隔离副本 = true;
                init.战旗战略投影 = true;
                init.战旗投影契约 = "player_avatar_isolated_v1";
            } else {
                spawnIdentifier = String(unit.identifier);
                init.等级 = Number(unit.level);
                init.宠物属性 = buildProjectedPetAttributes(unit);
                if (!isNaN(Number(unit.height)) && Number(unit.height) > 0) {
                    init.身高 = Number(unit.height);
                }
            }
            init.是否为敌人 = isEnemy;
            init.产生源 = "军阀动作源";
            init.掉落物 = [];
            init.不掉钱 = true;
            init.计算经验值 = function():Void {
                this.已加经验值 = true;
            };
            init._warlordActionUnit = true;
            // 从 attachMovie 的首个 update 起冻结所有单位 AI。玩家若因初始化
            // 漂移误走普通 onUpdate 分支，也不能在输入权威交接前被 AI 接管。
            init._warlordActionAiHeld = true;
            init._x = position.x;
            init._y = position.y;
            init.名字 = "军阀动作" + side + i;
            if (unit.projectionKind === "player_avatar") {
                init.名字 = String(_root.角色名 || "主角");
            }
            if (isEnemy) {
                world.军阀动作源.僵尸型敌人场上实际人数++;
                world.军阀动作源.僵尸型敌人总个数++;
            }
            if (unit.projectionKind === "player_avatar") {
                // 玩家模板在 attach/onLoad 期间读取控制目标来选择玩家状态机，
                // 因此必须在生成前绑定实例名，随后仍由 bindPlayerControl 复核。
                _root.控制目标 = name;
                // 保持玩家身份供后续帧的纸娃娃/操控编号初始化读取；以全自动
                // 临时冻结按键，武装提交时 bindPlayerControl 再一次性解冻。
                _root.控制目标全自动 = true;
            }

            var mc:MovieClip = _root.加载游戏世界人物(
                spawnIdentifier, name,
                world.getNextHighestDepth(), init);
            if (mc == undefined || mc._parent == undefined) {
                errors.push({code:"spawn_failed", side:side,
                    unit:String(unit.sourceId),
                    message:"unit loader did not attach the projected actor"});
                if (isEnemy) {
                    world.军阀动作源.僵尸型敌人场上实际人数--;
                    world.军阀动作源.僵尸型敌人总个数--;
                }
                continue;
            }
            mc.不掉钱 = true;
            mc.掉落物 = [];
            mc.计算经验值 = function():Void {
                this.已加经验值 = true;
            };
            mc._warlordActionUnit = true;
            mc._warlordActionSide = side;
            mc._warlordActionAiHeld = true;
            mc.攻击目标 = "无";
            installDeathFence(mc,
                unit.projectionKind === "player_avatar");
            var startMaxHp:Number = readMaxHp(mc);
            var record:Object = {};
            record.mc = mc;
            record.projectionKind = String(unit.projectionKind);
            record.sourceId = String(unit.sourceId);
            record.hpPermille = Number(unit.hpPermille);
            record.startMaxHp = startMaxHp;
            record.startSnapshotReady = startMaxHp > 0;
            record.initialHpApplied = false;
            record.side = side;
            record.isEnemy = isEnemy;
            record.aiHeld = true;
            record.countReleased = false;
            record.deathObserved = false;
            record.deadFinalized = false;
            record.spawnX = position.x;
            record.spawnY = position.y;
            if (unit.projectionKind === "player_avatar") {
                record.commanderId = String(unit.commanderId);
                record.characterId = String(unit.characterId);
                record.factionId = String(unit.factionId);
                record.runtimeLevel = Number(unit.runtimeLevel);
                record.runtimeIdentifier = String(unit.runtimeIdentifier);
                record.controlReleased = false;
            } else {
                record.petId = Number(unit.petId);
                record.identifier = String(unit.identifier);
                record.resolvedType = String(unit.identifier);
                record.rosterType = String(unit.rosterType);
                record.strategicPromotions = unit.strategicPromotions.slice();
                record.level = Number(unit.level);
            }
            out.push(record);
        }
        return out;
    }

    private static function installDeathFence(
            mc:MovieClip, isPlayerAvatar:Boolean):Void {
        if (mc == undefined || mc._warlordActionOriginalDeathCheck != undefined) {
            return;
        }
        if (isPlayerAvatar) {
            mc.斗兽标定隔离 = true;
            mc._warlordActionPlayerAvatar = true;
        }
        mc._warlordActionOriginalDeathCheck = mc.死亡检测;
        mc.死亡检测 = function(parameters):Void {
            if (parameters == undefined) parameters = {};
            parameters.noCount = true;
            this.不掉钱 = true;
            this.掉落物 = [];
            this._warlordActionDeathCheckCalled = true;
            if (typeof this._warlordActionOriginalDeathCheck == "function") {
                this._warlordActionOriginalDeathCheck(parameters);
            }
        };
    }

    private static function captureStartSnapshots(units:Array,
            finalAttempt:Boolean, errors:Array):Boolean {
        var ready:Boolean = true;
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (record.startSnapshotReady === true
                    && record.initialHpApplied === true) continue;
            var unitMax:Number = Number(record.startMaxHp);
            if (isNaN(unitMax) || unitMax <= 0) {
                unitMax = readMaxHp(record.mc);
            }
            if (unitMax > 0) {
                record.startMaxHp = unitMax;
                record.startSnapshotReady = true;
                applyInitialHp(record, unitMax);
            } else if (finalAttempt) {
                errors.push({code:"hp_snapshot_missing", side:record.side,
                    unit:String(record.sourceId),
                    message:"runtime max hp was not initialized"});
                record.startSnapshotReady = false;
                ready = false;
            } else {
                ready = false;
            }
        }
        return ready;
    }

    /**
     * attachMovie 的同步返回只证明 placement。战斗武装必须等待通用
     * StaticInitializer 的版本闩锁、基础组件和实际可见 bounds 全部成立。
     */
    private static function isActorVisualReady(
            record:Object, world:Object):Boolean {
        if (record == null || world == null) return false;
        var mc:Object = record.mc;
        if (mc == undefined || mc._parent !== world
                || mc._visible === false) return false;
        var version:Number = Number(mc.version);
        if (!isFinite(version)
                || mc.__unitInitializedVersion !== mc.version) return false;
        var requiresUnitAi:Boolean = record.projectionKind !== "player_avatar";
        if (mc.dispatcher == undefined
                || typeof mc.dispatcher.publish != "function"
                || mc.aabbCollider == undefined
                || (requiresUnitAi && mc.unitAI == undefined)
                || mc.shield == undefined) {
            return false;
        }
        if (!requiresUnitAi && !isPlayerAvatarInitialized(record)) {
            return false;
        }
        var width:Number = Number(mc._width);
        var height:Number = Number(mc._height);
        return isFinite(width) && width > 0
            && isFinite(height) && height > 0;
    }

    private static function areActorsVisualReady(
            units:Array, world:Object):Boolean {
        if (!(units instanceof Array) || units.length == 0) return false;
        for (var i:Number = 0; i < units.length; i++) {
            if (!isActorVisualReady(units[i], world)) return false;
        }
        return true;
    }

    /** 主 XFL 的“空”标签位于运行时第 36 帧，是标准淡出后的静止态。 */
    private static function isSceneRevealReady():Boolean {
        var fade:Object = _root.淡出动画;
        return fade == undefined
            || Number(fade._currentframe) == SCENE_REVEAL_IDLE_FRAME;
    }

    private static function setPreArmAiHold(
            record:Object, held:Boolean):Void {
        if (record == null) return;
        var mc:Object = record.mc;
        if (mc == undefined || mc._parent == undefined) return;
        record.aiHeld = held;
        mc._warlordActionAiHeld = held;
    }

    /**
     * 主角可见不等于可操作。只有标准主角分支完成操控编号、11 槽 canonical
     * 装备投影与纸娃娃刷新后才允许战斗武装；否则宁可停在淡入后等待/失败，
     * 也不能把裸体非主角实例交给 AI。
     */
    private static function isPlayerAvatarInitialized(record:Object):Boolean {
        if (record == null || record.projectionKind !== "player_avatar") {
            return false;
        }
        var mc:Object = record.mc;
        var inventory:Object = _root.物品栏 != undefined
            ? _root.物品栏.装备栏 : undefined;
        if (mc == undefined || inventory == undefined
                || typeof inventory.getItem != "function") return false;
        var slotKeys:Array = RuntimeEquipmentProjection.getSlotKeys();
        var canonicalRefs:Array = [];
        for (var i:Number = 0; i < slotKeys.length; i++) {
            canonicalRefs[i] = inventory.getItem(String(slotKeys[i]));
        }
        return mc != undefined
            && Number(mc.操控编号) == 0
            && mc.hasDressup === true
            && RuntimeEquipmentProjection.getStatus(mc, canonicalRefs)
                == RuntimeEquipmentProjection.STATUS_ALIGNED;
    }

    private static function releasePreArmAiHolds(units:Array):Void {
        if (!(units instanceof Array)) return;
        for (var i:Number = 0; i < units.length; i++) {
            setPreArmAiHold(units[i], false);
        }
    }

    private static function traceActorReadiness(
            units:Array, world:Object, phase:String):Void {
        if (!(units instanceof Array)) return;
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            var mc:Object = record != null ? record.mc : undefined;
            trace("[WarlordActionEncounter] actor " + phase
                + " sourceId=" + String(record != null
                    ? record.sourceId : "")
                + " identifier=" + String(record != null
                    ? (record.projectionKind === "player_avatar"
                        ? record.runtimeIdentifier : record.identifier) : "")
                + " level=" + String(record != null
                    ? (record.projectionKind === "player_avatar"
                        ? record.runtimeLevel : record.level) : "")
                + " parent=" + String(mc != undefined && mc._parent != undefined
                    ? mc._parent._name : "detached")
                + " hp=" + String(mc != undefined ? mc.hp : "")
                + "/" + String(mc != undefined ? mc.hp满血值 : "")
                + " visible=" + String(mc != undefined ? mc._visible : false)
                + " bounds=" + String(mc != undefined ? mc._width : 0)
                + "x" + String(mc != undefined ? mc._height : 0)
                + " initialized=" + String(mc != undefined
                    ? mc.__unitInitializedVersion : "")
                + " controlTarget=" + String(_root.控制目标)
                + " controlIndex=" + String(mc != undefined
                    ? mc.操控编号 : "")
                + " dressup=" + String(mc != undefined
                    ? mc.hasDressup : false)
                + " equipmentAligned=" + String(record != null
                    && record.projectionKind === "player_avatar"
                    ? isPlayerAvatarInitialized(record) : true)
                + " aiHeld=" + String(mc != undefined
                    ? mc._warlordActionAiHeld : false)
                + " ready=" + String(isActorVisualReady(record, world)));
        }
    }

    /** 只在生命周期边界调用；不给每帧 readiness 热路径制造日志。 */
    private static function publishLifecycleDiagnostic(
            code:String, run:Object, detail:String):Void {
        try {
            var logger:Object = _root.服务器;
            if (logger == undefined
                    || typeof logger.发布服务器消息 != "function") return;
            var encounterId:String = run != null && run.binding != null
                ? String(run.binding.encounterId) : "";
            logger.发布服务器消息("[WarlordActionEncounter] " + code
                + " encounterId=" + encounterId + " detail=" + detail);
        } catch (lifecycleError) {
            trace("[WarlordActionEncounter] lifecycle log failed: "
                + lifecycleError);
        }
    }

    private static function applyInitialHp(
            record:Object, unitMax:Number):Void {
        if (record == undefined || record.initialHpApplied === true) return;
        var mc:MovieClip = record.mc;
        if (mc == undefined || mc._parent == undefined
                || isNaN(unitMax) || unitMax <= 0) return;
        var hpPermille:Number = Number(record.hpPermille);
        var initialHp:Number = Math.max(
            1, Math.round(unitMax * hpPermille / 1000));
        if (initialHp > unitMax) initialHp = unitMax;
        mc.hp = initialHp;
        record.initialHpApplied = true;
    }

    private static function primeTargets(
            blueUnits:Array, redUnits:Array):Void {
        var i:Number;
        for (i = 0; i < blueUnits.length; i++) {
            var blueRecord:Object = blueUnits[i];
            var blue:MovieClip = blueRecord.mc;
            var redTarget:MovieClip = redUnits[i % redUnits.length].mc;
            if (isAiPrimeCandidate(blueRecord)
                    && blue != undefined && blue._parent != undefined
                    && redTarget != undefined
                    && redTarget._parent != undefined) {
                blue.攻击目标 = redTarget._name;
            }
        }
        for (i = 0; i < redUnits.length; i++) {
            var redRecord:Object = redUnits[i];
            var red:MovieClip = redRecord.mc;
            var blueTarget:MovieClip = blueUnits[i % blueUnits.length].mc;
            if (isAiPrimeCandidate(redRecord)
                    && red != undefined && red._parent != undefined
                    && blueTarget != undefined
                    && blueTarget._parent != undefined) {
                red.攻击目标 = blueTarget._name;
            }
        }
    }

    private static function isAiPrimeCandidate(record:Object):Boolean {
        return record != null
            && record.projectionKind !== "player_avatar";
    }

    private static function bindPlayerControl(
            run:Object, switchCamera:Boolean):Boolean {
        if (run == null) return false;
        if (String(run.playerControlledSide) === "none") return true;
        var source:Array = String(run.playerControlledSide) === "blue"
            ? run.blueUnits : run.redUnits;
        if (!(source instanceof Array)) return false;
        var avatar:Object = null;
        for (var i:Number = 0; i < source.length; i++) {
            if (source[i] != null
                    && source[i].projectionKind === "player_avatar") {
                if (avatar != null) return false;
                avatar = source[i];
            }
        }
        if (avatar == null || avatar.mc == undefined
                || avatar.mc._parent == undefined
                || !isPlayerAvatarInitialized(avatar)) return false;
        run.playerAvatar = avatar;
        run.playerControlReleased = false;
        avatar.controlReleased = false;
        _root.控制目标 = avatar.mc._name;
        _root.控制目标全自动 = false;
        if (switchCamera) HorizontalScroller.switchFollowTo(avatar.mc);
        return true;
    }

    private static function releasePlayerControl(run:Object,
            record:Object, switchCamera:Boolean):Void {
        if (run == null || record == null
                || record.projectionKind !== "player_avatar"
                || record.controlReleased === true) return;
        record.controlReleased = true;
        run.playerControlReleased = true;
        _root.控制目标 = "军阀动作镜头";
        if (switchCamera && run.camera != undefined) {
            HorizontalScroller.switchFollowTo(run.camera);
        }
    }

    private static function observeUnits(units:Array):Void {
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (record == undefined || record.deathObserved === true) continue;
            var mc:MovieClip = record.mc;
            if (mc == undefined || mc._parent == undefined
                    || Number(mc.hp) <= 0) {
                record.deathObserved = true;
                if (record.projectionKind === "player_avatar") {
                    releasePlayerControl(_active, record, true);
                }
                releaseDeathCount(record);
            }
        }
    }

    private static function hasPendingDeathEffects(units:Array):Boolean {
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (record == undefined || record.deadFinalized === true
                    || record.deathObserved !== true) continue;
            var mc:MovieClip = record.mc;
            if (mc != undefined && mc._parent != undefined) {
                if (mc._warlordActionDeathCheckCalled === true) {
                    record.deadFinalized = true;
                    continue;
                }
                return true;
            }
            record.deadFinalized = true;
        }
        return false;
    }

    private static function releaseDeathCount(record:Object):Void {
        if (record == undefined || record.countReleased === true) return;
        record.countReleased = true;
        if (record.isEnemy === true && _active != null
                && _active.world != null
                && _active.world.军阀动作源 != undefined) {
            var source:Object = _active.world.军阀动作源;
            if (Number(source.僵尸型敌人场上实际人数) > 0) {
                source.僵尸型敌人场上实际人数--;
            }
            if (Number(source.僵尸型敌人总个数) > 0) {
                source.僵尸型敌人总个数--;
            }
        }
    }

    private static function countAlive(units:Array):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            var mc:MovieClip = record != undefined ? record.mc : undefined;
            if (mc != undefined && mc._parent != undefined
                    && Number(mc.hp) > 0) count++;
        }
        return count;
    }

    private static function summarizeUnitResults(units:Array):Array {
        var out:Array = [];
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            var unitMax:Number = Number(record.startMaxHp);
            if (isNaN(unitMax) || unitMax < 0) unitMax = 0;
            var unitHp:Number = 0;
            var mc:MovieClip = record.mc;
            if (mc != undefined && mc._parent != undefined) {
                unitHp = Number(mc.hp);
                if (isNaN(unitHp) || unitHp < 0) unitHp = 0;
            }
            if (unitMax > 0 && unitHp > unitMax) unitHp = unitMax;
            var permille:Number = unitMax > 0
                ? Math.round(unitHp * 1000 / unitMax) : 0;
            if (unitHp > 0 && permille < 1) permille = 1;
            permille = clampNumber(permille, 0, 1000);
            if (record.projectionKind === "player_avatar") {
                var runtimeLevel:Number = Number(record.runtimeLevel);
                if (mc != undefined && mc._parent != undefined
                        && isWhole(Number(mc.等级))) {
                    runtimeLevel = Number(mc.等级);
                }
                out.push({projectionKind:"player_avatar",
                    sourceId:String(record.sourceId),
                    commanderId:String(record.commanderId),
                    characterId:String(record.characterId),
                    factionId:String(record.factionId),
                    runtimeLevel:runtimeLevel,
                    startMaxHp:Math.round(unitMax),
                    remainHp:Math.round(unitHp),
                    hpPermille:Math.round(permille),
                    alive:unitHp > 0});
            } else {
                out.push({projectionKind:"pet_projection",
                    sourceId:String(record.sourceId),
                    petId:Number(record.petId),
                    identifier:String(record.identifier),
                    resolvedType:String(record.resolvedType),
                    level:Number(record.level),
                    strategicPromotions:record.strategicPromotions.slice(),
                    strategicPromotionsValid:true,
                    startMaxHp:Math.round(unitMax),
                    remainHp:Math.round(unitHp),
                    hpPermille:Math.round(permille),
                    alive:unitHp > 0});
            }
        }
        return out;
    }

    private static function readMaxHp(mc:MovieClip):Number {
        var value:Number = 0;
        if (mc != undefined && mc._parent != undefined) {
            value = Number(mc.hp满血值);
            if (isNaN(value) || value <= 0) value = Number(mc.hp);
        }
        if (isNaN(value) || value < 0) value = 0;
        return value;
    }

    private static function updateCamera(force:Boolean):Void {
        var run:Object = _active;
        if (run == null || run.camera == undefined) return;
        if (run.playerAvatar != null
                && run.playerControlReleased !== true
                && countAlive([run.playerAvatar]) > 0) return;
        if (!force && (Number(run.frames) % 6) != 0) return;
        var centroid:Object = activeCentroid(run.blueUnits, run.redUnits);
        if (centroid == null) centroid = {x:CENTER_X, y:CENTER_Y};
        var targetX:Number = clampNumber(Number(centroid.x), XMIN, XMAX);
        var targetY:Number = clampNumber(Number(centroid.y), YMIN, YMAX);
        if (force) {
            run.camera._x = targetX;
            run.camera._y = targetY;
        } else {
            run.camera._x += (targetX - run.camera._x) / 6;
            run.camera._y += (targetY - run.camera._y) / 6;
        }
    }

    private static function activeCentroid(
            blueUnits:Array, redUnits:Array):Object {
        var aggregate:Object = {x:0, y:0, count:0};
        accumulateCentroid(blueUnits, aggregate);
        accumulateCentroid(redUnits, aggregate);
        if (aggregate.count == 0) return null;
        return {x:aggregate.x / aggregate.count,
            y:aggregate.y / aggregate.count};
    }

    private static function accumulateCentroid(
            units:Array, aggregate:Object):Void {
        for (var i:Number = 0; i < units.length; i++) {
            var mc:MovieClip = units[i] != undefined
                ? units[i].mc : undefined;
            if (mc == undefined || mc._parent == undefined
                    || Number(mc.hp) <= 0) continue;
            aggregate.x += Number(mc._x);
            aggregate.y += Number(mc._y);
            aggregate.count++;
        }
    }
    private static function resolveOrigin(distanceValue:Number):Object {
        var minX:Number = XMIN + EDGE_RESERVE;
        var maxX:Number = XMAX - EDGE_RESERVE;
        var maxDistance:Number = maxX - minX;
        var distance:Number = Math.round(distanceValue);
        if (isNaN(distance) || distance < MIN_DISTANCE) distance = MIN_DISTANCE;
        distance = clampNumber(distance, MIN_DISTANCE, maxDistance);
        var half:Number = distance * 0.5;
        var center:Number = clampNumber(CENTER_X,
            minX + half, maxX - half);
        return {blueX:center - half, redX:center + half,
            y:CENTER_Y, spawnDistance:Math.round(distance)};
    }

    private static function normalizeSpacing(value:Number):Number {
        if (isNaN(value) || value <= 0) value = DEFAULT_SPACING;
        return Math.round(clampNumber(value, MIN_SPACING, MAX_SPACING));
    }

    private static function resolveFormationPosition(formation:String,
            side:String, index:Number, total:Number, anchorX:Number,
            anchorY:Number, spacing:Number):Object {
        if (total < 1) total = 1;
        spacing = normalizeSpacing(spacing);
        var direction:Number = side == "blue" ? -1 : 1;
        var maxVertical:Number = Math.max(
            1, Math.floor((YMAX - YMIN) / spacing) + 1);
        if (maxVertical > total) maxVertical = total;
        var x:Number = anchorX;
        var y:Number = anchorY;

        if (formation == "column") {
            y = resolveFormationY(anchorY, index, total, spacing);
        } else if (formation == "wedge") {
            if (total == 2) {
                x = anchorX + direction * index
                    * resolveFormationDepthStep(side, anchorX, spacing, 2);
                y = index == 0 ? anchorY : anchorY - spacing;
            } else {
                var wedge:Object = resolveWedgeSlot(
                    index, total, maxVertical);
                x = anchorX + direction * wedge.row
                    * resolveFormationDepthStep(
                        side, anchorX, spacing, wedge.depthSlots);
                y = resolveFormationY(anchorY, wedge.lane,
                    wedge.laneCount, spacing);
            }
        } else if (formation == "shield") {
            if (total >= 2 && total <= 4) {
                var frontCount:Number = total - 1;
                if (index < frontCount) {
                    x = anchorX;
                    var frontSpacing:Number = total == 3
                        ? spacing * 2 : spacing;
                    y = resolveFormationY(anchorY, index,
                        frontCount, frontSpacing);
                } else {
                    x = anchorX + direction * resolveFormationDepthStep(
                        side, anchorX, spacing, 2);
                    y = total == 2 ? anchorY + spacing * 0.5 : anchorY;
                }
            } else {
                var shieldFront:Number = Math.min(5, total);
                if (index < shieldFront) {
                    y = resolveFormationY(anchorY, index,
                        shieldFront, spacing);
                } else {
                    var shieldAnchor:Number = anchorX + direction
                        * resolveFormationDepthStep(side, anchorX, spacing,
                            Math.ceil((total - shieldFront)
                                / maxVertical) + 1);
                    var shieldPos:Object = resolveGridPosition(side,
                        index - shieldFront, total - shieldFront,
                        shieldAnchor, anchorY, spacing, maxVertical);
                    x = shieldPos.x;
                    y = shieldPos.y;
                }
            }
        } else if (formation == "grid") {
            var grid:Object = resolveGridPosition(side, index, total,
                anchorX, anchorY, spacing, maxVertical);
            x = grid.x;
            y = grid.y;
        } else {
            x = anchorX + direction * index
                * resolveFormationDepthStep(
                    side, anchorX, spacing, total);
        }
        return {x:clampNumber(Math.round(x), XMIN, XMAX),
            y:clampNumber(Math.round(y), YMIN, YMAX)};
    }

    private static function resolveGridPosition(side:String, index:Number,
            total:Number, anchorX:Number, anchorY:Number, spacing:Number,
            maxVertical:Number):Object {
        var verticalCount:Number = Math.ceil(Math.sqrt(total));
        verticalCount = clampNumber(verticalCount, 1, maxVertical);
        var depth:Number = Math.floor(index / verticalCount);
        var lane:Number = index % verticalCount;
        var laneCount:Number = Math.min(
            verticalCount, total - depth * verticalCount);
        var depthSlots:Number = Math.ceil(total / verticalCount);
        var direction:Number = side == "blue" ? -1 : 1;
        return {x:anchorX + direction * depth
                * resolveFormationDepthStep(
                    side, anchorX, spacing, depthSlots),
            y:resolveFormationY(anchorY, lane, laneCount, spacing)};
    }

    private static function resolveWedgeSlot(index:Number, total:Number,
            maxVertical:Number):Object {
        var consumed:Number = 0;
        var row:Number = 0;
        var rowSize:Number = 1;
        while (consumed + rowSize <= index
                && consumed + rowSize < total) {
            consumed += rowSize;
            row++;
            rowSize = Math.min(row + 1, maxVertical);
        }
        return {row:row, lane:index - consumed,
            laneCount:Math.min(rowSize, total - consumed),
            depthSlots:row + 1};
    }

    private static function resolveFormationY(anchorY:Number, lane:Number,
            laneCount:Number, spacing:Number):Number {
        if (laneCount <= 1) return clampNumber(anchorY, YMIN, YMAX);
        var step:Number = Math.min(
            spacing, (YMAX - YMIN) / (laneCount - 1));
        return clampNumber(anchorY
            + (lane - (laneCount - 1) * 0.5) * step, YMIN, YMAX);
    }

    private static function resolveFormationDepthStep(side:String,
            anchorX:Number, spacing:Number, depthSlots:Number):Number {
        if (depthSlots <= 1) return 0;
        var available:Number = side == "blue"
            ? anchorX - XMIN : XMAX - anchorX;
        if (available <= 0) return 0;
        return Math.min(spacing, available / (depthSlots - 1));
    }

    private static function isStartEnvelope(value:Object):Boolean {
        return value != null && typeof value == "object"
            && !(value instanceof Array)
            && hasExactOwnKeys(value, COMMAND_KEYS)
            && value.task === "cmd"
            && value.action === START_ACTION
            && isValidBinding(value.binding)
            && isValidControl(value.encounter);
    }

    private static function isValidBinding(value:Object):Boolean {
        return value != null && typeof value == "object"
            && !(value instanceof Array)
            && hasExactOwnKeys(value, BINDING_KEYS)
            && value.schema === BINDING_SCHEMA
            && isOpaqueId(value.outerRunId)
            && isOpaqueId(value.encounterId)
            && isOpaqueId(value.requestId)
            && typeof value.inputDigest == "string"
            && CANONICAL_DIGEST_PATTERN.test(value.inputDigest);
    }

    private static function isValidAdmission(value:Object):Boolean {
        return value != null && typeof value == "object"
            && !(value instanceof Array)
            && hasExactOwnKeys(value, ADMISSION_KEYS)
            && value.schema === ADMISSION_SCHEMA
            && isValidBinding(value.binding)
            && (value.disposition === "accepted"
                || value.disposition === "duplicate")
            && isAdmissionPhase(value.phase);
    }

    private static function isAdmissionPhase(value):Boolean {
        return value === "prepared" || value === "entering"
            || value === "activating" || value === "active"
            || value === "returning" || value === "terminal";
    }

    private static function isValidTerminal(value:Object):Boolean {
        return value != null && typeof value == "object"
            && !(value instanceof Array)
            && hasExactOwnKeys(value, TERMINAL_KEYS)
            && value.schema === TERMINAL_SCHEMA
            && isOpaqueId(value.outerRunId)
            && isOpaqueId(value.encounterId)
            && isOpaqueId(value.requestId)
            && typeof value.inputDigest == "string"
            && CANONICAL_DIGEST_PATTERN.test(value.inputDigest)
            && (value.status === "completed"
                || value.status === "not_started"
                || value.status === "unknown")
            && isOpaqueId(value.reasonCode)
            && (value.status === "completed"
                ? value.result != null && typeof value.result == "object"
                    && !(value.result instanceof Array)
                : value.result == null);
    }

    private static function isValidControl(value:Object):Boolean {
        if (value == null || typeof value != "object"
                || value instanceof Array
                || !hasExactOwnKeys(value, CONTROL_KEYS)
                || value.schema !== CONTROL_SCHEMA
                || !isOpaqueId(value.battleId)
                || !(value.blueRoster instanceof Array)
                || !(value.redRoster instanceof Array)
                || value.blueRoster.length < 1 || value.blueRoster.length > 64
                || value.redRoster.length < 1 || value.redRoster.length > 64
                || !isWhole(value.timeoutFrames)
                || Number(value.timeoutFrames) < 1
                || Number(value.timeoutFrames) > 36000
                || !isWhole(value.spawnDistance)
                || !isAllowedDistance(Number(value.spawnDistance))
                || !isFormation(value.blueFormation)
                || !isFormation(value.redFormation)
                || !isWhole(value.formationSpacing)
                || Number(value.formationSpacing) < MIN_SPACING
                || Number(value.formationSpacing) > MAX_SPACING
                || value.authorityContext == null
                || typeof value.authorityContext != "object"
                || value.authorityContext instanceof Array
                || !isPlayerControlledSide(value.playerControlledSide)) {
            return false;
        }
        if (!isValidRoster(value.blueRoster)
                || !isValidRoster(value.redRoster)) return false;
        return hasConsistentPlayerAvatar(value.blueRoster, value.redRoster,
            String(value.playerControlledSide));
    }

    private static function isValidRoster(value:Array):Boolean {
        var seen:Object = {};
        for (var i:Number = 0; i < value.length; i++) {
            if (!isValidRosterItem(value[i])) return false;
            var sourceId:String = String(value[i].sourceId);
            if (seen[sourceId] === true) return false;
            seen[sourceId] = true;
        }
        return true;
    }

    private static function isValidRosterItem(value:Object):Boolean {
        if (value == null || typeof value != "object"
                || value instanceof Array
                || typeof value.projectionKind != "string") return false;
        if (value.projectionKind === "pet_projection") {
            return isValidPetRosterItem(value);
        }
        if (value.projectionKind === "player_avatar") {
            return isValidPlayerAvatarRosterItem(value);
        }
        return false;
    }

    private static function isValidPetRosterItem(value:Object):Boolean {
        if (!hasExactOwnKeys(value, PET_ROSTER_KEYS)
                || !isPieceId(value.sourceId)
                || !isWhole(value.petId) || Number(value.petId) < 0
                || Number(value.petId) > MAX_SAFE_INTEGER
                || typeof value.identifier != "string"
                || String(value.identifier).length < 1
                || String(value.identifier).length > 160
                || (value.rosterType !== "partner"
                    && value.rosterType !== "pet"
                    && value.rosterType !== "mechanical")
                || !isWhole(value.level) || Number(value.level) < 1
                || Number(value.level) > 9999
                || !isWhole(value.hpPermille)
                || Number(value.hpPermille) < 1
                || Number(value.hpPermille) > 1000
                || !(value.strategicPromotions instanceof Array)
                || value.strategicPromotions.length > 3) return false;
        for (var i:Number = 0; i < value.strategicPromotions.length; i++) {
            if (typeof value.strategicPromotions[i] != "string"
                    || !isStrategicPromotion(
                        String(value.strategicPromotions[i]))) return false;
        }
        return true;
    }

    private static function isValidPlayerAvatarRosterItem(
            value:Object):Boolean {
        return hasExactOwnKeys(value, PLAYER_AVATAR_ROSTER_KEYS)
            && value.projectionKind === "player_avatar"
            && isPieceId(value.sourceId)
            && value.commanderId === "commander.player"
            && value.characterId === "character.player-avatar"
            && value.factionId === "player"
            && isWhole(value.hpPermille)
            && Number(value.hpPermille) > 0
            && Number(value.hpPermille) <= 1000;
    }

    private static function isPlayerControlledSide(value):Boolean {
        return value === "blue" || value === "red" || value === "none";
    }

    private static function hasConsistentPlayerAvatar(blueRoster:Array,
            redRoster:Array, playerControlledSide:String):Boolean {
        var blueCount:Number = countProjectionKind(
            blueRoster, "player_avatar");
        var redCount:Number = countProjectionKind(
            redRoster, "player_avatar");
        if (playerControlledSide === "none") {
            return blueCount == 0 && redCount == 0;
        }
        if (playerControlledSide === "blue") {
            return blueCount == 1 && redCount == 0;
        }
        return blueCount == 0 && redCount == 1;
    }

    private static function countProjectionKind(
            roster:Array, projectionKind:String):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < roster.length; i++) {
            if (roster[i] != null
                    && roster[i].projectionKind === projectionKind) count++;
        }
        return count;
    }

    private static function isAllowedDistance(value:Number):Boolean {
        return value == 180 || value == 360 || value == 650;
    }

    private static function isFormation(value):Boolean {
        return value === "line" || value === "column"
            || value === "wedge" || value === "shield"
            || value === "grid";
    }

    private static function sameBinding(left:Object, right:Object):Boolean {
        return isValidBinding(left) && isValidBinding(right)
            && left.schema === right.schema
            && left.outerRunId === right.outerRunId
            && left.encounterId === right.encounterId
            && left.requestId === right.requestId
            && left.inputDigest === right.inputDigest;
    }

    private static function terminalMatchesBinding(
            terminal:Object, binding:Object):Boolean {
        return isValidTerminal(terminal) && isValidBinding(binding)
            && terminal.outerRunId === binding.outerRunId
            && terminal.encounterId === binding.encounterId
            && terminal.requestId === binding.requestId
            && terminal.inputDigest === binding.inputDigest;
    }

    private static function sameTerminalIdentity(
            left:Object, right:Object):Boolean {
        return isValidTerminal(left) && isValidTerminal(right)
            && left.outerRunId === right.outerRunId
            && left.encounterId === right.encounterId
            && left.requestId === right.requestId
            && left.inputDigest === right.inputDigest;
    }

    private static function cloneBinding(value:Object):Object {
        if (value == null) return null;
        return {schema:value.schema, outerRunId:value.outerRunId,
            encounterId:value.encounterId, requestId:value.requestId,
            inputDigest:value.inputDigest};
    }

    private static function cloneJson(value) {
        if (value == null || typeof value != "object") return value;
        if (value instanceof Array) {
            var arrayCopy:Array = [];
            for (var i:Number = 0; i < value.length; i++) {
                arrayCopy.push(cloneJson(value[i]));
            }
            return arrayCopy;
        }
        var objectCopy:Object = {};
        for (var key:String in value) {
            if (owns(value, key)) objectCopy[key] = cloneJson(value[key]);
        }
        return objectCopy;
    }

    /** 跨异步边界只接受同形同值的普通 JSON 数据。 */
    private static function samePlainValue(left, right, depth:Number):Boolean {
        if (left === right) return true;
        if (depth > 32 || left == null || right == null
                || typeof left != typeof right
                || typeof left != "object") return false;
        var leftIsArray:Boolean = left instanceof Array;
        var rightIsArray:Boolean = right instanceof Array;
        if (leftIsArray != rightIsArray) return false;
        if (leftIsArray) {
            if (left.length != right.length) return false;
            for (var i:Number = 0; i < left.length; i++) {
                if (!samePlainValue(left[i], right[i], depth + 1)) return false;
            }
            return true;
        }
        var count:Number = 0;
        for (var key:String in left) {
            if (!owns(left, key)) continue;
            if (!owns(right, key)
                    || !samePlainValue(left[key], right[key], depth + 1)) {
                return false;
            }
            count++;
        }
        var rightCount:Number = 0;
        for (var rightKey:String in right) {
            if (owns(right, rightKey)) rightCount++;
        }
        return count == rightCount;
    }

    private static function hasExactOwnKeys(
            value:Object, expected:Array):Boolean {
        if (value == null || typeof value != "object") return false;
        var count:Number = 0;
        for (var key:String in value) {
            if (!owns(value, key)) continue;
            if (!containsExact(expected, key)) return false;
            count++;
        }
        if (count != expected.length) return false;
        for (var i:Number = 0; i < expected.length; i++) {
            if (!owns(value, String(expected[i]))) return false;
        }
        return true;
    }

    private static function owns(value:Object, key:String):Boolean {
        return value != null
            && Object.prototype.hasOwnProperty.call(value, key);
    }

    private static function containsExact(values:Array, value):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (values[i] === value) return true;
        }
        return false;
    }

    private static function isOpaqueId(value):Boolean {
        return typeof value == "string" && OPAQUE_ID_PATTERN.test(value);
    }

    private static function isPieceId(value):Boolean {
        return typeof value == "string"
            && new RegExp("^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$", "")
                .test(value);
    }

    private static function isWhole(value):Boolean {
        return typeof value == "number" && isFinite(value)
            && Math.floor(Number(value)) == Number(value);
    }

    private static function clampNumber(
            value:Number, min:Number, max:Number):Number {
        if (isNaN(value)) return min;
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    private static function sanitizeName(value:String):String {
        value = value.split("-").join("_");
        value = value.split(":").join("_");
        value = value.split(".").join("_");
        value = value.split("/").join("_");
        value = value.split("\\").join("_");
        return value;
    }
}
