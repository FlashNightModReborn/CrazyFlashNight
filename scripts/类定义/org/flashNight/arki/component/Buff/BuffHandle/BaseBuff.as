import org.flashNight.arki.component.Buff.BuffHandle.IBuff;

class org.flashNight.arki.component.Buff.BuffHandle.BaseBuff implements IBuff {
    private var _type:String;

    /**
     * 构造函数
     * @param type Buff 的类型标志
     */
    public function BaseBuff(type:String) {
        this._type = type;
        // 基类 buff 构造逻辑
    }

    /**
     * 获取 Buff 的类型标志
     * @return Buff 类型标志
     */
    public function getType():String {
        return this._type;
    }

    /**
     * 应用 buff 到一个值
     * @param value 原始值
     * @return 修改后的值
     */
    public function apply(value:Number):Number {
        // 子类需实现
        return value;
    }

    /**
     * 使 buff 的缓存失效
     */
    public function invalidate():Void {
        // 子类需实现
    }

    /**
     * 判断 Buff 是否为 POD 类型
     * 子类需覆盖此方法
     */
    public function isPOD():Boolean {
        return false;
    }
}
