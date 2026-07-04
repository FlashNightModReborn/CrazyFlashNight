/**
 * 文件：org/flashNight/arki/merc/ArenaCalibrationService.as
 * 说明：竞技场斗兽标定的 AS2 端 runner。
 *
 * C# 下发：
 *   {task:"cmd", action:"arenaCalibrationRun", callId, batchId, caseId, caseHash,
 *    runId, repeatIndex, timeoutFrames, spawnDistance?,
 *    blueFormation?, redFormation?, formationSpacing?,
 *    blueRoster:[{兵种,等级,Parameters}], redRoster:[{兵种,等级,Parameters}]}
 *   {task:"cmd", action:"arenaCalibrationAbort", callId, batchId, reason}
 *
 * AS2 回包：
 *   {task:"arena_calibration_response", callId, success, status, winner, frames,
 *    durationMs, spawnDistance, blueFormation, redFormation, formationSpacing,
 *    phaseSpawnCount, spawnedUnits, blueX, redX, blueSpawnPositions, redSpawnPositions,
 *    formationAudit, blue, red, errors}
 *
 * 本服务不走普通角斗场押金/奖金/FinishStage 链；若当前不在专用斗兽标定竞技场，
 * 先请求 StageManager 通过正常跳关进入 no-player host，再继续同一轮 run。
 * 专用舞台不生成主角/同伴，只生成本轮蓝/红单位，监控存活/超时，结束后清理生成单位并回包。
 */
import LiteJSON;
import org.flashNight.arki.camera.HorizontalScroller;
import org.flashNight.arki.scene.SceneManager;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.merc.ArenaController;

class org.flashNight.arki.merc.ArenaCalibrationService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _active:Object = undefined;
    private static var _pendingRun:Object = undefined;
    private static var _transitionStarted:Boolean = false;
    private static var _originalLoadGameWorldUnit:Function = undefined;
    private static var _loaderHookInstalled:Boolean = false;
    private static var _runSeq:Number = 0;
    private static var SNAPSHOT_WARMUP_FRAMES:Number = 5;
    private static var CALIBRATION_STAGE_LINKAGE:String = "wuxianguotu_1";
    private static var CALIBRATION_STAGE_NAME:String = "斗兽标定竞技场";
    private static var CALIBRATION_CENTER_X:Number = 895;
    private static var CALIBRATION_CENTER_Y:Number = 430;
    private static var CALIBRATION_DEFAULT_SPAWN_DISTANCE:Number = 650;
    private static var CALIBRATION_BLUE_X:Number = 570;
    private static var CALIBRATION_RED_X:Number = 1220;
    private static var CALIBRATION_XMIN:Number = 230;
    private static var CALIBRATION_XMAX:Number = 1560;
    private static var CALIBRATION_YMIN:Number = 242;
    private static var CALIBRATION_YMAX:Number = 620;
    private static var CALIBRATION_BG_WIDTH:Number = 1688;
    private static var CALIBRATION_BG_HEIGHT:Number = 640;
    private static var CALIBRATION_MIN_SPAWN_DISTANCE:Number = 360;
    private static var CALIBRATION_SPAWN_EDGE_RESERVE:Number = 290;
    private static var CALIBRATION_DEFAULT_FORMATION:String = "line";
    private static var CALIBRATION_DEFAULT_FORMATION_SPACING:Number = 54;
    private static var CALIBRATION_MIN_FORMATION_SPACING:Number = 36;
    private static var CALIBRATION_MAX_FORMATION_SPACING:Number = 96;
    private static var SPECTATOR_CAMERA_INTERVAL:Number = 4;
    private static var SPECTATOR_CAMERA_EASE:Number = 7;
    private static var SPECTATOR_CAMERA_PAIR_RANGE:Number = 760;

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["arenaCalibrationRun"] = function(params) {
            org.flashNight.arki.merc.ArenaCalibrationService.handleRun(params);
        };
        _root.gameCommands["arenaCalibrationAbort"] = function(params) {
            org.flashNight.arki.merc.ArenaCalibrationService.handleAbort(params);
        };

        _inited = true;
    }

    public static function handleRun(params:Object):Void {
        if (params == undefined) params = {};
        var callId = params.callId;

        if (_active != undefined) {
            finish("aborted", "none", [{code: "aborted", message: "superseded by a new calibration run"}]);
        }
        if (_pendingRun != undefined) {
            sendResponse({
                task: "arena_calibration_response",
                callId: _pendingRun.callId,
                success: false,
                status: "aborted",
                winner: "none",
                frames: 0,
                durationMs: 0,
                blue: emptySideSummary(),
                red: emptySideSummary(),
                errors: [{code: "aborted", message: "superseded by a new calibration run before stage ready"}]
            });
            _pendingRun = undefined;
        }

        if (!isLoaderReady()) {
            sendResponse({
                task: "arena_calibration_response",
                callId: callId,
                success: false,
                status: "stage_failed",
                winner: "none",
                frames: 0,
                durationMs: 0,
                blue: emptySideSummary(),
                red: emptySideSummary(),
                errors: [{code: "stage_failed", message: "unit loader or calibration stage loader is not ready"}]
            });
            return;
        }

        var errors:Array = [];
        var blueRoster:Array = normalizeRoster(params.blueRoster, "blue", errors);
        var redRoster:Array = normalizeRoster(params.redRoster, "red", errors);
        if (errors.length > 0) {
            sendResponse({
                task: "arena_calibration_response",
                callId: callId,
                success: false,
                status: "invalid_case",
                winner: "none",
                frames: 0,
                durationMs: 0,
                blue: emptySideSummary(),
                red: emptySideSummary(),
                errors: errors
            });
            return;
        }

        if (!isCalibrationStageActive()) {
            if (requestCalibrationStage(params, errors)) return;
            clearCalibrationGlobals();
            sendResponse({
                task: "arena_calibration_response",
                callId: callId,
                success: false,
                status: "stage_failed",
                winner: "none",
                frames: 0,
                durationMs: 0,
                blue: emptySideSummary(),
                red: emptySideSummary(),
                errors: errors.length > 0 ? errors : [{code: "stage_failed", message: "failed to enter calibration arena stage"}]
            });
            return;
        }

        if (!prepareCalibrationStage(errors) || !isRuntimeReady()) {
            clearCalibrationGlobals();
            sendResponse({
                task: "arena_calibration_response",
                callId: callId,
                success: false,
                status: "stage_failed",
                winner: "none",
                frames: 0,
                durationMs: 0,
                blue: emptySideSummary(),
                red: emptySideSummary(),
                errors: errors.length > 0 ? errors : [{code: "stage_failed", message: "calibration arena stage is not ready"}]
            });
            return;
        }

        _runSeq++;
        var runKey:String = sanitizeName(String(params.runId || ("run" + _runSeq)));
        var origin:Object = resolveOrigin(params);
        var blueFormation:String = normalizeFormation(params.blueFormation);
        var redFormation:String = normalizeFormation(params.redFormation);
        var formationSpacing:Number = resolveFormationSpacing(params);
        ensureCalibrationSource();
        guardArenaContamination(errors, true, true);

        var blueUnits:Array = spawnSide(blueRoster, "blue", false, origin.blueX, origin.y, runKey, blueFormation, formationSpacing, errors);
        var redUnits:Array = spawnSide(redRoster, "red", true, origin.redX, origin.y, runKey, redFormation, formationSpacing, errors);

        if (blueUnits.length == 0 || redUnits.length == 0) {
            var row:Object = {
                task: "arena_calibration_response",
                callId: callId,
                success: false,
                status: "spawn_failed",
                winner: "none",
                frames: 0,
                durationMs: 0,
                spawnDistance: origin.spawnDistance,
                blueFormation: blueFormation,
                redFormation: redFormation,
                formationSpacing: formationSpacing,
                phaseSpawnCount: 0,
                spawnedUnits: [],
                blueX: origin.blueX,
                redX: origin.redX,
                blueSpawnPositions: captureSpawnPositions(blueUnits),
                redSpawnPositions: captureSpawnPositions(redUnits),
                formationAudit: buildFormationAudit(blueUnits, redUnits),
                blue: summarizeSide(blueUnits),
                red: summarizeSide(redUnits),
                errors: errors
            };
            cleanupUnits(blueUnits);
            cleanupUnits(redUnits);
            resetCalibrationSource();
            clearCalibrationGlobals();
            sendResponse(row);
            return;
        }

        var timeoutFrames:Number = Number(params.timeoutFrames);
        if (isNaN(timeoutFrames) || timeoutFrames < 1) timeoutFrames = 5400;

        _active = {
            callId: callId,
            batchId: String(params.batchId || ""),
            caseId: String(params.caseId || ""),
            caseHash: String(params.caseHash || ""),
            runId: String(params.runId || runKey),
            repeatIndex: Number(params.repeatIndex),
            timeoutFrames: timeoutFrames,
            frames: 0,
            startedMs: getTimer(),
            primed: false,
            snapshotFrames: 0,
            blueUnits: blueUnits,
            redUnits: redUnits,
            errors: errors,
            spawnDistance: origin.spawnDistance,
            blueX: origin.blueX,
            redX: origin.redX,
            blueFormation: blueFormation,
            redFormation: redFormation,
            formationSpacing: formationSpacing,
            phaseSpawnCount: 0,
            spawnedUnits: [],
            lastHotspotX: CALIBRATION_CENTER_X,
            lastHotspotY: CALIBRATION_CENTER_Y
        };

        if (guardArenaContamination(errors, true, false) != true) {
            finish("contamination", "none", errors);
            return;
        }
        installPhaseSpawnHook();
        installClock();
    }

    public static function onCalibrationStageReady():Void {
        _transitionStarted = false;
        if (_pendingRun == undefined) {
            clearCalibrationGlobals();
            return;
        }
        var params:Object = _pendingRun;
        _pendingRun = undefined;
        handleRun(params);
    }

    public static function handleAbort(params:Object):Void {
        if (params == undefined) params = {};
        var callId = params.callId;
        var batchId:String = String(params.batchId || "");

        if (_pendingRun != undefined) {
            if (batchId != "" && String(_pendingRun.batchId || "") != "" && batchId != String(_pendingRun.batchId || "")) {
                sendResponse({
                    task: "arena_calibration_response",
                    callId: callId,
                    success: false,
                    status: "error",
                    winner: "none",
                    frames: 0,
                    durationMs: 0,
                    blue: emptySideSummary(),
                    red: emptySideSummary(),
                    errors: [{code: "batch_mismatch", message: "abort batchId does not match pending calibration run"}]
                });
                return;
            }

            _pendingRun = undefined;
            if (_transitionStarted != true) clearCalibrationGlobals();
            sendResponse({
                task: "arena_calibration_response",
                callId: callId,
                success: true,
                status: "aborted",
                winner: "none",
                frames: 0,
                durationMs: 0,
                blue: emptySideSummary(),
                red: emptySideSummary(),
                errors: [{code: "aborted", message: String(params.reason || "abort requested before stage ready")}]
            });
            return;
        }

        if (_active == undefined) {
            sendResponse({
                task: "arena_calibration_response",
                callId: callId,
                success: true,
                status: "aborted",
                winner: "none",
                frames: 0,
                durationMs: 0,
                blue: emptySideSummary(),
                red: emptySideSummary(),
                errors: [{code: "not_running", message: "no active calibration run"}]
            });
            return;
        }

        if (batchId != "" && String(_active.batchId || "") != "" && batchId != String(_active.batchId || "")) {
            sendResponse({
                task: "arena_calibration_response",
                callId: callId,
                success: false,
                status: "error",
                winner: "none",
                frames: _active.frames,
                durationMs: getTimer() - _active.startedMs,
                blue: summarizeSide(_active.blueUnits),
                red: summarizeSide(_active.redUnits),
                errors: [{code: "batch_mismatch", message: "abort batchId does not match active calibration run"}]
            });
            return;
        }

        var errors:Array = _active.errors;
        if (errors == undefined) errors = [];
        errors.push({code: "aborted", message: String(params.reason || "abort requested")});
        finish("aborted", "none", errors);
    }

    public static function tick():Void {
        if (_active == undefined) return;
        _active.frames++;
        var purged:Number = purgePlayerActors(_active.errors, _active.playerPurgeWarned != true);
        if (purged > 0) _active.playerPurgeWarned = true;
        if (guardArenaContamination(_active.errors, true, false) != true) {
            finish("contamination", "none", _active.errors);
            return;
        }

        if (_active.primed != true) {
            _active.snapshotFrames++;
            var blueReady:Boolean = captureStartSnapshots(_active.blueUnits, _active.errors, false);
            var redReady:Boolean = captureStartSnapshots(_active.redUnits, _active.errors, false);
            if ((blueReady && redReady) || _active.snapshotFrames >= SNAPSHOT_WARMUP_FRAMES) {
                captureStartSnapshots(_active.blueUnits, _active.errors, true);
                captureStartSnapshots(_active.redUnits, _active.errors, true);
                primeTargets(_active.blueUnits, _active.redUnits);
                _active.primed = true;
                updateSpectatorCamera(true);
            }
            return;
        }

        observeDeadUnits(_active.blueUnits);
        observeDeadUnits(_active.redUnits);
        updateSpectatorCamera(false);

        var blueAlive:Number = countAlive(_active.blueUnits);
        var redAlive:Number = countAlive(_active.redUnits);
        var deathEffectsPending:Boolean = hasPendingDeathEffects(_active.blueUnits) || hasPendingDeathEffects(_active.redUnits);

        if (_active.frames >= _active.timeoutFrames) {
            finish("timeout", "timeout", _active.errors);
            return;
        }
        if (deathEffectsPending == true) {
            return;
        }

        if (blueAlive <= 0 && redAlive <= 0) {
            finish("finished", "draw", _active.errors);
            return;
        }
        if (blueAlive <= 0) {
            finish("finished", "red", _active.errors);
            return;
        }
        if (redAlive <= 0) {
            finish("finished", "blue", _active.errors);
            return;
        }
    }

    private static function isRuntimeReady():Boolean {
        if (_root.gameworld == undefined) return false;
        if (typeof _root.gameworld.getNextHighestDepth != "function") return false;
        if (typeof _root.加载游戏世界人物 != "function") return false;
        if (_root.兵种库 == undefined) return false;
        return true;
    }

    public static function handleStageDataReady():Void {
        if (_pendingRun == undefined) return;
        if (typeof _root.淡出动画.淡出跳转帧 != "function") {
            handleStageDataFailed();
            return;
        }
        applyCalibrationTransitionGlobals();
        _transitionStarted = true;
        _root.淡出动画.淡出跳转帧(CALIBRATION_STAGE_LINKAGE);
    }

    public static function handleStageDataFailed():Void {
        if (_pendingRun == undefined) return;
        var params:Object = _pendingRun;
        _pendingRun = undefined;
        _transitionStarted = false;
        clearCalibrationGlobals();
        sendResponse({
            task: "arena_calibration_response",
            callId: params.callId,
            success: false,
            status: "stage_failed",
            winner: "none",
            frames: 0,
            durationMs: 0,
            blue: emptySideSummary(),
            red: emptySideSummary(),
            errors: [{code: "stage_failed", message: "failed to load calibration arena stage data"}]
        });
    }

    private static function isCalibrationStageActive():Boolean {
        return _root.gameworld != undefined && _root.gameworld._arenaCalibrationStage === true;
    }

    private static function isLoaderReady():Boolean {
        if (typeof _root.加载游戏世界人物 != "function") return false;
        if (typeof _root.加载共享场景 != "function") return false;
        if (_root.兵种库 == undefined) return false;
        return true;
    }

    private static function normalizeRoster(input:Array, side:String, errors:Array):Array {
        var out:Array = [];
        if (input == undefined || input.length == undefined || input.length == 0) {
            errors.push({code: "invalid_case", side: side, message: side + "Roster is empty"});
            return out;
        }

        for (var i:Number = 0; i < input.length; i++) {
            var raw:Object = input[i];
            var type:String = String(raw.兵种 != undefined ? raw.兵种 : raw.type);
            var level:Number = Number(raw.等级 != undefined ? raw.等级 : raw.level);

            if (type == "" || type == "undefined" || _root.兵种库[type] == undefined) {
                errors.push({code: "spawn_failed", side: side, unit: type, message: "unknown unit type"});
                continue;
            }
            if (isNaN(level) || level < 1) {
                errors.push({code: "invalid_case", side: side, unit: type, message: "invalid level"});
                continue;
            }

            var normalized:Object = {兵种: type, 等级: Math.floor(level)};
            var rawParams:Object = raw.Parameters != undefined ? raw.Parameters
                : (raw.parameters != undefined ? raw.parameters : raw.参数);
            if (rawParams != undefined) normalized.Parameters = ObjectUtil.clone(rawParams);
            out.push(normalized);
        }

        if (out.length == 0) {
            errors.push({code: "invalid_case", side: side, message: side + "Roster has no valid unit"});
        }
        return out;
    }

    private static function spawnSide(roster:Array, side:String, isEnemy:Boolean, x:Number, y:Number, runKey:String, formation:String, spacing:Number, errors:Array):Array {
        var out:Array = [];
        for (var i:Number = 0; i < roster.length; i++) {
            var unit:Object = roster[i];
            var attr:Object = _root.兵种库[unit.兵种];
            if (attr == undefined) {
                errors.push({code: "spawn_failed", side: side, unit: unit.兵种, message: "unit attr missing"});
                continue;
            }

            var init:Object = cloneObject(attr);
            init.兵种名 = null;
            init.等级 = unit.等级;
            if (unit.Parameters != undefined) ObjectUtil.cloneParameters(init, unit.Parameters);
            init.是否为敌人 = isEnemy;
            init.产生源 = "斗兽标定源";
            init.掉落物 = [];
            init.不掉钱 = true;
            init.计算经验值 = function():Void{
                this.已加经验值 = true;
            };
            init._arenaCalibrationUnit = true;
            var position:Object = resolveFormationPosition(formation, side, i, roster.length, x, y, spacing);
            init._x = position.x;
            init._y = position.y;
            init.名字 = "斗兽标定" + side + i;

            if (isEnemy) {
                _root.gameworld.斗兽标定源.僵尸型敌人场上实际人数++;
                _root.gameworld.斗兽标定源.僵尸型敌人总个数++;
            }

            var name:String = "斗兽标定_" + side + "_" + runKey + "_" + i;
            var mc:MovieClip = _root.加载游戏世界人物(attr.兵种名, name, _root.gameworld.getNextHighestDepth(), init);
            if (mc == undefined) {
                errors.push({code: "spawn_failed", side: side, unit: unit.兵种, message: "attachMovie failed"});
                if (isEnemy) {
                    _root.gameworld.斗兽标定源.僵尸型敌人场上实际人数--;
                    _root.gameworld.斗兽标定源.僵尸型敌人总个数--;
                }
            } else {
                mc.不掉钱 = true;
                mc.掉落物 = [];
                mc.计算经验值 = function():Void{
                    this.已加经验值 = true;
                };
                mc._arenaCalibrationUnit = true;
                mc._arenaCalibrationSide = side;
                mc._arenaCalibrationRun = runKey;
                mc.攻击目标 = "无";
                installCalibrationDeathHooks(mc);

                var estimatedMaxHp:Number = estimateStartMaxHp(init, unit.等级, isEnemy);
                var startMaxHp:Number = readUnitMaxHp(mc);
                out.push({
                    mc: mc,
                    startMaxHp: startMaxHp,
                    estimatedStartMaxHp: estimatedMaxHp,
                    startSnapshotReady: (startMaxHp > 0),
                    unitType: unit.兵种,
                    level: unit.等级,
                    side: side,
                    isEnemy: isEnemy,
                    spawnIndex: i,
                    spawnName: name,
                    spawnX: position.x,
                    spawnY: position.y,
                    deathObserved: false,
                    deathFrame: -1,
                    countReleased: false,
                    deadFinalized: false
                });
            }
        }
        return out;
    }

    private static function normalizeFormation(value):String {
        var formation:String = String(value || CALIBRATION_DEFAULT_FORMATION);
        if (formation == "column" || formation == "line" || formation == "wedge" || formation == "shield" || formation == "grid") {
            return formation;
        }
        return CALIBRATION_DEFAULT_FORMATION;
    }

    private static function resolveFormationSpacing(params:Object):Number {
        var spacing:Number = Number(params != undefined ? params.formationSpacing : undefined);
        if (isNaN(spacing) || spacing <= 0) spacing = CALIBRATION_DEFAULT_FORMATION_SPACING;
        return Math.round(clampNumber(spacing, CALIBRATION_MIN_FORMATION_SPACING, CALIBRATION_MAX_FORMATION_SPACING));
    }

    private static function resolveFormationPosition(formation:String, side:String, index:Number, total:Number, anchorX:Number, anchorY:Number, spacing:Number):Object {
        formation = normalizeFormation(formation);
        if (total < 1) total = 1;
        if (spacing <= 0 || isNaN(spacing)) spacing = CALIBRATION_DEFAULT_FORMATION_SPACING;

        var direction:Number = side == "blue" ? -1 : 1;
        var maxVertical:Number = Math.max(1, Math.floor((CALIBRATION_YMAX - CALIBRATION_YMIN) / spacing) + 1);
        if (maxVertical > total) maxVertical = total;
        var x:Number = anchorX;
        var y:Number = anchorY;

        if (formation == "column") {
            x = anchorX;
            y = resolveFormationY(anchorY, index, total, spacing);
        } else if (formation == "wedge") {
            var wedge:Object = resolveWedgeSlot(index, total, maxVertical);
            var wedgeStep:Number = resolveFormationDepthStep(side, anchorX, spacing, wedge.depthSlots);
            x = anchorX + direction * wedge.row * wedgeStep;
            y = resolveFormationY(anchorY, wedge.lane, wedge.laneCount, spacing);
        } else if (formation == "shield") {
            var frontCount:Number = Math.min(5, total);
            if (index < frontCount) {
                x = anchorX;
                y = resolveFormationY(anchorY, index, frontCount, spacing);
            } else {
                var shieldAnchorX:Number = anchorX + direction * resolveFormationDepthStep(side, anchorX, spacing, Math.ceil((total - frontCount) / maxVertical) + 1);
                var shieldPos:Object = resolveGridPosition(side, index - frontCount, total - frontCount, shieldAnchorX, anchorY, spacing, maxVertical);
                x = shieldPos.x;
                y = shieldPos.y;
            }
        } else if (formation == "grid") {
            var gridPos:Object = resolveGridPosition(side, index, total, anchorX, anchorY, spacing, maxVertical);
            x = gridPos.x;
            y = gridPos.y;
        } else {
            var lineStep:Number = resolveFormationDepthStep(side, anchorX, spacing, total);
            x = anchorX + direction * index * lineStep;
            y = anchorY;
        }

        return {
            x: clampNumber(Math.round(x), CALIBRATION_XMIN, CALIBRATION_XMAX),
            y: clampNumber(Math.round(y), CALIBRATION_YMIN, CALIBRATION_YMAX)
        };
    }

    private static function resolveGridPosition(side:String, index:Number, total:Number, anchorX:Number, anchorY:Number, spacing:Number, maxVertical:Number):Object {
        var verticalCount:Number = Math.ceil(Math.sqrt(total));
        if (verticalCount < 1) verticalCount = 1;
        if (verticalCount > maxVertical) verticalCount = maxVertical;

        var depth:Number = Math.floor(index / verticalCount);
        var lane:Number = index % verticalCount;
        var laneCount:Number = Math.min(verticalCount, total - depth * verticalCount);
        var depthSlots:Number = Math.ceil(total / verticalCount);
        var direction:Number = side == "blue" ? -1 : 1;
        var depthStep:Number = resolveFormationDepthStep(side, anchorX, spacing, depthSlots);
        return {
            x: anchorX + direction * depth * depthStep,
            y: resolveFormationY(anchorY, lane, laneCount, spacing)
        };
    }

    private static function resolveWedgeSlot(index:Number, total:Number, maxVertical:Number):Object {
        var consumed:Number = 0;
        var row:Number = 0;
        var rowSize:Number = 1;
        while (consumed + rowSize <= index && consumed + rowSize < total) {
            consumed += rowSize;
            row++;
            rowSize = Math.min(row + 1, maxVertical);
        }
        var laneCount:Number = Math.min(rowSize, total - consumed);
        return {
            row: row,
            lane: index - consumed,
            laneCount: laneCount,
            depthSlots: row + 1
        };
    }

    private static function resolveFormationY(anchorY:Number, lane:Number, laneCount:Number, spacing:Number):Number {
        if (laneCount <= 1) return clampNumber(anchorY, CALIBRATION_YMIN, CALIBRATION_YMAX);
        var step:Number = spacing;
        var maxStep:Number = (CALIBRATION_YMAX - CALIBRATION_YMIN) / (laneCount - 1);
        if (step > maxStep) step = maxStep;
        return clampNumber(anchorY + (lane - (laneCount - 1) * 0.5) * step, CALIBRATION_YMIN, CALIBRATION_YMAX);
    }

    private static function resolveFormationDepthStep(side:String, anchorX:Number, spacing:Number, depthSlots:Number):Number {
        if (depthSlots <= 1) return 0;
        var available:Number = side == "blue" ? (anchorX - CALIBRATION_XMIN) : (CALIBRATION_XMAX - anchorX);
        if (available < 0) available = 0;
        var maxStep:Number = available / (depthSlots - 1);
        if (maxStep <= 0) return 0;
        return Math.min(spacing, maxStep);
    }

    private static function captureStartSnapshots(units:Array, errors:Array, finalAttempt:Boolean):Boolean {
        var ready:Boolean = true;
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (record == undefined) continue;
            if (record.startSnapshotReady == true) continue;

            var unitMax:Number = readUnitMaxHp(record.mc);
            if (unitMax > 0) {
                record.startMaxHp = unitMax;
                record.startSnapshotReady = true;
                continue;
            }

            if (finalAttempt == true) {
                unitMax = Number(record.estimatedStartMaxHp);
                if (!isNaN(unitMax) && unitMax > 0) {
                    record.startMaxHp = unitMax;
                    record.startSnapshotReady = true;
                    if (record.startSnapshotWarned != true) {
                        errors.push({
                            code: "hp_snapshot_estimated",
                            side: record.side,
                            unit: record.unitType,
                            message: "used estimated max hp because runtime hp was not ready"
                        });
                        record.startSnapshotWarned = true;
                    }
                } else {
                    record.startMaxHp = 0;
                    record.startSnapshotReady = true;
                    if (record.startSnapshotWarned != true) {
                        errors.push({
                            code: "hp_snapshot_missing",
                            side: record.side,
                            unit: record.unitType,
                            message: "max hp snapshot is unavailable"
                        });
                        record.startSnapshotWarned = true;
                    }
                }
            } else {
                ready = false;
            }
        }
        return ready;
    }

    private static function primeTargets(blueUnits:Array, redUnits:Array):Void {
        var i:Number;
        for (i = 0; i < blueUnits.length; i++) {
            var blueMc:MovieClip = blueUnits[i].mc;
            if (blueMc != undefined && redUnits.length > 0) {
                var redTarget:MovieClip = redUnits[i % redUnits.length].mc;
                if (redTarget != undefined) blueMc.攻击目标 = redTarget._name;
            }
        }
        for (i = 0; i < redUnits.length; i++) {
            var redMc:MovieClip = redUnits[i].mc;
            if (redMc != undefined && blueUnits.length > 0) {
                var blueTarget:MovieClip = blueUnits[i % blueUnits.length].mc;
                if (blueTarget != undefined) redMc.攻击目标 = blueTarget._name;
            }
        }
    }

    private static function updateSpectatorCamera(force:Boolean):Void {
        if (_active == undefined) return;

        if (force != true && (_active.frames % SPECTATOR_CAMERA_INTERVAL) != 0) return;

        var gw:MovieClip = _root.gameworld;
        if (gw == undefined) return;
        var camera:MovieClip = gw.斗兽标定镜头;
        if (camera == undefined || camera._x == undefined) return;

        var hotspot:Object = resolveSpectatorHotspot(_active.blueUnits, _active.redUnits);
        if (hotspot == undefined) {
            hotspot = {x: CALIBRATION_CENTER_X, y: CALIBRATION_CENTER_Y};
        }

        var targetX:Number = clampNumber(Number(hotspot.x), CALIBRATION_XMIN, CALIBRATION_XMAX);
        var targetY:Number = clampNumber(Number(hotspot.y), CALIBRATION_YMIN, CALIBRATION_YMAX);
        if (force == true) {
            camera._x = targetX;
            camera._y = targetY;
        } else {
            camera._x = clampNumber(camera._x + (targetX - camera._x) / SPECTATOR_CAMERA_EASE, CALIBRATION_XMIN, CALIBRATION_XMAX);
            camera._y = clampNumber(camera._y + (targetY - camera._y) / SPECTATOR_CAMERA_EASE, CALIBRATION_YMIN, CALIBRATION_YMAX);
        }
        _active.lastHotspotX = targetX;
        _active.lastHotspotY = targetY;
    }

    private static function resolveSpectatorHotspot(blueUnits:Array, redUnits:Array):Object {
        var pair:Object = findEngagementPairHotspot(blueUnits, redUnits);
        if (pair != undefined) return pair;
        return calculateActiveCentroid(blueUnits, redUnits);
    }

    private static function findEngagementPairHotspot(blueUnits:Array, redUnits:Array):Object {
        var best:Object = undefined;
        var bestScore:Number = 999999999;
        var rangeSq:Number = SPECTATOR_CAMERA_PAIR_RANGE * SPECTATOR_CAMERA_PAIR_RANGE;

        for (var i:Number = 0; i < blueUnits.length; i++) {
            var blue:Object = blueUnits[i];
            if (isSpectatorRecordActive(blue) != true) continue;
            var blueMc:MovieClip = blue.mc;

            for (var j:Number = 0; j < redUnits.length; j++) {
                var red:Object = redUnits[j];
                if (isSpectatorRecordActive(red) != true) continue;
                var redMc:MovieClip = red.mc;
                var dx:Number = blueMc._x - redMc._x;
                var dy:Number = blueMc._y - redMc._y;
                var distSq:Number = dx * dx + dy * dy;
                var targeted:Boolean = isTargetingUnit(blueMc, redMc) || isTargetingUnit(redMc, blueMc);
                if (targeted != true && distSq > rangeSq) continue;

                var score:Number = targeted == true ? (distSq - rangeSq) : distSq;
                if (score < bestScore) {
                    bestScore = score;
                    best = {x: (blueMc._x + redMc._x) * 0.5, y: (blueMc._y + redMc._y) * 0.5};
                }
            }
        }
        return best;
    }

    private static function calculateActiveCentroid(blueUnits:Array, redUnits:Array):Object {
        var acc:Object = {x: 0, y: 0, count: 0};
        accumulateCameraCentroid(blueUnits, acc);
        accumulateCameraCentroid(redUnits, acc);
        if (acc.count <= 0) return undefined;
        return {x: acc.x / acc.count, y: acc.y / acc.count};
    }

    private static function accumulateCameraCentroid(units:Array, acc:Object):Void {
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (isSpectatorRecordActive(record) != true) continue;
            var mc:MovieClip = record.mc;
            acc.x += mc._x;
            acc.y += mc._y;
            acc.count++;
        }
    }

    private static function isSpectatorRecordActive(record:Object):Boolean {
        if (record == undefined) return false;
        var mc:MovieClip = record.mc;
        if (mc == undefined || mc._parent == undefined) return false;

        var hp:Number = Number(mc.hp);
        if (!isNaN(hp) && hp > 0) return true;
        return record.deathObserved == true && record.deadFinalized != true;
    }

    private static function isTargetingUnit(source:MovieClip, target:MovieClip):Boolean {
        if (source == undefined || target == undefined) return false;
        var targetName:String = String(source.攻击目标 || "");
        return targetName != "" && targetName != "无" && targetName == target._name;
    }

    private static function clampNumber(value:Number, min:Number, max:Number):Number {
        if (isNaN(value)) return min;
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    private static function installClock():Void {
        removeClock();
        var clip:MovieClip = _root.gameworld.createEmptyMovieClip("斗兽标定时钟", _root.gameworld.getNextHighestDepth());
        clip.onEnterFrame = function():Void {
            org.flashNight.arki.merc.ArenaCalibrationService.tick();
        };
        _active.clock = clip;
    }

    private static function installPhaseSpawnHook():Void {
        if (_loaderHookInstalled == true) return;
        if (typeof _root.加载游戏世界人物 != "function") return;
        _originalLoadGameWorldUnit = _root.加载游戏世界人物;
        _root.加载游戏世界人物 = function(id:String, name:String, depth:Number, initObject:Object):MovieClip {
            return org.flashNight.arki.merc.ArenaCalibrationService.loadGameWorldUnitThroughHook(id, name, depth, initObject);
        };
        _loaderHookInstalled = true;
    }

    private static function restorePhaseSpawnHook():Void {
        if (_loaderHookInstalled == true && _originalLoadGameWorldUnit != undefined) {
            _root.加载游戏世界人物 = _originalLoadGameWorldUnit;
        }
        _originalLoadGameWorldUnit = undefined;
        _loaderHookInstalled = false;
    }

    public static function loadGameWorldUnitThroughHook(id:String, name:String, depth:Number, initObject:Object):MovieClip {
        var original:Function = _originalLoadGameWorldUnit;
        if (typeof original != "function") return undefined;

        var mc:MovieClip = original(id, name, depth, initObject);
        handleSpawnedUnit(id, name, initObject, mc);
        return mc;
    }

    public static function handleSpawnedUnit(id:String, name:String, initObject:Object, mc:MovieClip):Void {
        if (_active == undefined || mc == undefined || mc._parent == undefined) return;
        if (mc._arenaCalibrationUnit === true) return;

        var parentRecord:Object = findPhaseSpawnParentRecord(String(name || mc._name), initObject);
        if (parentRecord == undefined) {
            mc._arenaCalibrationUnknown = true;
            if (_active.errors != undefined) {
                _active.errors.push({
                    code: "contamination_spawn",
                    unit: String(id),
                    name: String(mc._name || name),
                    message: "unknown unit spawned during arena calibration"
                });
            }
            return;
        }

        registerPhaseSpawnedUnit(parentRecord, String(id), String(name || mc._name), initObject, mc);
    }

    private static function findPhaseSpawnParentRecord(name:String, initObject:Object):Object {
        var best:Object = findPhaseSpawnParentRecordInSide(_active.blueUnits, name, initObject);
        if (best != undefined) return best;
        return findPhaseSpawnParentRecordInSide(_active.redUnits, name, initObject);
    }

    private static function findPhaseSpawnParentRecordInSide(units:Array, name:String, initObject:Object):Object {
        var best:Object = undefined;
        var bestDist:Number = 999999999;
        var spawnX:Number = Number(initObject != undefined ? initObject._x : undefined);
        var spawnY:Number = Number(initObject != undefined ? initObject._y : undefined);

        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (record == undefined) continue;
            var mc:MovieClip = record.mc;
            if (mc == undefined || mc._parent == undefined) continue;
            var parentName:String = String(mc._name || "");
            if (parentName != "" && name.indexOf(parentName) == 0) return record;

            if (record.deathObserved == true && !isNaN(spawnX) && !isNaN(spawnY)) {
                var dx:Number = Number(mc._x) - spawnX;
                var dy:Number = Number(mc._y) - spawnY;
                var dist:Number = dx * dx + dy * dy;
                if (dist < bestDist && dist < 40000) {
                    best = record;
                    bestDist = dist;
                }
            }
        }
        return best;
    }

    private static function registerPhaseSpawnedUnit(parentRecord:Object, unitType:String, name:String, initObject:Object, mc:MovieClip):Void {
        if (parentRecord == undefined || mc == undefined) return;
        markCalibrationUnit(mc, parentRecord.side, _active.runId);
        installCalibrationDeathHooks(mc);

        var level:Number = Number(initObject != undefined ? initObject.等级 : undefined);
        if (isNaN(level) || level < 1) level = Number(parentRecord.level);
        if (isNaN(level) || level < 1) level = 1;

        var attr:Object = _root.兵种库[unitType];
        var estimatedMaxHp:Number = estimateStartMaxHp(attr, level, parentRecord.isEnemy == true);
        var startMaxHp:Number = readUnitMaxHp(mc);
        if (isNaN(startMaxHp) || startMaxHp <= 0) startMaxHp = estimatedMaxHp;

        var record:Object = {
            mc: mc,
            startMaxHp: startMaxHp,
            estimatedStartMaxHp: estimatedMaxHp,
            startSnapshotReady: true,
            unitType: unitType,
            level: level,
            side: parentRecord.side,
            isEnemy: parentRecord.isEnemy,
            parentUnitType: parentRecord.unitType,
            phaseSpawned: true,
            deathObserved: false,
            deathFrame: -1,
            countReleased: true,
            deadFinalized: false
        };

        if (parentRecord.side == "blue") {
            _active.blueUnits.push(record);
        } else {
            _active.redUnits.push(record);
        }
        _active.phaseSpawnCount = Number(_active.phaseSpawnCount || 0) + 1;
        if (_active.spawnedUnits == undefined) _active.spawnedUnits = [];
        _active.spawnedUnits.push({
            side: parentRecord.side,
            unit: unitType,
            from: parentRecord.unitType,
            name: String(mc._name || name),
            frame: Number(_active.frames || 0)
        });
        primeTargets(_active.blueUnits, _active.redUnits);
    }

    private static function markCalibrationUnit(mc:MovieClip, side:String, runKey:String):Void {
        if (mc == undefined) return;
        mc.不掉钱 = true;
        mc.掉落物 = [];
        mc.计算经验值 = function():Void{
            this.已加经验值 = true;
        };
        mc._arenaCalibrationUnit = true;
        mc._arenaCalibrationSide = side;
        mc._arenaCalibrationRun = runKey;
        mc.产生源 = "斗兽标定源";
        if (mc.攻击目标 == undefined) mc.攻击目标 = "无";
    }

    private static function observeDeadUnits(units:Array):Void {
        for (var i:Number = 0; i < units.length; i++) {
            observeDeadUnit(units[i]);
        }
    }

    private static function installCalibrationDeathHooks(mc:MovieClip):Void {
        if (mc == undefined) return;

        if (mc._arenaCalibrationOriginalDeathCheck == undefined) {
            mc._arenaCalibrationOriginalDeathCheck = mc.死亡检测;
            mc.死亡检测 = function(para):Void {
                if (para == undefined) para = {};
                para.noCount = true;
                this.不掉钱 = true;
                this.掉落物 = [];
                this._arenaCalibrationDeathCheckCalled = true;
                if (typeof this._arenaCalibrationOriginalDeathCheck == "function") {
                    this._arenaCalibrationOriginalDeathCheck(para);
                }
            };
        }

        if (typeof mc.计算经验值 == "function") {
            mc.计算经验值 = function():Void {
                this.已加经验值 = true;
            };
        }
    }

    private static function observeDeadUnit(record:Object):Void {
        if (record == undefined || record.deadFinalized == true) return;

        var mc:MovieClip = record.mc;
        if (mc == undefined || mc._parent == undefined) {
            record.deadFinalized = true;
            return;
        }

        var unitHp:Number = Number(mc.hp);
        if (isNaN(unitHp) || unitHp > 0 || record.deathObserved == true) return;

        record.deathObserved = true;
        if (_active != undefined) record.deathFrame = _active.frames;
        mc.不掉钱 = true;
        mc.掉落物 = [];
        releaseDeathCount(record);
    }

    private static function releaseDeathCount(record:Object):Void {
        if (record == undefined || record.countReleased == true) return;
        record.countReleased = true;

        if (record.isEnemy == true && _root.gameworld.斗兽标定源 != undefined) {
            if (_root.gameworld.斗兽标定源.僵尸型敌人场上实际人数 > 0) {
                _root.gameworld.斗兽标定源.僵尸型敌人场上实际人数--;
            }
            if (_root.gameworld.斗兽标定源.僵尸型敌人总个数 > 0) {
                _root.gameworld.斗兽标定源.僵尸型敌人总个数--;
            }
        }
    }

    private static function hasPendingDeathEffects(units:Array):Boolean {
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (record == undefined || record.deadFinalized == true || record.deathObserved != true) continue;

            var mc:MovieClip = record.mc;
            if (mc != undefined && mc._parent != undefined) {
                if (mc._arenaCalibrationDeathCheckCalled === true) {
                    record.deadFinalized = true;
                    continue;
                }
                return true;
            }
            record.deadFinalized = true;
        }
        return false;
    }

    private static function finish(status:String, winner:String, errors:Array):Void {
        if (_active == undefined) return;

        var blue:Object = summarizeSide(_active.blueUnits);
        var red:Object = summarizeSide(_active.redUnits);
        var resp:Object = {
            task: "arena_calibration_response",
            callId: _active.callId,
            success: (status == "finished" || status == "timeout"),
            status: status,
            winner: winner,
            frames: _active.frames,
            durationMs: getTimer() - _active.startedMs,
            spawnDistance: _active.spawnDistance,
            blueFormation: _active.blueFormation,
            redFormation: _active.redFormation,
            formationSpacing: _active.formationSpacing,
            phaseSpawnCount: Number(_active.phaseSpawnCount || 0),
            spawnedUnits: _active.spawnedUnits != undefined ? _active.spawnedUnits : [],
            blueX: _active.blueX,
            redX: _active.redX,
            blueSpawnPositions: captureSpawnPositions(_active.blueUnits),
            redSpawnPositions: captureSpawnPositions(_active.redUnits),
            formationAudit: buildFormationAudit(_active.blueUnits, _active.redUnits),
            blue: blue,
            red: red,
            errors: errors
        };

        var blueUnits:Array = _active.blueUnits;
        var redUnits:Array = _active.redUnits;
        removeClock();
        restorePhaseSpawnHook();
        _active = undefined;
        cleanupUnits(blueUnits);
        cleanupUnits(redUnits);
        resetCalibrationSource();
        clearCalibrationGlobals();
        sendResponse(resp);
    }

    private static function countAlive(units:Array):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            var mc:MovieClip = undefined;
            if (record != undefined) mc = record.mc;
            if (mc != undefined && mc._parent != undefined && mc.hp > 0) count++;
        }
        return count;
    }

    private static function summarizeSide(units:Array):Object {
        var maxHp:Number = 0;
        var remainHp:Number = 0;
        var aliveCount:Number = 0;
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (record == undefined) continue;
            var unitMax:Number = Number(record.startMaxHp);
            var unitHp:Number = 0;
            var mc:MovieClip = record.mc;
            if (mc != undefined && mc._parent != undefined) {
                if (isNaN(unitMax) || unitMax <= 0) {
                    unitMax = readUnitMaxHp(mc);
                    if (unitMax > 0) record.startMaxHp = unitMax;
                }
                unitHp = Number(mc.hp);
                if (isNaN(unitHp) || unitHp < 0) unitHp = 0;
                if (unitHp > 0) aliveCount++;
            }
            if (isNaN(unitMax) || unitMax <= 0) unitMax = Number(record.estimatedStartMaxHp);
            if (isNaN(unitMax) || unitMax < 0) unitMax = 0;
            maxHp += unitMax;
            remainHp += unitHp;
        }
        return {
            maxHp: Math.round(maxHp),
            remainHp: Math.round(remainHp),
            aliveCount: aliveCount,
            startMaxHp: Math.round(maxHp),
            startCount: units.length
        };
    }

    private static function captureSpawnPositions(units:Array):Array {
        var out:Array = [];
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (record == undefined) continue;
            out.push({
                side: String(record.side || ""),
                index: Number(record.spawnIndex),
                unit: String(record.unitType || ""),
                level: Number(record.level),
                name: String(record.spawnName || ""),
                x: Math.round(Number(record.spawnX)),
                y: Math.round(Number(record.spawnY))
            });
        }
        return out;
    }

    private static function buildFormationAudit(blueUnits:Array, redUnits:Array):Object {
        return {
            blue: auditSpawnPositions(blueUnits),
            red: auditSpawnPositions(redUnits)
        };
    }

    private static function auditSpawnPositions(units:Array):Object {
        var count:Number = 0;
        var minX:Number = 999999999;
        var maxX:Number = -999999999;
        var minY:Number = 999999999;
        var maxY:Number = -999999999;
        var xs:Array = [];
        var ys:Array = [];
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            if (record == undefined) continue;
            var x:Number = Math.round(Number(record.spawnX));
            var y:Number = Math.round(Number(record.spawnY));
            if (isNaN(x) || isNaN(y)) continue;
            count++;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            pushUniqueNumber(xs, x);
            pushUniqueNumber(ys, y);
        }
        if (count == 0) {
            minX = 0;
            maxX = 0;
            minY = 0;
            maxY = 0;
        }
        return {
            count: count,
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            xRange: maxX - minX,
            yRange: maxY - minY,
            distinctX: xs.length,
            distinctY: ys.length
        };
    }

    private static function pushUniqueNumber(values:Array, value:Number):Void {
        for (var i:Number = 0; i < values.length; i++) {
            if (values[i] == value) return;
        }
        values.push(value);
    }

    private static function cleanupUnits(units:Array):Void {
        for (var i:Number = 0; i < units.length; i++) {
            var record:Object = units[i];
            var mc:MovieClip = undefined;
            if (record != undefined) mc = record.mc;
            if (mc != undefined && mc._parent != undefined) {
                mc.removeMovieClip();
            }
        }
    }

    private static function requestCalibrationStage(params:Object, errors:Array):Boolean {
        if (typeof _root.淡出动画.淡出跳转帧 != "function") {
            errors.push({code: "stage_failed", message: "fade transition entry is unavailable"});
            return false;
        }

        removeClock();
        resetCalibrationSource();
        _pendingRun = params;
        _transitionStarted = false;

        if (!ArenaController.prepareArenaStage(
                0,
                0,
                "",
                function(data:Object):Void {
                    org.flashNight.arki.merc.ArenaCalibrationService.handleStageDataReady();
                },
                function():Void {
                    org.flashNight.arki.merc.ArenaCalibrationService.handleStageDataFailed();
                })) {
            _pendingRun = undefined;
            errors.push({code: "stage_failed", message: "DEATH MATCH arena StageInfo is unavailable"});
            return false;
        }

        applyCalibrationTransitionGlobals();
        return true;
    }

    private static function applyCalibrationTransitionGlobals():Void {
        _root.斗兽标定模式 = true;
        _root.斗兽标定禁存档 = true;
        _root._agentCalibrationNoSave = true;
        _root.当前通关的关卡 = "";
        _root.当前关卡名 = CALIBRATION_STAGE_NAME;
        _root.关卡类型 = "斗兽标定";
        _root.无限过图模式 = false;
        _root.场景进入位置名 = "出生地";
        _root.角斗场对手类型 = "calibration";
        _root.角斗场roster阵容 = [];
        _root.押金 = 0;
        _root.角斗场奖金 = 0;
        _root.敌人同伴数 = 0;
        _root.敌人总数 = 0;

        if (_root.场景转换函数 != undefined && _root.帧计时器 != undefined) {
            _root.场景转换函数.上次切换帧数 = _root.帧计时器.当前帧数;
        }
        if (_root.soundEffectManager != undefined && _root.soundEffectManager.stopBGMForTransition != undefined) {
            _root.soundEffectManager.stopBGMForTransition();
        }
    }

    private static function prepareCalibrationStage(errors:Array):Boolean {
        if (typeof _root.加载共享场景 != "function") {
            errors.push({code: "stage_failed", message: "shared scene loader is unavailable"});
            return false;
        }
        if (_root.gameworld层级定位器 == undefined) {
            errors.push({code: "stage_failed", message: "gameworld depth anchor is unavailable"});
            return false;
        }

        removeClock();
        resetCalibrationSource();
        _root.斗兽标定模式 = true;
        _root.斗兽标定禁存档 = true;
        _root._agentCalibrationNoSave = true;
        _root.当前为战斗地图 = true;
        _root.当前关卡名 = CALIBRATION_STAGE_NAME;
        _root.关卡类型 = "斗兽标定";
        _root.关卡路径 = CALIBRATION_STAGE_LINKAGE;
        _root.无限过图模式 = false;
        _root.角斗场对手类型 = "calibration";
        _root.角斗场roster阵容 = [];
        _root.敌人同伴数 = 0;
        _root.敌人总数 = 0;

        var gw:MovieClip = _root.gameworld;
        if (gw == undefined || gw._arenaCalibrationStage !== true) {
            errors.push({
                code: "stage_failed",
                message: "calibration run requires an already prepared calibration arena stage; direct gameworld replacement is disabled"
            });
            clearCalibrationGlobals();
            return false;
        }

        configureCalibrationWorld(gw);
        var purged:Number = purgePlayerActors(errors, true);
        guardArenaContamination(errors, true, true);
        if (hasPlayerActors(gw)) {
            errors.push({code: "stage_failed", message: "player or companion actor remains in calibration arena"});
            clearCalibrationGlobals();
            return false;
        }
        return true;
    }

    private static function configureCalibrationWorld(gw:MovieClip):Void {
        _root.Xmin = CALIBRATION_XMIN;
        _root.Xmax = CALIBRATION_XMAX;
        _root.Ymin = CALIBRATION_YMIN;
        _root.Ymax = CALIBRATION_YMAX;
        _root.启用后景 = false;

        gw._arenaCalibrationStage = true;
        gw.场景名 = CALIBRATION_STAGE_LINKAGE;
        gw.背景长 = CALIBRATION_BG_WIDTH;
        gw.背景高 = CALIBRATION_BG_HEIGHT;
        gw.Xmin = CALIBRATION_XMIN;
        gw.Xmax = CALIBRATION_XMAX;
        gw.Ymin = CALIBRATION_YMIN;
        gw.Ymax = CALIBRATION_YMAX;
        gw.允许通行 = false;
        gw.关卡结束 = false;
        gw.佣兵已进场 = false;

        if (gw.deadbody == undefined) gw.createEmptyMovieClip("deadbody", -3);
        if (gw.出生地 == undefined) gw.createEmptyMovieClip("出生地", gw.getNextHighestDepth());
        gw.出生地._x = CALIBRATION_CENTER_X;
        gw.出生地._y = CALIBRATION_CENTER_Y;

        if (DepthManager.instance != undefined) {
            DepthManager.instance.calibrate(CALIBRATION_YMIN, CALIBRATION_YMAX);
        }
        SceneManager.getInstance().addBodyLayers(CALIBRATION_BG_WIDTH, CALIBRATION_BG_HEIGHT);

        var camera:MovieClip = gw.斗兽标定镜头;
        if (camera == undefined) camera = gw.createEmptyMovieClip("斗兽标定镜头", gw.getNextHighestDepth());
        camera._x = CALIBRATION_CENTER_X;
        camera._y = CALIBRATION_CENTER_Y;
        resetCalibrationSkybox();
        HorizontalScroller.onSceneChanged();
        HorizontalScroller.switchFollowTo(camera);

        _global.ASSetPropFlags(gw, ["_arenaCalibrationStage", "斗兽标定镜头", "出生地", "deadbody", "佣兵已进场"], 1, false);
    }

    private static function resetCalibrationSkybox():Void {
        if (_root.天空盒 == undefined) return;
        if (_root.天空盒.bgLayerList != undefined) {
            for (var i:Number = 0; i < _root.天空盒.bgLayerList.length; i++) {
                if (_root.天空盒.bgLayerList[i] != undefined) _root.天空盒.bgLayerList[i].removeMovieClip();
            }
        }
        _root.天空盒.bgLayerList = [];
        _root.天空盒.bgParallaxList = [];
        _root.天空盒.地平线高度 = 0;
        _root.天空盒._x = 0;
        if (_root.天空盒.默认天空 != undefined) _root.天空盒.默认天空._visible = false;
    }

    private static function purgePlayerActors(errors:Array, report:Boolean):Number {
        var gw:MovieClip = _root.gameworld;
        if (gw == undefined) return 0;

        var removed:Number = 0;
        var controlName:String = String(_root.控制目标 || "");
        if (controlName != "" && gw[controlName] != undefined) {
            gw[controlName].removeMovieClip();
            removed++;
        }

        var limit:Number = Number(_root.佣兵个数限制);
        if (isNaN(limit) || limit < 1) limit = 12;
        for (var i:Number = 0; i < limit; i++) {
            var companionName:String = "同伴" + i;
            if (gw[companionName] != undefined) {
                gw[companionName].removeMovieClip();
                removed++;
            }
        }

        for (var name:String in gw) {
            var child:MovieClip = gw[name];
            if (child == undefined || child._parent == undefined) continue;
            if (child._arenaCalibrationUnit === true) continue;
            if (child.是否为佣兵 === true || child.宠物属性 != undefined || child.宠物信息数组号 != undefined) {
                child.removeMovieClip();
                removed++;
            }
        }

        if (removed > 0 && report == true && errors != undefined) {
            errors.push({code: "player_actor_purged", message: "removed player, companion or pet actor from calibration arena"});
        }
        return removed;
    }

    private static function guardArenaContamination(errors:Array, report:Boolean, allowPurge:Boolean):Boolean {
        var gw:MovieClip = _root.gameworld;
        if (gw == undefined) return true;

        var removed:Number = 0;
        for (var name:String in gw) {
            var child:MovieClip = gw[name];
            if (child == undefined || child._parent == undefined) continue;
            if (isCalibrationUtilityActor(name, child)) continue;
            if (child._arenaCalibrationUnit === true) continue;
            if (isCombatActor(child) != true) continue;

            if (allowPurge == true) {
                child.removeMovieClip();
                removed++;
            } else {
                if (errors != undefined) {
                    errors.push({
                        code: "arena_contamination",
                        name: String(child._name || name),
                        message: "unknown combat actor remains in arena calibration stage"
                    });
                }
                return false;
            }
        }

        if (removed > 0 && report == true && errors != undefined) {
            errors.push({
                code: "arena_contamination_purged",
                count: removed,
                message: "removed stale combat actors before arena calibration run"
            });
        }
        return true;
    }

    private static function isCalibrationUtilityActor(name:String, child:MovieClip):Boolean {
        if (name == "斗兽标定时钟" || name == "斗兽标定镜头" || name == "出生地" || name == "deadbody") return true;
        if (child == _root.gameworld.斗兽标定镜头 || child == _root.gameworld.出生地 || child == _root.gameworld.deadbody) return true;
        return false;
    }

    private static function isCombatActor(child:MovieClip):Boolean {
        if (child == undefined || child._parent == undefined) return false;
        if (child._arenaCalibrationUnknown === true) return true;
        if (child.兵种 != undefined || child.兵种名 != undefined) return true;
        if (child.是否为敌人 != undefined && (child.hp != undefined || child.攻击目标 != undefined || child.死亡检测 != undefined)) return true;
        if (child.hp != undefined && child.死亡检测 != undefined) return true;
        return false;
    }

    private static function hasPlayerActors(gw:MovieClip):Boolean {
        if (gw == undefined) return false;
        var controlName:String = String(_root.控制目标 || "");
        if (controlName != "" && gw[controlName] != undefined) return true;

        var limit:Number = Number(_root.佣兵个数限制);
        if (isNaN(limit) || limit < 1) limit = 12;
        for (var i:Number = 0; i < limit; i++) {
            if (gw["同伴" + i] != undefined) return true;
        }

        for (var name:String in gw) {
            var child:MovieClip = gw[name];
            if (child == undefined || child._parent == undefined) continue;
            if (child._arenaCalibrationUnit === true) continue;
            if (child.是否为佣兵 === true || child.宠物属性 != undefined || child.宠物信息数组号 != undefined) return true;
        }
        return false;
    }

    private static function clearCalibrationGlobals():Void {
        _root.斗兽标定模式 = false;
        _root.斗兽标定禁存档 = false;
        _root._agentCalibrationNoSave = false;
        if (_root.角斗场对手类型 == "calibration") _root.角斗场对手类型 = undefined;
        if (_root.角斗场roster阵容 != undefined && _root.角斗场roster阵容.length == 0) _root.角斗场roster阵容 = undefined;
    }

    private static function removeClock():Void {
        if (_active != undefined && _active.clock != undefined) {
            _active.clock.onEnterFrame = null;
            _active.clock.removeMovieClip();
            _active.clock = undefined;
        } else if (_root.gameworld != undefined && _root.gameworld.斗兽标定时钟 != undefined) {
            _root.gameworld.斗兽标定时钟.onEnterFrame = null;
            _root.gameworld.斗兽标定时钟.removeMovieClip();
        }
    }

    private static function resolveOrigin(params:Object):Object {
        var centerX:Number = CALIBRATION_CENTER_X;
        var centerY:Number = CALIBRATION_CENTER_Y;
        if (_root.gameworld.出生地 != undefined) {
            if (!isNaN(Number(_root.gameworld.出生地._x))) centerX = Number(_root.gameworld.出生地._x);
            if (!isNaN(Number(_root.gameworld.出生地._y))) centerY = Number(_root.gameworld.出生地._y);
        }

        var defaultDistance:Number = CALIBRATION_DEFAULT_SPAWN_DISTANCE;
        var requestedDistance:Number = Number(params != undefined ? params.spawnDistance : undefined);
        if (isNaN(requestedDistance) || requestedDistance <= 0) {
            requestedDistance = defaultDistance;
        }

        var minX:Number = CALIBRATION_XMIN + CALIBRATION_SPAWN_EDGE_RESERVE;
        var maxX:Number = CALIBRATION_XMAX - CALIBRATION_SPAWN_EDGE_RESERVE;
        var maxDistance:Number = (maxX - minX);
        if (maxDistance < CALIBRATION_MIN_SPAWN_DISTANCE) maxDistance = defaultDistance;

        var distance:Number = clampNumber(Math.round(requestedDistance), CALIBRATION_MIN_SPAWN_DISTANCE, maxDistance);
        var half:Number = distance * 0.5;
        centerX = clampNumber(centerX, minX + half, maxX - half);

        var blueX:Number = centerX - half;
        var redX:Number = centerX + half;
        return {blueX: blueX, redX: redX, y: centerY, spawnDistance: Math.round(redX - blueX)};
    }

    private static function ensureCalibrationSource():Void {
        if (_root.gameworld.斗兽标定源 == undefined) _root.gameworld.斗兽标定源 = {};
        _root.gameworld.斗兽标定源.僵尸型敌人场上实际人数 = 0;
        _root.gameworld.斗兽标定源.僵尸型敌人总个数 = 0;
    }

    private static function resetCalibrationSource():Void {
        if (_root.gameworld != undefined && _root.gameworld.斗兽标定源 != undefined) {
            _root.gameworld.斗兽标定源.僵尸型敌人场上实际人数 = 0;
            _root.gameworld.斗兽标定源.僵尸型敌人总个数 = 0;
        }
    }

    private static function emptySideSummary():Object {
        return {maxHp: 0, remainHp: 0, aliveCount: 0, startMaxHp: 0, startCount: 0};
    }

    private static function readUnitMaxHp(mc:MovieClip):Number {
        var unitMax:Number = 0;
        if (mc != undefined && mc._parent != undefined) {
            unitMax = Number(mc.hp满血值);
            if (isNaN(unitMax) || unitMax <= 0) unitMax = Number(mc.hp);
        }
        if (isNaN(unitMax) || unitMax < 0) unitMax = 0;
        return unitMax;
    }

    private static function estimateStartMaxHp(attr:Object, level:Number, isEnemy:Boolean):Number {
        var unitMax:Number = 0;
        if (attr != undefined && typeof _root.根据等级计算值 == "function") {
            unitMax = Number(_root.根据等级计算值(attr.hp_min, attr.hp_max, level));
            var equipHp:Number = Number(attr.hp满血值装备加层);
            if (!isNaN(equipHp)) unitMax += equipHp;
            if (isEnemy) {
                var difficulty:Number = Number(_root.难度等级);
                if (isNaN(difficulty) || difficulty <= 0) difficulty = 1;
                unitMax *= difficulty;
            } else {
                unitMax *= 3;
            }
        }
        if (isNaN(unitMax) || unitMax < 0) unitMax = 0;
        return unitMax;
    }

    private static function cloneObject(src:Object):Object {
        if (typeof _root.duplicateOf == "function") return _root.duplicateOf(src);
        var out:Object = {};
        for (var key:String in src) out[key] = src[key];
        return out;
    }

    private static function sanitizeName(value:String):String {
        value = value.split("-").join("_");
        value = value.split(":").join("_");
        value = value.split(".").join("_");
        value = value.split("/").join("_");
        value = value.split("\\").join("_");
        return value;
    }

    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
    }
}
