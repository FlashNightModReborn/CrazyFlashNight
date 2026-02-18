import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.EngageMovementStrategy;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

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

    public function HeroCombatModule(_data:UnitAIData) {
        // machine-level onEnter: 重入时强制重置到 Chasing
        super(null, function() { this.ChangeState("Chasing"); }, null);
        this.data = _data;
        this._movement = new EngageMovementStrategy();

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
        UnitAIData.clearInput(self);

        // 目标失效守卫（T0-1：增加 hp 校验，防止追尸体）
        var t:MovieClip = data.target;
        if (t == null || !t._x || !(t.hp > 0)) return;

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
            || (self.man != null && self.man.换弹标签)) {
            return;
        }

        // Z轴计算（先算距离，供跑步判定使用）
        var targetZ:Number = isNaN(t.Z轴坐标) ? t._y : t.Z轴坐标;
        var zDiff:Number = self._y - targetZ;
        var absZDiff:Number = zDiff < 0 ? -zDiff : zDiff;

        // 跑步切换：Z 轴基本对齐后再切跑，避免跑步高速导致 Z 轴抖动
        // absZDiff > 20 时保持走路（低速精确对齐），对齐后才允许跑步追击
        if (!self.射击中 && (self.man == null || !self.man.换弹标签) && random(3) == 0) {
            if (absZDiff <= 20) {
                self.状态改变(self.攻击模式 + "跑");
            }
        }

        // ── 收集移动意图 + 统一边界感知输出 ──

        // Z轴意图（5px 死区避免来回抖动）
        var wantZ:Number = 0;
        if (absZDiff > 5) {
            wantZ = (zDiff > 0) ? -1 : 1; // zDiff>0=自身偏下→上行(-1)
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
        var wantX:Number = 0;
        if (data.x > predTx + data.xdistance) {
            wantX = -1; // 左移接近
        } else if (data.x < predTx - data.xdistance) {
            wantX = 1;  // 右移接近
        }

        // 统一处理边界碰撞：沿墙滑行 / 角落突围 / 正常输出
        UnitAIData.applyBoundaryAwareMovement(UnitAIData(data), self, wantX, wantZ);
    }

    // ═══════ 交战（射程内）═══════

    public function engage_enter():Void {
        UnitAIData.clearInput(data.self);
    }

    public function engage():Void {
        var self:MovieClip = data.self;

        UnitAIData.clearInput(self);

        // 目标失效守卫（T0-1：增加 hp 校验，防止攻击尸体）
        var t:MovieClip = data.target;
        if (t == null || !t._x || !(t.hp > 0)) return;

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

        // 防呆：管线边界情况兜底（所有候选被过滤 / commitment 间隙 / 状态切换空隙）
        // 增加 commitment 检查：避免在换弹/技能 commitment 期间强行输出普攻打断动画
        if (!self.动作A && !self.动作B && !self.左行 && !self.右行 && !self.上行 && !self.下行) {
            var st:String = self.状态;
            if (st != "技能" && st != "战技" && !self.射击中) {
                var safeToAttack:Boolean =
                    !data.arbiter.getExecutor().isBodyCommitted(_root.帧计时器.当前帧数);
                if (safeToAttack) {
                    self.动作A = true;
                    if (self.攻击模式 === "双枪") self.动作B = true;
                }
            }
        }

        // T0-3：移动中但无攻击输出的兜底（防止纯走位不输出）
        // 仅当 arbiter 未提交任何 body 动作且未 committed 时生效
        if (!self.动作A && self.射击中 != true) {
            var st2:String = self.状态;
            if (st2 != "技能" && st2 != "战技") {
                var exec = data.arbiter.getExecutor();
                if (!exec.isBodyCommitted(_root.帧计时器.当前帧数)
                    && exec.getCurrentBodyType() == null) {
                    self.动作A = true;
                    if (self.攻击模式 === "双枪") self.动作B = true;
                }
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

        // 查找最近敌人（X 轴排序）
        var nearest = TargetCacheManager.findNearestEnemy(self, 1);
        if (nearest == null || nearest.hp <= 0) return false;

        // Z 轴过滤：Z 距离过远说明在不同战团，不切换
        var nearestZ:Number = nearest.Z轴坐标;
        if (isNaN(nearestZ)) nearestZ = nearest._y;
        var selfZ:Number = self.Z轴坐标;
        if (isNaN(selfZ)) selfZ = self._y;
        if (Math.abs(selfZ - nearestZ) > 60) return false;

        var t:MovieClip = data.target;

        // 无当前目标 → 直接获取
        if (t == null || t.hp <= 0) {
            _switchTarget(nearest);
            return true;
        }

        // 已是当前目标 → 跳过
        if (nearest == t) return false;

        // T1-B：多维目标评分（距离 + 残血优先 → 高效清场）
        var currentScore:Number = _scoreTarget(t, self, p);
        var nearestScore:Number = _scoreTarget(nearest, self, p);

        var ratio:Number = 0.5;
        if (p != null && !isNaN(p.targetSwitchRatio)) {
            ratio = p.targetSwitchRatio;
        }

        // 迟滞：新目标必须明显更优才切换（ratio 作为优势阈值）
        if (nearestScore > currentScore * (1 + ratio)) {
            _switchTarget(nearest);
            return true;
        }

        return false;
    }

    /**
     * _scoreTarget — 多维目标优先级评分
     *
     * 维度：距离（近优先）+ HP比率（残血优先）
     * 权重受经验调节：高经验角色更重视残血击杀（高效清场）
     */
    private function _scoreTarget(candidate:MovieClip, self:MovieClip, p:Object):Number {
        // 距离分（反比，归一化到 0~1）
        var dist:Number = Math.abs(self._x - candidate._x);
        var distScore:Number = 1.0 / (1.0 + dist * 0.005); // 200px→0.5, 400px→0.33

        // HP分（残血→高分，高效清场）
        var maxHP:Number = candidate.hp满血值;
        var hpRatio:Number = (maxHP > 0) ? candidate.hp / maxHP : 1;
        var hpScore:Number = 1.0 - hpRatio; // 满血=0, 残血=~1

        // 权重：经验高→残血优先，经验低→距离优先
        var wHP:Number = 0.3;
        if (p != null && !isNaN(p.经验)) {
            wHP = 0.3 + p.经验 * 0.3; // 0.3 ~ 0.6
        }
        return distScore * (1.0 - wHP) + hpScore * wHP;
    }

    private function _switchTarget(newTarget):Void {
        var self:MovieClip = data.self;
        data.target = newTarget;
        self.攻击目标 = newTarget._name;
        self.dispatcher.publish("aggroSet", self, newTarget);
    }
}
