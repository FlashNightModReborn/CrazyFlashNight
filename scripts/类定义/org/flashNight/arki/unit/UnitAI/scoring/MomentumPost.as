import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * MomentumPost — 反抖动后处理（跨候选二次遍历）
 *
 * 来源：ActionArbiter._scoreCandidates L480-493
 * - 同类动作惯性：维持当前动作类型 +0.1*(1-momentumDecay)
 * - 重复技能惩罚：连续使用同名技能 -0.08*(repeatCount+1)
 *
 * 通过共享 jitterState 对象读取 ActionArbiter 的反抖动状态。
 * jitterState = { lastActionType, lastSkillName, repeatCount }
 */
class org.flashNight.arki.unit.UnitAI.scoring.MomentumPost extends ScoringModifier {

    private var _js:Object; // jitterState (shared reference, ActionArbiter writes)

    public function MomentumPost(jitterState:Object) {
        this._js = jitterState;
    }

    public function getName():String { return "Momentum"; }

    public function end(candidates:Array, ctx, p:Object, scratch:Object):Void {
        var momentumDecay:Number = p.momentumDecay;
        var lastType:String = _js.lastActionType;
        var lastName:String = _js.lastSkillName;
        var repeatCount:Number = _js.repeatCount;

        for (var k:Number = 0; k < candidates.length; k++) {
            var ca:Object = candidates[k];
            if (ca.type == "continue" || ca.type == "reload" || ca.type == "preBuff") continue;

            if (ca.type == lastType) {
                ca.score += 0.1 * (1 - momentumDecay);
            }
            if (ca.type == "skill" && ca.name == lastName) {
                ca.score -= 0.08 * (repeatCount + 1);
            }
        }
    }
}
