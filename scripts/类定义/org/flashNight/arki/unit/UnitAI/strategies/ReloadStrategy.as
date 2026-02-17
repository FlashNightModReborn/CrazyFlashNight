import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;
import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;

/**
 * ReloadStrategy — 换弹候选源
 *
 * 从 ActionArbiter._collectReload 提取。
 * 职责：在远程姿态 + 弹药不足时注入 Reload 候选。
 *
 * 技能换弹（翻滚换弹等）：
 *   当单位拥有 功能=="换弹" 的技能且可用时，作为 skill 类型候选注入。
 *   高经验单位强烈偏好技能换弹（评分加成），低经验单位退化为普通换弹。
 *   技能换弹走 _scoreCandidates 评分管线，额外获得弹药紧迫度加成。
 */
class org.flashNight.arki.unit.UnitAI.strategies.ReloadStrategy {

    private var p:Object;
    private var _scorer:UtilityEvaluator;

    public function ReloadStrategy(personality:Object, scorer:UtilityEvaluator) {
        this.p = personality;
        this._scorer = scorer;
    }

    public function getName():String { return "Reload"; }

    public function collect(ctx:AIContext, data:UnitAIData, out:Array, trace:DecisionTrace):Void {
        // 非远程姿态不换弹
        if (ctx.repositionDir <= 0) { trace.reject("Reload", DecisionTrace.REASON_STANCE); return; }
        // 已在换弹
        if (ctx.isAnimLocked) { trace.reject("Reload", DecisionTrace.REASON_ANIMLOCK); return; }

        var ratio:Number = ctx.ammoRatio;
        if (isNaN(ratio)) ratio = _scorer.getAmmoRatio(ctx.self, ctx.attackMode);
        if (ratio >= 0.5) { trace.reject("Reload", DecisionTrace.REASON_AMMO); return; }

        // 评分：弹药越少越高 + 距离系数
        var urgency:Number = (1 - ratio);
        var safeDist:Number = (ctx.xdistance > 0) ? (ctx.xDist / ctx.xdistance) : 1;
        var distBonus:Number = (safeDist > 1) ? 0.3 : -0.2;
        var score:Number = 0.3 + urgency * 0.5 + distBonus;

        // ── 技能换弹（翻滚换弹等）──
        // 高经验→优先使用技能换弹（带闪避/增益的换弹方式）
        var sk:Object = _findReloadSkill(ctx);
        if (sk != null) {
            out.push({
                name: sk.技能名, type: "skill", priority: 1,
                skill: sk, commitFrames: p.skillCommitFrames, score: 0
            });
        }

        // 普通换弹（兜底，始终注入）
        out.push({
            name: "Reload", type: "reload", priority: 2,
            commitFrames: p.reloadCommitFrames, score: score
        });
    }

    /**
     * _findReloadSkill — 查找可用的技能换弹（功能=="换弹"）
     *
     * 条件：已学 + CD 就绪 + 距离匹配
     * 返回第一个匹配的技能对象，无匹配返回 null
     */
    private function _findReloadSkill(ctx:AIContext):Object {
        var skills:Array = ctx.self.已学技能表;
        if (skills == null) return null;

        var nowMs:Number = ctx.nowMs;
        var xDist:Number = ctx.xDist;

        for (var i:Number = 0; i < skills.length; i++) {
            var sk:Object = skills[i];
            if (sk.功能 != "换弹") continue;
            if (xDist < sk.距离min || xDist > sk.距离max) continue;
            if (!isNaN(sk.上次使用时间) && (nowMs - sk.上次使用时间 <= sk.冷却 * 1000)) continue;
            return sk;
        }
        return null;
    }
}
