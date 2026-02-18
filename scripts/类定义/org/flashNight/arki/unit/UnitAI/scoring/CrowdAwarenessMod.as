import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/**
 * CrowdAwarenessMod — 群攻意识评分修正器（T2-C）
 *
 * 周期性检测附近敌人密度（16帧一次，复用 TargetCacheManager 缓存）。
 * 敌人密集时：
 *   - 技能候选整体加分（技能多有AOE/范围性质）
 *   - 高密度下站桩普攻减分（应该用技能清场）
 *
 * 设计意图：
 *   1v10 场景中，AI 应在敌人聚团时优先释放技能而非普攻。
 *   通过温和的评分偏移引导技能选择，不硬编码技能判定。
 */
class org.flashNight.arki.unit.UnitAI.scoring.CrowdAwarenessMod extends ScoringModifier {

    private var _lastClusterCheck:Number;
    private var _nearbyCount:Number;

    public function CrowdAwarenessMod() {
        _lastClusterCheck = -999;
        _nearbyCount = 0;
    }

    public function getName():String { return "CrowdAwareness"; }

    public function begin(ctx, data, scratch:Object):Void {
        // 周期性检测附近敌人密度（16帧一次）
        if (ctx.frame - _lastClusterCheck >= 16) {
            _lastClusterCheck = ctx.frame;
            _nearbyCount = TargetCacheManager.getEnemyCountInRange(
                data.self, 16, 150, 150, true
            );
        }
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
