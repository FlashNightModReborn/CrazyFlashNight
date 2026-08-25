import org.flashNight.gesh.object.ObjectUtil;

/**
 * GameStage 会话级计时池。
 *
 * 一个计时池可被多个不连续 SubStage 引用；离开引用它的地图时暂停，
 * 重新进入时继续消耗剩余帧。多个引用同时存在时独立扣时。
 * 本类只负责确定性状态与 UI 命令，不直接访问 _root 或裁决关卡结果。
 */
class org.flashNight.arki.scene.StageTimePoolController {
    private static var FRAMES_PER_SECOND:Number = 30;
    private static var MAX_POOL_COUNT:Number = 16;
    private static var MAX_ACTIVE_POOL_COUNT:Number = 4;
    private static var MAX_DURATION_SECONDS:Number = 3600;
    private static var MAX_ID_LENGTH:Number = 32;
    private static var MAX_LABEL_LENGTH:Number = 32;

    private var poolsById:Object;
    private var poolOrder:Array;
    private var stageRefs:Array;
    private var activeIds:Array;
    private var uiCommands:Array;
    private var enabled:Boolean;
    private var validationError:String;

    public function StageTimePoolController() {
        resetStorage();
    }

    /**
     * @param definitions  TimePools/TimePool 的单值或数组投影。
     * @param refsByStage  每个 SubStage 的 TimePoolRef 数组。
     */
    public function initialize(definitions, refsByStage:Array):Boolean {
        resetStorage();

        var rawDefinitions:Array = ObjectUtil.toArray(definitions);
        if (rawDefinitions.length > MAX_POOL_COUNT) {
            return reject("计时池数量超过上限 " + MAX_POOL_COUNT);
        }

        var i:Number;
        for (i = 0; i < rawDefinitions.length; i++) {
            var raw:Object = rawDefinitions[i];
            if (raw == null || typeof raw != "object") {
                return reject("TimePool[" + i + "] 不是对象");
            }

            if (raw.Id == null) {
                return reject("TimePool[" + i + "] 缺少 Id");
            }
            var id:String = String(raw.Id);
            if (!isValidId(id)) {
                return reject("TimePool[" + i + "] Id 非法: " + id);
            }
            if (poolsById[id] !== undefined) {
                return reject("TimePool Id 重复: " + id);
            }

            var durationSeconds:Number = Number(raw.DurationSeconds);
            if (isNaN(durationSeconds) || durationSeconds < 1
                    || durationSeconds > MAX_DURATION_SECONDS
                    || Math.floor(durationSeconds) != durationSeconds) {
                return reject("TimePool " + id + " DurationSeconds 非法");
            }

            var displayName:String = raw.DisplayName == null
                ? "" : String(raw.DisplayName);
            if (!isValidLabel(displayName)) {
                return reject("TimePool " + id + " DisplayName 非法");
            }

            if (raw.TimeoutResult == null) {
                return reject("TimePool " + id + " 缺少 TimeoutResult");
            }
            var timeoutResult:String = String(raw.TimeoutResult);
            if (timeoutResult != "FailStage") {
                return reject("TimePool " + id + " TimeoutResult 仅支持 FailStage");
            }

            var totalFrames:Number = durationSeconds * FRAMES_PER_SECOND;
            var pool:Object = {
                id:id,
                displayName:displayName,
                timeoutResult:timeoutResult,
                totalFrames:totalFrames,
                remainingFrames:totalFrames,
                expired:false,
                lastUiSeconds:-1
            };
            poolsById[id] = pool;
            poolOrder.push(id);
        }

        var referenced:Object = {};
        referenced.__proto__ = null;
        var rawStageRefs:Array = ObjectUtil.toArray(refsByStage);
        for (i = 0; i < rawStageRefs.length; i++) {
            var refs:Array = ObjectUtil.toArray(rawStageRefs[i]);
            if (refs.length > MAX_ACTIVE_POOL_COUNT) {
                return reject("SubStage[" + i + "] 同时引用的计时池超过上限 "
                    + MAX_ACTIVE_POOL_COUNT);
            }

            var normalized:Array = [];
            var seen:Object = {};
            seen.__proto__ = null;
            for (var j:Number = 0; j < refs.length; j++) {
                var refId:String = String(refs[j]);
                if (!isValidId(refId)) {
                    return reject("SubStage[" + i + "] TimePoolRef 非法: " + refId);
                }
                if (seen[refId] === true) {
                    return reject("SubStage[" + i + "] TimePoolRef 重复: " + refId);
                }
                if (poolsById[refId] === undefined) {
                    return reject("SubStage[" + i + "] 引用了未知计时池: " + refId);
                }
                seen[refId] = true;
                referenced[refId] = true;
                normalized.push(refId);
            }
            stageRefs[i] = normalized;
        }

        for (i = 0; i < poolOrder.length; i++) {
            var poolId:String = String(poolOrder[i]);
            if (referenced[poolId] !== true) {
                return reject("TimePool 未被任何 SubStage 引用: " + poolId);
            }
        }

        enabled = poolOrder.length > 0;
        return true;
    }

    /** 激活指定 SubStage 的计时池；重复池保留剩余帧。 */
    public function enterStage(stageIndex:Number):Void {
        leaveStage();
        if (!enabled) return;

        var refs:Array = ObjectUtil.toArray(stageRefs[stageIndex]);
        for (var i:Number = 0; i < refs.length; i++) {
            var id:String = String(refs[i]);
            var pool:Object = poolsById[id];
            if (pool !== undefined) {
                activeIds.push(id);
                queueSet(pool);
            }
        }
    }

    /** 离开当前 SubStage：暂停扣时并清除当前 HUD 行。 */
    public function leaveStage():Void {
        for (var i:Number = 0; i < activeIds.length; i++) {
            uiCommands.push({type:"clear", id:String(activeIds[i])});
        }
        activeIds = [];
    }

    /**
     * 推进一个有效游戏帧。暂停、对话或转场由调用者传 false。
     * @return 首个在本帧到期的池 ID；没有到期则返回 null。
     */
    public function tick(shouldAdvance:Boolean):String {
        if (!enabled || !shouldAdvance || activeIds.length == 0) return null;

        var firstExpired:String = null;
        for (var i:Number = 0; i < activeIds.length; i++) {
            var id:String = String(activeIds[i]);
            var pool:Object = poolsById[id];
            if (pool === undefined || pool.expired === true) continue;

            pool.remainingFrames--;
            if (pool.remainingFrames < 1) {
                pool.remainingFrames = 0;
                pool.expired = true;
                if (firstExpired == null) firstExpired = id;
            } else {
                var seconds:Number = Math.ceil(pool.remainingFrames / FRAMES_PER_SECOND);
                if (seconds != pool.lastUiSeconds) queueSet(pool);
            }
        }
        return firstExpired;
    }

    /** 结束整次 GameStage 会话并清掉所有计时 HUD。 */
    public function clear():Void {
        if (!enabled && activeIds.length == 0) return;
        if (poolOrder.length > 0) uiCommands.push({type:"clearAll"});
        activeIds = [];
        enabled = false;
    }

    /** 返回并清空待发送的 Host UI 命令。 */
    public function drainUiCommands():Array {
        var result:Array = uiCommands;
        uiCommands = [];
        return result;
    }

    public function getValidationError():String {
        return validationError;
    }

    public function isEnabled():Boolean {
        return enabled;
    }

    public function getPoolCount():Number {
        return poolOrder.length;
    }

    public function getActiveCount():Number {
        return activeIds.length;
    }

    public function getRemainingFrames(id:String):Number {
        var pool:Object = poolsById[id];
        return pool === undefined ? -1 : Number(pool.remainingFrames);
    }

    public function getRemainingSeconds(id:String):Number {
        var frames:Number = getRemainingFrames(id);
        return frames < 0 ? -1 : Math.ceil(frames / FRAMES_PER_SECOND);
    }

    private function queueSet(pool:Object):Void {
        var seconds:Number = Math.ceil(Number(pool.remainingFrames) / FRAMES_PER_SECOND);
        pool.lastUiSeconds = seconds;
        uiCommands.push({
            type:"set",
            id:String(pool.id),
            label:String(pool.displayName),
            remainingSeconds:seconds
        });
    }

    private function reject(message:String):Boolean {
        validationError = message;
        enabled = false;
        return false;
    }

    private function resetStorage():Void {
        poolsById = {};
        poolsById.__proto__ = null;
        poolOrder = [];
        stageRefs = [];
        activeIds = [];
        uiCommands = [];
        enabled = false;
        validationError = "";
    }

    private static function isValidId(value:String):Boolean {
        if (value == null || value.length < 1 || value.length > MAX_ID_LENGTH) return false;
        var first:Number = value.charCodeAt(0);
        if (first < 97 || first > 122) return false;
        for (var i:Number = 1; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            var valid:Boolean = (code > 96 && code < 123)
                || (code > 47 && code < 58) || code == 95 || code == 45;
            if (!valid) return false;
        }
        return true;
    }

    private static function isValidLabel(value:String):Boolean {
        if (value == null || value.length < 1 || value.length > MAX_LABEL_LENGTH) return false;
        if (value.charCodeAt(0) < 33 || value.charCodeAt(value.length - 1) < 33) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || code == 124) return false;
        }
        return true;
    }
}
