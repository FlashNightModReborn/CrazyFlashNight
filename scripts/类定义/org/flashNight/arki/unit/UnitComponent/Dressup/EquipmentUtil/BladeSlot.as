/**
 * BladeSlot - 刀口位置 slot name 常量
 *
 * 项目术语：装备 dressup 子级 MovieClip 命名为 "刀口位置1".."刀口位置5"，
 * 用于子弹生成定位、特效触发等。本类只承载字面量常量，主要用户是
 * _root.装备生命周期函数 系列的 paramObj 默认值。
 *
 * 注意：普通 dot-notation 访问（如 saber.刀口位置3）保持原样，
 * 不应替换为 SLOT_N — 编译期成员访问 → 运行期动态查找是性能退化。
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.BladeSlot {

    public static var SLOT_1:String = "刀口位置1";
    public static var SLOT_2:String = "刀口位置2";
    public static var SLOT_3:String = "刀口位置3";
    public static var SLOT_4:String = "刀口位置4";
    public static var SLOT_5:String = "刀口位置5";
}