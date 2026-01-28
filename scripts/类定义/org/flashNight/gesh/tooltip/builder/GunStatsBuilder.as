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
import org.flashNight.gesh.tooltip.builder.SilenceEffectBuilder;
 
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
            result.push(TooltipConstants.LBL_CLIP_NAME, "：", ItemUtil.getItemData(data.clipname).displayname, "<BR>");
        }

        // 1.5 射击模式显示（全自动/半自动，支持插件修改显示）
        var baseSingleShoot:Boolean = (data.singleshoot == true || data.singleshoot == "true");
        var finalSingleShoot:Boolean = baseSingleShoot;

        // 检查插件是否修改了射击模式
        if (equipData && equipData.singleshoot != undefined) {
            finalSingleShoot = (equipData.singleshoot == true || equipData.singleshoot == "true");
        }

        var baseFireMode:String = baseSingleShoot ? TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipConstants.TIP_FIRE_MODE_AUTO;
        var finalFireMode:String = finalSingleShoot ? TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipConstants.TIP_FIRE_MODE_AUTO;

        if (equipData && finalSingleShoot != baseSingleShoot) {
            // 插件修改了射击模式，使用箭头形式显示变化
            result.push(TooltipConstants.LBL_FIRE_MODE, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalFireMode, "</FONT> (", baseFireMode, " → ", finalFireMode, ")<BR>");
        } else {
            result.push(TooltipConstants.LBL_FIRE_MODE, "：", finalFireMode, "<BR>");
        }

        // 2. 子弹类型显示（支持重命名，显示插件修改贡献）
        var baseBullet:String = data.bulletrename ? data.bulletrename : data.bullet;
        var finalBullet:String = (equipData && equipData.bullet)
            ? (equipData.bulletrename ? equipData.bulletrename : equipData.bullet)
            : baseBullet;
        if (finalBullet) {
            if (equipData && finalBullet != baseBullet) {
                // 插件修改了子弹类型，使用箭头形式显示变化
                result.push(TooltipConstants.LBL_BULLET_TYPE, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalBullet, "</FONT> (", baseBullet, " → ", finalBullet, ")<BR>");
            } else {
                result.push(TooltipConstants.LBL_BULLET_TYPE, "：", finalBullet, "<BR>");
            }
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
        // 说明：
        // - 对于点射/联弹（magazineCapacity > 1）的武器，最终显示容量会乘以点射数；
        // - 为避免"上限/增量被放大造成误解"，括号内的增量按基础容量计算，并明确显示"×点射数"。
        // - 当 deltaBase = 0（无配件修改）时，仅显示简化格式，避免混淆的 "0×N" 显示
        if (capacity > 0) {
            if (magazineCapacity > 1) {
                // 计算基础与最终容量（未乘点射数）
                var baseCap:Number = Number(data.capacity);
                var finalCap:Number = equipData ? Number(equipData.capacity) : baseCap;
                if (isNaN(baseCap)) baseCap = 0;
                if (isNaN(finalCap)) finalCap = baseCap;

                // 乘以点射数后的显示值
                var baseScaled:Number = baseCap * magazineCapacity;
                var finalScaled:Number = finalCap * magazineCapacity;

                // 基础增量（未乘点射数），用于解释"cap 按基础容量生效"
                var deltaBase:Number = finalCap - baseCap;

                // 根据是否有增量决定显示格式
                if (deltaBase != 0 && equipData) {
                    // 有配件修改时：显示详细分解公式
                    // 输出：弹夹容量：<HL>最终×点射</HL> (基础×点射 + 基础增量 × 点射数)
                    result.push(
                        TooltipConstants.LBL_CAPACITY, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalScaled, "</FONT>",
                        " (", baseScaled, " + ", deltaBase, "×", magazineCapacity, ")<BR>"
                    );
                } else {
                    // 无配件修改时：简化显示，避免混淆的 "0×N"
                    result.push(TooltipConstants.LBL_CAPACITY, "：", finalScaled, "<BR>");
                }
            } else {
                // 普通武器，直接使用 upgradeLine
                TooltipFormatter.upgradeLine(result, data, equipData, "capacity", TooltipConstants.LBL_CAPACITY, null);
            }
        }

        // 8. 子弹威力
        TooltipFormatter.upgradeLine(result, data, equipData, "power", TooltipConstants.LBL_BULLET_POWER, null);

        // 9. 弹裂数量显示
        if (splitValue > 1) {
            result.push(isNotMultiShot ? TooltipConstants.LBL_BURST_COUNT : TooltipConstants.LBL_PELLET_COUNT, "：", splitValue, "<BR>");
        }

        // 10. 射速显示（interval 防护：确保是有效数值且非零，显示插件修改贡献）
        var baseInterval:Number = Number(data.interval);
        var finalInterval:Number = (equipData && equipData.interval) ? Number(equipData.interval) : baseInterval;
        if (!isNaN(finalInterval) && finalInterval > 0) {
            var finalRate:Number = Math.floor(10000 / finalInterval) * 0.1 * magazineCapacity;
            if (equipData && !isNaN(baseInterval) && baseInterval > 0 && finalInterval != baseInterval) {
                // 插件修改了射击间隔，显示射速变化
                var baseRate:Number = Math.floor(10000 / baseInterval) * 0.1 * magazineCapacity;
                var rateDelta:Number = Math.round((finalRate - baseRate) * 10) / 10; // 保留一位小数
                var sign:String = rateDelta >= 0 ? " + " : " - ";
                if (rateDelta < 0) rateDelta = -rateDelta;
                result.push(TooltipConstants.LBL_FIRE_RATE, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalRate, "</FONT> (", baseRate, sign, rateDelta, ")", TooltipConstants.SUF_FIRE_RATE, "<BR>");
            } else {
                result.push(TooltipConstants.LBL_FIRE_RATE, "：", finalRate, TooltipConstants.SUF_FIRE_RATE, "<BR>");
            }
        }

        // 11. 冲击力显示（impact 防护：确保是有效数值且非零）
        var impact:Number = Number(data.impact);
        if (!isNaN(impact) && impact > 0) {
            result.push(TooltipConstants.LBL_IMPACT, "：", Math.floor(500 / impact), "<BR>");
        }

        // 11.5 换弹延迟显示（reloadPenalty：换弹惩罚值，用于延长换弹时间）
        // 说明：reloadPenalty 直接表示额外换弹时间百分比（加到基础100上）
        // 例如：reloadPenalty=17 表示换弹时间延长17%
        var reloadPenalty:Number = Number(data.reloadPenalty);
        if (!isNaN(reloadPenalty) && reloadPenalty > 0) {
            result.push(TooltipConstants.LBL_RELOAD_PENALTY, "：+", reloadPenalty, "%<BR>");
        }

        // 12. 纵向攻击范围（bulletsize）显示
        // 说明：bulletsize 定义了子弹在 Z 轴（纵深方向）的攻击判定范围
        // 数值越大，子弹越容易命中不同 Z 轴位置的目标
        TooltipFormatter.upgradeLine(result, data, equipData, "bulletsize", TooltipConstants.LBL_BULLET_SIZE, null);

        // 13. 消音效果显示
        SilenceEffectBuilder.build(result, baseItem, item, data, equipData);
    }
}
