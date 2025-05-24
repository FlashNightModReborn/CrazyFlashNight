// MetaBuff.as
import org.flashNight.arki.component.Buff.BuffHandle.BaseBuff;
import org.flashNight.neur.Event.EventBus;

class org.flashNight.arki.component.Buff.BuffHandle.MetaBuff extends BaseBuff {
    private var _condition:Function;      // 条件函数（可选）
    private var _effect:Function;         // 效果函数
    private var _duration:Number;         // 持续时间（单位：帧或毫秒，-1表示永久）
    private var _timer:Number;            // 剩余时间
    private var _isActive:Boolean;        // 是否激活
    private var _eventSubscriptions:Array;// 事件订阅列表（用于动态条件）

    /**
     * 构造函数
     * @param type Buff类型
     * @param effect 效果函数（必须）
     * @param condition 条件函数（可选，默认为立即激活）
     * @param duration 持续时间（可选，-1为永久）
     */
    public function MetaBuff(
        type:String,
        effect:Function,
        condition:Function,
        duration:Number
    ) {
        super(type);
        this._effect = effect;
        this._condition = condition || function():Boolean { return true; };
        this._duration = Number(duration) || -1;
        this._timer = duration;
        this._isActive = false;
        this._eventSubscriptions = [];
    }

    /**
     * 应用Buff（每帧或事件触发时调用）
     * @param value 原始值
     * @return 修改后的值
     */
    public function apply(value:Number):Number {
        if (!_isActive) return value;
        if (_duration > 0) _timer--; // 更新计时器
        return _effect(value);
    }

    /**
     * 激活Buff（手动或通过事件）
     */
    public function activate():Void {
        _isActive = true;
        _timer = _duration;
    }

    /**
     * 使Buff失效（手动或自动到期）
     */
    public function invalidate():Void {
        _isActive = false;
        // 清理事件订阅
        for (var i:Number = 0; i < _eventSubscriptions.length; i++) {
            EventBus.getInstance().unsubscribe(_eventSubscriptions[i].event, _eventSubscriptions[i].callback);
        }
        _eventSubscriptions = [];
    }

    /**
     * 绑定事件触发条件（可选）
     * @param eventName 事件名称
     * @param condition 基于事件数据的条件函数
     */
    public function bindEventCondition(eventName:String, condition:Function):Void {
        var callback:Function = function(data:Object):Void {
            if (condition(data)) this.activate();
        }.bind(this);
        
        EventBus.getInstance().subscribe(eventName, callback, this);
        _eventSubscriptions.push({ event: eventName, callback: callback });
    }

    /**
     * 判断是否已失效（用于自动移除）
     */
    public function isExpired():Boolean {
        return _duration > 0 && _timer <= 0;
    }
}