import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;
import org.flashNight.arki.unit.UnitAI.ActionExecutor;
import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;
import org.flashNight.arki.unit.UnitAI.PipelineFactory;
import org.flashNight.arki.unit.UnitAI.scoring.ScoringPipeline;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
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
 *   AnimLockFilter   → 技能期仅保留 skill/preBuff；换弹期仅保留 priority=0
 *   InterruptFilter  → 中断规则（默认 candidate.priority < current.priority；技能允许技能互断）
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

    // ── 反抖动状态（共享给 MomentumPost）──
    private var _jitterState:Object;

    // ── 评分管线 ──
    private var _pipeline:ScoringPipeline;

    // ── 事件响应状态 ──
    private var _recentHitFrame:Number;
    private var _selfRef:MovieClip;
    private var _onHitCallback:Function;
    private var _onSkillEndCallback:Function;

    // ── 单 tick 黑板（复用单例）──
    private var _ctx:AIContext;

    // ── 决策追踪（可观测性）──
    private var _trace:DecisionTrace;

    // ── 撤退紧迫度（burst damage tracking）──
    private var _prevHpRatio:Number = 1;
    private var _retreatUrgency:Number = 0;

    // ── 包围度（左右敌人分布检测）──
    private var _encirclement:Number = 0;
    private var _lastEncirclementFrame:Number = -999;

    // ═══════ 构造 ═══════

    public function ActionArbiter(personality:Object, scorer:UtilityEvaluator, self:MovieClip) {
        this.p = personality;
        this._scorer = scorer;
        this._executor = new ActionExecutor();
        this._rng = LinearCongruentialEngine.getInstance();
        this._candidates = [];
        this._jitterState = { lastActionType: null, lastSkillName: null, repeatCount: 0 };
        this._recentHitFrame = -999;
        this._selfRef = self;
        this._ctx = new AIContext();
        this._trace = new DecisionTrace();

        // ── 声明式管线构建（PipelineFactory 注册表驱动）──
        // personality.aiSpec 可选：{ mods, posts, sources, filters }
        // null → 使用 PipelineFactory.DEFAULT_* 全量配置
        var deps:Object = {
            personality: personality,
            scorer: scorer,
            rng: this._rng,
            jitterState: this._jitterState,
            executor: this._executor
        };
        var spec:Object = personality.aiSpec;

        var mods:Array = PipelineFactory.buildMods(spec != null ? spec.mods : null, deps);
        var posts:Array = PipelineFactory.buildPosts(spec != null ? spec.posts : null, deps);
        this._pipeline = new ScoringPipeline(scorer, mods, posts);
        this._sources = PipelineFactory.buildSources(spec != null ? spec.sources : null, deps);
        this._filters = PipelineFactory.buildFilters(spec != null ? spec.filters : null, deps);

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

    public function getRetreatUrgency():Number {
        return _retreatUrgency;
    }

    public function getEncirclement():Number {
        return _encirclement;
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

        // ═══ 撤退紧迫度（burst damage → 勇气调节）═══
        // HP 下降量超过勇气抵消阈值时累积紧迫度；自然衰减
        // 高勇气 → 需要更大伤害才触发撤退；低勇气 → 轻伤即退
        var hpDelta:Number = _ctx.hpRatio - _prevHpRatio;
        _prevHpRatio = _ctx.hpRatio;
        if (hpDelta < -0.01) {
            _retreatUrgency = Math.min(1,
                _retreatUrgency + Math.max(0, -hpDelta - p.勇气 * 0.15) * 3);
        }
        _retreatUrgency *= 0.92;
        if (_retreatUrgency < 0.05) _retreatUrgency = 0;
        _ctx.retreatUrgency = _retreatUrgency;

        // ═══ 包围度检测（周期性，每 16 帧 ≈ 0.6s）═══
        // 用 getEnemyCountInRange 分别统计左右 250px 内的敌人
        // 乘积公式：一侧为 0 则 encirclement=0；两侧各 2 个即满值
        if (frame - _lastEncirclementFrame >= 16) {
            _lastEncirclementFrame = frame;
            var scanRange:Number = 250;
            var leftCount:Number = TargetCacheManager.getEnemyCountInRange(self, 8, scanRange, 0, true);
            var rightCount:Number = TargetCacheManager.getEnemyCountInRange(self, 8, 0, scanRange, true);
            _encirclement = Math.min(1, leftCount * rightCount / 4);
        }
        _ctx.encirclement = _encirclement;

        // 包围加剧低勇气角色的撤退紧迫度
        // 高勇气不受影响（主动解围由评分层处理）
        if (_encirclement > 0.2) {
            var courageDampen:Number = 1.0 - p.勇气;
            _retreatUrgency = Math.min(1, _retreatUrgency + _encirclement * courageDampen * 0.3);
            _ctx.retreatUrgency = _retreatUrgency;
        }

        // ═══ 决策追踪 ═══
        _trace.begin(self.名字, _ctx, p);

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

                _pipeline.scoreAll(candidates, _ctx, data, self, p, T, _trace);
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
                        // 技能 CD 传入 executor，用于 getContinueScore CD 比例保护
                        var skillCD:Number = 0;
                        if (selected.skill != null) {
                            skillCD = selected.skill.冷却;
                        }
                        _executor.commitBody(selected.type, selected.priority,
                            Math.round(commitF * p.tickInterval), frame, skillCD);
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

        // 5.5 自动维持普攻 hold 输入（修复：中断过滤后 candidates 为空导致"松手点射"）
        // 仅在 engage 期启用：chase/selector 不应持续输出普攻按键。
        if (context == "engage") {
            _executor.autoHold(self);
        }

        // ═══ stance 轨：武器模式选择 ═══
        _evaluateStance(data, context, frame);

        // ═══ item 轨：血包使用 ═══
        _evaluateHeal(data);

        // ═══ 决策追踪输出 ═══
        _trace.flush();
    }


    // ═══════ 后处理 ═══════

    private function _postExecution(selected:Object, data:UnitAIData, frame:Number):Void {
        if (selected.type == "skill") {
            _scorer.triggerTacticalBias(selected.skill, frame);
        }

        _jitterState.lastActionType = selected.type;
        if (selected.type == "skill") {
            if (_jitterState.lastSkillName == selected.name) {
                _jitterState.repeatCount++;
            } else {
                _jitterState.repeatCount = 0;
            }
            _jitterState.lastSkillName = selected.name;
        } else {
            _jitterState.repeatCount = 0;
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
