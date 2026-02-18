/**
 * ScoringModifier — 评分修正器基类（鸭子类型契约）
 *
 * 子类覆写 modify() 返回对候选 c 的评分增量（delta）。
 * begin() 在每 tick 评分开始前调用一次，用于预计算（如预扫技能表）。
 * end()   用于后处理器（如反抖动、频率校正），跨候选二次遍历。
 *
 * 约束（五方审阅共识）：
 *   - modify() 只读 ctx，禁止写 ctx（避免修正器间隐式耦合）
 *   - modify() 不接收 total（避免"如果 total>X 则额外加分"的不可预测行为）
 *   - 返回纯增量，不替换分数
 *   - 禁止在 modify 内 new Object / new Array（零 tick 分配原则）
 */
class org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier {

    public function getName():String { return "ScoringModifier"; }

    /**
     * begin — tick 级预计算（可选）
     * 在评分循环开始前调用一次，可将预计算结果存入 scratch。
     */
    public function begin(ctx, data, scratch:Object):Void {}

    /**
     * modify — 逐候选评分增量
     * @return delta 加到 candidate.score 上的增量
     */
    public function modify(c:Object, ctx, p:Object, scratch:Object):Number { return 0; }

    /**
     * end — 后处理（可选）
     * 在所有候选评分完成后调用，用于跨候选的二次遍历修正。
     */
    public function end(candidates:Array, ctx, p:Object, scratch:Object):Void {}
}
