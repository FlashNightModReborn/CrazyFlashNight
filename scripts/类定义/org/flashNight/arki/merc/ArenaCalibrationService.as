/**
 * 文件：org/flashNight/arki/merc/ArenaCalibrationService.as
 * 说明：竞技场斗兽标定的 AS2 端 runner。
 *
 * C# 下发：
 *   {task:"cmd", action:"arenaCalibrationRun", callId, batchId, caseId, caseHash,
 *    runId, repeatIndex, timeoutFrames, blueRoster:[{兵种,等级,Parameters}], redRoster:[{兵种,等级,Parameters}]}
 *   {task:"cmd", action:"arenaCalibrationAbort", callId, batchId, reason}
 *
 * AS2 回包：
 *   {task:"arena_calibration_response", callId, success, status, winner, frames,
 *    durationMs, blue, red, errors}
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
    private static var _runSeq:Number = 0;
    private static var SNAPSHOT_WARMUP_FRAMES:Number = 5;
    private static var CALIBRATION_STAGE_LINKAGE:String = "wuxianguotu_1";
    private static var CALIBRATION_STAGE_NAME:String = "斗兽标定竞技场";
    private static var CALIBRATION_CENTER_X:Number = 895;
    private static var CALIBRATION_CENTER_Y:Number = 430;
    private static var CALIBRATION_BLUE_X:Number = 655;
    private static var CALIBRATION_RED_X:Number = 1135;
    private static var CALIBRATION_XMIN:Number = 230;
    private static var CALIBRATION_XMAX:Number = 1560;
    private static var CALIBRATION_YMIN:Number = 242;
    private static var CALIBRATION_YMAX:Number = 620;
    private static var CALIBRATION_BG_WIDTH:Number = 1688;
    private static var CALIBRATION_BG_HEIGHT:Number = 640;
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
        var origin:Object = resolveOrigin();
        ensureCalibrationSource();

        var blueUnits:Array = spawnSide(blueRoster, "blue", false, origin.blueX, origin.y, runKey, errors);
        var redUnits:Array = spawnSide(redRoster, "red", true, origin.redX, origin.y, runKey, errors);

        if (blueUnits.length == 0 || redUnits.length == 0) {
            var row:Object = {
                task: "arena_calibration_response",
                callId: callId,
                success: false,
                status: "spawn_failed",
                winner: "none",
                frames: 0,
                durationMs: 0,
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
            lastHotspotX: CALIBRATION_CENTER_X,
            lastHotspotY: CALIBRATION_CENTER_Y
        };

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
        if (_root.gameworld层级定位器 == undefined) return false;
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

    private static function spawnSide(roster:Array, side:String, isEnemy:Boolean, x:Number, y:Number, runKey:String, errors:Array):Array {
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
            init._x = x + random(100) - 50;
            init._y = y + random(100) - 50;
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
                    deathObserved: false,
                    deathFrame: -1,
                    countReleased: false,
                    deadFinalized: false
                });
            }
        }
        return out;
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
            blue: blue,
            red: red,
            errors: errors
        };

        var blueUnits:Array = _active.blueUnits;
        var redUnits:Array = _active.redUnits;
        removeClock();
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

    private static function resolveOrigin():Object {
        var centerX:Number = CALIBRATION_CENTER_X;
        var centerY:Number = CALIBRATION_CENTER_Y;
        if (_root.gameworld.出生地 != undefined) {
            if (!isNaN(Number(_root.gameworld.出生地._x))) centerX = Number(_root.gameworld.出生地._x);
            if (!isNaN(Number(_root.gameworld.出生地._y))) centerY = Number(_root.gameworld.出生地._y);
        }
        return {blueX: CALIBRATION_BLUE_X, redX: CALIBRATION_RED_X, y: centerY};
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
