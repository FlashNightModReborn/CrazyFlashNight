/**
 * Tween 是补间动画引擎的核心类，提供高性能、轻量级的属性补间功能。
 * 
 * @org.flashNight.neur.Tween
 * @version 1.0
 */

import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

class org.flashNight.neur.Tween.Tween extends TweenCore {
    // 静态变量
    private static var _tweens:Array = [];
    private static var _inited:Boolean = false;
    private static var _root:MovieClip;
    private static var _ticker:MovieClip;
    private static var _lastTime:Number;
    private static var _defaultEase:Function = Easing.Quad.easeOut;
    
    // 实例变量
    private var _target:Object;
    private var _vars:Object;
    private var _propData:Array; // 存储属性数据 {prop, start, change}
    private var _ease:Function;
    private var _delay:Number;
    private var _onComplete:Function;
    private var _onCompleteParams:Array;
    private var _onUpdate:Function;
    private var _onUpdateParams:Array;
    
    // 对象池
    private static var _pool:Array = [];
    private static var _poolLimit:Number = 50;
    
    /**
     * 初始化补间系统
     */
    public static function init():Void {
        if (_inited) return;
        
        _root = _root || _level0;
        _ticker = _root.createEmptyMovieClip("__tweenTicker", 16384);
        _ticker.onEnterFrame = _tick;
        _lastTime = getTimer() / 1000;
        _inited = true;
    }
    
    /**
     * 每帧更新函数
     */
    private static function _tick():Void {
        var currentTime:Number = getTimer() / 1000;
        var elapsed:Number = currentTime - _lastTime;
        _lastTime = currentTime;
        
        if (elapsed == 0) return;
        
        var tween:Tween;
        var i:Number = _tweens.length;
        
        while (--i > -1) {
            tween = _tweens[i];
            
            if (tween == null || !tween.isActive) {
                _tweens.splice(i, 1);
                continue;
            }
            
            if (!tween.update(elapsed)) {
                _tweens.splice(i, 1);
                tween._cleanup();
            }
        }
    }
    
    /**
     * 从对象池获取实例
     */
    private static function _getTweenFromPool():Tween {
        if (_pool.length > 0) {
            return Tween(_pool.pop());
        }
        return new Tween(null, 0, {});
    }
    
    /**
     * 创建一个从当前值到目标值的补间
     */
    public static function to(target:Object, duration:Number, vars:Object):Tween {
        if (!_inited) init();
        
        var tween:Tween = _getTweenFromPool();
        tween._initialize(target, duration, vars);
        _tweens.push(tween);
        
        return tween;
    }
    
    /**
     * 创建一个从指定值到当前值的补间
     */
    public static function from(target:Object, duration:Number, vars:Object):Tween {
        if (!_inited) init();
        
        // 复制vars以避免修改原始对象
        var copyVars:Object = {};
        for (var p in vars) {
            copyVars[p] = vars[p];
        }
        
        // 交换起始值和结束值
        var tween:Tween = _getTweenFromPool();
        tween._initialize(target, duration, copyVars, true);
        _tweens.push(tween);
        
        return tween;
    }
    
    /**
     * 停止目标对象的所有补间
     */
    public static function killTweensOf(target:Object):Void {
        var i:Number = _tweens.length;
        while (--i > -1) {
            if (_tweens[i]._target == target) {
                _tweens[i].complete();
                _tweens[i]._cleanup();
                _tweens.splice(i, 1);
            }
        }
    }
    
    /**
     * 延迟调用函数
     */
    public static function delayedCall(delay:Number, callback:Function, params:Array):Tween {
        var vars:Object = {
            delay: delay,
            onComplete: callback,
            onCompleteParams: params || []
        };
        return to({}, 0, vars);
    }
    
    /**
     * 构造函数
     */
    public function Tween(target:Object, duration:Number, vars:Object, isFrom:Boolean) {
        super(duration, false);
        if (target != null) {
            _initialize(target, duration, vars, isFrom);
        }
    }
    
    /**
     * 初始化补间
     */
    private function _initialize(target:Object, duration:Number, vars:Object, isFrom:Boolean):Void {
        _target = target;
        _vars = vars;
        super.time = 0;
        super.startTime = 0;
        _propData = [];
        
        // 解析特殊属性
        _delay = vars.delay || 0;
        _ease = vars.ease || _defaultEase;
        _onComplete = vars.onComplete;
        _onCompleteParams = vars.onCompleteParams || [];
        _onUpdate = vars.onUpdate;
        _onUpdateParams = vars.onUpdateParams || [];
        
        // 初始化属性数据
        for (var p in vars) {
            // 跳过特殊属性
            if (p == "delay" || p == "ease" || p == "onComplete" || p == "onCompleteParams" || 
                p == "onUpdate" || p == "onUpdateParams") {
                continue;
            }
            
            var start:Number = isFrom ? Number(vars[p]) : Number(_target[p]);
            var end:Number = isFrom ? Number(_target[p]) : Number(vars[p]);
            var propInfo:Object = {
                prop: p,
                start: start,
                change: end - start
            };
            _propData.push(propInfo);
            
            // 如果是from，立即设置起始值
            if (isFrom) {
                _target[p] = start;
            }
        }
    }
    
    /**
     * 更新补间
     */
    public function update(elapsed:Number):Boolean {
        if (_state != TweenCore.ACTIVE) {
            return false;
        }
        
        // 处理延迟
        if (_delay > 0) {
            _delay -= elapsed;
            if (_delay > 0) return true;
            elapsed = -_delay;
            _delay = 0;
        }
        
        // 更新时间
        super.time += elapsed;
        
        // 检查是否完成
        if (super.time >= super.duration) {
            _render(1);
            if (_onComplete != null) {
                _onComplete.apply(null, _onCompleteParams);
            }
            _state = TweenCore.COMPLETED;
            return false;
        }
        
        // 计算进度并渲染
        var progress:Number = super.time / super.duration;
        _render(_ease(progress, 0, 1, 1));
        
        return true;
    }
    
    /**
     * 渲染补间
     */
    private function _render(ratio:Number):Void {
        var i:Number = _propData.length;
        var info:Object;
        
        while (--i > -1) {
            info = _propData[i];
            _target[info.prop] = info.start + (info.change * ratio);
        }
        
        if (_onUpdate != null) {
            _onUpdate.apply(null, _onUpdateParams);
        }
    }
    
    /**
     * 清理补间资源，准备回收
     */
    private function _cleanup():Void {
        // 重置属性以便重用
        _target = null;
        _vars = null;
        _propData = null;
        _ease = null;
        _onComplete = null;
        _onCompleteParams = null;
        _onUpdate = null;
        _onUpdateParams = null;
        
        // 放回对象池
        if (_pool.length < _poolLimit) {
            _pool.push(this);
        }
    }
}