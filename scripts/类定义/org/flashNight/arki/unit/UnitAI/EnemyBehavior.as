import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.BaseUnitBehavior;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

// 敌人基础状态机，继承单位状态机基类

class org.flashNight.arki.unit.UnitAI.EnemyBehavior extends BaseUnitBehavior {

    public static var IDLE_BASIC_TIME:Number = 5; // 由追击进入停止 / 停止进入思考的最低间隔为5次action（即20帧）。计划在ai进一步重构后废弃
    public static var WANDER_BASIC_TIME:Number = 10; // 由追击进入随机移动 / 随机移动进入思考的最低间隔为10次action（即40帧）。计划在ai进一步重构后废弃
    public static var FOLLOW_TIME:Number = 5; // 跟随状态持续5次action（即20帧）
    public static var EVADE_TIME:Number = 10; // 远离状态持续10次action（即40帧）

    // 远离距离范围（为每个敌人分配不同的安全距离）
    public static var EVADE_DISTANCE_MIN:Number = 250; // 最小远离距离
    public static var EVADE_DISTANCE_MAX:Number = 400; // 最大远离距离

    public static var CHASE_TIME:Number = 30; // 暂时弃用

    public function EnemyBehavior(_data:UnitAIData) {
        super(_data);

        // 为每个敌人分配个性化的安全距离
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
        data.evade_distance = engine.randomIntegerStrict(EnemyBehavior.EVADE_DISTANCE_MIN, EnemyBehavior.EVADE_DISTANCE_MAX);

        // 初始化 player 引用，避免第一次使用时为 null
        data.player = TargetCacheManager.findHero();

        // 状态列表 
        // 已存在的包括基类的睡眠状态（默认状态）

        // 思考状态，结算进入状态函数后一定会跳转至其他状态
        this.AddStatus("Thinking", new FSM_Status(null, this.think, null));
        // 追击状态
        this.AddStatus("Chasing", new FSM_Status(this.chase, this.chase_enter, null));
        // 跟随状态
        this.AddStatus("Following", new FSM_Status(null, this.follow_enter, null));
        // 远离状态
        this.AddStatus("Evading", new FSM_Status(this.evade, this.evade_enter, null));
        // 空闲状态
        this.AddStatus("Idle", new FSM_Status(null, this.idle_enter, null));
        // 随机移动状态
        this.AddStatus("Wandering", new FSM_Status(null, this.wander_enter, null));

        //过渡线
        this.pushGateTransition("Chasing", "Idle", function() {
            return this.actionCount >= data.idle_threshold;
        });
        this.pushGateTransition("Chasing", "Wandering", function() {
            return this.actionCount >= data.wander_threshold;
        });
        this.pushGateTransition("Idle", "Thinking", function() {
            return this.actionCount >= data.think_threshold;
        });
        this.pushGateTransition("Wandering", "Thinking", function() {
            return this.actionCount >= data.think_threshold;
        });
        this.pushGateTransition("Following", "Thinking", function() {
            return this.actionCount >= EnemyBehavior.FOLLOW_TIME;
        });
        this.pushGateTransition("Evading", "Thinking", function() {
            return this.actionCount >= EnemyBehavior.EVADE_TIME;
        });

        // 检测到思考标签时结束睡眠状态进入思考状态
        this.pushGateTransition("Sleeping", "Thinking", this.wakeupCheck);
    }



    // 具体执行函数
    // 思考
    public function think():Void {
        data.updateSelf(); // 更新自身坐标

        // search target
        var self = data.self;
        var chaseTarget = self.攻击目标;

        // 先尝试解析“当前仇恨目标名”到真实对象；若目标已失效则清除并降级为重新索敌
        if (chaseTarget && chaseTarget != "无") {
            data.target = _root.gameworld[chaseTarget];
            var resolved:MovieClip = data.target;
            if (resolved == null || !(resolved.hp > 0)) {
                data.target = null;
                self.dispatcher.publish("aggroClear", self);
                chaseTarget = "无";
            }
        }

        // 当前无有效仇恨目标时才执行主动索敌
        if (!chaseTarget || chaseTarget == "无") {
            // 在1到威胁阈值中选取一个随机值，通过该威胁值索敌
            var threshold = self.threatThreshold > 1 ? LinearCongruentialEngine.instance.randomIntegerStrict(1, self.threatThreshold) : self.threatThreshold;
            // 使用新的智能搜索方法，自动过滤地图元件并降级搜索
            var target = TargetCacheManager.findValidEnemyForAI(self, 1, threshold);
            // _root.服务器.发布服务器消息(self._name, "at ", threshold, " 寻敌结果：", (target ? target._name : "无"));
            if (target) {
                data.target = target;
                self.dispatcher.publish("aggroSet", self, target);
            }
        }

        // _root.服务器.发布服务器消息(self._name, " 思考结果：", (data.target ? data.target._name : "无目标"));

        // 状态转移逻辑
        var newstate:String;
        if (data.target) {
            newstate = "Chasing";
        } else {
            // 没有攻击目标时才需要查找主角
            var hero = TargetCacheManager.findHero();
            if (hero != data.player) {
                data.player = hero;
            }

            if (!hero || !(hero.hp > 0)) {
                // 未找到攻击目标且主角死亡时，选择远离
                newstate = "Evading";
            } else {
                // 未找到攻击目标但主角存在时，跟随主角
                newstate = "Following";
            }
        }
        this.superMachine.ChangeState(newstate);
    }

    // 追击开始
    public function chase_enter():Void {
        var self:MovieClip = data.self;
        var 友军数量 = TargetCacheManager.getAllyCount(self, 5);
        if (友军数量 <= 1) {
            // 若己方没有任何队友，则永远不会停止追击
            data.idle_threshold = 999999;
            data.wander_threshold = 999999;
        } else {
            // 根据停止机率和随机移动机率随机一个临界时间
            var temp = 友军数量 <= 5 ? 4 : (友军数量 <= 10 ? 3 : 2);
            var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;

            data.idle_threshold = EnemyBehavior.IDLE_BASIC_TIME + engine.random(temp * self.停止机率);
            data.wander_threshold = EnemyBehavior.WANDER_BASIC_TIME + engine.random(temp * self.随机移动机率);
        }
    }

    // 追击
    public function chase():Void {
        var self = data.self;

        // 追击状态必须保证目标存在且有效；否则立即退回思考重新决策（避免“发呆/锁死”）
        var chaseTarget:String = self.攻击目标;
        if (!chaseTarget || chaseTarget == "无") {
            data.target = null;
            self.dispatcher.publish("aggroClear", self);
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            this.superMachine.ChangeState("Thinking");
            return;
        }

        // 与攻击目标参数一致（避免直接访问 data.target._name 导致 undefined 异常）
        if (!data.target || data.target._name != chaseTarget) {
            data.target = _root.gameworld[chaseTarget];
        }

        var t:MovieClip = data.target;
        if (t == null || !(t.hp > 0)) {
            data.target = null;
            self.dispatcher.publish("aggroClear", self);
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            this.superMachine.ChangeState("Thinking");
            return;
        }

        // 更新自身与攻击目标的坐标及差值
        data.updateSelf();
        data.updateTarget();

        if (data.absdiff_z < data.zrange && data.absdiff_x < data.xrange) {
            //每次action判定是否进入攻击
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            self.dispatcher.publish("aggroSet", self, data.target);
            if (data.diff_x < 0) {
                self.方向改变("左");
            } else if (data.diff_x > 0) {
                self.方向改变("右");
            }
            self.状态改变(self.攻击模式 + "攻击");
        } else if (!data.standby) {
            var sm = this.superMachine;
            if (sm.actionCount % 2 == 0) {
                //每奇数次action判定追击方向
                self.上行 = data.diff_z < 0;
                self.下行 = data.diff_z > 0;
                self.左行 = data.x > data.tx + data.xdistance;
                self.右行 = data.x < data.tx - data.xdistance;
            } else if (data.state != self.攻击模式 + "跑" && data.absdiff_x > data.run_threshold_x && data.absdiff_z > data.run_threshold_z) {
                //每偶数次action判定是否起跑
                if (LinearCongruentialEngine.instance.randomCheckHalf()) {
                    self.状态改变(self.攻击模式 + "跑");
                }
            }
        }
    }

    // 丢失攻击目标（未启用）
    // public function chase_exit():Void{
    // }

    // 跟随
    public function follow_enter():Void {
        data.updateSelf(); // 更新自身坐标
        var self = data.self;
        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;
        if (data.standby)
            return; // 待机状态下无法移动

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

    // 远离状态持续检查
    public function evade():Void {
        data.updateSelf();

        // 如果主角存在，检查距离
        if (data.player) {
            var distance = Math.sqrt((data.x - data.player._x) * (data.x - data.player._x) + (data.z - data.player._y) * (data.z - data.player._y));

            // 使用个性化的安全距离判断
            if (distance > data.evade_distance) {
                var self = data.self;
                // 停止移动
                self.左行 = false;
                self.右行 = false;
                self.上行 = false;
                self.下行 = false;

                // 转身面向主角位置（监视效果）
                if (data.x < data.player._x) {
                    self.方向改变("右");
                } else {
                    self.方向改变("左");
                }

                this.superMachine.ChangeState("Idle");
                return;
            }
        }

        // 主角复活时转入Following状态
        if (data.player && data.player.hp > 0) {
            this.superMachine.ChangeState("Following");
            return;
        }
    }

    // 远离主角
    public function evade_enter():Void {
        data.updateSelf(); // 更新自身坐标
        var self = data.self;
        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;

        if (data.standby)
            return; // 待机状态下无法移动

        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;

        // 如果主角存在但已死亡，远离主角；否则停止移动
        if (data.player) {
            var playerx = data.player._x;
            var playery = data.player._y;
            var distance = Math.sqrt((data.x - playerx) * (data.x - playerx) + (data.z - playery) * (data.z - playery));

            // 如果距离已经足够远，直接转入Idle状态
            if (distance > data.evade_distance) {
                this.superMachine.ChangeState("Idle");
                return;
            }

            // 计算基本远离方向
            var evadeX = data.x > playerx;
            var evadeZ = data.z > playery;

            // 增加方向随机性：有30%概率选择随机方向而不是严格远离
            var useRandomDirection = engine.randomCheck(30);

            if (useRandomDirection) {
                // 随机选择方向，增加散开效果
                evadeX = engine.randomCheckHalf();
                evadeZ = engine.randomCheckHalf();
            }

            // 增大随机偏移量，增强散开效果
            var randomOffsetX = engine.randomIntegerStrict(-80, 80);
            var randomOffsetZ = engine.randomIntegerStrict(-60, 60);

            // 远离距离也随机化
            var evadeDistanceX = engine.randomIntegerStrict(100, 180);
            var evadeDistanceZ = engine.randomIntegerStrict(60, 120);

            var targetX = data.x + (evadeX ? evadeDistanceX : -evadeDistanceX) + randomOffsetX;
            var targetZ = data.z + (evadeZ ? evadeDistanceZ : -evadeDistanceZ) + randomOffsetZ;

            // 敌人间排斥逻辑：检查附近友军并调整目标位置
            var nearbyAllies = TargetCacheManager.findAlliesInRadius(self, 1, 120);
            if (nearbyAllies.length > 0) {
                // 计算排斥向量
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
                            // 距离越近，排斥力越强
                            var force = (100 - dist) / dist;
                            repulseX += dx * force;
                            repulseZ += dz * force;
                        }
                    }
                }

                // 应用排斥力到目标位置
                targetX += repulseX * 0.5;
                targetZ += repulseZ * 0.5;
            }

            // 边界检查，确保不越界
            targetX = Math.max(_root.Xmin, Math.min(_root.Xmax, targetX));
            targetZ = Math.max(_root.Ymin, Math.min(_root.Ymax, targetZ));

            // 设置移动方向
            self.左行 = targetX < data.x;
            self.右行 = targetX > data.x;
            self.上行 = targetZ < data.z;
            self.下行 = targetZ > data.z;
        } else {
            // 主角不存在时，直接转入Idle状态
            this.superMachine.ChangeState("Idle");
        }
    }

    // 停止
    public function idle_enter():Void {
        // 丢失攻击目标
        data.target = null;
        data.self.dispatcher.publish("aggroClear", data.self);
        var self = data.self;
        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;

        // 如果主角存在但已死亡，面向主角进行监视
        if (data.player && data.player.hp <= 0) {
            data.updateSelf();
            if (data.x < data.player._x) {
                self.方向改变("右");
            } else {
                self.方向改变("左");
            }
        }

        // 根据友军数量计算随机时间
        var 友军数量 = TargetCacheManager.getAllyCount(self, 5);
        var temp = 友军数量 <= 5 ? 0 : (友军数量 <= 10 ? 1 : 2);
        data.think_threshold = EnemyBehavior.IDLE_BASIC_TIME + LinearCongruentialEngine.instance.random(temp * EnemyBehavior.IDLE_BASIC_TIME);
    }

    // 随机移动
    public function wander_enter():Void {
        // 丢失攻击目标
        data.target = null;
        data.self.dispatcher.publish("aggroClear", data.self);
        data.updateSelf(); // 更新自身坐标

        var self = data.self;
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;

        // 根据友军数量计算随机时间
        var 友军数量 = TargetCacheManager.getAllyCount(self, 5);
        var temp = 友军数量 <= 5 ? 0 : (友军数量 <= 10 ? 1 : 2);
        data.think_threshold = EnemyBehavior.WANDER_BASIC_TIME + engine.random(temp * EnemyBehavior.WANDER_BASIC_TIME);

        if (data.standby) {
            // 待机状态下无法移动
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            return;
        }

        var randy = engine.randomIntegerStrict(_root.Ymin, _root.Ymax);
        var randx = engine.randomIntegerStrict(_root.Xmin, _root.Xmax);

        self.左行 = randx < data.x;
        self.右行 = !self.左行;
        self.上行 = randy < data.z;
        self.下行 = randy > data.z;
    }
}
