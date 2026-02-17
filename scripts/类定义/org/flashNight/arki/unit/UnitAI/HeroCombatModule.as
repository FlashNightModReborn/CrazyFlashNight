import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.UnitAIData;

/**
 * 佣兵战斗模块 — 作为子状态机嵌入根机 HeroCombatBehavior
 *
 * 内部状态：Chasing (default) / Engaging
 * 退出条件：由根机 Gate 检测目标死亡/消失
 *
 * Phase 2 注入点：selectSkill() 可替换为 Utility 评分选择
 */
class org.flashNight.arki.unit.UnitAI.HeroCombatModule extends FSM_StateMachine {

    public function HeroCombatModule(_data:UnitAIData) {
        // machine-level onEnter: 重入时强制重置到 Chasing
        super(null, function() { this.ChangeState("Chasing"); }, null);
        this.data = _data;

        // 闭包捕获子状态机引用 — engage() 需要调用 selectSkill()/getRandomSkill()
        // 这些是 HeroCombatModule 的实例方法，FSM_Status 回调中 this = FSM_Status 无法访问
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

        // 重置移动与动作标志
        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;
        self.动作A = false;
        self.动作B = false;

        // 目标失效守卫
        var t:MovieClip = data.target;
        if (t == null || !t._x) return;

        data.updateSelf();
        data.updateTarget();

        // ── 统一动作管线（Phase 2 Step 5）──
        // 预战buff + 换弹 + 武器评估 全部收敛到 arbiter.tick()
        // arbiter 内部按中断规则互斥，不再有覆盖冲突
        if (data.arbiter != null) {
            data.arbiter.tick(data, "chase");

            // 技能期：禁止跑步切换/移动输入，避免非技能动作打断技能
            // （设计：只有技能才能取消技能）
            var bt:String = data.arbiter.getExecutor().getCurrentBodyType();
            if (bt == "skill" || bt == "preBuff" || self.状态 == "技能" || self.状态 == "战技") {
                return;
            }
        }

        // 跑步切换（修正运算符优先级：原 !self.man.换弹标签 != null 永远为 true）
        if (!self.射击中 && (self.man == null || !self.man.换弹标签) && random(3) == 0) {
            self.状态改变(self.攻击模式 + "跑");
        }

        // Z轴移动（原始使用 _y 而非 Z轴坐标）
        if (self._y > t.Z轴坐标) {
            self.上行 = true;
        } else {
            self.下行 = true;
        }

        // X轴移动（保持距离）
        if (data.x > data.tx + data.xdistance) {
            self.左行 = true;
        } else if (data.x < data.tx - data.xdistance) {
            self.右行 = true;
        }
    }

    // ═══════ 交战（射程内）═══════

    public function engage_enter():Void {
        var self:MovieClip = data.self;
        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;
    }

    public function engage():Void {
        var self:MovieClip = data.self;

        // 每 tick 重置所有输出标志（evaluator/fallback 按需设置）
        self.动作A = false;
        self.动作B = false;
        self.左行 = false;
        self.右行 = false;

        // 目标失效守卫
        var t:MovieClip = data.target;
        if (t == null || !t._x) return;

        data.updateSelf();
        data.updateTarget();

        // 面朝目标
        if (data.x > data.tx) {
            self.方向改变("左");
        } else if (data.x < data.tx) {
            self.方向改变("右");
        }

        // ── 统一动作管线（Phase 2 Step 5）──
        // 技能/平A/换弹/武器评估 全部收敛到 arbiter.tick()
        // arbiter 内部按中断规则互斥，不再有 gotoAndPlay 覆盖冲突
        if (data.arbiter != null) {
            data.arbiter.tick(data, "engage");

            // 远程风筝：边打边退（Stance repositionDir > 0 时激活）
            // 目标过近（< 40% 保持距离）→ 后退，保持射击距离
            // 技能期不输出移动（避免走动取消技能）
            var bodyType:String = data.arbiter.getExecutor().getCurrentBodyType();
            if (bodyType != "skill" && bodyType != "preBuff" && self.状态 != "技能" && self.状态 != "战技") {
                if (data.arbiter.getRepositionDir() > 0 && data.absdiff_x < data.xdistance * 0.4) {
                    if (data.diff_x > 0) {
                        self.左行 = true;
                    } else {
                        self.右行 = true;
                    }
                }
            }
        } else {
            selectSkillFallback();
        }

        // 目标死亡检查
        if (t.hp <= 0 || t.hp == undefined) {
            self.dispatcher.publish("aggroClear", self);
        }
    }

    // ═══════ Phase 1 Fallback（evaluator 不存在时）═══════

    private function selectSkillFallback():Void {
        var self:MovieClip = data.self;
        var X轴距离:Number = data.absdiff_x;

        var 技能使用概率:Number = Math.max(60 / X轴距离 * self.等级, 20);
        if (self.名字 == "尾上世莉架") 技能使用概率 *= 3;
        if (self.攻击模式 === "空手") {
            技能使用概率 = Math.min(技能使用概率, 100 - (Math.sqrt(self.佣兵技能概率抑制基数) + 5) * 2);
        }

        if (_root.成功率(技能使用概率)) {
            var skillName:String = getRandomSkill();
            if (skillName != null && skillName != undefined) {
                _root.技能路由.技能标签跳转_旧(self, skillName);
            }
        } else {
            self.动作A = true;
            if (self.攻击模式 === "双枪") self.动作B = true;
        }
    }

    private function getRandomSkill():String {
        var self:MovieClip = data.self;
        var 当前时间:Number = getTimer();
        var 攻击目标:String = self.攻击目标;
        var 游戏世界 = _root.gameworld;

        if (!游戏世界[攻击目标] || !游戏世界[攻击目标]._x) return null;

        var X轴距离:Number = Math.abs(self._x - 游戏世界[攻击目标]._x);

        var 候选技能池:Array = LinearCongruentialEngine.getInstance().reservoirSampleWithFilter(
            self.已学技能表,
            1,
            function(技能:Object):Boolean {
                var 距离有效:Boolean = (X轴距离 >= 技能.距离min && X轴距离 <= 技能.距离max);
                var 冷却就绪:Boolean = (isNaN(技能.上次使用时间) ||
                    (当前时间 - 技能.上次使用时间 > 技能.冷却 * 1000));
                return 距离有效 && 冷却就绪;
            }
        );

        if (候选技能池.length > 0) {
            var 选中技能:Object = 候选技能池[0];
            self.技能等级 = 选中技能.技能等级;
            选中技能.上次使用时间 = 当前时间;
            return 选中技能.技能名;
        }
        return null;
    }
}
