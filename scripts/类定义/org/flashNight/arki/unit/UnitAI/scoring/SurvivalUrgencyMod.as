import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * SurvivalUrgencyMod — 受创紧迫 + 包围状态联合修正
 *
 * 来源：ActionArbiter._scoreCandidates L442-471
 *
 * 受创紧迫（retreat urgency）：
 *   躲避 +urgency*0.8, 位移 +urgency*0.6, 解围霸体 +urgency*1.2, 增益 +urgency*0.4
 *
 * 包围度（encirclement）：
 *   解围霸体 +enc*(0.5+勇气), 高勇气近战 +enc*勇气*0.3
 */
class org.flashNight.arki.unit.UnitAI.scoring.SurvivalUrgencyMod extends ScoringModifier {

    public function getName():String { return "SurvivalUrgency"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        if (c.type != "skill") return 0;

        var delta:Number = 0;
        var func:String = c.skill.功能;

        // ── 受创紧迫度 → 提升逃脱/防御技能评分（求生本能）──
        var urgency:Number = ctx.retreatUrgency;
        if (urgency > 0.15) {
            if (func == "躲避") {
                delta += urgency * 0.8;
            } else if (func == "位移" || func == "高频位移") {
                delta += urgency * 0.6;
            } else if (func == "解围霸体") {
                delta += urgency * 1.2;
            } else if (func == "增益") {
                delta += urgency * 0.4;
            }
        }

        // ── 包围状态 → 高勇气主动解围，低勇气求生已通过 retreatUrgency 放大 ──
        var enc:Number = ctx.encirclement;
        if (enc > 0.2) {
            var cour:Number = p.勇气;
            if (func == "解围霸体") {
                // 被围 + 高勇气 → 强烈偏好解围霸体（AoE 清场）
                delta += enc * (0.5 + cour * 1.0);
            } else if (cour > 0.4) {
                // 高勇气近战：被围时更主动出击
                var skillType:String = c.skill.类型;
                if (skillType == "格斗" || skillType == "刀技") {
                    delta += enc * cour * 0.3;
                }
            }
        }

        // ── S7: 角落激进模式 → 被逼入角落时提升解围/击退，抑制位移/躲避 ──
        // 逃不掉就不该逃 — 转为主动解围、击退敌人创造空间
        var ca:Number = ctx.corneredAggression;
        if (ca > 0.1) {
            if (func == "解围霸体") {
                // 角落下强烈偏好解围霸体（震地/气动波/霸体破围）
                delta += ca * 1.5;
            } else if (func == "击退") {
                // 击退技能把敌人推开，创造脱困空间
                delta += ca * 1.0;
            } else if (func == "躲避" || func == "位移" || func == "高频位移") {
                // 角落里闪避/位移效果差（无处可闪），抑制评分
                delta -= ca * 0.5;
            }
        }

        return delta;
    }
}
