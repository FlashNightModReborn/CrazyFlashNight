import org.flashNight.arki.unit.Action.Input.LeeActionProfile;
import org.flashNight.arki.unit.Action.Input.UnitActionIntentService;
import org.flashNight.arki.unit.Action.Input.EnemyActionInputService;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/**
 * 怪物原生时间轴的共享动作入口。输入/AI只提出动作，伤害仍属于原资产。
 * 每个单位、每次动作都以普通 Object 身份隔离，旧 MovieClip 引用不能认领新实例。
 * 本类仅归 asLoader 所有；资源 SWF 必须通过 _root.敌人动作 调用。
 */
class org.flashNight.arki.unit.Action.Input.EnemyActionRuntime {
    private static var CHANNEL_ACTION:Number = 2;
    private static var KIND_ACTION:Number = 1;

    public static function installRootBridge(root:Object):Void {
        root.敌人动作 = {
            installLee: EnemyActionRuntime.installLee,
            currentToken: EnemyActionRuntime.currentToken,
            isCurrent: EnemyActionRuntime.isCurrent,
            ownsAI: EnemyActionRuntime.ownsAI,
            request: EnemyActionRuntime.request,
            finish: EnemyActionRuntime.finish,
            cancel: EnemyActionRuntime.cancel,
            abortToReady: EnemyActionRuntime.abortToReady,
            setOwnedFlag: EnemyActionRuntime.setOwnedFlag,
            resolveTarget: EnemyActionRuntime.resolveTarget,
            getParameter: EnemyActionRuntime.getParameter,
            handleDeath: EnemyActionRuntime.handleDeath,
            clearInput: EnemyActionRuntime.clearInput,
            releaseUnit: EnemyActionRuntime.releaseUnit,
            moveHop: EnemyActionRuntime.moveHop,
            moveTracking: EnemyActionRuntime.moveTracking,
            usesHitHop: EnemyActionRuntime.usesHitHop,
            moveHitHop: EnemyActionRuntime.moveHitHop,
            updateInput: EnemyActionInputService.updateControl
        };
    }

    public static function installLee(unit:Object):Boolean {
        if (unit.__enemyActionRuntime.enabled === true) return true;
        return install(unit, LeeActionProfile.create(unit.__enemyActionPlayer === true));
    }

    public static function install(unit:Object, profile:Object):Boolean {
        if (!unit || !profile || typeof unit.状态改变 != "function") return false;
        var existing:Object = unit.__enemyActionRuntime;
        if (existing && existing.enabled) return existing.profile.id == profile.id;
        var runtime:Object = {identity:{}, enabled:true, profile:profile, active:null,
            originalStateChange:unit.状态改变, inputPrevious:0, inputBlocked:true,
            cooldowns:{}, inputMask:0, hudRevision:0};
        // 同一试战的原生关卡时钟与截止帧跨场景保留；单位 token 仍逐实例创建。
        if (unit.__enemyActionPlayer === true && unit.__enemyActionCooldownSession != null) {
            runtime.cooldownSession = unit.__enemyActionCooldownSession;
            runtime.cooldowns = runtime.cooldownSession.deadlines;
        }
        for (var i:Number = 0; i < profile.inputs.length; i++) runtime.inputMask |= profile.inputs[i].bit;
        unit.__enemyActionRuntime = runtime;
        runtime.stateWrapper = function(nextState:String):Void {
            EnemyActionRuntime.changeState(this, nextState);
        };
        unit.状态改变 = runtime.stateWrapper;
        return true;
    }

    public static function ownsAI(unit:Object):Boolean {
        return unit.__enemyActionRuntime.enabled === true
            && unit.__enemyActionPlayer !== true && unit._name !== _root.控制目标;
    }

    public static function currentToken(unit:Object):Object {
        return unit.__enemyActionRuntime.active;
    }

    public static function isCurrent(unit:Object, token:Object):Boolean {
        var runtime:Object = unit.__enemyActionRuntime;
        return token != null && runtime != null && runtime.enabled === true
            && token.identity === runtime.identity && runtime.active === token
            && token.active === true && unit.hp > 0 && unit._parent != undefined;
    }

    public static function request(unit:Object, actionId:String, source:String, target:Object):Object {
        var runtime:Object = unit.__enemyActionRuntime;
        if (!runtime || !runtime.enabled || !(unit.hp > 0)
            || unit._parent == undefined || _root.暂停 || unit._warlordActionAiHeld === true
            || unit._封印冻结 === true || unit.倒地 || unit.浮空) return null;
        if (source == "ai") {
            if (!ownsAI(unit)) return null;
        } else if (source == "player") {
            if (unit._name !== _root.控制目标 || _root.控制目标全自动 === true) return null;
        } else return null;
        var action:Object = runtime.profile.actions[actionId];
        if (!action || !available(unit, actionId)) return null;
        var interrupt:Boolean = action.canInterrupt === true;
        if ((runtime.active != null || unit.硬直中) && !interrupt) return null;
        var state:String = unit.状态;
        var ready:Boolean = state == "空手站立" || state == "空手行走" || state == "空手跑";
        if (!ready && !(interrupt && (state == "近战" || state == "空手攻击" || state == "被击"
            || (unit.__enemyActionPlayer === true && state == "小跳")))) return null;
        var frame:Number = Number(_root.帧计时器.当前帧数);
        if (isNaN(frame)) frame = 0;
        var actionFrame:Number = cooldownFrame(runtime);
        if (Number(runtime.cooldowns[actionId]) > actionFrame) return null;
        if (!UnitActionIntentService.submit(unit, CHANNEL_ACTION, KIND_ACTION,
                frame, 0, {actionId:actionId, source:source}, 0)) return null;
        var intent:Object = UnitActionIntentService.take(unit, CHANNEL_ACTION,
            KIND_ACTION, frame, false);
        if (intent == null) return null;
        if (!isValidTarget(unit, target)) target = _root.gameworld[unit.攻击目标];
        if (!isValidTarget(unit, target)) target = null;
        if (target && target.__enemyActionTargetIdentity == undefined) {
            target.__enemyActionTargetIdentity = {};
        }
        // Admission is complete before cancelling the previous action. A rejected
        // ability must not steal an attack or consume cooldown.
        if (runtime.active != null) cancel(unit, runtime.active, "abilityInterrupt");
        if (interrupt && unit.stiffID != null) {
            EnhancedCooldownWheel.I().removeTask(unit.stiffID);
            unit.stiffID = null;
        }
        if (interrupt) unit.硬直中 = false;
        var token:Object = {identity:runtime.identity, active:true, actionId:actionId,
            source:source, action:action, target:target,
            targetIdentity:target.__enemyActionTargetIdentity, ownedFlags:{}, startedAt:actionFrame};
        if (actionId == "hop") {
            token.hopX = unit.左行 ? -1 : unit.右行 ? 1 : 0;
            token.hopZ = unit.上行 ? -1 : unit.下行 ? 1 : 0;
            if (token.hopX == 0 && token.hopZ == 0) token.hopX = unit.方向 == "左" ? 1 : -1;
        }
        runtime.active = token;
        runtime.cooldowns[actionId] = actionFrame + Number(action.cooldownFrames || 0);
        unit.近战招式 = action.label;
        // 所有准入与冷却先提交；同为“近战”的换招也必须离开旧帧，重建真实动作容器。
        // 旧容器 unload 只携带旧 token，不能撤销这个新动作。
        if (unit.__enemyActionPlayer === true && unit.状态 == action.state)
            runtime.originalStateChange.call(unit, "空手站立");
        if (source == "player" && action.allowFacingInput === true) {
            if (unit.右行) unit.方向改变("右");
            else if (unit.左行) unit.方向改变("左");
        }
        runtime.originalStateChange.call(unit, action.state);
        return token;
    }

    /** 接住仍由共用怪物 AI 发起的标签切换，也在受击/死亡跳帧前取消旧动作。 */
    public static function changeState(unit:Object, nextState:String):Void {
        var runtime:Object = unit.__enemyActionRuntime;
        if (!runtime || !runtime.enabled) return;
        var fallback:String = runtime.profile.stateFallbacks[nextState];
        if (fallback != undefined) nextState = fallback;
        if (nextState == "近战" || nextState == "空手攻击") {
            var actionId:String = "basic";
            if (nextState == "近战") {
                var label:String = unit.近战招式;
                if (label == "a1" || label == "a2") actionId = label;
                else if (label == "冲腿") actionId = "rush";
                else if (label == "强力冲腿") actionId = "strongRush";
                else return;
            }
            request(unit, actionId, "ai", null);
            return;
        }
        if (runtime.active != null) cancel(unit, runtime.active, "stateChange");
        runtime.originalStateChange.call(unit, nextState);
    }

    public static function finish(unit:Object, token:Object):Void {
        cancel(unit, token, "complete");
    }

    public static function cancel(unit:Object, token:Object, reason:String):Void {
        var runtime:Object = unit.__enemyActionRuntime;
        if (!token || !runtime || token.identity !== runtime.identity
            || runtime.active !== token || token.active !== true) return;
        // 先撤销资格，再还原只属于本动作、且未被其他写者覆盖的字段。
        token.active = false;
        token.reason = reason;
        runtime.active = null;
        for (var key:String in token.ownedFlags) {
            var owned:Object = token.ownedFlags[key];
            if (unit[key] === owned.value) {
                if (owned.present) unit[key] = owned.previous;
                else delete unit[key];
            }
        }
        UnitActionIntentService.cancelKind(unit, CHANNEL_ACTION, KIND_ACTION);
        token.target = null;
    }

    /** 控制权丢失的专用收口；普通取消仍不跳帧，避免 unload/stateChange 重入。 */
    public static function abortToReady(unit:Object, token:Object, reason:String):Void {
        var runtime:Object = unit.__enemyActionRuntime;
        if (!token || !runtime || token.identity !== runtime.identity
            || runtime.active !== token || token.active !== true) return;
        var actionState:String = token.action.state;
        var originalStateChange:Function = runtime.originalStateChange;
        clearInput(unit);
        cancel(unit, token, reason);
        // 仅活体仍处本动作的容器时回待机；受击/死亡等外部状态绝不能被覆盖。
        if (unit.hp > 0 && unit.__enemyActionRuntime === runtime
            && unit.状态 == actionState) originalStateChange.call(unit, "空手站立");
    }

    public static function setOwnedFlag(unit:Object, token:Object, key:String, value):Void {
        if (!isCurrent(unit, token) || (key != "刚体" && key != "锁定方向")) return;
        // 只略过玩家可转向招式自己要求的锁向；不改外部锁向或 AI。
        if (key == "锁定方向" && unit.__enemyActionPlayer === true && token.action.allowFacingInput === true) return;
        var owned:Object = token.ownedFlags[key];
        if (!owned) {
            owned = {present:unit[key] != undefined, previous:unit[key], value:value};
            token.ownedFlags[key] = owned;
        }
        owned.value = value;
        unit[key] = value;
    }

    public static function resolveTarget(unit:Object, token:Object):Object {
        if (!isCurrent(unit, token)) return null;
        var target:Object = token.target;
        if (!isValidTarget(unit, target)
            || target.__enemyActionTargetIdentity !== token.targetIdentity) return null;
        return target;
    }

    public static function getParameter(unit:Object, token:Object, key:String):Number {
        return isCurrent(unit, token) ? Number(token.action[key]) : NaN;
    }

    private static function isValidTarget(unit:Object, target:Object):Boolean {
        return target != null && target !== unit && target.hp > 0
            && target._parent === unit._parent && !isNaN(Number(target._x))
            && !isNaN(Number(target.Z轴坐标)) && target.是否为敌人 !== unit.是否为敌人;
    }

    /** 只认本帧已裁决的移动方向；原地按住奔跑键不算跑动攻击。 */
    public static function isRunning(unit:Object):Boolean {
        return (unit.左行 || unit.右行 || unit.上行 || unit.下行)
            && (unit.强制奔跑 === true || unit.状态 == "空手跑");
    }

    private static function cooldownFrame(runtime:Object):Number {
        // activeFrames 只由未暂停的 StageManager 游戏帧推进；ServerManager 的通信帧在暂停中仍会走。
        var frame:Number = Number(runtime.cooldownSession == null
            ? _root.帧计时器.当前帧数 : runtime.cooldownSession.clock.activeFrames);
        return isNaN(frame) ? 0 : frame;
    }

    public static function available(unit:Object, actionId:String):Boolean {
        var action:Object = unit.__enemyActionRuntime.profile.actions[actionId];
        return action != null && (action.promotion == undefined || unit.宠物属性[action.promotion] === true);
    }

    /** Called only by the native hop's active movement frames. */
    public static function moveHop(unit:Object, token:Object):Void {
        if (!isCurrent(unit, token) || token.actionId != "hop") return;
        if (token.hopX != 0) unit.移动(token.hopX < 0 ? "左" : "右", token.hopZ != 0 ? 14.1421356 : 20);
        if (token.hopZ != 0) unit.移动(token.hopZ < 0 ? "上" : "下", token.hopX != 0 ? 14.1421356 : 20);
    }

    /** 强力冲腿的玩家追身段按当前朝向位移；旧动作和 AI 不能借此移动。 */
    public static function moveTracking(unit:Object, token:Object, speed:Number):Void {
        if (!isCurrent(unit, token) || unit.__enemyActionPlayer !== true
                || token.actionId != "strongRush" || !(speed > 0) || !isFinite(speed)) return;
        unit.移动(unit.方向, speed);
    }

    /** AI 保留原生反射；玩家仅龙息进阶后恢复，与主动小跳的冷却完全独立。 */
    public static function usesHitHop(unit:Object):Boolean {
        return unit.__enemyActionPlayer !== true || unit.宠物属性.冲腿龙息 === true;
    }

    public static function moveHitHop(unit:Object, direction:String):Void {
        if (unit.hp > 0 && unit.状态 == "被击" && usesHitHop(unit) && !_root.暂停) unit.移动(direction, 20);
    }

    /** Fixed native abilities are projected without writing the main-character skill table. */
    public static function hudDescriptors(unit:Object):Object {
        var runtime:Object = unit.__enemyActionRuntime;
        var signature:String = "";
        var keys:Array = [];
        for (var i:Number = 1; i <= 12; i++) {
            var key:String = String(_root.keyshow(_root["快捷技能栏键" + i]) || "");
            keys.push(key);
            signature += ";" + key;
        }
        signature += ";" + String(unit.宠物属性.冲腿龙息 === true);
        if (runtime.hud != null && runtime.hudSignature === signature) return runtime.hud;
        var slots:Array = [];
        for (i = 0; i < 12; i++) {
            var actionId:String = runtime.profile.quickSlots[i];
            var action:Object = runtime.profile.actions[actionId];
            var equipped:Boolean = action != null && available(unit, actionId);
            slots.push({slot:i+1, equipped:equipped, skillKey:action == null ? null : action.name,
                keyLabel:keys[i], stateHealth:"ok", writeBlocked:true, level:equipped ? 1 : 0,
                iconKey:action == null ? null : action.icon, mp:0,
                cooldownMs:action == null ? 0 : Number(action.cooldownFrames || 0) * 1000 / 30});
        }
        runtime.hudSignature = signature;
        runtime.hud = {revision:++runtime.hudRevision, slots:slots};
        return runtime.hud;
    }

    public static function hudAction(unit:Object, slot:Number):Object {
        return unit.__enemyActionRuntime.profile.actions[unit.__enemyActionRuntime.profile.quickSlots[slot-1]];
    }

    public static function hudCooldowns(unit:Object):Array {
        var runtime:Object = unit.__enemyActionRuntime;
        var result:Array = [[1,0,0]];
        var frame:Number = cooldownFrame(runtime);
        for (var i:Number = 0; i < 12; i++) {
            var actionId:String = runtime.profile.quickSlots[i];
            var action:Object = runtime.profile.actions[actionId];
            var total:Number = Number(action.cooldownFrames || 0);
            var remaining:Number = Math.max(0, Number(runtime.cooldowns[actionId] || 0) - frame);
            if (remaining > 0) result.push([0, total - remaining, total]);
            else if (runtime.active != null && runtime.active.actionId == actionId) {
                total = Number(action.animationFrames || 1);
                result.push([0, Math.min(total, Math.max(0, frame-runtime.active.startedAt)), total]);
            } else result.push([1,0,0]);
        }
        for (i = 0; i < 5; i++) result.push([1,0,0]);
        return result;
    }

    public static function clearInput(unit:Object):Void {
        if (!unit) return;
        unit.左行 = unit.右行 = unit.上行 = unit.下行 = false;
        unit.动作A = unit.动作B = unit.动作C = unit.强制奔跑 = false;
        unit.commandId = unit.当前搓招ID = unit.搓招缓冲ID = 0;
        unit.当前搓招名 = unit.搓招缓冲名 = "";
        unit.搓招缓冲已消费 = true;
        unit.doubleTapRunDirection = 0;
        UnitActionIntentService.clearAll(unit);
        var runtime:Object = unit.__enemyActionRuntime;
        if (runtime) {
            runtime.inputPrevious = 0;
            runtime.inputBlocked = true;
        }
    }

    public static function handleDeath(unit:Object):Boolean {
        // 通用死亡检测也会逐帧访问活体；非托管单位及未确认死亡必须零副作用。
        if (!unit || (unit.__enemyActionRuntime.enabled !== true
            && typeof unit.__enemyActionOnDeath != "function")) return false;
        var hp:Number = Number(unit.hp);
        if (isNaN(hp) || hp > 0) return false;
        clearInput(unit);
        cancel(unit, currentToken(unit), "death");
        if (typeof unit.__enemyActionOnDeath == "function") {
            return unit.__enemyActionOnDeath(unit) === true;
        }
        return false;
    }

    public static function releaseUnit(unit:Object, reason:String):Void {
        var runtime:Object = unit.__enemyActionRuntime;
        if (!runtime) return;
        clearInput(unit);
        cancel(unit, runtime.active, reason);
        runtime.enabled = false;
        if (unit.状态改变 === runtime.stateWrapper) unit.状态改变 = runtime.originalStateChange;
        delete unit.__enemyActionRuntime;
    }
}