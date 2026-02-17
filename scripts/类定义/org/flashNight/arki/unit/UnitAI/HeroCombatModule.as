import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * 佣兵战斗模块 — 作为子状态机嵌入根机 HeroCombatBehavior
 *
 * 内部状态：Chasing (default) / Engaging
 * 退出条件：由根机 Gate 检测目标死亡/消失
 *
 * Phase 2 注入点：selectSkill() 可替换为 Utility 评分选择
 */
class org.flashNight.arki.unit.UnitAI.HeroCombatModule extends FSM_StateMachine {

    private var _lastTargetCheckFrame:Number = -999;

    // Z 轴走位脉冲状态
    private var _strafeDir:Number = 0;        // -1=上, 1=下, 0=不动
    private var _strafePulseEnd:Number = 0;   // 当前移动脉冲结束帧
    private var _strafeNextStart:Number = 0;  // 下次移动脉冲开始帧

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
        _strafePulseEnd = 0; // 脱离交战，重置走位状态
        _strafeNextStart = 0;
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

        // ── 周期性目标评估（近身感知 + 转火）──
        if (_checkTargetSwitch()) {
            data.updateTarget();
        }

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

        // Z轴计算（先算距离，供跑步判定使用）
        var targetZ:Number = isNaN(t.Z轴坐标) ? t._y : t.Z轴坐标;
        var zDiff:Number = self._y - targetZ;
        var absZDiff:Number = zDiff < 0 ? -zDiff : zDiff;

        // 跑步切换：Z 轴基本对齐后再切跑，避免跑步高速导致 Z 轴抖动
        // absZDiff > 20 时保持走路（低速精确对齐），对齐后才允许跑步追击
        if (!self.射击中 && (self.man == null || !self.man.换弹标签) && random(3) == 0) {
            if (absZDiff <= 20) {
                self.状态改变(self.攻击模式 + "跑");
            }
        }

        // Z轴移动（5px 死区避免来回抖动）
        if (absZDiff > 5) {
            if (zDiff > 0) { self.上行 = true; } else { self.下行 = true; }
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
        self.上行 = false;
        self.下行 = false;

        // 目标失效守卫
        var t:MovieClip = data.target;
        if (t == null || !t._x) return;

        data.updateSelf();
        data.updateTarget();

        // ── 周期性目标评估（近身感知 + 转火）──
        if (_checkTargetSwitch()) {
            data.updateTarget();
            t = data.target;
        }

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
            var frame:Number = _root.帧计时器.当前帧数;

            // 始终 engage context — 走位与进攻并行，不抑制 offense
            data.arbiter.tick(data, "engage");

            var bodyType:String = data.arbiter.getExecutor().getCurrentBodyType();
            var inSkill:Boolean = (bodyType == "skill" || bodyType == "preBuff"
                                || self.状态 == "技能" || self.状态 == "战技");

            // ── 战术走位（技能期不输出移动）──
            // 只在有战术理由时走位，正常近战不干扰攻击输出
            if (!inSkill) {
                var urgency:Number = data.arbiter.getRetreatUrgency();
                var repoDir:Number = data.arbiter.getRepositionDir();
                var enc:Number = data.arbiter.getEncirclement();

                // 走位触发条件
                var kiteT:Number = 0.7;
                if (data.personality != null && !isNaN(data.personality.kiteThreshold)) {
                    kiteT = data.personality.kiteThreshold;
                }
                if (urgency > 0) {
                    kiteT = kiteT + urgency * (1.0 - kiteT);
                }
                var wantsKite:Boolean = (repoDir > 0 && data.absdiff_x < data.xdistance * kiteT);
                var wantsEvade:Boolean = (urgency > 0.5) || (enc > 0.3);

                // 仅在远程风筝 / 受创 / 被围时启动走位脉冲
                if (wantsKite || wantsEvade) {
                    var inPulse:Boolean = frame < _strafePulseEnd;
                    if (!inPulse && frame >= _strafeNextStart) {
                        _strafeDir = _pickStrafeDir();
                        var dur:Number = 8 + random(8); // 8~15帧 ≈ 0.3~0.6s
                        _strafePulseEnd = frame + dur;
                        var gap:Number = 12 - Math.floor((enc + urgency) * 5);
                        if (gap < 3) gap = 3;
                        _strafeNextStart = _strafePulseEnd + gap + random(gap);
                        inPulse = true;
                    }

                    if (inPulse) {
                        // Z 轴走位
                        if (_strafeDir < 0) {
                            self.上行 = true;
                        } else if (_strafeDir > 0) {
                            self.下行 = true;
                        }

                        // X 轴后退（远程风筝 / 近战高紧迫脱战）
                        if (wantsKite || (urgency > 0.7 && repoDir <= 0)) {
                            var margin:Number = 80;
                            var bMinX:Number = (_root.Xmin != undefined) ? _root.Xmin : 0;
                            var bMaxX:Number = (_root.Xmax != undefined) ? _root.Xmax : Stage.width;
                            var retreatLeft:Boolean = data.diff_x > 0;
                            var wallBlocked:Boolean = (retreatLeft && (data.x - bMinX < margin))
                                                   || (!retreatLeft && (bMaxX - data.x < margin));
                            if (!wallBlocked) {
                                if (retreatLeft) { self.左行 = true; } else { self.右行 = true; }
                            } else {
                                // 退无可退 → 斜向穿越敌人突围（Z偏移 + 反向冲刺）
                                if (retreatLeft) { self.右行 = true; } else { self.左行 = true; }
                            }
                        }

                        // 抑制攻击以允许移动执行（移动射击保持输出）
                        if (self.移动射击 != true) {
                            self.动作A = false;
                            self.动作B = false;
                            if (!self.射击中) {
                                self.状态改变(self.攻击模式 + "跑");
                            }
                        }
                    }
                }
            }
        } else {
            selectSkillFallback();
        }

        // 防呆：管线边界情况兜底（所有候选被过滤 / commitment 间隙 / 状态切换空隙）
        if (!self.动作A && !self.动作B && !self.左行 && !self.右行 && !self.上行 && !self.下行) {
            var st:String = self.状态;
            if (st != "技能" && st != "战技" && !self.射击中) {
                self.动作A = true;
                if (self.攻击模式 === "双枪") self.动作B = true;
            }
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

    // ═══════ 走位方向选择 ═══════

    /**
     * _pickStrafeDir — 选择走位脉冲的 Z 轴方向
     *
     * 交替上/下方向，形成自然的 Z 轴蛇形走位。
     * 边界检查：贴边时强制反向；双边贴边时放弃走位。
     */
    private function _pickStrafeDir():Number {
        var margin:Number = 80;
        var bMinY:Number = (_root.Ymin != undefined) ? _root.Ymin : 0;
        var bMaxY:Number = (_root.Ymax != undefined) ? _root.Ymax : Stage.height;
        var upSpace:Number = data.y - bMinY;
        var downSpace:Number = bMaxY - data.y;

        // 边界约束
        if (upSpace < margin && downSpace < margin) return 0;
        if (upSpace < margin) return 1;  // 靠近上边界，只能向下
        if (downSpace < margin) return -1; // 靠近下边界，只能向上

        // 交替方向（首次选择空间较大的一侧）
        if (_strafeDir == 0) {
            return (upSpace >= downSpace) ? -1 : 1;
        }
        return -_strafeDir;
    }

    // ═══════ 目标切换（近距离感知）═══════

    /**
     * _checkTargetSwitch — 周期性检测更近的敌人
     *
     * 使用 TargetCacheManager.findNearestEnemy 感知被近身。
     * 距离比率迟滞：新目标必须显著更近才切换（避免频繁转火）。
     * 检测频率 / 迟滞阈值由人格参数驱动。
     *
     * @return Boolean 是否发生了目标切换
     */
    private function _checkTargetSwitch():Boolean {
        var self:MovieClip = data.self;
        var frame:Number = _root.帧计时器.当前帧数;

        // 人格参数驱动检测频率
        var p:Object = data.personality;
        var interval:Number = 12;
        if (p != null && !isNaN(p.targetSwitchInterval)) {
            interval = p.targetSwitchInterval;
        }

        if (frame - _lastTargetCheckFrame < interval) return false;
        _lastTargetCheckFrame = frame;

        // 查找最近敌人（X 轴排序）
        var nearest = TargetCacheManager.findNearestEnemy(self, 1);
        if (nearest == null || nearest.hp <= 0) return false;

        // Z 轴过滤：Z 距离过远说明在不同战团，不切换
        var nearestZ:Number = nearest.Z轴坐标;
        if (isNaN(nearestZ)) nearestZ = nearest._y;
        var selfZ:Number = self.Z轴坐标;
        if (isNaN(selfZ)) selfZ = self._y;
        if (Math.abs(selfZ - nearestZ) > 60) return false;

        var t:MovieClip = data.target;

        // 无当前目标 → 直接获取
        if (t == null || t.hp <= 0) {
            _switchTarget(nearest);
            return true;
        }

        // 已是当前目标 → 跳过
        if (nearest == t) return false;

        // 距离比较 + 迟滞（X 轴）
        var currentDist:Number = Math.abs(self._x - t._x);
        var nearestDist:Number = Math.abs(self._x - nearest._x);

        var ratio:Number = 0.5;
        if (p != null && !isNaN(p.targetSwitchRatio)) {
            ratio = p.targetSwitchRatio;
        }

        if (nearestDist < currentDist * ratio) {
            _switchTarget(nearest);
            return true;
        }

        return false;
    }

    private function _switchTarget(newTarget):Void {
        var self:MovieClip = data.self;
        data.target = newTarget;
        self.攻击目标 = newTarget._name;
        self.dispatcher.publish("aggroSet", self, newTarget);
    }
}
