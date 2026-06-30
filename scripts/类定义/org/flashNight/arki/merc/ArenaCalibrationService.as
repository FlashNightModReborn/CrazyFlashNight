/**
 * 文件：org/flashNight/arki/merc/ArenaCalibrationService.as
 * 说明：竞技场斗兽标定的 AS2 端 runner。
 *
 * C# 下发：
 *   {task:"cmd", action:"arenaCalibrationRun", callId, batchId, caseId, caseHash,
 *    runId, repeatIndex, timeoutFrames, blueRoster:[{兵种,等级}], redRoster:[{兵种,等级}]}
 *
 * AS2 回包：
 *   {task:"arena_calibration_response", callId, success, status, winner, frames,
 *    durationMs, blue, red, errors}
 *
 * 本服务不走普通角斗场押金/奖金/FinishStage 链；只在当前 gameworld 中生成本轮蓝/红单位，
 * 监控存活/超时，结束后清理生成单位并回包。
 */
import LiteJSON;

class org.flashNight.arki.merc.ArenaCalibrationService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _active:Object = undefined;
    private static var _runSeq:Number = 0;

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["arenaCalibrationRun"] = function(params) {
            org.flashNight.arki.merc.ArenaCalibrationService.handleRun(params);
        };

        _inited = true;
    }

    public static function handleRun(params:Object):Void {
        if (params == undefined) params = {};
        var callId = params.callId;

        if (_active != undefined) {
            finish("aborted", "none", [{code: "aborted", message: "superseded by a new calibration run"}]);
        }

        if (!isRuntimeReady()) {
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
                errors: [{code: "stage_failed", message: "gameworld or unit loader is not ready"}]
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
            sendResponse(row);
            return;
        }

        primeTargets(blueUnits, redUnits);

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
            blueUnits: blueUnits,
            redUnits: redUnits,
            errors: errors
        };

        installClock();
    }

    public static function tick():Void {
        if (_active == undefined) return;
        _active.frames++;

        var blueAlive:Number = countAlive(_active.blueUnits);
        var redAlive:Number = countAlive(_active.redUnits);

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
        if (_active.frames >= _active.timeoutFrames) {
            finish("timeout", "timeout", _active.errors);
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

            out.push({兵种: type, 等级: Math.floor(level)});
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
            init.是否为敌人 = isEnemy;
            init.产生源 = "斗兽标定源";
            init.掉落物 = [];
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
                mc._arenaCalibrationSide = side;
                mc._arenaCalibrationRun = runKey;
                mc.攻击目标 = "无";
                out.push(mc);
            }
        }
        return out;
    }

    private static function primeTargets(blueUnits:Array, redUnits:Array):Void {
        var i:Number;
        for (i = 0; i < blueUnits.length; i++) {
            if (redUnits.length > 0) blueUnits[i].攻击目标 = redUnits[i % redUnits.length]._name;
        }
        for (i = 0; i < redUnits.length; i++) {
            if (blueUnits.length > 0) redUnits[i].攻击目标 = blueUnits[i % blueUnits.length]._name;
        }
    }

    private static function installClock():Void {
        removeClock();
        var clip:MovieClip = _root.gameworld.createEmptyMovieClip("斗兽标定时钟", _root.gameworld.getNextHighestDepth());
        clip.onEnterFrame = function():Void {
            org.flashNight.arki.merc.ArenaCalibrationService.tick();
        };
        _active.clock = clip;
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
        sendResponse(resp);
    }

    private static function countAlive(units:Array):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < units.length; i++) {
            var mc:MovieClip = units[i];
            if (mc != undefined && mc._parent != undefined && mc.hp > 0) count++;
        }
        return count;
    }

    private static function summarizeSide(units:Array):Object {
        var maxHp:Number = 0;
        var remainHp:Number = 0;
        var aliveCount:Number = 0;
        for (var i:Number = 0; i < units.length; i++) {
            var mc:MovieClip = units[i];
            if (mc == undefined || mc._parent == undefined) continue;
            var unitMax:Number = Number(mc.hp满血值);
            var unitHp:Number = Number(mc.hp);
            if (isNaN(unitMax) || unitMax < 0) unitMax = 0;
            if (isNaN(unitHp) || unitHp < 0) unitHp = 0;
            maxHp += unitMax;
            remainHp += unitHp;
            if (unitHp > 0) aliveCount++;
        }
        return {maxHp: Math.round(maxHp), remainHp: Math.round(remainHp), aliveCount: aliveCount};
    }

    private static function cleanupUnits(units:Array):Void {
        for (var i:Number = 0; i < units.length; i++) {
            var mc:MovieClip = units[i];
            if (mc != undefined && mc._parent != undefined) {
                mc.removeMovieClip();
            }
        }
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
        var centerX:Number = 760;
        var centerY:Number = 430;
        if (_root.gameworld.出生地 != undefined) {
            if (!isNaN(Number(_root.gameworld.出生地._x))) centerX = Number(_root.gameworld.出生地._x);
            if (!isNaN(Number(_root.gameworld.出生地._y))) centerY = Number(_root.gameworld.出生地._y);
        }
        return {blueX: centerX - 240, redX: centerX + 240, y: centerY};
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
        return {maxHp: 0, remainHp: 0, aliveCount: 0};
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
