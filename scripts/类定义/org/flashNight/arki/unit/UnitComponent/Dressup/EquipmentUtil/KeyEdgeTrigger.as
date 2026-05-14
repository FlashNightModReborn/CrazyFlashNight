/**
 * KeyEdgeTrigger - 按键上升沿检测
 *
 * 收口"按键按下瞬间触发一次"的标准 idiom：
 *   var 按住 = _root.按键输入检测(unit, keyConst) ? true : false;
 *   var 上升沿 = 按住 && !ref[slotKey];
 *   ref[slotKey] = 按住;
 *   if (上升沿) { 触发逻辑 }
 *
 * 通过 ref[slotKey] 持久化上一帧按下状态；slotKey 由调用方显式传入避免同一 ref
 * 监听多键时的状态互冲。
 *
 * 字段 contract：
 *   ref[slotKey]  Boolean  上一帧按下状态（首次调用前应为 undefined / false；建议
 *                          在 init 期用 ref[slotKey] = _root.按键输入检测(...) ? true : false
 *                          做 edge-trigger 初始化，避免"穿装备瞬间已按住键"被误判为
 *                          上升沿）
 *
 * 返回：true 仅在 (本帧按下 && 上一帧未按下) 时；hold 期间返回 false。
 *
 * ⚠️ 仅用于 "press-once" 语义。需要 "持续按住" 行为的场景必须保留原 hold 写法，
 *    并加 // hold-trigger intentional 注释。
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.KeyEdgeTrigger {

    public static function onRise(ref:Object, unit:MovieClip, keyConst:Number, slotKey:String):Boolean {
        var pressed:Boolean = _root.按键输入检测(unit, keyConst) ? true : false;
        var rise:Boolean = pressed && !ref[slotKey];
        ref[slotKey] = pressed;
        return rise;
    }
}
