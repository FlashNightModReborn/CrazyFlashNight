import org.flashNight.arki.unit.UnitAI.UnitAIData;

/**
 * UtilityEvaluator — 人格驱动 Utility AI 评估器
 *
 * 职责：
 *   1. selectCombatAction  — 交战状态下的动作选择（替换 selectSkill）
 *   2. evaluateWeaponMode  — 武器模式选择（替换 evaluateWeapon）
 *   3. evaluateHealNeed    — 血包使用决策（替换 evaluateHeal）
 *
 * 管线：Filter → Score → Anti-oscillation → Boltzmann
 *
 * 所有参数从 personality 对象读取（mutate-only 引用）：
 *   六维人格：勇气/技术/经验/反应/智力/谋略
 *   派生参数：engageDistanceMult, retreatHPRatio, chaseCommitment,
 *            decisionNoise, stanceMastery, stabilityFactor, maxCandidates,
 *            tickInterval, evalDepth, healEagerness, baseTemperature,
 *            temperature, w_damage, w_safety, w_resource, w_positioning, w_combo
 *
 * 降级策略：personality == null 时评估器不创建，原 Phase 1 逻辑不变
 */
class org.flashNight.arki.unit.UnitAI.UtilityEvaluator {

    // ── 人格引用 ──
    private var p:Object;

    // ── 反抖动状态 ──
    private var _commitUntilFrame:Number;
    private var _lastActionType:String;
    private var _lastSkillName:String;
    private var _repeatCount:Number;
    private var _lastWeaponSwitchFrame:Number;

    // ── 候选池（复用减少 GC）──
    private var _candidates:Array;

    // ── 评分维度键序（evalDepth 控制前 N 维激活）──
    // dim0=damage, dim1=safety, dim2=resource, dim3=positioning, dim4=combo
    private static var DIM_WEIGHTS:Array = ["w_damage", "w_safety", "w_resource", "w_positioning", "w_combo"];

    // ═══════ 构造 ═══════

    public function UtilityEvaluator(personality:Object) {
        this.p = personality;
        this._commitUntilFrame = 0;
        this._lastActionType = null;
        this._lastSkillName = null;
        this._repeatCount = 0;
        this._lastWeaponSwitchFrame = -999;
        this._candidates = [];
    }

    // ═══════ 1. 交战动作选择 ═══════

    /**
     * selectCombatAction — 替换 HeroCombatModule.selectSkill
     *
     * 在 Engaging 状态的 onAction 中每帧调用。
     * 候选：BasicAttack / Skill(filtered) / Hold
     */
    public function selectCombatAction(data:UnitAIData):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 预计算决策间隔参数（频率校正 + commitment 锁共用）
        var commitment:Number = p.chaseCommitment;
        if (isNaN(commitment)) commitment = 5;
        var reactionMult:Number = p.tickInterval;
        if (isNaN(reactionMult) || reactionMult < 1) reactionMult = 1;

        // ── commitment 锁：锁定期间重复上次动作类型 ──
        if (currentFrame < _commitUntilFrame) {
            repeatLastAction(self);
            return;
        }

        // ── 1. Filter: 构建候选列表 ──
        var candidates:Array = this._candidates;
        candidates.length = 0;

        // BasicAttack（始终可选）
        candidates.push({name: "BasicAttack", type: "attack", score: 0});

        // 技能（距离 + 冷却过滤）
        var skills:Array = self.已学技能表;
        var nowMs:Number = getTimer();
        var xDist:Number = data.absdiff_x;
        var maxC:Number = p.maxCandidates;
        if (isNaN(maxC) || maxC < 2) maxC = 8;
        var skillCount:Number = 0;

        if (skills != null) {
            for (var i:Number = 0; i < skills.length && skillCount < maxC; i++) {
                var sk:Object = skills[i];
                // 距离过滤
                if (xDist < sk.距离min || xDist > sk.距离max) continue;
                // 冷却过滤
                if (!isNaN(sk.上次使用时间) && (nowMs - sk.上次使用时间 <= sk.冷却 * 1000)) continue;

                candidates.push({
                    name: sk.技能名,
                    type: "skill",
                    skill: sk,
                    score: 0
                });
                skillCount++;
            }
        }

        // Hold（始终可选，低分兜底）
        candidates.push({name: "Hold", type: "hold", score: 0});

        // ── 2. Score: 多维评分 ──
        var evalDepth:Number = p.evalDepth;
        if (isNaN(evalDepth) || evalDepth < 1) evalDepth = 1;
        if (evalDepth > 5) evalDepth = 5;

        var noise:Number = p.decisionNoise;
        if (isNaN(noise)) noise = 0.5;

        // 特殊角色加成
        var skillBonus:Number = 0;
        if (self.名字 == "尾上世莉架") skillBonus = 0.3;

        for (var j:Number = 0; j < candidates.length; j++) {
            var c:Object = candidates[j];
            var total:Number = 0;

            for (var d:Number = 0; d < evalDepth; d++) {
                var w:Number = p[DIM_WEIGHTS[d]];
                if (isNaN(w)) w = 0.2;
                total += w * scoreDimension(d, c, data, self);
            }

            // 技能类型加成（特殊角色）
            if (c.type == "skill" && skillBonus > 0) {
                total += skillBonus;
            }

            // 技术噪声（高技术→低噪声→更准确）
            total += (Math.random() - 0.5) * noise;

            c.score = total;
        }

        // ── 3. Anti-oscillation ──
        var momentumDecay:Number = p.momentumDecay;
        if (isNaN(momentumDecay)) momentumDecay = 0.5;

        for (var k:Number = 0; k < candidates.length; k++) {
            var ca:Object = candidates[k];

            // 动量奖励：与上次同类型 → 加分（被 momentumDecay 衰减）
            if (ca.type == _lastActionType) {
                ca.score += 0.1 * (1 - momentumDecay);
            }

            // 重复惩罚：连续使用同一技能 → 递减
            if (ca.type == "skill" && ca.name == _lastSkillName) {
                ca.score -= 0.08 * (_repeatCount + 1);
            }
        }

        // ── 3.5 频率校正：使技能总使用期望与原始16帧基准等价 ──
        // 原始技能概率按每16帧决策一次设计。当前有效决策间隔 E = commitment × reactionMult。
        // Boltzmann 概率缩放: P_new = P_old × (E/16)，等价于 δ = T × ln(E/16)
        // E < 16(高反应,决策频繁)→ δ < 0 → 技能降权，避免滥用
        // E > 16(低反应,决策稀疏)→ δ > 0 → 技能升权，保持总期望
        var T:Number = p.temperature;
        if (isNaN(T) || T < 0.01) T = 0.2;

        var effectiveInterval:Number = commitment * reactionMult;
        if (effectiveInterval < 1) effectiveInterval = 1;
        var BASELINE_INTERVAL:Number = 16;
        var freqAdjust:Number = T * Math.log(effectiveInterval / BASELINE_INTERVAL);

        for (var fa:Number = 0; fa < candidates.length; fa++) {
            if (candidates[fa].type == "skill") {
                candidates[fa].score += freqAdjust;
            }
        }

        // ── 4. Boltzmann 选择 ──
        var selected:Object = boltzmannSelect(candidates, T);

        // ── 5. 执行 ──
        executeCombatAction(selected, self);

        // ── 6. 更新状态 ──
        // commitment × reactionMult 已在函数开头预计算
        _commitUntilFrame = currentFrame + Math.round(commitment * reactionMult);
        _lastActionType = selected.type;

        if (selected.type == "skill") {
            if (_lastSkillName == selected.name) {
                _repeatCount++;
            } else {
                _repeatCount = 0;
            }
            _lastSkillName = selected.name;
            selected.skill.上次使用时间 = nowMs;
            self.技能等级 = selected.skill.技能等级;
        } else {
            _repeatCount = 0;
        }

        // ── 7. Debug 输出 ──
        if (_root.AI调试模式 == true) {
            debugTop3(candidates, selected, self, T);
        }
    }

    // ── 单维度评分 ──

    private function scoreDimension(dim:Number, c:Object, data:UnitAIData, self:MovieClip):Number {
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
        if (c.skill.功能 == "躲避") return 0.9;
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

    // ── Boltzmann 选择 ──

    private function boltzmannSelect(candidates:Array, T:Number):Object {
        var len:Number = candidates.length;
        if (len == 0) return null;
        if (len == 1) return candidates[0];

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
        var r:Number = Math.random() * sumExp;
        var cum:Number = 0;
        for (var k:Number = 0; k < len; k++) {
            cum += candidates[k]._ew;
            if (r <= cum) return candidates[k];
        }
        return candidates[len - 1];
    }

    // ── 动作执行 ──

    private function executeCombatAction(selected:Object, self:MovieClip):Void {
        if (selected == null) {
            self.动作A = true;
            return;
        }
        switch (selected.type) {
            case "attack":
                self.动作A = true;
                if (self.攻击模式 === "双枪") self.动作B = true;
                break;
            case "skill":
                _root.技能路由.技能标签跳转_旧(self, selected.name);
                break;
            case "hold":
                // 等待 — 不输出任何动作
                break;
        }
    }

    private function repeatLastAction(self:MovieClip):Void {
        // commitment 期间：普攻继续输出，技能/hold 不重复触发
        if (_lastActionType == "attack") {
            self.动作A = true;
            if (self.攻击模式 === "双枪") self.动作B = true;
        }
    }

    // ═══════ 2. 武器模式选择 ═══════

    /**
     * evaluateWeaponMode — 替换 HeroCombatBehavior.evaluateWeapon
     *
     * 在 Selector 中每次决策时调用。
     * 评估各可用武器模式 → 切换最优 → 设定攻击范围参数。
     */
    public function evaluateWeaponMode(data:UnitAIData):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 武器切换冷却（30帧）
        if (currentFrame - _lastWeaponSwitchFrame < 30) {
            applyWeaponRanges(self, data);
            return;
        }

        // 检查装备
        var has刀:Boolean = self.刀 ? true : false;
        var has长枪:Boolean = self.长枪 ? true : false;
        var has手枪:Boolean = self.手枪 ? true : false;
        var has手枪2:Boolean = self.手枪2 ? true : false;
        var hasWeapon:Boolean = has刀 || has长枪 || has手枪 || has手枪2;

        if (!hasWeapon) {
            // 只有空手
            applyWeaponRanges(self, data);
            return;
        }

        // 估算到目标的距离
        var dist:Number = 200;
        if (data.target != null) {
            data.updateSelf();
            data.updateTarget();
            dist = data.absdiff_x;
        }

        // 评估各可用模式
        var bestMode:String = self.攻击模式;
        var bestScore:Number = -999;
        var modes:Array = ["空手"];
        if (has刀) modes.push("兵器");
        if (has手枪 || has手枪2) modes.push("手枪");
        if (has长枪) modes.push("长枪");

        for (var i:Number = 0; i < modes.length; i++) {
            var mode:String = modes[i];
            var score:Number = scoreWeaponMode(mode, dist);
            // 切换成本
            if (mode != self.攻击模式) score -= 0.3;
            if (score > bestScore) {
                bestScore = score;
                bestMode = mode;
            }
        }

        // 执行切换
        if (bestMode != self.攻击模式 && bestMode != "空手") {
            self.攻击模式切换(bestMode);
            _lastWeaponSwitchFrame = currentFrame;
        }

        applyWeaponRanges(self, data);
    }

    private function scoreWeaponMode(mode:String, dist:Number):Number {
        var score:Number = 0;
        var optDist:Number;
        switch (mode) {
            case "空手":
                optDist = 50;
                score = 0.5 - Math.abs(dist - optDist) / 400;
                score += (p.勇气 || 0) * 0.3 + (p.stanceMastery || 0) * 0.2;
                break;
            case "兵器":
                optDist = 100;
                score = 0.7 - Math.abs(dist - optDist) / 300;
                score += (p.勇气 || 0) * 0.3 + (p.stanceMastery || 0) * 0.2;
                break;
            case "手枪":
                optDist = 250;
                score = 0.6 - Math.abs(dist - optDist) / 400;
                score += (p.智力 || 0) * 0.3 + (p.stabilityFactor || 0) * 0.2;
                break;
            case "长枪":
                optDist = 350;
                score = 0.65 - Math.abs(dist - optDist) / 500;
                score += (p.智力 || 0) * 0.3 + (p.stabilityFactor || 0) * 0.2;
                break;
        }
        return score;
    }

    /**
     * 根据当前攻击模式设定范围参数
     * 保留原始 Phase 1 的硬编码值（这些是游戏平衡参数）
     */
    private function applyWeaponRanges(self:MovieClip, data:UnitAIData):Void {
        switch (self.攻击模式) {
            case "空手":
                self.x轴攻击范围 = 90;
                self.y轴攻击范围 = 20;
                self.x轴保持距离 = 50;
                break;
            case "兵器":
                self.x轴攻击范围 = 150;
                self.y轴攻击范围 = 20;
                self.x轴保持距离 = 150;
                break;
            case "长枪":
            case "手枪":
            case "手枪2":
            case "双枪":
                self.x轴攻击范围 = 400;
                self.y轴攻击范围 = 20;
                self.x轴保持距离 = 200;
                break;
            case "手雷":
                self.x轴攻击范围 = 300;
                self.y轴攻击范围 = 10;
                self.x轴保持距离 = 200;
                break;
        }
        data.xrange = self.x轴攻击范围;
        data.zrange = self.y轴攻击范围;
        data.xdistance = self.x轴保持距离;
    }

    // ═══════ 3. 血包评估 ═══════

    /**
     * evaluateHealNeed — 替换 HeroCombatBehavior.evaluateHeal
     *
     * healScore = (1 - hp/maxHP) × healEagerness × 2.0 + 紧急加成
     * healScore > 0.5 → 使用血包
     */
    public function evaluateHealNeed(data:UnitAIData):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 前置条件
        if (self.血包数量 <= 0) return;
        if (currentFrame - self.上次使用血包时间 <= self.血包使用间隔) return;

        var hpRatio:Number = self.hp / self.hp满血值;
        var eagerness:Number = p.healEagerness;
        if (isNaN(eagerness)) eagerness = 0.5;

        var healScore:Number = (1 - hpRatio) * eagerness * 2.0;

        // 紧急加成：血量 < 20%
        if (hpRatio < 0.2) healScore += 1.0;

        // 安全区自动回血
        if (_root.gameworld.允许通行 && self.hp满血值 > self.hp) {
            healScore += 0.6;
        }

        if (healScore > 0.5) {
            var hpBefore:Number = self.hp;
            self.血包数量--;
            _root.佣兵使用血包(self._name);
            self.上次使用血包时间 = currentFrame;
            _root.发布消息(self.名字 + "[" + hpBefore + "/" + self.hp满血值 + "] 紧急治疗后还剩[" + self.血包数量 + "]个治疗包");
        }
    }

    // ═══════ Debug 输出 ═══════

    private function debugTop3(candidates:Array, selected:Object, self:MovieClip, T:Number):Void {
        // 按分数降序排列（浅拷贝）
        var sorted:Array = candidates.slice(0);
        sorted.sort(function(a, b) {
            return (b.score > a.score) ? 1 : ((b.score < a.score) ? -1 : 0);
        });

        var msg:String = "[AI] " + self.名字 + " Top3: ";
        var count:Number = sorted.length < 3 ? sorted.length : 3;
        for (var i:Number = 0; i < count; i++) {
            var ci:Object = sorted[i];
            var prob:Number = Math.round((ci._ew / (ci._ew + 0.001)) * 100);
            msg += ci.name + "=" + (Math.round(ci.score * 100) / 100);
            if (i < count - 1) msg += ", ";
        }
        msg += " -> " + selected.name + " [T=" + (Math.round(T * 100) / 100) + "]";
        _root.服务器.发布服务器消息(msg);
    }
}
