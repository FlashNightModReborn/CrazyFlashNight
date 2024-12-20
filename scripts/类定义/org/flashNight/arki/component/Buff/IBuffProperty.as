// org/flashNight/arki/component/Buff/IBuffProperty.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.BuffHandle.*;
interface org.flashNight.arki.component.Buff.IBuffProperty {
    /**
     * 添加一个 Buff。
     * @param buff 实现 IBuff 接口的 buff 实例
     */
    function addBuff(buff:IBuff):Void;

    /**
     * 移除一个 Buff。
     * @param buff 要移除的 buff 实例
     */
    function removeBuff(buff:IBuff):Void;

    /**
     * 清空所有 Buff。
     */
    function clearAllBuffs():Void;

    /**
     * 使缓存失效，强制重新计算 buffed 属性值。
     */
    function invalidate():Void;

    /**
     * 获取基础值（未应用 Buff 的原始值）。
     */
    function getBaseValue():Number;

    /**
     * 设置基础值（未应用 Buff 的原始值）。
     * @param value 要设置的基础值
     */
    function setBaseValue(value:Number):Void;

    /**
     * 获取当前计算后的 buffed 值。
     */
    function getBuffedValue():Number;

    /**
     * 获取属性名称。
     */
    function getPropName():String;
}
