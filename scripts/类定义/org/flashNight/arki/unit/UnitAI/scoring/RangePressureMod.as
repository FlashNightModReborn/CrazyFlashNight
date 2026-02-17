import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * RangePressureMod — 距离压力（远程被近身）
 *
 * 来源：ActionArbiter._scoreCandidates L391-409
 * 远程姿态下被近身时：躲避/位移加分，普攻被压减分
 * rangePressure = (1 - xDist/xdistance) * (1 - 勇气)
 */
class org.flashNight.arki.unit.UnitAI.scoring.RangePressureMod extends ScoringModifier {

    public function getName():String { return "RangePressure"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        var stance:Object = ctx.stance;
        if (stance == null || stance.repositionDir <= 0) return 0;

        var xDist:Number = ctx.xDist;
        var xdistance:Number = ctx.xdistance;
        if (xDist >= xdistance) return 0;

        var rangePressure:Number = (1 - xDist / xdistance) * (1 - p.勇气);
        var delta:Number = 0;

        if (c.type == "skill") {
            var rpFunc:String = c.skill.功能;
            if (rpFunc == "躲避") {
                if (ctx.underFire || xDist < xdistance * 0.4) {
                    delta = rangePressure * 0.25;
                }
            } else if (rpFunc == "位移" || rpFunc == "高频位移") {
                delta = rangePressure * 0.4;
            }
        } else if (c.type == "attack") {
            if (ctx.underFire) {
                delta = -rangePressure * 0.15;
            }
        }

        return delta;
    }
}
