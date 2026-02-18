import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;

/**
 * CrowdAwarenessMod — 群攻意识评分修正器（T2-C）
 *
 * 复用 ActionArbiter 周期性采样的 ctx.nearbyCount（150px 范围内敌人数），
 * 不再独立调用 TargetCacheManager，避免多 AI 同屏时重复扫描。
 *
 * 敌人密集时：
 *   - 技能候选整体加分（技能多有AOE/范围性质）
 *   - 高密度下站桩普攻减分（应该用技能清场）
 */
class org.flashNight.arki.unit.UnitAI.scoring.CrowdAwarenessMod extends ScoringModifier {

    private var _nearbyCount:Number;

    public function CrowdAwarenessMod() {
        _nearbyCount = 0;
    }

    public function getName():String { return "CrowdAwareness"; }

    public function begin(ctx, data, scratch:Object):Void {
        // 直接读取 AIContext 预计算值（ActionArbiter 每 16 帧采样一次）
        _nearbyCount = ctx.nearbyCount;
    }

    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        if (_nearbyCount < 3) return 0; // 敌人不密集，不干预

        // 对技能候选：敌人密集时整体加分（技能多有AOE性质）
        if (c.type == "skill" && c.skill != null) {
            return (_nearbyCount - 2) * 0.15; // 每多一个敌人 +0.15
        }
        // 敌人高密度时，站桩普攻减分（应该用技能清场）
        if (c.type == "attack" && _nearbyCount >= 5) {
            return -0.2;
        }
        return 0;
    }
}
