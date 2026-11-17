/**
 * ResistanceBlockBuilder - 抗性块构建器
 * 
 * 职责：
 * - 构建抗性相关属性（各类元素抗性等）
 * - 迭代抗性字典，应用高亮和增量显示
 * - 处理抗性增强值显示
 * 
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipFormatter 统一格式化
 * - 保持与原逻辑完全一致的输出
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.ResistanceBlockBuilder {

    /**
     * 构建抗性属性块
     *
     * 迁移自 TooltipTextBuilder Line 347-404
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据
     * @param equipData:Object 强化/配件数据（可选）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        // 使用最终计算后的数据显示魔法抗性（如果有mod或强化，则使用equipData）
        var finalData:Object = equipData ? equipData : data;

        // 收集所有需要显示的抗性类型（基础数据和最终数据的并集）
        if (!finalData.magicdefence && !data.magicdefence) {
            return;
        }

        var resistanceTypes:Object = {};
        if (data.magicdefence) {
            for (var key:String in data.magicdefence) {
                if (ObjectUtil.isInternalKey(key)) continue;
                resistanceTypes[key] = true;
            }
        }
        if (finalData.magicdefence) {
            for (var key:String in finalData.magicdefence) {
                if (ObjectUtil.isInternalKey(key)) continue;
                resistanceTypes[key] = true;
            }
        }

        // 对每个抗性类型显示变化前后的值（类似 upgradeLine 的逻辑）
        for (var key:String in resistanceTypes) {
            var baseResist = (data.magicdefence && data.magicdefence[key]) ? data.magicdefence[key] : null;
            var finalResist = (finalData.magicdefence && finalData.magicdefence[key]) ? finalData.magicdefence[key] : null;

            // 如果两者都没有值或都为0，跳过
            if ((baseResist == null || Number(baseResist) == 0) && (finalResist == null || Number(finalResist) == 0)) continue;

            var displayName:String = (key == TooltipConstants.TXT_BASE ? TooltipConstants.TXT_ENERGY : key);
            var label:String = displayName + TooltipConstants.SUF_RESISTANCE;

            // 若没有实际装备数值或实际数值与原始数值相等，则打印原始数值
            if (!equipData || finalResist == baseResist || finalResist == null) {
                if (baseResist != null && Number(baseResist) != 0) {
                    result.push(label, "：", baseResist, "<BR>");
                }
            } else {
                // 有变化，显示变化前后的值
                if (finalResist != null && Number(finalResist) != 0) {
                    result.push(label, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalResist, "</FONT>");
                    if (baseResist == null) baseResist = 0;
                    // 若属性为数字，则额外打印增幅值
                    var baseNum:Number = Number(baseResist);
                    var finalNum:Number = Number(finalResist);
                    if (isNaN(finalNum) || isNaN(baseNum)) {
                        result.push(" (覆盖", baseResist, ")<BR>");
                    } else {
                        var enhance:Number = finalNum - baseNum;
                        var sign:String;
                        if (enhance < 0) {
                            enhance = -enhance;
                            sign = " - ";
                        } else {
                            sign = " + ";
                        }
                        result.push(" (", baseResist, sign, enhance, ")<BR>");
                    }
                }
            }
        }
    }
}
