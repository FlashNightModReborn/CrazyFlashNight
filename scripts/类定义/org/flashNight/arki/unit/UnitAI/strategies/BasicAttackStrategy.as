import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;

/**
 * BasicAttackStrategy — 无条件基础攻击候选源
 *
 * 从 OffenseStrategy 拆分。始终输出恰好一个 BasicAttack 候选。
 * 智力门控：evalDepth >= 1（始终启用），是所有 AI 的行为底线。
 *
 * 与 SkillCandidateStrategy 分离后可在 PipelineFactory 中独立门控：
 *   BasicAttack 始终可用（depth 1），Skill 需要 depth >= 2。
 */
class org.flashNight.arki.unit.UnitAI.strategies.BasicAttackStrategy {

    private var p:Object;

    public function BasicAttackStrategy(personality:Object) {
        this.p = personality;
    }

    public function getName():String { return "BasicAttack"; }

    /**
     * collect — 输出一个 BasicAttack 候选
     */
    public function collect(ctx:AIContext, data:UnitAIData, out:Array, trace:DecisionTrace):Void {
        out.push({
            name: "BasicAttack", type: "attack", priority: 3,
            commitFrames: p.chaseCommitment, score: 0
        });
    }
}
