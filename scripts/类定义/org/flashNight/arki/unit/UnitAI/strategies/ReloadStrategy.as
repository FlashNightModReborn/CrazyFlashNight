import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;
import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;

/**
 * ReloadStrategy — 换弹候选源
 *
 * 从 ActionArbiter._collectReload 提取。
 * 职责：在远程姿态 + 弹药不足时注入 Reload 候选。
 */
class org.flashNight.arki.unit.UnitAI.strategies.ReloadStrategy {

    private var p:Object;
    private var _scorer:UtilityEvaluator;

    public function ReloadStrategy(personality:Object, scorer:UtilityEvaluator) {
        this.p = personality;
        this._scorer = scorer;
    }

    public function getName():String { return "Reload"; }

    public function collect(ctx:AIContext, data:UnitAIData, out:Array, trace:DecisionTrace):Void {
        // 非远程姿态不换弹
        if (ctx.repositionDir <= 0) { trace.reject("Reload", DecisionTrace.REASON_STANCE); return; }
        // 已在换弹
        if (ctx.isAnimLocked) { trace.reject("Reload", DecisionTrace.REASON_ANIMLOCK); return; }

        var ratio:Number = _scorer.getAmmoRatio(ctx.self, ctx.attackMode);
        if (ratio >= 0.5) { trace.reject("Reload", DecisionTrace.REASON_AMMO); return; }

        // 评分：弹药越少越高 + 距离系数
        var urgency:Number = (1 - ratio);
        var safeDist:Number = (ctx.xdistance > 0) ? (ctx.xDist / ctx.xdistance) : 1;
        var distBonus:Number = (safeDist > 1) ? 0.3 : -0.2;
        var score:Number = 0.3 + urgency * 0.5 + distBonus;

        out.push({
            name: "Reload", type: "reload", priority: 2,
            commitFrames: p.reloadCommitFrames, score: score
        });
    }
}
