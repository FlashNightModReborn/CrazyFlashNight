import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;

/**
 * SkillCandidateStrategy — 技能候选源（距离/冷却/buff 过滤）
 *
 * 从 OffenseStrategy 拆分。扫描 已学技能表 并生成通过过滤的技能候选。
 * 智力门控：evalDepth >= 2（智力≥0.13），低于此阈值的 AI 无法使用技能。
 *
 * 过滤顺序：距离范围 → 冷却时间 → 全局buff重复 → 单次施放保护
 * 优先级：解围霸体=0(emergency)，受威胁时躲避=0，其余=1
 * 候选上限：p.maxCandidates（经验驱动，2~8）
 */
class org.flashNight.arki.unit.UnitAI.strategies.SkillCandidateStrategy {

    private var p:Object;

    public function SkillCandidateStrategy(personality:Object) {
        this.p = personality;
    }

    public function getName():String { return "Skill"; }

    /**
     * collect — 收集技能候选（距离 + 冷却 + buff 过滤）
     */
    public function collect(ctx:AIContext, data:UnitAIData, out:Array, trace:DecisionTrace):Void {
        var self:MovieClip = ctx.self;
        var skills:Array = self.已学技能表;
        if (skills == null) return;

        var nowMs:Number = ctx.nowMs;
        var xDist:Number = ctx.xDist;
        var maxC:Number = p.maxCandidates;
        var skillCommit:Number = p.skillCommitFrames;
        var skillCount:Number = 0;

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
            // 单次施放保护：全局buff已施放过 → 不重复
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
