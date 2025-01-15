import org.flashNight.neur.Event.EventBus;

class org.flashNight.arki.component.Effect.EffectSystem
{
    // ------------------------------
    // 静态属性：内部状态管理
    // ------------------------------
    private static var currentEffectCount:Number = 0;
    private static var currentScreenEffectCount:Number = 0;
    private static var screenEffectDuration:Number = 1000;

    private static var effectMapping:Object = {};
    private static var initialized:Boolean = false;

    // ------------------------------
    // 1. 初始化效果池
    // ------------------------------
    public static function initializeEffectPool():Void
    {
        var gameWorld:MovieClip = _root.gameworld;
        if (!gameWorld) return;

        gameWorld.effectPools = {};
        currentEffectCount = 0;

        _global.ASSetPropFlags(gameWorld, ["effectPools"], 1, true);
        initialized = true;
    }

    // ------------------------------
    // 2. 发射特效
    // ------------------------------
    public static function Effect(effectType:String, x:Number, y:Number, scaleX:Number, forceTrigger:Boolean):MovieClip
    {
        if (!effectType) return null;

        if (_root.是否视觉元素 && 
            (currentEffectCount <= _root.效果上限 || _root.成功率(_root.效果上限 / 5)) || 
            forceTrigger
        ) {
            var gameWorld:MovieClip = _root.gameworld;
            if (!gameWorld.effectPools) initializeEffectPool();

            var effectPool:Array = gameWorld.effectPools[effectType];
            var effect;

            if (effectPool && effectPool.length > 0) {
                effect = effectPool.pop();
                effect._x = x;
                effect._y = y;
                effect._visible = true;
                effect.gotoAndPlay(1);
            } else {
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
    public static function ScreenEffect(effectType:String, x:Number, y:Number, scaleX:Number, forceTrigger:Boolean):Void
    {
        if (!effectType) return;

        if (_root.是否视觉元素 && 
            (currentScreenEffectCount <= _root.画面效果上限 || _root.成功率(_root.画面效果上限 / 5)) || 
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

            // 使用帧计时器销毁效果
            _root.帧计时器.添加单次任务(function():Void {
                currentScreenEffectCount--;
            }, screenEffectDuration);
        }
    }

    // ------------------------------
    // 4. 内部方法：创建特效
    // ------------------------------
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
    // 5. 初始化特效行为
    // ------------------------------
    private static function initializeEffectBehavior(effect:MovieClip):Void
    {
        effect.old_removeMovieClip = effect.removeMovieClip;

        effect.removeMovieClip = function(forceDestroy:Boolean):Void
        {
            if (!_root.帧计时器.是否死亡特效 || forceDestroy) {
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
                EffectSystem.decrementEffectCount();
            }
        };

        effect.onUnload = function():Void {
            this.removeMovieClip(true);
        };
    }

    // ------------------------------
    // 6. 递减当前特效数量
    // ------------------------------
    private static function decrementEffectCount():Void
    {
        if (currentEffectCount > 0) {
            currentEffectCount--;
        }
    }

    // ------------------------------
    // Getter 和 Setter 方法
    // ------------------------------

    public static function getCurrentEffectCount():Number
    {
        return currentEffectCount;
    }

    public static function getCurrentScreenEffectCount():Number
    {
        return currentScreenEffectCount;
    }

    public static function getScreenEffectDuration():Number
    {
        return screenEffectDuration;
    }

    public static function setScreenEffectDuration(duration:Number):Void
    {
        screenEffectDuration = duration;
    }
}
