import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;

/**
 * OffenseStrategy — 攻击候选源（技能 + 平A）
 *
 * 从 ActionArbiter._collectOffense 提取。
 * 职责：生成 BasicAttack + 技能候选（距离/冷却/buff 初级过滤）。
 * 不做评分（评分保持集中在 Arbiter 的 _scoreCandidates）。
 */
class org.flashNight.arki.unit.UnitAI.strategies.OffenseStrategy {

    private var p:Object;

    public function OffenseStrategy(personality:Object) {
        this.p = personality;
    }

    public function getName():String { return "Offense"; }

    /**
     * collect — 收集攻击类候选
     */
    public function collect(ctx:AIContext, data:UnitAIData, out:Array, trace:DecisionTrace):Void {
        var self:MovieClip = ctx.self;

        var attackCommit:Number = p.chaseCommitment;
        var skillCommit:Number = p.skillCommitFrames;

        // BasicAttack
        out.push({
            name: "BasicAttack", type: "attack", priority: 3,
            commitFrames: attackCommit, score: 0
        });

        // Skills（距离 + 冷却 + buff 过滤）
        var skills:Array = self.已学技能表;
        var nowMs:Number = ctx.nowMs;
        var xDist:Number = ctx.xDist;
        var maxC:Number = p.maxCandidates;
        var skillCount:Number = 0;

        if (skills != null) {
            for (var i:Number = 0; i < skills.length && skillCount < maxC; i++) {
                var sk:Object = skills[i];
                if (xDist < sk.距离min || xDist > sk.距离max) {
                    trace.reject(sk.技能名, DecisionTrace.REASON_RANGE);
                    continue;
                }
                if (!isNaN(sk.上次使用时间) && (nowMs - sk.上次使用时间 <= sk.冷却 * 1000)) {
                    trace.reject(sk.技能名, DecisionTrace.REASON_CD);
                    continue;
                }

                // 全局buff已激活 → 排除
                var preBuffMark:Object = _root.技能函数.预战buff标记[sk.技能名];
                if (preBuffMark != null && preBuffMark.global && preBuffMark.buffId != null) {
                    if (self.buffManager != null && self.buffManager.getBuffById(preBuffMark.buffId) != null) {
                        trace.reject(sk.技能名, DecisionTrace.REASON_BUFF);
                        continue;
                    }
                }
                // 单次施放保护：全局buff已施放过 → 不重复（即使 buffManager 未检测到）
                if (preBuffMark != null && preBuffMark.global && data._usedGlobalBuffs[sk.技能名] == true) {
                    trace.reject(sk.技能名, DecisionTrace.REASON_BUFF);
                    continue;
                }

                // 优先级：解围霸体常驻 emergency(0)；躲避仅受威胁时为 0
                var skillPri:Number = 1;
                if (sk.功能 == "解围霸体") {
                    skillPri = 0;
                } else if (sk.功能 == "躲避") {
                    skillPri = ctx.underFire ? 0 : 1;
                }
                out.push({
                    name: sk.技能名, type: "skill", priority: skillPri,
                    skill: sk, commitFrames: skillCommit, score: 0
                });
                skillCount++;
            }
        }
    }
}
