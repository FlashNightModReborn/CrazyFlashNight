import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * UtilityEvaluator — 人格驱动 Utility AI 评估器
 *
 * 职责：
 *   1. selectCombatAction  — 交战状态下的动作选择（替换 selectSkill）
 *   2. evaluateWeaponMode  — 武器模式选择（替换 evaluateWeapon）
 *   3. evaluateHealNeed    — 血包使用决策（替换 evaluateHeal）
 *
 * 管线：Filter → Score(+Stance 调制 +战术偏置) → Anti-oscillation → Boltzmann
 *
 * Stance 系统（Step 4）：
 *   武器模式 → Stance 配置（dimMod + skillAffinity + repositionDir）
 *   Stance 调制评分维度权重 + 候选加成，驱动近战贴身/远程拉距行为分化
 *
 * 战术偏置（Tactical Bias）：
 *   技能执行后设定短期评分偏置（如位移后追加近战连招）
 *   自然衰减（expiryFrame），不需要独立状态机
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
    private var _lastSkillUseFrame:Number;

    // ── 确定性随机源 ──
    private var _rng:LinearCongruentialEngine;

    // ── 候选池（复用减少 GC）──
    private var _candidates:Array;

    // ── 武器姿态（Stance）──
    private var _currentStance:Object;

    // ── 战术偏置（Tactical Bias）──
    // 技能执行后的短期评分偏置，expiryFrame 后自动失效
    private var _tacticalBias:Object;

    // ── 预战buff冷却帧 ──
    private var _preBuffCooldownFrame:Number;

    // ── 评分维度键序（evalDepth 控制前 N 维激活）──
    // dim0=damage, dim1=safety, dim2=resource, dim3=positioning, dim4=combo
    public static var DIM_WEIGHTS:Array = ["w_damage", "w_safety", "w_resource", "w_positioning", "w_combo"];

    // ═══════ 武器威力系数（DPS 代理）═══════
    //
    // 控制武器选择的基础偏好：高系数 = 更高效的输出方式
    // 当前硬编码，后续替换为 actualDPS / referenceDPS
    // 中心化偏移公式：(power - 0.5) × POWER_WEIGHT
    //   0.5 = 中性点（兵器），不改变原有评分
    //   < 0.5 → 降权（空手），> 0.5 → 升权（远程）
    //   远程牵制 > 近战换血 的战术思路通过系数差异表达

    private static var WEAPON_POWER:Object = initWeaponPower();
    private static var POWER_WEIGHT:Number = 0.3;  // 降权：让距离/人格有更多发言权

    private static function initWeaponPower():Object {
        var wp:Object = {};
        wp["空手"] = 0.1;   // 极低：几乎不应主动选择
        wp["兵器"] = 0.75;  // 近战武器，效率较高但有风险
        wp["手枪"] = 0.6;   // 单手枪，略优于近战
        wp["双枪"] = 0.8;   // 双持高火力
        wp["长枪"] = 1.0;   // 最高效远程输出
        wp["手雷"] = 0.5;   // 情境武器，中性
        return wp;
    }

    // ═══════ 武器有效射程表（射程匹配度评分用）═══════
    //
    // min/max 定义每种武器的最优作战距离区间
    // 在区间内 → +0.1，偏离 → 按距离线性惩罚，封顶 -0.3
    // 与 WEAPON_POWER 共同决定武器选择：power 管基准偏好，range 管距离适应

    private static var WEAPON_RANGES:Object = initWeaponRanges();

    private static function initWeaponRanges():Object {
        var wr:Object = {};
        wr["空手"] = { min: 0,   max: 80  };
        wr["兵器"] = { min: 0,   max: 180 };
        wr["手枪"] = { min: 100, max: 350 };
        wr["双枪"] = { min: 80,  max: 350 };
        wr["长枪"] = { min: 150, max: 400 };
        wr["手雷"] = { min: 150, max: 350 };
        return wr;
    }

    // ═══════ Stance 配置表 ═══════
    //
    // 每种武器模式对应一组评分调制参数：
    //   dimMod[5]      : 叠加到 personality 维度权重上的偏移
    //   skillAffinity  : { 技能类型 → 额外加分 }
    //   repositionDir  : -1=贴近, 0=中性, +1=拉距
    //   attackBonus    : BasicAttack 额外加分
    //   optDistMin/Max : 距离窗口型姿态的最优区间（仅手雷）

    private static var STANCES:Object = initStances();

    private static function initStances():Object {
        var s:Object = {};

        // 近战：空手 — 高连击+伤害，贴近作战
        s["空手"] = {
            dimMod: [0.15, -0.1, 0, -0.05, 0.2],
            skillAffinity: {格斗: 0.25, 躲避: 0.1},
            repositionDir: -1,
            attackBonus: 0.1
        };

        // 近战：兵器 — 高伤害，刀技专精
        s["兵器"] = {
            dimMod: [0.2, -0.05, 0, 0, 0.15],
            skillAffinity: {刀技: 0.25, 格斗: 0.1},
            repositionDir: -1,
            attackBonus: 0.05
        };

        // 远程：手枪系 — 安全+定位，保持距离
        var ranged:Object = {
            dimMod: [-0.05, 0.1, 0.1, 0.1, -0.1],
            skillAffinity: {火器: 0.2},
            repositionDir: 1,
            attackBonus: 0
        };
        s["手枪"] = ranged;
        s["手枪2"] = ranged;
        s["双枪"] = ranged;

        // 远程：长枪 — 高安全+定位，技能优先于普攻
        s["长枪"] = {
            dimMod: [-0.05, 0.15, 0.05, 0.15, -0.15],
            skillAffinity: {火器: 0.25},
            repositionDir: 1,
            attackBonus: -0.1
        };

        // 特殊：手雷 — 距离窗口型，投掷后建议切换
        s["手雷"] = {
            dimMod: [0.15, 0, -0.15, 0.2, 0],
            skillAffinity: {},
            repositionDir: 1,
            attackBonus: -0.2,
            optDistMin: 150,
            optDistMax: 350
        };

        return s;
    }

    // ═══════ 构造 ═══════

    public function UtilityEvaluator(personality:Object) {
        this.p = personality;
        this._rng = LinearCongruentialEngine.getInstance();
        this._commitUntilFrame = 0;
        this._lastActionType = null;
        this._lastSkillName = null;
        this._repeatCount = 0;
        this._lastWeaponSwitchFrame = -999;
        this._lastSkillUseFrame = -999;
        this._candidates = [];
        this._currentStance = null;
        this._tacticalBias = null;
        this._preBuffCooldownFrame = 0;
    }

    // ═══════ Stance 公开接口 ═══════

    /**
     * syncStance — 同步武器姿态（由 evaluateWeaponMode 调用）
     */
    public function syncStance(mode:String):Void {
        _currentStance = STANCES[mode];
    }

    /**
     * getRepositionDir — 当前姿态的位移倾向
     * @return -1=贴近, 0=中性/无姿态, +1=拉距
     * HeroCombatModule.engage 读取此值决定远程风筝行为
     */
    public function getRepositionDir():Number {
        return (_currentStance != null) ? _currentStance.repositionDir : 0;
    }

    // ═══════ Stance/Tactical 访问器（供 ActionArbiter 评分用）═══════

    public function getCurrentStance():Object {
        return _currentStance;
    }

    public function getTacticalBias():Object {
        return _tacticalBias;
    }

    public function clearTacticalBias():Void {
        _tacticalBias = null;
    }

    // ═══════ 0. 预战buff准备 ═══════

    /**
     * selectPreCombatBuff — Chasing 阶段远距离时主动施放增益技能
     *
     * 由 HeroCombatModule.chase() 调用，当距离足够远时触发。
     * 读取 _root.技能函数.预战buff标记 确定哪些技能是预战buff及优先级。
     * 通过 buffManager.getBuffById() 检测全局buff是否已激活（避免重复使用）。
     * 帧节流防止频繁尝试。
     */
    public function selectPreCombatBuff(data:UnitAIData):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 帧节流
        if (currentFrame < _preBuffCooldownFrame) return;

        var skills:Array = self.已学技能表;
        if (skills == null) return;

        var marks:Object = _root.技能函数.预战buff标记;
        if (marks == null) return;

        var nowMs:Number = getTimer();
        var hasBM:Boolean = (self.buffManager != null);

        // 刚体检测（霸体类 buff 在刚体期间跳过）
        var isRigid:Boolean = (self.刚体 == true) ||
            (self.man.刚体标签 != null && self.man.刚体标签 != undefined);

        var bestSkill:Object = null;
        var bestPriority:Number = -1;

        for (var i:Number = 0; i < skills.length; i++) {
            var sk:Object = skills[i];
            var mark:Object = marks[sk.技能名];
            if (mark == null) continue; // 不在预战buff表中

            // 技能冷却过滤
            if (!isNaN(sk.上次使用时间) && (nowMs - sk.上次使用时间 <= sk.冷却 * 1000)) continue;

            // 全局buff已激活 → 跳过（通过 buffManager 查询实际状态）
            if (mark.global && hasBM && mark.buffId != null) {
                if (self.buffManager.getBuffById(mark.buffId) != null) continue;
            }

            // 刚体已激活 → 跳过霸体类
            if (isRigid && sk.功能 == "解围霸体") continue;

            // 优先级比较
            var pri:Number = mark.priority;
            if (pri > bestPriority) {
                bestPriority = pri;
                bestSkill = sk;
            }
        }

        if (bestSkill != null) {
            // 执行 buff 技能
            self.技能等级 = bestSkill.技能等级;
            bestSkill.上次使用时间 = nowMs;
            _root.技能路由.技能标签跳转_旧(self, bestSkill.技能名);
            // 施放后长冷却，等技能动画完成再考虑下一个
            _preBuffCooldownFrame = currentFrame + 30;
        } else {
            // 无可用 buff，短冷却后再检查
            _preBuffCooldownFrame = currentFrame + 20;
        }
    }

    // ═══════ 1. 交战动作选择 ═══════

    /**
     * selectCombatAction — 替换 HeroCombatModule.selectSkill
     *
     * 在 Engaging 状态的 onAction 中每帧调用。
     * 管线：Filter → Score(+Stance+Tactical) → Anti-oscillation → Freq → Boltzmann
     */
    public function selectCombatAction(data:UnitAIData):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 预计算决策间隔参数（频率校正 + commitment 锁共用）
        var commitment:Number = p.chaseCommitment;
        if (isNaN(commitment)) commitment = 5;
        var reactionMult:Number = p.tickInterval;
        if (isNaN(reactionMult) || reactionMult < 1) reactionMult = 1;

        // ── commitment 锁 ──
        // 技能阶段：软评估 — "Continue" 高分候选参与 Boltzmann 竞争
        //   技能只能被技能取消（BasicAttack 不参与），不能被平A取消
        // 平A阶段：硬锁（短期内不重新评估）
        //   平A可以被技能取消（commitment 过期后自然进入正常评估）
        var inSkillPhase:Boolean = false;
        if (currentFrame < _commitUntilFrame) {
            if (_lastActionType == "skill") {
                inSkillPhase = true;
                // 不 return：继续到候选构建，但 BasicAttack 被排除
            } else {
                repeatLastAction(self);
                return;
            }
        }

        // ── 战术偏置过期检查 ──
        if (_tacticalBias != null && currentFrame >= _tacticalBias.expiryFrame) {
            _tacticalBias = null;
        }

        // ── 1. Filter: 构建候选列表 ──
        var candidates:Array = this._candidates;
        candidates.length = 0;

        // BasicAttack（技能阶段不可用 — 技能只能被技能取消，不能被平A取消）
        if (!inSkillPhase) {
            candidates.push({name: "BasicAttack", type: "attack", score: 0});
        }

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

                // 全局buff已激活 → 排除（兴奋剂/铁布衫等场景永久buff不重复使用）
                var preBuffMark:Object = _root.技能函数.预战buff标记[sk.技能名];
                if (preBuffMark != null && preBuffMark.global && preBuffMark.buffId != null) {
                    if (self.buffManager != null && self.buffManager.getBuffById(preBuffMark.buffId) != null) continue;
                }

                candidates.push({
                    name: sk.技能名,
                    type: "skill",
                    skill: sk,
                    score: 0
                });
                skillCount++;
            }
        }

        // ── 2. Score: 多维评分 + Stance 调制 + 战术偏置 ──
        var evalDepth:Number = p.evalDepth;
        if (isNaN(evalDepth) || evalDepth < 1) evalDepth = 1;
        if (evalDepth > 5) evalDepth = 5;

        var noise:Number = p.decisionNoise;
        if (isNaN(noise)) noise = 0.5;

        // 特殊角色加成
        var skillBonus:Number = 0;
        if (self.名字 == "尾上世莉架") skillBonus = 0.3;

        // 刚体（超级装甲）状态检测 — 循环外预计算
        var isRigid:Boolean = (self.刚体 == true) || (self.man.刚体标签 != null && self.man.刚体标签 != undefined);

        // 缓存 stance/tactical 引用（避免循环内重复解引用）
        var stance:Object = _currentStance;
        var tactical:Object = _tacticalBias;

        for (var j:Number = 0; j < candidates.length; j++) {
            var c:Object = candidates[j];
            var total:Number = 0;

            for (var d:Number = 0; d < evalDepth; d++) {
                var w:Number = p[DIM_WEIGHTS[d]];
                if (isNaN(w)) w = 0.2;

                // Stance 维度权重调制
                if (stance != null) {
                    var dm:Number = stance.dimMod[d];
                    if (!isNaN(dm)) w += dm;
                }

                total += w * scoreDimension(d, c, data, self);
            }

            // 特殊角色加成
            if (c.type == "skill" && skillBonus > 0) {
                total += skillBonus;
            }

            // ── Stance 候选加成 ──
            if (stance != null) {
                if (c.type == "attack") {
                    total += stance.attackBonus;
                } else if (c.type == "skill") {
                    // 技能类型亲和
                    var aff:Number = stance.skillAffinity[c.skill.类型];
                    if (!isNaN(aff)) total += aff;

                    // 手雷距离窗口
                    if (stance.optDistMin != undefined) {
                        if (xDist >= stance.optDistMin && xDist <= stance.optDistMax) {
                            total += 0.3;
                        } else {
                            total -= 0.15;
                        }
                    }
                }
            }

            // ── 战术偏置 ──
            if (tactical != null) {
                if (c.type == "attack") {
                    total += tactical.attackBonus;
                } else if (c.type == "skill") {
                    var tb:Number = tactical.skillType[c.skill.类型];
                    if (!isNaN(tb)) total += tb;
                }
            }

            // ── 刚体状态感知 ──
            // 增益技能的主要贡献是提供刚体状态，输出极低；
            // 已有刚体时大幅降权（避免重复施放），同时鼓励攻击性行为利用霸体窗口
            if (isRigid) {
                if (c.type == "skill" && c.skill.功能 == "增益") {
                    total -= 0.8;
                } else if (c.type == "attack") {
                    total += 0.15;
                } else if (c.type == "skill") {
                    var rigidFunc:String = c.skill.功能;
                    // 近战/输出类技能在霸体窗口期加分（不会被打断）
                    if (rigidFunc != "躲避") total += 0.1;
                }
            }

            // ── 距离压力（远程被近身应急）──
            // 远程姿态 + 敌人侵入保持距离以内 → 躲避/位移技能升权
            // 勇气调制：低勇气急于脱离，高勇气沉着应对（可能触发武器切换近战）
            if (stance != null && stance.repositionDir > 0 && xDist < data.xdistance) {
                // 0~1: 越近压力越大（dist=0 → 1, dist=xdistance → 0）
                var rangePressure:Number = 1 - xDist / data.xdistance;
                rangePressure *= (1 - (p.勇气 || 0));  // 勇气抵消

                if (c.type == "skill") {
                    var rpFunc:String = c.skill.功能;
                    // 躲避类（翻滚换弹等）：最高优先
                    if (rpFunc == "躲避") total += rangePressure * 0.5;
                    // 位移类（闪现等）：高优先
                    else if (rpFunc == "位移" || rpFunc == "高频位移") total += rangePressure * 0.4;
                } else if (c.type == "attack") {
                    // 被贴脸时远程普攻效率低，轻惩罚
                    total -= rangePressure * 0.15;
                }
            }

            // 技术噪声（高技术→低噪声→更准确）
            total += (_rng.nextFloat() - 0.5) * noise;

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

        // ── 技能延续候选：固定高分，跳过评分管线 ──
        // 在 Boltzmann 前注入，不参与维度评分/反抖动/频率校正
        // 高分（1.5）确保大多数情况下技能动画继续播放
        // 只有特别高分的替代技能（紧急/完美时机）才能竞争胜出
        if (inSkillPhase) {
            candidates.push({name: "Continue", type: "continue", score: 1.5});
        }

        // ── 4. Boltzmann 选择 ──
        var selected:Object = boltzmannSelect(candidates, T);

        // ── 5. 技能属性预写入（必须在 executeCombatAction 之前）──
        // 技能路由 技能标签跳转_旧 内部读取 self.技能等级 决定技能版本，
        // 上次使用时间 也必须在路由前写入以防同帧重入冷却检查
        if (selected.type == "skill") {
            self.技能等级 = selected.skill.技能等级;
            selected.skill.上次使用时间 = nowMs;
        }

        // ── 6. 执行 ──
        executeCombatAction(selected, self);

        // ── 7. 战术偏置触发 + 武器切换锁 ──
        if (selected.type == "skill") {
            triggerTacticalBias(selected.skill, currentFrame);
            _lastSkillUseFrame = currentFrame; // 技能动画保护：18帧内禁止切换武器
        }

        // ── 8. 更新评估器内部状态 ──
        // Continue（延续技能）：不更新任何状态，保留技能阶段上下文
        // → 下一帧 _lastActionType 仍为 "skill"，_commitUntilFrame 不变
        // → 自然维持技能阶段直到 commitment 过期或被其他技能取代
        if (selected.type != "continue") {
            _commitUntilFrame = currentFrame + Math.round(commitment * reactionMult);
            _lastActionType = selected.type;

            if (selected.type == "skill") {
                if (_lastSkillName == selected.name) {
                    _repeatCount++;
                } else {
                    _repeatCount = 0;
                }
                _lastSkillName = selected.name;
            } else {
                _repeatCount = 0;
            }
        }

        // ── 9. Debug 输出 ──
        if (_root.AI调试模式 == true) {
            debugTop3(candidates, selected, self, T);
        }
    }

    // ── 战术偏置触发 ──

    /**
     * triggerTacticalBias — 技能执行后设定短期评分偏置
     *
     * 位移技能 → 后续 tick 提升近战/连招评分（"闪现突击"效果）
     * 增益技能 → 后续 tick 提升攻击性评分（"霸体冲锋"效果）
     * 躲避技能 → 后续 tick 提升反击评分（"规避反击"效果）
     *
     * 偏置自然过期（expiryFrame），无需独立状态机
     */
    public function triggerTacticalBias(skill:Object, currentFrame:Number):Void {
        var func:String = skill.功能;

        if (func == "位移" || func == "高频位移") {
            // 闪现突击：位移后追加近战连招
            _tacticalBias = {
                skillType: {格斗: 0.3, 刀技: 0.3, 火器: 0.1},
                attackBonus: 0.2,
                expiryFrame: currentFrame + 8
            };
        } else if (func == "增益") {
            // 霸体冲锋：buff 后提升攻击性
            _tacticalBias = {
                skillType: {格斗: 0.2, 刀技: 0.2, 火器: 0.2},
                attackBonus: 0.15,
                expiryFrame: currentFrame + 12
            };
        } else if (func == "躲避") {
            // 规避反击：闪避后窗口期反击
            _tacticalBias = {
                skillType: {格斗: 0.25, 刀技: 0.2},
                attackBonus: 0.1,
                expiryFrame: currentFrame + 6
            };
        }
        // 其他技能类型不触发战术偏置
    }

    // ── 单维度评分 ──

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
            // 被击加分（+0.5）由 ActionArbiter._scoreCandidates 处理
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

    // ── Boltzmann 选择 ──

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
            case "continue":
                // 延续当前技能动画 — 不输出任何动作指令
                break;
        }
    }

    private function repeatLastAction(self:MovieClip):Void {
        // commitment 锁期内一律输出普攻:
        // - 技能是一次性路由（动画触发后引擎接管），不能也不需要"重复"
        // - hold 只在决策帧有意义，后续帧空输出 = 发呆
        // 锁的作用是阻止重新选择动作，不是阻止攻击输出
        self.动作A = true;
        if (self.攻击模式 === "双枪") self.动作B = true;
    }

    // ═══════ 2. 武器模式选择 ═══════

    /**
     * getAmmoRatio — 指定武器模式的余弹比
     *
     * @return 1.0=满弹, 0.0=空弹; 近战模式返回 1.0
     *         双枪取两把中较低值（短板决定切换紧迫度）
     */
    public function getAmmoRatio(self:MovieClip, mode:String):Number {
        switch (mode) {
            case "长枪":
                if (self.长枪弹匣容量 > 0) return 1 - self.长枪.value.shot / self.长枪弹匣容量;
                break;
            case "手枪":
                if (self.手枪弹匣容量 > 0) return 1 - self.手枪.value.shot / self.手枪弹匣容量;
                break;
            case "双枪":
                var r1:Number = (self.手枪弹匣容量 > 0) ? (1 - self.手枪.value.shot / self.手枪弹匣容量) : 1;
                var r2:Number = (self.手枪2弹匣容量 > 0) ? (1 - self.手枪2.value.shot / self.手枪2弹匣容量) : 1;
                return (r1 < r2) ? r1 : r2; // 短板值
        }
        return 1.0; // 近战/空手/无限弹药
    }

    /**
     * shouldReload — 当前远程武器是否需要主动换弹
     *
     * 由 HeroCombatModule.chase()/engage() 调用
     * 条件：远程姿态 + 余弹低于阈值 + 非换弹中
     * @param threshold 余弹比阈值，低于此值触发（默认 0.3）
     * @return true=应该换弹
     */
    public function shouldReload(data:UnitAIData, threshold:Number):Boolean {
        if (_currentStance == null || _currentStance.repositionDir <= 0) return false;
        var self:MovieClip = data.self;
        if (self.man.换弹标签) return false; // 已在换弹
        var ratio:Number = getAmmoRatio(self, self.攻击模式);
        return ratio < threshold;
    }

    /**
     * evaluateWeaponMode — 替换 HeroCombatBehavior.evaluateWeapon
     *
     * 在 Selector 中每次决策时调用。
     * 评估各可用武器模式 → 切换最优 → 设定攻击范围参数 → 同步 Stance。
     *
     * 紧急前置：远程空弹 + 近距 → 直接切近战（不走评分）
     * 余弹比参与武器评分（弹药快耗尽的武器降权）
     */
    public function evaluateWeaponMode(data:UnitAIData):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 武器切换冷却（8帧 ≈ 0.3s，配合 unitUpdateWheel 4帧间隔 = 每2个AI tick评估一次）
        if (currentFrame - _lastWeaponSwitchFrame < 8) {
            applyWeaponRanges(self, data);
            syncStance(self.攻击模式);
            return;
        }

        // 检查装备
        var has刀:Boolean = self.刀 ? true : false;
        var has长枪:Boolean = self.长枪 ? true : false;
        var has手枪:Boolean = self.手枪 ? true : false;
        var has手枪2:Boolean = self.手枪2 ? true : false;
        var hasWeapon:Boolean = has刀 || has长枪 || has手枪 || has手枪2;

        if (!hasWeapon) {
            applyWeaponRanges(self, data);
            syncStance(self.攻击模式);
            return;
        }

        // 估算到目标的距离
        var dist:Number = 200;
        if (data.target != null) {
            data.updateSelf();
            data.updateTarget();
            dist = data.absdiff_x;
        }

        // ── 紧急前置：远程空弹 + 近距 → 直接切近战 ──
        // 不走评分，生死攸关不交给概率
        if (_currentStance != null && _currentStance.repositionDir > 0) {
            var curAmmo:Number = getAmmoRatio(self, self.攻击模式);
            if (curAmmo <= 0 && dist < 150 && has刀) {
                self.攻击模式切换("兵器");
                _lastWeaponSwitchFrame = currentFrame;
                applyWeaponRanges(self, data);
                syncStance("兵器");
                if (_root.AI调试模式 == true) {
                    _root.服务器.发布服务器消息("[WPN] " + self.名字 + " EMERGENCY melee! ammo=0 dist=" + Math.round(dist));
                }
                return;
            }
        }

        // 技能动画保护：使用技能后 18帧（≈0.6s）内禁止切换武器
        // 放在紧急切换之后：空弹贴脸是生死问题不受此限制
        if (currentFrame - _lastSkillUseFrame < 18) {
            applyWeaponRanges(self, data);
            syncStance(self.攻击模式);
            return;
        }

        // 生命值比例（供武器评分中生存压力计算）
        var hpRatio:Number = self.hp / self.hp满血值;
        if (isNaN(hpRatio) || hpRatio > 1) hpRatio = 1;
        if (hpRatio < 0) hpRatio = 0;

        // 生存压力（切换成本 + debug 共用）
        var courage:Number = p.勇气 || 0;
        var healthPressure:Number = (1 - hpRatio) * (1 - courage);

        // 评估各可用模式
        var bestMode:String = self.攻击模式;
        var bestScore:Number = -999;
        var modes:Array = ["空手"];
        if (has刀) modes.push("兵器");
        if (has手枪 && has手枪2) {
            modes.push("双枪");
        } else if (has手枪 || has手枪2) {
            modes.push("手枪");
        }
        if (has长枪) modes.push("长枪");

        // 切换成本/迟滞（从 personality 读取，fallback 硬编码）
        var baseSwitchCost:Number = p.weaponSwitchCost;
        if (isNaN(baseSwitchCost) || baseSwitchCost < 0.05) baseSwitchCost = 0.2;
        var hysteresis:Number = p.weaponHysteresis;
        if (isNaN(hysteresis) || hysteresis < 0) hysteresis = 0.1;

        for (var i:Number = 0; i < modes.length; i++) {
            var mode:String = modes[i];
            var score:Number = scoreWeaponMode(mode, dist, hpRatio);

            // ── 射程匹配度 ──
            // 在最优区间内 → +0.1；偏离 → 按距离线性惩罚，封顶 -0.3
            var wRange:Object = WEAPON_RANGES[mode];
            if (wRange != null) {
                if (dist < wRange.min) {
                    var underPenalty:Number = -(wRange.min - dist) / 200;
                    score += (underPenalty < -0.3) ? -0.3 : underPenalty;
                } else if (dist > wRange.max) {
                    var overPenalty:Number = -(dist - wRange.max) / 200;
                    score += (overPenalty < -0.3) ? -0.3 : overPenalty;
                } else {
                    score += 0.1; // 在最优区间内
                }
            }

            // ── 余弹比评分调制 ──
            // 满弹=+0.1, 半弹=0, 空弹=-0.5（大惩罚直接淘汰）
            var ammoR:Number = getAmmoRatio(self, mode);
            if (ammoR <= 0) {
                score -= 0.5;
            } else {
                score += (ammoR - 0.5) * 0.2;
            }

            // ── 切换成本 + 迟滞（hysteresis）──
            // 切入新武器：需要越过 switchCost 关卡
            // 维持当前武器：获得 hysteresis 加分（形成死区，抑制抖动）
            if (mode == self.攻击模式) {
                score += hysteresis; // 维持当前 → 加分
            } else {
                var switchCost:Number = baseSwitchCost * (1 - healthPressure * 0.7);
                if (switchCost < 0.05) switchCost = 0.05;
                score -= switchCost; // 切换 → 惩罚
            }

            if (score > bestScore) {
                bestScore = score;
                bestMode = mode;
            }
        }

        // 执行切换
        var didSwitch:Boolean = false;
        if (bestMode != self.攻击模式 && bestMode != "空手") {
            var prevMode:String = self.攻击模式;
            self.攻击模式切换(bestMode);
            didSwitch = true;
        }

        // 更新评估帧（无论是否切换，防止每帧重复评估）
        _lastWeaponSwitchFrame = currentFrame;

        applyWeaponRanges(self, data);
        syncStance(self.攻击模式);

        // ── Debug 武器评估输出 ──
        if (_root.AI调试模式 == true) {
            var curMode:String = didSwitch ? prevMode : self.攻击模式;
            var dbgSwitchCost:Number = baseSwitchCost * (1 - healthPressure * 0.7);
            if (dbgSwitchCost < 0.05) dbgSwitchCost = 0.05;
            var wmsg:String = "[WPN] " + self.名字 + " cur=" + curMode + " sc=" + (Math.round(dbgSwitchCost * 100) / 100) + " hy=" + (Math.round(hysteresis * 100) / 100) + " | ";
            for (var di:Number = 0; di < modes.length; di++) {
                var dm:String = modes[di];
                var ds:Number = scoreWeaponMode(dm, dist, hpRatio);
                var ar:Number = getAmmoRatio(self, dm);
                var ammoAdj:Number = (ar <= 0) ? -0.5 : ((ar - 0.5) * 0.2);
                var dsc:Number = (dm != curMode) ? -dbgSwitchCost : 0;
                wmsg += dm + "=" + (Math.round((ds + ammoAdj + dsc) * 100) / 100);
                // 远程武器显示余弹比
                if (dm != "空手" && dm != "兵器") wmsg += "[" + Math.round(ar * 100) + "%]";
                wmsg += " ";
            }
            wmsg += "-> " + bestMode + (didSwitch ? " SWITCH!" : " hold");
            wmsg += " [dist=" + Math.round(dist) + " hp=" + Math.round(hpRatio * 100) + "% pr=" + (Math.round(healthPressure * 100) / 100) + "]";
            _root.服务器.发布服务器消息(wmsg);
        }
    }

    /**
     * scoreWeaponMode — 武器模式评分
     *
     * 设计原则：
     *   武器选择主要由人格（勇气/智力）和生存压力驱动，
     *   当前距离只做轻度调制（±0.1 级别），因为切换武器后
     *   AI 会通过 repositionDir + xdistance 自动调整站位。
     *
     * 评分结构：
     *   base（0.5 统一基准）+ 人格加成 + 生存压力 + 距离微调
     *
     * 生存压力：healthPressure = (1 - hpRatio) × (1 - 勇气)
     *   满血: ≈0, 无影响
     *   低血+低勇气: 高压 → 强烈偏向远程
     *   低血+高勇气: 低压 → 维持近战
     */
    private function scoreWeaponMode(mode:String, dist:Number, hpRatio:Number):Number {
        var score:Number = 0;
        var courage:Number = p.勇气 || 0;
        var intel:Number = p.智力 || 0;
        var mastery:Number = p.stanceMastery || 0;
        var stability:Number = p.stabilityFactor || 0;

        // 生存压力：(1 - 血量比) × (1 - 勇气)
        var healthPressure:Number = (1 - hpRatio) * (1 - courage);

        switch (mode) {
            case "空手":
                // 基准 + 勇气驱动近战倾向 + 熟练度
                score = 0.5 + courage * 0.35 + mastery * 0.15;
                // 近战：生存压力惩罚
                score -= healthPressure * 0.5;
                // 距离微调：近距小加分，远距轻惩罚
                if (dist < 80) score += 0.05;
                else if (dist > 200) score -= 0.1;
                break;
            case "兵器":
                // 基准偏高（有武器 > 没武器）+ 勇气 + 熟练度
                score = 0.55 + courage * 0.3 + mastery * 0.15;
                // 近战：生存压力惩罚（略低于空手，有距离优势）
                score -= healthPressure * 0.4;
                // 距离微调
                if (dist < 180) score += 0.05;
                else if (dist > 300) score -= 0.1;
                break;
            case "手枪":
                // 基准 + 智力驱动远程倾向 + 稳定性
                score = 0.5 + intel * 0.3 + stability * 0.15;
                // 远程：生存压力加分
                score += healthPressure * 0.35;
                // 距离微调：远距小加分，极近轻惩罚
                if (dist > 150) score += 0.05;
                else if (dist < 60) score -= 0.1;
                break;
            case "双枪":
                // 双持：火力密度高于单手枪，适用距离更灵活
                score = 0.5 + intel * 0.25 + courage * 0.1 + stability * 0.1;
                // 远程：生存压力加分
                score += healthPressure * 0.35;
                // 距离微调：比手枪更适应中近距
                if (dist > 120) score += 0.05;
                else if (dist < 50) score -= 0.1;
                break;
            case "长枪":
                // 基准 + 智力 + 稳定性
                score = 0.5 + intel * 0.3 + stability * 0.15;
                // 远程：生存压力加分（最安全选择）
                score += healthPressure * 0.4;
                // 距离微调
                if (dist > 200) score += 0.05;
                else if (dist < 80) score -= 0.1;
                break;
        }

        // ── 武器威力系数偏移（DPS 代理层）──
        // 中心化：兵器(0.5) = 中性不变，< 0.5 降权，> 0.5 升权
        // 后续替换：WEAPON_POWER[mode] → self[mode].dps / referenceDPS
        var power:Number = WEAPON_POWER[mode];
        if (power == undefined) power = 0.5; // 未知模式 → 中性
        score += (power - 0.5) * POWER_WEIGHT;

        return score;
    }

    /**
     * 根据当前攻击模式设定范围参数
     * 保留原始 Phase 1 的硬编码值（这些是游戏平衡参数）
     */
    public function applyWeaponRanges(self:MovieClip, data:UnitAIData):Void {
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

    public function debugTop3(candidates:Array, selected:Object, self:MovieClip, T:Number):Void {
        // 计算概率分母（所有候选的 exp 权重之和）
        var sumExp:Number = 0;
        for (var s:Number = 0; s < candidates.length; s++) {
            sumExp += candidates[s]._ew;
        }
        if (sumExp <= 0) sumExp = 1; // 防除零

        // 按分数降序排列（浅拷贝）
        var sorted:Array = candidates.slice(0);
        sorted.sort(function(a, b) {
            return (b.score > a.score) ? 1 : ((b.score < a.score) ? -1 : 0);
        });

        // Stance 标签
        var stanceTag:String = (_currentStance != null) ? (" S:" + self.攻击模式) : "";
        // 战术偏置标签
        var tactTag:String = (_tacticalBias != null) ? " T!" : "";
        // 刚体标签
        var rigidTag:String = ((self.刚体 == true) || (self.man.刚体标签 != null && self.man.刚体标签 != undefined)) ? " R!" : "";

        var msg:String = "[AI] " + self.名字 + stanceTag + tactTag + rigidTag + " Top3: ";
        var count:Number = sorted.length < 3 ? sorted.length : 3;
        for (var i:Number = 0; i < count; i++) {
            var ci:Object = sorted[i];
            var prob:Number = Math.round(ci._ew / sumExp * 100);
            msg += ci.name + "=" + (Math.round(ci.score * 100) / 100) + "(" + prob + "%)";
            if (i < count - 1) msg += ", ";
        }
        msg += " -> " + selected.name + " [T=" + (Math.round(T * 100) / 100) + "]";
        _root.服务器.发布服务器消息(msg);
    }
}
