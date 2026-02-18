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
    private var _retreatStartFrame:Number = -1;      // 撤退开始帧（超时兜底用）

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

        // 撤退/重整状态（受创脱离 → buff/换弹 → 恢复后重新进攻）
        this.AddStatus("Retreating", new FSM_Status(
            function() { behavior.retreat_action(); },
            function() { behavior.retreat_enter(); },
            null
        ));

        // ═══════ Root Gate 转换 ═══════

        // HeroCombatModule → Retreating（撤退检查，优先于目标死亡检查）
        this.pushGateTransition("HeroCombatModule", "Retreating", function() {
            return data.arbiter.getRetreatUrgency() > 0.6;
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
        this.pushGateTransition("Retreating", "Selector", function() {
            var urgency:Number = data.arbiter.getRetreatUrgency();
            if (urgency > 0.2) {
                // 紧迫度仍高，但检查是否退无可退
                // 角落（X+Z双贴边）
                if (data.bndCorner > 0.5) return true;
                // 撤退方向贴墙（单轴）→ 无法继续后退，回去战斗
                if (data.target != null && data.target._x != undefined) {
                    var retDir:Number = (data.diff_x > 0) ? -1 : 1;
                    if ((retDir < 0 && data.bndLeftDist < 80)
                     || (retDir > 0 && data.bndRightDist < 80)) {
                        return true;
                    }
                }
                // 超时兜底：撤退超过 120 帧(~5s) 且紧迫度已降至中等以下 → 回去战斗
                // 防止"低血无药一直跑"的死循环
                if (urgency < 0.5) {
                    var retreatDur:Number = _root.帧计时器.当前帧数 - behavior._retreatStartFrame;
                    if (retreatDur > 120) return true;
                }
                return false;
            }
            var maxHP = data.self.hp满血值;
            var hpR = (maxHP > 0) ? data.self.hp / maxHP : 1;
            return hpR > 0.4;
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

        // 收集移动意图 + 统一边界感知输出
        var wantX:Number = 0;
        var wantZ:Number = 0;
        if (absDx > moveThreshold) {
            wantX = (dx < 0) ? -1 : 1;
        }
        if (Math.abs(dz) > 20) {
            wantZ = (dz < 0) ? -1 : 1;
        }
        UnitAIData.applyBoundaryAwareMovement(data, self, wantX, wantZ);

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
        UnitAIData.clearInput(data.self);
    }

    // ═══════ 撤退/重整（T1-A）═══════

    /**
     * retreat_enter — 进入撤退状态
     * 保留当前目标引用（用于确定撤退方向），清除输入
     */
    public function retreat_enter():Void {
        UnitAIData.clearInput(data.self);
        _retreatStartFrame = _root.帧计时器.当前帧数;
    }

    /**
     * retreat_action — 撤退状态每帧动作
     *
     * 面朝方向策略：
     *   远程姿态(repositionDir > 0)：面朝目标（边退边射/边退边buff）
     *   近战姿态(repositionDir <= 0)：背对目标（全速奔跑撤离）
     *
     * 调用 arbiter.tick(data, "retreat") → PreBuff + Reload（无 Offense）
     */
    public function retreat_action():Void {
        var self:MovieClip = data.self;
        UnitAIData.clearInput(self);

        if (self.hp <= 0) return;
        if (_root.暂停) return;

        data.updateSelf();
        if (data.target != null && data.target.hp > 0) {
            data.updateTarget();
        }

        // 调用管线（retreat context → PreBuff + Reload，无 Offense）
        data.arbiter.tick(data, "retreat");

        // 技能期不移动
        var bt:String = data.arbiter.getExecutor().getCurrentBodyType();
        if (bt == "skill" || bt == "preBuff" || self.状态 == "技能" || self.状态 == "战技") {
            return;
        }

        var repoDir:Number = data.arbiter.getRepositionDir();

        // ── 收集移动意图 + 统一边界感知输出 ──
        var moveX:Number = 0;
        if (data.target != null && data.target._x != undefined) {
            var retDir:Number = (data.diff_x > 0) ? -1 : 1; // 远离目标
            // 撤退方向贴墙检查：退路被堵 → 放弃X轴撤退（Gate会检测并退出Retreating）
            var retWall:Boolean = (retDir < 0 && data.bndLeftDist < 80)
                               || (retDir > 0 && data.bndRightDist < 80);
            if (!retWall) {
                moveX = retDir;
            }
        }
        // Z轴撤退策略：优先拉开垂直距离，足够后轻微蛇形闪避
        var frame:Number = _root.帧计时器.当前帧数;
        var moveZ:Number = 0;
        var zSep:Number = data.absdiff_z; // 与目标的Z轴距离
        if (isNaN(zSep)) zSep = 0;
        var Z_SAFE:Number = 120; // 安全Z距离阈值

        if (zSep < Z_SAFE) {
            // Z距离不足：持续远离目标Z轴（选空间更大的一侧）
            if (data.diff_z != null && data.diff_z != 0) {
                // diff_z = tz - z，>0 目标在下方 → 往上(-1)，<0 目标在上方 → 往下(+1)
                var escapeZ:Number = (data.diff_z > 0) ? -1 : 1;
                // 验证逃离方向有空间
                if (escapeZ < 0 && data.bndUpDist < 50) {
                    escapeZ = 1; // 上方没空间，改往下
                } else if (escapeZ > 0 && data.bndDownDist < 50) {
                    escapeZ = -1; // 下方没空间，改往上
                }
                moveZ = escapeZ;
            } else {
                // 无目标Z信息：朝空间更大的一侧撤
                moveZ = (data.bndUpDist > data.bndDownDist) ? -1 : 1;
            }
        } else {
            // Z距离充足：轻微蛇形（30帧周期，不来回跑回去）
            // 仅在当前方向有空间时微调，不强制
            var zWave:Number = Math.floor(frame / 30) % 2;
            if (zWave == 0 && data.bndUpDist > 60) {
                moveZ = -1;
            } else if (zWave == 1 && data.bndDownDist > 60) {
                moveZ = 1;
            }
            // 否则 moveZ=0，不做Z轴移动（已拉开足够距离）
        }

        // ── 掩护射击判定（远程姿态：火力-机动交替）──
        // 核心问题：引擎将 左行/右行 与面朝方向耦合，无法同时移动和反向射击
        // 解法：开火帧放弃X轴移动（原地面朝目标射击），非开火帧正常撤退
        var wantFire:Boolean = false;
        if (repoDir > 0 && !self.射击中
            && bt != "reload"
            && (self.man == null || !self.man.换弹标签)) {
            // 余弹检查：弹药不足时停止掩护射击，纯撤退避免途中换弹
            // NaN 安全：武器属性异常时默认允许开火（NaN > 0.3 = false，故取反）
            var ammoR:Number = data.arbiter.getAmmoRatio(self);
            if (!(ammoR <= 0.3)) {
                var fireGap:Number = 6 - Math.floor((data.personality.反应 || 0) * 4);
                if (fireGap < 2) fireGap = 2;
                if (frame % fireGap == 0) {
                    wantFire = true;
                }
            }
        }

        if (wantFire) {
            // 开火帧：放弃X轴移动，仅保留Z轴（侧向闪避不影响面朝）
            UnitAIData.applyBoundaryAwareMovement(data, self, 0, moveZ);
            // 无X轴移动干扰，方向改变可生效
            if (data.diff_x > 0) self.方向改变("右");
            else if (data.diff_x < 0) self.方向改变("左");
            self.动作A = true;
            if (self.攻击模式 === "双枪") self.动作B = true;
        } else {
            // 非开火帧 / 弹药不足 / 近战姿态：正常撤退
            UnitAIData.applyBoundaryAwareMovement(data, self, moveX, moveZ);
        }

        // 切换跑步（非射击期间才切，避免打断射击动作）
        if (!self.射击中 && !self.动作A && (self.man == null || !self.man.换弹标签)) {
            self.状态改变(self.攻击模式 + "跑");
        }
    }
}
