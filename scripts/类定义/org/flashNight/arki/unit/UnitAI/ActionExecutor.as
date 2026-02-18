/**
 * ActionExecutor — 动作互斥/commitment/中断规则执行器
 *
 * 三轨独立追踪：
 *   body  : 动画时间线（技能/平A/换弹/预战buff）— priority 中断矩阵
 *   stance: 武器模式切换 — 冷却
 *   item  : 消耗品使用（血包）— 冷却
 *
 * body commitment 双重锁定：
 *   1. 帧计数锁（commitBody 提交时设定 _bodyCommitUntil）
 *   2. 动画标签锁（换弹标签 / self.状态=="技能" → 动作动画播放中）
 *   两者 OR 合并：任一为 true 即视为 committed
 *   仅当已有 body 动作提交（_bodyPriority >= 0）时动画锁才生效
 *
 * 重要：刚体/刚体标签 是 buff 状态（护盾/霸体），不是动作动画
 *       不应纳入 animLock，否则 buff 期间会永久空转
 *
 * body 中断规则：
 *   - 默认：candidate.priority < currentAction.priority → 允许中断（严格小于）
 *   - 例外：skill/preBuff 允许 skill/preBuff 互相取消（同优先级也允许）
 *   Emergency(0) > Skill/PreBuff(1) > Reload(2) > Attack(3)
 *   同优先级不互断；躲避/解围霸体设为 Emergency(0) 可抢断技能
 */
class org.flashNight.arki.unit.UnitAI.ActionExecutor {

    // ── 输入语义常量表 ──
    // attack = hold（持续按键，每帧需重新输出）
    // skill/reload/preBuff = trigger（一次性触发，引擎管理后续动画）
    static var INPUT_SEMANTIC:Object = {
        attack: "hold", skill: "trigger", preBuff: "trigger", reload: "trigger"
    };

    // ── body 轨状态 ──
    private var _bodyPriority:Number;
    private var _bodyCommitUntil:Number;
    private var _bodyType:String;

    // ── 动画标签锁（每 tick 由 updateAnimLock 刷新）──
    private var _animLocked:Boolean;

    // ── 连续攻击计数（连招深度代理）──
    private var _consecutiveAttacks:Number;

    // ── stance 轨冷却 ──
    private var _stanceCooldownUntil:Number;

    // ── item 轨冷却 ──
    private var _itemCooldownUntil:Number;

    // ── 技能使用帧（武器切换保护）──
    private var _lastSkillUseFrame:Number;

    // ── 当前技能 CD（秒，用于 Continue 分数缩放）──
    private var _bodySkillCD:Number;

    // ── 换弹结束伪事件（追踪 换弹标签 true→false 下降沿）──
    private var _lastReloadTag:Boolean;

    // ═══════ 构造 ═══════

    public function ActionExecutor() {
        reset();
    }

    public function reset():Void {
        _bodyPriority = -1;
        _bodyCommitUntil = 0;
        _bodyType = null;
        _animLocked = false;
        _stanceCooldownUntil = 0;
        _itemCooldownUntil = 0;
        _lastSkillUseFrame = -999;
        _lastReloadTag = false;
        _consecutiveAttacks = 0;
        _bodySkillCD = 0;
    }

    // ═══════ 动画标签锁 ═══════

    /**
     * updateAnimLock — 每 tick 刷新动画标签锁状态
     *
     * 只绑定"动作播放期"，不绑 buff 状态：
     *   换弹标签 → 换弹动画播放中
     *   self.状态 == "技能" → 技能路由必经 状态改变("技能")，技能动画播放期
     *
     * 不包含：
     *   刚体/刚体标签 → buff/护盾状态，可持续很久，不是动作动画
     *   射击中 → 普攻播放期，但应该能被技能取消
     */
    public function updateAnimLock(self:MovieClip):Void {
        _animLocked = false;

        // ── 换弹标签追踪（必须在所有 early return 之前采样）──
        var currentReloadTag:Boolean = (self.man != null && self.man != undefined
            && self.man.换弹标签 != null && self.man.换弹标签 != undefined);

        // null guard: man 可能尚未初始化
        if (currentReloadTag) { _animLocked = true; _lastReloadTag = true; return; }

        // 技能/战技播放期：技能路由 → 状态改变("技能"/"战技") → 动画完毕后自动离开
        if (self.状态 == "技能" || self.状态 == "战技") { _animLocked = true; _lastReloadTag = false; return; }

        // ── 换弹结束伪事件：追踪 换弹标签 下降沿（true→false）──
        // skill 有 skillEnd 事件驱动 expireBodyCommit()；reload 无对应事件，
        // 纯靠 reloadCommitFrames + animLock 可能与动画实际时长不匹配。
        // 检测 换弹标签 消失的瞬间 → 立即释放帧计数锁，消除空转/提前放开。
        if (_bodyType == "reload" && _lastReloadTag && !currentReloadTag) {
            expireBodyCommit();
        }
        _lastReloadTag = currentReloadTag;
    }

    public function isAnimLocked():Boolean {
        return _animLocked;
    }

    // ═══════ body 轨 ═══════

    /**
     * isBodyCommitted — 帧计数锁 OR 动画标签锁
     *
     * 关键：_bodyPriority < 0 = 从未提交过 body 动作 → 直接放行
     * 否则 animLocked=true + _bodyPriority=-1 会导致 canInterruptBody
     * 把所有 priority≥0 的候选过滤掉，只剩 Continue → 永久空转
     */
    public function isBodyCommitted(frame:Number):Boolean {
        if (_bodyPriority < 0) return false;
        return frame < _bodyCommitUntil || _animLocked;
    }

    /**
     * canInterruptBody — 检查候选是否能中断当前 body 动作
     *
     * 规则：
     *   - 默认：candidate.priority < currentAction.priority（严格小于）
     *   - 例外：当前为 skill/preBuff 时，skill/preBuff 允许 <=（同优先级也可取消）
     * 紧急技能(0)可中断技能(1) → 躲避/解围霸体设为 priority=0
     * 未 committed 时始终允许
     */
    public function canInterruptBody(candidateType:String, candidatePriority:Number, frame:Number):Boolean {
        if (!isBodyCommitted(frame)) return true;

        // 仅技能可取消技能：skill/preBuff 允许互相中断（同优先级也允许）
        if ((_bodyType == "skill" || _bodyType == "preBuff")
            && (candidateType == "skill" || candidateType == "preBuff")) {
            return candidatePriority <= _bodyPriority;
        }

        return candidatePriority < _bodyPriority;
    }

    /**
     * commitBody — 提交 body 动作，更新 commitment 状态
     *
     * @param skillCD  当前技能的冷却时间（秒），用于 getContinueScore 的 CD 比例保护。
     *                 非技能动作传 0 或省略。
     */
    public function commitBody(type:String, priority:Number, commitFrames:Number, frame:Number, skillCD:Number):Void {
        // 连续攻击追踪
        if (type == "attack") {
            _consecutiveAttacks++;
        } else {
            _consecutiveAttacks = 0;
        }
        _bodyType = type;
        _bodyPriority = priority;
        _bodyCommitUntil = frame + commitFrames;
        _bodySkillCD = isNaN(skillCD) ? 0 : skillCD;
        if (type == "skill" || type == "preBuff") {
            _lastSkillUseFrame = frame;
        }
    }

    /**
     * expireBodyCommit — 立即释放帧计数锁
     *
     * 由 ActionArbiter 在技能动画正常结束后调用（skillEnd 事件），
     * 避免 _bodyCommitUntil 超出动画实际持续时间导致空转。
     * 不清除 _animLocked（由 updateAnimLock 每 tick 刷新）。
     */
    public function expireBodyCommit():Void {
        _bodyCommitUntil = 0;
        _bodyPriority = -1;
        _bodyType = null;
        _bodySkillCD = 0;
    }

    /** @deprecated 统一使用 autoHold */
    public function holdCurrentBody(self:MovieClip):Void {
        autoHold(self);
    }

    /**
     * getContinueScore — 当前 body 动作对应的 Continue 候选评分
     *
     * 基础分：
     *   Skill/PreBuff: 1.5
     *   Reload: 1.0
     *   Attack: 0.3
     *
     * CD 比例保护（仅 skill/preBuff）：
     *   cdBoost = clamp(ln(cd/3) × 0.5, 0, 2.0)
     *   3秒CD → +0（行为不变），60秒CD → +1.5（极强保护）
     *   紧急技能（priority=0）走 AnimLockFilter 不参与 Boltzmann，不受此影响
     */
    public function getContinueScore():Number {
        switch (_bodyType) {
            case "skill":
            case "preBuff":
                var base:Number = 1.5;
                if (_bodySkillCD > 3) {
                    var cdBoost:Number = Math.log(_bodySkillCD / 3) * 0.5;
                    if (cdBoost > 2.0) cdBoost = 2.0;
                    base += cdBoost;
                }
                return base;
            case "reload":
                return 1.0;
            case "attack":
                return 0.3;
            default:
                return 0.5;
        }
    }

    public function getCurrentBodyType():String {
        return _bodyType;
    }

    public function getLastSkillUseFrame():Number {
        return _lastSkillUseFrame;
    }

    public function getConsecutiveAttacks():Number {
        return _consecutiveAttacks;
    }

    /**
     * getInputSemantic — 当前 body 动作的输入语义
     * @return "hold" | "trigger" | null
     */
    public function getInputSemantic():String {
        if (_bodyType == null) return null;
        return INPUT_SEMANTIC[_bodyType];
    }

    /**
     * getLockSource — 结构化锁定原因（供 AIContext / DecisionTrace 使用）
     *
     * @return "FRAME_COMMIT" | "ANIM_SKILL" | "ANIM_RELOAD" | null
     *   null = 未锁定；FRAME_COMMIT = 帧计数锁尚未到期；
     *   ANIM_SKILL = 技能/战技动画播放中；ANIM_RELOAD = 换弹动画播放中
     */
    public function getLockSource(frame:Number):String {
        if (_bodyPriority < 0) return null;
        if (_animLocked) {
            // 区分动画锁来源：换弹标签 vs 技能/战技状态
            // _lastReloadTag == true 意味着当前帧换弹标签存在（updateAnimLock 已采样）
            if (_lastReloadTag) return "ANIM_RELOAD";
            return "ANIM_SKILL";
        }
        if (frame < _bodyCommitUntil) return "FRAME_COMMIT";
        return null;
    }

    /**
     * autoHold — 自动维持 hold 型 body 动作的按键输出
     *
     * 目标态：ActionExecutor 内部管理 hold 输出，Arbiter 不再负责 holdCurrentBody 调用。
     * 当前阶段（Phase B）先添加方法，Phase C/D 迁移后再从 Arbiter 移除 holdAttack 分支。
     */
    public function autoHold(self:MovieClip):Void {
        if (_bodyType == "attack" && _bodyPriority >= 0) {
            // 技能/战技/换弹动画锁期间禁止维持普攻按键，避免打断 trigger 动作
            if (self.状态 == "技能" || self.状态 == "战技") return;
            if (self.man != null && self.man != undefined
                && self.man.换弹标签 != null && self.man.换弹标签 != undefined) return;
            self.动作A = true;
            if (self.攻击模式 === "双枪") self.动作B = true;
        }
    }

    // ═══════ stance 轨 ═══════

    public function canEvaluateStance(frame:Number):Boolean {
        return frame >= _stanceCooldownUntil;
    }

    public function commitStance(cooldownFrames:Number, frame:Number):Void {
        _stanceCooldownUntil = frame + cooldownFrames;
    }

    // ═══════ item 轨 ═══════

    public function canEvaluateItem(frame:Number):Boolean {
        return frame >= _itemCooldownUntil;
    }

    public function commitItem(cooldownFrames:Number, frame:Number):Void {
        _itemCooldownUntil = frame + cooldownFrames;
    }

    // ═══════ 统一执行 ═══════

    /**
     * execute — 按候选类型执行对应动作
     *
     * 所有改变 self.man 动画的行为统一走此方法，
     * 确保同一时刻只有一个 body 动作生效
     */
    public function execute(candidate:Object, self:MovieClip):Void {
        switch (candidate.type) {
            case "attack":
                self.动作A = true;
                if (self.攻击模式 === "双枪") self.动作B = true;
                break;
            case "skill":
            case "preBuff":
                _root.技能路由.技能标签跳转_旧(self, candidate.name);
                break;
            case "reload":
                self.man.gotoAndPlay("换弹匣");
                break;
            case "continue":
                // 安全兜底：attack hold 语义
                // 正常路径下 attack committed 不注入 Continue（tier 2 hold 分流）
                // 此处仅防御性保护，避免结构变更后遗漏
                if (_bodyType == "attack") {
                    self.动作A = true;
                    if (self.攻击模式 === "双枪") self.动作B = true;
                }
                break;
        }
    }
}
