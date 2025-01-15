import org.flashNight.arki.component.Damage.*;

interface org.flashNight.arki.component.Damage.IDamageHandle {
    /**
     * 核心方法：处理伤害
     * @param bullet      子弹对象
     * @param shooter     发射者
     * @param target      被击中目标
     * @param manager     DamageManager (可选，用于获取上下文或顺序控制)
     * @param result      DamageResult  (最终伤害结果)
     */
    function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void;
}
