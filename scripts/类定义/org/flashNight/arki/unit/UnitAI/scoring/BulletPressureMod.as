import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * BulletPressureMod — 射弹压迫评分修正
 *
 * 当 AIContext.bulletThreat > 0 时（有子弹接近），
 * 提升躲避/位移技能评分，压制站桩平A评分。
 *
 * 设计原则（Dave Mark Utility AI + DOOM push-forward）：
 *
 *   C. 有界响应曲线（防止评分极化）
 *      pressure = 1 - 1/(1 + btCount*0.25)  — 渐近饱和
 *      btCount=3 → 0.43, btCount=7 → 0.64, btCount=20 → 0.83, btCount=50 → 0.93
 *      对比原线性: btCount=7 时已饱和到 1.0
 *
 *   B. Maslow 层级：弹压下换弹 = 求生（空枪 = 零战力）
 *      ammoRatio < 0.3 时 Reload 获得弹压加成，而非被忽略
 *
 *   D. 背水一战：retreatUrgency > 0.8 时 attack 惩罚翻转为微正
 *      防止候选池评分全面崩塌 → 呆滞
 */
class org.flashNight.arki.unit.UnitAI.scoring.BulletPressureMod extends ScoringModifier {

    public function getName():String { return "BulletPressure"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        if (ctx.bulletThreat == 0) return 0;

        // C: 有界响应曲线（渐近饱和，取代 min(1, btCount*0.15)）
        var pressure:Number = 1 - 1 / (1 + ctx.bulletThreat * 0.25);
        var etaFactor:Number = Math.max(0, 1 - ctx.bulletETA / 15);
        var combined:Number = pressure * etaFactor;
        if (combined <= 0) return 0;

        // 躲避/位移技能加分
        if (c.type == "skill") {
            var fn:String = c.skill.功能;
            if (fn == "躲避")     return combined * 1.0;
            if (fn == "位移")     return combined * 0.7;
            if (fn == "解围霸体") return combined * 0.4;
        }

        // B: 弹压下换弹紧急度（空枪 = 求生：弹药越低加成越强）
        if (c.type == "reload") {
            var ammoR:Number = ctx.ammoRatio;
            if (!isNaN(ammoR) && ammoR < 0.3) {
                return combined * (1 - ammoR) * 1.5;
            }
            return 0;
        }

        // D: 背水一战 — 高紧迫+弹压下攻击保底（防止候选池全面崩塌→呆滞）
        if (c.type == "attack") {
            if (ctx.retreatUrgency > 0.8) {
                return combined * 0.15; // 绝境：惩罚翻转为微正
            }
            return -combined * 0.2;
        }

        return 0;
    }
}
