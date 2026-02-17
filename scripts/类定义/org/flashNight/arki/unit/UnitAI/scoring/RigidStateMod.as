import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * RigidStateMod — 刚体状态感知
 *
 * 来源：ActionArbiter._scoreCandidates L380-389
 * 刚体期间：增益技能重惩罚 -0.8，普攻加成 +0.15，非躲避技能轻加成 +0.1
 */
class org.flashNight.arki.unit.UnitAI.scoring.RigidStateMod extends ScoringModifier {

    public function getName():String { return "RigidState"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        if (!ctx.isRigid) return 0;

        if (c.type == "skill" && c.skill.功能 == "增益") {
            return -0.8;
        } else if (c.type == "attack") {
            return 0.15;
        } else if (c.type == "skill") {
            if (c.skill.功能 != "躲避") return 0.1;
        }

        return 0;
    }
}
