import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.BaseUnitBehavior;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.HeroCombatModule;
import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;
import org.flashNight.arki.unit.UnitAI.ActionArbiter;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * 佣兵根状态机 — HFSM 模块化架构（Phase 1: 无损迁移）
 *
 * 根机状态：
 *   Sleeping        → 基类默认状态（暂停/无思考标签）
 *   Selector        → 决策中枢（映射原 思考()）
 *   HeroCombatModule → 战斗子状态机（Chasing / Engaging）
 *   FollowingHero   → 无目标时跟随（映射原 gotoAndPlay(命令) / 跟随）
 *   ManualOverride  → 玩家手动控制（映射原 不思考）
 *
 * 模块退出机制：
 *   HeroCombatModule → Selector：Root Gate 检测 data.target 死亡/消失
 *   FollowingHero    → Selector：超时重新评估
 *   ManualOverride   → Selector：玩家释放控制 / 全自动开启
 *
 * Phase 2 注入点：
 *   evaluateHeal()   → Utility 评分替换概率逻辑
 *   evaluateWeapon() → Utility 评分替换随机切换
 *   selectSkill()    → 在 HeroCombatModule.Engaging 中
 */
class org.flashNight.arki.unit.UnitAI.HeroCombatBehavior extends BaseUnitBehavior {

    public static var FOLLOW_REEVAL_TIME:Number = 5; // 跟随状态重新评估间隔（5次action = 20帧）

    public function HeroCombatBehavior(_data:UnitAIData) {
        super(_data);

        // 闭包捕获根机引用 — 解决 FSM_Status 回调 this 上下文问题
        // FSM_Status 回调中 this = FSM_Status 实例，无法访问 HeroCombatBehavior 的方法
        // 通过闭包委托到根机实例方法，确保 evaluateWeapon/evaluateHeal/searchTarget 可达
        var behavior:HeroCombatBehavior = this;

        // ── 创建 Utility 评估器 + 统一动作管线（无条件）──
        // Phase 3a: 移除 personality null 守卫；personality 应在 配置人形怪AI 中已设置
        if (data.personality == null) {
            // 防御性兜底：复用 配置人形怪AI 的 seed 算法，避免 seed=0 导致同质化
            _root.服务器.发布服务器消息("[AI WARNING] " + data.self._name
                + " personality==null, auto-generating");
            var self:MovieClip = data.self;
            if (self.aiSeed == null) {
                var _seed:Number = self.等级 || 0;
                var _n:String = self.名字 || self._name;
                for (var _i:Number = 0; _i < _n.length; _i++) {
                    _seed = _seed * 31 + _n.charCodeAt(_i);
                }
                self.aiSeed = _seed & 0x7FFFFFFF;
            }
            self.personality = _root.生成随机人格(self.aiSeed);
            _root.计算AI参数(self.personality);
            data.personality = self.personality;
        }
        var eval:UtilityEvaluator = new UtilityEvaluator(data.personality);
        data.evaluator = eval;
        data.arbiter = new ActionArbiter(data.personality, eval, data.self);

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

        // ═══════ Root Gate 转换 ═══════

        // HeroCombatModule 退出：目标死亡/消失 → 回到 Selector 重新决策
        this.pushGateTransition("HeroCombatModule", "Selector", function() {
            var t = data.target;
            return (t == null || !(t.hp > 0));
        });

        // 跟随 → Selector（超时重新评估）
        this.pushGateTransition("FollowingHero", "Selector", function() {
            return this.actionCount >= HeroCombatBehavior.FOLLOW_REEVAL_TIME;
        });

        // 手动控制 → Selector（控制释放 / 全自动开启）
        this.pushGateTransition("ManualOverride", "Selector", function() {
            var self = data.self;
            return self.操控编号 == -1 || _root.控制目标全自动 == true;
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

        UnitAIData.clearInput(self);

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
        UnitAIData.clearInput(self);

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

        if (absDx > moveThreshold) {
            self.左行 = dx < 0;
            self.右行 = dx > 0;
            // 己方远距离跑步跟随
            if (!self.是否为敌人 && absDx > 300) {
                self.状态改变(self.攻击模式 + "跑");
            }
        }
        if (Math.abs(dz) > 20) {
            self.上行 = dz < 0;
            self.下行 = dz > 0;
        }
    }

    // ═══════ 玩家手动控制（映射原 不思考）═══════

    /**
     * manual_enter — 停止所有 AI 输出，让玩家输入接管
     */
    public function manual_enter():Void {
        UnitAIData.clearInput(data.self);
    }
}
