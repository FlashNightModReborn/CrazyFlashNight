/**
 * EquipmentTick - 装备周期开场 helper
 *
 * 32 个装备脚本周期函数顶部共用同一对开场调用：
 *   _root.装备生命周期函数.移除异常周期函数(ref);
 *   if (!VisualSync.beginTick(ref)) return;
 * 此类合并为单行 if (!EquipmentTick.open(ref)) return;
 *
 * 不并入 VisualSync — VisualSync 只负责同帧 tick dedup，不耦合异常清理。
 */
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.VisualSync;

class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentTick {

    public static function open(ref:Object):Boolean {
        _root.装备生命周期函数.移除异常周期函数(ref);
        return VisualSync.beginTick(ref);
    }

    /**
     * 仅 cleanup 不 dedup — 用于无 visual sync 的装备（背景物件 / buff 类 / delegate
     * 到通用 helper 的 thin wrapper 等）。语义等价于裸调
     * _root.装备生命周期函数.移除异常周期函数(ref) 的单行替换。
     */
    public static function cleanup(ref:Object):Void {
        _root.装备生命周期函数.移除异常周期函数(ref);
    }
}