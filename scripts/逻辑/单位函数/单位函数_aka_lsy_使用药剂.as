/**
 * 药剂使用系统
 *
 * 重构说明:
 * - 使用 XML 中的 effects 数组（词条系统）执行药剂效果
 * - 使用 DrugEffectNormalizer 归一化 effects 结构
 * - 保持 _root.使用药剂(物品名) 接口不变，FLA快捷栏无需改动
 *
 * @author FlashNight
 * @version 3.0
 */
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.drug.*;

/**
 * 使用药剂（主入口）
 *
 * @param 物品名 String 药剂物品名称
 */
_root.使用药剂 = function(物品名:String):Void {
    var 控制对象:Object = TargetCacheManager.findHero();
    if (!控制对象 || 控制对象.hp <= 0) {
        return;
    }

    var itemData:Object = _root.getItemData(物品名);
    if (!itemData || !itemData.data) {
        trace("[使用药剂] 无效的物品数据: " + 物品名);
        return;
    }

    // 使用共享的归一化工具
    var effects:Array = DrugEffectNormalizer.normalize(itemData.data);

    if (effects.length == 0) {
        trace("[使用药剂] 无有效的 effects: " + 物品名);
        return;
    }

    // 初始化注册表（首次调用时自动注册所有词条）
    DrugEffectRegistry.initialize();

    // 创建执行上下文，直接传入已获取的数据避免重复查询
    var context:DrugContext = DrugContext.createWithData(物品名, 控制对象, itemData);
    if (!context.isValid()) {
        trace("[使用药剂] 上下文无效");
        return;
    }

    // 执行所有词条
    DrugEffectRegistry.executeAll(effects, context);
};
