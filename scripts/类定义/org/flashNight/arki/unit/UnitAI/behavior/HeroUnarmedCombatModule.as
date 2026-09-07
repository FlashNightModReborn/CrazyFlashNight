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

        // 面朝目标（照抄默认 AI HeroCombatModule:229 写法；方向改变 内部有 锁定方向/飞行浮空 守卫，
        // 锁向或浮空时其内部直接 return，不会强行翻转）
        if (hasTarget) {
            if (data.x > data.tx) {
                self.方向改变("左");
            } else if (data.x < data.tx) {
                self.方向改变("右");
            }
        }

        // 技能脑无条件 tick：
        //   1) 升龙拳等跳起技的空中窗口、击倒脱困、喝药都不依赖目标；
        //   2) 状态==技能/战技 时 brain 内部走 commit/打断分支——不能在本模块提前 return，
        //      否则追击态下（被击退/目标拉开即进 Chasing）空中出招与击倒小跳会被整段吞掉。
        brain.tick(frame);
        // 方向锁回写（clearInput 会清掉跳跃方向输入）
        HeroUnarmedMoveHelper.syncLockedInput(self);

        // 已出招 → 本 tick 不输出移动；无目标 → 不移动（等根机回 Selector 重索敌）
        if (self.状态 == "技能" || self.状态 == "战技") return;
        if (!hasTarget) return;

        // Z 轴意图（5px 死区）
        var wantZ:Number = 0;
        if (data.absdiff_z > 5) {
            wantZ = (data.diff_z < 0) ? -1 : 1; // diff_z<0=目标偏上→上行(-1)
        }

        // ── Z 轴精确对齐接管判定（D3 三条件）──
        if (HeroUnarmedMoveHelper.shouldTakeOverZ(data, self, wantZ)) {
            // 激活每帧任务接管；本 tick 不输出 Z 意图（防双走）
            self.虎妙Z对齐 = {目标: t, 每帧速度: HeroUnarmedMoveHelper._getZSpeed(self)};
            wantZ = 0;
        } else {
            // 未接管则清掉，交回原路径
            self.虎妙Z对齐 = null;
        }

        // X 轴意图：朝目标移动
        var wantX:Number = 0;
        if (data.absdiff_x > p.攻击判定X * 0.6) {
            wantX = (data.diff_x < 0) ? -1 : 1;
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
        brain.tick(AIEnvironment.getFrame());
        HeroUnarmedMoveHelper.syncLockedInput(self);

        if (self.状态 == "技能" || self.状态 == "战技") return;

        // ── 交战期 Z 微调 ──
        // 进入交战的阈值是 攻击判定Z（宽松，保证能开打），若交战期完全不动 Z，
        // 单位会卡在阈值边缘：目标稍一移动 Z 差超过 ×1.3 就被判出交战 → Chasing 又走回来
        // → 观感即"在离目标 Z 一段距离的地方上下反复走动，走进范围又走出去"。
        // 修复：交战中继续贴到 交战Z死区（默认5）才停，走进范围后稳定待在范围内。
        if (data.absdiff_z > p.交战Z死区) {
            var wantZ:Number = (data.diff_z < 0) ? -1 : 1;
            if (HeroUnarmedMoveHelper.shouldTakeOverZ(data, self, wantZ)) {
                // 近距离精确对齐（末步截断，永不越过目标 Z）
                self.虎妙Z对齐 = {目标: t, 每帧速度: HeroUnarmedMoveHelper._getZSpeed(self)};
                wantZ = 0;
            } else {
                self.虎妙Z对齐 = null;
            }
            if (wantZ != 0) {
                MovementResolver.applyBoundaryAwareMovement(UnitAIData(data), self, 0, wantZ);
            }
        } else {
            self.虎妙Z对齐 = null;
        }
    }
}
