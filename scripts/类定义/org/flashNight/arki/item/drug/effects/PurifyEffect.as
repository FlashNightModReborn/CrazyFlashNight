import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * PurifyEffect - 净化效果词条
 *
 * 保护麻痹抗性，并缩短或移除仍处于计时中的 debuff_ 状态。
 *
 * XML配置示例:
 * <effect type="purify" value="50" scaleWithAlchemy="true" />
 * <effect type="purify" value="15" target="group" />
 *
 * 参数说明:
 * - value: 净化强度值
 * - target: 作用范围（"self" 默认单体；"group" 作用于友军缓存中的自身及存活友军）
 * - scaleWithAlchemy: 是否应用炼金加成（默认 true）
 * - paralysisMultiplier: 麻痹值倍率（默认 -10），保留原值与倍率乘积中较低者
 *
 * @author FlashNight
 * @version 2.0
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
        // XMLParser 会把 "true"/"false" 转成 Boolean，需要同时兼容两种情况。
        var scaleWithAlchemy:Boolean = (effectData.scaleWithAlchemy !== false && effectData.scaleWithAlchemy != "false");
        if (scaleWithAlchemy) {
            value = ctx.calcPurifyWithAlchemy(value);
        }
        if (isNaN(value) || !isFinite(value) || !(value > 0)) return true;

        var paralysisMultiplier:Number = Number(effectData.paralysisMultiplier);
        if (isNaN(paralysisMultiplier) || !isFinite(paralysisMultiplier)) paralysisMultiplier = -10;
        var paralysisFloor:Number = paralysisMultiplier * value;
        var hasParalysisFloor:Boolean = !isNaN(paralysisFloor) && isFinite(paralysisFloor);

        var caster:Object = ctx.target;
        var isGroup:Boolean = (effectData.target == "group");
        var snapshot:Array;
        var casterUid:Number;
        var memberUids:Array;
        if (isGroup) {
            if (typeof caster == "movieclip") {
                if (caster._parent == undefined || caster._deInitialized === true) return true;
                casterUid = Dictionary.getStaticUID(caster);
            }
            var allies:Array = TargetCacheManager.getCachedAlly(caster, 5);
            if (!allies || allies.length == 0) return true;
            snapshot = allies.slice();

            // AVM1 的旧 MovieClip 引用可能指向同路径的新单位，施放前一并捕获实例身份。
            memberUids = [];
            for (var j:Number = 0; j < snapshot.length; j++) {
                var member:Object = snapshot[j];
                if (typeof member == "movieclip" && member._parent != undefined) {
                    memberUids[j] = Dictionary.getStaticUID(member);
                }
            }
        } else {
            snapshot = [caster];
        }

        for (var i:Number = 0; i < snapshot.length; i++) {
            var unit:Object = snapshot[i];
            if (!unit) continue;
            if (isGroup) {
                if (casterUid !== undefined && (caster._parent == undefined ||
                    caster._deInitialized === true || caster.__dictUID !== casterUid)) break;
                if (!(unit.hp > 0) || unit._deInitialized === true) continue;
                if (typeof unit == "movieclip" && (unit._parent == undefined ||
                    memberUids[i] === undefined ||
                    unit.__dictUID !== memberUids[i])) continue;
                if (unit !== caster && !FactionManager.areUnitsAllies(caster, unit)) continue;
            }

            if (hasParalysisFloor) {
                var curParalysis:Number = Number(unit.麻痹值);
                if (unit.麻痹值 == undefined || unit.麻痹值 == null || isNaN(curParalysis) || curParalysis > paralysisFloor) {
                    unit.麻痹值 = paralysisFloor;
                }
            }

            var buffManager:BuffManager = unit.buffManager;
            if (buffManager) {
                var purifyResult:Object = buffManager.purifyDebuffs(value);
                if (purifyResult && purifyResult.removed > 0) {
                    buffManager.update(0);
                }
            }
        }

        return true;
    }
}
