import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * BulletPressureMod — 射弹压迫评分修正
 *
 * 当 AIContext.bulletThreat > 0 时（有子弹接近），
 * 提升躲避/位移技能评分，降低站桩平A评分。
 * 压迫强度 = 子弹数量 × ETA紧迫度。
 */
class org.flashNight.arki.unit.UnitAI.scoring.BulletPressureMod extends ScoringModifier {

    public function getName():String { return "BulletPressure"; }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        if (ctx.bulletThreat == 0) return 0;

        // 压迫强度：子弹越多越强，ETA越短越强
        var pressure:Number = Math.min(1, ctx.bulletThreat * 0.15);
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

        // 站桩平A减分（鼓励走位/释放技能）
        if (c.type == "attack") return -combined * 0.2;

        return 0;
    }
}
