/**
 * MuzzleWorldShoot - 枪口/刀口世界坐标 → 子弹 shoot 三元组写入
 *
 * 把"刀口 local → world → gameworld local → 写 shootX/Y/Z"的固定 7 行块封装为单行：
 *
 *   不带 offset（如死者之手）：
 *     MuzzleWorldShoot.populate(刀口, 自机, 子弹属性);
 *
 *   带方向 offset（如初期特效周期）：
 *     MuzzleWorldShoot.populate(刀口, 自机, 子弹属性, xOffset, yOffset, 身高修正比);
 *
 * 后三参 undefined 时跳过 offset。方向乘法 (自机.方向 === "左" ? -1 : 1) 内置。
 *
 * 不适用："myPoint" 写 target._y 给 shootY/Z 的变体（吉他喷火/键盘镰刀），或带
 * 转换中间y 中间存储的复杂变体（剑圣胸甲）— 它们是不同意图，保留原 inline 实现。
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.MuzzleWorldShoot {

    public static function populate(刀口:MovieClip, 自机:MovieClip, 子弹属性:Object, xOffset, yOffset, 身高修正比):Void {
        var 坐标:Object = {x:刀口._x, y:刀口._y};
        刀口._parent.localToGlobal(坐标);
        _root.gameworld.globalToLocal(坐标);
        if (xOffset != undefined) {
            坐标.x += (自机.方向 === "左" ? -1 : 1) * xOffset * 身高修正比;
            坐标.y += yOffset * 身高修正比;
        }
        子弹属性.shootX = 坐标.x;
        子弹属性.shootY = 坐标.y;
        子弹属性.shootZ = 自机.Z轴坐标;
    }
}