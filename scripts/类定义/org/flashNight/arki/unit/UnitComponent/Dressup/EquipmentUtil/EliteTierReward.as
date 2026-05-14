/**
 * EliteTierReward - 敌人精英等级 → 分级奖励值解析
 *
 * 标准 idiom：
 *   var eliteLevel:Number = UnitUtil.getEliteLevel(hitTarget);
 *   var level:Number = Math.max(0, eliteLevel);
 *   switch (level) {
 *       case 1: rewardValue = eliteReward; break;
 *       case 2: rewardValue = bossReward; break;
 *       default: rewardValue = normalReward;
 *   }
 *
 * 当前 call sites（2 + 后续铺开）：
 *   - GM6_LYNX.as            子弹奖励 (shot 计数)
 *   - 等离子切割机.as        回血百分比
 *
 * 行为约定（保持原 idiom 不变）：
 *   - level 0（普通）/ 负数（getEliteLevel 返回 <0 已被 Math.max 钳成 0）→ normalReward
 *   - level 1（精英）→ eliteReward
 *   - level 2（首领）→ bossReward
 *   - level >= 3（异常或未来扩展）→ normalReward（switch default 兜底，与原 idiom 一致）
 *
 * ⚠️ 纯计算静态方法，不维护 combo / window / cooldown 等 state。需要这些状态的
 *    复杂奖励模型（如剑圣胸甲的 dual-coefficient + comboCount）请保留独立实现，
 *    不要塞进本工具。
 */
import org.flashNight.arki.unit.UnitUtil;

class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EliteTierReward {

    public static function resolve(hitTarget:MovieClip, normalReward:Number, eliteReward:Number, bossReward:Number):Number {
        var level:Number = Math.max(0, UnitUtil.getEliteLevel(hitTarget));
        switch (level) {
            case 1: return eliteReward;
            case 2: return bossReward;
            default: return normalReward;
        }
    }
}
