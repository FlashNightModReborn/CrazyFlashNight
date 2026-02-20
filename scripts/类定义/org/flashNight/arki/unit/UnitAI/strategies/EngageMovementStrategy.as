import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.MovementResolver;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * EngageMovementStrategy -- 交战期战术走位
 *
 * 从 HeroCombatModule.engage() 提取的移动逻辑。
 * 职责：脉冲式 Z 轴蛇形走位 + X 轴风筝/撤退
 *
 * 触发条件（每 tick 评估）：
 *   远程风筝：repositionDir > 0 且距离 < 保持距离 * kiteThreshold
 *   受创闪避：retreatUrgency > evadeUrgencyThreshold 或 encirclement > evadeEncirclementThreshold
 *
 * 脉冲机制：
 *   激活 -> dur 帧移动（8~15帧） -> gap 帧间歇 -> 重新评估
 *   间歇长度随紧迫度/包围度缩短（紧急时密集走位）
 *
 * 职责边界（Input Composer 模式）：
 *   本策略只输出移动意图（通过 MovementResolver），不操控开火输入。
 *   返回模式代码，由 HeroCombatModule.engage() 统一裁决开火/走位冲突。
 *   0=无走位, 1=正常脉冲, 2=硬性闪避, 3=贴墙走位
 */
class org.flashNight.arki.unit.UnitAI.strategies.EngageMovementStrategy {

    // ── Z 轴走位脉冲状态 ──
    private var _strafeDir:Number;        // -1=上, 1=下, 0=不动
    private var _strafePulseEnd:Number;   // 当前移动脉冲结束帧
    private var _strafeNextStart:Number;  // 下次移动脉冲开始帧

    // 确定性随机源（可复现行为）
    private var _rng:LinearCongruentialEngine;

    // ═══════ 构造 ═══════

    public function EngageMovementStrategy() {
        _rng = LinearCongruentialEngine.getInstance();
        reset();
    }

    /**
     * reset -- 脱离交战时重置走位状态（chase_enter 调用）
     */
    public function reset():Void {
        _strafeDir = 0;
        _strafePulseEnd = 0;
        _strafeNextStart = 0;
    }

    /**
     * apply -- 每 engage tick 执行战术走位（纯移动输出）
     *
     * 只通过 MovementResolver 写入移动键，不操控 动作A/B。
     * 返回模式代码供 HeroCombatModule 的 Input Composer 统一裁决。
     *
     * @param data    共享 AI 数据（含 arbiter、personality、位置信息）
     * @param self    单位 MovieClip
     * @param frame   当前帧数
     * @param inSkill 是否在技能/换弹动画中（true 时跳过走位）
     * @return 走位模式: 0=无, 1=正常脉冲, 2=硬性闪避, 3=贴墙
     */
    public function apply(data:UnitAIData, self:MovieClip, frame:Number, inSkill:Boolean):Number {
        if (inSkill) {
            // 闪避/位移技能期间保持 Z 轴垂直闪避（子弹威胁时斜向机动）
            if (data.arbiter.getExecutor().isDodgeActive()
                && (frame - self._btFrame) <= 1 && self._btCount > 0) {
                if (_strafeDir == 0) _strafeDir = _pickStrafeDir(data);
                // 通过统一工具输出（自动处理边界贴墙重定向）
                if (_strafeDir != 0) {
                    MovementResolver.applyBoundaryAwareMovement(data, self, 0, _strafeDir);
                }
            }
            return 0;
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
        var evadeUrg:Number = data.personality.evadeUrgencyThreshold;
        if (isNaN(evadeUrg)) evadeUrg = 0.5;
        var evadeEnc:Number = data.personality.evadeEncirclementThreshold;
        if (isNaN(evadeEnc)) evadeEnc = 0.3;
        var wantsEvade:Boolean = (urgency > evadeUrg) || (enc > evadeEnc);

        // 仅在远程风筝 / 受创 / 被围时启动走位脉冲
        if (!wantsKite && !wantsEvade) return 0;

        var inPulse:Boolean = frame < _strafePulseEnd;
        if (!inPulse && frame >= _strafeNextStart) {
            _strafeDir = _pickStrafeDir(data);
            var dur:Number = 8 + _rng.randomInteger(0, 7); // 8~15帧 ≈ 0.3~0.6s
            _strafePulseEnd = frame + dur;
            var gap:Number = 12 - Math.floor((enc + urgency) * 5);
            // T2-B：弹道威胁时缩短间歇（更密集的走位脉冲）
            var btAge2:Number = frame - self._btFrame;
            if (btAge2 >= 0 && btAge2 <= 1 && self._btCount > 0) {
                var btETA2:Number = self._btMinETA - btAge2;
                if (btETA2 < 15) gap -= 3;
            }
            if (gap < 3) gap = 3;
            _strafeNextStart = _strafePulseEnd + gap + _rng.randomInteger(0, gap - 1);
            inPulse = true;
        }

        if (!inPulse) return 0;

        // ── 收集移动意图 + 统一边界感知输出 ──
        var moveZ:Number = _strafeDir; // -1=上, 1=下, 0=不动
        var moveX:Number = 0;

        // 1vN：反包夹（Anti-Pincer / Directional Dominance）
        // 目标：在被围/受创走位触发时，尽量向"敌人更少的一侧"突围，
        // 让敌人集中到同一侧（横版格斗黄金法则：不要让敌人出现在身后）。
        var safeX:Number = 0;
        if (data.arbiter != null && enc > 0.25) {
            var lCnt:Number = data.arbiter.getLeftEnemyCount();
            var rCnt:Number = data.arbiter.getRightEnemyCount();
            // 使用 1 的滞后阈值抑制左右抖动
            if (lCnt > rCnt + 1) safeX = 1;
            else if (rCnt > lCnt + 1) safeX = -1;
            // 边界门控：突围方向必须有空间
            if (safeX < 0 && data.bndLeftDist < 60) safeX = (data.bndRightDist > 60) ? 1 : 0;
            else if (safeX > 0 && data.bndRightDist < 60) safeX = (data.bndLeftDist > 60) ? -1 : 0;
        }

        // 贴边时向场内回拉，防止"卡边缘只上下移动"
        // 说明：kiteDir 被墙挡住时继续 Z 轴蛇形没有意义，应该先脱离边缘再重新风筝
        var edgeMargin:Number = 80;
        var edgeEscapeX:Number = 0;
        if (data.bndLeftDist < edgeMargin) edgeEscapeX = 1;
        else if (data.bndRightDist < edgeMargin) edgeEscapeX = -1;
        if (wantsKite || (urgency > 0.7 && repoDir <= 0)) {
            var kiteDir:Number = (data.diff_x > 0) ? -1 : 1; // 远离目标
            // 风筝方向贴墙检查：退路被堵 → 放弃风筝，接受近身战斗
            var kiteWall:Boolean = (kiteDir < 0 && data.bndLeftDist < edgeMargin)
                                || (kiteDir > 0 && data.bndRightDist < edgeMargin);
            if (!kiteWall) {
                moveX = kiteDir;
            } else if (edgeEscapeX != 0) {
                // 退路被堵：优先向场内挪出空间（等价于 -kiteDir）
                moveX = edgeEscapeX;
            }
        } else if (wantsEvade && edgeEscapeX != 0) {
            // 被围/受创且贴边：优先脱离边缘，否则容易被压墙集火
            moveX = edgeEscapeX;
        }

        // 被围：优先突围到安全侧（若当前未产生 X 意图或包围度很高）
        if (wantsEvade && safeX != 0) {
            if (moveX == 0 || (moveX != safeX && enc > 0.6)) {
                moveX = safeX;
            }
        }

        // 统一处理边界碰撞：沿墙滑行 / 角落突围 / 正常输出
        var bndResult:Number = MovementResolver.applyBoundaryAwareMovement(data, self, moveX, moveZ);
        // SLIDE(1) 和 CORNER(2) 都视为贴墙
        var wallBlocked:Boolean = (bndResult >= 1);

        // ── 返回模式代码（不操控 动作A/B，交由 Input Composer 裁决）──
        var moving:Boolean = (self.左行 || self.右行 || self.上行 || self.下行);
        if (!moving) return 0;

        // 贴墙：虽有移动意图但受限于边界，建议保持开火
        if (wallBlocked) return 3;

        // 硬性闪避检测：子弹逼近/高紧迫/重包围 → 建议纯走位
        if (wantsEvade) {
            var btAge:Number = frame - self._btFrame;
            var bulletSoon:Boolean = (btAge >= 0 && btAge <= 1
                && self._btCount > 0 && self._btMinETA < 12);
            if (bulletSoon || urgency > 0.75 || enc > 0.55) return 2;
        }

        // 正常走位脉冲
        return 1;
    }

    // ═══════ 走位方向选择 ═══════

    /**
     * _pickStrafeDir -- 选择走位脉冲的 Z 轴方向
     *
     * 交替上/下方向，形成自然的 Z 轴蛇形走位。
     * 边界检查：贴边时强制反向；双边贴边时放弃走位。
     */
    private function _pickStrafeDir(data:UnitAIData):Number {
        var s:MovieClip = data.self;
        var zPick:Number = MovementResolver.pickZDirBySpaceEx(data, s, 80);
        if (zPick == 0) return 0;

        var dir:Number = (zPick < 0) ? -1 : 1;
        var forced:Boolean = (Math.abs(zPick) == 2);
        if (forced) return dir;

        // 交替方向（首次选择偏好方向，后续交替）
        if (_strafeDir == 0) return dir;
        return -_strafeDir;
    }
}
