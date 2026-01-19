/**
 * EventListenerComponent.as - 原语级事件监听组件
 *
 * 设计原则：
 * - 只负责"监听-状态-计时-回调"，不包含任何业务逻辑
 * - 具体行为完全由回调决定（buff切换、视觉效果等）
 * - 非门控组件，不影响宿主MetaBuff生死
 *
 * 状态机：
 *   IDLE ──[事件触发且filter通过]──► ACTIVE ──[duration到期]──► IDLE
 *           ↑                           │
 *           │                           │[重复触发]
 *           │                           ▼
 *           │                      刷新计时器
 *           └───[duration=0时需手动deactivate]
 *
 * 使用示例：
 *   var eventComp:EventListenerComponent = new EventListenerComponent({
 *       dispatcher: unit.dispatcher,
 *       eventName: "WeaponSkill",
 *       filter: function(skillName:String):Boolean {
 *           return skillName == "刀剑乱舞";
 *       },
 *       duration: 450, // 15秒@30fps，0=永久激活
 *       onActivate: function():Void {
 *           // 首次激活或从IDLE切换到ACTIVE
 *       },
 *       onDeactivate: function():Void {
 *           // 计时到期或手动停用
 *       },
 *       onRefresh: function():Void {
 *           // 激活期间重复触发（可选）
 *       }
 *   });
 *
 * 与BuffManager配合的典型模式：
 *   - 控制器MetaBuff（永久，无PodBuff）挂载本组件
 *   - 回调中通过同ID替换切换效果MetaBuff
 *   - 组件不会因效果buff替换而被销毁
 *
 * @author FlashNight
 * @version 1.0
 */
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.component.Buff.Component.EventListenerComponent
    implements IBuffComponent
{
    // ==================== 状态常量 ====================
    private static var STATE_IDLE:Number = 0;
    private static var STATE_ACTIVE:Number = 1;

    // ==================== 配置（构造后只读） ====================
    private var _dispatcher:Object;         // 事件派发器（需有subscribe/unsubscribe方法）
    private var _eventName:String;          // 监听的事件名
    private var _filter:Function;           // 过滤函数 (args...) => Boolean，可选
    private var _duration:Number;           // 激活持续帧数，0=永久（需手动deactivate）

    // ==================== 回调 ====================
    private var _onActivate:Function;       // () => Void，IDLE→ACTIVE时触发
    private var _onDeactivate:Function;     // () => Void，ACTIVE→IDLE时触发
    private var _onRefresh:Function;        // () => Void，ACTIVE期间重复触发（可选）

    // ==================== 运行时状态 ====================
    private var _state:Number;              // 当前状态
    private var _remaining:Number;          // 剩余激活帧数
    private var _handler:Function;          // 事件处理函数引用（用于取消订阅）
    private var _subscribeTarget:Object;    // 订阅时的target引用

    /**
     * 构造函数
     * @param config 配置对象：
     *   - dispatcher: Object   事件派发器（必需）
     *   - eventName: String    事件名（必需）
     *   - filter: Function     过滤函数，返回true时才触发（可选）
     *   - duration: Number     激活持续帧数，0=永久（可选，默认0）
     *   - onActivate: Function 激活回调（可选）
     *   - onDeactivate: Function 停用回调（可选）
     *   - onRefresh: Function  刷新回调（可选）
     */
    public function EventListenerComponent(config:Object) {
        if (!config) config = {};

        _dispatcher = config.dispatcher;
        _eventName = (config.eventName != undefined) ? String(config.eventName) : "";
        _filter = config.filter;
        _duration = (config.duration > 0) ? Number(config.duration) : 0;

        _onActivate = config.onActivate;
        _onDeactivate = config.onDeactivate;
        _onRefresh = config.onRefresh;

        _state = STATE_IDLE;
        _remaining = 0;
        _handler = null;
        _subscribeTarget = null;

        // [DEBUG] 构造诊断
        _root.服务器.发布服务器消息("[EventListenerComponent] 构造完成: eventName=" + _eventName +
              ", hasDispatcher=" + (_dispatcher != null) +
              ", duration=" + _duration);
    }

    // ==================== IBuffComponent 接口实现 ====================

    /**
     * 组件挂载到宿主时调用
     * 订阅事件
     */
    public function onAttach(host:IBuff):Void {
        _root.服务器.发布服务器消息("[EventListenerComponent] onAttach 被调用, eventName=" + _eventName);

        if (!_dispatcher || !_eventName || _eventName.length == 0) {
            _root.服务器.发布服务器消息("[EventListenerComponent] 警告：dispatcher或eventName未配置，组件无效");
            return;
        }

        // 检查dispatcher是否有subscribe方法
        if (typeof _dispatcher.subscribe != "function") {
            _root.服务器.发布服务器消息("[EventListenerComponent] 警告：dispatcher没有subscribe方法");
            return;
        }

        var self:EventListenerComponent = this;
        _subscribeTarget = host; // 用宿主作为订阅target

        // 创建事件处理函数
        _handler = function():Void {
            _root.服务器.发布服务器消息("[EventListenerComponent] 事件处理函数被触发: " + self._eventName);
            self._handleEvent(arguments);
        };

        // 订阅事件
        _dispatcher.subscribe(_eventName, _handler, _subscribeTarget);
        _root.服务器.发布服务器消息("[EventListenerComponent] 订阅完成: " + _eventName);
    }

    /**
     * 组件从宿主卸载时调用
     * 取消订阅并清理状态
     */
    public function onDetach():Void {
        // 取消订阅
        if (_dispatcher && _eventName && _handler) {
            if (typeof _dispatcher.unsubscribe == "function") {
                _dispatcher.unsubscribe(_eventName, _handler);
            }
        }

        // 如果正在激活状态，触发停用回调
        if (_state == STATE_ACTIVE) {
            _state = STATE_IDLE;
            _remaining = 0;
            _safeCall(_onDeactivate);
        }

        // 清理引用
        _dispatcher = null;
        _handler = null;
        _filter = null;
        _onActivate = null;
        _onDeactivate = null;
        _onRefresh = null;
        _subscribeTarget = null;
    }

    /**
     * 组件更新
     * 处理激活状态的计时
     * @return Boolean 始终返回true（非门控组件）
     */
    public function update(host:IBuff, deltaFrames:Number):Boolean {
        // 仅在激活状态且有持续时间限制时处理计时
        if (_state == STATE_ACTIVE && _duration > 0) {
            _remaining -= deltaFrames;
            if (_remaining <= 0) {
                // 计时到期，切换到IDLE
                _state = STATE_IDLE;
                _remaining = 0;
                _safeCall(_onDeactivate);
            }
        }

        // 非门控组件，始终返回true
        return true;
    }

    /**
     * [Phase 0 契约] 非门控组件
     * 状态变化不影响宿主Buff生死
     */
    public function isLifeGate():Boolean {
        return false;
    }

    // ==================== 内部方法 ====================

    /**
     * 事件处理
     */
    private function _handleEvent(args:Array):Void {
        _root.服务器.发布服务器消息("[EventListenerComponent] _handleEvent 被调用, eventName=" + _eventName + ", argsLength=" + args.length);

        // 过滤检查
        if (_filter != null) {
            var pass:Boolean = false;
            try {
                pass = _filter.apply(null, args);
                _root.服务器.发布服务器消息("[EventListenerComponent] filter结果=" + pass);
            } catch (e) {
                _root.服务器.发布服务器消息("[EventListenerComponent] filter执行异常: " + e);
                return;
            }
            if (!pass) {
                _root.服务器.发布服务器消息("[EventListenerComponent] filter未通过，退出");
                return;
            }
        }

        // 状态切换
        _root.服务器.发布服务器消息("[EventListenerComponent] 当前状态=" + (_state == STATE_IDLE ? "IDLE" : "ACTIVE"));
        if (_state == STATE_IDLE) {
            // IDLE → ACTIVE
            _state = STATE_ACTIVE;
            _remaining = _duration;
            _root.服务器.发布服务器消息("[EventListenerComponent] 状态切换: IDLE → ACTIVE, 调用onActivate");
            _safeCall(_onActivate);
        } else {
            // 已激活，刷新计时
            _remaining = _duration;
            _root.服务器.发布服务器消息("[EventListenerComponent] 刷新计时, 调用onRefresh");
            _safeCall(_onRefresh);
        }
    }

    /**
     * 安全调用回调函数
     */
    private function _safeCall(callback:Function):Void {
        if (callback != null) {
            try {
                callback();
            } catch (e) {
                _root.服务器.发布服务器消息("[EventListenerComponent] 回调执行异常: " + e);
            }
        }
    }

    // ==================== 公共接口 ====================

    /**
     * 获取当前是否处于激活状态
     */
    public function isActive():Boolean {
        return _state == STATE_ACTIVE;
    }

    /**
     * 获取剩余激活时间（帧）
     * @return 剩余帧数，IDLE状态返回0
     */
    public function getRemaining():Number {
        return (_state == STATE_ACTIVE) ? _remaining : 0;
    }

    /**
     * 获取配置的持续时间
     */
    public function getDuration():Number {
        return _duration;
    }

    /**
     * 手动激活
     * 用于非事件触发的场景
     */
    public function activate():Void {
        if (_state == STATE_IDLE) {
            _state = STATE_ACTIVE;
            _remaining = _duration;
            _safeCall(_onActivate);
        }
    }

    /**
     * 手动停用
     * 用于提前结束激活状态
     */
    public function deactivate():Void {
        if (_state == STATE_ACTIVE) {
            _state = STATE_IDLE;
            _remaining = 0;
            _safeCall(_onDeactivate);
        }
    }

    /**
     * 运行时更新持续时间
     * @param d 新的持续帧数，0=永久
     */
    public function setDuration(d:Number):Void {
        _duration = (d > 0) ? d : 0;
    }

    /**
     * 运行时更新回调
     */
    public function setOnActivate(callback:Function):Void {
        _onActivate = callback;
    }

    public function setOnDeactivate(callback:Function):Void {
        _onDeactivate = callback;
    }

    public function setOnRefresh(callback:Function):Void {
        _onRefresh = callback;
    }

    /**
     * 调试信息
     */
    public function toString():String {
        var stateStr:String = (_state == STATE_ACTIVE) ? "ACTIVE" : "IDLE";
        return "[EventListenerComponent event=" + _eventName +
               ", state=" + stateStr +
               ", remaining=" + _remaining +
               ", duration=" + _duration + "]";
    }
}
