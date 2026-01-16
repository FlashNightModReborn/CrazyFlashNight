import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.Buff.BuffManager;

/**
 * PurifyEffect - 净化效果词条
 *
 * 清除负面状态：减少麻痹值、降低地形伤害系数、可选清除debuff。
 *
 * XML配置示例:
 * <effect type="purify" value="50" scaleWithAlchemy="true"/>
 * <effect type="purify" value="30" clearDebuffs="debuff_"/>
 *
 * 参数说明:
 * - value: 净化强度值（影响麻痹值和地形伤害系数的计算）
 * - scaleWithAlchemy: 是否应用炼金加成（默认true）
 * - clearDebuffs: 要清除的debuff的ID前缀（可选，多个用逗号分隔）
 * - terrainDamageBase: 地形伤害系数的基准值（默认0.09）
 * - terrainDamageFactor: 地形伤害系数的衰减因子（默认20）
 * - paralysisMultiplier: 麻痹值减少的倍率（默认-10）
 *
 * 计算公式:
 * - 麻痹值 = paralysisMultiplier * 净化量
 * - 地形伤害系数 = terrainDamageBase + (当前系数 - terrainDamageBase) * terrainDamageFactor / 净化量
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.effects.PurifyEffect implements IDrugEffect {

    public function PurifyEffect() {
    }

    public function getType():String {
        return "purify";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var value:Number = Number(effectData.value);
        if (isNaN(value)) value = 0;

        var scaleWithAlchemy:Boolean = effectData.scaleWithAlchemy != "false";

        // 应用炼金加成
        if (scaleWithAlchemy) {
            value = ctx.calcPurifyWithAlchemy(value);
        }

        // 获取配置参数（使用默认值）
        var terrainDamageBase:Number = Number(effectData.terrainDamageBase);
        if (isNaN(terrainDamageBase)) terrainDamageBase = 0.09;

        var terrainDamageFactor:Number = Number(effectData.terrainDamageFactor);
        if (isNaN(terrainDamageFactor)) terrainDamageFactor = 20;

        var paralysisMultiplier:Number = Number(effectData.paralysisMultiplier);
        if (isNaN(paralysisMultiplier)) paralysisMultiplier = -10;

        var target:Object = ctx.target;

        // 1. 减少地形伤害系数
        if (_root.地形伤害系数 && value > 0) {
            _root.地形伤害系数 = terrainDamageBase +
                (_root.地形伤害系数 - terrainDamageBase) * terrainDamageFactor / value;
        }

        // 2. 减少麻痹值
        target.麻痹值 = paralysisMultiplier * value;

        // 3. 清除debuff（可选）
        var clearDebuffs:String = effectData.clearDebuffs;
        if (clearDebuffs && clearDebuffs.length > 0 && target.buffManager) {
            var buffManager:BuffManager = target.buffManager;
            var prefixes:Array = clearDebuffs.split(",");
            for (var i:Number = 0; i < prefixes.length; i++) {
                var prefix:String = prefixes[i];
                // 去除首尾空格
                while (prefix.charAt(0) == " ") prefix = prefix.substring(1);
                while (prefix.charAt(prefix.length - 1) == " ") prefix = prefix.substring(0, prefix.length - 1);
                if (prefix.length > 0) {
                    buffManager.removeBuffsByIdPrefix(prefix);
                }
            }
        }

        return true;
    }
}
