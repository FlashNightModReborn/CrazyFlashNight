// ============================================================
// HeroUnarmedAI — 空手人形怪专用 AI 顶层对象（替代 BaseUnitAI 的角色）
//
// 由装备生命周期（九命猫妖初始化，真猫妖头套挂载）强制迁移挂载：
//   自机.unitAI.destroy(); 自机.unitAI = new HeroUnarmedAI(自机);
// 对外接口与 BaseUnitAI 对齐（D9 已核实外部依赖）：
//   update()  —— UpdateEventComponent.as:104 每 4 帧调用
//   destroy() —— StaticDeinitializer.as:30 单位移除时调用
//   isHeroUnarmed —— 生命周期防重复重建标记（换装刷新时保留现有 AI 状态）
//
// UnitAI 通用层（ActionArbiter/ActionExecutor/UtilityEvaluator/MovementResolver/Mover）
// 零改动：MovementResolver/Mover/AIEnvironment/UnitAIData/TargetCacheManager 只读复用（D7）。
// ============================================================

import org.flashNight.arki.unit.UnitAI.core.UnitAIData;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;
import org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedBehavior;
import org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedSkillBrain;

class org.flashNight.arki.unit.UnitAI.behavior.HeroUnarmedAI {

    public var self:MovieClip;
    public var data:UnitAIData;
    public var stateMachine:HeroUnarmedBehavior;
    public var brain:HeroUnarmedSkillBrain;
    public var isHeroUnarmed:Boolean = true;

    public function HeroUnarmedAI(_self:MovieClip) {
        this.self = _self;
        this.data = new UnitAIData(_self);
        // Z轴索敌范围：UnitAIData.init() 强制 zrange=10（通用层，不动），仅本 AI 实例覆写为 20。
        // init() 只在构造时跑一次、updateSelf 不回写、WeaponEvaluator 不在本 AI 链路 → 此处覆写后不会被冲掉。
        this.data.zrange = 20;
        // 参数由生命周期先写入 自机.配置AI参数（声库→AI参数→技能库→本构造 的顺序保证已就绪）
        var params:Object = _self.配置AI参数;
        if (params == null) params = {};
        this.brain = new HeroUnarmedSkillBrain(this.data, params);
        this.stateMachine = new HeroUnarmedBehavior(this.data, this.brain);
        this.stateMachine.activate();

        if (AIEnvironment.isAIDebug()) {
            AIEnvironment.log("[HU-AI] " + _self.名字 + " HeroUnarmedAI 挂载完成");
        }
    }

    // 更新入口（与 BaseUnitAI.update 对齐：直接驱动根状态机）
    public function update():Void {
        if (this.stateMachine != null) this.stateMachine.onAction();
    }

    /**
     * destroy — 释放资源（StaticDeinitializer 调用）
     * 清理：Z 轴精确对齐每帧任务（生命周期任务，unload 也会自动清，此处显式兜底）
     *       → 状态机 → 引用置空
     */
    public function destroy():Void {
        if (this.self != null) {
            this.self.虎妙Z对齐 = null;
            _root.帧计时器.移除生命周期任务(this.self, "虎妙Z精确对齐");
        }
        if (this.stateMachine != null) {
            this.stateMachine.destroy();
        }
        this.stateMachine = null;
        this.brain = null;
        this.data = null;
        this.self = null;
    }
}
