﻿import org.flashNight.sara.util.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.neur.Server.*; 
import org.flashNight.gesh.object.*;
import org.flashNight.arki.bullet.BulletComponent.Loader.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;

class org.flashNight.arki.bullet.BulletComponent.Shell.ShellSystem {
    // 弹壳映射表（由数据加载）
    private static var shellMap:Object = {};
    // 弹壳池映射
    private static var shellPools:Object = {};
    // 当前弹壳总数与上限
    private static var currentShellCount:Number = 0;
    private static var maxShellCount:Number = 25;

    private static var initialized:Boolean = false;

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
    }

    /**
     * 发射弹壳接口
     * 与原先 _root.弹壳系统.发射弹壳 功能一致，可通过 delegate 转接
     */
    public static function launchShell(子弹类型:String, myX:Number, myY:Number, xscale:Number, 必然触发:Boolean):Void {
        if (!initialized) {
            // 如果未初始化，则尝试初始化
            initializeBulletPools();
        }

        if (currentShellCount <= maxShellCount || _root.成功率(maxShellCount) || 必然触发) {
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
                initializeBulletPools();
                pool = shellPools[弹壳种类];
                if (!pool)
                    return;
            }

            var 弹壳:MovieClip = pool.getObject();
            var scale = xscale / 100;
            var ascale = Math.abs(scale);
            myX -= scale * 弹壳信息.myX;
            myY += ascale * 弹壳信息.myY;

            弹壳._x = myX;
            弹壳._y = myY;
            弹壳._visible = true;
            弹壳._xscale = xscale;
            弹壳._yscale = ascale * 100;

            // 存储子弹类型
            弹壳.弹壳种类 = 弹壳种类;

            // 启动物理模拟
            shellPhysicsSimulation(弹壳);

            ++currentShellCount;
        }
    }

    /**
     * 弹壳物理模拟函数 (原逻辑)
     */
    private static function shellPhysicsSimulation(弹壳:MovieClip):Void {
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
        弹壳.水平速度 = engine.randomFloatOffset(4);
        弹壳.垂直速度 = engine.randomFloat(-8, -20);
        弹壳.旋转速度 = engine.randomFloat(-10, 10);
        弹壳.Z轴坐标 = 弹壳._y + 100;
        弹壳.swapDepths(弹壳.Z轴坐标);

        弹壳.任务ID = _root.帧计时器.taskManager.addLifecycleTask(
            弹壳,
            "运动",
            shellPhysics,
            33,
            [弹壳]
        );
    }

    /**
     * 弹壳物理运动函数 (原逻辑)
     */
    /**
     * 弹壳物理运动函数 (原逻辑)
     */
    private static function shellPhysics(弹壳:MovieClip):Void {
        if (弹壳._y - 弹壳.Z轴坐标 < -5) {
            弹壳.垂直速度 += 4;
            弹壳._x += 弹壳.水平速度;
            弹壳._y += 弹壳.垂直速度;
            弹壳._rotation += 弹壳.旋转速度;
        } else {
            var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
            弹壳.垂直速度 = 弹壳.垂直速度 / -2 - engine.randomIntegerStrict(0, 5);
            弹壳._xscale *= ((Math.sin(弹壳._rotation * 0.0174533) + 1) * 0.5) * 0.5 + 0.5;
            if (弹壳.垂直速度 < -10) {
                弹壳.水平速度 += engine.randomFloatOffset(4)
                弹壳.旋转速度 *= engine.randomFluctuation(50);
                弹壳._x += 弹壳.水平速度;
                弹壳._y = 弹壳.Z轴坐标 - 6;
                弹壳._rotation += 弹壳.旋转速度;
            } else {
                // 弹壳落地，添加回收任务
                _root.add2map3(弹壳, 2);
                _root.帧计时器.移除任务(弹壳.任务ID);
                _root.帧计时器.添加或更新任务(弹壳, "回收", function(壳:MovieClip) {
                    recycleShell(壳);
                }, 1, 弹壳);
            }
        }
    }


    /**
     * 回收弹壳方法
     */
    private static function recycleShell(弹壳:MovieClip):Void {
        var 弹壳种类:String = 弹壳.弹壳种类;
        var pool:ObjectPool = shellPools[弹壳种类];
        if (pool) {
            pool.releaseObject(弹壳);
        }

        --currentShellCount;
    }
}
