import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.component.StatHandler.ImpactHandler {
    // *******************************
    // 常量配置：便于外部调整相关参数
    // *******************************
    public static var IMPACT_COEFFICIENT:Number = 50;      // 冲击系数，控制冲击力的基础倍数
    public static var IMPACT_DECAY_TIME:Number = 5;        // 冲击残余时间（秒）
    public static var IMPACT_STAGGER_COEFFICIENT:Number = 2; // 控制硬直与冲击力衰减关联的系数
    public static var IMPACT_DECAY_FRAME:Number = IMPACT_DECAY_TIME * 30; // 衰减起始帧数（假设30FPS）
    public static var IMPACT_DECAY_DFRAME:Number = IMPACT_DECAY_FRAME * 2; // 衰减最大帧数（两倍衰减时间）

    /**
     * 韧性上限的唯一公式入口。
     * 防御按伤害链实际使用的完整数值参与计算，保证战斗、头顶条与个人信息面板一致。
     */
    public static function calculateImpactCap(target:Object):Number {
        if (!target) return 0;

        var toughness:Number = Number(target.韧性系数);
        var hp:Number = Number(target.hp);
        var defense:Number = Number(target.防御力);
        if (!isFinite(toughness) || toughness < 0) toughness = 0;
        if (!isFinite(hp) || hp <= 0) return 0;
        // DamageCalculator 在实际承伤前会把非正防御归一到 1；这里沿用同一边界，
        // 避免个人信息/头顶条在异常配置下先显示另一套韧性上限。
        if (!(defense > 0) || !isFinite(defense)) defense = 1;

        var damageRatio:Number = DamageResistanceHandler.defenseDamageRatio(defense);
        if (!(damageRatio > 0) || !isFinite(damageRatio)) return 0;

        var cap:Number = toughness * hp / damageRatio;
        return (cap > 0 && isFinite(cap)) ? cap : 0;
    }

    private static function calculateStaggerFromCap(target:Object, cap:Number):Number {
        if (!(cap > 0)) return 0;

        var dodgeRate:Number = Number(target.躲闪率);
        if (!(dodgeRate > 0) || !isFinite(dodgeRate)) {
            dodgeRate = DodgeHandler.DODGE_RATE_LIMIT;
        }
        return cap / IMPACT_STAGGER_COEFFICIENT / dodgeRate;
    }

    /** 由同一韧性上限与反向躲闪参数计算踉跄阈值。 */
    public static function calculateImpactStaggerBoundary(target:Object):Number {
        return calculateStaggerFromCap(target, calculateImpactCap(target));
    }

    /**
     * 从当前权威属性与冲击残量重建派生字段，不推进时间也不触发状态改变。
     * 换装降低上限时仅把显示夹到 0；下一次真实命中仍由 ImpactStateHandler 判定破韧。
     */
    public static function refreshImpactDerived(target:Object):Void {
        if (!target) return;

        var cap:Number = calculateImpactCap(target);
        var remaining:Number = Number(target.remainingImpactForce);
        if (!isFinite(remaining)) {
            remaining = remaining > 0 ? cap + 1 : 0;
        } else if (remaining < 0) {
            remaining = 0;
        }

        target.remainingImpactForce = remaining;
        target.韧性上限 = cap;
        target.impactStaggerBoundary = calculateStaggerFromCap(target, cap);

        if (cap > 0) {
            var loadRatio:Number = remaining / cap;
            if (loadRatio < 0) loadRatio = 0;
            else if (loadRatio > 1) loadRatio = 1;
            target.nonlinearMappingResilience = 1 - Math.sqrt(loadRatio);
        } else {
            target.nonlinearMappingResilience = 0;
        }
    }

    private static function applyImpactDecay(target:Object, intervalFrames:Number):Void {
        if (!(intervalFrames > IMPACT_DECAY_FRAME)) return;

        if (intervalFrames >= IMPACT_DECAY_DFRAME) {
            target.remainingImpactForce = 0;
        } else {
            var decayFactor:Number = (IMPACT_DECAY_DFRAME - intervalFrames) / IMPACT_DECAY_DFRAME;
            target.remainingImpactForce *= decayFactor;
        }
    }

    /**
     * 结算冲击力
     * -----------------------------
     * 根据伤害值和击倒率计算冲击力，并累加到目标的剩余冲击力中。
     *
     * 计算公式：
     *   冲击力 = (伤害值 × 冲击系数) ÷ 击倒率
     *
     * 特殊情况：
     *   若击倒率为0或无效，则直接将目标的剩余冲击力设置为超出韧性上限的值，
     *   使其必定被击倒。
     *
     * @param damage Number 造成的伤害值，直接影响冲击力的基础值
     * @param knockRate Number 击倒率，目标受击稳定性（数值越高，越难击倒）
     * @param target Object 被命中的目标对象，需具备属性：
     *        - remainingImpactForce（当前剩余冲击力）
     *        - 韧性上限（目标的冲击韧性上限）
     */
    public static function settleImpactForce(damage:Number, knockRate:Number, target:Object):Void {
        var remaining:Number = Number(target.remainingImpactForce);
        if (!isFinite(remaining) || remaining < 0) remaining = 0;

        // 若击倒率为0或无效，直接设置冲击力超出韧性上限
        if (!(knockRate > 0) || !isFinite(knockRate)) {
            var cap:Number = Number(target.韧性上限);
            if (!isFinite(cap) || cap < 0) cap = calculateImpactCap(target);
            target.remainingImpactForce = cap + 1;
            return;
        }

        if (!(damage > 0) || !isFinite(damage)) {
            target.remainingImpactForce = remaining;
            return;
        }

        // 计算冲击力，并累加到目标的剩余冲击力中
        var impactForce:Number = damage * IMPACT_COEFFICIENT / knockRate;
        if (isFinite(impactForce)) {
            target.remainingImpactForce = remaining + impactForce;
        } else {
            var overflowCap:Number = Number(target.韧性上限);
            if (!isFinite(overflowCap) || overflowCap < 0) overflowCap = calculateImpactCap(target);
            target.remainingImpactForce = overflowCap + 1;
        }
    }

    /**
     * 刷新命中对象的冲击力状态
     * -----------------------------
     * 根据目标的受击时间以及属性，计算当前的韧性上限，同时在必要时对
     * 剩余冲击力进行衰减更新。
     *
     * 衰减规则：
     * 1. 获取当前游戏帧数（currentFrame），计算与上次受击的间隔帧数（intervalFrames）。
     * 2. 当间隔帧数大于衰减起始帧（IMPACT_DECAY_FRAME）时，
     *    - 若 intervalFrames >= IMPACT_DECAY_DFRAME，则直接将 remainingImpactForce = 0；
     *    - 否则按线性衰减公式计算：
     *        remainingImpactForce *= (IMPACT_DECAY_DFRAME - intervalFrames) / IMPACT_DECAY_DFRAME
     *      由于此时 intervalFrames < IMPACT_DECAY_DFRAME，因此系数必然在 (0,1) 区间，保证衰减结果大于 0。
     * 3. 更新目标的 lastHitTime。
     *
     * 同时，韧性上限的计算公式为：
     *    韧性上限 = 韧性系数 × 生命值 ÷ 防御伤害比率
     *
     * @param target Object 被命中的目标对象，需具备以下属性：
     *        - 韧性上限
     *        - remainingImpactForce
     *        - 韧性系数
     *        - lastHitTime（上次受击帧数）
     *        - hp（当前生命值）
     *        - 防御力
     */
    public static function refreshImpactForce(target:Object, actualHit:Boolean):Void {
        // 获取当前帧数（假设全局有帧计时器）
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 计算自上次受击以来的帧数间隔
        var intervalFrames:Number = currentFrame - target.lastHitTime;
        applyImpactDecay(target, intervalFrames);

        // HitUpdater 在伤害结算后调用本方法，因此本次命中使用扣血后的 HP 上限。
        refreshImpactDerived(target);

        // 只有真实命中才开启新的冲击残留窗口。MISS 只允许把既有残量衰减到当前帧，
        // 不得靠连续擦碰无限延后衰减。
        if (actualHit !== false) target.lastHitTime = currentFrame;
    }

    /**
     * 单独的冲击力衰减方法
     * -----------------------------
     * 此方法仅用于计算并更新目标的剩余冲击力衰减值，而不修改上次受击时间，
     * 便于外部按帧调用以实现逐帧衰减效果。
     *
     * 衰减规则同上：
     * 1. 计算当前帧与上次受击帧的间隔 intervalFrames。
     * 2. 若 intervalFrames > IMPACT_DECAY_FRAME：
     *    - 若 intervalFrames >= IMPACT_DECAY_DFRAME，则直接剩余冲击力归零；
     *    - 否则按照线性衰减公式更新冲击力。
     *
     * @param target Object 需要衰减的目标对象，需具备属性：
     *        - remainingImpactForce
     *        - lastHitTime
     */
    public static function decayImpactForce(target:Object):Void {
        // 获取当前帧数
        var currentFrame:Number = _root.帧计时器.当前帧数;
        var intervalFrames:Number = currentFrame - target.lastHitTime;
        applyImpactDecay(target, intervalFrames);
        // 先衰减再更新派生显示，避免头顶韧性条永远慢一帧。
        refreshImpactDerived(target);
    }
}
