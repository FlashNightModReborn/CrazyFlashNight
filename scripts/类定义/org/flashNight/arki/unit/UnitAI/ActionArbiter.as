import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;
import org.flashNight.arki.unit.UnitAI.ActionExecutor;
import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;
import org.flashNight.arki.unit.UnitAI.strategies.OffenseStrategy;
import org.flashNight.arki.unit.UnitAI.strategies.ReloadStrategy;
import org.flashNight.arki.unit.UnitAI.strategies.PreBuffStrategy;
import org.flashNight.arki.unit.UnitAI.strategies.InterruptFilter;
import org.flashNight.arki.unit.UnitAI.strategies.AnimLockFilter;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * ActionArbiter — 统一动作决策管线
 *
 * 架构：策略组（候选源 + 过滤器）+ 集中评分 + Boltzmann 选择 + 统一执行
 *
 * body 轨候选源（context → strategy[] 映射）：
 *   engage   → [OffenseStrategy, ReloadStrategy]
 *   chase    → [PreBuffStrategy, ReloadStrategy]
 *   selector → []（selector 是瞬态，只做 stance + item 评估）
 *
 * 过滤器（顺序执行）：
 *   AnimLockFilter   → 动画锁期间只保留 priority=0
 *   InterruptFilter  → 中断规则（candidate.priority < current.priority）
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

    // ── 策略组（候选源 + 过滤器）──
    private var _sources:Object;             // { "engage": [...], "chase": [...], "selector": [] }
    private var _filters:Array;              // [AnimLockFilter, InterruptFilter]

    // ── 复用候选池 ──
    private var _candidates:Array;

    // ── 反抖动状态 ──
    private var _lastActionType:String;
    private var _lastSkillName:String;
    private var _repeatCount:Number;

    // ── 事件响应状态 ──
    private var _recentHitFrame:Number;
    private var _selfRef:MovieClip;
    private var _onHitCallback:Function;
    private var _onSkillEndCallback:Function;

    // ── 单 tick 黑板（复用单例）──
    private var _ctx:AIContext;

    // ── 决策追踪（可观测性）──
    private var _trace:DecisionTrace;

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
        this._recentHitFrame = -999;
        this._selfRef = self;
        this._ctx = new AIContext();
        this._trace = new DecisionTrace();

        // ── 策略注册 ──
        var offense = new OffenseStrategy(personality);
        var reload = new ReloadStrategy(personality, scorer);
        var preBuff = new PreBuffStrategy(personality);

        this._sources = {};
        this._sources["engage"]   = [offense, reload];
        this._sources["chase"]    = [preBuff, reload];
        this._sources["selector"] = [];

        this._filters = [
            new AnimLockFilter(),
            new InterruptFilter(this._executor)
        ];

        // ── 事件订阅 ──
        if (self.dispatcher != undefined && self.dispatcher != null) {
            var arbiter:ActionArbiter = this;

            this._onHitCallback = function() {
                arbiter._recentHitFrame = _root.帧计时器.当前帧数;
            };
            self.dispatcher.subscribe("hit", this._onHitCallback, arbiter);

            this._onSkillEndCallback = function() {
                var currentState:String = self.状态;
                if (currentState != "技能" && currentState != "战技") {
                    arbiter._executor.expireBodyCommit();
                }
            };
            self.dispatcher.subscribe("skillEnd", this._onSkillEndCallback, arbiter);
        }
    }

    // ═══════ 公开接口 ═══════

    public function getRepositionDir():Number {
        return _scorer.getRepositionDir();
    }

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
        var self:MovieClip = data.self;

        // ═══ 黑板构建（单 tick 唯一真相源）═══
        _executor.updateAnimLock(self);
        _ctx.build(data, context, _executor, _scorer, _recentHitFrame, p);
        var frame:Number = _ctx.frame;

        // ═══ 决策追踪 ═══
        _trace.begin(self.名字, _ctx);

        // ═══ body 轨：统一动作选择 ═══

        var candidates:Array = _candidates;
        candidates.length = 0;

        // 1. 策略组收集候选
        var sources:Array = _sources[context];
        if (sources != null) {
            for (var si:Number = 0; si < sources.length; si++) {
                sources[si].collect(_ctx, data, candidates, _trace);
            }
        }

        // 2. 过滤器（AnimLock → Interrupt）
        for (var fi:Number = 0; fi < _filters.length; fi++) {
            _filters[fi].filter(_ctx, candidates, _trace);
        }

        // 3. hold/trigger 分流 + Continue 注入
        if (candidates.length > 0) {
            var holdAttack:Boolean = false;

            if (_ctx.isBodyCommitted) {
                if (_ctx.inputSemantic == "hold") {
                    var atkMode:String = _ctx.attackMode;
                    if (atkMode == "空手" || atkMode == "兵器") {
                        // 近战 Hold+Continue: 连招保护
                        var meleeContScore:Number = 0.5 + p.勇气 * 2.0;
                        candidates.push({
                            name: "Continue", type: "continue", priority: -1,
                            score: meleeContScore
                        });
                    } else {
                        // 远程 Hold: 不注入 Continue
                        holdAttack = true;
                    }
                } else {
                    // Trigger 语义（skill/reload/preBuff）
                    candidates.push({
                        name: "Continue", type: "continue", priority: -1,
                        score: _executor.getContinueScore()
                    });
                }
            }

            // 4. 评分 + Boltzmann + 执行
            if (candidates.length > 0) {
                var T:Number = p.temperature;

                _scoreCandidates(candidates, data, self, T);
                var selected:Object = _scorer.boltzmannSelect(candidates, T);

                if (selected != null) {
                    // 技能属性预写入（必须在 execute 之前）
                    if (selected.type == "skill" || selected.type == "preBuff") {
                        if (selected.skill != null) {
                            self.技能等级 = selected.skill.技能等级;
                            selected.skill.上次使用时间 = _ctx.nowMs;
                        }
                    }

                    // 执行
                    _executor.execute(selected, self);

                    // 提交 commitment + 后处理（Continue 不提交）
                    if (selected.type != "continue") {
                        var commitF:Number = selected.commitFrames;
                        if (isNaN(commitF)) commitF = 5;
                        _executor.commitBody(selected.type, selected.priority,
                            Math.round(commitF * p.tickInterval), frame);
                        _postExecution(selected, data, frame);
                        holdAttack = false;
                    }

                    _trace.selected(selected, 0, T);
                }
            }

            // 5. Attack hold：无新动作打断 → 维持按键输出
            if (holdAttack) {
                _executor.holdCurrentBody(self);
            }
        }

        // ═══ stance 轨：武器模式选择 ═══
        _evaluateStance(data, context, frame);

        // ═══ item 轨：血包使用 ═══
        _evaluateHeal(data);

        // ═══ 决策追踪输出 ═══
        _trace.flush();
    }

    // ═══════ 集中评分 ═══════

    /**
     * _scoreCandidates — 对候选列表评分
     *
     * Continue / Reload / PreBuff 的分数已在收集时预设，跳过评分管线。
     * Skill / Attack 走完整维度评分 + Stance 调制 + 战术偏置 + 噪声 + 反抖动 + 频率校正。
     */
    private function _scoreCandidates(candidates:Array, data:UnitAIData, self:MovieClip, T:Number):Void {
        var evalDepth:Number = p.evalDepth;
        var noise:Number = p.decisionNoise;

        var skillBonus:Number = 0;
        if (self.名字 == "尾上世莉架") skillBonus = 0.3;

        // 信号从 ctx 读取（单一真相源）
        var isRigid:Boolean = _ctx.isRigid;
        var stance:Object = _ctx.stance;
        var tactical:Object = _ctx.tactical;
        var xDist:Number = _ctx.xDist;
        var underFire:Boolean = _ctx.underFire;

        // ── 维度评分循环 ──
        for (var j:Number = 0; j < candidates.length; j++) {
            var c:Object = candidates[j];

            if (c.type == "continue" || c.type == "reload" || c.type == "preBuff") continue;

            var total:Number = 0;

            // 多维评分 + Stance 调制
            for (var d:Number = 0; d < evalDepth; d++) {
                var wKey:String = UtilityEvaluator.DIM_WEIGHTS[d];
                var w:Number = p[wKey];

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

            // 距离压力（远程被近身）
            if (stance != null && stance.repositionDir > 0 && xDist < _ctx.xdistance) {
                var rangePressure:Number = 1 - xDist / _ctx.xdistance;
                rangePressure *= (1 - p.勇气);
                if (c.type == "skill") {
                    var rpFunc:String = c.skill.功能;
                    if (rpFunc == "躲避") {
                        if (underFire || xDist < _ctx.xdistance * 0.4) {
                            total += rangePressure * 0.25;
                        }
                    } else if (rpFunc == "位移" || rpFunc == "高频位移") {
                        total += rangePressure * 0.4;
                    }
                } else if (c.type == "attack") {
                    if (underFire) {
                        total -= rangePressure * 0.15;
                    }
                }
            }

            // 反应性躲避
            if (c.type == "skill" && c.skill.功能 == "躲避" && underFire) {
                total += 0.5;
            }

            // 决策噪声
            total += (_rng.nextFloat() - 0.5) * noise;

            c.score = total;
            _trace.scored(c, null);
        }

        // ── 反抖动 ──
        var momentumDecay:Number = p.momentumDecay;

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
        var effectiveInterval:Number = p.chaseCommitment * p.tickInterval;
        if (effectiveInterval < 1) effectiveInterval = 1;
        var freqAdjust:Number = T * Math.log(effectiveInterval / 16);

        for (var fa:Number = 0; fa < candidates.length; fa++) {
            if (candidates[fa].type == "skill") {
                candidates[fa].score += freqAdjust;
            }
        }

        // 记录预设分数的候选
        for (var tr:Number = 0; tr < candidates.length; tr++) {
            var tc:Object = candidates[tr];
            if (tc.type == "continue" || tc.type == "reload" || tc.type == "preBuff") {
                _trace.scored(tc, null);
            }
        }
    }

    // ═══════ 后处理 ═══════

    private function _postExecution(selected:Object, data:UnitAIData, frame:Number):Void {
        if (selected.type == "skill") {
            _scorer.triggerTacticalBias(selected.skill, frame);
        }

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

    // ═══════ stance 轨 ═══════

    private function _evaluateStance(data:UnitAIData, context:String, frame:Number):Void {
        var self:MovieClip = _ctx.self;

        if (_ctx.isAnimLocked) {
            _scorer.applyWeaponRanges(self, data);
            _scorer.syncStance(_ctx.attackMode);
            return;
        }

        if (!_executor.canEvaluateStance(frame)) {
            _scorer.applyWeaponRanges(self, data);
            _scorer.syncStance(_ctx.attackMode);
            return;
        }

        if (frame - _executor.getLastSkillUseFrame() < p.skillAnimProtect) {
            _scorer.applyWeaponRanges(self, data);
            _scorer.syncStance(_ctx.attackMode);
            return;
        }

        if (context == "chase" && !isNaN(data._chaseStartFrame)) {
            if (frame - data._chaseStartFrame <= p.chaseFrustration) {
                _scorer.applyWeaponRanges(self, data);
                _scorer.syncStance(_ctx.attackMode);
                return;
            }
        }

        _scorer.evaluateWeaponMode(data);
        _executor.commitStance(p.stanceCooldown, frame);
    }

    // ═══════ item 轨 ═══════

    private function _evaluateHeal(data:UnitAIData):Void {
        _scorer.evaluateHealNeed(data);
    }

    // ═══════ 生命周期 ═══════

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
