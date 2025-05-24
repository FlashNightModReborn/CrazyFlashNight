import org.flashNight.neur.Event.*;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * EffectSystem
 * 
 * 游戏中的特效管理系统，负责特效对象的创建、复用与销毁。
 * 包括普通效果与画面效果的管理，并提供初始化、发射与回收机制。
 */
class org.flashNight.arki.component.Effect.EffectSystem
{
    // ------------------------------
    // 静态属性：内部状态管理
    // ------------------------------

    /** 当前正在运行的普通特效数量 */
    private static var currentEffectCount:Number = 0;

    /** 普通特效数量上限 */
    public static var maxEffectCount:Number = 20;

    /** 当前正在运行的画面特效数量 */
    private static var currentScreenEffectCount:Number = 0;

    /** 画面特效的持续时间（毫秒） */
    private static var screenEffectDuration:Number = 1000;

    /** 画面特效数量上限 */
    public static var maxScreenEffectCount:Number = 20;

    /** 特效映射表（暂未使用，预留扩展） */
    private static var effectMapping:Object = {};

    /** 是否已初始化 */
    private static var initialized:Boolean = false;

    /** 随机数引擎（用于特效触发概率计算） */
    private static var RandomNumberEngine:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();


    public static var isDeathEffect:Boolean = true;

    // ------------------------------
    // 1. 初始化效果池
    // ------------------------------

    /**
     * 初始化特效池
     * 在场景切换或首次进入游戏时需要调用此方法。
     * 负责在 _root.gameworld 上创建并挂载 effectPools（用于存储可复用的特效对象）。
     */
    public static function initializeEffectPool():Void
    {
        var gameWorld:MovieClip = _root.gameworld;
        if (!gameWorld) return;

        gameWorld.effectPools = {};
        currentEffectCount = 0;
        currentScreenEffectCount = 0;

        // 设置 effectPools 为不可枚举，防止意外遍历和修改
        _global.ASSetPropFlags(gameWorld, ["effectPools"], 1, false);
        initialized = true;
    }

    // ------------------------------
    // 2. 发射特效（普通特效）
    // ------------------------------

    /**
     * 发射普通特效
     * @param effectType 特效类型（库链接名）
     * @param x 特效的 X 坐标
     * @param y 特效的 Y 坐标
     * @param scaleX 特效的横向缩放（方向控制）
     * @param forceTrigger 是否强制触发（无视触发条件）
     * @return 创建或复用的特效 MovieClip 对象
     */
    public static function Effect(effectType:String, x:Number, y:Number, scaleX:Number, forceTrigger:Boolean):MovieClip
    {
        if (!effectType) return null;

        // 判断是否满足触发条件（包括是否视觉元素、数量上限和触发概率）
        if (_root.是否视觉元素 && 
            (currentEffectCount <= EffectSystem.maxEffectCount || RandomNumberEngine.successRate(EffectSystem.maxEffectCount / 5)) || 
            forceTrigger
        ) {
            var gameWorld:MovieClip = _root.gameworld;
            // if (!gameWorld.effectPools) initializeEffectPool();

            var effectPool:Array = gameWorld.effectPools[effectType];
            var effect;

            // 优先从对象池中复用已有特效
            if (effectPool && effectPool.length > 0) {
                effect = effectPool.pop();
                effect._x = x;
                effect._y = y;
                effect._visible = true;
                effect.gotoAndPlay(1);
            } else {
                // 若池中无可用特效，则创建新特效
                effect = createEffect(effectType, x, y);
            }

            if (effect) {
                effect._x = x;
                effect._y = y;
                effect._xscale = scaleX;
                currentEffectCount++;
            }

            return effect;
        }

        return null;
    }

    // ------------------------------
    // 3. 发射画面效果
    // ------------------------------

    /**
     * 发射画面效果（不复用，直接 attach 到 _root）
     * @param effectType 特效类型（库链接名）
     * @param x 特效的 X 坐标
     * @param y 特效的 Y 坐标
     * @param scaleX 特效的横向缩放（方向控制）
     * @param forceTrigger 是否强制触发（无视触发条件）
     */
    public static function ScreenEffect(effectType:String, x:Number, y:Number, scaleX:Number, forceTrigger:Boolean):Void
    {
        if (!effectType) return;

        if (_root.是否视觉元素 && 
            (currentScreenEffectCount <= EffectSystem.maxScreenEffectCount || RandomNumberEngine.successRate(EffectSystem.maxScreenEffectCount / 5)) || 
            forceTrigger
        ) {
            var depth:Number = _root.getNextHighestDepth();
            var effectName:String = "screenEffect_" + depth;

            _root.attachMovie(effectType, effectName, depth);
            var effect:MovieClip = _root[effectName];
            effect._x = x;
            effect._y = y;
            effect._xscale = scaleX;

            currentScreenEffectCount++;

            // 定时销毁画面效果
            _root.帧计时器.添加单次任务(function():Void {
                currentScreenEffectCount--;
            }, screenEffectDuration);
        }
    }

    // ------------------------------
    // 4. 创建特效对象
    // ------------------------------

    /**
     * 创建新的特效 MovieClip 对象
     * @param effectType 特效类型（库链接名）
     * @param x 特效的 X 坐标
     * @param y 特效的 Y 坐标
     * @return 创建的特效对象
     */
    private static function createEffect(effectType:String, x:Number, y:Number):MovieClip
    {
        var gameWorld:MovieClip = _root.gameworld;
        var worldEffects:MovieClip = gameWorld.效果;
        var depth:Number = worldEffects.getNextHighestDepth();

        var effect:MovieClip = worldEffects.attachMovie(effectType, effectType + "_" + depth, depth);
        effect._x = x;
        effect._y = y;
        effect._visible = true;
        initializeEffectBehavior(effect);

        return effect;
    }

    // ------------------------------
    // 5. 初始化特效行为（回收机制）
    // ------------------------------

    /**
     * 初始化特效对象的行为逻辑
     * 覆盖 removeMovieClip，实现对象池回收机制
     * @param effect 特效 MovieClip 对象
     */
    private static function initializeEffectBehavior(effect:MovieClip):Void
    {
        effect.old_removeMovieClip = effect.removeMovieClip;

        effect.removeMovieClip = function(forceDestroy:Boolean):Void
        {
            EffectSystem.decrementEffectCount();

            if (!EffectSystem.isDeathEffect || forceDestroy) {
                this.old_removeMovieClip();
            } else {
                var effectPool:Array = _root.gameworld.effectPools[this.effectType];
                if (!effectPool) {
                    effectPool = _root.gameworld.effectPools[this.effectType] = [];
                }
                delete this.onEnterFrame;
                this.stop();
                this._visible = false;
                effectPool.push(this);
            }
        };

        effect.onUnload = function():Void {
            this.removeMovieClip(true);
        };
    }

    // ------------------------------
    // 6. 递减特效数量（防止溢出）
    // ------------------------------

    /**
     * 递减当前特效数量（防止特效数量溢出）
     */
    private static function decrementEffectCount():Void
    {
        if (currentEffectCount > 0) {
            currentEffectCount--;
        }
    }

    // ------------------------------
    // Getter 和 Setter 方法
    // ------------------------------

    public static function getCurrentEffectCount():Number { return currentEffectCount; }
    public static function getCurrentScreenEffectCount():Number { return currentScreenEffectCount; }
    public static function getScreenEffectDuration():Number { return screenEffectDuration; }
    public static function setScreenEffectDuration(duration:Number):Void { screenEffectDuration = duration; }
}
