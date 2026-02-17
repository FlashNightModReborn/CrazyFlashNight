import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.ActionExecutor;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;

/**
 * InterruptFilter — 中断规则过滤器
 *
 * 从 ActionArbiter._filterByInterrupt 提取。
 * 职责：根据 ActionExecutor 的 canInterruptBody 规则过滤候选。
 * trace 输出 lockSource 供诊断。
 */
class org.flashNight.arki.unit.UnitAI.strategies.InterruptFilter {

    private var _executor:ActionExecutor;

    public function InterruptFilter(executor:ActionExecutor) {
        this._executor = executor;
    }

    public function filter(ctx:AIContext, candidates:Array, trace:DecisionTrace):Void {
        var lockSrc:String = ctx.lockSource;
        var frame:Number = ctx.frame;
        for (var i:Number = candidates.length - 1; i >= 0; i--) {
            if (!_executor.canInterruptBody(candidates[i].type, candidates[i].priority, frame)) {
                trace.reject(candidates[i].name,
                    DecisionTrace.REASON_INTERRUPT + (lockSrc != null ? ":" + lockSrc : ""));
                candidates.splice(i, 1);
            }
        }
    }
}
