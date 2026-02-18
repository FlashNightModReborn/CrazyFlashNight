import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.ActionExecutor;
import org.flashNight.arki.unit.UnitAI.StanceManager;
import org.flashNight.arki.unit.UnitAI.WeaponEvaluator;

/**
 * AIContext — 单 tick 黑板（Blackboard）
 *
 * 设计原则：
 *   每 tick 在 ActionArbiter.tick() 入口处构建一次（复用单例）。
 *   所有候选源 / 过滤器 / 评分器只允许读 ctx，
 *   禁止在管线内部再直接读 self.状态 / self.man.换弹标签 / _recentHitFrame 等散落状态。
 *   "二次口径"计算视为 bug。
 *
 * 信号来源唯一性保证：
 *   underFire  : 此处为唯一计算点（原先 _collectOffense:292 和 _scoreCandidates:434 各算一次）
 *   isRigid    : 此处为唯一计算点（原先 _collectPreBuff:360 和 _scoreCandidates:419 各算一次）
 *
 * 复用策略：
 *   ActionArbiter 持有 _ctx 单例字段，每次 build() 覆写所有字段。
 *   避免每 tick 创建新对象产生 GC 压力。
 */
class org.flashNight.arki.unit.UnitAI.AIContext {

    // ── 帧/时间 ──
    public var frame:Number;             // _root.帧计时器.当前帧数
    public var nowMs:Number;             // getTimer()

    // ── 自身状态 ──
    public var self:MovieClip;
    public var hpRatio:Number;           // clamped [0,1]
    public var isRigid:Boolean;          // 刚体 || man.刚体标签
    public var attackMode:String;        // self.攻击模式
    public var ammoRatio:Number;         // 当前武器余弹比 [0,1]（远程姿态有效）

    // ── 目标/距离 ──
    public var target:MovieClip;
    public var targetValid:Boolean;      // target != null && target.hp > 0
    public var xDist:Number;             // data.absdiff_x
    public var zDist:Number;             // data.absdiff_z
    public var xdistance:Number;         // 保持距离
    public var xrange:Number;            // 攻击范围

    // ── 威胁感知（唯一计算点）──
    public var underFire:Boolean;        // 被击窗口内 OR 目标正在攻击/施技
    public var recentHitAge:Number;      // 帧距上次被击（负数=从未被击）
    public var targetThreat:Boolean;     // 目标是否正在 射击中/技能/战技

    // ── Stance / Tactical ──
    public var stance:Object;            // _currentStance（只读引用）
    public var tactical:Object;          // _tacticalBias（null=无/已过期）
    public var repositionDir:Number;     // stance.repositionDir（无 stance 时为 0）

    // ── 动作生命周期（从 ActionExecutor 只读快照）──
    public var bodyType:String;              // _executor.getCurrentBodyType()
    public var isBodyCommitted:Boolean;      // _executor.isBodyCommitted(frame)
    public var isAnimLocked:Boolean;         // _executor.isAnimLocked()
    public var consecutiveAttacks:Number;    // 连续普攻次数（连招深度代理）
    public var inputSemantic:String;         // "hold" | "trigger" | null
    public var lockSource:String;            // "FRAME_COMMIT" | "ANIM_SKILL" | "ANIM_RELOAD" | null

    // ── 撤退紧迫度（burst damage → 勇气调节）──
    public var retreatUrgency:Number;    // [0,1] 受创紧迫程度（高=重创应撤退）

    // ── 包围度（左右敌人分布）──
    public var encirclement:Number;      // [0,1] 被包围程度（乘积公式：两侧均有敌人时高）

    // ── pipeline context ──
    public var context:String;           // "chase" | "engage" | "selector"

    // ═══════ 构造（空壳，由 build 填充）═══════

    public function AIContext() {}

    // ═══════ 每 tick 构建 ═══════

    /**
     * build — 聚合所有管线信号到黑板
     *
     * @param data           共享 AI 数据
     * @param ctx            "chase" | "engage" | "selector"
     * @param executor       ActionExecutor 实例
     * @param stanceMgr      StanceManager 实例（姿态/战术偏置）
     * @param weaponEval     WeaponEvaluator 实例（余弹比查询）
     * @param recentHitFrame   最近被击帧号
     * @param p                personality 引用（含派生参数）
     * @param retreatUrgency   撤退紧迫度 [0,1]（ActionArbiter 预计算）
     * @param encirclement     包围度 [0,1]（ActionArbiter 预计算）
     */
    public function build(
        data:UnitAIData,
        ctx:String,
        executor:ActionExecutor,
        stanceMgr:StanceManager,
        weaponEval:WeaponEvaluator,
        recentHitFrame:Number,
        p:Object,
        retreatUrgency:Number,
        encirclement:Number
    ):Void {
        var s:MovieClip = data.self;
        var t:MovieClip = data.target;

        // ── 帧/时间 ──
        this.frame = _root.帧计时器.当前帧数;
        this.nowMs = getTimer();

        // ── 自身状态 ──
        this.self = s;
        var maxHP:Number = s.hp满血值;
        this.hpRatio = (maxHP > 0) ? Math.max(0, Math.min(1, s.hp / maxHP)) : 1;
        this.isRigid = (s.刚体 == true) ||
            (s.man != null && s.man.刚体标签 != null && s.man.刚体标签 != undefined);
        this.attackMode = s.攻击模式;
        this.ammoRatio = weaponEval.getAmmoRatio(s, s.攻击模式);

        // ── 目标/距离 ──
        this.target = t;
        this.targetValid = (t != null && t.hp > 0);
        this.xDist = data.absdiff_x;
        this.zDist = data.absdiff_z;
        this.xdistance = data.xdistance;
        this.xrange = data.xrange;

        // ── 威胁感知（单一真相源）──
        var dodgeWin:Number = p.dodgeReactWindow;
        // dodgeReactWindow 已在 计算AI参数 中 clamp，此处信任
        this.recentHitAge = this.frame - recentHitFrame;
        var hitThreat:Boolean = (this.recentHitAge >= 0 && this.recentHitAge < dodgeWin);

        this.targetThreat = false;
        if (t != null) {
            this.targetThreat = (t.射击中 == true || t.状态 == "技能" || t.状态 == "战技");
        }

        this.underFire = hitThreat || this.targetThreat;

        // ── Stance / Tactical（只读快照，过期清理由 ActionArbiter 负责）──
        this.stance = stanceMgr.getCurrentStance();
        this.tactical = stanceMgr.getTacticalBias();
        this.repositionDir = (this.stance != null) ? this.stance.repositionDir : 0;

        // ── 动作生命周期 ──
        this.bodyType = executor.getCurrentBodyType();
        this.isBodyCommitted = executor.isBodyCommitted(this.frame);
        this.isAnimLocked = executor.isAnimLocked();
        this.consecutiveAttacks = executor.getConsecutiveAttacks();
        this.inputSemantic = executor.getInputSemantic();
        this.lockSource = executor.getLockSource(this.frame);

        // ── 撤退/包围度（ActionArbiter 预计算，build-once 契约）──
        this.retreatUrgency = retreatUrgency;
        this.encirclement = encirclement;

        // ── pipeline ──
        this.context = ctx;
    }
}
