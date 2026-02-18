import org.flashNight.arki.unit.UnitAI.UnitAIData;

/**
 * EngageMovementStrategy — 交战期战术走位
 *
 * 从 HeroCombatModule.engage() 提取的移动逻辑。
 * 职责：脉冲式 Z 轴蛇形走位 + X 轴风筝/撤退
 *
 * 触发条件（每 tick 评估）：
 *   远程风筝：repositionDir > 0 且距离 < 保持距离 × kiteThreshold
 *   受创闪避：retreatUrgency > 0.5 或 encirclement > 0.3
 *
 * 脉冲机制：
 *   激活 → dur 帧移动（8~15帧） → gap 帧间歇 → 重新评估
 *   间歇长度随紧迫度/包围度缩短（紧急时密集走位）
 *
 * 攻击抑制：
 *   走位脉冲期间清除攻击输入以允许移动执行（移动射击除外）
 */
class org.flashNight.arki.unit.UnitAI.EngageMovementStrategy {

    // ── Z 轴走位脉冲状态 ──
    private var _strafeDir:Number;        // -1=上, 1=下, 0=不动
    private var _strafePulseEnd:Number;   // 当前移动脉冲结束帧
    private var _strafeNextStart:Number;  // 下次移动脉冲开始帧

    // ═══════ 构造 ═══════

    public function EngageMovementStrategy() {
        reset();
    }

    /**
     * reset — 脱离交战时重置走位状态（chase_enter 调用）
     */
    public function reset():Void {
        _strafeDir = 0;
        _strafePulseEnd = 0;
        _strafeNextStart = 0;
    }

    /**
     * apply — 每 engage tick 执行战术走位
     *
     * @param data    共享 AI 数据（含 arbiter、personality、位置信息）
     * @param self    单位 MovieClip
     * @param frame   当前帧数
     * @param inSkill 是否在技能/换弹动画中（true 时跳过走位）
     */
    public function apply(data:UnitAIData, self:MovieClip, frame:Number, inSkill:Boolean):Void {
        if (inSkill) {
            // 闪避/位移技能期间保持 Z 轴垂直闪避（子弹威胁时斜向机动）
            if (data.arbiter.getExecutor().isDodgeActive()
                && (frame - self._btFrame) <= 1 && self._btCount > 0) {
                if (_strafeDir == 0) _strafeDir = _pickStrafeDir(data);
                // 通过统一工具输出（自动处理边界贴墙重定向）
                if (_strafeDir != 0) {
                    UnitAIData.applyBoundaryAwareMovement(data, self, 0, _strafeDir);
                }
            }
            return;
        }

        var urgency:Number = data.arbiter.getRetreatUrgency();
        var repoDir:Number = data.arbiter.getRepositionDir();
        var enc:Number = data.arbiter.getEncirclement();

        // 走位触发条件
        var kiteT:Number = data.personality.kiteThreshold;
        if (isNaN(kiteT)) kiteT = 0.7;
        if (urgency > 0) {
            kiteT = kiteT + urgency * (1.0 - kiteT);
        }
        var wantsKite:Boolean = (repoDir > 0 && data.absdiff_x < data.xdistance * kiteT);
        var wantsEvade:Boolean = (urgency > 0.5) || (enc > 0.3);

        // 仅在远程风筝 / 受创 / 被围时启动走位脉冲
        if (!wantsKite && !wantsEvade) return;

        var inPulse:Boolean = frame < _strafePulseEnd;
        if (!inPulse && frame >= _strafeNextStart) {
            _strafeDir = _pickStrafeDir(data);
            var dur:Number = 8 + random(8); // 8~15帧 ≈ 0.3~0.6s
            _strafePulseEnd = frame + dur;
            var gap:Number = 12 - Math.floor((enc + urgency) * 5);
            // T2-B：弹道威胁时缩短间歇（更密集的走位脉冲）
            var btAge2:Number = frame - self._btFrame;
            if (btAge2 >= 0 && btAge2 <= 1 && self._btCount > 0) {
                var btETA2:Number = self._btMinETA - btAge2;
                if (btETA2 < 15) gap -= 3;
            }
            if (gap < 3) gap = 3;
            _strafeNextStart = _strafePulseEnd + gap + random(gap);
            inPulse = true;
        }

        if (!inPulse) return;

        // ── 收集移动意图 + 统一边界感知输出 ──
        var moveZ:Number = _strafeDir; // -1=上, 1=下, 0=不动
        var moveX:Number = 0;
        if (wantsKite || (urgency > 0.7 && repoDir <= 0)) {
            var kiteDir:Number = (data.diff_x > 0) ? -1 : 1; // 远离目标
            // 风筝方向贴墙检查：退路被堵 → 放弃风筝，接受近身战斗
            var kiteWall:Boolean = (kiteDir < 0 && data.bndLeftDist < 80)
                                || (kiteDir > 0 && data.bndRightDist < 80);
            if (!kiteWall) {
                moveX = kiteDir;
            }
        }

        // 统一处理边界碰撞：沿墙滑行 / 角落突围 / 正常输出
        var bndResult:Number = UnitAIData.applyBoundaryAwareMovement(data, self, moveX, moveZ);
        // SLIDE(1) 和 CORNER(2) 都视为贴墙 — 保持攻击输出，不抑制
        var wallBlocked:Boolean = (bndResult >= 1);

        // 抑制攻击以允许移动执行（仅正常风筝时）
        // wallBlocked(贴墙) → 保持攻击输出（贴墙时应该战斗，不应发呆）
        var moving:Boolean = (self.左行 || self.右行 || self.上行 || self.下行);
        if (moving && self.移动射击 != true && !wallBlocked) {
            self.动作A = false;
            self.动作B = false;
            if (!self.射击中) {
                self.状态改变(self.攻击模式 + "跑");
            }
        }
    }

    // ═══════ 走位方向选择 ═══════

    /**
     * _pickStrafeDir — 选择走位脉冲的 Z 轴方向
     *
     * 交替上/下方向，形成自然的 Z 轴蛇形走位。
     * 边界检查：贴边时强制反向；双边贴边时放弃走位。
     */
    private function _pickStrafeDir(data:UnitAIData):Number {
        var margin:Number = 80;
        // 复用 updateSelf 中已计算的边界距离（消除重复计算）
        var upSpace:Number = data.bndUpDist;
        var downSpace:Number = data.bndDownDist;

        // 边界约束
        if (upSpace < margin && downSpace < margin) return 0;
        if (upSpace < margin) return 1;  // 靠近上边界，只能向下
        if (downSpace < margin) return -1; // 靠近下边界，只能向上

        // T2-B：弹道方向感知 — 有子弹威胁时选择空间更大的一侧
        var s:MovieClip = data.self;
        var btAge:Number = _root.帧计时器.当前帧数 - s._btFrame;
        if (btAge >= 0 && btAge <= 1 && s._btCount > 0) {
            if (upSpace > downSpace * 1.3) return -1;  // 上方空间明显更大
            if (downSpace > upSpace * 1.3) return 1;   // 下方空间明显更大
        }

        // 交替方向（首次选择空间较大的一侧）
        if (_strafeDir == 0) {
            return (upSpace >= downSpace) ? -1 : 1;
        }
        return -_strafeDir;
    }
}
