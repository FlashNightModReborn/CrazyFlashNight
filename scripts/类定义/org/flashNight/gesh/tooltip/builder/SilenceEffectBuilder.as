/**
 * SilenceEffectBuilder - 消音效果构建器
 *
 * 职责：
 * - 构建消音效果的显示文本
 * - 根据消音策略类型（距离/概率）生成友好的说明文字
 * - 提供详细的效果解释
 *
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipConstants 统一格式化和配色
 * - 保持与其他 builder 一致的接口风格
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.builder.SilenceEffectBuilder {

    /**
     * 构建消音效果块
     *
     * 关于数据流和 override 语义的说明：
     * - data: 武器的基础属性（未应用配件）
     * - equipData: 应用配件后的最终属性（仅在有配件时存在）
     * - silence 属性使用 override 修改类型（完全替换），而非 flat（加法）或 percentage（乘法）
     * - 原因：消音是定性属性（距离模式 vs 概率模式），无法进行数值累加
     *   例如：武器300距离消音 + 配件200距离消音 = 500？这在游戏逻辑上无意义
     * - 配件的 silence 会完全替换武器的 silence，体现为 finalSilence != baseSilence
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 基础装备数据（不含配件）
     * @param equipData:Object 强化/配件数据（可选，包含配件修改后的最终数据）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        var baseSilence:Object = data ? data.silence : null;
        var finalSilence:Object = equipData ? equipData.silence : null;

        // 优先使用最终值，如果没有则使用基础值
        var silenceValue:Object = finalSilence != null ? finalSilence : baseSilence;

        // 检查是否有消音属性
        if (silenceValue == null || silenceValue == undefined) {
            return;
        }

        var silenceStr:String = String(silenceValue);

        // 百分比消音（概率模式）
        if (silenceStr.indexOf("%") > 0) {
            buildPercentageSilence(result, silenceStr, baseSilence, finalSilence);
        }
        // 距离消音（阈值模式）
        else {
            buildDistanceSilence(result, silenceValue, baseSilence, finalSilence);
        }
    }

    /**
     * 构建百分比消音显示（概率模式）
     *
     * @param result:Array 输出缓冲区
     * @param silenceStr:String 消音值字符串（例如 "90%"）
     * @param baseSilence:Object 基础消音值
     * @param finalSilence:Object 配件修改后的最终消音值
     * @return Void
     */
    private static function buildPercentageSilence(result:Array, silenceStr:String, baseSilence:Object, finalSilence:Object):Void {
        var percentIndex:Number = silenceStr.indexOf("%");
        var percentValue:String = silenceStr.substring(0, percentIndex);
        var percentNum:Number = Number(percentValue);

        // 验证百分比值是否有效
        if (isNaN(percentNum) || percentNum < 0 || percentNum > 100) {
            return;
        }

        // 主显示行：消音效果
        result.push("<FONT COLOR='" + TooltipConstants.COL_SILENCE + "'>消音效果：</FONT>");

        // 检查是否有配件修改
        if (finalSilence != null && baseSilence != null && finalSilence != baseSilence) {
            // 检测是否为类型切换（从距离模式切换到概率模式）
            var baseStr:String = String(baseSilence);
            var isTypeSwitched:Boolean = (baseStr.indexOf("%") < 0); // 原值不含%说明是距离模式

            // 显示配件覆盖效果
            result.push(
                "<FONT COLOR='" + TooltipConstants.COL_HL + "'>",
                percentValue,
                "%</FONT> 概率消音成功 <FONT COLOR='" + TooltipConstants.COL_INFO + "'>(原"
            );

            if (isTypeSwitched) {
                // 类型切换：从距离模式切换到概率模式
                result.push("距离 ", baseSilence);
            } else {
                // 同类型覆盖
                result.push(baseSilence);
            }

            result.push(")</FONT><BR>");
        } else {
            // 正常显示
            result.push(percentValue, "% 概率消音成功<BR>");
        }

        // 详细说明行
        result.push(
            "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>  [攻击时有 ",
            percentValue,
            "% 几率不触发敌人仇恨]</FONT><BR>"
        );
    }

    /**
     * 构建距离消音显示（阈值模式）
     *
     * @param result:Array 输出缓冲区
     * @param silenceValue:Object 消音值（数字，表示距离阈值）
     * @param baseSilence:Object 基础消音值
     * @param finalSilence:Object 配件修改后的最终消音值
     * @return Void
     */
    private static function buildDistanceSilence(result:Array, silenceValue:Object, baseSilence:Object, finalSilence:Object):Void {
        var distanceValue:Number = Number(silenceValue);

        // 验证距离值是否有效
        if (isNaN(distanceValue) || distanceValue <= 0) {
            return;
        }

        // 主显示行：消音效果（突出显示距离数值）
        result.push("<FONT COLOR='" + TooltipConstants.COL_SILENCE + "'>消音效果：</FONT>");

        // 检查是否有配件修改
        if (finalSilence != null && baseSilence != null && finalSilence != baseSilence) {
            // 检测是否为类型切换（从概率模式切换到距离模式）
            var baseStr:String = String(baseSilence);
            var isTypeSwitched:Boolean = (baseStr.indexOf("%") > 0); // 原值含%说明是概率模式

            // 显示配件覆盖效果
            result.push(
                "距离 > <FONT COLOR='" + TooltipConstants.COL_HL + "'>",
                distanceValue,
                "</FONT> <FONT COLOR='" + TooltipConstants.COL_INFO + "'>(原"
            );

            if (isTypeSwitched) {
                // 类型切换：从概率模式切换到距离模式
                result.push("概率 ", baseSilence);
            } else {
                // 同类型覆盖
                result.push(baseSilence);
            }

            result.push(")</FONT><BR>");
        } else {
            // 正常显示
            result.push(
                "距离 > <FONT COLOR='" + TooltipConstants.COL_HL + "'>",
                distanceValue,
                "</FONT><BR>"
            );
        }

        // 详细说明行
        result.push(
            "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>  [攻击超过 ",
            "<FONT COLOR='" + TooltipConstants.COL_HL + "'>",
            distanceValue,
            "</FONT>",
            " 距离的目标不触发仇恨]</FONT><BR>"
        );
    }

    /**
     * 获取消音效果的简短描述（用于配件列表等简略显示场景）
     *
     * @param silenceValue:Object 消音值
     * @return String 简短描述文本
     */
    public static function getShortDescription(silenceValue:Object):String {
        if (silenceValue == null || silenceValue == undefined) {
            return "";
        }

        var silenceStr:String = String(silenceValue);

        // 百分比消音
        if (silenceStr.indexOf("%") > 0) {
            return silenceStr + "消音";
        }

        // 距离消音
        var distanceValue:Number = Number(silenceValue);
        if (!isNaN(distanceValue) && distanceValue > 0) {
            return ">" + distanceValue + "消音";
        }

        return "";
    }
}