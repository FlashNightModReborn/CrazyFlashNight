import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;

/**
 * PreBuffStrategy — 预战增益候选源
 *
 * 从 ActionArbiter._collectPreBuff 提取。
 * 职责：在安全距离且非射击中时注入预战buff候选。
 * 内部状态：帧节流计数器。
 */
class org.flashNight.arki.unit.UnitAI.strategies.PreBuffStrategy {

    private var p:Object;
    private var _preBuffCooldownFrame:Number;

    public function PreBuffStrategy(personality:Object) {
        this.p = personality;
        this._preBuffCooldownFrame = 0;
    }

    public function getName():String { return "PreBuff"; }

    public function collect(ctx:AIContext, data:UnitAIData, out:Array, trace:DecisionTrace):Void {
        var self:MovieClip = ctx.self;

        // 条件：非射击中 + 安全距离
        if (self.射击中) return;
        if (ctx.xDist <= ctx.xrange * 1.5) return;

        // 帧节流
        var currentFrame:Number = ctx.frame;
        if (currentFrame < _preBuffCooldownFrame) return;

        var skills:Array = self.已学技能表;
        if (skills == null) return;

        var marks:Object = _root.技能函数.预战buff标记;
        if (marks == null) return;

        var nowMs:Number = ctx.nowMs;
        var hasBM:Boolean = (self.buffManager != null);

        var found:Boolean = false;
        for (var i:Number = 0; i < skills.length; i++) {
            var sk:Object = skills[i];
            var mark:Object = marks[sk.技能名];
            if (mark == null) continue;

            if (!isNaN(sk.上次使用时间) && (nowMs - sk.上次使用时间 <= sk.冷却 * 1000)) {
                trace.reject(sk.技能名, DecisionTrace.REASON_CD);
                continue;
            }
            if (mark.global && hasBM && mark.buffId != null) {
                if (self.buffManager.getBuffById(mark.buffId) != null) {
                    trace.reject(sk.技能名, DecisionTrace.REASON_BUFF);
                    continue;
                }
            }
            if (ctx.isRigid && sk.功能 == "解围霸体") {
                trace.reject(sk.技能名, DecisionTrace.REASON_RIGID);
                continue;
            }

            var pri:Number = mark.priority || 0;
            out.push({
                name: sk.技能名, type: "preBuff", priority: 1,
                skill: sk, commitFrames: p.skillCommitFrames,
                score: 0.8 + pri * 0.2
            });
            found = true;
        }

        _preBuffCooldownFrame = currentFrame + (found ? 30 : 20);
    }
}
