import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

/**
 * ResistanceBuffEffect - 七种基础伤害属性的临时全抗增益。
 *
 * 魔法抗性是对象，不能交给普通 buff 词条当作一个数值属性处理。本词条
 * 使用 BuffManager 路径绑定，对电、热、冷、波、蚀、毒、冲分别施加同值
 * ADD_POSITIVE Buff。
 *
 * XML配置示例:
 * <effect type="resistanceBuff" value="10" duration="300"
 *         buffId="九龙_螭吻_全抗"/>
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

        var value:Number = Number(effectData.value);
        if (!isFinite(value) || value <= 0) {
            trace("[ResistanceBuffEffect] 无效的value: " + effectData.value);
            return false;
        }

        var duration:Number = Number(effectData.duration);
        if (!isFinite(duration) || duration < 0) duration = 0;

        var buffId:String = effectData.buffId;
        if (!buffId || buffId.length == 0) {
            buffId = "药剂_全抗_" + getTimer() + "_" + Math.floor(Math.random() * 1000);
        }

        var resistanceKeys:Array = ["电", "热", "冷", "波", "蚀", "毒", "冲"];
        var childBuffs:Array = [];
        for (var i:Number = 0; i < resistanceKeys.length; i++) {
            childBuffs.push(new PodBuff(
                "魔法抗性." + resistanceKeys[i],
                BuffCalculationType.ADD_POSITIVE,
                value
            ));
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
