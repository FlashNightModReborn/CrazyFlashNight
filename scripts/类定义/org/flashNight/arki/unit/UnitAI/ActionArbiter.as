import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;
import org.flashNight.arki.unit.UnitAI.ActionExecutor;
import org.flashNight.arki.unit.UnitAI.AIContext;
import org.flashNight.arki.unit.UnitAI.DecisionTrace;
import org.flashNight.arki.unit.UnitAI.PipelineFactory;
import org.flashNight.arki.unit.UnitAI.StanceManager;
import org.flashNight.arki.unit.UnitAI.WeaponEvaluator;
import org.flashNight.arki.unit.UnitAI.HealExecutor;
import org.flashNight.arki.unit.UnitAI.scoring.ScoringPipeline;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletThreatScanProcessor;

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
    private var _stanceMgr:StanceManager;
    private var _weaponEval:WeaponEvaluator;
    private var _healExec:HealExecutor;
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
    private var _prevHpRatio:Number;
    private var _retreatUrgency:Number = 0;

    // ── 角落激进模式（S7: 被逼入角落时主动解围而非继续逃跑）──
    private var _corneredAggression:Number = 0;

    // ── 包围度 + 近距密度（左右敌人分布检测，统一采样）──
    private var _encirclement:Number = 0;
    private var _nearbyCount:Number = 0;
    private var _leftEnemyCount:Number = 0;
    private var _rightEnemyCount:Number = 0;
    private var _lastEncirclementFrame:Number = -999;

    // ═══════ 构造 ═══════

    public function ActionArbiter(personality:Object, scorer:UtilityEvaluator, self:MovieClip) {
        this.p = personality;
        this._scorer = scorer;
        this._stanceMgr = new StanceManager();
        this._weaponEval = new WeaponEvaluator(personality, this._stanceMgr);
        this._healExec = new HealExecutor(personality);
        this._executor = new ActionExecutor();
        this._rng = LinearCongruentialEngine.getInstance();
        this._candidates = [];
        this._jitterState = { lastActionType: null, lastSkillName: null, repeatCount: 0 };
        this._recentHitFrame = -999;
        this._selfRef = self;
        BulletThreatScanProcessor.register(self);
        this._ctx = new AIContext();
        this._trace = new DecisionTrace();

        // ── 声明式管线构建（PipelineFactory 注册表驱动）──
        // personality.aiSpec 可选：{ mods, posts, sources, filters }
        // null → 使用 PipelineFactory.DEFAULT_* 全量配置
        var deps:Object = {
            personality: personality,
            scorer: scorer,
            weaponEval: this._weaponEval,
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
        return _stanceMgr.getRepositionDir();
    }

    public function getExecutor():ActionExecutor {
        return _executor;
    }

    public function getRetreatUrgency():Number {
        // S7: 角落激进模式下降低有效撤退紧迫度
        // 逃不掉就不该逃 — 抑制 Retreating Gate 触发，转为原地解围
        if (_corneredAggression > 0) {
            return _retreatUrgency * (1 - _corneredAggression * 0.5);
        }
        return _retreatUrgency;
    }

    public function getEncirclement():Number {
        return _encirclement;
    }

    public function getNearbyCount():Number {
        return _nearbyCount;
    }

    /**
     * getLeftEnemyCount / getRightEnemyCount — 左右敌人数量（周期采样）
     *
     * 说明：统计窗口为 scanRange（当前 250px），仅用于走位/战术偏置等
     * 低频信号，不用于精确碰撞或逐帧反应。
     */
    public function getLeftEnemyCount():Number  { return _leftEnemyCount; }
    public function getRightEnemyCount():Number { return _rightEnemyCount; }

    public function getAmmoRatio(self:MovieClip):Number {
        return _weaponEval.getAmmoRatio(self, self.攻击模式);
    }

    public function getAmmoRatioForMode(self:MovieClip, mode:String):Number {
        return _weaponEval.getAmmoRatio(self, mode);
    }

    // ═══════ 核心管线 ═══════

     /**
      * tick — 每 AI 帧唯一入口
      *
      * 7 阶段管线：
      *   1. _updateRetreatUrgency  — burst damage → 撤退紧迫度
      *   2. _updateSpatialAwareness — 包围度/近距密度/射弹预警
      *   3. _prepareContext         — 战术偏置清理 + build 黑板 + 自适应温度
      *   4. _selectBodyAction       — collect → filter → score → select → execute
      *   5. _evaluateStance         — 武器模式选择（独立冷却）
      *   6. _evaluateHeal           — 血包使用（独立冷却）
      *   7. _trace.flush            — 决策追踪输出
      *
      * @param data    共享 AI 数据
      * @param context "chase" | "engage" | "selector" | "retreat"
      */
    public function tick(data:UnitAIData, context:String):Void {
        var self:MovieClip = data.self;
        var frame:Number = _root.帧计时器.当前帧数;

        _updateRetreatUrgency(self, frame);
        _updateSpatialAwareness(self, frame);
        var dynT:Number = _prepareContext(data, context, frame);
        _selectBodyAction(data, context, self, frame, dynT);

        _evaluateStance(data, context, frame);
        _evaluateHeal(data);
        _trace.flush();
    }

    // ═══════ tick 阶段 1：撤退紧迫度 ═══════

    /**
     * _updateRetreatUrgency — burst damage → 勇气调节的撤退紧迫度
     *
     * hpRatio 内联计算（与 AIContext.build 内相同公式，同 tick 内一致）。
     * 首帧 _prevHpRatio 为 NaN → hpDelta 视为 0（避免非满血单位误触撤退）。
     */
    private function _updateRetreatUrgency(self:MovieClip, frame:Number):Void {
        var maxHP:Number = self.hp满血值;
        var hpRatio:Number = (maxHP > 0) ? Math.max(0, Math.min(1, self.hp / maxHP)) : 1;
        var hpDelta:Number = hpRatio - _prevHpRatio;
        _prevHpRatio = hpRatio;
        if (isNaN(hpDelta)) hpDelta = 0;
        if (hpDelta < -0.01) {
            _retreatUrgency = Math.min(1,
                _retreatUrgency + Math.max(0, -hpDelta - p.勇气 * 0.15) * 3);
        }
        _retreatUrgency *= 0.92;
        if (_retreatUrgency < 0.05) _retreatUrgency = 0;
    }

    // ═══════ tick 阶段 2：空间感知 ═══════

    /**
     * _updateSpatialAwareness — 包围度 + 近距密度 + 射弹预警
     *
     * 包围度/近距密度每 16 帧周期性采样（≈0.6s），射弹预警逐帧检测。
     * 两者均可加剧 _retreatUrgency。
     */
    private function _updateSpatialAwareness(self:MovieClip, frame:Number):Void {
        // 包围度 + 近距密度检测（周期性，每 16 帧 ≈ 0.6s）
        if (frame - _lastEncirclementFrame >= 16) {
            _lastEncirclementFrame = frame;
            var scanRange:Number = 250;
            var leftCount:Number = TargetCacheManager.getEnemyCountInRange(self, 8, scanRange, 0, true);
            var rightCount:Number = TargetCacheManager.getEnemyCountInRange(self, 8, 0, scanRange, true);
            _leftEnemyCount = leftCount;
            _rightEnemyCount = rightCount;
            _encirclement = Math.min(1, leftCount * rightCount / 4);
            _nearbyCount = TargetCacheManager.getEnemyCountInRange(self, 16, 150, 150, true);
        }

        // 包围加剧低勇气角色的撤退紧迫度
        if (_encirclement > 0.2) {
            var courageDampen:Number = 1.0 - p.勇气;
            _retreatUrgency = Math.min(1, _retreatUrgency + _encirclement * courageDampen * 0.3);
        }

        // 射弹预警 → 前瞻性撤退（年龄窗口容忍 0~1 帧延迟）
        var btAge:Number = frame - self._btFrame;
        var btCount:Number = self._btCount;
        if (btAge >= 0 && btAge <= 1 && !isNaN(btCount) && btCount > 0) {
            var btETA:Number = self._btMinETA - btAge;
            if (isNaN(btETA) || btETA < 0) btETA = 0;
            var btUrgency:Number = Math.min(0.5, btCount * 0.1)
                * Math.max(0, 1 - btETA / 20)
                * (1 - p.勇气 * 0.7);
            _retreatUrgency = Math.min(1, _retreatUrgency + btUrgency);
        }
    }

    // ═══════ tick 阶段 3：黑板构建 + 温度 ═══════

    /**
     * _prepareContext — 战术偏置过期 + build-once 黑板 + 自适应温度 + trace begin
     *
     * @return dynT 自适应 Boltzmann 温度
     */
    private function _prepareContext(data:UnitAIData, context:String, frame:Number):Number {
        // 战术偏置过期清理（build 前处理，保持 build 无副作用）
        var tactBias:Object = _stanceMgr.getTacticalBias();
        if (tactBias != null && frame >= tactBias.expiryFrame) {
            _stanceMgr.clearTacticalBias();
        }

        // 黑板构建（build-once 契约：所有信号在此一次性聚合）
        _executor.updateAnimLock(data.self);
        _ctx.build(data, context, _executor, _stanceMgr, _weaponEval, _recentHitFrame, p,
                   _retreatUrgency, _encirclement, _nearbyCount, _leftEnemyCount, _rightEnemyCount);

        // S7: 角落激进模式 — 被逼入角落 + 高勇气 + 目标活跃 → 主动解围
        // bndCorner > 0.3 = X轴和Z轴同时靠近边界（无处可逃）
        // 高勇气角色转为激进（解围/击退），低勇气角色维持求生本能
        var corner:Number = data.bndCorner;
        if (isNaN(corner)) corner = 0;
        if (corner > 0.3 && p.勇气 > 0.3) {
            var caTgt:Number = corner * p.勇气;
            // 快速上升、缓慢衰减（进入角落立刻反应，脱离后逐渐恢复）
            if (caTgt > _corneredAggression) {
                _corneredAggression = caTgt;
            } else {
                _corneredAggression += (caTgt - _corneredAggression) * 0.15;
            }
        } else {
            _corneredAggression *= 0.9;
        }
        if (_corneredAggression < 0.05) _corneredAggression = 0;
        if (_corneredAggression > 1) _corneredAggression = 1;
        _ctx.corneredAggression = _corneredAggression;

        // 自适应温度（高压更确定，低压更灵动）
        var dynT:Number = p.temperature;
        if (isNaN(dynT) || dynT <= 0) dynT = 0.1;

        var pressure:Number = 0;
        if (_ctx.underFire) pressure += 0.35;
        pressure += _ctx.retreatUrgency * 0.6;
        pressure += _ctx.encirclement * 0.5;
        if (_ctx.bulletThreat > 0) {
            var etaP:Number = 1 - _ctx.bulletETA / 20;
            if (etaP < 0) etaP = 0;
            if (etaP > 1) etaP = 1;
            pressure += etaP * 0.4;
        }
        if (pressure > 1) pressure = 1;

        var calm:Number = 1 - pressure;
        dynT = dynT * (0.6 + calm * 0.6); // 0.6~1.2 倍
        if (dynT < 0.01) dynT = 0.01;
        if (dynT > 0.5) dynT = 0.5;

        // 决策追踪 begin
        _trace.begin(data.self.名字, _ctx, p);

        return dynT;
    }

    // ═══════ tick 阶段 4：body 轨动作选择 ═══════

    /**
     * _selectBodyAction — collect → filter → score → select → execute
     *
     * 完整的 body 轨管线：候选收集 + 过滤 + 评分 + Boltzmann 选择 + 执行提交。
     * ReflexBoostMod 在评分阶段对反射闪避注入高分（替代原硬旁路）。
     */
    private function _selectBodyAction(data:UnitAIData, context:String,
                                       self:MovieClip, frame:Number, dynT:Number):Void {
        var candidates:Array = _candidates;
        candidates.length = 0;

        // 1. 策略组收集候选
        var sources:Array = _sources[context];
        if (sources != null) {
            for (var si:Number = 0; si < sources.length; si++) {
                sources[si].collect(_ctx, data, candidates, _trace);
            }
        }
        var rawCount:Number = candidates.length;

        // 2. 过滤器（AnimLock → Interrupt）
        for (var fi:Number = 0; fi < _filters.length; fi++) {
            _filters[fi].filter(_ctx, candidates, _trace);
        }
        var postFilterCount:Number = candidates.length;

        // 诊断：记录候选计数 + 源概览
        if (_trace.isEnabled()) {
            var srcSummary:String = "";
            if (sources == null) {
                srcSummary = "null";
            } else if (sources.length == 0) {
                srcSummary = "-";
            } else {
                for (var ssi:Number = 0; ssi < sources.length; ssi++) {
                    if (ssi > 0) srcSummary += "+";
                    srcSummary += (sources[ssi].getName != undefined) ? sources[ssi].getName() : "?";
                }
            }
            _trace.setSourceSummary(srcSummary);
            _trace.setCandidateCounts(rawCount, postFilterCount);
            if (postFilterCount == 0) {
                var nd:String;
                if (sources == null) nd = "CTX_UNCONFIGURED";
                else if (sources.length == 0) nd = "NO_SOURCES";
                else if (rawCount == 0) nd = "NO_CANDIDATES";
                else nd = "FILTERED_TO_ZERO";
                _trace.noDecision(nd, dynT);
            }
        }

        // 3. hold/trigger 分流 + Continue 注入
        if (candidates.length > 0) {
            var holdAttack:Boolean = false;

            if (_ctx.isBodyCommitted) {
                if (_ctx.inputSemantic == "hold") {
                    var atkMode:String = _ctx.attackMode;
                    if (atkMode == "空手" || atkMode == "兵器") {
                        var meleeContScore:Number = 0.5 + p.勇气 * 2.0;
                        candidates.push({
                            name: "Continue", type: "continue", priority: -1,
                            score: meleeContScore
                        });
                    } else {
                        holdAttack = true;
                    }
                } else {
                    candidates.push({
                        name: "Continue", type: "continue", priority: -1,
                        score: _executor.getContinueScore()
                    });
                }
            }

            // 4. 评分 + Boltzmann + 执行
            if (candidates.length > 0) {
                var T:Number = dynT;

                _pipeline.scoreAll(candidates, _ctx, data, self, p, T, _trace);
                var selected:Object = _scorer.boltzmannSelect(candidates, T);

                if (selected != null) {
                    if (selected.type == "skill" || selected.type == "preBuff") {
                        if (selected.skill != null) {
                            self.技能等级 = selected.skill.技能等级;
                            selected.skill.上次使用时间 = _ctx.nowMs;
                        }
                    }

                    _executor.execute(selected, self);

                    if (selected.type != "continue") {
                        var commitF:Number = selected.commitFrames;
                        if (isNaN(commitF)) commitF = 5;
                        var skillCD:Number = 0;
                        if (selected.skill != null) {
                            skillCD = selected.skill.冷却;
                        }
                        _executor.commitBody(selected.type, selected.priority,
                            Math.round(commitF * p.tickInterval), frame, skillCD);
                        if (selected.skill != null
                            && (selected.skill.功能 == "躲避" || selected.skill.功能 == "位移")) {
                            _executor.setDodgeActive(true);
                        }
                        if (selected._reflexBoosted) {
                            _executor.commitReflex(frame);
                        }
                        _postExecution(selected, data, frame);
                        holdAttack = false;
                    }

                    var prob:Number = 0;
                    if (_trace.isEnabled()) {
                        var sumExp:Number = 0;
                        for (var pi:Number = 0; pi < candidates.length; pi++) {
                            var ew:Number = candidates[pi]._ew;
                            if (!isNaN(ew) && ew > 0) sumExp += ew;
                        }
                        if (sumExp > 0 && selected._ew != undefined && !isNaN(selected._ew)) {
                            prob = selected._ew / sumExp;
                        }
                    }
                    _trace.selected(selected, prob, T);
                }
            }

            // 5. Attack hold：无新动作打断 → 维持按键输出
            if (holdAttack) {
                _executor.autoHold(self);
            }
        }

        // 5.5 自动维持普攻 hold 输入
        if (context == "engage") {
            _executor.autoHold(self);
        }
    }


    // ═══════ 后处理 ═══════

    private function _postExecution(selected:Object, data:UnitAIData, frame:Number):Void {
        if (selected.type == "skill") {
            _stanceMgr.triggerTacticalBias(selected.skill, frame);
        }

        // 全局buff单次施放记录（兴奋剂/铁布衫/觉醒霸体等永久buff仅施放一次）
        if (selected.type == "skill" || selected.type == "preBuff") {
            var pbMark:Object = _root.技能函数.预战buff标记[selected.name];
            if (pbMark != null && pbMark.global) {
                data._usedGlobalBuffs[selected.name] = true;
            }
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
            _weaponEval.applyWeaponRanges(self, data);
            _stanceMgr.syncStance(_ctx.attackMode);
            return;
        }

        if (!_executor.canEvaluateStance(frame)) {
            _weaponEval.applyWeaponRanges(self, data);
            _stanceMgr.syncStance(_ctx.attackMode);
            return;
        }

        if (frame - _executor.getLastSkillUseFrame() < p.skillAnimProtect) {
            _weaponEval.applyWeaponRanges(self, data);
            _stanceMgr.syncStance(_ctx.attackMode);
            return;
        }

        if (context == "chase" && !isNaN(data._chaseStartFrame)) {
            if (frame - data._chaseStartFrame <= p.chaseFrustration) {
                _weaponEval.applyWeaponRanges(self, data);
                _stanceMgr.syncStance(_ctx.attackMode);
                return;
            }
        }

        _weaponEval.evaluateWeaponMode(data);
        _executor.commitStance(p.stanceCooldown, frame);
    }

    // ═══════ item 轨 ═══════

    private function _evaluateHeal(data:UnitAIData):Void {
        _healExec.evaluateHealNeed(data);
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
        BulletThreatScanProcessor.unregister(_selfRef);
        _selfRef = null;
        _onHitCallback = null;
        _onSkillEndCallback = null;
    }
}
