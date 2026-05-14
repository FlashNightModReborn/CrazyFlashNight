/**
 * WeaponAnimationTarget - 武器动画 MovieClip 深路径解析 helper
 *
 * 解决 reflector.自机[reflector.config.instanceContainer][reflector.animationTarget]
 * 的可读性与重复书写问题。纯解析，无副作用。
 *
 * 不并入 VisualSync — VisualSync 只管同帧 tick dedup，与"动画目标解析"职责正交。
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.WeaponAnimationTarget {

    public static function resolve(反射对象:Object):MovieClip {
        return 反射对象.自机[反射对象.config.instanceContainer][反射对象.animationTarget];
    }
}