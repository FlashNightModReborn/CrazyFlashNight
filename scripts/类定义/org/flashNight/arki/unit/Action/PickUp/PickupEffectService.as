/**
 * 路径: org/flashNight/arki/unit/Action/PickUp/PickupEffectService.as
 *
 * PickupEffectService - 战场即时补给领取服务
 *
 * <use>战场补给</use> 的物品不进入背包：拾取瞬间由本服务现场结算药效词条，
 * 按实际收益决定整包是否消耗。设计契约见
 * docs/战场即时补给品-技术调研与首批施工准备-2026-09-12.md §13。
 *
 * 结果四态：
 *   "applied"   任一词条产生真实收益，整包消耗（调用方继续实体收尾）
 *   "noBenefit" 配置有效但零收益（如满血），实体保留，可重试
 *   "rejected"  前置拒绝（占用中/目标死亡/配置不支持），零写入，实体保留
 *   "tooFar"    距离不满足近距规则，静默，实体保留
 *
 * 键盘/鼠标拾取的距离规则收拢在本类，调用方不再各自判定。
 * supplyAmmo 词条本片仅识别不执行（下一片注册进 DrugEffectRegistry 前，
 * 含该词条的配置在配置校验按"配置不支持"前置拒绝，属预期行为）。
 */

import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.item.drug.DrugEffectNormalizer;
import org.flashNight.arki.item.drug.DrugEffectRegistry;
import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

class org.flashNight.arki.unit.Action.PickUp.PickupEffectService {

    /** 即时激活策略标识：物品 use 字段等于该值即视为战场补给 */
    public static var SUPPLY_USE:String = "战场补给";

    /** 允许出现在补给配置中的效果词条白名单（supplyAmmo 下一片注册，本片仅识别后拦截） */
    private static var ALLOWED_TYPES:Array =
        ["heal", "regen", "buff", "resistanceBuff", "supplyAmmo", "playEffect", "message"];

    /**
     * 物品是否为战场即时补给。
     */
    public static function isInstantSupply(itemName:String):Boolean {
        if (itemName == null || itemName.length == 0) return false;
        var itemData:Object = _root.getItemData(itemName);
        return itemData != null && itemData.use == SUPPLY_USE;
    }

    /**
     * 尝试为玩家本人领取一个战场补给实体。
     *
     * @param target 可拾取物 MovieClip（需带 物品名/Z轴坐标/area）
     * @return "applied" / "noBenefit" / "rejected" / "tooFar"
     */
    public static function tryClaim(target:MovieClip):String {
        // 同步领取占用：重复输入最前端退出；applied 时保持置位防止消耗前重入
        if (target._supplyClaimed === true) return "rejected";
        target._supplyClaimed = true;

        var outcome:String = claimInternal(target);
        if (outcome != "applied") target._supplyClaimed = false;
        return outcome;
    }

    private static function claimInternal(target:MovieClip):String {
        var hero:MovieClip = TargetCacheManager.findHero();
        if (hero == null || hero.area == undefined) return "rejected";

        // 距离判定：Z 轴差 <50 且 area.hitTest，不满足静默保留实体
        if (!(Math.abs(hero.Z轴坐标 - target.Z轴坐标) < 50) ||
                !hero.area.hitTest(target.area)) {
            return "tooFar";
        }
        if (!(hero.hp > 0)) return "rejected";

        var itemName:String = target.物品名;
        var itemData:Object = _root.getItemData(itemName);
        var effects:Array = DrugEffectNormalizer.normalize(itemData == null ? null : itemData.data);

        // 配置校验：任一词条不在白名单或尚未注册，整包前置拒绝（零写入）
        if (effects.length == 0) {
            trace("[PickupEffectService] 补给缺少效果配置: " + itemName);
            _root.发布消息("补给配置无效");
            return "rejected";
        }
        for (var i:Number = 0; i < effects.length; i++) {
            var effectType:String = effects[i] == null ? null : effects[i].type;
            if (!isAllowedType(effectType) || !DrugEffectRegistry.hasType(effectType)) {
                trace("[PickupEffectService] 补给配置不支持的效果词条: " + effectType + " (" + itemName + ")");
                _root.发布消息("补给配置无效");
                return "rejected";
            }
        }

        // 中性上下文：战场补给不吃炼金加成，强制 alchemyLevel=0
        var ctx:DrugContext = DrugContext.createWithData(itemName, hero, itemData);
        ctx.alchemyLevel = 0;

        // 逐条执行并统计真实收益；playEffect/message 执行但不计收益，
        // supplyAmmo 本片在配置校验即拦截，不会走到这里
        var benefits:Array = [];
        for (i = 0; i < effects.length; i++) {
            var effectData:Object = effects[i];
            var effect:IDrugEffect = DrugEffectRegistry.get(effectData.type);
            var hpBefore:Number = hero.hp;
            var mpBefore:Number = hero.mp;
            if (!effect.execute(ctx, effectData)) continue;

            switch (effectData.type) {
                case "heal":
                    var hpGain:Number = Math.round(hero.hp - hpBefore);
                    var mpGain:Number = Math.round(hero.mp - mpBefore);
                    if (hpGain > 0) benefits.push({kind: "healHp", value: hpGain});
                    if (mpGain > 0) benefits.push({kind: "healMp", value: mpGain});
                    break;
                case "buff":
                    benefits.push({kind: "buff", text: buffDescription(effectData)});
                    break;
                case "resistanceBuff":
                    benefits.push({kind: "resistance"});
                    break;
                case "regen":
                    benefits.push({kind: "regen"});
                    break;
            }
        }

        if (benefits.length == 0) {
            _root.发布消息("状态良好，无需补给");
            return "noBenefit";
        }

        _root.发布消息(buildAppliedMessage(itemName, benefits));
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
        return "applied";
    }

    private static function isAllowedType(effectType:String):Boolean {
        if (effectType == null) return false;
        for (var i:Number = 0; i < ALLOWED_TYPES.length; i++) {
            if (ALLOWED_TYPES[i] == effectType) return true;
        }
        return false;
    }

    private static function buffDescription(effectData:Object):String {
        var sign:String = effectData.calc == "add" ? "+" : "×";
        return String(effectData.property) + " " + sign + String(effectData.value);
    }

    /**
     * 领取收益文案的唯一收口。下一片 supplyAmmo 的弹药反馈在此扩展 "ammo" 分支。
     */
    private static function buildAppliedMessage(itemName:String, benefits:Array):String {
        var parts:Array = [];
        for (var i:Number = 0; i < benefits.length; i++) {
            var benefit:Object = benefits[i];
            switch (benefit.kind) {
                case "healHp":
                    parts.push("HP +" + benefit.value);
                    break;
                case "healMp":
                    parts.push("MP +" + benefit.value);
                    break;
                case "buff":
                    parts.push("已获得强化（" + benefit.text + "）");
                    break;
                case "resistance":
                    parts.push("已获得抗性强化");
                    break;
                case "regen":
                    parts.push("已获得持续恢复");
                    break;
                case "ammo":
                    parts.push("弹药已补充");
                    break;
            }
        }
        return itemName + "：" + parts.join("，");
    }
}
