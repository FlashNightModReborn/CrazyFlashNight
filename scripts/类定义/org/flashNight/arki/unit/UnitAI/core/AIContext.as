import org.flashNight.arki.unit.UnitAI.core.UnitAIData;
import org.flashNight.arki.unit.UnitAI.combat.ActionExecutor;
import org.flashNight.arki.unit.UnitAI.combat.StanceManager;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;

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
 *
 * data / ctx 分工约定：
 *   ctx (AIContext)   — 管线组件使用（候选源、过滤器、评分器、后处理器）。
 *                       每 tick build-once，只读快照，保证管线内信号一致性。
 *   data (UnitAIData) — 移动组件使用（EngageMovementStrategy、RetreatMovementStrategy、
 *                       MovementResolver、HeroCombatModule.chase/engage）。
 *                       包含坐标、边界距离、目标差值等几何信息，
 *                       updateSelf/updateTarget 后实时有效。
 *   personality       — 两者皆可读取（管线读 p = data.personality，移动读 data.personality）。
 *   重叠字段（如 xDist/absdiff_x）：管线组件始终从 ctx 读取，移动组件从 data 读取。
 *   此约定消除"二次口径"计算风险。
 */
class org.flashNight.arki.unit.UnitAI.core.AIContext {

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
    public var zrange:Number;            // Z轴攻击范围（data.zrange = self.y轴攻击范围）

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
    public var nearbyCount:Number;       // 近距(150px)敌人数（ActionArbiter 周期采样，复用包围度扫描）
    public var enemyLeftCount:Number;    // 左侧敌人数（scanRange 窗口内，周期采样）
    public var enemyRightCount:Number;   // 右侧敌人数（scanRange 窗口内，周期采样）
    public var enemyBalance:Number;      // (-1..1) (right-left)/(left+right)，0=均衡
    public var enemyDominantSide:Number; // -1=左侧明显更多, 1=右侧明显更多, 0=近似均衡

    // ── 射弹预警（BulletQueueProcessor 尾循环写入 _bt* 动态属性）──
    public var bulletThreat:Number;      // 威胁子弹计数（0=无）
    public var bulletThreatDir:Number;   // -1=从左, +1=从右, 0=混合/无
    public var bulletETA:Number;         // 最近子弹到达帧数（9999=无）

    // ── 边界压迫 ──
    public var bndCorner:Number;         // 角落压迫度 [0,1]（X+Z双轴贴墙时趋近1）
    public var corneredAggression:Number;// S7: 角落激进信号 [0,1]（被逼角落+高勇气→主动解围）

    // ── pipeline context ──
    public var context:String;           // "chase" | "engage" | "selector" | "retreat"

    // ═══════ 构造（空壳，由 build 填充）═══════

    public function AIContext() {}

    // ═══════ 每 tick 构建 ═══════

    // build — 聚合所有管线信号到黑板
    // 前置条件：调用方必须确保 data.updateSelf() 已在当帧执行；
    //           有目标时 data.updateTarget() 也必须先于 build() 执行。
    // data 含聚合字段：hp/hpMax/isRigid/attackMode/ammoRatio/bt系列/target系列
    public function build(
        data:UnitAIData,
        ctx:String,
        executor:ActionExecutor,
        stanceMgr:StanceManager,
        recentHitFrame:Number,
        p:Object,
        retreatUrgency:Number,
        encirclement:Number,
        nearbyCount:Number,
        leftCount:Number,
        rightCount:Number
    ):Void {
        // 防御性检查：updateSelf 必须先于 build
        if (data.hp == undefined) {
            AIEnvironment.log("[AIContext] WARN: build() called before updateSelf()");
        }

        // ── 帧/时间（从 AIEnvironment 读取，零 _root 直读）──
        this.frame = AIEnvironment.getFrame();
        this.nowMs = AIEnvironment.getTimerMs();

        // ── 自身状态（全部从 data 聚合字段读取，零 MC 直读）──
        this.self = data.self;
        var maxHP:Number = data.hpMax;
        this.hpRatio = (maxHP > 0) ? Math.max(0, Math.min(1, data.hp / maxHP)) : 1;
        this.isRigid = data.isRigid;
        this.attackMode = data.attackMode;
        this.ammoRatio = data.ammoRatio;

        // ── 目标/距离（从 data 聚合字段读取）──
        var t:MovieClip = data.target;
        this.target = t;
        if (t == null) {
            this.targetValid = false;
            this.targetThreat = false;
        } else {
            this.targetValid = (data.targetHP > 0);
            this.targetThreat = (data.targetShooting == true
                || data.targetState == "技能" || data.targetState == "战技");
        }
        this.xDist = data.absdiff_x;
        this.zDist = data.absdiff_z;
        this.xdistance = data.xdistance;
        this.xrange = data.xrange;
        this.zrange = data.zrange;

        // ── 威胁感知（单一真相源）──
        var dodgeWin:Number = p.dodgeReactWindow;
        this.recentHitAge = this.frame - recentHitFrame;
        var hitThreat:Boolean = (this.recentHitAge >= 0 && this.recentHitAge < dodgeWin);

        // ── 射弹预警（从 data.bt* 聚合字段读取，零 MC 直读）──
        var btAge:Number = this.frame - data.btFrame;
        if (btAge >= 0 && btAge <= 1 && data.btCount > 0) {
            this.bulletThreat = data.btCount;
            var btDir:Number = data.btDirX;
            this.bulletThreatDir = (btDir > 0) ? 1 : ((btDir < 0) ? -1 : 0);
            this.bulletETA = data.btMinETA - btAge;
        } else {
            this.bulletThreat = 0;
            this.bulletThreatDir = 0;
            this.bulletETA = 9999;
        }

        this.underFire = hitThreat || this.targetThreat
            || (this.bulletThreat > 0 && this.bulletETA < dodgeWin);

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

        // ── 撤退/包围度/密度（ActionArbiter 预计算，build-once 契约）──
        this.retreatUrgency = retreatUrgency;
        this.encirclement = encirclement;
        this.nearbyCount = nearbyCount;
        this.enemyLeftCount = leftCount;
        this.enemyRightCount = rightCount;
        var lrSum:Number = leftCount + rightCount;
        this.enemyBalance = (lrSum > 0) ? ((rightCount - leftCount) / lrSum) : 0;
        if (rightCount > leftCount + 1) this.enemyDominantSide = 1;
        else if (leftCount > rightCount + 1) this.enemyDominantSide = -1;
        else this.enemyDominantSide = 0;

        // ── 边界压迫（updateSelf 预计算）──
        this.bndCorner = data.bndCorner;

        // ── pipeline ──
        this.context = ctx;
    }
}
