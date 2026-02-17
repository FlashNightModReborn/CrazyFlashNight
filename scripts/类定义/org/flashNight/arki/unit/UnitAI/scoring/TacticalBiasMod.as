import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * TacticalBiasMod — 战术偏置修正
 *
 * 来源：ActionArbiter._scoreCandidates L370-378
 * 技能执行后的短期评分偏置（闪现突击/霸体冲锋/规避反击）
 */
class org.flashNight.arki.unit.UnitAI.scoring.TacticalBiasMod extends ScoringModifier {

    public function getName():String { return "TacticalBias"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        var tactical:Object = ctx.tactical;
        if (tactical == null) return 0;

        if (c.type == "attack") {
            return tactical.attackBonus;
        } else if (c.type == "skill") {
            var tb:Number = tactical.skillType[c.skill.类型];
            if (!isNaN(tb)) return tb;
        }

        return 0;
    }
}
