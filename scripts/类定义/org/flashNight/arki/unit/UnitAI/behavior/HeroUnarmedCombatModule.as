// ============================================================
// HeroUnarmedCombatModule — 空手战斗子状态机（嵌入 HeroUnarmedBehavior）
//
// 内部状态：Chasing（默认）/ Engaging
// 退出条件：由根机 Gate 检测目标死亡/消失
//
// 与默认 HeroCombatModule 的区别（D1/D7：默认层零改动，这里是我们的实现）：
//   - 无 ActionArbiter/EngageMovementStrategy 管线，动作决策委托 HeroUnarmedSkillBrain
//   - Z 轴精确对齐：满足 D3 三条件时设置 自机.虎妙Z对齐 激活每帧任务接管，
//     本模块同时停止输出 Z 意图（避免双走）
//   - 攻击判定用我们自己的 攻击判定X/Z 参数（不用被 UnitAIData 强制成 10 的 zrange）
// ============================================================

import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.arki.unit.UnitAI.core.UnitAIData;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;
import org.flashNight.arki.unit.UnitAI.combat.MovementResolver;
import org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedSkillBrain;
import org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedMoveHelper;

class org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedCombatModule extends FSM_StateMachine {

    private var data:UnitAIData;
    private var brain:HeroUnarmedSkillBrain;
    private var p:Object;

    public function HeroUnarmedCombatModule(_data:UnitAIData, _brain:HeroUnarmedSkillBrain) {
        // machine-level onEnter：重入时强制重置到 Chasing
        super(null, function() { this.ChangeState("Chasing"); }, null);
        this.data = _data;
        this.brain = _brain;
        this.p = _data.self.配置AI参数;
        if (this.p == null) this.p = {};

        var module:HeroUnarmedCombatModule = this;

        this.AddStatus("Chasing", new FSM_Status(
            function() { module.chase(); },
            function() { module.chase_enter(); },
            null
        ));
        this.AddStatus("Engaging", new FSM_Status(
            function() { module.engage(); },
            function() { module.engage_enter(); },
            null
        ));

        // 内部 Gate：进入交战（我们的攻击判定参数）
        this.transitions.push("Chasing", "Engaging", function():Boolean {
            return _data.absdiff_x <= module.p.攻击判定X
                && _data.absdiff_z <= module.p.攻击判定Z;
        }, true);
        // 内部 Gate：退出交战（迟滞 1.3 倍，防连招中被击退就断段）
        this.transitions.push("Engaging", "Chasing", function():Boolean {
            return _data.absdiff_x > module.p.攻击判定X * 1.3
                || _data.absdiff_z > module.p.攻击判定Z * 1.3;
        }, true);
    }

    // ═══════ 追击 ═══════

    private function chase_enter():Void {
        MovementResolver.clearInput(data.self);
    }

    private function chase():Void {
        var self:MovieClip = data.self;
        var frame:Number = AIEnvironment.getFrame();
        MovementResolver.clearInput(self);

        var t:MovieClip = data.target;
        var hasTarget:Boolean = (t != null && !isNaN(t._x) && (t.hp > 0));

        data.updateSelf();
        if (hasTarget) data.updateTarget();

        // （追击期主动转向已回退：AI 数据 4 帧陈旧 + 移动旗标每 tick 清写，
        //   方向改变 与行走状态机的朝向互相拉扯 → 疯狂来回翻转。追击中靠
        //   移动旗标自带的朝向即可，engage 的转向是原有逻辑保留。）

        // 技能脑无条件 tick：
        //   1) 升龙拳等跳起技的空中窗口、击倒脱困、喝药都不依赖目标；
        //   2) 状态==技能/战技 时 brain 内部走 commit/打断分支——不能在本模块提前 return，
        //      否则追击态下（被击退/目标拉开即进 Chasing）空中出招与击倒小跳会被整段吞掉。
        brain.tick(frame);
        // 方向锁回写（clearInput 会清掉跳跃方向输入）
        HeroUnarmedMoveHelper.syncLockedInput(self);

        // 已出招 → 本 tick 不输出移动；无目标 → 不移动（等根机回 Selector 重索敌）
        // ★同时清掉 Z 对齐接管：技能/战技（升龙拳、小跳等）空中期间 _y 由 空中控制器 独占积分，
        //   若残留接管，alignTick 会每帧 move2D 写 _y=Z轴坐标（拽回地面），与重力积分互相拉扯
        //   → 空中上下抖动 + Z轴坐标被拖走 → 落地后 Z/Y 偏离。
        if (self.状态 == "技能" || self.状态 == "战技") { self.虎妙Z对齐 = null; return; }
        if (!hasTarget) { self.虎妙Z对齐 = null; return; }

        // Z 轴意图（5px 死区）
        var wantZ:Number = 0;
        if (data.absdiff_z > 5) {
            wantZ = (data.diff_z < 0) ? -1 : 1; // diff_z<0=目标偏上→上行(-1)
        }

        // X 轴意图：朝目标移动（先算：收口探测是斜向端点，需要 X 口径一致）
        var wantX:Number = 0;
        if (data.absdiff_x > p.攻击判定X * 0.6) {
            wantX = (data.diff_x < 0) ? -1 : 1;
        }

        // ★边界收口：距边不足一个脱困探测距离时归零（不给脱困逻辑喂会被判挡的方向，防振荡）；
        //   被收口的最后一段由下方 Z 对齐接管小步走完（见 clampZIntent 注释）
        var rawZ:Number = wantZ;
        wantZ = HeroUnarmedMoveHelper.clampZIntent(self, wantX, wantZ);

        // ── Z 轴精确对齐接管判定（D3 三条件）──
        if (HeroUnarmedMoveHelper.shouldTakeOverZ(data, self, wantZ)) {
            // 激活每帧任务接管；本 tick 不输出 Z 意图（防双走）
            self.虎妙Z对齐 = {目标: t, 每帧速度: HeroUnarmedMoveHelper._getZSpeed(self)};
            wantZ = 0;
        } else {
            // 未接管则清掉，交回原路径
            self.虎妙Z对齐 = null;
        }

        // ★收口后的最后一程：意图仍在但被收口（贴边带内）→ 直接交给 Z 对齐接管，
        //   alignTick 以步长级探测 + 边界步长钳制小步直走到边缘，绕开脱困逻辑。
        //   （障碍物场景 alignTick 自身复检走不动会清接管，不会硬压。）
        if (rawZ != 0 && wantZ == 0 && self.虎妙Z对齐 == null) {
            self.虎妙Z对齐 = {目标: t, 每帧速度: HeroUnarmedMoveHelper._getZSpeed(self)};
        }

        // 跑步切换：Z 轴基本对齐后才切跑（沿 HeroCombatModule:163 思路）
        if (wantX != 0 && data.absdiff_z <= 20 && self.状态 != self.攻击模式 + "跑") {
            self.状态改变(self.攻击模式 + "跑");
        }

        // 统一边界感知移动输出（Z 意图已被对齐接管时置 0）
        MovementResolver.applyBoundaryAwareMovement(UnitAIData(data), self, wantX, wantZ);
        // 移动输出会重写 左行/右行/上行/下行 → 方向锁窗口内再回写一次，保证跳跃方向生效
        HeroUnarmedMoveHelper.syncLockedInput(self);
    }

    // ═══════ 交战 ═══════

    private function engage_enter():Void {
        MovementResolver.clearInput(data.self);
        // 交战期允许 Z 对齐接管（见 engage() 内的 Z 微调）
        data.self.虎妙Z对齐 = null;
    }

    private function engage():Void {
        var self:MovieClip = data.self;
        MovementResolver.clearInput(self);

        var t:MovieClip = data.target;
        if (t == null || isNaN(t._x) || !(t.hp > 0)) return;

        data.updateSelf();
        data.updateTarget();

        // 面朝目标
        if (data.x > data.tx) {
            self.方向改变("左");
        } else if (data.x < data.tx) {
            self.方向改变("右");
        }

        // 技能/战技播放中：brain 处理 commit/打断，本模块不移动
        // （brain.tick 内部已在技能中走 _tryInterrupt 分支）
        // ★与 chase() 同款：早退必须清 Z 对齐接管，防残留进空中期拽 _y（见 alignTick 守卫注释）
        brain.tick(AIEnvironment.getFrame());
        HeroUnarmedMoveHelper.syncLockedInput(self);

        if (self.状态 == "技能" || self.状态 == "战技") { self.虎妙Z对齐 = null; return; }

        // ── 交战期 Z 微调 ──
        // 进入交战的阈值是 攻击判定Z（宽松，保证能开打），若交战期完全不动 Z，
        // 单位会卡在阈值边缘：目标稍一移动 Z 差超过 ×1.3 就被判出交战 → Chasing 又走回来
        // → 观感即"在离目标 Z 一段距离的地方上下反复走动，走进范围又走出去"。
        // 修复：交战中继续贴到 交战Z死区（默认5）才停，走进范围后稳定待在范围内。
        if (data.absdiff_z > p.交战Z死区) {
            var wantZ:Number = (data.diff_z < 0) ? -1 : 1;
            // ★边界收口：距边不足一个脱困探测距离时归零（防脱困振荡），见 clampZIntent
            var rawZ:Number = wantZ;
            wantZ = HeroUnarmedMoveHelper.clampZIntent(self, 0, wantZ);
            if (HeroUnarmedMoveHelper.shouldTakeOverZ(data, self, wantZ)) {
                // 近距离精确对齐（末步截断，永不越过目标 Z）
                self.虎妙Z对齐 = {目标: t, 每帧速度: HeroUnarmedMoveHelper._getZSpeed(self)};
                wantZ = 0;
            } else {
                self.虎妙Z对齐 = null;
            }
            // ★收口后的最后一程：目标贴边时由 Z 对齐接管小步走完（同 chase）
            if (rawZ != 0 && wantZ == 0 && self.虎妙Z对齐 == null) {
                self.虎妙Z对齐 = {目标: t, 每帧速度: HeroUnarmedMoveHelper._getZSpeed(self)};
            }
            if (wantZ != 0) {
                MovementResolver.applyBoundaryAwareMovement(UnitAIData(data), self, 0, wantZ);
            }
        } else {
            self.虎妙Z对齐 = null;
        }
    }
}
