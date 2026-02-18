import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;

/**
 * AnimLockFilter — 动画锁期间非紧急候选过滤器
 *
 * 从 ActionArbiter.tick() 中 animLock 分支提取。
 * 职责：
 *   - 技能期：仅保留 skill/preBuff（实现“只有技能才能取消技能”）
 *   - 换弹期：仅保留 priority=0（Emergency）候选
 */
class org.flashNight.arki.unit.UnitAI.strategies.AnimLockFilter {

    public function AnimLockFilter() {}

    public function filter(ctx:AIContext, candidates:Array, trace:DecisionTrace):Void {
        if (!ctx.isAnimLocked) return;

        // 通过 ctx.lockSource 判断锁定类型（单一真相源，不再直接读 self）
        var lockSrc:String = ctx.lockSource;
        var isReloadAnim:Boolean = (lockSrc == "ANIM_RELOAD");
        var isSkillAnim:Boolean = (lockSrc == "ANIM_SKILL");

        // 技能期：仅允许技能取消技能（skill/preBuff）；其他动作必须等待技能结束
        if (isSkillAnim && !isReloadAnim) {
            for (var si:Number = candidates.length - 1; si >= 0; si--) {
                var c:Object = candidates[si];
                if (c.type != "skill" && c.type != "preBuff") {
                    trace.reject(c.name, DecisionTrace.REASON_ANIMLOCK);
                    candidates.splice(si, 1);
                }
            }
            return;
        }

        // 换弹期：保留旧规则（仅紧急 priority=0 允许抢断）
        for (var i:Number = candidates.length - 1; i >= 0; i--) {
            if (candidates[i].priority > 0) {
                trace.reject(candidates[i].name, DecisionTrace.REASON_ANIMLOCK);
                candidates.splice(i, 1);
            }
        }
    }
}
