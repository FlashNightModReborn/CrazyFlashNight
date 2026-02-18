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
                if (_strafeDir < 0) { self.上行 = true; }
                else if (_strafeDir > 0) { self.下行 = true; }
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
            if (gap < 3) gap = 3;
            _strafeNextStart = _strafePulseEnd + gap + random(gap);
            inPulse = true;
        }

        if (!inPulse) return;

        // Z 轴走位
        if (_strafeDir < 0) {
            self.上行 = true;
        } else if (_strafeDir > 0) {
            self.下行 = true;
        }

        // X 轴后退（远程风筝 / 近战高紧迫脱战）
        var wallBlocked:Boolean = false;
        if (wantsKite || (urgency > 0.7 && repoDir <= 0)) {
            var margin:Number = 80;
            var bMinX:Number = (_root.Xmin != undefined) ? _root.Xmin : 0;
            var bMaxX:Number = (_root.Xmax != undefined) ? _root.Xmax : Stage.width;
            var retreatLeft:Boolean = data.diff_x > 0;
            wallBlocked = (retreatLeft && (data.x - bMinX < margin))
                       || (!retreatLeft && (bMaxX - data.x < margin));
            if (!wallBlocked) {
                if (retreatLeft) { self.左行 = true; } else { self.右行 = true; }
            } else {
                // 退无可退 → 斜向穿越敌人突围（Z偏移 + 反向冲刺）
                if (retreatLeft) { self.右行 = true; } else { self.左行 = true; }
            }
        }

        // 抑制攻击以允许移动执行（仅在真实后撤时生效）
        // 修复1：dir=0（上下均贴边）时 inPulse=true 但无移动输入 → 不应抑制攻击
        // 修复2：wallBlocked 突围时不抑制攻击 — 正面冲锋应保持输出，否则呈现发呆
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
}
