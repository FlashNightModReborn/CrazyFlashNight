import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

/**
 * ToughnessBuffEffect - 以装备 toughness 口径施加临时韧性增益。
 *
 * 装备初始化公式为：韧性系数 = 基础韧性系数 × (1 + toughness / 100)。
 * 因此 XML 的 value 继续填写装备 toughness 点数；运行时把它换算成
 * “基础韧性系数 × value / 100”的加法 Buff。这样不会把既有装备
 * toughness 再乘一次，换装时也仍由 BuffManager 保留临时增量。
 *
 * XML配置示例:
 * <effect type="toughnessBuff" value="2750" duration="300"
 *         buffId="九龙_狴犴_韧性"/>
 */
class org.flashNight.arki.item.drug.effects.ToughnessBuffEffect implements IDrugEffect {

    public function ToughnessBuffEffect() {
    }

    public function getType():String {
        return "toughnessBuff";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var target:Object = ctx.target;
        if (!target.buffManager) {
            trace("[ToughnessBuffEffect] 目标没有buffManager");
            return false;
        }

        var value:Number = Number(effectData.value);
        if (!isFinite(value) || value <= 0) {
            trace("[ToughnessBuffEffect] 无效的value: " + effectData.value);
            return false;
        }

        var duration:Number = Number(effectData.duration);
        if (!isFinite(duration) || duration < 0) duration = 0;

        var buffId:String = effectData.buffId;
        if (!buffId || buffId.length == 0) {
            buffId = "药剂_韧性系数_" + getTimer() + "_" + Math.floor(Math.random() * 1000);
        }

        var baseToughness:Number = Number(target.基础韧性系数);
        if (!isFinite(baseToughness) || baseToughness <= 0) {
            trace("[ToughnessBuffEffect] 无效的基础韧性系数: " + target.基础韧性系数);
            return false;
        }

        // 装备 toughness 是对“基础韧性系数”的线性增量，不是对已含装备值的乘算。
        var toughnessDelta:Number = baseToughness * value / 100;
        var childBuffs:Array = [
            new PodBuff("韧性系数", BuffCalculationType.ADD_POSITIVE, toughnessDelta)
        ];
        var components:Array = [];
        if (duration > 0) components.push(new TimeLimitComponent(duration));

        var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);
        var registeredId:String = target.buffManager.addBuff(metaBuff, buffId);
        ctx.registerDomainBuffId(registeredId);
        target.buffManager.update(0);
        return true;
    }
}
