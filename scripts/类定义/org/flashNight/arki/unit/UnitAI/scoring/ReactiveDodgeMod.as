import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * ReactiveDodgeMod — 反应性躲避
 *
 * 来源：ActionArbiter._scoreCandidates L411-414
 * 被攻击时躲避技能 +0.5
 */
class org.flashNight.arki.unit.UnitAI.scoring.ReactiveDodgeMod extends ScoringModifier {

    public function getName():String { return "ReactiveDodge"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        if (c.type == "skill" && c.skill.功能 == "躲避" && ctx.underFire) {
            return 0.5;
        }
        return 0;
    }
}
