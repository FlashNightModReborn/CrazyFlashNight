import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.MovementResolver;

/**
 * RetreatMovementStrategy — 撤退期移动 + 掩护射击策略
 *
 * 从 HeroCombatBehavior 提取的撤退移动逻辑。
 * 与 EngageMovementStrategy 对称，封装撤退状态的全部移动决策。
 *
 * 四阶段管线（每 tick 由 apply() 驱动）：
 *   1. _trySafeReload()        — 安全距离换弹（到达安全距离后主动停下换弹）
 *   2. _computeRetreatMove()   — 收集 X/Z 轴移动意图
 *   3. _evaluateCoveringFire() — 五重门控掩护射击判定
 *   4. _applyRetreatOutput()   — 统一输出（开火帧 vs 撤退帧）
 *
 * 面朝方向策略：
 *   远程姿态(repositionDir > 0)：面朝目标（边退边射/边退边buff）
 *   近战姿态(repositionDir <= 0)：背对目标（全速奔跑撤离）
 */
class org.flashNight.arki.unit.UnitAI.strategies.RetreatMovementStrategy {

    // ── 撤退状态 ──
    private var _retreatStartFrame:Number;
    private var _retreatFireCounter:Number;

    // ── per-tick 暂存（_computeRetreatMove 写入，后续阶段读取）──
    private var _retMoveX:Number;
    private var _retMoveZ:Number;
    private var _retZSep:Number;

    // ═══════ 构造 ═══════

    public function RetreatMovementStrategy() {
        _retreatStartFrame = -1;
        _retreatFireCounter = 0;
        _retMoveX = 0;
        _retMoveZ = 0;
        _retZSep = 0;
    }

    // ═══════ 生命周期 ═══════

    /**
     * enter — 进入撤退状态时调用
     */
    public function enter(frame:Number):Void {
        _retreatStartFrame = frame;
        _retreatFireCounter = 0;
    }

    /**
     * getStartFrame — 撤退开始帧（Gate 超时判定用）
     */
    public function getStartFrame():Number {
        return _retreatStartFrame;
    }

    /**
     * apply — 撤退状态每 tick 执行（arbiter.tick 之后调用）
     *
     * 前置条件：调用方已完成 dead/pause 检查、updateSelf/Target、arbiter.tick、技能保护检查。
     */
    public function apply(data:UnitAIData, self:MovieClip):Void {
        // 阶段 1: 安全距离换弹（可能 early return）
        if (_trySafeReload(data, self)) return;

        // 阶段 2: 收集移动意图
        _computeRetreatMove(data, self);

        // 阶段 3: 掩护射击判定
        var wantFire:Boolean = _evaluateCoveringFire(data, self);

        // 阶段 4: 统一输出
        _applyRetreatOutput(data, self, wantFire);
    }

    // ═══════ 阶段 1: 安全距离换弹 ═══════

    /**
     * _trySafeReload — 撤退到安全距离后主动停下来换弹
     *
     * 条件：X距离充足(>xrange*2且>400) + 紧急度低(<0.3) + 非射击中
     * 支持切换到弹药不足的其他远程武器进行换弹。
     *
     * @return true 表示已处理（换弹中/已触发换弹），调用方应 return
     */
    private function _trySafeReload(data:UnitAIData, self:MovieClip):Boolean {
        var distMult:Number = data.personality.safeReloadDistMult;
        if (isNaN(distMult)) distMult = 2.0;
        var safeReloadDist:Number = data.xrange * distMult;
        if (safeReloadDist < 400) safeReloadDist = 400;

        var urgMax:Number = data.personality.safeReloadUrgMax;
        if (isNaN(urgMax)) urgMax = 0.3;

        if (isNaN(data.absdiff_x) || data.absdiff_x <= safeReloadDist
            || data.arbiter.getRetreatUrgency() >= urgMax
            || self.射击中) {
            return false;
        }

        // 已在换弹 → 原地等待完成
        if (self.man.换弹标签) {
            return true;
        }

        var executor:Object = data.arbiter.getExecutor();
        var frame:Number = _root.帧计时器.当前帧数;
        var commitFrames:Number = data.personality.reloadCommitFrames;
        if (isNaN(commitFrames) || commitFrames <= 0) commitFrames = 30;

        // 当前武器弹药不足 → 停下换弹
        var curAmmoRR:Number = data.arbiter.getAmmoRatio(self);
        if (!(curAmmoRR >= 0.5)) { // NaN-safe
            self.状态改变(self.攻击模式 + "停");
            if (self.man.开始换弹) {
                self.man.开始换弹();
            } else {
                self.man.换弹标签 = true;
                self.man.gotoAndPlay("换弹匣");
            }
            executor.commitBody("reload", 2, commitFrames, frame, 0);
            if (_root.AI调试模式 == true) {
                _root.服务器.发布服务器消息("[RET-RELOAD] " + self.名字
                    + " 安全距离换弹 cur=" + self.攻击模式
                    + " ammo=" + Math.round((curAmmoRR || 0) * 100) + "%");
            }
            return true;
        }

        // 当前武器满弹 → 检查其他远程武器是否需要换弹
        var reloadModes:Array = ["长枪", "双枪", "手枪"];
        for (var rmi:Number = 0; rmi < reloadModes.length; rmi++) {
            var rmMode:String = reloadModes[rmi];
            if (rmMode == self.攻击模式) continue;
            if (rmMode == "长枪" && !self.长枪) continue;
            if ((rmMode == "手枪" || rmMode == "双枪") && !self.手枪) continue;
            var rmAmmo:Number = data.arbiter.getAmmoRatioForMode(self, rmMode);
            if (!isNaN(rmAmmo) && rmAmmo < 0.5) {
                var rmSwitchArg:String = (rmMode == "双枪") ? "手枪" : rmMode;
                self.攻击模式切换(rmSwitchArg);
                self.状态改变(self.攻击模式 + "停");
                if (self.man.开始换弹) {
                    self.man.开始换弹();
                } else {
                    self.man.换弹标签 = true;
                    self.man.gotoAndPlay("换弹匣");
                }
                executor.commitBody("reload", 2, commitFrames, frame, 0);
                if (_root.AI调试模式 == true) {
                    _root.服务器.发布服务器消息("[RET-RELOAD] " + self.名字
                        + " 切换到 " + rmMode + " 换弹 ammo="
                        + Math.round(rmAmmo * 100) + "%");
                }
                return true;
            }
        }

        return false;
    }

    // ═══════ 阶段 2: 移动意图收集 ═══════

    /**
     * _computeRetreatMove — 计算 X/Z 轴撤退移动意图
     *
     * X轴：远离目标方向移动（贴墙/角落/障碍统一交给 MovementResolver 处理）
     * Z轴：优先拉开垂直距离(zSep < Z_SAFE)，足够后轻微蛇形闪避(30帧周期)
     *
     * 结果写入 _retMoveX, _retMoveZ, _retZSep
     */
    private function _computeRetreatMove(data:UnitAIData, self:MovieClip):Void {
        // X轴
        _retMoveX = 0;
        if (data.target != null && data.target._x != undefined && data.target.hp > 0) {
            // 注意：撤退方向在策略层不做“贴墙归零”门控。
            // 贴边/障碍处理应统一交给 MovementResolver.applyBoundaryAwareMovement：
            //   - retWall 归零会导致 wantX=0，从而无法触发沿墙滑行/角落突围/edgeEscape 脱离逻辑
            //   - 实战表现为：被压到地图边缘后只上下移动，无法正确反向撤离
            _retMoveX = (data.diff_x > 0) ? -1 : 1; // 远离目标
        } else {
            if (data.diff_x != null && !isNaN(data.diff_x) && data.diff_x != 0) {
                _retMoveX = (data.diff_x > 0) ? -1 : 1;
            }
        }

        // Z轴
        var frame:Number = _root.帧计时器.当前帧数;
        _retMoveZ = 0;
        _retZSep = data.absdiff_z;
        if (isNaN(_retZSep)) _retZSep = 0;
        var Z_SAFE:Number = 120;

        if (_retZSep < Z_SAFE) {
            if (data.diff_z != null && data.diff_z != 0) {
                var escapeZ:Number = (data.diff_z > 0) ? -1 : 1;
                if (escapeZ < 0 && data.bndUpDist < 50) {
                    escapeZ = 1;
                } else if (escapeZ > 0 && data.bndDownDist < 50) {
                    escapeZ = -1;
                }
                _retMoveZ = escapeZ;
            } else {
                _retMoveZ = (data.bndUpDist > data.bndDownDist) ? -1 : 1;
            }
        } else {
            var zWave:Number = Math.floor(frame / 30) % 2;
            if (zWave == 0 && data.bndUpDist > 60) {
                _retMoveZ = -1;
            } else if (zWave == 1 && data.bndDownDist > 60) {
                _retMoveZ = 1;
            }
        }
    }

    // ═══════ 阶段 3: 掩护射击判定 ═══════

    /**
     * _evaluateCoveringFire — 远程姿态下的火力-机动交替判定
     *
     * 五重门控：
     *   1. 姿态门控：远程(repoDir>0) + 非射击中 + 非动画锁
     *   2. 弹药门控：ammoR > 0.3
     *   3. Z轴对齐门控：_retZSep <= zrange*2
     *   4. X轴安全门控：absdiff_x <= xrange*1.5
     *   5. 紧急度门控：urgency < 0.8 且无迫近弹道
     *
     * @return true 表示本帧应开火
     */
    private function _evaluateCoveringFire(data:UnitAIData, self:MovieClip):Boolean {
        var repoDir:Number = data.arbiter.getRepositionDir();
        var executor:Object = data.arbiter.getExecutor();
        var frame:Number = _root.帧计时器.当前帧数;

        if (repoDir <= 0 || self.射击中 || executor.isAnimLocked()) {
            return false;
        }

        // 弹药门控
        var ammoR:Number = data.arbiter.getAmmoRatio(self);
        var ammoOK:Boolean = !(ammoR <= 0.3); // NaN → true

        // Z轴对齐门控
        var zRange:Number = data.zrange;
        if (isNaN(zRange) || zRange < 10) zRange = 25;
        var zAligned:Boolean = (isNaN(_retZSep) || _retZSep <= zRange * 2);

        // X轴安全门控
        var xSafe:Boolean = !(data.absdiff_x > data.xrange * 1.5);

        // 紧急度门控
        var urgency:Number = data.arbiter.getRetreatUrgency();
        var btAge:Number = frame - self._btFrame;
        var imminent:Boolean = (btAge >= 0 && btAge <= 1
            && self._btCount > 0 && (self._btMinETA - btAge) < 8);
        var canPause:Boolean = (urgency < 0.8 && !imminent);

        var wantFire:Boolean = false;
        if (ammoOK && zAligned && xSafe && canPause) {
            var fireGap:Number = data.personality.coveringFireGap;
            if (isNaN(fireGap) || fireGap < 2) fireGap = 4;
            _retreatFireCounter++;
            if (_retreatFireCounter >= fireGap) {
                wantFire = true;
                _retreatFireCounter = 0;
            }
        }

        // 调试日志
        if (_root.AI调试模式 == true && (frame & 31) == 0) {
            _root.服务器.发布服务器消息("[RET-FIRE] " + self.名字
                + " ammo=" + Math.round((ammoR || 0) * 100) + "%"
                + " z=" + Math.round(_retZSep) + "/" + Math.round(zRange * 2)
                + " x=" + Math.round(data.absdiff_x) + "/" + Math.round(data.xrange * 1.5)
                + " urg=" + Math.round(urgency * 100)
                + " anim=" + executor.isAnimLocked()
                + " fire=" + wantFire);
        }

        return wantFire;
    }

    // ═══════ 阶段 4: 统一输出 ═══════

    /**
     * _applyRetreatOutput — 根据开火判定输出移动/射击指令
     *
     * 开火帧：放弃X轴移动，仅Z轴闪避 + 面朝目标射击
     * 非开火帧：正常撤退移动
     */
    private function _applyRetreatOutput(data:UnitAIData, self:MovieClip, wantFire:Boolean):Void {
        if (wantFire) {
            MovementResolver.applyBoundaryAwareMovement(data, self, 0, _retMoveZ);
            if (data.diff_x > 0) self.方向改变("右");
            else if (data.diff_x < 0) self.方向改变("左");
            self.动作A = true;
            if (self.攻击模式 === "双枪") self.动作B = true;
        } else {
            MovementResolver.applyBoundaryAwareMovement(data, self, _retMoveX, _retMoveZ);
        }

        // 切换跑步（非射击期间才切，避免打断射击动作）
        if (!self.射击中 && !self.动作A && !self.man.换弹标签) {
            self.状态改变(self.攻击模式 + "跑");
        }
    }
}
