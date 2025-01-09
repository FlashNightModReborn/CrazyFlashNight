import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.component.StatHandler.ImpactHandler {
    // 常量配置，便于外部调整
    public static var IMPACT_COEFFICIENT:Number = 50; // 冲击系数，控制冲击力的基础倍数
    public static var IMPACT_DECAY_TIME:Number = 5;  // 冲击残余时间（秒）
    public static var IMPACT_STAGGER_COEFFICIENT:Number = 2; // 控制硬直和冲击力衰减关联的系数
    public static var IMPACT_DECAY_FRAME:Number = IMPACT_DECAY_TIME * 30; // 按帧计算的冲击力衰减时间，假设游戏帧率为30FPS
    public static var IMPACT_DECAY_DFRAME:Number = IMPACT_DECAY_FRAME * 2; // 简化内部公式计算中帧数两倍的常量

    /**
     * 结算冲击力
     * 将计算得到的冲击力添加到命中对象的 `remainingImpactForce` 中。
     * 
     * 冲击力计算公式：
     * - 冲击力 = (伤害值 × 冲击系数) ÷ 击倒率
     * 
     * @param damage Number 造成的伤害值，直接影响冲击力的基础值
     * @param knockRate Number 击倒率，描述目标的受击稳定性，数值越高表示越难被击倒
     * @param target Object 被命中的对象，需具备 `remainingImpactForce` 和 `韧性上限` 属性
     */
    public static function settleImpactForce(damage:Number, knockRate:Number, target:Object):Void {
        // 若击倒率为 0 或无效，直接设置为超出韧性上限的值
        if (knockRate == 0 || !isFinite(knockRate)) {
            target.remainingImpactForce = target.韧性上限 + 1;
            return;
        }

        // 按公式计算冲击力，并累加到目标的剩余冲击力中
        var impactForce:Number = damage * IMPACT_COEFFICIENT / knockRate;
        target.remainingImpactForce += impactForce;
    }

    /**
     * 刷新命中对象的冲击力状态
     * 该方法会根据受击时间和对象的属性计算韧性上限，并在必要时衰减 `remainingImpactForce`。
     * 
     * 冲击力衰减公式：
     * - 若当前帧数 - 上次受击帧数 > 衰减阈值帧数，则：
     *   剩余冲击力 = 剩余冲击力 × (设定最大衰减帧数 - 时间间隔帧数) ÷ 设定最大衰减帧数
     * - 若结果小于 0，则设为 0。
     * 
     * 游戏场景说明：
     * - `currentFrame`：表示游戏当前的帧数，用于计算时间间隔。
     * - `韧性上限`：受目标的生命值 (`hp`)、韧性系数 (`韧性系数`)、以及防御力 (`防御力`) 共同影响。
     * - `lastHitTime`：记录目标上次受击的帧数，决定是否进行冲击力衰减。
     * 
     * @param target Object 被命中的对象，需具备以下属性：
     *  - `韧性上限`：最大允许的冲击力。
     *  - `remainingImpactForce`：当前剩余的冲击力。
     *  - `韧性系数`：影响韧性上限的系数。
     *  - `lastHitTime`：上次受击的帧数。
     *  - `hp`：目标当前生命值。
     *  - `防御力`：目标的防御属性。
     */
    public static function refreshImpactForce(target:Object):Void {
        // 获取当前帧数
        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 计算韧性上限，公式：
        // 韧性上限 = 韧性系数 × 生命值 ÷ 防御伤害比率
        target.韧性上限 = target.韧性系数 * target.hp / DamageResistanceHandler.defenseDamageRatio(target.防御力);

        var intervalFrames:Number = currentFrame - target.lastHitTime; // 距离上次受击的时间间隔（帧数）

        // 若间隔超过设定的衰减时间，按公式计算衰减
        if (intervalFrames > IMPACT_DECAY_FRAME) {
            // 剩余冲击力的衰减公式
            var decayForce:Number = target.remainingImpactForce * ((IMPACT_DECAY_DFRAME - intervalFrames) / IMPACT_DECAY_DFRAME);
            
            // 手动实现 Math.max，以避免调用开销
            target.remainingImpactForce = decayForce > 0 ? decayForce : 0;
        }

        // 更新目标的受击时间为当前帧数
        target.lastHitTime = currentFrame;
    }
}
