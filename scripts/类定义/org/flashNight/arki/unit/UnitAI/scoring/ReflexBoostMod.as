import org.flashNight.arki.unit.UnitAI.scoring.ScoringModifier;
import org.flashNight.arki.unit.UnitAI.ActionExecutor;

/**
 * ReflexBoostMod — 反射闪避评分注入
 *
 * 将原 ActionArbiter.tick() 中的硬旁路（bypass）改为管线内评分修正器，
 * 保持 collect→filter→score→select 单出口契约，DecisionTrace 完整记录。
 *
 * 触发条件（与原旁路一致）：
 *   bulletThreat > 0 && bulletETA <= 8 && 反应 >= 0.7 && 反射冷却就绪
 *
 * 行为：对符合条件的躲避技能 +5.0 分。
 * Boltzmann T=0.5 时 exp(5/0.5) ≈ 22026，选中概率 > 99.99%。
 *
 * 反射冷却（DOOM push-forward 模式）：
 *   两次反射闪避间隔至少 3 * tickInterval 帧，
 *   间歇期 Boltzmann 正常运作，让换弹/攻击/技能有机会被选中。
 *
 * 选中后处理：ActionArbiter 检测 selected._reflexBoosted 标记，
 * 调用 executor.commitReflex(frame) 记录反射帧。
 */
class org.flashNight.arki.unit.UnitAI.scoring.ReflexBoostMod extends ScoringModifier {

    private var _executor:ActionExecutor;

    public function ReflexBoostMod(executor:ActionExecutor) {
        this._executor = executor;
    }

    public function getName():String { return "ReflexBoost"; }

    /**
     * begin — 预计算反射条件（每 tick 一次）
     *
     * 检查射弹威胁 + 反应阈值 + 冷却就绪，结果存入 scratch._reflexActive。
     */
    public function begin(ctx, data, scratch:Object):Void {
        var p:Object = data.personality;
        if (ctx.bulletThreat <= 0 || ctx.bulletETA > 8 || p.反应 < 0.7) {
            scratch._reflexActive = false;
            return;
        }
        var frame:Number = _root.帧计时器.当前帧数;
        var reflexCooldown:Number = 3 * p.tickInterval;
        scratch._reflexActive = (frame - _executor.getLastReflexFrame() >= reflexCooldown);
    }

    /**
     * modify — 对躲避技能注入 +5.0 分（反射条件满足时）
     *
     * 标记 c._reflexBoosted = true，供 ActionArbiter 选中后调用 commitReflex。
     */
    public function modify(c:Object, ctx, p:Object, scratch:Object):Number {
        if (!scratch._reflexActive) return 0;
        if (c.type != "skill" || c.skill == null) return 0;
        if (c.skill.功能 != "躲避") return 0;
        c._reflexBoosted = true;
        return 5.0;
    }
}
