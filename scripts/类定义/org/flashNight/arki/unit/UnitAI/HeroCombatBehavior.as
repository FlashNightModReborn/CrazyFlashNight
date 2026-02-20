import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.BaseUnitBehavior;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.HeroCombatModule;
import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;
import org.flashNight.arki.unit.UnitAI.ActionArbiter;
import org.flashNight.arki.unit.UnitAI.MovementResolver;
import org.flashNight.arki.unit.UnitAI.strategies.RetreatMovementStrategy;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * 佣兵根状态机 — HFSM 模块化架构（Phase 1: 无损迁移）
 *
 * 根机状态：
 *   Sleeping        → 基类默认状态（暂停/无思考标签）
 *   Selector        → 决策中枢（映射原 思考()）
 *   HeroCombatModule → 战斗子状态机（Chasing / Engaging）
 *   Retreating      → 撤退/重整（受创脱离 → buff/换弹 → 恢复后重新进攻）
 *   FollowingHero   → 无目标时跟随（映射原 gotoAndPlay(命令) / 跟随）
 *   ManualOverride  → 玩家手动控制（映射原 不思考）
 *
 * 模块退出机制：
 *   HeroCombatModule → Retreating：retreatUrgency > 0.6（受创严重，主动脱离）
 *   HeroCombatModule → Selector：Root Gate 检测 data.target 死亡/消失
 *   Retreating       → Selector：紧迫度恢复 + HP回升
 *   FollowingHero    → Selector：超时重新评估 / 附近有敌人
 *   ManualOverride   → Selector：玩家释放控制 / 全自动开启
 *
 * Phase 2 注入点：
 *   evaluateHeal()   → Utility 评分替换概率逻辑
 *   evaluateWeapon() → Utility 评分替换随机切换
 *   selectSkill()    → 在 HeroCombatModule.Engaging 中
 */
class org.flashNight.arki.unit.UnitAI.HeroCombatBehavior extends BaseUnitBehavior {

    public static var FOLLOW_REEVAL_TIME:Number = 2; // 跟随状态重新评估间隔（2次action = 8帧）

    // ── 撤退移动策略（封装全部撤退移动 + 掩护射击逻辑）──
    private var _retreatMovement:RetreatMovementStrategy;

    public function HeroCombatBehavior(_data:UnitAIData) {
        super(_data);

        // 闭包捕获根机引用 — 解决 FSM_Status 回调 this 上下文问题
        // FSM_Status 回调中 this = FSM_Status 实例，无法访问 HeroCombatBehavior 的方法
        // 通过闭包委托到根机实例方法，确保 evaluateWeapon/evaluateHeal/searchTarget 可达
        var behavior:HeroCombatBehavior = this;

        // ── 创建 Utility 评估器 + 统一动作管线 ──
        // personality null 守卫已提升到 BaseUnitAI 构造函数，此处保证不为 null
        var eval:UtilityEvaluator = new UtilityEvaluator(data.personality);
        data.evaluator = eval;
        data.arbiter = new ActionArbiter(data.personality, eval, data.self);
        this._retreatMovement = new RetreatMovementStrategy();

        // ═══════ 状态列表 ═══════
        // 已存在：Sleeping（基类默认状态）

        // 决策中枢（映射原 思考()）— 闭包委托
        this.AddStatus("Selector", new FSM_Status(null, function() {
            behavior.selector_enter();
        }, null));

        // 战斗模块（子状态机）
        this.AddStatus("HeroCombatModule", new HeroCombatModule(data));

        // 跟随状态（无目标时）
        this.AddStatus("FollowingHero", new FSM_Status(null, this.follow_enter, null));

        // 玩家手动控制
        this.AddStatus("ManualOverride", new FSM_Status(null, this.manual_enter, null));

        // 撤退/重整状态（受创脱离 → buff/换弹 → 恢复后重新进攻）
        this.AddStatus("Retreating", new FSM_Status(
            function() { behavior.retreat_action(); },
            function() { behavior.retreat_enter(); },
            function() { behavior.retreat_exit(); }
        ));

        // ═══════ Root Gate 转换 ═══════

        // HeroCombatModule → Retreating（撤退检查，优先于目标死亡检查）
        // 阈值由 personality.retreatEnterThreshold 驱动（勇气低→更容易撤退）
        // S6: 冷却期内禁止再次进入撤退（振荡抑制）
        this.pushGateTransition("HeroCombatModule", "Retreating", function() {
            if (_root.帧计时器.当前帧数 < data._retreatCooldownUntil) return false;
            var threshold:Number = data.personality.retreatEnterThreshold;
            if (isNaN(threshold)) threshold = 0.6;
            return data.arbiter.getRetreatUrgency() > threshold;
        });

        // HeroCombatModule 退出：目标死亡/消失 → 回到 Selector 重新决策
        this.pushGateTransition("HeroCombatModule", "Selector", function() {
            var t = data.target;
            return (t == null || !(t.hp > 0));
        });

        // 跟随 → Selector（超时重新评估 + 敌人接近快速通道）
        this.pushGateTransition("FollowingHero", "Selector", function() {
            if (this.actionCount >= HeroCombatBehavior.FOLLOW_REEVAL_TIME) return true;
            // 快速通道：附近有有效敌人 → 立即重评估
            // 复用 ActionArbiter 周期采样的 nearbyCount（150px，16帧周期）
            if (data.arbiter != null && data.arbiter.getNearbyCount() > 0) {
                return true;
            }
            return false;
        });

        // 手动控制 → Selector（控制释放 / 全自动开启）
        this.pushGateTransition("ManualOverride", "Selector", function() {
            var self = data.self;
            return self.操控编号 == -1 || _root.控制目标全自动 == true;
        });

        // Retreating → Selector（紧迫度恢复 + HP回升 + 撤退方向被堵 + 超时兜底）
        // 阈值由 personality 驱动（retreatExitMinUrgency, retreatMaxDuration, retreatExitHPThreshold）
        this.pushGateTransition("Retreating", "Selector", function() {
            // Target lost/dead → 立即退出撤退回到 Selector
            var rt = data.target;
            if (rt == null || !(rt.hp > 0) || rt._x == undefined) return true;

            var pp:Object = data.personality;
            var exitUrg:Number = pp.retreatExitMinUrgency;
            if (isNaN(exitUrg)) exitUrg = 0.2;

            var urgency:Number = data.arbiter.getRetreatUrgency();
            if (urgency > exitUrg) {
                // 紧迫度仍高，但检查是否退无可退
                if (data.bndCorner > 0.5) return true;
                if (data.target != null && data.target._x != undefined) {
                    var retDir:Number = (data.diff_x > 0) ? -1 : 1;
                    if ((retDir < 0 && data.bndLeftDist < 80)
                     || (retDir > 0 && data.bndRightDist < 80)) {
                        return true;
                    }
                }
                // 超时兜底：紧迫度已降至中等以下 + 超时 → 回去战斗
                if (urgency < 0.5) {
                    var maxDur:Number = pp.retreatMaxDuration;
                    if (isNaN(maxDur)) maxDur = 120;
                    var retreatDur:Number = _root.帧计时器.当前帧数 - behavior._retreatMovement.getStartFrame();
                    if (retreatDur > maxDur) return true;
                }
                return false;
            }
            var exitHP:Number = pp.retreatExitHPThreshold;
            if (isNaN(exitHP)) exitHP = 0.4;
            var maxHP = data.self.hp满血值;
            var hpR = (maxHP > 0) ? data.self.hp / maxHP : 1;
            return hpR > exitHP;
        });

        // 唤醒：Sleeping → Selector
        this.pushGateTransition("Sleeping", "Selector", this.wakeupCheck);
    }

    // ═══════ 决策中枢（精确复刻原 思考()）═══════

    /**
     * selector_enter — 统一决策入口
     *
     * 复刻原 _root.主角模板ai函数.思考 的完整流程：
     * 1. 暂停检查（sleepCheck Gate 兜底）
     * 2. 死亡检查
     * 3. 玩家控制检查 → ManualOverride
     * 4. 武器模式评估 evaluateWeapon()
     * 5. 命令同步
     * 6. 血包评估 evaluateHeal()
     * 7. 目标搜索 searchTarget()
     * 8. 集中攻击目标覆盖（己方佣兵）
     * 9. 路由 → HeroCombatModule / FollowingHero
     */
    public function selector_enter():Void {
        data.updateSelf();
        var self = data.self;

        // 1. 暂停守卫（复刻原 if(_root.暂停) 逻辑）
        //    sleepCheck Gate 会在下帧处理，这里做安全退出
        if (_root.暂停) {
            this.ChangeState("FollowingHero");
            return;
        }

        // 2. 死亡守卫（复刻原 hp<=0 早期退出）
        if (self.hp <= 0) {
            self.状态改变(_root.血腥开关 == false ? "击倒" : "血腥死");
            return;
        }

        // 3. 玩家控制检查（复刻原 操控编号 != -1 && !全自动 → 不思考）
        if (self.操控编号 != -1 && _root.控制目标全自动 == false) {
            this.ChangeState("ManualOverride");
            return;
        }

        MovementResolver.clearInput(self);

        // 4-6. 武器模式 + 血包评估（统一管线）
        data.arbiter.tick(data, "selector");

        // 5. 命令同步（复刻原 _parent.命令 = _root.命令）
        self.命令 = _root.命令;

        // 7. 目标搜索（复刻原 aggroClear → 寻找攻击目标）
        self.dispatcher.publish("aggroClear", self);
        data.target = null;
        searchTarget();

        // 8-9. 决策路由
        var newstate:String;

        if (!self.是否为敌人) {
            // 己方佣兵
            if (_root.集中攻击目标 != "无" && _root.集中攻击目标) {
                // 集中攻击目标覆盖（复刻原 aggroSet + 强制进入攻击）
                var focusTarget = _root.gameworld[_root.集中攻击目标];
                if (focusTarget && focusTarget.hp > 0) {
                    data.target = focusTarget;
                    self.dispatcher.publish("aggroSet", self, focusTarget);
                }
                newstate = "HeroCombatModule";
            } else if (self.攻击目标 != "无" && self.攻击目标) {
                // 自主索敌成功
                newstate = "HeroCombatModule";
            } else {
                // 无目标 → 跟随/待命（复刻原 gotoAndPlay(命令)）
                newstate = "FollowingHero";
            }
        } else {
            // 敌方佣兵
            if (self.攻击目标 != "无" && self.攻击目标) {
                newstate = "HeroCombatModule";
            } else {
                // 无目标 → 跟随（复刻原 gotoAndStop("跟随")）
                newstate = "FollowingHero";
            }
        }

        this.ChangeState(newstate);
    }

    // ═══════ 目标搜索（复刻原 寻找攻击目标）═══════

    /**
     * searchTarget — 复刻原 寻找攻击目标
     *
     * 原始逻辑在每次思考时先 aggroClear 再搜索，因此总是走"搜索新目标"路径。
     * 使用 findValidEnemyForAI 替代原始 findNearestThreateningEnemy
     * （行为严格超集，修复了原始 threshold 变量引用 bug）。
     */
    public function searchTarget():Void {
        var self = data.self;

        // 计算威胁阈值（修复原始 threshold 自引用 bug）
        var threshold:Number = self.threatThreshold > 1
            ? LinearCongruentialEngine.instance.randomIntegerStrict(1, self.threatThreshold)
            : self.threatThreshold;

        var target = TargetCacheManager.findValidEnemyForAI(self, 1, threshold);

        if (target) {
            data.target = target;
            self.dispatcher.publish("aggroSet", self, target);
        } else {
            self.dispatcher.publish("aggroClear", self);
        }
    }

    // ═══════ 跟随（无目标时）═══════

    /**
     * follow_enter — 跟随状态
     *
     * 敌方佣兵：朝主角移动（复刻原 gotoAndStop("跟随") 行为）
     * 己方佣兵：朝主角移动，远距离时跑步跟随（Gate 超时后重新评估索敌）
     */
    public function follow_enter():Void {
        var self = data.self;
        MovementResolver.clearInput(self);

        if (data.standby) return;

        // 跟随目标：敌方 → 主角，己方 → 主角
        var hero:MovieClip = self.是否为敌人
            ? TargetCacheManager.findHero()
            : (data.player || TargetCacheManager.findHero());
        if (hero == null || hero.hp <= 0) return;

        data.updateSelf();
        var dx:Number = hero._x - data.x;
        var dz:Number = hero._y - data.z;
        var absDx:Number = Math.abs(dx);

        // 距离阈值：敌方 100，己方 150（稍远避免重叠）
        var moveThreshold:Number = self.是否为敌人 ? 100 : 150;

        // 收集移动意图 + 统一边界感知输出
        var wantX:Number = 0;
        var wantZ:Number = 0;
        if (absDx > moveThreshold) {
            wantX = (dx < 0) ? -1 : 1;
        }
        if (Math.abs(dz) > 20) {
            wantZ = (dz < 0) ? -1 : 1;
        }
        MovementResolver.applyBoundaryAwareMovement(data, self, wantX, wantZ);

        // 己方远距离跑步跟随
        if (wantX != 0 && !self.是否为敌人 && absDx > 300) {
            self.状态改变(self.攻击模式 + "跑");
        }
    }

    // ═══════ 玩家手动控制（映射原 不思考）═══════

    /**
     * manual_enter — 停止所有 AI 输出，让玩家输入接管
     */
    public function manual_enter():Void {
        MovementResolver.clearInput(data.self);
    }

    // ═══════ 撤退/重整 ═══════

    /**
     * retreat_enter — 进入撤退状态
     * 保留当前目标引用（用于确定撤退方向），清除输入
     */
    public function retreat_enter():Void {
        MovementResolver.clearInput(data.self);
        _retreatMovement.enter(_root.帧计时器.当前帧数);
    }

    /**
     * retreat_exit — 退出撤退状态
     *
     * S6: 设置再入冷却（振荡抑制）。
     * S9: 结果导向评估撤退有效性 — 未能拉开有效距离则累积失败计数，
     *     WeaponEvaluator 据此偏置近战（刷怪场景下远程撤退=负收益循环）。
     */
    public function retreat_exit():Void {
        var frame:Number = _root.帧计时器.当前帧数;

        // S6: 再入冷却
        var cooldown:Number = data.personality.retreatReentryCooldown;
        if (isNaN(cooldown) || cooldown <= 0) cooldown = 60;
        data._retreatCooldownUntil = frame + cooldown;

        // S9: 撤退效果评估（结果导向：不管退出原因，看是否拉开了有效距离）
        var t = data.target;
        if (t != null && t.hp > 0 && t._x != undefined) {
            data.updateSelf();
            data.updateTarget();
            // 远程有效距离阈值：≥200px 才够远程武器发挥
            if (data.absdiff_x < 200) {
                data._retreatFailCount++;
            } else {
                data._retreatFailCount = 0;
            }
        }

        if (_root.AI调试模式 == true) {
            _root.服务器.发布服务器消息("[RET-EXIT] " + data.self.名字
                + " dist=" + Math.round(data.absdiff_x)
                + " failCount=" + data._retreatFailCount);
        }
    }

    /**
     * retreat_action — 撤退状态每帧动作
     *
     * 前置处理（死亡/暂停/数据更新/管线调用/技能保护）后委托给
     * RetreatMovementStrategy 执行四阶段移动管线。
     *
     * 调用 arbiter.tick(data, "retreat") → PreBuff（无 Offense）
     */
    public function retreat_action():Void {
        var self:MovieClip = data.self;
        MovementResolver.clearInput(self);

        if (self.hp <= 0) return;
        if (_root.暂停) return;

        data.updateSelf();
        if (data.target != null && data.target.hp > 0) {
            data.updateTarget();
        }

        // 调用管线（retreat context → PreBuff，无 Offense）
        data.arbiter.tick(data, "retreat");

        // 技能期不移动
        var bt:String = data.arbiter.getExecutor().getCurrentBodyType();
        if (bt == "skill" || bt == "preBuff" || self.状态 == "技能" || self.状态 == "战技") {
            return;
        }

        // 委托撤退移动策略
        _retreatMovement.apply(data, self);
    }
}
