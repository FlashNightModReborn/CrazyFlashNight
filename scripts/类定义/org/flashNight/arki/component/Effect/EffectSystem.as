import org.flashNight.sara.util.ObjectPool;
import org.flashNight.naki.DataStructures.Dictionary;
import org.flashNight.neur.Event.Delegate;

class org.flashNight.arki.component.Effect.EffectSystem
{
    // 是否初始化过
    private static var _initialized:Boolean = false;

    // 当前可见特效数量 & 上限
    private static var _currentEffectCount:Number = 0;
    private static var _maxEffectCount:Number = 80; 

    // 当前画面效果数量 & 上限
    private static var _currentScreenEffectCount:Number = 0;
    private static var _maxScreenEffectCount:Number = 20;

    // 画面效果存活时间
    private static var _screenEffectLifetime:Number = 1000;

    /**
     * ==============================
     *  1) 对外公开方法：重新初始化
     * ==============================
     * 与原脚本的 _root.效果系统.初始化效果池() 类似。
     * 当场景 / gameworld 重建后，需要调用此方法，
     * 以在新的 gameworld 中重新挂载可用的特效池。
     */
    public static function reinitializeEffectSystem():Void
    {
        // 重置特效计数
        _currentEffectCount = 0;
        _currentScreenEffectCount = 0;
        _initialized = false;

        // 如果新的 gameworld 尚未创建好，则先不做后续操作
        if (!_root.gameworld) {
            return;
        }

        // 在新的 gameworld 上挂载 "availableEffectPools" 字段，用于储存对象池映射
        // 避免之前场景卸载造成的对象池遗留
        _root.gameworld.availableEffectPools = {};
        _global.ASSetPropFlags(_root.gameworld, ["availableEffectPools"], 1, true);

        // 设置为初始化完成
        _initialized = true;
    }

    /**
     * ======================================
     *  2) 对外公开方法：发射普通特效
     * ======================================
     * 对应原脚本: _root.效果(效果种类, x, y, 方向, 必然触发)
     */
    public static function effect(effectType:String, x:Number, y:Number, direction:Number, forceTrigger:Boolean):MovieClip
    {
        // A. 如果没指定特效类型，直接返回
        if (!effectType) {
            return null;
        }

        // B. 检查是否视觉元素 + 上限或几率限制，或强制触发
        var canPlay:Boolean = false;
        if (_root.是否视觉元素) {
            // 如果当前特效数未达上限，或者满足成功率，亦或 forceTrigger
            if (_currentEffectCount <= _maxEffectCount || _root.成功率(_maxEffectCount / 5) || forceTrigger) {
                canPlay = true;
            }
        }
        // 如果根本不满足条件
        if (!canPlay) {
            return null;
        }

        // C. 如果还没初始化、或 gameworld 不存在，就先试图初始化
        if (!_initialized) {
            reinitializeEffectSystem();
        }
        if (!_root.gameworld) {
            return null;
        }

        // D. 确保在 gameworld 上有 availableEffectPools
        if (!_root.gameworld.availableEffectPools) {
            _root.gameworld.availableEffectPools = {};
            _global.ASSetPropFlags(_root.gameworld, ["availableEffectPools"], 1, true);
        }

        // E. 若尚无该特效类型的池，则创建
        if (!_root.gameworld.availableEffectPools[effectType]) {
            _root.gameworld.availableEffectPools[effectType] = createEffectPool(effectType);
        }

        // F. 从对象池里取一个特效
        var pool:ObjectPool = _root.gameworld.availableEffectPools[effectType];
        var eff:MovieClip = MovieClip(pool.getObject(x, y, direction));

        if (eff) {
            _currentEffectCount++;
        }
        return eff;
    }

    /**
     * ========================================
     *  3) 对外公开方法：发射画面效果(屏幕特效)
     * ========================================
     * 对应原脚本: _root.画面效果(效果种类, x, y, 方向, 必然触发)
     * 仍然是 attach 到 _root，并在计时器中销毁，不进对象池。
     */
    public static function screenEffect(effectType:String, x:Number, y:Number, direction:Number, forceTrigger:Boolean):MovieClip
    {
        // A. 判断是否视觉元素 + 上限或几率限制 / forceTrigger
        var canPlay:Boolean = false;
        if (_root.是否视觉元素) {
            if (_currentScreenEffectCount <= _maxScreenEffectCount 
                || _root.成功率(_maxScreenEffectCount / 5)
                || forceTrigger) {
                canPlay = true;
            }
        }
        if (!canPlay) {
            return null;
        }

        // B. attach 到 _root
        var depth:Number = _root.getNextHighestDepth();
        var name:String = "screenEff_" + depth;
        _root.attachMovie(effectType, name, depth);
        var eff:MovieClip = _root[name];
        if (!eff) {
            return null;
        }

        // C. 设置坐标和方向
        eff._x = x;
        eff._y = y;
        eff._xscale = direction;

        // D. 数量 +1
        _currentScreenEffectCount++;

        // E. 用帧计时器延迟销毁(或减少计数)
        var timerID:Number = _root.帧计时器.添加单次任务(function() {
            // 此时画面效果已到期
            _currentScreenEffectCount--;
            // 你可以选择 eff.removeMovieClip() 或是 eff._visible=false 等
            // 这里示例仅减少计数
            // eff.removeMovieClip();
        }, _screenEffectLifetime);

        return eff;
    }

    /* ----------------------------------------------------------------------------------
       以下为【对象池】相关的内部逻辑，用于替换原脚本中的“原型+duplicateMovieClip”做法
       ---------------------------------------------------------------------------------- */

    /**
     * 创建特效对象池
     * @param effectType  库链接名 (类似 "Dust" / "Fire" )
     */
    private static function createEffectPool(effectType:String):ObjectPool
    {
        // 1) createFunc: 真正创建新的 MovieClip 对象
        //    注意：ObjectPool 调用时会将 parentClip, prototypeInitArgs 传进来
        var createFunc:Function = function(parentClip:MovieClip, effType:String):MovieClip
        {
            // 在 parentClip(即 _root.gameworld.效果) 上 attachMovie
            var depth:Number = parentClip.getNextHighestDepth();
            var mcName:String = effType + "_pooled_" + depth;

            var effMC:MovieClip = parentClip.attachMovie(effType, mcName, depth);
            if (effMC) {
                effMC._visible = false; 
                effMC.effectType = effType; // 记下类型
            }
            return effMC;
        };

        // 2) resetFunc: 当从池中取出时，要如何重置
        //    这里接收 pool.getObject(...) 的可变参数列表
        //    假设 getObject(x, y, direction) => resetFunc(this, x, y, direction)
        var resetFunc:Function = function(x:Number, y:Number, direction:Number):Void
        {
            // 重置为初始状态
            this._x = x;
            this._y = y;
            this._xscale = direction;
            this._visible = true;
            this.gotoAndPlay(1);

            // 模拟原脚本：覆盖 removeMovieClip => 回收到池
            var oldRemove:Function = this.removeMovieClip;
            var self:MovieClip = this;
            this.removeMovieClip = function(forceDestroy:Boolean):Void
            {
                // 若真正需要销毁(或全局“死亡特效”标志)
                if (forceDestroy || _root.帧计时器.是否死亡特效) {
                    oldRemove.call(self);
                } else {
                    // 否则回收到对象池
                    if (_root.gameworld && _root.gameworld.availableEffectPools) {
                        var pool:ObjectPool = _root.gameworld.availableEffectPools[self.effectType];
                        if (pool) {
                            pool.releaseObject(self);
                        }
                    }
                    // 特效计数递减
                    if (_currentEffectCount > 0) {
                        _currentEffectCount--;
                    }
                }
            };
        };

        // 3) releaseFunc: 当对象被回收到池时，要如何处理
        var releaseFunc:Function = function():Void
        {
            // 隐藏 & 停止
            this._visible = false;
            this.stop();

            // 还原 removeMovieClip
            if (this.removeMovieClip != undefined 
                && this.removeMovieClip.__proto__ != MovieClip.prototype.removeMovieClip)
            {
                delete this.removeMovieClip;
            }
        };

        // 4) 构建并返回对象池
        var parentClip:MovieClip = _root.gameworld.效果;  // 原脚本: 特效都在 gameworld.效果 层上
        var pool:ObjectPool = new ObjectPool(
            createFunc,      // 创建函数
            resetFunc,       // 重置函数
            releaseFunc,     // 回收函数
            parentClip,      // 父级影片剪辑 (gameworld.效果)
            30,              // 最大容量，可根据需要
            0,               // preloadSize=0
            true,            // isLazyLoaded
            true,            // isPrototypeEnabled
            [effectType]     // prototypeInitArgs => 传给 createFunc 的第二个参数
        );
        return pool;
    }

    /* ---------------------------------------------------------------------------
       以下若干接口方法，可用来动态修改特效上限/画面效果上限/持续时间
       --------------------------------------------------------------------------- */

    public static function setMaxEffectCount(value:Number):Void {
        _maxEffectCount = value;
    }

    public static function setMaxScreenEffectCount(value:Number):Void {
        _maxScreenEffectCount = value;
    }

    public static function setScreenEffectLifetime(value:Number):Void {
        _screenEffectLifetime = value;
    }
}
