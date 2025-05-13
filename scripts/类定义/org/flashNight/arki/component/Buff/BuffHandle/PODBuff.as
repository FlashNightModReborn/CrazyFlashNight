import org.flashNight.arki.component.Buff.BuffHandle.*;

// PODBuff.as（抽象基类）
class org.flashNight.arki.component.Buff.BuffHandle.PODBuff extends BaseBuff implements IBuff {
    private var _value:Number;

    public function PODBuff(type:String, value:Number) {
        super(type);
        this._value = value;
    }

    // 子类必须实现具体计算逻辑
    public function apply(value:Number):Number {
        throw new Error("PODBuff.apply() must be overridden!");
        return 0;
    }

    // 标记为POD类型
    public function isPOD():Boolean {
        return true;
    }
}