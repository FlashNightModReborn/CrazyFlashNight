// 文件路径：org/flashNight/arki/unit/Action/Skill/ManualCooldownService.as

/**
 * @class ManualCooldownService
 * @description 玩家手动技能、战技与药剂的共享冷却权威。
 *
 * 逻辑状态只保存在本类；玩家信息 XFL 中的旧进度条降级为可缺失、可重绑的投影。
 * 调度继续使用 CooldownWheel 的逐帧任务，因此保持暂停期间推进与跨场景存活语义。
 */
class org.flashNight.arki.unit.Action.Skill.ManualCooldownService {

    public static var FRAME_MS:Number = 33.33333;
    public static var WEAPON_SKILL_KEY:String = "weapon:shared";

    private static var states:Object = {};
    private static var renderers:Object = {};
    private static var schedulerForTests:Function = null;
    private static var nextGeneration:Number = 1;

    public static function quickSkillKey(slotIndex:Number):String {
        return "quick:" + slotIndex;
    }

    public static function drugKey(slotIndex:Number):String {
        return "drug:" + slotIndex;
    }

    public static function isReady(key:String):Boolean {
        return getState(key).ready === true;
    }

    /**
     * 冷却开始后至少等待一个 CooldownWheel tick；重复 start 被权威层拒绝。
     */
    public static function start(key:String, durationMs:Number):Boolean {
        if (!isValidKey(key)) return false;

        var state:Object = getState(key);
        if (state.ready !== true) return false;

        var totalSteps:Number = Math.ceil(Number(durationMs) / FRAME_MS);
        if (isNaN(totalSteps) || totalSteps < 1) totalSteps = 1;

        state.ready = false;
        state.totalSteps = totalSteps;
        state.currentStep = 0;
        state.generation = nextGeneration++;
        syncRenderer(key, state);
        scheduleNext(key, state.generation);
        return true;
    }

    /**
     * 绑定/重绑旧 XFL 进度条。绑定只影响投影，不参与 isReady/start 判定。
     */
    public static function bindRenderer(key:String, renderer:Object):Boolean {
        if (!isValidKey(key) || !renderer) return false;

        if (renderers[key] !== renderer) {
            renderers[key] = renderer;
            renderer.__manualCooldownKey = key;
            if (!renderer.__manualCooldownAuthorityStarter) {
                renderer.__manualCooldownAuthorityStarter = function(durationMs:Number):Boolean {
                    return ManualCooldownService.start(String(this.__manualCooldownKey), durationMs);
                };
            }
        }
        renderer.__manualCooldownKey = key;
        if (renderer.冷却开始 !== renderer.__manualCooldownAuthorityStarter) {
            renderer.冷却开始 = renderer.__manualCooldownAuthorityStarter;
        }
        syncRenderer(key, getState(key));
        return true;
    }

    public static function unbindRenderer(key:String, renderer:Object):Void {
        if (renderers[key] === renderer) delete renderers[key];
    }

    public static function getSnapshot(key:String):Object {
        var state:Object = getState(key);
        return {
            key: key,
            ready: state.ready === true,
            totalSteps: state.totalSteps,
            currentStep: state.currentStep,
            progressPercent: getProgressPercent(state),
            animationFrame: getAnimationFrame(state)
        };
    }

    /** 测试夹具注入：生产代码不得调用。 */
    public static function setSchedulerForTests(scheduler:Function):Void {
        schedulerForTests = scheduler;
    }

    /** 测试夹具复位：生产代码不得调用。 */
    public static function resetForTests():Void {
        states = {};
        renderers = {};
        schedulerForTests = null;
        nextGeneration = 1;
    }

    private static function getState(key:String):Object {
        var state:Object = states[key];
        if (!state) {
            state = {ready: true, totalSteps: 0, currentStep: 0, generation: 0};
            states[key] = state;
        }
        return state;
    }

    private static function scheduleNext(key:String, generation:Number):Void {
        var callback:Function = function():Void {
            ManualCooldownService.advance(key, generation);
        };

        if (schedulerForTests != null) {
            schedulerForTests(callback);
            return;
        }

        var timer:Object = _root.帧计时器;
        if (timer && timer.添加冷却任务) {
            timer.添加冷却任务(1, callback);
            return;
        }

        // 启动顺序异常时宁可保持不可用，也不能把无计时的冷却误判为已结束。
        trace("[ManualCooldownService] 缺少帧计时器，冷却保持锁定: " + key);
    }

    public static function advance(key:String, generation:Number):Void {
        var state:Object = states[key];
        if (!state || state.ready === true || state.generation !== generation) return;

        state.currentStep++;
        if (state.currentStep >= state.totalSteps) {
            state.ready = true;
            state.currentStep = 0;
            syncRenderer(key, state);
            return;
        }

        syncRenderer(key, state);
        scheduleNext(key, generation);
    }

    private static function syncRenderer(key:String, state:Object):Void {
        var renderer:Object = renderers[key];
        if (!renderer) return;

        var projectionSignature:String = String(state.ready) + ":" + state.totalSteps + ":"
            + state.currentStep + ":" + state.generation;
        if (renderer.__manualCooldownProjectionSignature == projectionSignature) return;
        renderer.__manualCooldownProjectionSignature = projectionSignature;

        var progressPercent:Number = getProgressPercent(state);
        var animationFrame:Number = getAnimationFrame(state);
        renderer.冷却 = state.ready === true;
        renderer.总步数 = state.totalSteps;
        renderer.当前进度 = state.currentStep;
        renderer.__manualCooldownProgressPercent = progressPercent;

        if (renderer.应用冷却投影) {
            renderer.应用冷却投影(
                state.ready === true,
                state.totalSteps,
                state.currentStep,
                animationFrame
            );
        } else if (renderer.动画 && renderer.动画.gotoAndStop) {
            renderer.动画.gotoAndStop(animationFrame);
        }
    }

    private static function getProgressPercent(state:Object):Number {
        if (!state || state.ready === true || state.totalSteps <= 0) return 0;
        return Math.round(state.currentStep / state.totalSteps * 100);
    }

    private static function getAnimationFrame(state:Object):Number {
        if (!state || state.ready === true) return 1;
        return 1 + getProgressPercent(state);
    }

    private static function isValidKey(key:String):Boolean {
        return key != null && key != "" && key != "undefined";
    }
}
