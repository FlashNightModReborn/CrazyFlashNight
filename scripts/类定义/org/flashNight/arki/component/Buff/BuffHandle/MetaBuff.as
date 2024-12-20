import org.flashNight.arki.component.Buff.BuffHandle.*
class org.flashNight.arki.component.Buff.BuffHandle.MetaBuff extends BaseBuff implements IBuff {
    private var _condition:Function;  // 条件函数
    private var _effect:Function;     // 效果函数

    /**
     * 构造函数
     * @param type Buff 的类型标志
     * @param condition 条件函数，返回 true 时生效
     * @param effect 效果函数，用于动态计算
     */
    public function MetaBuff(type:String, condition:Function, effect:Function) {
        super(type);
        this._condition = condition;
        this._effect = effect;
    }

    /**
     * 应用 buff 到一个值
     * @param value 原始值
     * @return 修改后的值
     */
    public function apply(value:Number):Number {
        if (this._condition()) {
            return this._effect(value);
        }
        return value; // 条件不满足，返回原始值
    }

    /**
     * 判断 Buff 是否为 POD 类型
     * @return false
     */
    public function isPOD():Boolean {
        return false;
    }
}
