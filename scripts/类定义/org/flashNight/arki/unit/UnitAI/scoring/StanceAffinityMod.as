import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * StanceAffinityMod — Stance 候选加成
 *
 * 来源：ActionArbiter._scoreCandidates L352-368
 * - attack: +stance.attackBonus
 * - skill:  +stance.skillAffinity[类型]
 * - 手雷距离窗口: optDistMin/Max 内 +0.3，外 -0.15
 */
class org.flashNight.arki.unit.UnitAI.scoring.StanceAffinityMod extends ScoringModifier {

    public function getName():String { return "StanceAffinity"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        var stance:Object = ctx.stance;
        if (stance == null) return 0;

        var delta:Number = 0;

        if (c.type == "attack") {
            delta += stance.attackBonus;
        } else if (c.type == "skill") {
            var aff:Number = stance.skillAffinity[c.skill.类型];
            if (!isNaN(aff)) delta += aff;

            if (stance.optDistMin != undefined) {
                var xDist:Number = ctx.xDist;
                if (xDist >= stance.optDistMin && xDist <= stance.optDistMax) {
                    delta += 0.3;
                } else {
                    delta -= 0.15;
                }
            }
        }

        return delta;
    }
}
