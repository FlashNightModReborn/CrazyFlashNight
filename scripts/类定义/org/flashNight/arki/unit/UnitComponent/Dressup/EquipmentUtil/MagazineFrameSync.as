/**
 * MagazineFrameSync - 弹匣视觉帧同步 + 激光模组显隐
 *
 * 抽离 P90 / AR57 同模板：
 *   - init: 从装备数据读 capacity → 计算 bulletRate (capacity/50)
 *   - apply: 每帧读 shot → 算 bulletFrame 跳到弹匣对应帧 + 按 modeObject/攻击模式
 *           控制激光模组显隐
 *
 * 字段 contract（调用方 init 时种好）：
 *   ref.自机                MovieClip 持有者
 *   ref.装备类型            String    装备槽位名
 *   ref.gunString           String    枪 MC 容器名（"<装备类型>_引用"）
 *   ref.modeObject          Object    { 攻击模式名: true } 白名单
 *   ref.bulletRate          Number    由 init 写入
 *
 * 设计选择（与 plan §K11 略简化）：
 *   - 不外参 modeObject / laserFieldName。modeObject 已在 ref 上，重复传成本无收益；
 *     "激光模组" 是项目跨装备的 canonical 字段名（grep 26+ 文件均用此名）
 *   - 未来若有装备激光字段名不同，再外参化
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.MagazineFrameSync {

    public static function init(ref:Object):Void {
        var target:MovieClip = ref.自机;
        var equipmentData:Object = target[ref.装备类型 + "属性"];
        var capacity:Number = equipmentData.capacity > 0 ? equipmentData.capacity : 50;
        ref.bulletRate = capacity / 50;
    }

    public static function apply(ref:Object):Void {
        var target:MovieClip = ref.自机;
        var gun:MovieClip = target[ref.gunString];
        if (!gun) return;

        var bulletFrame:Number = Math.floor(target[ref.装备类型].value.shot / ref.bulletRate) + 1;
        gun.弹匣.gotoAndStop(bulletFrame);

        gun.激光模组._visible = !!ref.modeObject[target.攻击模式];
    }
}
