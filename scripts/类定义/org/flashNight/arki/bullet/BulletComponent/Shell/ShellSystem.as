import org.flashNight.sara.util.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.neur.Server.*; 
import org.flashNight.gesh.object.*;
import org.flashNight.arki.bullet.BulletComponent.Loader.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

class org.flashNight.arki.bullet.BulletComponent.Shell.ShellSystem {
    // 弹壳映射表（由数据加载）
    private static var shellMap:Object = {};
    // 弹壳池映射
    private static var shellPools:Object = {};
    // 当前弹壳总数与上限
    private static var currentShellCount:Number = 0;
    private static var maxShellCount:Number = 25;

    private static var initialized:Boolean = false;
    
    // 用于存放所有正在进行物理模拟的活动弹壳
    private static var activeShells:Array = [];
    // 用于存储全局更新任务的唯一ID
    private static var globalUpdateTaskID:Number;
    // 标志位，用于确保全局更新任务只被启动一次
    private static var isUpdateLoopRunning:Boolean = false;

    /**
     * 初始化方法：注册InfoLoader回调，将数据加载整合到ShellSystem内部
     */
    public static function initialize():Void {
        InfoLoader.getInstance().onLoad(function(data:Object):Void {
            ShellSystem.onShellDataLoad(data);
        });
    }

    /**
     * 设置弹壳总数上限
     */
    public static function setMaxShellCountLimit(limit:Number):Void {
        maxShellCount = limit;
    }

    /**
     * 获取弹壳总数上限
     */
    public static function getMaxShellCountLimit():Number {
        return maxShellCount;
    }

    /**
     * 当加载完成 InfoLoader 数据后调用此方法
     * 用于设置 shellMap，并初始化弹壳池
     */
    public static function onShellDataLoad(data:Object):Void {
        shellMap = data.shellData;
        initializeBulletPools();
    }

    /**
     * 初始化弹壳池
     * 在重新加载 _root.gameworld 后需要再次调用该函数
     */
    public static function initializeBulletPools():Void {
        var 游戏世界 = _root.gameworld;
        if (!游戏世界)
            return; // 确保游戏世界存在

        // _root.服务器.发布服务器消息("[ShellSystem] initializeBulletPools: 重置系统状态");
        activeShells = [];
        stopUpdateLoop();
        currentShellCount = 0;
        shellPools = {};
        游戏世界.可用弹壳池 = {}; // 兼容旧逻辑

        // 对象池函数构造器
        function createBulletPoolFuncs(bulletType:String):Object {
            var createFunc:Function = function(parentClip:MovieClip):MovieClip {
                var 游戏世界 = _root.gameworld;
                var 世界效果 = 游戏世界.效果;
                var prototypeBullet = 世界效果.attachMovie(bulletType, "prototype_" + bulletType, 世界效果.getNextHighestDepth());
                prototypeBullet._visible = false;
                return prototypeBullet;
            };

            var resetFunc:Function = function():Void {
                this._visible = true;
                this.__isDestroyed = false;
                // ⚠️ 清零所有内部标志，防止对象池重用时状态污染
                this.__isRecycled = false;
                this.__scheduledRecycle = false;
            };

            var releaseFunc:Function = function():Void {
                this._visible = false;
            };

            return {createFunc: createFunc, resetFunc: resetFunc, releaseFunc: releaseFunc};
        }

        // 创建或更新对象池
        for (var bulletName in shellMap) {
            var 弹壳信息 = shellMap[bulletName];
            var 弹壳种类:String = 弹壳信息.弹壳;
            if (!弹壳种类)
                continue;

            var funcs = createBulletPoolFuncs(弹壳种类);
            var 世界效果 = 游戏世界.效果;
            var pool = new org.flashNight.sara.util.ObjectPool(funcs.createFunc, funcs.resetFunc, funcs.releaseFunc, 世界效果, 30, 0, true, true, []);

            shellPools[弹壳种类] = pool;
            游戏世界.可用弹壳池[弹壳种类] = pool;
        }

        _global.ASSetPropFlags(游戏世界, ["可用弹壳池"], 1, false);
        initialized = true;
        // _root.服务器.发布服务器消息("[ShellSystem] initializeBulletPools: 启动全局更新循环");
        startUpdateLoop();
    }

    /**
     * 发射弹壳接口
     */
    public static function launchShell(bullet:MovieClip, myX:Number, myY:Number, xscale:Number, 必然触发:Boolean):Void {
        var 子弹类型:String = bullet.子弹种类;

        if (!initialized) {
            // 如果未初始化，则尝试初始化
            initializeBulletPools();
            if (!initialized) {
                return; // 初始化失败，直接返回
            }
        }
        // 位掩码优化：使用宏展开避免属性索引开销
        #include "../macros/FLAG_VERTICAL.as"    
        // 注入: var FLAG_VERTICAL:Number = 128;
        
        // 原始: bullet.纵向检测 ? bullet.霰弹值 : 1 - 需要属性哈希查找
        // 优化: (bullet.flags & FLAG_VERTICAL) != 0 - 直接位运算检测
        var shellCount:Number = ((bullet.flags & FLAG_VERTICAL) != 0) ? bullet.霰弹值 : 1;
        
        // 性能优化：使用线性随机数引擎的直接方法调用替代 _root.成功率
        // 原 _root.成功率 通过 Delegate.create 包装，增加了函数调用开销
        // 直接调用 engine.successRate 避免了 Delegate 包装的性能损耗
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
        
        if (activeShells.length < maxShellCount || engine.successRate(maxShellCount) || 必然触发) {
            var 游戏世界 = _root.gameworld;
            if (!游戏世界)
                return;

            var 弹壳信息 = shellMap[子弹类型];
            if (!弹壳信息)
                return;

            var 弹壳种类:String = 弹壳信息.弹壳;
            if (!弹壳种类)
                return;

            var pool:ObjectPool = shellPools[弹壳种类];
            if (!pool) {
                return; // 池不存在，避免重复初始化
            }

            var scale = xscale / 100;
            var ascale = Math.abs(scale);
            var baseX:Number = myX - scale * 弹壳信息.myX;
            var baseY:Number = myY + ascale * 弹壳信息.myY;
            var yScale:Number = ascale * 100;
            var hasMultipleShells:Boolean = shellCount > 1;
            
            // 根据shellCount生成对应数量的弹壳
            for (var i:Number = 0; i < shellCount; i++) {
                if (activeShells.length >= maxShellCount && !必然触发) {
                    break; // 如果达到上限且非必然触发，停止生成
                }
                
                var 弹壳:MovieClip = pool.getObject();
                
                // 为多个弹壳添加轻微的位置偏移，避免重叠
                var offsetX:Number = hasMultipleShells ? engine.randomFloatOffset(8) : 0;
                var offsetY:Number = hasMultipleShells ? engine.randomFloatOffset(4) : 0;
                
                弹壳._x = baseX + offsetX;
                弹壳._y = baseY + offsetY;
                弹壳._visible = true;
                弹壳._xscale = xscale;
                弹壳._yscale = yScale;

                // 存储子弹类型
                弹壳.弹壳种类 = 弹壳种类;

                // 初始化物理状态并添加到活动列表
                initializeShellPhysicsState(弹壳);
                activeShells.push(弹壳);
                // _root.服务器.发布服务器消息("[ShellSystem] launchShell: 添加弹壳到活动列表, activeShells.length=" + activeShells.length + ", currentShellCount=" + currentShellCount);

                ++currentShellCount;
            }
        }
    }

    /**
     * 初始化弹壳物理状态 (重构后版本，不创建独立任务)
     */
    private static function initializeShellPhysicsState(弹壳:MovieClip):Void {
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
        弹壳.水平速度 = engine.randomFloatOffset(4);
        弹壳.垂直速度 = engine.randomFloat(-8, -20);
        弹壳.旋转速度 = engine.randomFloat(-10, 10);
        弹壳.Z轴坐标 = 弹壳._y + 100;
        弹壳.swapDepths(弹壳.Z轴坐标);
        弹壳.存活帧 = 0;          // 记录已执行 tick 次数
    }

    /**
     * 启动全局更新循环
     */
    private static function startUpdateLoop():Void {
        if (!isUpdateLoopRunning) {
            isUpdateLoopRunning = true;
            globalUpdateTaskID = EnhancedCooldownWheel.I().addTask(updateAllShells, 33, -1);
        }
    }

    /**
     * 停止全局更新循环
     */
    private static function stopUpdateLoop():Void {
        if (isUpdateLoopRunning) {
            EnhancedCooldownWheel.I().removeTask(globalUpdateTaskID);
            isUpdateLoopRunning = false;
        }
    }

    /**
     * 全局弹壳更新函数 - 核心批处理逻辑
     */
    private static function updateAllShells():Void {
        // 使用向后循环遍历活动弹壳，确保在遍历时安全移除元素
        if (activeShells.length > 0) {
            // _root.服务器.发布服务器消息("[ShellSystem] updateAllShells: 开始更新 " + activeShells.length + " 个活动弹壳, currentShellCount=" + currentShellCount);
        }
        
        // 缓存常用对象引用以减少属性访问开销
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
        var cooldownWheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();
        
        for (var i:Number = activeShells.length - 1; i >= 0; --i) {
            var 弹壳:MovieClip = activeShells[i];
            var shouldRemove:Boolean = false;

            // --------------- 60 帧保险丝 ----------------
            // 每执行一次物理逻辑先 ++，
            // 到 60 就直接强制回收，跳过其余计算
            if (++弹壳.存活帧 >= 60) {
                // _root.服务器.发布服务器消息("[ShellSystem] updateAllShells: 弹壳存活帧>=60, 强制回收 " + 弹壳);
                shouldRemove = true;
            } else if (弹壳._y - 弹壳.Z轴坐标 < -5) {
                // ------------------------------------------
                弹壳.垂直速度 += 4;
                弹壳._x += 弹壳.水平速度;
                弹壳._y += 弹壳.垂直速度;
                弹壳._rotation += 弹壳.旋转速度;
            } else {
                弹壳.垂直速度 = 弹壳.垂直速度 / -2 - engine.randomIntegerStrict(0, 5);
                // 透视缩放效果：根据旋转角度调整水平缩放，模拟3D旋转的透视感
                // 公式简化为：0.75 + 0.25 * sin(θ)，取值范围 [0.5, 1.0]
                // 当弹壳正面朝向时缩放为1.0，侧面时缩放为0.5，产生压扁效果
                弹壳._xscale *= ((Math.sin(弹壳._rotation * 0.0174533) + 1) * 0.5) * 0.5 + 0.5;
                if (弹壳.垂直速度 < -10) {
                    弹壳.水平速度 += engine.randomFloatOffset(4)
                    弹壳.旋转速度 *= engine.randomFluctuation(50);
                    弹壳._x += 弹壳.水平速度;
                    弹壳._y = 弹壳.Z轴坐标 - 6;
                    弹壳._rotation += 弹壳.旋转速度;
                } else {
                    // 弹壳落地，立即从活动循环中移除并调度回收
                    // _root.服务器.发布服务器消息("[ShellSystem] updateAllShells: 弹壳落地 " + 弹壳 + ", 从activeShells[" + i + "]移除并调度回收");
                    _root.add2map3(弹壳, 2);
                    shouldRemove = true;
                }
            }
            
            // 统一处理删除和回收逻辑
            if (shouldRemove) {
                // 使用交换并弹出技巧进行O(1)删除操作
                if (i < activeShells.length - 1) {
                    activeShells[i] = activeShells[activeShells.length - 1];
                }
                activeShells.pop();
                --currentShellCount;
                // 延迟释放到对象池
                弹壳.__scheduledRecycle = true;
                cooldownWheel.addDelayedTask(33, recycleShell, 弹壳);
            }
        }
    }

    /**
     * 回收弹壳方法
     */
    private static function recycleShell(弹壳:MovieClip):Void {
        // _root.服务器.发布服务器消息("[ShellSystem] recycleShell: 开始回收弹壳 " + 弹壳 + ", __isRecycled=" + 弹壳.__isRecycled + ", __scheduledRecycle=" + 弹壳.__scheduledRecycle);
        
        // **防止过时延迟任务的强化保护**
        if (弹壳.__isRecycled) {
            // _root.服务器.发布服务器消息("[ShellSystem] recycleShell: 弹壳已回收，跳过 " + 弹壳);
            return;
        }
        
        // **检查是否为过时的延迟任务**
        if (!弹壳.__scheduledRecycle) {
            // _root.服务器.发布服务器消息("[ShellSystem] recycleShell: 弹壳未标记为待回收，可能是过时任务，跳过 " + 弹壳);
            return;
        }
        
        弹壳.__isRecycled = true;
        
        var 弹壳种类:String = 弹壳.弹壳种类;
        var pool:ObjectPool = shellPools[弹壳种类];
        if (pool) {
            pool.releaseObject(弹壳);
        }

        // 移除危险的备用清理机制
        // 在当前设计下，弹壳应该已经在 updateAllShells 中被移除
        // 这个循环可能会错误地移除已被复用的弹壳实例
        // _root.服务器.发布服务器消息("[ShellSystem] recycleShell: 跳过activeShells清理，避免竞态条件 " + 弹壳);

        // currentShellCount 已经在 updateAllShells 中同步减少，这里不再重复减少
        // _root.服务器.发布服务器消息("[ShellSystem] recycleShell: 完成回收，currentShellCount=" + currentShellCount + ", activeShells.length=" + activeShells.length);
    }
}
