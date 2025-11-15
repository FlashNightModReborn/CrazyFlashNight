import org.flashNight.arki.component.Damage.*;

/**
 * ExecuteDamageHandle 类是用于处理斩杀伤害的处理器。
 * - 当目标的当前血量低于斩杀阈值时，直接将其血量降为 0，并增加相应的损伤值。
 * - 支持根据子弹的敌我属性值设置不同的斩杀效果颜色。
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
     * - 如果目标扣血后的剩余血量低于斩杀阈值（目标满血值 * 斩杀比例 / 100），则将其血量降为 0，并增加相应的损伤值。
     * - 根据子弹的敌我属性值设置不同的斩杀效果颜色。
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

        // 如果扣血后的剩余血量低于斩杀阈值，则执行斩杀
        if (remainingHp < executeThreshold) {
            // 如果剩余血量大于0，则将其也计入损伤值；否则保持当前损伤值不变
            if (remainingHp > 0) {
                target.损伤值 += remainingHp;
            }
            target.hp = 0; // 将目标血量降为 0（防止护盾等机制干扰）

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