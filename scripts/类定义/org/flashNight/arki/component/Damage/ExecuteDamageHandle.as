import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;

/**
 * ExecuteDamageHandle 类是用于处理斩杀伤害的处理器。
 *
 * 【斩杀机制】
 * - 当目标扣血后的剩余血量低于斩杀阈值时，触发斩杀效果
 * - 斩杀阈值 = 目标满血值 * 斩杀比例 / 100
 *
 * 【护盾交互】
 * - 斩杀会检查目标护盾强度，只有子弹威力 > 护盾强度时才能触发斩杀
 * - 斩杀触发时，将护盾强度计入损伤值，确保一击必杀（击穿护盾 + 斩杀目标）
 * - 同时清空护盾容量，防止后续护盾吸收干扰
 *
 * 【设计理念】
 * 护盾强度代表"能挡住的单次伤害上限"，斩杀作为终结技，
 * 只要攻击力足够强（超过护盾强度），就应该无视护盾直接处决目标。
 */
class org.flashNight.arki.component.Damage.ExecuteDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========

    /** 单例实例 */
    public static var instance:ExecuteDamageHandle = new ExecuteDamageHandle();

    // ========== 构造函数 ==========

    /**
     * 构造函数。
     * 调用父类构造函数以初始化基类。
     */
    public function ExecuteDamageHandle() {
        super();
    }

    /**
     * 获取 ExecuteDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 ExecuteDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return ExecuteDamageHandle 单例实例
     */
    public static function getInstance():ExecuteDamageHandle {
        if (instance == null) {
            instance = new ExecuteDamageHandle();
            getInstance = function():ExecuteDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    // ========== 公共方法 ==========

    /**
     * 判断子弹是否具有斩杀属性。
     * - 如果子弹对象包含斩杀属性（bullet.斩杀 != null），则返回 true。
     *
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有斩杀属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        return (bullet.斩杀 != null);
    }

    /**
     * 处理斩杀伤害。
     *
     * 【执行条件】
     * 1. 目标扣血后剩余血量 < 斩杀阈值
     * 2. 子弹威力 > 目标护盾强度（护盾无法阻挡此攻击）
     *
     * 【执行效果】
     * - 将护盾当前容量计入损伤值（击穿护盾）
     * - 将目标剩余血量计入损伤值（斩杀目标）
     * - 清空护盾容量，防止后续吸收
     * - 目标血量归零
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象
     * @param result  伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 计算斩杀阈值
        var executeThreshold:Number = target.hp满血值 * bullet.斩杀 / 100;

        // 计算扣血后的剩余血量
        var remainingHp:Number = target.hp - target.损伤值;

        // 如果扣血后的剩余血量低于斩杀阈值，检查是否能触发斩杀
        if (remainingHp < executeThreshold) {
            // 获取目标护盾
            var shield:IShield = target.shield;
            var shieldStrength:Number = shield.getStrength();

            // 护盾强度检查：子弹威力必须超过护盾强度才能触发斩杀
            // 这确保了高强度护盾能有效阻止斩杀效果
            if (bullet.子弹威力 <= shieldStrength) {
                return; // 护盾强度足以阻挡，斩杀失败
            }

            // ===== 斩杀生效 =====

            // 将护盾当前容量计入损伤值（击穿护盾造成的"伤害"）
            var shieldCapacity:Number = shield.getCapacity();
            if (shieldCapacity > 0) {
                target.损伤值 += shieldCapacity;
                // 清空护盾，防止后续 DamageCalculator 中的护盾吸收
                shield.consumeCapacity(shieldCapacity);
            }

            // 将目标剩余血量计入损伤值
            if (remainingHp > 0) {
                target.损伤值 += remainingHp;
            }

            // 目标血量归零
            target.hp = 0;

            // 根据子弹的敌我属性值设置斩杀效果颜色
            var executeColor:String = bullet.是否为敌人 ? '#660033' : '#4A0099';

            // 添加斩杀效果描述
            result.addDamageEffect('<font color="' + executeColor + '" size="20"> 斩</font>');
        }
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "ExecuteDamageHandle";
    }
}