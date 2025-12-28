import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;

/**
 * LifeStealDamageHandle 类是用于处理吸血伤害的处理器。
 * - 当子弹具有吸血属性时，根据目标的损伤值和吸血比例，计算吸血量并恢复射击者的血量。
 * - 吸血量受目标当前血量、射击者最大血量和吸血比例的限制。
 * - 吸血效果会显示在伤害结果中。
 *
 * 【护盾交互】
 * - 吸血会检查目标护盾强度，只有子弹威力 > 护盾强度时才能生效
 * - 护盾强度代表"能挡住的单次伤害上限"，高强度护盾可阻止吸血效果
 */
class org.flashNight.arki.component.Damage.LifeStealDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========

    /** 单例实例 */
    public static var instance:LifeStealDamageHandle = new LifeStealDamageHandle();

    // ========== 构造函数 ==========

    /**
     * 构造函数。
     * 调用父类构造函数以初始化基类。
     */
    public function LifeStealDamageHandle() {
        super();
    }

    /**
     * 获取 LifeStealDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 LifeStealDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return LifeStealDamageHandle 单例实例
     */
    public static function getInstance():LifeStealDamageHandle {
        if (instance == null) {
            instance = new LifeStealDamageHandle();
            getInstance = function():LifeStealDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    // ========== 公共方法 ==========

    /**
     * 判断子弹是否具有吸血属性。
     * - 如果子弹的吸血属性值大于 0，则返回 true。
     *
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有吸血属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        return !(bullet.吸血 <= 0);
    }

    /**
     * 处理吸血伤害。
     * - 根据目标的损伤值和吸血比例，计算吸血量并恢复射击者的血量。
     * - 吸血量受以下限制：
     *   1. 不能超过目标当前血量。
     *   2. 不能超过射击者最大血量的 1.5 倍减去当前血量。
     * - 吸血效果会显示在伤害结果中。
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象
     * @param result  伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 护盾强度检查：子弹威力必须超过护盾强度才能触发吸血
        var shield:IShield = target.shield;
        if (shield && bullet.子弹威力 <= shield.getStrength()) {
            return; // 护盾强度足以阻挡，吸血失败
        }

        if (target.损伤值 > 1) {
            var actualScatterUsed:Number = result.actualScatterUsed;

            // 计算吸血量
            var lifeStealAmount:Number = (target.损伤值 * bullet.吸血 / 100) | 0; // 使用位运算取整
            // _root.服务器.发布服务器消息("吸血效果：恢复 " + lifeStealAmount + " 点生命值。");
            lifeStealAmount = lifeStealAmount > target.hp ? target.hp : lifeStealAmount; // 限制吸血量不超过目标当前血量
            lifeStealAmount = lifeStealAmount < 0 ? 0 : lifeStealAmount; // 确保吸血量不小于 0

            // 计算射击者可恢复的血量上限
            // 缓存射击者HP，减少属性访问
            var shooterHP:Number = shooter.hp;
            // 检查射击者是否存活，只有存活的单位才能吸血
            if (shooterHP > 0) {
                var maxHeal:Number = (shooter.hp满血值 * 1.5 - shooterHP) | 0; // 使用位运算取整
                var healAmount:Number = lifeStealAmount > maxHeal ? maxHeal : lifeStealAmount; // 限制吸血量不超过可恢复上限
                
                // 恢复射击者血量
                shooter.hp = shooterHP + healAmount;
            }

            // 添加吸血效果描述
            result.addDamageEffect(
                '<font color="#bb00aa" size="15"> 汲:' + ((lifeStealAmount / actualScatterUsed) | 0).toString() + "</font>"
            );
        }
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "LifeStealDamageHandle";
    }
}