
/**
 * PlayerInfoProvider 的领域专用结构化投影叶。
 *
 * 只负责把既有 getter 结果编排为稳定、无 HTML、无 MovieClip 布局信息的数据。
 * 不持有 hero 引用，不实现第二套属性公式。
 */
class org.flashNight.arki.unit.PlayerInfoSnapshotBuilder {

    public static function build(unit:MovieClip):Object {
        if (!unit) return unavailable("hero_not_found");

        var titleProjection:Object =
            org.flashNight.arki.unit.PlayerInfoProvider.getTitleProjection(unit);
        var groups:Array = [
            group("profile", "基础信息", [
                row("height", "身高", org.flashNight.arki.unit.PlayerInfoProvider.getHeightValue(unit), "cm", "integer"),
                row("bodyWeight", "体重", org.flashNight.arki.unit.PlayerInfoProvider.getBodyWeightValue(unit), "kg", "integer"),
                row("killCount", "杀敌数", org.flashNight.arki.unit.PlayerInfoProvider.getKillCountValue(unit), "", "integer"),
                styledRow("title", "称号", titleProjection.text, "",
                    "styled-text", titleProjection.spans),
                row("level", "等级", org.flashNight.arki.unit.PlayerInfoProvider.getLevelValue(), "", "integer"),
                row("experience", "经验值", org.flashNight.arki.unit.PlayerInfoProvider.getExperienceValue(), "", "integer")
            ]),
            group("encumbrance", "负重", [
                row("equipmentWeight", "装备重量",
                    org.flashNight.arki.unit.PlayerInfoProvider.getEquipmentWeightValue(unit), "kg", "number"),
                row("lightMediumThreshold", "轻甲/中甲阈值",
                    org.flashNight.arki.unit.PlayerInfoProvider.getBaseEncumbranceValue(unit), "kg", "number"),
                row("mediumHeavyThreshold", "中甲/重甲阈值",
                    org.flashNight.arki.unit.PlayerInfoProvider.getMediumHeavyEncumbranceValue(unit), "kg", "number"),
                row("heavyThreshold", "最大负重",
                    org.flashNight.arki.unit.PlayerInfoProvider.getHeavyEncumbranceValue(unit), "kg", "number"),
                row("weightRatio", "负重比例",
                    org.flashNight.arki.unit.PlayerInfoProvider.getEncumbranceRatio(unit), "", "ratio-3"),
                row("encumbranceState", "负重状态",
                    org.flashNight.arki.unit.PlayerInfoProvider.getEncumbranceState(unit), "", "enum")
            ]),
            group("vitals", "生命与能量", [
                row("maxHp", "最大HP", org.flashNight.arki.unit.PlayerInfoProvider.getMaxHP(unit), "", "integer"),
                row("maxMp", "最大MP", org.flashNight.arki.unit.PlayerInfoProvider.getMaxMP(unit), "", "integer"),
                row("innerPower", "内力", org.flashNight.arki.unit.PlayerInfoProvider.getInnerPower(unit), "", "integer")
            ]),
            group("resistance", "魔法抗性", [
                row("energyResistance", "能量抗性",
                    org.flashNight.arki.unit.PlayerInfoProvider.getEnergyResistance(unit), "", "integer"),
                row("heatResistance", "热抗性",
                    org.flashNight.arki.unit.PlayerInfoProvider.getHeatResistance(unit), "", "integer"),
                row("corrosionResistance", "蚀抗性",
                    org.flashNight.arki.unit.PlayerInfoProvider.getCorrosionResistance(unit), "", "integer"),
                row("poisonResistance", "毒抗性",
                    org.flashNight.arki.unit.PlayerInfoProvider.getPoisonResistance(unit), "", "integer"),
                row("coldResistance", "冷抗性",
                    org.flashNight.arki.unit.PlayerInfoProvider.getColdResistance(unit), "", "integer"),
                row("lightningResistance", "电抗性",
                    org.flashNight.arki.unit.PlayerInfoProvider.getLightningResistance(unit), "", "integer"),
                row("waveResistance", "波抗性",
                    org.flashNight.arki.unit.PlayerInfoProvider.getWaveResistance(unit), "", "integer"),
                row("impactResistance", "冲抗性",
                    org.flashNight.arki.unit.PlayerInfoProvider.getImpactResistance(unit), "", "integer")
            ]),
            group("defense", "防御", [
                row("totalDefense", "综合防御力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getTotalDefense(unit), "", "integer"),
                row("baseDefense", "基本防御",
                    org.flashNight.arki.unit.PlayerInfoProvider.getBaseDefense(unit), "", "integer"),
                row("equipmentDefense", "装备防御",
                    org.flashNight.arki.unit.PlayerInfoProvider.getEquipmentDefenseBase(unit), "", "integer"),
                row("equipmentDefenseBonus", "装备防御加成",
                    org.flashNight.arki.unit.PlayerInfoProvider.getEquipmentDefenseBonus(unit), "", "signed-integer"),
                row("damageReduction", "减伤率",
                    org.flashNight.arki.unit.PlayerInfoProvider.getDamageReductionValue(unit), "%", "percent-1")
            ]),
            group("tenacity", "韧性", [
                row("tenacityLimit", "韧性上限",
                    org.flashNight.arki.unit.PlayerInfoProvider.getTenacityLimitValue(unit), "", "compact-number-1"),
                row("staggerTenacity", "踉跄韧性",
                    org.flashNight.arki.unit.PlayerInfoProvider.getStaggerTenacityValue(unit), "", "compact-number-1"),
                row("guardBreakAbility", "拆挡能力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getGuardBreakAbility(unit), "", "integer"),
                row("stabilityAbility", "坚稳能力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getStabilityAbility(unit), "", "integer")
            ]),
            group("mobility", "命中与移动", [
                row("accuracy", "命中力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getAccuracy(unit), "", "integer"),
                row("evasionCost", "闪避负荷",
                    org.flashNight.arki.unit.PlayerInfoProvider.getEvasionCost(unit), "", "integer"),
                row("lazyDodge", "懒闪避",
                    org.flashNight.arki.unit.PlayerInfoProvider.getLazyDodge(unit), "%", "percent-0"),
                row("movementSpeed", "速度",
                    org.flashNight.arki.unit.PlayerInfoProvider.getMovementSpeedValue(unit), "m/s", "decimal-1")
            ]),
            group("offense", "伤害加成", [
                row("damageBonus", "伤害加成",
                    org.flashNight.arki.unit.PlayerInfoProvider.getDamageBonus(unit), "", "integer"),
                row("unarmedBonus", "空手加成",
                    org.flashNight.arki.unit.PlayerInfoProvider.getUnarmedBonus(unit), "", "signed-integer"),
                row("unarmedAttack", "空手攻击力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getUnarmedAttack(unit), "", "integer"),
                row("meleeBonus", "冷兵加成",
                    org.flashNight.arki.unit.PlayerInfoProvider.getMeleeBonus(unit), "", "signed-number"),
                row("firearmBonus", "枪械加成",
                    org.flashNight.arki.unit.PlayerInfoProvider.getFirearmBonus(unit), "", "signed-number")
            ]),
            group("power", "武器威力", [
                row("unarmedPower", "空手威力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getUnarmedPower(unit), "", "integer"),
                row("meleePower", "冷兵威力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getMeleePower(unit), "", "integer"),
                row("mainHandPower", "主手威力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getMainHandPower(unit), "", "integer"),
                row("offHandPower", "副手威力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getOffHandPower(unit), "", "integer"),
                row("riflePower", "长枪威力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getRiflePower(unit), "", "integer"),
                row("grenadePower", "手雷威力",
                    org.flashNight.arki.unit.PlayerInfoProvider.getGrenadePower(unit), "", "integer")
            ])
        ];

        var invalidKey:String = findInvalidRow(groups);
        if (invalidKey != null) return unavailable("invalid_row:" + invalidKey);
        return {
            v:1,
            stateHealth:"ok",
            diagnostics:[],
            groups:groups
        };
    }

    public static function unavailable(reason:String):Object {
        return {
            v:1,
            stateHealth:"unavailable",
            diagnostics:[reason],
            groups:[]
        };
    }

    private static function group(key:String, label:String, rows:Array):Object {
        return {key:key, label:label, rows:rows};
    }

    private static function row(key:String, label:String, value,
                                unit:String, displayHint:String):Object {
        return {
            key:key,
            label:label,
            value:value,
            unit:unit,
            displayHint:displayHint
        };
    }

    private static function styledRow(key:String, label:String, value:String,
                                      unit:String, displayHint:String,
                                      spans:Array):Object {
        return {
            key:key,
            label:label,
            value:value,
            unit:unit,
            displayHint:displayHint,
            spans:spans
        };
    }

    private static function findInvalidRow(groups:Array):String {
        for (var i:Number = 0; i < groups.length; i++) {
            var rows:Array = groups[i].rows;
            for (var j:Number = 0; j < rows.length; j++) {
                var item:Object = rows[j];
                if (!item || !item.key || !item.label
                    || item.value == null || item.unit == null
                    || !item.displayHint) {
                    return item && item.key ? String(item.key) : "unknown";
                }
                var valueType:String = typeof(item.value);
                if (valueType != "number" && valueType != "string"
                    && valueType != "boolean") {
                    return String(item.key);
                }
                if (valueType == "number" && (item.value - item.value) != 0) {
                    return String(item.key);
                }
                if (valueType == "string"
                    && (String(item.value).indexOf("<") >= 0
                        || String(item.value).indexOf(">") >= 0)) {
                    return String(item.key);
                }
                if (item.spans != undefined && !isValidStyledRow(item)) {
                    return String(item.key);
                }
            }
        }
        return null;
    }

    private static function isValidStyledRow(item:Object):Boolean {
        if (item.key != "title" || item.displayHint != "styled-text"
            || !(item.spans instanceof Array)) {
            return false;
        }

        var parts:Array = [];
        for (var i:Number = 0; i < item.spans.length; i++) {
            var span:Object = item.spans[i];
            if (!span || typeof(span.text) != "string"
                || span.text.indexOf("<") >= 0 || span.text.indexOf(">") >= 0) {
                return false;
            }
            if (span.color != undefined
                && !isSafeColor(String(span.color))) {
                return false;
            }
            if (span.size != undefined) {
                var size:Number = Number(span.size);
                if ((size - size) != 0 || size < 1 || size > 72
                    || Math.floor(size) != size) {
                    return false;
                }
            }
            parts.push(span.text);
        }
        return parts.join("") == String(item.value);
    }

    private static function isSafeColor(value:String):Boolean {
        if (value.length != 7 || value.charAt(0) != "#") return false;
        for (var i:Number = 1; i < 7; i++) {
            var code:Number = value.charCodeAt(i);
            var isHex:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 70)
                || (code >= 97 && code <= 102);
            if (!isHex) return false;
        }
        return true;
    }
}
