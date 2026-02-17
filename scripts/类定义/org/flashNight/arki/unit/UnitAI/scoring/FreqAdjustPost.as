import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * FreqAdjustPost — 频率校正后处理
 *
 * 来源：ActionArbiter._scoreCandidates L495-504
 * freqAdjust = T * ln(effectiveInterval / 16)
 * 仅加到 skill 候选上，标准化不同 tick 间隔下的技能使用频率
 */
class org.flashNight.arki.unit.UnitAI.scoring.FreqAdjustPost extends ScoringModifier {

    public function getName():String { return "FreqAdjust"; }

    public function end(candidates:Array, ctx, p:Object, scratch:Object):Void {
        var effectiveInterval:Number = p.chaseCommitment * p.tickInterval;
        if (isNaN(effectiveInterval) || effectiveInterval < 1) effectiveInterval = 1;
        var T:Number = scratch.T;
        var freqAdjust:Number = T * Math.log(effectiveInterval / 16);

        for (var fa:Number = 0; fa < candidates.length; fa++) {
            if (candidates[fa].type == "skill") {
                candidates[fa].score += freqAdjust;
            }
        }
    }
}
