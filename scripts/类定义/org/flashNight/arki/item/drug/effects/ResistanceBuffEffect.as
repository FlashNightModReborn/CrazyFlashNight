import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

/**
 * ResistanceBuffEffect - 属性抗性的临时增益/减益。
 *
 * 魔法抗性是对象，不能交给普通 buff 词条当作一个数值属性处理。本词条
 * 使用 BuffManager 路径绑定，对目标抗性叶子路径施加加算与乘区 Buff。
 *
 * 默认作用范围 = 电/热/冷/波/蚀/毒/冲 + 基础（"基础"即能量抗性，对外的显示名是"能量"）。
 *
 * 【正负双向】
 * 游戏存在负抗性设定：抗性为负即易伤（伤害公式 伤害 × (100 - 抗性) / 100，
 * 抗性 -50 → 承伤 ×1.5）。因此本词条的 value / mult_positive 均接受正负两侧取值，
 * 并按符号自动选用保守语义的对应类型：
 *   value > 0  → ADD_POSITIVE（同类取 max）
 *   value < 0  → ADD_NEGATIVE（同类取 min）
 *   mult > 1   → MULT_POSITIVE（同类取 max）
 *   mult < 1   → MULT_NEGATIVE（同类取 min，0 表示抗性归零，负值表示抗性反转）
 * 正向与负向分属两个乘区，可同时生效（例如 ×2 与 ×0.5 并存 → 净 ×1）。
 *
 * 【倍率的方向陷阱】
 * 倍率是"按比例缩放当前抗性值"，方向取决于抗性本身的正负：
 *   抗性为正（30）→ ×0.5 = 15，减抗、更易伤（符合减益预期）
 *   抗性已为负（-50）→ ×0.5 = -25，反而减轻易伤（与减益预期相反）
 * 因此想做"易伤"debuff 时优先用负的 value（直接打负抗性），
 * 只有在明确知道目标抗性为正时才用 <1 的倍率。
 *
 * XML配置示例:
 * <effect type="resistanceBuff" value="10" duration="300"
 *         buffId="九龙_螭吻_全抗"/>
 *
 * <effect type="resistanceBuff" mult_positive="2" value="5" duration="300"
 *         buffId="全属性抗性药剂_全抗"/>
 *
 * <effect type="resistanceBuff" property="电" mult_positive="2.2" value="10"
 *         duration="300" buffId="电抗性药剂_电抗"/>
 *
 * <!-- 减益示例：电抗 -20，易伤 -->
 * <effect type="resistanceBuff" property="电" value="-20" duration="300"
 *         buffId="破防_电抗"/>
 *
 * <!-- 减益示例：电抗倍率 0.5，抗性减半（仅当抗性为正时才是易伤，见下方方向陷阱） -->
 * <effect type="resistanceBuff" property="电" mult_positive="0.5" duration="300"
 *         buffId="脆化_电抗"/>
 *
 * - value: 固定点数，正负皆可；0 视为未提供
 * - mult_positive: 乘区倍率，参数名与 BuffEffect 的 calc="mult_positive" 保持一致，
 *   即 value 就是倍率本身：2.2 = ×2.2（+120%）；正负皆可，1 视为未提供
 * - property: 单一抗性名（电/热/冷/波/蚀/毒/冲/基础），不填则为全属性
 * - value 与 mult_positive 至少给一个，可同时给出，共用同一 MetaBuff
 */
class org.flashNight.arki.item.drug.effects.ResistanceBuffEffect implements IDrugEffect {

    public function ResistanceBuffEffect() {
    }

    public function getType():String {
        return "resistanceBuff";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var target:Object = ctx.target;
        if (!target.buffManager || !target.魔法抗性) {
            trace("[ResistanceBuffEffect] 目标缺少buffManager或魔法抗性");
            return false;
        }

        // 固定点数（value）与乘区倍率（mult_positive）至少要给出一个有效值。
        // 用 NaN 表示"未提供"：0 点与 1 倍率均无实际效果，等同于未提供；
        // 负值（负抗性 = 易伤）是合法取值，不得当作无效拦下。
        // 属性缺失或写成空串时不得当成 0 倍率，否则会误把抗性清零
        var rawValue:Number = (effectData.value == undefined || effectData.value == "")
            ? NaN : Number(effectData.value);
        var value:Number = NaN;
        if (!isNaN(rawValue) && rawValue != 0) value = rawValue;

        var rawMult:Number = (effectData.mult_positive == undefined || effectData.mult_positive == "")
            ? NaN : Number(effectData.mult_positive);
        var mult:Number = NaN;
        if (!isNaN(rawMult) && rawMult != 1) mult = rawMult;

        if (isNaN(value) && isNaN(mult)) {
            trace("[ResistanceBuffEffect] value/mult_positive 均无效: "
                + effectData.value + " / " + effectData.mult_positive);
            return false;
        }

        var duration:Number = Number(effectData.duration);
        if (!isFinite(duration) || duration < 0) duration = 0;

        var buffId:String = effectData.buffId;
        if (!buffId || buffId.length == 0) {
            buffId = "药剂_全抗_" + getTimer() + "_" + Math.floor(Math.random() * 1000);
        }

        // property 指定时只作用于单一抗性，否则作用于全属性（七属性 + 基础）
        var property:String = effectData.property;
        var resistanceKeys:Array;
        if (property && property.length > 0) {
            resistanceKeys = [property];
        } else {
            resistanceKeys = ["电", "热", "冷", "波", "蚀", "毒", "冲", "基础"];
        }

        var childBuffs:Array = [];
        for (var i:Number = 0; i < resistanceKeys.length; i++) {
            var path:String = "魔法抗性." + resistanceKeys[i];
            // 按符号分流到保守语义的正/负类型：正向取 max，负向取 min
            if (!isNaN(value)) {
                childBuffs.push(new PodBuff(
                    path,
                    (value > 0) ? BuffCalculationType.ADD_POSITIVE
                                : BuffCalculationType.ADD_NEGATIVE,
                    value
                ));
            }
            if (!isNaN(mult)) {
                childBuffs.push(new PodBuff(
                    path,
                    (mult > 1) ? BuffCalculationType.MULT_POSITIVE
                               : BuffCalculationType.MULT_NEGATIVE,
                    mult
                ));
            }
        }

        var components:Array = [];
        if (duration > 0) components.push(new TimeLimitComponent(duration));

        var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);
        var registeredId:String = target.buffManager.addBuff(metaBuff, buffId);
        ctx.registerDomainBuffId(registeredId);
        target.buffManager.update(0);
        return true;
    }
}
