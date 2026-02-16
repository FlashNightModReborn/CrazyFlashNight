import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;

/**
 * AnimLockFilter — 动画锁期间非紧急候选过滤器
 *
 * 从 ActionArbiter.tick() 中 animLock 分支提取。
 * 职责：动画锁期间只保留 priority=0（Emergency）候选。
 */
class org.flashNight.arki.unit.UnitAI.strategies.AnimLockFilter {

    public function AnimLockFilter() {}

    public function filter(ctx:AIContext, candidates:Array, trace:DecisionTrace):Void {
        if (!ctx.isAnimLocked) return;
        for (var i:Number = candidates.length - 1; i >= 0; i--) {
            if (candidates[i].priority > 0) {
                trace.reject(candidates[i].name, DecisionTrace.REASON_ANIMLOCK);
                candidates.splice(i, 1);
            }
        }
    }
}
