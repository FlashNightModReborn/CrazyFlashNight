import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * 战斗模块 — 作为子状态机嵌入根机 EnemyBehavior
 *
 * 内部状态：Chasing (default) / Idle / Wandering
 * 退出条件：由根机 Gate 检测目标死亡/消失，本模块不主动退出
 *
 * 关键设计：
 *   - Idle/Wandering 保留 data.target 引用，仅发布 aggroClear
 *     → 根机 Gate 可持续监测目标血量，目标死亡时即时退出
 *   - chase_enter 同步外部 攻击目标 变更（如被击触发仇恨）
 *   - 重入时通过 machine-level onEnter 强制重置到 Chasing
 */
class org.flashNight.arki.unit.UnitAI.CombatModule extends FSM_StateMachine {

    public static var IDLE_BASIC_TIME:Number = 5;
    public static var WANDER_BASIC_TIME:Number = 10;

    public function CombatModule(_data:UnitAIData) {
        // machine-level onEnter: 重入时强制重置到 Chasing
        // onEnter 阶段 ChangeState = _csInit（pointer-only）
        // 首次进入：Chasing 是 default，自转换被拒绝，无副作用
        // 重入：从 Idle/Wandering 重置到 Chasing
        super(null, function() {
            this.ChangeState("Chasing");
        }, null);

        // C3d: data 必须在 AddStatus 之前设定
        this.data = _data;

        // 子状态
        this.AddStatus("Chasing", new FSM_Status(this.chase, this.chase_enter, null));
        this.AddStatus("Idle", new FSM_Status(null, this.idle_enter, null));
        this.AddStatus("Wandering", new FSM_Status(null, this.wander_enter, null));

        // 内部 Gate 转换
        // Chasing → Idle / Wandering（战术暂停）
        this.transitions.push("Chasing", "Idle", function() {
            return this.actionCount >= _data.idle_threshold;
        }, true);
        this.transitions.push("Chasing", "Wandering", function() {
            return this.actionCount >= _data.wander_threshold;
        }, true);
        // Idle / Wandering → Chasing（恢复追击，替代原来经 Thinking 绕回的路径）
        this.transitions.push("Idle", "Chasing", function() {
            return this.actionCount >= _data.think_threshold;
        }, true);
        this.transitions.push("Wandering", "Chasing", function() {
            return this.actionCount >= _data.think_threshold;
        }, true);
    }

    // ═══════ 追击 ═══════

    public function chase_enter():Void {
        var self:MovieClip = data.self;

        // 同步外部 攻击目标 变更（如 HitUpdater 在 idle 期间触发仇恨）
        var extTarget:String = self.攻击目标;
        if (extTarget && extTarget != "无") {
            var resolved = _root.gameworld[extTarget];
            if (resolved != null && resolved.hp > 0 && resolved != data.target) {
                data.target = resolved;
            }
        }
        // 确保 aggroSet 发布（idle/wander 期间已 aggroClear）
        if (data.target != null) {
            self.dispatcher.publish("aggroSet", self, data.target);
        }

        // 原有的友军数量 / threshold 计算
        var 友军数量 = TargetCacheManager.getAllyCount(self, 5);
        if (友军数量 <= 1) {
            data.idle_threshold = 999999;
            data.wander_threshold = 999999;
        } else {
            var temp = 友军数量 <= 5 ? 4 : (友军数量 <= 10 ? 3 : 2);
            var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
            data.idle_threshold = CombatModule.IDLE_BASIC_TIME + engine.random(temp * self.停止机率);
            data.wander_threshold = CombatModule.WANDER_BASIC_TIME + engine.random(temp * self.随机移动机率);
        }
    }

    public function chase():Void {
        var self = data.self;

        // 目标失效守卫 — 不主动 ChangeState，root Gate 下帧处理
        var t:MovieClip = data.target;
        if (t == null || !(t.hp > 0)) {
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            return;
        }

        // 与外部 攻击目标 参数保持一致
        var chaseTarget:String = self.攻击目标;
        if (chaseTarget && chaseTarget != "无" && t._name != chaseTarget) {
            var resolved = _root.gameworld[chaseTarget];
            if (resolved != null && resolved.hp > 0) {
                data.target = resolved;
                t = resolved;
            }
        }

        // 更新坐标
        data.updateSelf();
        data.updateTarget();

        if (data.absdiff_z < data.zrange && data.absdiff_x < data.xrange) {
            // 攻击范围内
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
            if ((sm.getActionCount() & 1) == 0) {
                self.上行 = data.diff_z < 0;
                self.下行 = data.diff_z > 0;
                self.左行 = data.x > data.tx + data.xdistance;
                self.右行 = data.x < data.tx - data.xdistance;
            } else if (data.state != self.攻击模式 + "跑" && data.absdiff_x > data.run_threshold_x && data.absdiff_z > data.run_threshold_z) {
                if (LinearCongruentialEngine.instance.randomCheckHalf()) {
                    self.状态改变(self.攻击模式 + "跑");
                }
            }
        }
    }

    // ═══════ 停止（战术暂停）═══════

    public function idle_enter():Void {
        // 关键：保留 data.target 引用，供 root Gate 持续监测
        // 仅发布 aggroClear 让外部系统知道当前不在主动攻击
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
        data.think_threshold = CombatModule.IDLE_BASIC_TIME + LinearCongruentialEngine.instance.random(temp * CombatModule.IDLE_BASIC_TIME);
    }

    // ═══════ 随机移动（战术暂停）═══════

    public function wander_enter():Void {
        // 关键：保留 data.target 引用，同 idle_enter
        data.self.dispatcher.publish("aggroClear", data.self);
        data.updateSelf();

        var self = data.self;
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;

        var 友军数量 = TargetCacheManager.getAllyCount(self, 5);
        var temp = 友军数量 <= 5 ? 0 : (友军数量 <= 10 ? 1 : 2);
        data.think_threshold = CombatModule.WANDER_BASIC_TIME + engine.random(temp * CombatModule.WANDER_BASIC_TIME);

        if (data.standby) {
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
