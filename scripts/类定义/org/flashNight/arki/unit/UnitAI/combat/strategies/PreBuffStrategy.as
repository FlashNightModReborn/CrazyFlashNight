import org.flashNight.arki.unit.UnitAI.core.AIContext;
import org.flashNight.arki.unit.UnitAI.core.UnitAIData;
import org.flashNight.arki.unit.UnitAI.combat.DecisionTrace;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;

/**
 * PreBuffStrategy — 预战增益候选源
 *
 * 从 ActionArbiter._collectPreBuff 提取。
 * 职责：在安全距离且非射击中时注入预战buff候选。
 * 内部状态：帧节流计数器。
 *
 * 经验缩放（p.preBuffDistMult / p.preBuffCooldown）：
 *   高经验 → 远距离主动准备buff + 短冷却频繁尝试
 *   低经验 → 仅近距离才触发 + 长冷却间隔
 */
class org.flashNight.arki.unit.UnitAI.combat.strategies.PreBuffStrategy {

    private var p:Object;
    private var _preBuffCooldownFrame:Number;
    private var _lastRetreatEmergencyLogFrame:Number;

    public function PreBuffStrategy(personality:Object) {
        this.p = personality;
        this._preBuffCooldownFrame = 0;
        this._lastRetreatEmergencyLogFrame = -999;
    }

    public function getName():String { return "PreBuff"; }

    public function collect(ctx:AIContext, data:UnitAIData, out:Array, trace:DecisionTrace):Void {
        var self:MovieClip = ctx.self;
        var currentFrame:Number = ctx.frame;
        var skills:Array = self.已学技能表;

        // retreat 期间 edge-pin / 脸上换弹属于即时求生问题，不走普通 preBuff 节奏。
        if (_shouldCollectRetreatEmergency(ctx, data)) {
            var emergencyNames:Array = [];
            var emergencyCount:Number = _collectRetreatEmergencySkills(
                ctx, data, skills, out, trace, emergencyNames);
            _logRetreatEmergency(ctx, data, currentFrame, emergencyCount, emergencyNames);
            return;
        }

        // 条件：非射击中 + 安全距离（经验缩放）
        // 使用 xdistance（保持距离）而非 xrange（最大攻击范围）：
        //   xrange(长枪)=600 * 1.5=900px → 几乎永远不满足
        //   xdistance(长枪)=350 * 1.5=525px → 合理的预战准备距离
        if (self.射击中) return;
        var distMult:Number = p.preBuffDistMult;
        if (isNaN(distMult) || distMult < 1.5) distMult = 1.5;
        if (ctx.xDist <= ctx.xdistance * distMult) return;

        // 帧节流（经验缩放）
        if (currentFrame < _preBuffCooldownFrame) return;

        if (skills == null) return;

        var marks:Object = AIEnvironment.getPreBuffMarks();
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
            // 单次施放保护：全局buff已施放过 → 不重复（即使 buffManager 未检测到）
            if (mark.global && data._usedGlobalBuffs[sk.技能名] == true) {
                trace.reject(sk.技能名, DecisionTrace.REASON_BUFF);
                continue;
            }
            if (ctx.isRigid && sk.功能 == "解围霸体") {
                trace.reject(sk.技能名, DecisionTrace.REASON_RIGID);
                continue;
            }

            var pri:Number = mark.priority || 0;
            // 经验加成：高经验→更重视预战准备，buff 在 Boltzmann 中竞争力更强
            var expBonus:Number = (p.经验 || 0) * 0.4;
            out.push({
                name: sk.技能名, type: "preBuff", priority: 1,
                skill: sk, commitFrames: p.skillCommitFrames,
                score: 0.8 + pri * 0.2 + expBonus
            });
            found = true;
        }

        var cd:Number = p.preBuffCooldown;
        if (isNaN(cd) || cd < 10) cd = 30;
        _preBuffCooldownFrame = currentFrame + (found ? cd : Math.round(cd * 0.7));
    }

    private function _shouldCollectRetreatEmergency(ctx:AIContext, data:UnitAIData):Boolean {
        if (ctx == null || data == null) return false;
        if (ctx.context != "retreat") return false;

        var edgeMargin:Number = p.retreatEmergencyEdgeMargin;
        if (isNaN(edgeMargin) || edgeMargin <= 0) edgeMargin = 110;

        var cornerGate:Number = p.retreatEmergencyCornerThreshold;
        if (isNaN(cornerGate) || cornerGate <= 0) cornerGate = 0.2;

        if (!_isRetreatPinned(data, edgeMargin, cornerGate)) return false;

        var urgGate:Number = p.retreatEmergencyUrgencyThreshold;
        if (isNaN(urgGate) || urgGate <= 0) urgGate = 0.7;

        var nearGate:Number = p.retreatEmergencyNearbyThreshold;
        if (isNaN(nearGate) || nearGate <= 0) nearGate = 3;

        var reloadNearGate:Number = p.retreatReloadBreakNearbyThreshold;
        if (isNaN(reloadNearGate) || reloadNearGate <= 0) reloadNearGate = 2;

        if (ctx.lockSource == "ANIM_RELOAD" && ctx.nearbyCount >= reloadNearGate) {
            return true;
        }

        return ctx.retreatUrgency >= urgGate && ctx.nearbyCount >= nearGate;
    }

    private function _isRetreatPinned(data:UnitAIData, edgeMargin:Number, cornerGate:Number):Boolean {
        if (data == null) return false;
        if (data.bndCorner >= cornerGate) return true;

        var edgePinned:Boolean = (data.bndLeftDist < edgeMargin || data.bndRightDist < edgeMargin);
        if (!edgePinned) return false;

        var retDir:Number = (data.diff_x > 0) ? -1 : 1;
        if (retDir < 0 && data.bndLeftDist < edgeMargin) return true;
        if (retDir > 0 && data.bndRightDist < edgeMargin) return true;

        return Math.min(data.bndLeftDist, data.bndRightDist) < edgeMargin * 0.6;
    }

    private function _collectRetreatEmergencySkills(
        ctx:AIContext, data:UnitAIData, skills:Array, out:Array, trace:DecisionTrace, names:Array
    ):Number {
        if (skills == null) return 0;

        var marks:Object = AIEnvironment.getPreBuffMarks();
        var self:MovieClip = ctx.self;
        var nowMs:Number = ctx.nowMs;
        var xDist:Number = ctx.xDist;
        var hasBM:Boolean = (self.buffManager != null);
        var count:Number = 0;

        for (var i:Number = 0; i < skills.length; i++) {
            var sk:Object = skills[i];
            if (!_isRetreatEmergencySkill(sk)) continue;

            if (xDist < sk.距离min || xDist > sk.距离max) {
                trace.reject(sk.技能名, DecisionTrace.REASON_RANGE);
                continue;
            }
            if (!isNaN(sk.上次使用时间) && (nowMs - sk.上次使用时间 <= sk.冷却 * 1000)) {
                trace.reject(sk.技能名, DecisionTrace.REASON_CD);
                continue;
            }

            var mark:Object = (marks != null) ? marks[sk.技能名] : null;
            if (mark != null && mark.global && hasBM && mark.buffId != null) {
                if (self.buffManager.getBuffById(mark.buffId) != null) {
                    trace.reject(sk.技能名, DecisionTrace.REASON_BUFF);
                    continue;
                }
            }
            if (mark != null && mark.global && data._usedGlobalBuffs[sk.技能名] == true) {
                trace.reject(sk.技能名, DecisionTrace.REASON_BUFF);
                continue;
            }
            if (ctx.isRigid && (sk.功能 == "解围霸体" || sk.功能 == "霸体" || sk.功能 == "无敌")) {
                trace.reject(sk.技能名, DecisionTrace.REASON_RIGID);
                continue;
            }

            out.push({
                name: sk.技能名, type: "skill", priority: 0,
                skill: sk, commitFrames: p.skillCommitFrames, score: 0
            });
            names.push(sk.技能名);
            count++;
        }

        return count;
    }

    private function _isRetreatEmergencySkill(sk:Object):Boolean {
        if (sk == null) return false;
        if (sk.类型 == "躲避") return true;

        var func:String = sk.功能;
        return func == "防护"
            || func == "解围霸体"
            || func == "霸体"
            || func == "无敌"
            || func == "爆发解围输出"
            || func == "持续解围输出"
            || func == "持续解围爆发输出"
            || func == "解围持续爆发输出";
    }

    private function _logRetreatEmergency(
        ctx:AIContext, data:UnitAIData, frame:Number, count:Number, names:Array
    ):Void {
        if (!(AIEnvironment.isAIDebug() || AIEnvironment.getAILogLevel() >= 2)) return;
        if (frame - _lastRetreatEmergencyLogFrame < 12) return;
        _lastRetreatEmergencyLogFrame = frame;

        var edgeMargin:Number = p.retreatEmergencyEdgeMargin;
        if (isNaN(edgeMargin) || edgeMargin <= 0) edgeMargin = 110;

        var pinTag:String = "OPEN";
        if (data.bndCorner > 0.2) pinTag = "CORNER";
        else if (data.bndLeftDist < edgeMargin && data.bndRightDist < edgeMargin) pinTag = "CENTER";
        else if (data.bndLeftDist < edgeMargin) pinTag = "LEFT";
        else if (data.bndRightDist < edgeMargin) pinTag = "RIGHT";

        AIEnvironment.log("[RET-SAFE] " + ctx.self.名字
            + " EDGE_PIN " + ((count > 0) ? "ARMED" : "NO_SKILL")
            + " side=" + pinTag
            + " urg=" + Math.round(ctx.retreatUrgency * 100)
            + " near=" + Math.round(ctx.nearbyCount)
            + " corner=" + Math.round(data.bndCorner * 100)
            + " lock=" + ((ctx.lockSource != null) ? ctx.lockSource : "-")
            + " reload=" + (data.reloadTag ? 1 : 0)
            + " xDist=" + Math.round(ctx.xDist)
            + " skills=" + ((count > 0) ? names.join("/") : "-"));
    }
}
