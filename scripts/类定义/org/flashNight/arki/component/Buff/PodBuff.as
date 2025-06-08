// org/flashNight/arki/component/Buff/PodBuff.as
import org.flashNight.arki.component.Buff.*;

class org.flashNight.arki.component.Buff.PodBuff implements IBuff {
    private var _id:String;
    private var _targetProperty:String;    // 修饰属性
    private var _calculationType:String;   // 计算种类
    private var _value:Number;             // 数值
    private var _priority:Number;          // 优先级
    private var _duration:Number;          // 持续时间（-1为永久）
    private var _startTime:Number;         // 开始时间
    private var _dataContainer:Object;     // 数据区
    private var _active:Boolean;
    
    public function PodBuff(
        id:String,
        targetProperty:String, 
        calculationType:String,
        value:Number,
        priority:Number,
        duration:Number
    ) {
        this._id = id;
        this._targetProperty = targetProperty;
        this._calculationType = calculationType;
        this._value = value;
        this._priority = priority || 0;
        this._duration = duration || -1;
        this._startTime = getTimer();
        this._dataContainer = {};
        this._active = true;
    }
    
    /**
     * PodBuff的applyEffect实现：简单直接的数值贡献
     */
    public function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void {
        if (!this.isActive()) return;
        
        // 检查是否影响当前属性
        if (this._targetProperty != context.propertyName) return;
        
        // 简单直接：将自己的数值贡献给计算器
        calculator.addModification(this._calculationType, this._value, this._priority);
    }
    
    public function getId():String {
        return this._id;
    }
    
    public function getType():String {
        return "PodBuff";
    }
    
    public function isActive():Boolean {
        if (!this._active) return false;
        
        // 检查时效性
        if (this._duration > 0) {
            var elapsed:Number = getTimer() - this._startTime;
            if (elapsed >= this._duration) {
                this._active = false;
                return false;
            }
        }
        
        return true;
    }
    
    public function destroy():Void {
        this._active = false;
        this._dataContainer = null;
    }
    
    // 数据区访问接口
    public function setData(key:String, value):Void {
        this._dataContainer[key] = value;
    }
    
    public function getData(key:String) {
        return this._dataContainer[key];
    }
    
    // Getter/Setter
    public function getValue():Number { return this._value; }
    public function setValue(value:Number):Void { this._value = value; }
    
    public function getTargetProperty():String { return this._targetProperty; }
    public function getCalculationType():String { return this._calculationType; }
}