import org.flashNight.arki.component.Damage.*;

interface org.flashNight.arki.component.Damage.IDamageHandle {
    /**
     * 判断是否可以处理当前子弹的伤害
     * @param bullet 子弹对象
     * @return 是否可以处理
     */
    function canHandle(bullet:Object):Boolean;
    
    /**
     * 处理伤害
     * @param bullet 子弹对象
     * @param shooter 发射者
     * @param target 被击中目标
     * @param manager DamageManager 实例
     * @param result DamageResult 实例
     */
    function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void;
}
