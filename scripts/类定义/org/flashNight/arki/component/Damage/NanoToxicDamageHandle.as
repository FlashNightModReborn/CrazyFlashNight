import org.flashNight.arki.component.Damage.*;

/**
 * NanoToxicDamageHandle 类是用于处理纳米毒素伤害的处理器。
 * - 当子弹具有纳米毒素属性时，根据子弹的毒素值和目标的属性，计算毒素伤害并更新目标的损伤值。
 * - 支持普通检测和近战检测，影响毒素伤害的计算。
 * - 支持毒素返还机制，当目标具有毒返属性时，会将部分毒素伤害返还给射击者。
 */
class org.flashNight.arki.component.Damage.NanoToxicDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========

    /** 单例实例 */
    public static var instance:NanoToxicDamageHandle = new NanoToxicDamageHandle();

    // ========== 构造函数 ==========

    /**
     * 构造函数。
     * 调用父类构造函数以初始化基类。
     */
    public function NanoToxicDamageHandle() {
        super();
    }

    /**
     * 获取 NanoToxicDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 NanoToxicDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return NanoToxicDamageHandle 单例实例
     */
    public static function getInstance():NanoToxicDamageHandle {
        if (instance == null) {
            instance = new NanoToxicDamageHandle();
            getInstance = function():NanoToxicDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    // ========== 公共方法 ==========

    /**
     * 判断子弹是否具有纳米毒素属性。
     * - 如果子弹的 nanoToxic 属性值大于 0，则返回 true。
     *
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有纳米毒素属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        //_root.发布消息(!!(bullet.nanoToxic > 0))
        return (bullet.nanoToxic > 0);
    }

    /**
     * 处理纳米毒素伤害。
     * - 根据子弹的毒素值和目标的属性，计算毒素伤害并更新目标的损伤值。
     * - 支持普通检测和近战检测，影响毒素伤害的计算。
     * - 支持毒素返还机制，当目标具有毒返属性时，会将部分毒素伤害返还给射击者。
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象
     * @param result  伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var damageNumber:Number = target.损伤值;
        var nanoToxicAmount:Number = bullet.nanoToxic;

        // 根据普通检测调整毒素伤害
        if (bullet.普通检测) {
            nanoToxicAmount *= 1; // 普通检测时，毒素伤害不变
        } else {
            nanoToxicAmount *= 0.3; // 非普通检测时，毒素伤害减少为 30%
        }
        if(bullet.子弹种类.indexOf("纵向") != -1 && result.actualScatterUsed > 1){
            nanoToxicAmount *= result.actualScatterUsed;
        }

        // 将毒素伤害添加到子弹的额外效果伤害中
        bullet.additionalEffectDamage += nanoToxicAmount;

        // 如果目标的损伤值大于 0，则应用毒素伤害
        if (damageNumber > 0) {
            target.损伤值 += nanoToxicAmount; // 更新目标的损伤值
            damageNumber = target.损伤值;

            // 添加毒素效果描述
            result.addDamageEffect('<font color="#66dd00" size="20"> 毒</font>');

            // 如果子弹具有毒素衰减属性且为近战检测，并且射击者的淬毒值大于 10，则减少射击者的淬毒值
            if (bullet.nanoToxicDecay && bullet.近战检测 && shooter.淬毒 > 10) {
                shooter.淬毒 -= bullet.nanoToxicDecay;
            }

            // 如果目标具有毒返属性，则计算毒素返还伤害
            if (target.毒返 > 0) {
                var nanoToxicReturnAmount:Number = nanoToxicAmount * target.毒返;

                // 如果目标定义了毒返函数，则调用该函数
                if (target.毒返函数) {
                    target.毒返函数(nanoToxicAmount, nanoToxicReturnAmount);
                }

                // 将毒素返还伤害存储在目标的淬毒属性中
                target.淬毒 = nanoToxicReturnAmount;
            }
        }
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "NanoToxicDamageHandle";
    }
}