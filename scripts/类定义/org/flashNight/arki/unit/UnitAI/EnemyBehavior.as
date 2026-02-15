import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.BaseUnitBehavior;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.CombatModule;
import org.flashNight.arki.unit.UnitAI.PickupModule;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.naki.Select.QuickSelect;

/**
 * 敌人根状态机 — HFSM 模块化架构
 *
 * 根机状态：
 *   Sleeping    → 基类默认状态（暂停/无思考标签）
 *   Selector    → 决策中枢（替代原 Thinking），按优先级选择模块
 *   CombatModule → 战斗子状态机（Chasing / Idle / Wandering）
 *   PickupModule → 拾取子状态机（ChasingPickup），可选，通过 setPickupEnabled() 注册
 *   Following   → 跟随主角
 *   Evading     → 远离死亡主角
 *   Idle        → 简单停顿（远离后的过渡状态）
 *
 * 模块退出机制：
 *   CombatModule → Selector：Root Gate 检测 data.target 死亡/消失
 *   PickupModule → Selector：Root Gate 检测 target 消失/area==null/超时
 */
class org.flashNight.arki.unit.UnitAI.EnemyBehavior extends BaseUnitBehavior {

    public static var IDLE_BASIC_TIME:Number = 5;   // 根级 Idle 持续时间（20帧）
    public static var FOLLOW_TIME:Number = 5;        // 跟随状态持续5次action（20帧）
    public static var EVADE_TIME:Number = 10;        // 远离状态持续10次action（40帧）

    // 远离距离范围（为每个敌人分配不同的安全距离）
    public static var EVADE_DISTANCE_MIN:Number = 250;
    public static var EVADE_DISTANCE_MAX:Number = 400;

    public function EnemyBehavior(_data:UnitAIData) {
        super(_data);

        // 为每个敌人分配个性化的安全距离
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
        data.evade_distance = engine.randomIntegerStrict(EnemyBehavior.EVADE_DISTANCE_MIN, EnemyBehavior.EVADE_DISTANCE_MAX);

        // 初始化 player 引用，避免第一次使用时为 null
        data.player = TargetCacheManager.findHero();

        // ═══════ 状态列表 ═══════
        // 已存在：Sleeping（基类默认状态）

        // 决策中枢（替代原 Thinking）
        this.AddStatus("Selector", new FSM_Status(null, this.selector_enter, null));

        // 战斗模块（子状态机）
        this.AddStatus("CombatModule", new CombatModule(data));

        // 跟随状态
        this.AddStatus("Following", new FSM_Status(null, this.follow_enter, null));
        // 远离状态
        this.AddStatus("Evading", new FSM_Status(this.evade, this.evade_enter, null));
        // 简单停顿状态（远离后的过渡）
        this.AddStatus("Idle", new FSM_Status(null, this.idle_enter, null));

        // ═══════ Root Gate 转换 ═══════

        // CombatModule 退出：目标死亡/消失 → 回到 Selector 重新决策
        this.pushGateTransition("CombatModule", "Selector", function() {
            var t = data.target;
            return (t == null || !(t.hp > 0));
        });

        // 跟随 → Selector
        this.pushGateTransition("Following", "Selector", function() {
            return this.actionCount >= EnemyBehavior.FOLLOW_TIME;
        });
        // 远离 → Selector
        this.pushGateTransition("Evading", "Selector", function() {
            return this.actionCount >= EnemyBehavior.EVADE_TIME;
        });
        // 停顿 → Selector
        this.pushGateTransition("Idle", "Selector", function() {
            return this.actionCount >= EnemyBehavior.IDLE_BASIC_TIME;
        });

        // 唤醒：Sleeping → Selector
        this.pushGateTransition("Sleeping", "Selector", this.wakeupCheck);
    }

    // ═══════ 模块注册 ═══════

    /**
     * 启用拾取能力 — 注册 PickupModule 子状态机
     * 由 BaseUnitAI 工厂在创建 "PickupEnemy" 类型时调用
     */
    public function setPickupEnabled():Void {
        if (this.statusDict["PickupModule"]) return; // 已注册，幂等

        this.AddStatus("PickupModule", new PickupModule(data));

        // PickupModule 退出：拾取物消失/被拾取/超时 → 回到 Selector
        this.pushGateTransition("PickupModule", "Selector", function() {
            var t = data.target;
            return (t == null || t.area == null || this.actionCount >= PickupModule.CHASE_PICKUP_TIME);
        });
    }

    // ═══════ 决策中枢 ═══════

    /**
     * Selector — 统一决策入口（合并原 EnemyBehavior.think + PickupEnemyBehavior.think）
     *
     * 优先级：拾取物（如果 PickupModule 可用）> 战斗目标 > 跟随/远离
     */
    public function selector_enter():Void {
        data.updateSelf();

        var self = data.self;
        var chaseTarget = self.攻击目标;

        // Step 1: 解析现有仇恨目标 → 验证 → 失效则清除并降级为重新索敌
        if (chaseTarget && chaseTarget != "无") {
            data.target = _root.gameworld[chaseTarget];
            var resolved:MovieClip = data.target;
            if (resolved == null || !(resolved.hp > 0)) {
                data.target = null;
                self.dispatcher.publish("aggroClear", self);
                chaseTarget = "无";
            }
        }

        // Step 2: 无有效仇恨目标时主动索敌
        if (!chaseTarget || chaseTarget == "无") {
            var threshold = self.threatThreshold > 1
                ? LinearCongruentialEngine.instance.randomIntegerStrict(1, self.threatThreshold)
                : self.threatThreshold;
            var target = TargetCacheManager.findValidEnemyForAI(self, 1, threshold);
            if (target) {
                data.target = target;
                self.dispatcher.publish("aggroSet", self, target);
            }
        }

        // Step 3: 拾取物搜索（仅当 PickupModule 已注册且单位允许拾取）
        var targetItem:MovieClip = null;
        var hasPickupModule:Boolean = (this.superMachine && this.superMachine.hasStatus("PickupModule"));

        if (hasPickupModule && self.允许拾取) {
            // 己方单位背包已满时禁用拾取
            if (self.是否为敌人 == false) {
                if (_root.物品栏.背包.getFirstVacancy() == -1) {
                    self.允许拾取 = false;
                    hasPickupModule = false;
                }
            }

            if (hasPickupModule) {
                // 最大拾取范围：默认800，受最近敌人距离限制
                var maxdistance:Number = 800;
                if (data.target) {
                    var enemyDist:Number = Math.abs(data.target._x - data.x);
                    if (enemyDist > 0 && enemyDist < maxdistance) {
                        maxdistance = enemyDist;
                    }
                }

                // 收集已落地的可拾取物
                var 可拾取物距离表 = [];
                for (var i in _root.pickupItemManager.pickupItemDict) {
                    var 可拾取物 = _root.pickupItemManager.pickupItemDict[i];
                    if (可拾取物 != null && 可拾取物.area != null) {
                        可拾取物距离表.push({
                            物品: 可拾取物,
                            距离: Math.abs(可拾取物._x - data.x)
                        });
                    }
                }

                // 根据数据量选择搜索算法
                var 最小距离 = maxdistance;
                if (可拾取物距离表.length > 0) {
                    if (可拾取物距离表.length <= 20) {
                        for (var j = 0; j < 可拾取物距离表.length; j++) {
                            if (可拾取物距离表[j].距离 < 最小距离) {
                                最小距离 = 可拾取物距离表[j].距离;
                                targetItem = 可拾取物距离表[j].物品;
                            }
                        }
                    } else {
                        var 最近记录 = QuickSelect.selectKth(
                            可拾取物距离表, 0,
                            function(a, b) { return a.距离 - b.距离; }
                        );
                        if (最近记录.距离 < maxdistance) {
                            targetItem = 最近记录.物品;
                        }
                    }
                }
            }
        }

        // Step 4: 决策 — 按优先级选择目标状态
        var newstate:String;

        if (targetItem != null) {
            // 最高优先级：拾取
            data.target = targetItem;
            self.dispatcher.publish("aggroClear", self);
            self.拾取目标 = targetItem._name;
            newstate = "PickupModule";
        } else if (data.target) {
            // 战斗目标
            newstate = "CombatModule";
        } else {
            // 无目标：跟随 / 远离
            var hero = TargetCacheManager.findHero();
            if (hero != data.player) {
                data.player = hero;
            }
            if (!hero || !(hero.hp > 0)) {
                newstate = "Evading";
            } else {
                newstate = "Following";
            }
        }

        this.superMachine.ChangeState(newstate);
    }

    // ═══════ 跟随 ═══════

    public function follow_enter():Void {
        data.updateSelf();
        var self = data.self;
        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;
        if (data.standby)
            return;

        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;

        var X距离 = engine.randomIntegerStrict(100, 300);
        var Y距离 = 50;
        var playerx = data.player._x;
        var playery = data.player._y;

        if (Math.abs(data.x - playerx) > X距离) {
            self.左行 = data.x > playerx;
            self.右行 = data.x < playerx;
            var randz = engine.randomIntegerStrict(_root.Ymin, _root.Ymax);
            if (Math.abs(data.z - randz) > Y距离) {
                self.上行 = data.z > randz;
                self.下行 = data.z < randz;
            }
        } else if (Math.abs(data.z - playery) > Y距离) {
            self.上行 = data.z > playery;
            self.下行 = data.z < playery;
        }
    }

    // ═══════ 远离 ═══════

    public function evade():Void {
        data.updateSelf();

        if (data.player) {
            var distance = Math.sqrt((data.x - data.player._x) * (data.x - data.player._x) + (data.z - data.player._y) * (data.z - data.player._y));

            if (distance > data.evade_distance) {
                var self = data.self;
                self.左行 = false;
                self.右行 = false;
                self.上行 = false;
                self.下行 = false;

                if (data.x < data.player._x) {
                    self.方向改变("右");
                } else {
                    self.方向改变("左");
                }

                this.superMachine.ChangeState("Idle");
                return;
            }
        }

        if (data.player && data.player.hp > 0) {
            this.superMachine.ChangeState("Following");
            return;
        }
    }

    public function evade_enter():Void {
        data.updateSelf();
        var self = data.self;
        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;

        if (data.standby)
            return;

        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;

        if (data.player) {
            var playerx = data.player._x;
            var playery = data.player._y;
            var distance = Math.sqrt((data.x - playerx) * (data.x - playerx) + (data.z - playery) * (data.z - playery));

            if (distance > data.evade_distance) {
                this.superMachine.ChangeState("Idle");
                return;
            }

            var evadeX = data.x > playerx;
            var evadeZ = data.z > playery;

            var useRandomDirection = engine.randomCheck(30);
            if (useRandomDirection) {
                evadeX = engine.randomCheckHalf();
                evadeZ = engine.randomCheckHalf();
            }

            var randomOffsetX = engine.randomIntegerStrict(-80, 80);
            var randomOffsetZ = engine.randomIntegerStrict(-60, 60);
            var evadeDistanceX = engine.randomIntegerStrict(100, 180);
            var evadeDistanceZ = engine.randomIntegerStrict(60, 120);

            var targetX = data.x + (evadeX ? evadeDistanceX : -evadeDistanceX) + randomOffsetX;
            var targetZ = data.z + (evadeZ ? evadeDistanceZ : -evadeDistanceZ) + randomOffsetZ;

            var nearbyAllies = TargetCacheManager.findAlliesInRadius(self, 1, 120);
            if (nearbyAllies.length > 0) {
                var repulseX = 0;
                var repulseZ = 0;

                for (var i = 0; i < nearbyAllies.length; i++) {
                    var ally = nearbyAllies[i];
                    if (ally != self) {
                        var allyX = ally._x;
                        var allyZ = ally.Z轴坐标 || ally._y;
                        var dx = data.x - allyX;
                        var dz = data.z - allyZ;
                        var dist = Math.sqrt(dx * dx + dz * dz);

                        if (dist > 0 && dist < 100) {
                            var force = (100 - dist) / dist;
                            repulseX += dx * force;
                            repulseZ += dz * force;
                        }
                    }
                }

                targetX += repulseX * 0.5;
                targetZ += repulseZ * 0.5;
            }

            targetX = Math.max(_root.Xmin, Math.min(_root.Xmax, targetX));
            targetZ = Math.max(_root.Ymin, Math.min(_root.Ymax, targetZ));

            self.左行 = targetX < data.x;
            self.右行 = targetX > data.x;
            self.上行 = targetZ < data.z;
            self.下行 = targetZ > data.z;
        } else {
            this.superMachine.ChangeState("Idle");
        }
    }

    // ═══════ 根级停顿（远离后的过渡）═══════

    public function idle_enter():Void {
        var self = data.self;
        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;

        // 面向主角位置（监视效果）
        if (data.player) {
            data.updateSelf();
            if (data.x < data.player._x) {
                self.方向改变("右");
            } else {
                self.方向改变("左");
            }
        }
    }
}
