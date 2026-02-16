import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;
import org.flashNight.arki.unit.UnitAI.ActionExecutor;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * ActionArbiter — 统一动作决策管线
 *
 * 职责：
 *   1. 按 context（chase/engage/selector）激活策略组，收集候选
 *   2. 通过 ActionExecutor 按中断规则过滤
 *   3. 注入 Continue 候选（保护当前动作）
 *   4. 委托 UtilityEvaluator 评分 + Boltzmann 选择
 *   5. 通过 ActionExecutor 统一执行
 *
 * 三轨并行：
 *   body  : 技能/平A/换弹/预战buff — 互斥管线（本类核心）
 *   stance: 武器模式选择 — 独立冷却
 *   item  : 血包使用 — 独立冷却
 *
 * Candidate 结构：
 *   { name, type, priority, commitFrames, score, skill?, mode? }
 *   priority: 0=emergency(躲避/解围霸体), 1=skill/preBuff, 2=reload, 3=attack
 *   中断规则：严格小于（<）才能中断 → 同优先级不互断
 */
class org.flashNight.arki.unit.UnitAI.ActionArbiter {

    // ── 组件引用 ──
    private var _executor:ActionExecutor;
    private var _scorer:UtilityEvaluator;
    private var p:Object;                    // personality 引用
    private var _rng:LinearCongruentialEngine;

    // ── 复用候选池 ──
    private var _candidates:Array;

    // ── 反抖动状态（从 UtilityEvaluator 迁出）──
    private var _lastActionType:String;
    private var _lastSkillName:String;
    private var _repeatCount:Number;

    // ── 预战buff帧节流 ──
    private var _preBuffCooldownFrame:Number;

    // ── 事件响应状态 ──
    private var _recentHitFrame:Number;         // 最近一次被击中的帧号
    private var _selfRef:MovieClip;             // self 引用（事件订阅/退订）
    private var _onHitCallback:Function;        // hit 回调（退订用）
    private var _onSkillEndCallback:Function;   // skillEnd 回调（退订用）

    // ═══════ 构造 ═══════

    public function ActionArbiter(personality:Object, scorer:UtilityEvaluator, self:MovieClip) {
        this.p = personality;
        this._scorer = scorer;
        this._executor = new ActionExecutor();
        this._rng = LinearCongruentialEngine.getInstance();
        this._candidates = [];
        this._lastActionType = null;
        this._lastSkillName = null;
        this._repeatCount = 0;
        this._preBuffCooldownFrame = 0;
        this._recentHitFrame = -999;
        this._selfRef = self;

        // ── 事件订阅 ──
        if (self.dispatcher != undefined && self.dispatcher != null) {
            var arbiter:ActionArbiter = this;

            // 被击事件：记录帧号，用于反应性躲避评分
            this._onHitCallback = function() {
                arbiter._recentHitFrame = _root.帧计时器.当前帧数;
            };
            self.dispatcher.subscribe("hit", this._onHitCallback, arbiter);

            // 技能结束事件：立即释放帧锁，消除"技能后发呆"
            this._onSkillEndCallback = function() {
                // 安全检查：只在技能/战技正常结束后才释放
                // 如果 状态 仍是"技能"/"战技"，说明被另一个技能中断了，不释放
                var currentState:String = self.状态;
                if (currentState != "技能" && currentState != "战技") {
                    arbiter._executor.expireBodyCommit();
                }
            };
            self.dispatcher.subscribe("skillEnd", this._onSkillEndCallback, arbiter);
        }
    }

    // ═══════ 公开接口 ═══════

    /**
     * getRepositionDir — 委托 scorer 读取当前 Stance 位移倾向
     * HeroCombatModule.engage() 用于风筝逻辑
     */
    public function getRepositionDir():Number {
        return _scorer.getRepositionDir();
    }

    /**
     * getExecutor — 供外部查询 body/stance/item 状态
     */
    public function getExecutor():ActionExecutor {
        return _executor;
    }

    // ═══════ 核心管线 ═══════

    /**
     * tick — 每 AI 帧唯一入口
     *
     * @param data    共享 AI 数据
     * @param context "chase" | "engage" | "selector"
     */
    public function tick(data:UnitAIData, context:String):Void {
        var frame:Number = _root.帧计时器.当前帧数;
        var self:MovieClip = data.self;

        // ═══ body 轨：统一动作选择 ═══

        // 刷新动画标签锁（换弹标签 / 刚体 / 刚体标签）
        _executor.updateAnimLock(self);

        var candidates:Array = _candidates;
        candidates.length = 0;

        // 1. 策略组按 context 注入候选
        if (_executor.isAnimLocked()) {
            // 动画锁期间：仅收集紧急候选（priority=0: 躲避/解围霸体）
            // 换弹/技能刚体动画不应被普通技能/平A/换弹打断
            if (context == "engage" || context == "chase") {
                _collectOffense(data, candidates);
                for (var ri:Number = candidates.length - 1; ri >= 0; ri--) {
                    if (candidates[ri].priority > 0) candidates.splice(ri, 1);
                }
            }
        } else {
            switch (context) {
                case "engage":
                    _collectOffense(data, candidates);      // priority 0(emergency) / 1(skill) / 3(attack)
                    _collectReload(data, candidates);       // priority 2
                    break;
                case "chase":
                    _collectPreBuff(data, candidates);      // priority 1
                    _collectReload(data, candidates);       // priority 2
                    break;
                case "selector":
                    // body 轨无候选（selector 是瞬态，只做 stance + item 评估）
                    break;
            }
        }

        // 2. 中断过滤 + hold/trigger 分流
        //
        // 输入语义区分：
        //   attack = hold 型（持续按键）→ 不注入 Continue，由 holdCurrentBody 维持
        //   skill/reload/preBuff = trigger 型（一次性触发）→ Continue 作为 Boltzmann 屏障
        //
        if (candidates.length > 0) {
            var isCommitted:Boolean = _executor.isBodyCommitted(frame);
            var holdAttack:Boolean = false;

            if (isCommitted) {
                _filterByInterrupt(candidates, frame);

                if (_executor.getCurrentBodyType() == "attack") {
                    // ── Hold 语义 ──
                    // 不注入 Continue → Boltzmann 只在能抢断的候选中选
                    // 无候选/无新动作 → holdCurrentBody 维持 動作A
                    holdAttack = true;
                } else {
                    // ── Trigger 语义 ──
                    // Continue 分数屏障：保护技能/换弹动画不被低分候选打断
                    candidates.push({
                        name: "Continue", type: "continue", priority: -1,
                        score: _executor.getContinueScore()
                    });
                }
            }

            // 3. 评分 + Boltzmann + 执行
            if (candidates.length > 0) {
                var T:Number = p.temperature;
                if (isNaN(T) || T < 0.01) T = 0.2;

                _scoreCandidates(candidates, data, self, T);
                var selected:Object = _scorer.boltzmannSelect(candidates, T);

                if (selected != null) {
                    // 技能属性预写入（必须在 execute 之前）
                    if (selected.type == "skill" || selected.type == "preBuff") {
                        if (selected.skill != null) {
                            self.技能等级 = selected.skill.技能等级;
                            selected.skill.上次使用时间 = getTimer();
                        }
                    }

                    // 执行
                    _executor.execute(selected, self);

                    // 提交 commitment + 后处理（Continue 不提交）
                    if (selected.type != "continue") {
                        var commitF:Number = selected.commitFrames;
                        if (isNaN(commitF)) commitF = 5;
                        var reactionMult:Number = p.tickInterval || 1;
                        if (reactionMult < 1) reactionMult = 1;
                        _executor.commitBody(selected.type, selected.priority,
                            Math.round(commitF * reactionMult), frame);
                        _postExecution(selected, data, frame);
                        holdAttack = false; // 新动作已接管 body 轨
                    }

                    // Debug 输出
                    if (_root.AI调试模式 == true) {
                        _scorer.debugTop3(candidates, selected, self, T);
                    }
                }
            }

            // 4. Attack hold：无新动作打断 → 维持按键输出
            if (holdAttack) {
                _executor.holdCurrentBody(self);
            }
        }

        // ═══ stance 轨：武器模式选择 ═══
        _evaluateStance(data, context, frame);

        // ═══ item 轨：血包使用 ═══
        // 所有 context 均可评估（使用间隔由 evaluateHealNeed 内部控制）
        _evaluateHeal(data);
    }

    // ═══════ 策略组：Offense（技能 + 平A）═══════

    private function _collectOffense(data:UnitAIData, candidates:Array):Void {
        var self:MovieClip = data.self;

        // 平A commitment：短窗口，容易被技能取消
        var attackCommit:Number = p.chaseCommitment;
        if (isNaN(attackCommit) || attackCommit < 2) attackCommit = 5;

        // 技能 commitment：独立且更长，保护技能动画最小执行窗口
        var skillCommit:Number = p.skillCommitFrames;
        if (isNaN(skillCommit) || skillCommit < 5) skillCommit = 10;

        // BasicAttack
        candidates.push({
            name: "BasicAttack", type: "attack", priority: 3,
            commitFrames: attackCommit, score: 0
        });

        // Skills（距离 + 冷却 + buff 过滤）
        var skills:Array = self.已学技能表;
        var nowMs:Number = getTimer();
        var xDist:Number = data.absdiff_x;
        var maxC:Number = p.maxCandidates;
        if (isNaN(maxC) || maxC < 2) maxC = 8;
        var skillCount:Number = 0;

        if (skills != null) {
            for (var i:Number = 0; i < skills.length && skillCount < maxC; i++) {
                var sk:Object = skills[i];
                if (xDist < sk.距离min || xDist > sk.距离max) continue;
                if (!isNaN(sk.上次使用时间) && (nowMs - sk.上次使用时间 <= sk.冷却 * 1000)) continue;

                // 全局buff已激活 → 排除
                var preBuffMark:Object = _root.技能函数.预战buff标记[sk.技能名];
                if (preBuffMark != null && preBuffMark.global && preBuffMark.buffId != null) {
                    if (self.buffManager != null && self.buffManager.getBuffById(preBuffMark.buffId) != null) continue;
                }

                // 优先级：解围霸体常驻 emergency(0)；躲避仅受威胁时为 0
                var skillPri:Number = 1;
                if (sk.功能 == "解围霸体") {
                    skillPri = 0;
                } else if (sk.功能 == "躲避") {
                    // underFire: 近期被击 OR 目标正在攻击/施技
                    var dw:Number = p.dodgeReactWindow;
                    if (isNaN(dw) || dw < 5) dw = 20;
                    var ha:Number = _root.帧计时器.当前帧数 - _recentHitFrame;
                    var tgt:MovieClip = data.target;
                    var threat:Boolean = (ha >= 0 && ha < dw);
                    if (!threat && tgt != null) {
                        threat = (tgt.射击中 == true || tgt.状态 == "技能" || tgt.状态 == "战技");
                    }
                    skillPri = threat ? 0 : 1;
                }
                candidates.push({
                    name: sk.技能名, type: "skill", priority: skillPri,
                    skill: sk, commitFrames: skillCommit, score: 0
                });
                skillCount++;
            }
        }
    }

    // ═══════ 策略组：Reload（换弹）═══════

    private function _collectReload(data:UnitAIData, candidates:Array):Void {
        var self:MovieClip = data.self;

        // 非远程姿态不换弹
        if (_scorer.getRepositionDir() <= 0) return;
        // 已在换弹
        if (self.man.换弹标签) return;

        var ratio:Number = _scorer.getAmmoRatio(self, self.攻击模式);
        // 弹药充足不需要
        if (ratio >= 0.5) return;

        // 评分：弹药越少越高 + 距离系数
        var urgency:Number = (1 - ratio); // 0~1
        var safeDist:Number = (data.xdistance > 0) ? (data.absdiff_x / data.xdistance) : 1;
        var distBonus:Number = (safeDist > 1) ? 0.3 : -0.2;
        var score:Number = 0.3 + urgency * 0.5 + distBonus;

        var reloadCommit:Number = p.reloadCommitFrames;
        if (isNaN(reloadCommit) || reloadCommit < 15) reloadCommit = 30;
        candidates.push({
            name: "Reload", type: "reload", priority: 2,
            commitFrames: reloadCommit, score: score  // 主保护靠动画标签锁（换弹标签/刚体）
        });
    }

    // ═══════ 策略组：PreBuff（预战增益）═══════

    private function _collectPreBuff(data:UnitAIData, candidates:Array):Void {
        var self:MovieClip = data.self;
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 条件：非射击中 + 安全距离
        if (self.射击中) return;
        if (data.absdiff_x <= data.xrange * 1.5) return;

        // 帧节流
        if (currentFrame < _preBuffCooldownFrame) return;

        var skills:Array = self.已学技能表;
        if (skills == null) return;

        var marks:Object = _root.技能函数.预战buff标记;
        if (marks == null) return;

        var nowMs:Number = getTimer();
        var hasBM:Boolean = (self.buffManager != null);
        var isRigid:Boolean = (self.刚体 == true) ||
            (self.man.刚体标签 != null && self.man.刚体标签 != undefined);

        var found:Boolean = false;
        for (var i:Number = 0; i < skills.length; i++) {
            var sk:Object = skills[i];
            var mark:Object = marks[sk.技能名];
            if (mark == null) continue;

            if (!isNaN(sk.上次使用时间) && (nowMs - sk.上次使用时间 <= sk.冷却 * 1000)) continue;
            if (mark.global && hasBM && mark.buffId != null) {
                if (self.buffManager.getBuffById(mark.buffId) != null) continue;
            }
            if (isRigid && sk.功能 == "解围霸体") continue;

            var pri:Number = mark.priority || 0;
            var buffCommit:Number = p.skillCommitFrames;
            if (isNaN(buffCommit) || buffCommit < 5) buffCommit = 10;
            candidates.push({
                name: sk.技能名, type: "preBuff", priority: 1,
                skill: sk, commitFrames: buffCommit,
                score: 0.8 + pri * 0.2
            });
            found = true;
        }

        // 更新帧节流
        _preBuffCooldownFrame = currentFrame + (found ? 30 : 20);
    }

    // ═══════ 管线内部：中断过滤 ═══════

    private function _filterByInterrupt(candidates:Array, frame:Number):Void {
        for (var i:Number = candidates.length - 1; i >= 0; i--) {
            if (!_executor.canInterruptBody(candidates[i].priority, frame)) {
                candidates.splice(i, 1);
            }
        }
    }

    // ═══════ 管线内部：评分 ═══════

    /**
     * _scoreCandidates — 对候选列表评分
     *
     * Continue / Reload / PreBuff 的分数已在收集时预设，跳过评分管线。
     * Skill / Attack 走完整维度评分 + Stance 调制 + 战术偏置 + 噪声 + 反抖动 + 频率校正。
     */
    private function _scoreCandidates(candidates:Array, data:UnitAIData, self:MovieClip, T:Number):Void {
        var evalDepth:Number = p.evalDepth;
        if (isNaN(evalDepth) || evalDepth < 1) evalDepth = 1;
        if (evalDepth > 5) evalDepth = 5;

        var noise:Number = p.decisionNoise;
        if (isNaN(noise)) noise = 0.5;

        var skillBonus:Number = 0;
        if (self.名字 == "尾上世莉架") skillBonus = 0.3;

        var isRigid:Boolean = (self.刚体 == true) ||
            (self.man.刚体标签 != null && self.man.刚体标签 != undefined);

        var stance:Object = _scorer.getCurrentStance();
        var tactical:Object = _scorer.getTacticalBias();
        var xDist:Number = data.absdiff_x;

        // 战术偏置过期检查
        var currentFrame:Number = _root.帧计时器.当前帧数;
        if (tactical != null && currentFrame >= tactical.expiryFrame) {
            _scorer.clearTacticalBias();
            tactical = null;
        }

        // ── 威胁判定（驱动反应性躲避 + 距离压力门控）──
        var underFire:Boolean = false;
        var ufDodgeWin:Number = p.dodgeReactWindow;
        if (isNaN(ufDodgeWin) || ufDodgeWin < 5) ufDodgeWin = 20;
        var ufHitAge:Number = currentFrame - _recentHitFrame;
        if (ufHitAge >= 0 && ufHitAge < ufDodgeWin) underFire = true;
        if (!underFire) {
            var ufTgt:MovieClip = data.target;
            if (ufTgt != null && (ufTgt.射击中 == true || ufTgt.状态 == "技能" || ufTgt.状态 == "战技")) {
                underFire = true;
            }
        }

        // ── 维度评分循环 ──
        for (var j:Number = 0; j < candidates.length; j++) {
            var c:Object = candidates[j];

            // 跳过已预设分数的候选
            if (c.type == "continue" || c.type == "reload" || c.type == "preBuff") continue;

            var total:Number = 0;

            // 多维评分 + Stance 调制
            for (var d:Number = 0; d < evalDepth; d++) {
                var wKey:String = UtilityEvaluator.DIM_WEIGHTS[d];
                var w:Number = p[wKey];
                if (isNaN(w)) w = 0.2;

                if (stance != null) {
                    var dm:Number = stance.dimMod[d];
                    if (!isNaN(dm)) w += dm;
                }

                total += w * _scorer.scoreDimension(d, c, data, self);
            }

            // 特殊角色加成
            if (c.type == "skill" && skillBonus > 0) {
                total += skillBonus;
            }

            // Stance 候选加成
            if (stance != null) {
                if (c.type == "attack") {
                    total += stance.attackBonus;
                } else if (c.type == "skill") {
                    var aff:Number = stance.skillAffinity[c.skill.类型];
                    if (!isNaN(aff)) total += aff;

                    if (stance.optDistMin != undefined) {
                        if (xDist >= stance.optDistMin && xDist <= stance.optDistMax) {
                            total += 0.3;
                        } else {
                            total -= 0.15;
                        }
                    }
                }
            }

            // 战术偏置
            if (tactical != null) {
                if (c.type == "attack") {
                    total += tactical.attackBonus;
                } else if (c.type == "skill") {
                    var tb:Number = tactical.skillType[c.skill.类型];
                    if (!isNaN(tb)) total += tb;
                }
            }

            // 刚体状态感知
            if (isRigid) {
                if (c.type == "skill" && c.skill.功能 == "增益") {
                    total -= 0.8;
                } else if (c.type == "attack") {
                    total += 0.15;
                } else if (c.type == "skill") {
                    if (c.skill.功能 != "躲避") total += 0.1;
                }
            }

            // 距离压力（远程被近身）— 门控：躲避/普攻惩罚需 underFire
            if (stance != null && stance.repositionDir > 0 && xDist < data.xdistance) {
                var rangePressure:Number = 1 - xDist / data.xdistance;
                rangePressure *= (1 - (p.勇气 || 0));
                if (c.type == "skill") {
                    var rpFunc:String = c.skill.功能;
                    if (rpFunc == "躲避") {
                        // 躲避：仅受威胁或极近距离（< 40%射程）时加分
                        if (underFire || xDist < data.xdistance * 0.4) {
                            total += rangePressure * 0.25;
                        }
                    } else if (rpFunc == "位移" || rpFunc == "高频位移") {
                        total += rangePressure * 0.4; // 位移技能保留：走位不是怂
                    }
                } else if (c.type == "attack") {
                    // 普攻扣分：仅受威胁时（站着不动不应该被扣攻击分）
                    if (underFire) {
                        total -= rangePressure * 0.15;
                    }
                }
            }

            // 反应性躲避：受威胁时（被击/目标攻击中）大幅提升躲避优先级
            if (c.type == "skill" && c.skill.功能 == "躲避" && underFire) {
                total += 0.5;
            }

            // 决策噪声
            total += (_rng.nextFloat() - 0.5) * noise;

            c.score = total;
        }

        // ── 反抖动 ──
        var momentumDecay:Number = p.momentumDecay;
        if (isNaN(momentumDecay)) momentumDecay = 0.5;

        for (var k:Number = 0; k < candidates.length; k++) {
            var ca:Object = candidates[k];
            if (ca.type == "continue" || ca.type == "reload" || ca.type == "preBuff") continue;

            if (ca.type == _lastActionType) {
                ca.score += 0.1 * (1 - momentumDecay);
            }
            if (ca.type == "skill" && ca.name == _lastSkillName) {
                ca.score -= 0.08 * (_repeatCount + 1);
            }
        }

        // ── 频率校正 ──
        var commitment:Number = p.chaseCommitment;
        if (isNaN(commitment)) commitment = 5;
        var reactionMult:Number = p.tickInterval;
        if (isNaN(reactionMult) || reactionMult < 1) reactionMult = 1;
        var effectiveInterval:Number = commitment * reactionMult;
        if (effectiveInterval < 1) effectiveInterval = 1;
        var freqAdjust:Number = T * Math.log(effectiveInterval / 16);

        for (var fa:Number = 0; fa < candidates.length; fa++) {
            if (candidates[fa].type == "skill") {
                candidates[fa].score += freqAdjust;
            }
        }
    }

    // ═══════ 管线内部：后处理 ═══════

    private function _postExecution(selected:Object, data:UnitAIData, frame:Number):Void {
        // 战术偏置触发
        if (selected.type == "skill") {
            _scorer.triggerTacticalBias(selected.skill, frame);
        }

        // 反抖动状态更新
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

    // ═══════ stance 轨：武器模式选择 ═══════

    /**
     * _evaluateStance — 委托 scorer 进行武器评估
     *
     * 在 body 管线之后执行，独立轨道不与 body 冲突。
     * 守卫链：动画锁 → stance冷却 → 技能保护 → chase frustration
     * 参数来源：p.stanceCooldown, p.skillAnimProtect, p.chaseFrustration
     */
    private function _evaluateStance(data:UnitAIData, context:String, frame:Number):Void {
        var self:MovieClip = data.self;

        // 动画锁期间禁止切武器（换弹/技能刚体动画会被打断）
        if (_executor.isAnimLocked()) {
            _scorer.applyWeaponRanges(self, data);
            _scorer.syncStance(self.攻击模式);
            return;
        }

        // stance 冷却
        var stanceCd:Number = p.stanceCooldown;
        if (isNaN(stanceCd) || stanceCd < 4) stanceCd = 8;
        if (!_executor.canEvaluateStance(frame)) {
            _scorer.applyWeaponRanges(self, data);
            _scorer.syncStance(self.攻击模式);
            return;
        }

        // 技能动画保护：施放技能后 N 帧内禁止切武器
        var skillProtect:Number = p.skillAnimProtect;
        if (isNaN(skillProtect) || skillProtect < 8) skillProtect = 18;
        if (frame - _executor.getLastSkillUseFrame() < skillProtect) {
            _scorer.applyWeaponRanges(self, data);
            _scorer.syncStance(self.攻击模式);
            return;
        }

        // chase frustration：追击 N 帧后才评估
        var frustration:Number = p.chaseFrustration;
        if (isNaN(frustration) || frustration < 10) frustration = 40;
        if (context == "chase" && !isNaN(data._chaseStartFrame)) {
            if (frame - data._chaseStartFrame <= frustration) {
                _scorer.applyWeaponRanges(self, data);
                _scorer.syncStance(self.攻击模式);
                return;
            }
        }

        // 委托 scorer 执行实际武器评估
        _scorer.evaluateWeaponMode(data);
        _executor.commitStance(stanceCd, frame);
    }

    // ═══════ item 轨：血包使用 ═══════

    private function _evaluateHeal(data:UnitAIData):Void {
        _scorer.evaluateHealNeed(data);
    }

    // ═══════ 生命周期 ═══════

    /**
     * destroy — 清理事件订阅
     * 由单位销毁时调用，防止回调泄漏
     */
    public function destroy():Void {
        if (_selfRef != null && _selfRef.dispatcher != undefined) {
            if (_onHitCallback != null) {
                _selfRef.dispatcher.unsubscribe("hit", _onHitCallback, this);
            }
            if (_onSkillEndCallback != null) {
                _selfRef.dispatcher.unsubscribe("skillEnd", _onSkillEndCallback, this);
            }
        }
        _selfRef = null;
        _onHitCallback = null;
        _onSkillEndCallback = null;
    }
}
