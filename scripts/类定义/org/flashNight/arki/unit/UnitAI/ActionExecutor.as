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
 *   2. 动画标签锁（换弹标签 / 刚体 / 刚体标签 → 动画仍在播放）
 *   两者 OR 合并：任一为 true 即视为 committed
 *
 * body 中断规则：candidate.priority < currentAction.priority → 允许中断（严格小于）
 *   Emergency(0) > Skill/PreBuff(1) > Reload(2) > Attack(3)
 *   同优先级不互断；躲避/解围霸体设为 Emergency(0) 可抢断技能
 */
class org.flashNight.arki.unit.UnitAI.ActionExecutor {

    // ── body 轨状态 ──
    private var _bodyPriority:Number;
    private var _bodyCommitUntil:Number;
    private var _bodyType:String;

    // ── 动画标签锁（每 tick 由 updateAnimLock 刷新）──
    private var _animLocked:Boolean;

    // ── stance 轨冷却 ──
    private var _stanceCooldownUntil:Number;

    // ── item 轨冷却 ──
    private var _itemCooldownUntil:Number;

    // ── 技能使用帧（武器切换保护）──
    private var _lastSkillUseFrame:Number;

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
    }

    // ═══════ 动画标签锁 ═══════

    /**
     * updateAnimLock — 每 tick 刷新动画标签锁状态
     *
     * 检测游戏引擎实际动画状态（比帧计数更可靠）：
     *   换弹标签 → 换弹动画播放中
     *   刚体 / 刚体标签 → 技能超级装甲期间
     * 注意：射击中(普攻)不视为锁定 — 技能应该能取消普攻
     */
    public function updateAnimLock(self:MovieClip):Void {
        _animLocked = false;
        if (self.man.换弹标签 != null && self.man.换弹标签 != undefined) { _animLocked = true; return; }
        if (self.刚体 == true) { _animLocked = true; return; }
        if (self.man.刚体标签 != null && self.man.刚体标签 != undefined) { _animLocked = true; return; }
    }

    public function isAnimLocked():Boolean {
        return _animLocked;
    }

    // ═══════ body 轨 ═══════

    /**
     * isBodyCommitted — 帧计数锁 OR 动画标签锁
     */
    public function isBodyCommitted(frame:Number):Boolean {
        return frame < _bodyCommitUntil || _animLocked;
    }

    /**
     * canInterruptBody — 检查候选是否能中断当前 body 动作
     *
     * 规则：candidate.priority < currentAction.priority（严格小于）
     * 同优先级不能互相中断 → 技能(1)不取消技能(1)
     * 紧急技能(0)可中断技能(1) → 躲避/解围霸体设为 priority=0
     * 未 committed 时始终允许
     */
    public function canInterruptBody(candidatePriority:Number, frame:Number):Boolean {
        if (!isBodyCommitted(frame)) return true;
        return candidatePriority < _bodyPriority;
    }

    /**
     * commitBody — 提交 body 动作，更新 commitment 状态
     */
    public function commitBody(type:String, priority:Number, commitFrames:Number, frame:Number):Void {
        _bodyType = type;
        _bodyPriority = priority;
        _bodyCommitUntil = frame + commitFrames;
        if (type == "skill" || type == "preBuff") {
            _lastSkillUseFrame = frame;
        }
    }

    /**
     * getContinueScore — 当前 body 动作对应的 Continue 候选评分
     *
     * Skill/PreBuff: 1.5（强保护）
     * Reload: 1.0（中等保护）
     * Attack: 0.3（弱保护）
     */
    public function getContinueScore():Number {
        switch (_bodyType) {
            case "skill":
            case "preBuff":
                return 1.5;
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
                // 延续当前动作 — 不输出任何指令
                break;
        }
    }
}
