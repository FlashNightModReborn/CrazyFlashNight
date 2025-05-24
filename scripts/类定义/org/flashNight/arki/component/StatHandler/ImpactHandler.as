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
        // 若击倒率为0或无效，直接设置冲击力超出韧性上限
        if (knockRate == 0 || !isFinite(knockRate)) {
            target.remainingImpactForce = target.韧性上限 + 1;
            return;
        }

        // 计算冲击力，并累加到目标的剩余冲击力中
        var impactForce:Number = damage * IMPACT_COEFFICIENT / knockRate;
        target.remainingImpactForce += impactForce;
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
    public static function refreshImpactForce(target:Object):Void {
        // 获取当前帧数（假设全局有帧计时器）
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 计算韧性上限：考虑生命值、韧性系数及防御力影响
        // target.韧性上限 = target.韧性系数 * target.hp / DamageResistanceHandler.defenseDamageRatio(target.防御力);

        // 计算自上次受击以来的帧数间隔
        var intervalFrames:Number = currentFrame - target.lastHitTime;

        // 当间隔超过衰减起始帧数时，进行冲击力衰减处理
        if (intervalFrames > IMPACT_DECAY_FRAME) {
            // 如果间隔帧数达到或超过最大衰减帧数，则直接将剩余冲击力归零
            if (intervalFrames >= IMPACT_DECAY_DFRAME) {
                target.remainingImpactForce = 0;
            } else {
                // 否则，intervalFrames < IMPACT_DECAY_DFRAME，系数必然位于(0,1)之间
                var decayFactor:Number = (IMPACT_DECAY_DFRAME - intervalFrames) / IMPACT_DECAY_DFRAME;
                // 直接乘以衰减系数即可，无需额外判断负值
                target.remainingImpactForce *= decayFactor;
            }
        }

        // 更新目标的上次受击帧数为当前帧数
        target.lastHitTime = currentFrame;
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
        target.韧性上限 = target.韧性系数 * target.hp / DamageResistanceHandler.defenseDamageRatio(target.防御力);
        target.nonlinearMappingResilience = (1 - Math.sqrt(target.remainingImpactForce / target.韧性上限));
        target.impactStaggerBoundary = target.韧性上限 / IMPACT_STAGGER_COEFFICIENT / target.躲闪率;

        // 当间隔超过衰减起始帧数时，开始计算衰减
        if (intervalFrames > IMPACT_DECAY_FRAME) {
            // 当间隔达到或超过最大衰减帧数时，直接归零
            if (intervalFrames >= IMPACT_DECAY_DFRAME) {
                target.remainingImpactForce = 0;
            } else {
                // 否则，intervalFrames < IMPACT_DECAY_DFRAME，衰减系数必定位于(0,1)
                var decayFactor:Number = (IMPACT_DECAY_DFRAME - intervalFrames) / IMPACT_DECAY_DFRAME;
                target.remainingImpactForce *= decayFactor;
            }
        }
    }
}
