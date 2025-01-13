/**
 * 效果系统
 * 负责管理游戏中的视觉效果，包括对象池、效果创建、回收及一些简单的生命周期控制。
 * 
 * 说明：
 * 1. 借鉴了 “弹壳系统” 使用对象池的思路，避免频繁创建/销毁 MovieClip。
 * 2. 参考了 _root.效果系统 中的相关逻辑，并进行了类的封装。
 * 3. 需要在游戏初始化时先调用 initialize 方法，确保效果池就绪。
 */

import org.flashNight.sara.util.*;
import org.flashNight.naki.RandomNumberEngine.*;

class org.flashNight.arki.component.Effect.EffectSystem {

    // —————————————— 静态变量区 ——————————————
    /**
     * 效果映射表：外部可通过加载或手动设置
     * 结构示例：
     * {
     *   "fire": { 原型: null },
     *   "smoke": { 原型: null }
     * }
     */
    private static var effectMap:Object = {};  

    /** 记录各类效果对应的对象池表，key 为效果名，value 为 ObjectPool 实例 */
    private static var effectPools:Object = {};

    /** 当前效果数量、上限（对应 _root.当前效果总数、_root.效果上限） */
    private static var currentEffectCount:Number = 0;
    private static var maxEffectCount:Number = 50; 

    /** 当前画面效果数量、上限（对应 _root.当前画面效果总数、_root.画面效果上限） */
    private static var currentScreenEffectCount:Number = 0;
    private static var maxScreenEffectCount:Number = 20;
    
    /** 画面效果存在时间（毫秒），对应 _root.画面效果存在时间 */
    private static var screenEffectDuration:Number = 1000;

    /** 是否已初始化 */
    private static var initialized:Boolean = false;


    // —————————————— 公有接口 ——————————————

    /**
     * 初始化效果系统（通常在游戏启动时调用）
     */
    public static function initialize():Void {
        if (initialized) return;  // 避免重复初始化
        
        var 游戏世界:MovieClip = _root.gameworld;
        if (!游戏世界) return; // 需确保 _root.gameworld 存在

        // 初始化效果池结构
        游戏世界.可用效果池 = {};
        effectPools = {};
        effectMap = {};
        currentEffectCount = 0;

        // 将 “可用效果池” 设置为不可枚举
        _global.ASSetPropFlags(游戏世界, ["可用效果池"], 1, true);

        // 标记完成初始化
        initialized = true;
    }

    /**
     * 设置/获取 效果映射表
     * 一旦设置，系统就会基于此数据来创建不同类型的效果
     */
    public static function setEffectMap(map:Object):Void {
        effectMap = map;
    }
    public static function getEffectMap():Object {
        return effectMap;
    }

    /**
     * 设置/获取 效果上限
     */
    public static function setMaxEffectCountLimit(limit:Number):Void {
        maxEffectCount = limit;
    }
    public static function getMaxEffectCountLimit():Number {
        return maxEffectCount;
    }

    /**
     * 设置/获取 画面效果上限
     */
    public static function setMaxScreenEffectCountLimit(limit:Number):Void {
        maxScreenEffectCount = limit;
    }
    public static function getMaxScreenEffectCountLimit():Number {
        return maxScreenEffectCount;
    }

    /**
     * 设置/获取 画面效果存在时间
     */
    public static function setScreenEffectDuration(duration:Number):Void {
        screenEffectDuration = duration;
    }
    public static function getScreenEffectDuration():Number {
        return screenEffectDuration;
    }

    /**
     * 发射/创建游戏内效果
     * 对应原先的 _root.效果()
     * @param effectType  效果种类
     * @param x           坐标 x
     * @param y           坐标 y
     * @param direction   xscale 用于反转、缩放等
     * @param forced      是否必然触发
     */
    public static function launchEffect(effectType:String, x:Number, y:Number, direction:Number, forced:Boolean):MovieClip {
        if (!initialized) { 
            initialize();
        }
        if (!effectType) return null;

        // 这里对应：_root.是否视觉元素
        // 如果 _root.是否视觉元素 == false，则不创建任何效果
        if (!_root.是否视觉元素 && !forced) {
            return null;
        }

        // 判断数量是否超过上限，或通过某种概率判断
        if (currentEffectCount >= maxEffectCount && !_root.成功率(maxEffectCount/5) && !forced) {
            return null;
        }

        var 游戏世界:MovieClip = _root.gameworld;
        if (!游戏世界.可用效果池) {
            // 如果尚未初始化或重新载入 _root.gameworld
            initialize();
        }

        // 1. 在可用效果池中尝试取对象
        var effectPool:Array = 游戏世界.可用效果池[effectType];
        if (!effectPool) {
            effectPool = 游戏世界.可用效果池[effectType] = [];
        }
        
        var newEffect:MovieClip;
        if (effectPool.length > 0) {
            // 如果池子里有空闲对象，直接复用
            newEffect = effectPool.pop();
            newEffect._x = x;
            newEffect._y = y;
            newEffect._visible = true;
            newEffect.gotoAndPlay(1);
        } else {
            // 如果池子里没有，则创建新的
            newEffect = createEffect(effectType, x, y);
        }

        if (newEffect) {
            newEffect._x = x;
            newEffect._y = y;
            newEffect._xscale = direction;
            ++currentEffectCount;
        }

        return newEffect;
    }

    /**
     * 发射/创建画面效果（UI 层或特殊层）
     * 对应原先的 _root.画面效果()
     */
    public static function launchScreenEffect(effectType:String, x:Number, y:Number, direction:Number, forced:Boolean):Void {
        if (!initialized) { 
            initialize();
        }
        // 同理先判断是否可创建
        if (!_root.是否视觉元素 && !forced) {
            return;
        }
        if (currentScreenEffectCount >= maxScreenEffectCount && !_root.成功率(maxScreenEffectCount/5) && !forced) {
            return;
        }

        var depth:Number = _root.getNextHighestDepth();
        var effectName:String = "screenEffect_" + depth;
        _root.attachMovie(effectType, effectName, depth);
        var screenEffect:MovieClip = _root[effectName];
        screenEffect._x = x;
        screenEffect._y = y;
        screenEffect._xscale = direction;

        // 增加计数
        currentScreenEffectCount++;

        // 创建一个定时器，过一段时间后让画面效果数减1
        var timerID:Number = _root.帧计时器.添加单次任务(function() {
            // 销毁 or 回收
            currentScreenEffectCount--;
            // 如果有需要，这里可考虑将 screenEffect.removeMovieClip() 也一并处理
        }, screenEffectDuration);
    }


    // —————————————— 私有方法区 ——————————————

    /**
     * 创建一个新的效果 MovieClip（用于对象池不够用的情况下）
     */
    private static function createEffect(effectType:String, x:Number, y:Number):MovieClip {
        var prototypeEffect:MovieClip = getOrCreatePrototypeEffect(effectType);
        if (!prototypeEffect) return null;

        var 游戏世界:MovieClip = _root.gameworld;
        var 世界效果:MovieClip = 游戏世界.效果;
        var newDepth:Number = 世界效果.getNextHighestDepth();
        // 复制原型
        var newEffect:MovieClip = prototypeEffect.duplicateMovieClip(effectType + "_" + newDepth, newDepth);
        newEffect._x = x;
        newEffect._y = y;
        newEffect._visible = true;

        // 初始化默认行为
        initializeEffectBehavior(newEffect, effectType);
        return newEffect;
    }

    /**
     * 获取或创建一个原型 MovieClip（懒加载）
     */
    private static function getOrCreatePrototypeEffect(effectType:String):MovieClip {
        // 如果 effectMap 中没有该效果类型，先创建一条空记录
        if (!effectMap[effectType]) {
            effectMap[effectType] = {原型: null};
        }

        // 如果已经创建过原型，直接返回
        if (effectMap[effectType].原型) {
            return effectMap[effectType].原型;
        }

        var 游戏世界:MovieClip = _root.gameworld;
        var 世界效果:MovieClip = 游戏世界.效果;
        if (!世界效果) {
            return null;
        }

        // attachMovie -> 加载实际库中的资源
        var prototypeEffect:MovieClip = 世界效果.attachMovie(effectType, "prototype_" + effectType, 世界效果.getNextHighestDepth());
        if (prototypeEffect) {
            prototypeEffect._visible = false; // 原型不可见
            effectMap[effectType].原型 = prototypeEffect;
        }
        return prototypeEffect;
    }

    /**
     * 初始化单个效果的默认行为
     * 这里参考了原先对 removeMovieClip 的改写，以及动画回收的逻辑
     */
    private static function initializeEffectBehavior(effectMC:MovieClip, effectType:String):Void {
        // 记录效果类型，回收时用
        effectMC.效果种类 = effectType;

        // 备份原有的 removeMovieClip
        effectMC.old_removeMovieClip = effectMC.removeMovieClip;

        effectMC.removeMovieClip = function(forceDestroy:Boolean) {
            // 对应 _root.帧计时器.是否死亡特效，如果没有此变量，你可以自行定义
            if (!_root.帧计时器.是否死亡特效 || forceDestroy) {
                this.old_removeMovieClip();
            } else {
                // 回收
                var gameWorld:MovieClip = _root.gameworld;
                var pool:Array = gameWorld.可用效果池[this.效果种类];
                if (!pool) {
                    pool = gameWorld.可用效果池[this.效果种类] = [];
                }
                // 清理本身引用
                delete this.onEnterFrame;
                this.stop();
                this._visible = false;
                pool.push(this);  // 回收进对象池

                // 计数 -1
                EffectSystem.decrementEffectCount();
            }
        };

        // 监测卸载
        effectMC.onUnload = function() {
            this.removeMovieClip(true);
        };
    }

    /**
     * 计数 -1
     * 用于回收时减少当前效果数量
     */
    private static function decrementEffectCount():Void {
        if (currentEffectCount > 0) {
            currentEffectCount--;
        }
    }
}
