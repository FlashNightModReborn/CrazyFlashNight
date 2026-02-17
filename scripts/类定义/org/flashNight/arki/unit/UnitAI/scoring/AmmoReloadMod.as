import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * AmmoReloadMod — 技能换弹加成
 *
 * 来源：ActionArbiter._scoreCandidates L416-424
 * 功能==换弹 的技能：弹药低 + 经验高 → 强烈偏好技能换弹
 * 经验=1 弹药=0%: +1.5；经验=0 弹药=0%: +0.3
 */
class org.flashNight.arki.unit.UnitAI.scoring.AmmoReloadMod extends ScoringModifier {

    public function getName():String { return "AmmoReload"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        if (c.type != "skill" || c.skill.功能 != "换弹") return 0;

        var ammoR:Number = ctx.ammoRatio;
        if (isNaN(ammoR) || ammoR < 0.5) {
            var ammoUrgency:Number = isNaN(ammoR) ? 1 : (1 - ammoR);
            return ammoUrgency * (0.3 + (p.经验 || 0) * 1.2);
        }

        return 0;
    }
}
