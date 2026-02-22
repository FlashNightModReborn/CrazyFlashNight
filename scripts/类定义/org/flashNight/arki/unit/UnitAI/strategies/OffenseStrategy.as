import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;
import org.flashNight.arki.unit.UnitAI.strategies.BasicAttackStrategy;
import org.flashNight.arki.unit.UnitAI.strategies.SkillCandidateStrategy;

/**
 * @deprecated 已拆分为 BasicAttackStrategy + SkillCandidateStrategy (2026-02)
 *
 * OffenseStrategy — 攻击候选源（技能 + 平A）
 *
 * 保留此类仅用于向后兼容 aiSpec.sources 中使用 "Offense" key 的配置。
 * 新代码应使用 "BasicAttack" + "Skill" 两个独立 key。
 *
 * 内部委托给 BasicAttackStrategy + SkillCandidateStrategy，不再维护独立逻辑。
 */
class org.flashNight.arki.unit.UnitAI.strategies.OffenseStrategy {

    private var _basic:BasicAttackStrategy;
    private var _skill:SkillCandidateStrategy;

    public function OffenseStrategy(personality:Object) {
        this._basic = new BasicAttackStrategy(personality);
        this._skill = new SkillCandidateStrategy(personality);
    }

    public function getName():String { return "Offense"; }

    public function collect(ctx:AIContext, data:UnitAIData, out:Array, trace:DecisionTrace):Void {
        this._basic.collect(ctx, data, out, trace);
        this._skill.collect(ctx, data, out, trace);
    }
}
