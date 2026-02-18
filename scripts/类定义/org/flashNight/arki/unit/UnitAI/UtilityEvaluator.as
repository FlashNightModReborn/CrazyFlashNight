import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * UtilityEvaluator — 评分服务（纯评分 + Boltzmann 选择）
 *
 * 职责（Phase 3 提取后）：
 *   1. 评分维度：scoreDimension() + 5 维度函数
 *   2. 随机选择：boltzmannSelect()（Boltzmann 轮盘）
 *   3. 维度键序：DIM_WEIGHTS（evalDepth 控制前 N 维激活）
 *
 * 以下职责已提取至独立子服务：
 *   - 武器评估 → WeaponEvaluator
 *   - 姿态/战术偏置 → StanceManager
 *   - 血包评估 → HealExecutor
 *
 * 所有参数从 personality 对象读取（mutate-only 引用）
 */
class org.flashNight.arki.unit.UnitAI.UtilityEvaluator {

    // ── 人格引用 ──
    private var p:Object;

    // ── 确定性随机源 ──
    private var _rng:LinearCongruentialEngine;

    // ── 评分维度键序（evalDepth 控制前 N 维激活）──
    // dim0=damage, dim1=safety, dim2=resource, dim3=positioning, dim4=combo
    public static var DIM_WEIGHTS:Array = ["w_damage", "w_safety", "w_resource", "w_positioning", "w_combo"];

    // ═══════ 构造 ═══════

    public function UtilityEvaluator(personality:Object) {
        this.p = personality;
        this._rng = LinearCongruentialEngine.getInstance();
    }

    // ═══════ 评分服务（供 ScoringPipeline 调用）═══════

    public function scoreDimension(dim:Number, c:Object, data:UnitAIData, self:MovieClip):Number {
        switch (dim) {
            case 0: return scoreDamage(c, data, self);
            case 1: return scoreSafety(c, self);
            case 2: return scoreResource(c);
            case 3: return scorePositioning(c, data);
            case 4: return scoreCombo(c);
            default: return 0;
        }
    }

    private function scoreDamage(c:Object, data:UnitAIData, self:MovieClip):Number {
        if (c.type == "attack") return 0.5;
        if (c.type == "hold") return 0;
        // Skill
        var base:Number = 0.3 + (c.skill.技能等级 / 10) * 0.7;
        var 类型:String = c.skill.类型;
        var 功能:String = c.skill.功能;
        if (类型 == "刀技") base += 0.3;
        else if (类型 == "格斗") base += 0.2;
        else if (类型 == "火器") base += 0.3;
        if (功能 == "躲避") base -= 0.2;
        if (功能 == "远程输出" && data.absdiff_x > 200) base += 0.2;
        if (功能 == "位移持续输出") base += 0.2;
        if (base > 1) base = 1;
        if (base < 0) base = 0;
        return base;
    }

    private function scoreSafety(c:Object, self:MovieClip):Number {
        var hpRatio:Number = self.hp / self.hp满血值;
        if (c.type == "attack") return 0.5;
        if (c.type == "hold") return 0.5;
        // Skill
        if (c.skill.功能 == "躲避") {
            // 基础分大幅下调：躲避是反应性行为，非默认选项
            // 被击加分（+0.5）由 ReactiveDodgeMod 处理
            var hpDodge:Number = self.hp / self.hp满血值;
            if (hpDodge < 0.3) return 0.6;  // 低血恐慌躲避
            return 0.2;                      // 正常低基础分
        }
        var base:Number = 0.3 + hpRatio * 0.4;
        return base > 1 ? 1 : base;
    }

    private function scoreResource(c:Object):Number {
        // 当前游戏无 MP 系统，所有动作资源成本相同
        return 1.0;
    }

    private function scorePositioning(c:Object, data:UnitAIData):Number {
        if (c.type != "skill") return 0.3;
        var 功能:String = c.skill.功能;
        if (功能 == "高频位移") {
            return (data.absdiff_x > data.xrange * 0.8) ? 0.7 : 0.4;
        }
        if (功能 == "位移持续输出") return 0.6;
        return 0.3;
    }

    private function scoreCombo(c:Object):Number {
        var cp:Number = p.comboPreference;
        if (isNaN(cp)) cp = 0;
        if (c.type == "attack") return 0.4 + cp * 0.4;
        if (c.type == "hold") return 0.1;
        // Skill
        var 类型:String = c.skill.类型;
        if (类型 == "格斗" || 类型 == "刀技") return 0.6 + cp * 0.3;
        if (c.skill.功能 == "躲避" || c.skill.功能 == "增益") return 0.2;
        return 0.3;
    }

    // ═══════ Boltzmann 选择 ═══════

    public function boltzmannSelect(candidates:Array, T:Number):Object {
        var len:Number = candidates.length;
        if (len == 0) return null;
        if (len == 1) {
            candidates[0]._ew = 1;
            return candidates[0];
        }

        // 数值稳定：减去最大分
        var maxS:Number = candidates[0].score;
        for (var i:Number = 1; i < len; i++) {
            if (candidates[i].score > maxS) maxS = candidates[i].score;
        }

        // 计算 exp 权重
        var sumExp:Number = 0;
        for (var j:Number = 0; j < len; j++) {
            var ew:Number = Math.exp((candidates[j].score - maxS) / T);
            candidates[j]._ew = ew;
            sumExp += ew;
        }

        // 轮盘选择
        var r:Number = _rng.nextFloat() * sumExp;
        var cum:Number = 0;
        for (var k:Number = 0; k < len; k++) {
            cum += candidates[k]._ew;
            if (r <= cum) return candidates[k];
        }
        return candidates[len - 1];
    }
}
