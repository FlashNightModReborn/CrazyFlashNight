/**
 * ChargeKeyAccumulator - 按住充能 / 松开衰减 / 满则锁定 通用模型
 *
 * 标准 idiom（G111 / Jackhammer 同质化版本）：
 *   - 激活姿态下：按住 keyConst → ref.chargeCount += chargeStep（封顶 chargeCountMax）
 *                  松开 keyConst → ref.chargeCount -= chargeStep（保底 0）
 *                  达 chargeCountMax → unit.chargeComplete = true（锁定，由 caller 在射击/重置事件中清零）
 *   - 非激活姿态：强制 unit.chargeComplete = false 并继续递减
 *
 * 字段契约（caller 必须在 init 提供）：
 *   ref.chargeCount     : Number  当前充能值（init 0）
 *   ref.chargeCountMax  : Number  最大充能值
 *   ref.chargeStep      : Number  每帧充能/衰减步长
 *   unit.chargeComplete : Boolean 满充锁（init false；战技系统会读它做 gating）
 *
 * ⚠️ isActive 由 caller 判定（"长枪" / "兵器" / 其他姿态因装备而异），helper 不猜。
 * ⚠️ 视觉表达（gunFrame 推进 / 战技切换等）保留在调用方，helper 只管 charge state。
 *
 * Call sites:
 *   - G111.as            标准充能 + chargeComplete 锁
 *   - Jackhammer.as      标准充能 + chargeComplete 锁 + 战技切换
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.ChargeKeyAccumulator {

    public static function tick(ref:Object, unit:MovieClip, keyConst:Number, isActive:Boolean):Void {
        if (isActive) {
            if (_root.按键输入检测(unit, keyConst)) {
                ref.chargeCount = Math.min(ref.chargeCount + ref.chargeStep, ref.chargeCountMax);
            } else if (ref.chargeCount > 0) {
                ref.chargeCount = Math.max(ref.chargeCount - ref.chargeStep, 0);
            }
            if (ref.chargeCount >= ref.chargeCountMax) {
                unit.chargeComplete = true;
            }
        } else {
            unit.chargeComplete = false;
            if (ref.chargeCount > 0) {
                ref.chargeCount = Math.max(ref.chargeCount - ref.chargeStep, 0);
            }
        }
    }
}
