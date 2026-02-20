import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.MovementResolver;
import org.flashNight.arki.unit.UnitAI.strategies.EngageMovementStrategy;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * 佣兵战斗模块 — 作为子状态机嵌入根机 HeroCombatBehavior
 *
 * 内部状态：Chasing (default) / Engaging
 * 退出条件：由根机 Gate 检测目标死亡/消失
 *
 * 动作决策：完全由 ActionArbiter 统一管线驱动
 */
class org.flashNight.arki.unit.UnitAI.HeroCombatModule extends FSM_StateMachine {

    private var _lastTargetCheckFrame:Number = -999;

    // 战术走位策略
    private var _movement:EngageMovementStrategy;

    // 确定性随机源（可复现行为）
    private var _rng:LinearCongruentialEngine;

    public function HeroCombatModule(_data:UnitAIData) {
        // machine-level onEnter: 重入时强制重置到 Chasing
        super(null, function() { this.ChangeState("Chasing"); }, null);
        this.data = _data;
        this._movement = new EngageMovementStrategy();
        this._rng = LinearCongruentialEngine.getInstance();

        // 闭包捕获子状态机引用 — engage() 需要访问 HeroCombatModule 实例方法
        // FSM_Status 回调中 this = FSM_Status 无法直接访问
        var module:HeroCombatModule = this;

        this.AddStatus("Chasing", new FSM_Status(this.chase, this.chase_enter, null));
        this.AddStatus("Engaging", new FSM_Status(
            function() { module.engage(); },
            this.engage_enter,
            null
        ));

        // 内部 Gate: 距离判定
        this.transitions.push("Chasing", "Engaging", function() {
            return _data.absdiff_z <= _data.zrange && _data.absdiff_x <= _data.xrange;
        }, true);
        this.transitions.push("Engaging", "Chasing", function() {
            // 迟滞退出：防止连招中被击退一帧就切回追击断段
            // 基础迟滞 1.2 + 勇气加成 0~0.3 → 退出阈值 1.2~1.5 倍射程
            var exitMult:Number = 1.2;
            if (_data.personality != null) {
                exitMult += (_data.personality.勇气 || 0) * 0.3;
            }
            // 近战连招中：大幅加宽退出阈值（1.7~2.0 倍）
            // 防止连招前段推人/自身被击退导致越界切回追击
            var s:MovieClip = _data.self;
            if (s.状态 == "空手攻击" || s.状态 == "兵器攻击") {
                exitMult += 0.5;
            }
            return _data.absdiff_z > _data.zrange || _data.absdiff_x > _data.xrange * exitMult;
        }, true);
    }

    // ═══════ 追击（射程外）═══════

    public function chase_enter():Void {
        var self:MovieClip = data.self;
        _movement.reset(); // 脱离交战，重置走位状态
        // 同步外部攻击目标变更
        var extTarget:String = self.攻击目标;
        if (extTarget && extTarget != "无") {
            var resolved = _root.gameworld[extTarget];
            if (resolved != null && resolved.hp > 0 && resolved != data.target) {
                data.target = resolved;
            }
        }
        if (data.target != null) {
            self.dispatcher.publish("aggroSet", self, data.target);
        }
        // 追击计时：用于检测长时间追不上目标
        data._chaseStartFrame = _root.帧计时器.当前帧数;
    }

    public function chase():Void {
        var self:MovieClip = data.self;
        MovementResolver.clearInput(self);

        // 目标失效守卫（T0-1：增加 hp 校验，防止追尸体）
        var t:MovieClip = data.target;
        if (t == null || isNaN(t._x) || !(t.hp > 0)) return;

        data.updateSelf();
        data.updateTarget();

        // ── 周期性目标评估（近身感知 + 转火）──
        if (_checkTargetSwitch()) {
            data.updateTarget();
        }

        // ── 统一动作管线 ──
        // 预战buff + 换弹 + 武器评估 全部收敛到 arbiter.tick()
        // arbiter 内部按中断规则互斥，不再有覆盖冲突
        data.arbiter.tick(data, "chase");

        // 动作保护期：禁止跑步切换/移动输入，避免打断技能/换弹动画
        // 技能：只有技能才能取消技能
        // 换弹：跑步/移动可能打断换弹动画导致"没子弹发呆"
        var bt:String = data.arbiter.getExecutor().getCurrentBodyType();
        if (bt == "skill" || bt == "preBuff" || self.状态 == "技能" || self.状态 == "战技"
            || self.man.换弹标签) {
            return;
        }

        // Z轴计算：统一使用 data.diff_z（基于 Z轴坐标，与碰撞层一致）
        // 不再自行用 _y 计算，避免跳跃/浮空/受击抖动导致 Z 对齐错向
        var zDiff:Number = data.diff_z;
        var absZDiff:Number = data.absdiff_z;

        // ── 近战追击兜底：仅在Z轴已对齐时输出平A，避免"空挥锁帧"阻碍对齐 ──
        // 远程追击不攻击（缩距优先，不浪费弹药）
        // 近战在射程内应立即输出，避免"切到近战后只追不打"
        var atkMode:String = self.攻击模式;
        if ((atkMode == "空手" || atkMode == "兵器")
            && data.absdiff_x <= data.xrange
            && absZDiff <= data.zrange) {
            if (!self.射击中 && self.状态 != "技能" && self.状态 != "战技") {
                self.动作A = true;
            }
        }

        // 跑步切换：Z 轴基本对齐后再切跑，避免跑步高速导致 Z 轴抖动
        // absZDiff > 20 时保持走路（低速精确对齐），对齐后才允许跑步追击
        if (!self.射击中 && !self.man.换弹标签 && _rng.randomInteger(0, 2) == 0) {
            if (absZDiff <= 20) {
                self.状态改变(self.攻击模式 + "跑");
            }
        }

        // ── 收集移动意图 + 统一边界感知输出 ──

        // Z轴意图（5px 死区避免来回抖动）
        var wantZ:Number = 0;
        if (absZDiff > 5) {
            wantZ = (zDiff < 0) ? -1 : 1; // diff_z<0=自身偏下→上行(-1)
        }

        // T2-A：预测拦截 — 朝预测位置移动而非当前位置
        var leadFrames:Number = 0;
        if (!isNaN(data.targetVX) && data.targetVX != 0) {
            var spd:Number = self.跑X速度;
            if (isNaN(spd) || spd <= 0) spd = (self.行走X速度 || 5) * 2;
            leadFrames = data.absdiff_x / (spd + 1);
            if (leadFrames < 4) leadFrames = 4;
            if (leadFrames > 12) leadFrames = 12;
        }
        var predTx:Number = data.tx + (data.targetVX || 0) * leadFrames;

        // X轴意图（保持距离，朝预测位置）
        // 防发呆：keepX 不得大于 xrange，否则会停在射程外进不了 engage
        var keepX:Number = data.xdistance;
        if (keepX > data.xrange) keepX = data.xrange;
        var wantX:Number = 0;
        if (data.x > predTx + keepX) {
            wantX = -1; // 左移接近
        } else if (data.x < predTx - keepX) {
            wantX = 1;  // 右移接近
        }

        // 统一处理边界碰撞：沿墙滑行 / 角落突围 / 正常输出
        MovementResolver.applyBoundaryAwareMovement(UnitAIData(data), self, wantX, wantZ);
    }

    // ═══════ 交战（射程内）═══════

    public function engage_enter():Void {
        MovementResolver.clearInput(data.self);
    }

    public function engage():Void {
        var self:MovieClip = data.self;

        MovementResolver.clearInput(self);

        // 目标失效守卫（T0-1：增加 hp 校验，防止攻击尸体）
        var t:MovieClip = data.target;
        if (t == null || isNaN(t._x) || !(t.hp > 0)) return;

        data.updateSelf();
        data.updateTarget();

        // ── 周期性目标评估（近身感知 + 转火）──
        if (_checkTargetSwitch()) {
            data.updateTarget();
            t = data.target;
        }

        // 面朝目标
        if (data.x > data.tx) {
            self.方向改变("左");
        } else if (data.x < data.tx) {
            self.方向改变("右");
        }

        // ── 统一动作管线 ──
        // 技能/平A/换弹/武器评估 全部收敛到 arbiter.tick()
        // arbiter 内部按中断规则互斥，不再有 gotoAndPlay 覆盖冲突
        var frame:Number = _root.帧计时器.当前帧数;

        // 始终 engage context — 走位与进攻并行，不抑制 offense
        data.arbiter.tick(data, "engage");

        var bodyType:String = data.arbiter.getExecutor().getCurrentBodyType();
        var inSkill:Boolean = (bodyType == "skill" || bodyType == "preBuff"
                            || bodyType == "reload"
                            || self.状态 == "技能" || self.状态 == "战技");

        // ── 战术走位（策略委托）──
        _movement.apply(UnitAIData(data), self, frame, inSkill);

        // 防呆兜底：管线未产出动作 + 无 commitment → 默认普攻
        // getCurrentBodyType()==null 蕴含 !isBodyCommitted()（无类型 = 无承诺）
        // 覆盖：纯站立无输出 + 移动中无攻击 两种边界场景
        if (!self.动作A && self.射击中 != true) {
            var st:String = self.状态;
            if (st != "技能" && st != "战技"
                && data.arbiter.getExecutor().getCurrentBodyType() == null) {
                self.动作A = true;
                if (self.攻击模式 === "双枪") self.动作B = true;
            }
        }

        // 目标死亡检查
        if (t.hp <= 0 || t.hp == undefined) {
            self.dispatcher.publish("aggroClear", self);
        }
    }

    // ═══════ 目标切换（近距离感知）═══════

    /**
     * _checkTargetSwitch — 周期性检测更近的敌人
     *
     * 使用 TargetCacheManager.findNearestEnemy 感知被近身。
     * 距离比率迟滞：新目标必须显著更近才切换（避免频繁转火）。
     * 检测频率 / 迟滞阈值由人格参数驱动。
     *
     * @return Boolean 是否发生了目标切换
     */
    private function _checkTargetSwitch():Boolean {
        var self:MovieClip = data.self;
        var frame:Number = _root.帧计时器.当前帧数;

        // 人格参数驱动检测频率
        var p:Object = data.personality;
        var interval:Number = 12;
        if (p != null && !isNaN(p.targetSwitchInterval)) {
            interval = p.targetSwitchInterval;
        }

        if (frame - _lastTargetCheckFrame < interval) return false;
        _lastTargetCheckFrame = frame;

        // 目标采样（低成本）：最近 / 最近活跃威胁 / 最近残血
        // 说明：不做全局扫描与怪物特判，只用通用信号提升 1vN 的转火质量。
        var searchLimit:Number = 12;
        var candNearest:MovieClip = MovieClip(TargetCacheManager.findNearestEnemy(self, 1));
        var candActive:MovieClip = MovieClip(TargetCacheManager.findNearestEnemyWithFilter(
            self, 1, _filterActiveThreat,
            searchLimit, undefined
        ));
        var candLowHP:MovieClip = MovieClip(TargetCacheManager.findNearestLowHPEnemy(self, 1, searchLimit));

        var selfZ:Number = self.Z轴坐标;
        if (isNaN(selfZ)) selfZ = self._y;

        // 选出最佳候选（同战团Z过滤）
        var best:MovieClip = null;
        var bestScore:Number = -999;
        var samples:Array = [candNearest, candActive, candLowHP];
        for (var si:Number = 0; si < samples.length; si++) {
            var c:MovieClip = samples[si];
            if (c == null || !(c.hp > 0) || c._x == undefined) continue;
            var cz:Number = c.Z轴坐标;
            if (isNaN(cz)) cz = c._y;
            if (Math.abs(selfZ - cz) > 60) continue;
            var sc:Number = _scoreTarget(c, self, p);
            if (sc > bestScore) {
                bestScore = sc;
                best = c;
            }
        }

        if (best == null) return false;

        var t:MovieClip = data.target;

        // 无当前目标 → 直接获取
        if (t == null || t.hp <= 0) {
            _switchTarget(best);
            return true;
        }

        // 已是当前目标 → 跳过
        if (best == t) return false;

        // T1-B：多维目标评分（距离 + 残血优先 → 高效清场）
        var currentScore:Number = _scoreTarget(t, self, p);

        var ratio:Number = 0.5;
        if (p != null && !isNaN(p.targetSwitchRatio)) {
            ratio = p.targetSwitchRatio;
        }

        // 迟滞：新目标必须明显更优才切换（ratio 作为优势阈值）
        if (bestScore > currentScore * (1 + ratio)) {
            _switchTarget(best);
            return true;
        }

        return false;
    }

    /**
     * _scoreTarget — 多维目标优先级评分
     *
     * 维度：
     *   1) 距离（近优先）
     *   2) HP比率（残血优先，高效清场）
     *   3) 活跃威胁（正在攻击/技能的敌人更优先）
     *   4) 补刀窗口（极残血目标强优先：减少威胁源数量）
     */
    private function _scoreTarget(candidate:MovieClip, self:MovieClip, p:Object):Number {
        // 距离分（反比，归一化到 0~1）
        var dist:Number = Math.abs(self._x - candidate._x);
        var distScore:Number = 1.0 / (1.0 + dist * 0.005); // 200px→0.5, 400px→0.33

        // HP分（残血→高分，高效清场）
        var maxHP:Number = candidate.hp满血值;
        var hpRatio:Number = (maxHP > 0) ? candidate.hp / maxHP : 1;
        if (isNaN(hpRatio) || hpRatio > 1) hpRatio = 1;
        if (hpRatio < 0) hpRatio = 0;
        var hpScore:Number = 1.0 - hpRatio; // 满血=0, 残血=~1

        // 权重：经验高→残血优先，经验低→距离优先
        var wHP:Number = 0.3;
        if (p != null && !isNaN(p.经验)) {
            wHP = 0.3 + p.经验 * 0.3; // 0.3 ~ 0.6
        }
        var score:Number = distScore * (1.0 - wHP) + hpScore * wHP;

        // 活跃威胁：正在攻击/施技的敌人优先处理（降低入射伤害）
        var activeThreat:Boolean = (candidate.射击中 == true
            || candidate.状态 == "技能" || candidate.状态 == "战技");
        if (activeThreat) {
            var strat:Number = (p != null && !isNaN(p.谋略)) ? p.谋略 : 0;
            score += 0.15 + strat * 0.25; // 0.15~0.40
        }

        // 补刀窗口：极残血目标强优先（减少威胁源数量）
        if (hpRatio < 0.2) {
            var fin:Number = (0.2 - hpRatio) / 0.2; // 0~1
            var exp:Number = (p != null && !isNaN(p.经验)) ? p.经验 : 0;
            score += fin * (0.25 + exp * 0.25); // 0~0.50
        }

        // 背后威胁：若候选与当前目标分居两侧且距离近，提升优先级
        // 近似“不要让敌人出现在身后”，不依赖怪物类型。
        var cur:MovieClip = data.target;
        if (cur != null && cur != candidate && cur.hp > 0 && cur._x != undefined && dist < 160) {
            var frontSide:Number = (cur._x >= self._x) ? 1 : -1;
            var candSide:Number = (candidate._x >= self._x) ? 1 : -1;
            if (candSide != frontSide) {
                score += activeThreat ? 0.25 : 0.15;
            }
        }

        return score;
    }

    /**
     * _filterActiveThreat — TargetCacheManager.findNearestEnemyWithFilter 使用
     * 仅使用通用信号：射击中/技能/战技
     */
    private static function _filterActiveThreat(u:Object):Boolean {
        if (u == null) return false;
        return (u.射击中 == true || u.状态 == "技能" || u.状态 == "战技");
    }

    private function _switchTarget(newTarget):Void {
        var self:MovieClip = data.self;
        data.target = newTarget;
        self.攻击目标 = newTarget._name;
        self.dispatcher.publish("aggroSet", self, newTarget);
    }
}
