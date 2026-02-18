import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * ComboDepthMod — 连招深度评分修正器（T1-C）
 *
 * 利用 AIContext.consecutiveAttacks 信号：
 *   连招深度超过阈值后，鼓励脱离（闪避/位移加分），抑制继续普攻。
 *   阈值受勇气调节：高勇气角色打更深的连段再脱离。
 *
 * 设计意图：
 *   "打完就走"模式 — 避免站桩无限平A，迫使AI在连段后主动撤出。
 *   配合 Retreating 状态形成"进攻→脱离→重整→再进攻"的攻防节奏。
 */
class org.flashNight.arki.unit.UnitAI.scoring.ComboDepthMod extends ScoringModifier {

    public function getName():String { return "ComboDepth"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        var depth:Number = ctx.consecutiveAttacks;
        if (isNaN(depth) || depth < 3) return 0; // 连招未达深度，不干预

        // 连招深度阈值受勇气调节：高勇气打更深
        var courage:Number = (p != null && !isNaN(p.勇气)) ? p.勇气 : 0;
        var threshold:Number = 3 + Math.floor(courage * 3); // 3~6
        if (depth < threshold) return 0;

        // 超过阈值：鼓励脱离（"打完就走"模式）
        var overshoot:Number = depth - threshold;

        if (c.type == "skill" && c.skill != null) {
            var func:String = c.skill.功能;
            if (func == "躲避" || func == "位移") {
                return overshoot * 0.2; // 闪避/位移加分
            }
        }
        if (c.type == "attack") {
            return -overshoot * 0.1; // 继续平A减分
        }
        return 0;
    }
}
