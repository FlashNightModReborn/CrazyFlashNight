/**
 * GunStatsBuilder - 枪械属性构建器
 * 
 * 职责：
 * - 构建枪械专属属性（容量/弹裂/射速/冲击等）
 * - 处理子弹类型重命名和显示
 * - 计算多发弹匣容量
 * - 应用条件后缀（硬直/后坐）
 * 
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipFormatter 统一格式化
 * - 保持与原逻辑完全一致的输出
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.GunStatsBuilder {

    /**
     * 构建枪械属性块
     *
     * 迁移自 TooltipTextBuilder.buildEquipmentStats Line 273-316
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据
     * @param equipData:Object 强化/配件数据（可选）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        // 1. 弹夹名称显示
        if (data.clipname) {
            result.push("使用弹夹：", ItemUtil.getItemData(data.clipname).displayname, "<BR>");
        }

        // 2. 子弹类型显示（支持重命名）
        var bulletString:String = data.bulletrename ? data.bulletrename : data.bullet;
        if (bulletString) {
            result.push("子弹类型：", bulletString, "<BR>");
        }

        // 3. 判断是否为点射武器（非多发弹匣）
        var isNotMultiShot:Boolean = (data.bullet && BulletTypesetter.isVertical(data.bullet));

        // 4. 弹裂规范化（防护：使用 Number() 转换 + isNaN() 兜底）
        var splitValue:Number = Number(data.split);
        if (isNaN(splitValue) || splitValue <= 1) {
            splitValue = 1;
        }

        // 5. 容量规范化
        var capacity:Number = Number(data.capacity);
        if (isNaN(capacity)) {
            capacity = 0;
        }

        // 6. 计算弹匣容量乘数
        var magazineCapacity:Number = isNotMultiShot ? splitValue : 1;

        // 7. 处理弹夹容量显示（考虑 magazineCapacity 乘数）
        if (capacity > 0) {
            if (magazineCapacity > 1) {
                // 有 magazineCapacity 乘数（点射武器）
                // 需要临时创建对象来正确显示乘数后的容量
                var tempData:Object = {capacity: data.capacity * magazineCapacity};
                var tempEquipData:Object = equipData ? {capacity: equipData.capacity * magazineCapacity} : null;
                TooltipFormatter.upgradeLine(result, tempData, tempEquipData, "capacity", "弹夹容量", null);
            } else {
                // 普通武器，直接使用 upgradeLine
                TooltipFormatter.upgradeLine(result, data, equipData, "capacity", "弹夹容量", null);
            }
        }

        // 8. 子弹威力
        TooltipFormatter.upgradeLine(result, data, equipData, "power", "子弹威力", null);

        // 9. 弹裂数量显示
        if (splitValue > 1) {
            result.push(isNotMultiShot ? "点射弹数：" : "弹丸数量：", splitValue, "<BR>");
        }

        // 10. 射速显示（interval 防护：确保是有效数值且非零）
        var interval:Number = Number(data.interval);
        if (!isNaN(interval) && interval > 0) {
            result.push("射速：", (Math.floor(10000 / interval) * 0.1 * magazineCapacity), TooltipConstants.SUF_FIRE_RATE + "<BR>");
        }

        // 11. 冲击力显示（impact 防护：确保是有效数值且非零）
        var impact:Number = Number(data.impact);
        if (!isNaN(impact) && impact > 0) {
            result.push("冲击力：", Math.floor(500 / impact), "<BR>");
        }
    }
}
