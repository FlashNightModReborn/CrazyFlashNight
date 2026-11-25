// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/BuffTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let BuffTooltipBuilder;
    (function (BuffTooltipBuilder) {
        function build(ctx, effectData) {
            var result = [];
            var property = effectData.property;
            var calc = effectData.calc;
            var value = TooltipEngine.as2Number(effectData.value);
            var duration = TooltipEngine.as2Number(effectData.duration);
            if (!property || !calc || TooltipEngine.as2IsNaN(value))
                return result;
            var valueStr;
            switch (calc.toLowerCase()) {
                case "add":
                    valueStr = (TooltipEngine.as2GreaterEqual(value, 0) ? "+" : "") + value;
                    break;
                case "multiply":
                    valueStr = "×" + value;
                    break;
                case "percent":
                    var percentValue = value * 100;
                    valueStr = (TooltipEngine.as2GreaterEqual(percentValue, 0) ? "+" : "") + percentValue + "%";
                    break;
                case "override":
                    valueStr = "=" + value;
                    break;
                case "max":
                    valueStr = "≥" + value;
                    break;
                case "min":
                    valueStr = "≤" + value;
                    break;
                default:
                    valueStr = String(value);
            }
            result.push(TooltipEngine.DrugTooltipUtil.color(ctx, TooltipEngine.TooltipConstants.LBL_DRUG_BUFF + "：", TooltipEngine.TooltipConstants.COL_HL));
            result.push(property + " " + valueStr);
            if (!TooltipEngine.as2IsNaN(duration) && TooltipEngine.as2Greater(duration, 0)) {
                var durationSec = TooltipEngine.DrugTooltipUtil.framesToSeconds(ctx, duration);
                result.push("（" + durationSec + TooltipEngine.TooltipConstants.TIP_DRUG_SECOND + "）");
            }
            result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            return result;
        }
        BuffTooltipBuilder.build = build;
    })(BuffTooltipBuilder = TooltipEngine.BuffTooltipBuilder || (TooltipEngine.BuffTooltipBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/CommonStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let CommonStatsBuilder;
    (function (CommonStatsBuilder) {
        const ACTION_TYPE_USES = {
            刀: true,
            手部装备: true
        };
        function build(ctx, result, baseItem, item, data, equipData, nativeOpt) {
            var slayTarget = result;
            if (TooltipEngine.as2NotEqual(nativeOpt, null) && nativeOpt.omitCritSlay === true && TooltipEngine.as2NotEqual(nativeOpt.critSlay, null)) {
                slayTarget = nativeOpt.critSlay;
            }
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "force", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "damage", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "punch", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "knifepower", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "gunpower", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "accuracy", null, TooltipEngine.TooltipConstants.SUF_PERCENT);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "evasion", null, TooltipEngine.TooltipConstants.SUF_PERCENT);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "toughness", null, TooltipEngine.TooltipConstants.SUF_PERCENT);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "lazymiss", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "poison", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "vampirism", null, TooltipEngine.TooltipConstants.SUF_PERCENT);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "rout", null, TooltipEngine.TooltipConstants.SUF_PERCENT);
            TooltipEngine.TooltipFormatter.upgradeLine(slayTarget, data, equipData, "slay", null, TooltipEngine.TooltipConstants.SUF_BLOOD);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "defence", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "hp", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "mp", null, null);
            if (ACTION_TYPE_USES[item.use] === true
                && (TooltipEngine.as2Equal(nativeOpt, null) || nativeOpt.omitActionType !== true)) {
                var finalActionType = null;
                var originalActionType = item.actiontype;
                if (baseItem && TooltipEngine.as2NotEqual(baseItem.getData, undefined)) {
                    var calculatedData = baseItem.getData();
                    if (calculatedData && calculatedData.actiontype !== undefined) {
                        finalActionType = calculatedData.actiontype;
                    }
                }
                if (TooltipEngine.as2Equal(finalActionType, null)) {
                    finalActionType = originalActionType;
                }
                if (finalActionType === undefined) {
                    finalActionType = "默认";
                }
                var isOverridden = (originalActionType !== undefined && TooltipEngine.as2NotEqual(finalActionType, originalActionType));
                if (isOverridden) {
                    result.push(TooltipEngine.TooltipConstants.LBL_ACTION, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", finalActionType, "</FONT>");
                    result.push(" <FONT COLOR='", TooltipEngine.TooltipConstants.COL_INFO, "'>(←", originalActionType, ")</FONT><BR>");
                }
                else {
                    result.push(TooltipEngine.TooltipConstants.LBL_ACTION, "：", finalActionType, "<BR>");
                }
            }
        }
        CommonStatsBuilder.build = build;
    })(CommonStatsBuilder = TooltipEngine.CommonStatsBuilder || (TooltipEngine.CommonStatsBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/CriticalBlockBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let CriticalBlockBuilder;
    (function (CriticalBlockBuilder) {
        function build(ctx, result, baseItem, item, data, equipData) {
            var critData = equipData ? equipData : data;
            if (!critData.criticalhit) {
                return;
            }
            var criticalhit = critData.criticalhit;
            if (!TooltipEngine.as2IsNaN(TooltipEngine.as2Number(criticalhit))) {
                result.push("<FONT COLOR='", TooltipEngine.TooltipConstants.COL_CRIT, "'>", TooltipEngine.TooltipConstants.LBL_CRIT, "：</FONT><FONT COLOR='", TooltipEngine.TooltipConstants.COL_CRIT, "'>", criticalhit, TooltipEngine.TooltipConstants.SUF_PERCENT, TooltipEngine.TooltipConstants.TIP_CRIT_CHANCE, "</FONT><BR>");
            }
            else if (criticalhit === TooltipEngine.TooltipConstants.TIP_CRIT_FULL_HP) {
                result.push("<FONT COLOR='", TooltipEngine.TooltipConstants.COL_CRIT, "'>", TooltipEngine.TooltipConstants.LBL_CRIT, "：", TooltipEngine.TooltipConstants.TIP_CRIT_FULL_HP_DESC, "</FONT><BR>");
            }
        }
        CriticalBlockBuilder.build = build;
    })(CriticalBlockBuilder = TooltipEngine.CriticalBlockBuilder || (TooltipEngine.CriticalBlockBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/DamageTypeBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let DamageTypeBuilder;
    (function (DamageTypeBuilder) {
        function build(ctx, result, baseItem, item, data, equipData) {
            var baseDamageType = data ? data.damagetype : null;
            var baseMagicType = data ? data.magictype : null;
            var finalDamageType = equipData ? equipData.damagetype : baseDamageType;
            var finalMagicType = equipData ? equipData.magictype : baseMagicType;
            if (!finalDamageType) {
                return;
            }
            var hasOverride = TooltipEngine.as2NotEqual(equipData, null) && (TooltipEngine.as2NotEqual(finalDamageType, baseDamageType) || TooltipEngine.as2NotEqual(finalMagicType, baseMagicType));
            if (hasOverride) {
                buildWithOverride(ctx, result, baseDamageType, baseMagicType, finalDamageType, finalMagicType);
            }
            else {
                buildNormal(ctx, result, finalDamageType, finalMagicType);
            }
        }
        DamageTypeBuilder.build = build;
        function buildNormal(ctx, result, damageType, magicType) {
            if (TooltipEngine.as2Equal(damageType, TooltipEngine.TooltipConstants.TXT_MAGIC) && magicType) {
                TooltipEngine.TooltipFormatter.colorLine(result, TooltipEngine.TooltipConstants.COL_DMG, TooltipEngine.TooltipConstants.LBL_DAMAGE_ATTR + "：" + magicType);
            }
            else if (TooltipEngine.as2Equal(damageType, TooltipEngine.TooltipConstants.TXT_BREAK) && magicType) {
                if (TooltipEngine.isMagicDamage(ctx, magicType)) {
                    TooltipEngine.TooltipFormatter.colorLine(result, TooltipEngine.TooltipConstants.COL_BREAK_LIGHT, TooltipEngine.TooltipConstants.LBL_EXTRA_DAMAGE + "：" + magicType);
                }
                else {
                    TooltipEngine.TooltipFormatter.colorLine(result, TooltipEngine.TooltipConstants.COL_BREAK_MAIN, TooltipEngine.TooltipConstants.LBL_BREAK_TYPE + "：" + magicType);
                }
            }
            else {
                TooltipEngine.TooltipFormatter.colorLine(result, TooltipEngine.TooltipConstants.COL_DMG, TooltipEngine.TooltipConstants.LBL_DAMAGE_TYPE + "：" + (TooltipEngine.as2Equal(damageType, TooltipEngine.TooltipConstants.TXT_MAGIC) ? TooltipEngine.TooltipConstants.TXT_ENERGY : damageType));
            }
        }
        function buildWithOverride(ctx, result, baseDamageType, baseMagicType, finalDamageType, finalMagicType) {
            var label;
            var color;
            var finalDisplay;
            if (TooltipEngine.as2Equal(finalDamageType, TooltipEngine.TooltipConstants.TXT_MAGIC) && finalMagicType) {
                label = TooltipEngine.TooltipConstants.LBL_DAMAGE_ATTR;
                color = TooltipEngine.TooltipConstants.COL_DMG;
                finalDisplay = finalMagicType;
            }
            else if (TooltipEngine.as2Equal(finalDamageType, TooltipEngine.TooltipConstants.TXT_BREAK) && finalMagicType) {
                if (TooltipEngine.isMagicDamage(ctx, finalMagicType)) {
                    label = TooltipEngine.TooltipConstants.LBL_EXTRA_DAMAGE;
                    color = TooltipEngine.TooltipConstants.COL_BREAK_LIGHT;
                }
                else {
                    label = TooltipEngine.TooltipConstants.LBL_BREAK_TYPE;
                    color = TooltipEngine.TooltipConstants.COL_BREAK_MAIN;
                }
                finalDisplay = finalMagicType;
            }
            else {
                label = TooltipEngine.TooltipConstants.LBL_DAMAGE_TYPE;
                color = TooltipEngine.TooltipConstants.COL_DMG;
                finalDisplay = (TooltipEngine.as2Equal(finalDamageType, TooltipEngine.TooltipConstants.TXT_MAGIC) ? TooltipEngine.TooltipConstants.TXT_ENERGY : finalDamageType);
            }
            var baseDisplay = getTypeDisplayString(ctx, baseDamageType, baseMagicType);
            result.push("<FONT COLOR='", color, "'>", label, "：</FONT>");
            result.push("<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", finalDisplay, "</FONT>");
            result.push(" <FONT COLOR='", TooltipEngine.TooltipConstants.COL_INFO, "'>(←", baseDisplay, ")</FONT><BR>");
        }
        function getTypeDisplayString(ctx, damageType, magicType) {
            if (!damageType) {
                return TooltipEngine.TooltipConstants.TXT_NONE;
            }
            if (TooltipEngine.as2Equal(damageType, TooltipEngine.TooltipConstants.TXT_MAGIC)) {
                if (magicType) {
                    return TooltipEngine.TooltipConstants.LBL_DAMAGE_ATTR + ":" + magicType;
                }
                return TooltipEngine.TooltipConstants.TXT_ENERGY;
            }
            if (TooltipEngine.as2Equal(damageType, TooltipEngine.TooltipConstants.TXT_BREAK)) {
                if (magicType) {
                    if (TooltipEngine.isMagicDamage(ctx, magicType)) {
                        return TooltipEngine.TooltipConstants.LBL_EXTRA_DAMAGE + ":" + magicType;
                    }
                    else {
                        return TooltipEngine.TooltipConstants.LBL_BREAK_TYPE + ":" + magicType;
                    }
                }
                return TooltipEngine.TooltipConstants.TXT_BREAK;
            }
            return damageType;
        }
    })(DamageTypeBuilder = TooltipEngine.DamageTypeBuilder || (TooltipEngine.DamageTypeBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/DrugTooltipComposer.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let DrugTooltipComposer;
    (function (DrugTooltipComposer) {
        function compose(ctx, item, buffBuffer) {
            if (!item || !item.data)
                return [];
            var effects = ctx.projection.drugEffects;
            if (TooltipEngine.as2Equal(effects.length, 0)) {
                return [];
            }
            if (TooltipEngine.as2Equal(buffBuffer, null))
                return TooltipEngine.DrugTooltipRegistry.buildAll(ctx, effects);
            var main = [];
            var buff = [];
            for (var i = 0; TooltipEngine.as2Less(i, effects.length); i++) {
                var fragments = TooltipEngine.DrugTooltipRegistry.buildOne(ctx, effects[i]);
                if (TooltipEngine.as2Equal(fragments, null) || TooltipEngine.as2Equal(fragments.length, 0))
                    continue;
                if (isBuffEffect(ctx, effects[i].type))
                    buff = buff.concat(fragments);
                else
                    main = main.concat(fragments);
            }
            for (var j = 0; TooltipEngine.as2Less(j, buff.length); j++)
                buffBuffer.push(buff[j]);
            return main;
        }
        DrugTooltipComposer.compose = compose;
        function isBuffEffect(ctx, type) {
            return TooltipEngine.as2Equal(type, "buff") || TooltipEngine.as2Equal(type, "toughnessBuff")
                || TooltipEngine.as2Equal(type, "resistanceBuff") || TooltipEngine.as2Equal(type, "regen");
        }
    })(DrugTooltipComposer = TooltipEngine.DrugTooltipComposer || (TooltipEngine.DrugTooltipComposer = {}));
})(TooltipEngine || (TooltipEngine = {}));
var TooltipEngine;
(function (TooltipEngine) {
    /** Closed display dispatch. No mutable registration API or per-request builder objects. */
    let DrugTooltipRegistry;
    (function (DrugTooltipRegistry) {
        function buildOne(ctx, effect) {
            if (!effect || effect.tooltip === false || effect.tooltip === 'false')
                return [];
            switch (effect.type) {
                case 'heal': return TooltipEngine.HealTooltipBuilder.build(ctx, effect);
                case 'regen': return TooltipEngine.RegenTooltipBuilder.build(ctx, effect);
                case 'state': return TooltipEngine.StateTooltipBuilder.build(ctx, effect);
                case 'purify': return TooltipEngine.PurifyTooltipBuilder.build(ctx, effect);
                case 'buff': return TooltipEngine.BuffTooltipBuilder.build(ctx, effect);
                case 'toughnessBuff': return TooltipEngine.ToughnessBuffTooltipBuilder.build(ctx, effect);
                case 'resistanceBuff': return TooltipEngine.ResistanceBuffTooltipBuilder.build(ctx, effect);
                case 'restoreToughness': return TooltipEngine.ToughnessRestoreTooltipBuilder.build(ctx, effect);
                case 'grantItem': return TooltipEngine.GrantItemTooltipBuilder.build(ctx, effect);
                default: return [];
            }
        }
        DrugTooltipRegistry.buildOne = buildOne;
        function buildAll(ctx, effects) {
            const result = [];
            for (const effect of effects || [])
                result.push(...buildOne(ctx, effect));
            return result;
        }
        DrugTooltipRegistry.buildAll = buildAll;
    })(DrugTooltipRegistry = TooltipEngine.DrugTooltipRegistry || (TooltipEngine.DrugTooltipRegistry = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/DrugTooltipUtil.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let DrugTooltipUtil;
    (function (DrugTooltipUtil) {
        DrugTooltipUtil.FPS = 30;
        function framesToSeconds(ctx, frames) {
            if (TooltipEngine.as2IsNaN(frames) || TooltipEngine.as2LessEqual(frames, 0))
                return "0";
            var seconds = frames / DrugTooltipUtil.FPS;
            if (TooltipEngine.as2Equal(seconds, Math.floor(seconds))) {
                return String(Math.floor(seconds));
            }
            return String(Math.round(seconds * 10) / 10);
        }
        DrugTooltipUtil.framesToSeconds = framesToSeconds;
        function formatValue(ctx, value) {
            if (TooltipEngine.as2Equal(value, null) || TooltipEngine.as2Equal(value, undefined))
                return "0";
            var strValue = String(value);
            if (TooltipEngine.as2GreaterEqual(strValue.indexOf("%"), 0)) {
                return strValue;
            }
            var num = TooltipEngine.as2Number(value);
            return TooltipEngine.as2IsNaN(num) ? "0" : String(num);
        }
        DrugTooltipUtil.formatValue = formatValue;
        function alchemyTag(ctx, scaleWithAlchemy) {
            if (!scaleWithAlchemy) {
                return "<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>" + TooltipEngine.TooltipConstants.LBL_DRUG_NO_ALCHEMY + "</FONT>";
            }
            return "";
        }
        DrugTooltipUtil.alchemyTag = alchemyTag;
        function color(ctx, text, col) {
            return "<FONT COLOR='" + col + "'>" + text + "</FONT>";
        }
        DrugTooltipUtil.color = color;
        function br(ctx) {
            return "<BR>";
        }
        DrugTooltipUtil.br = br;
    })(DrugTooltipUtil = TooltipEngine.DrugTooltipUtil || (TooltipEngine.DrugTooltipUtil = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/EquipmentLightingInfoBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let EquipmentLightingInfoBuilder;
    (function (EquipmentLightingInfoBuilder) {
        const bladeOrder = ["static", "blood", "vocalist", "libra", "inductor", "lion", "capricorn"];
        const bladeText = [
            "持用兵器时照亮近处，收起后熄灭。",
            "拔剑时照亮近处，收剑或收起后熄灭。",
            "光剑形态展开时照亮近处，亮度随展开程度变化。",
            "默认形态在战技冷却期间发光；攻势与守御形态保持照明并改变光色。收起后熄灭。",
            "刀刃展开时照亮近处，亮度随展开程度变化，过载时改变光色。",
            "兵器激活期间照亮近处，失活或收起后熄灭。",
            "兵器激活窗口内照亮近处，窗口结束或收起后熄灭。"
        ];
        function build(ctx, item, mods, standaloneMod) {
            var life = item.lifecycle;
            var result = [];
            if (!life || Array.isArray(life) || TooltipEngine.as2NotEqual(typeof life, "object"))
                return result;
            var body = false, headlamp = false, torch = false, laser = false;
            var blades = [], baseBonus = 0, electricBonus = 0, activeBonus = 0;
            var electric = false, tagsRead = false;
            for (var key of TooltipEngine.as2Keys(life)) {
                if (!life.hasOwnProperty(key))
                    continue;
                var attr = life[key], routine = attr?.init?.initRoutines, param = attr?.init?.initParam;
                if (!param)
                    continue;
                if (TooltipEngine.as2NotEqual(param.energy, undefined) && !(TooltipEngine.as2Greater(TooltipEngine.as2Number(param.energy), 0)))
                    continue;
                if (TooltipEngine.as2Equal(routine, "装备自发光初始化")) {
                    if (TooltipEngine.as2Equal(param.group, "body"))
                        body = true;
                    else if (TooltipEngine.as2Equal(param.group, "blade")) {
                        var adapter = TooltipEngine.as2Equal(param.adapter, undefined) ? "static" : String(param.adapter);
                        for (var bi = 0; TooltipEngine.as2Less(bi, bladeOrder.length); bi++)
                            if (TooltipEngine.as2Equal(bladeOrder[bi], adapter))
                                blades[bi] = true;
                    }
                }
                else if (TooltipEngine.as2Equal(routine, "枪械激光初始化")) {
                    if (TooltipEngine.as2Equal(typeof param.beamLinkage, "string") && TooltipEngine.as2Greater(param.beamLinkage.length, 0))
                        laser = true;
                }
                else if (TooltipEngine.as2Equal(routine, "装备光源初始化")) {
                    if (TooltipEngine.as2Equal(param.kind, "laser"))
                        laser = true;
                    else if (TooltipEngine.as2Equal(param.kind, "headlamp"))
                        headlamp = true;
                    else if (TooltipEngine.as2Equal(param.kind, "flashlight")) {
                        torch = true;
                        if (!standaloneMod && TooltipEngine.as2Equal(attr.__modName, undefined) && param.builtinDefense !== true)
                            continue;
                        var amount = TooltipEngine.as2Number(param.evasionBonus);
                        var extra = TooltipEngine.as2Equal(param.electricEvasionBonus, undefined) ? 0 : TooltipEngine.as2Number(param.electricEvasionBonus);
                        if (!(TooltipEngine.as2Greater(amount, 0)) || !TooltipEngine.as2IsFinite(amount + extra) || TooltipEngine.as2Greater(amount + extra, 100) || TooltipEngine.as2Less(extra, 0))
                            continue;
                        if (standaloneMod) {
                            baseBonus = Math.max(baseBonus, amount);
                            electricBonus = Math.max(electricBonus, amount + extra);
                        }
                        else {
                            if (!tagsRead) {
                                electric = ctx.projection.electric === true;
                                tagsRead = true;
                            }
                            activeBonus = Math.max(activeBonus, amount + (electric ? extra : 0));
                        }
                    }
                }
            }
            if (body)
                result.push("穿戴时持续照亮自身周围，多件发光防具共同提供近身照明。<BR>");
            if (headlamp)
                result.push("穿戴时持续提供近身补光与前方照明，不受持用武器限制。<BR>");
            for (var i = 0; TooltipEngine.as2Less(i, bladeOrder.length); i++) {
                if (blades[i])
                    result.push(bladeText[i], "<BR>");
            }
            if (torch)
                result.push("持枪开灯时提供近身补光与前方照明；移动、换弹时保持，收枪后熄灭。<BR>");
            if (laser)
                result.push("持枪时投射激光，并提供狭窄束带的辅助照明；收枪后熄灭。<BR>");
            if (TooltipEngine.as2Greater(baseBonus, 0)) {
                result.push("持枪开灯期间：闪避加成 +", baseBonus);
                if (TooltipEngine.as2Greater(electricBonus, baseBonus))
                    result.push("；电力适配时 +", electricBonus);
                result.push("。多把手电取最高值，收枪或卸装后失效。<BR>");
            }
            else if (TooltipEngine.as2Greater(activeBonus, 0)) {
                result.push("持枪开灯期间：闪避加成 +", activeBonus, electric ? "（电力适配）" : "", "。多把手电取最高值，收枪或卸装后失效。<BR>");
            }
            if (TooltipEngine.as2Equal(result.length, 0))
                return result;
            return ["<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_LIGHTING_INFO + "</font><BR>", result.join("")];
        }
        EquipmentLightingInfoBuilder.build = build;
    })(EquipmentLightingInfoBuilder = TooltipEngine.EquipmentLightingInfoBuilder || (TooltipEngine.EquipmentLightingInfoBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/EquipmentStatsComposer.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let EquipmentStatsComposer;
    (function (EquipmentStatsComposer) {
        function compose(ctx, baseItem, item, data, equipData, nativeOpt) {
            var result = [];
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "level", null, null);
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "weight", null, TooltipEngine.TooltipConstants.SUF_KG);
            switch (item.use) {
                case TooltipEngine.ItemUseTypes.MELEE:
                    TooltipEngine.MeleeStatsBuilder.build(ctx, result, baseItem, item, data, equipData);
                    break;
                case TooltipEngine.ItemUseTypes.GRENADE:
                    TooltipEngine.GrenadeStatsBuilder.build(ctx, result, baseItem, item, data, equipData);
                    break;
                case TooltipEngine.ItemUseTypes.RIFLE:
                case TooltipEngine.ItemUseTypes.PISTOL:
                    TooltipEngine.GunStatsBuilder.build(ctx, result, baseItem, item, data, equipData, nativeOpt);
                    break;
            }
            TooltipEngine.CommonStatsBuilder.build(ctx, result, baseItem, item, data, equipData, nativeOpt);
            TooltipEngine.CriticalBlockBuilder.build(ctx, critSlayTarget(ctx, nativeOpt, result), baseItem, item, data, equipData);
            TooltipEngine.DamageTypeBuilder.build(ctx, result, baseItem, item, data, equipData);
            TooltipEngine.ResistanceBlockBuilder.build(ctx, result, baseItem, item, data, equipData);
            return result;
        }
        EquipmentStatsComposer.compose = compose;
        function critSlayTarget(ctx, nativeOpt, result) {
            if (TooltipEngine.as2NotEqual(nativeOpt, null) && nativeOpt.omitCritSlay === true && TooltipEngine.as2NotEqual(nativeOpt.critSlay, null)) {
                return nativeOpt.critSlay;
            }
            return result;
        }
    })(EquipmentStatsComposer = TooltipEngine.EquipmentStatsComposer || (TooltipEngine.EquipmentStatsComposer = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/GrantItemTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let GrantItemTooltipBuilder;
    (function (GrantItemTooltipBuilder) {
        function build(ctx, effectData) {
            var result = [];
            var name = effectData.name;
            var count = TooltipEngine.as2Number(effectData.count);
            var chance = TooltipEngine.as2Number(effectData.chance);
            var spoiler = effectData.tooltipSpoiler === true || effectData.tooltipSpoiler === "true";
            if (!name)
                return result;
            if (TooltipEngine.as2IsNaN(count) || TooltipEngine.as2LessEqual(count, 0))
                count = 1;
            if (TooltipEngine.as2IsNaN(chance) || TooltipEngine.as2LessEqual(chance, 0) || TooltipEngine.as2Greater(chance, 1))
                chance = 1;
            if (spoiler) {
                result.push(TooltipEngine.DrugTooltipUtil.color(ctx, TooltipEngine.TooltipConstants.LBL_DRUG_GRANT + "：", TooltipEngine.TooltipConstants.COL_HL));
                result.push(name);
                if (TooltipEngine.as2Greater(count, 1)) {
                    result.push(" x" + count);
                }
                if (TooltipEngine.as2Less(chance, 1)) {
                    result.push("（" + Math.round(chance * 100) + "%" + TooltipEngine.TooltipConstants.TIP_DRUG_CHANCE + "）");
                }
            }
            else {
                result.push(TooltipEngine.DrugTooltipUtil.color(ctx, TooltipEngine.TooltipConstants.LBL_DRUG_GRANT_HIDDEN, TooltipEngine.TooltipConstants.COL_INFO));
            }
            result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            return result;
        }
        GrantItemTooltipBuilder.build = build;
    })(GrantItemTooltipBuilder = TooltipEngine.GrantItemTooltipBuilder || (TooltipEngine.GrantItemTooltipBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/GrenadeStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let GrenadeStatsBuilder;
    (function (GrenadeStatsBuilder) {
        function build(ctx, result, baseItem, item, data, equipData) {
            var power = TooltipEngine.as2Number(data.power);
            if (TooltipEngine.as2IsNaN(power)) {
                power = 0;
            }
            if (power !== 0) {
                result.push(TooltipEngine.TooltipConstants.LBL_POWER, "：", power, "<BR>");
            }
        }
        GrenadeStatsBuilder.build = build;
    })(GrenadeStatsBuilder = TooltipEngine.GrenadeStatsBuilder || (TooltipEngine.GrenadeStatsBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/GunStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let GunStatsBuilder;
    (function (GunStatsBuilder) {
        function build(ctx, result, baseItem, item, data, equipData, nativeOpt) {
            if (data.clipname && !(TooltipEngine.as2NotEqual(nativeOpt, null) && nativeOpt.omitClipName === true)) {
                result.push(TooltipEngine.TooltipConstants.LBL_CLIP_NAME, "：", TooltipEngine.lookupItem(ctx, data.clipname)?.displayname, "<BR>");
            }
            var baseSingleShoot = (TooltipEngine.as2Equal(data.singleshoot, true) || TooltipEngine.as2Equal(data.singleshoot, "true"));
            var finalSingleShoot = baseSingleShoot;
            if (equipData && TooltipEngine.as2NotEqual(equipData.singleshoot, undefined)) {
                finalSingleShoot = (TooltipEngine.as2Equal(equipData.singleshoot, true) || TooltipEngine.as2Equal(equipData.singleshoot, "true"));
            }
            var baseFireMode = baseSingleShoot ? TooltipEngine.TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipEngine.TooltipConstants.TIP_FIRE_MODE_AUTO;
            var finalFireMode = finalSingleShoot ? TooltipEngine.TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipEngine.TooltipConstants.TIP_FIRE_MODE_AUTO;
            if (baseSingleShoot || (equipData && TooltipEngine.as2NotEqual(equipData.singleshoot, undefined) && TooltipEngine.as2NotEqual(finalSingleShoot, baseSingleShoot))) {
                if (equipData && TooltipEngine.as2NotEqual(finalSingleShoot, baseSingleShoot)) {
                    result.push(TooltipEngine.TooltipConstants.LBL_FIRE_MODE, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", finalFireMode, "</FONT> (←", baseFireMode, ")<BR>");
                }
                else {
                    result.push(TooltipEngine.TooltipConstants.LBL_FIRE_MODE, "：", finalFireMode, "<BR>");
                }
            }
            var baseReloadType = data.reloadType ? data.reloadType : "";
            var finalReloadType = baseReloadType;
            if (equipData && TooltipEngine.as2NotEqual(equipData.reloadType, undefined)) {
                finalReloadType = equipData.reloadType;
            }
            var baseReloadDisplay = (TooltipEngine.as2Equal(baseReloadType, "tube")) ? TooltipEngine.TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipEngine.TooltipConstants.TIP_RELOAD_TYPE_MAG;
            var finalReloadDisplay = (TooltipEngine.as2Equal(finalReloadType, "tube")) ? TooltipEngine.TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipEngine.TooltipConstants.TIP_RELOAD_TYPE_MAG;
            var baseIsTube = (TooltipEngine.as2Equal(baseReloadType, "tube"));
            if (baseIsTube || (equipData && TooltipEngine.as2NotEqual(equipData.reloadType, undefined) && TooltipEngine.as2NotEqual(finalReloadType, baseReloadType))) {
                if (equipData && TooltipEngine.as2NotEqual(finalReloadType, baseReloadType)) {
                    result.push(TooltipEngine.TooltipConstants.LBL_RELOAD_TYPE, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", finalReloadDisplay, "</FONT> (←", baseReloadDisplay, ")<BR>");
                }
                else {
                    result.push(TooltipEngine.TooltipConstants.LBL_RELOAD_TYPE, "：", finalReloadDisplay, "<BR>");
                }
            }
            var baseBullet = data.bulletrename ? data.bulletrename : data.bullet;
            var finalBullet = (equipData && equipData.bullet)
                ? (equipData.bulletrename ? equipData.bulletrename : equipData.bullet)
                : baseBullet;
            if (finalBullet && !(TooltipEngine.as2NotEqual(nativeOpt, null) && nativeOpt.omitBulletType === true)) {
                if (equipData && TooltipEngine.as2NotEqual(finalBullet, baseBullet)) {
                    result.push(TooltipEngine.TooltipConstants.LBL_BULLET_TYPE, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", finalBullet, "</FONT> (←", baseBullet, ")<BR>");
                }
                else {
                    result.push(TooltipEngine.TooltipConstants.LBL_BULLET_TYPE, "：", finalBullet, "<BR>");
                }
            }
            var isNotMultiShot = (data.bullet && ctx.projection.isVerticalBullet === true);
            var baseSplit = TooltipEngine.as2Number(data.split);
            if (TooltipEngine.as2IsNaN(baseSplit) || TooltipEngine.as2LessEqual(baseSplit, 1)) {
                baseSplit = 1;
            }
            var splitValue = baseSplit;
            if (equipData && TooltipEngine.as2NotEqual(equipData.split, undefined)) {
                var eqSplit = TooltipEngine.as2Number(equipData.split);
                if (!TooltipEngine.as2IsNaN(eqSplit) && TooltipEngine.as2GreaterEqual(eqSplit, 1)) {
                    splitValue = eqSplit;
                }
            }
            var capacity = TooltipEngine.as2Number(data.capacity);
            if (TooltipEngine.as2IsNaN(capacity)) {
                capacity = 0;
            }
            var magazineCapacity = isNotMultiShot ? splitValue : 1;
            if (TooltipEngine.as2Greater(capacity, 0)) {
                var ammoSuffix = TooltipEngine.WeaponAmmoInfoBuilder.capacitySuffix(ctx, equipData ? equipData : data);
                if (TooltipEngine.as2Greater(magazineCapacity, 1)) {
                    var baseCap = TooltipEngine.as2Number(data.capacity);
                    var finalCap = equipData ? TooltipEngine.as2Number(equipData.capacity) : baseCap;
                    if (TooltipEngine.as2IsNaN(baseCap))
                        baseCap = 0;
                    if (TooltipEngine.as2IsNaN(finalCap))
                        finalCap = baseCap;
                    var baseScaled = baseCap * magazineCapacity;
                    var finalScaled = finalCap * magazineCapacity;
                    var deltaBase = finalCap - baseCap;
                    if (TooltipEngine.as2NotEqual(deltaBase, 0) && equipData) {
                        result.push(TooltipEngine.TooltipConstants.LBL_CAPACITY, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", finalScaled, "</FONT>", ammoSuffix, " (", baseScaled, " + ", deltaBase, "×", magazineCapacity, ")<BR>");
                    }
                    else {
                        result.push(TooltipEngine.TooltipConstants.LBL_CAPACITY, "：", finalScaled, ammoSuffix, "<BR>");
                    }
                }
                else {
                    TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "capacity", TooltipEngine.TooltipConstants.LBL_CAPACITY, null, ammoSuffix);
                }
            }
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "power", TooltipEngine.TooltipConstants.LBL_BULLET_POWER, null);
            if (TooltipEngine.as2Greater(splitValue, 1) || TooltipEngine.as2Greater(baseSplit, 1)) {
                var splitLabel = isNotMultiShot ? TooltipEngine.TooltipConstants.LBL_BURST_COUNT : TooltipEngine.TooltipConstants.LBL_PELLET_COUNT;
                if (equipData && TooltipEngine.as2NotEqual(splitValue, baseSplit)) {
                    result.push(splitLabel, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", splitValue, "</FONT> (←", baseSplit, ")<BR>");
                }
                else {
                    result.push(splitLabel, "：", splitValue, "<BR>");
                }
            }
            var baseInterval = TooltipEngine.as2Number(data.interval);
            var finalInterval = (equipData && equipData.interval) ? TooltipEngine.as2Number(equipData.interval) : baseInterval;
            if (!TooltipEngine.as2IsNaN(finalInterval) && TooltipEngine.as2Greater(finalInterval, 0)) {
                var finalRate = Math.floor(10000 / finalInterval) * magazineCapacity / 10;
                if (equipData && !TooltipEngine.as2IsNaN(baseInterval) && TooltipEngine.as2Greater(baseInterval, 0) && TooltipEngine.as2NotEqual(finalInterval, baseInterval)) {
                    var baseRate = Math.floor(10000 / baseInterval) * magazineCapacity / 10;
                    var rateDelta = Math.round((finalRate - baseRate) * 10) / 10;
                    var sign = TooltipEngine.as2GreaterEqual(rateDelta, 0) ? " + " : " - ";
                    if (TooltipEngine.as2Less(rateDelta, 0))
                        rateDelta = -rateDelta;
                    result.push(TooltipEngine.TooltipConstants.LBL_FIRE_RATE, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", finalRate, "</FONT> (", baseRate, sign, rateDelta, ")", TooltipEngine.TooltipConstants.SUF_FIRE_RATE, "<BR>");
                }
                else {
                    result.push(TooltipEngine.TooltipConstants.LBL_FIRE_RATE, "：", finalRate, TooltipEngine.TooltipConstants.SUF_FIRE_RATE, "<BR>");
                }
            }
            var baseImpact = TooltipEngine.as2Number(data.impact);
            var finalImpact = (equipData && TooltipEngine.as2NotEqual(equipData.impact, undefined)) ? TooltipEngine.as2Number(equipData.impact) : baseImpact;
            if (!TooltipEngine.as2IsNaN(finalImpact) && TooltipEngine.as2Greater(finalImpact, 0)) {
                var finalImpactDisplay = Math.floor(500 / finalImpact);
                if (equipData && !TooltipEngine.as2IsNaN(baseImpact) && TooltipEngine.as2Greater(baseImpact, 0) && TooltipEngine.as2NotEqual(finalImpact, baseImpact)) {
                    var baseImpactDisplay = Math.floor(500 / baseImpact);
                    result.push(TooltipEngine.TooltipConstants.LBL_IMPACT, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", finalImpactDisplay, "</FONT> (←", baseImpactDisplay, ")<BR>");
                }
                else {
                    result.push(TooltipEngine.TooltipConstants.LBL_IMPACT, "：", finalImpactDisplay, "<BR>");
                }
            }
            var baseReloadPenalty = TooltipEngine.as2Number(data.reloadPenalty);
            var finalReloadPenalty = (equipData && TooltipEngine.as2NotEqual(equipData.reloadPenalty, undefined))
                ? TooltipEngine.as2Number(equipData.reloadPenalty) : baseReloadPenalty;
            if (TooltipEngine.as2IsNaN(baseReloadPenalty))
                baseReloadPenalty = 0;
            if (TooltipEngine.as2IsNaN(finalReloadPenalty))
                finalReloadPenalty = baseReloadPenalty;
            if (TooltipEngine.as2NotEqual(finalReloadPenalty, 0) || (equipData && TooltipEngine.as2NotEqual(finalReloadPenalty, baseReloadPenalty))) {
                if (TooltipEngine.as2Greater(finalReloadPenalty, 0)) {
                    if (equipData && TooltipEngine.as2NotEqual(finalReloadPenalty, baseReloadPenalty)) {
                        var delayDelta = finalReloadPenalty - baseReloadPenalty;
                        var delaySign = TooltipEngine.as2GreaterEqual(delayDelta, 0) ? " + " : " - ";
                        if (TooltipEngine.as2Less(delayDelta, 0))
                            delayDelta = -delayDelta;
                        result.push(TooltipEngine.TooltipConstants.LBL_RELOAD_PENALTY, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>+", finalReloadPenalty, "%</FONT> (+", baseReloadPenalty, "%", delaySign, delayDelta, "%)<BR>");
                    }
                    else {
                        result.push(TooltipEngine.TooltipConstants.LBL_RELOAD_PENALTY, "：+", finalReloadPenalty, "%<BR>");
                    }
                }
                else if (TooltipEngine.as2Less(finalReloadPenalty, 0)) {
                    if (equipData && TooltipEngine.as2NotEqual(finalReloadPenalty, baseReloadPenalty)) {
                        var bonusDelta = baseReloadPenalty - finalReloadPenalty;
                        result.push(TooltipEngine.TooltipConstants.LBL_RELOAD_BONUS, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", -finalReloadPenalty, "%</FONT> (", baseReloadPenalty, "% + ", bonusDelta, "%)<BR>");
                    }
                    else {
                        result.push(TooltipEngine.TooltipConstants.LBL_RELOAD_BONUS, "：", -finalReloadPenalty, "%<BR>");
                    }
                }
                else if (equipData && TooltipEngine.as2NotEqual(baseReloadPenalty, 0)) {
                    result.push(TooltipEngine.TooltipConstants.LBL_RELOAD_PENALTY, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>0%</FONT> (+", baseReloadPenalty, "% - ", baseReloadPenalty, "%)<BR>");
                }
            }
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "bulletsize", TooltipEngine.TooltipConstants.LBL_BULLET_SIZE, null);
            TooltipEngine.SilenceEffectBuilder.build(ctx, result, baseItem, item, data, equipData);
        }
        GunStatsBuilder.build = build;
    })(GunStatsBuilder = TooltipEngine.GunStatsBuilder || (TooltipEngine.GunStatsBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/HealTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let HealTooltipBuilder;
    (function (HealTooltipBuilder) {
        function build(ctx, effectData) {
            var result = [];
            var hp = effectData.hp;
            var mp = effectData.mp;
            var target = effectData.target || "self";
            var scaleWithAlchemy = effectData.scaleWithAlchemy !== false;
            var hpStr = TooltipEngine.DrugTooltipUtil.formatValue(ctx, hp);
            var mpStr = TooltipEngine.DrugTooltipUtil.formatValue(ctx, mp);
            var hpNum = TooltipEngine.as2Number(hp);
            var mpNum = TooltipEngine.as2Number(mp);
            if (!TooltipEngine.as2IsNaN(hpNum) && TooltipEngine.as2NotEqual(hpNum, 0) || TooltipEngine.as2GreaterEqual(String(hp).indexOf("%"), 0)) {
                result.push(TooltipEngine.DrugTooltipUtil.color(ctx, "HP+" + hpStr, TooltipEngine.TooltipConstants.COL_HP));
                result.push(TooltipEngine.DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
                result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            }
            if (!TooltipEngine.as2IsNaN(mpNum) && TooltipEngine.as2NotEqual(mpNum, 0) || TooltipEngine.as2GreaterEqual(String(mp).indexOf("%"), 0)) {
                result.push(TooltipEngine.DrugTooltipUtil.color(ctx, "MP+" + mpStr, TooltipEngine.TooltipConstants.COL_MP));
                result.push(TooltipEngine.DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
                result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            }
            if (TooltipEngine.as2Equal(target, "group")) {
                result.push(TooltipEngine.DrugTooltipUtil.color(ctx, TooltipEngine.TooltipConstants.TIP_ALLY_EFFECT, TooltipEngine.TooltipConstants.COL_HL));
                result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            }
            return result;
        }
        HealTooltipBuilder.build = build;
    })(HealTooltipBuilder = TooltipEngine.HealTooltipBuilder || (TooltipEngine.HealTooltipBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/ItemUseTypes.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let ItemUseTypes;
    (function (ItemUseTypes) {
        ItemUseTypes.MELEE = "刀";
        ItemUseTypes.PISTOL = "手枪";
        ItemUseTypes.RIFLE = "长枪";
        ItemUseTypes.GRENADE = "手雷";
        ItemUseTypes.ARMOR = "防具";
        ItemUseTypes.POTION = "药剂";
        ItemUseTypes.SKILL = "技能";
        ItemUseTypes.MATERIAL = "材料";
        ItemUseTypes.INFORMATION = "情报";
        ItemUseTypes.TYPE_WEAPON = "武器";
        ItemUseTypes.TYPE_ARMOR = "防具";
        ItemUseTypes.TYPE_SKILL = "技能";
        ItemUseTypes.TYPE_CONSUMABLE = "消耗品";
        function isGun(useType) {
            return TooltipEngine.as2Equal(useType, ItemUseTypes.PISTOL) || TooltipEngine.as2Equal(useType, ItemUseTypes.RIFLE);
        }
        ItemUseTypes.isGun = isGun;
        function isWeapon(useType) {
            return TooltipEngine.as2Equal(useType, ItemUseTypes.MELEE) || TooltipEngine.as2Equal(useType, ItemUseTypes.PISTOL) || TooltipEngine.as2Equal(useType, ItemUseTypes.RIFLE) || TooltipEngine.as2Equal(useType, ItemUseTypes.GRENADE);
        }
        ItemUseTypes.isWeapon = isWeapon;
    })(ItemUseTypes = TooltipEngine.ItemUseTypes || (TooltipEngine.ItemUseTypes = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/MeleeStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let MeleeStatsBuilder;
    (function (MeleeStatsBuilder) {
        function build(ctx, result, baseItem, item, data, equipData) {
            TooltipEngine.TooltipFormatter.upgradeLine(result, data, equipData, "power", "锋利度", null);
            var bladeCount = (data && TooltipEngine.as2Greater(data.bladeCount, 0)) ? TooltipEngine.as2Number(data.bladeCount) : 0;
            if (TooltipEngine.as2LessEqual(bladeCount, 0)) {
                var dressupName = (data && data.dressup) ? String(data.dressup) : null;
                bladeCount = TooltipEngine.as2Number(ctx.projection.bladeCount);
            }
            if (TooltipEngine.as2Greater(bladeCount, 0)) {
                result.push("判定数：", String(bladeCount), TooltipEngine.TooltipFormatter.br());
            }
        }
        MeleeStatsBuilder.build = build;
    })(MeleeStatsBuilder = TooltipEngine.MeleeStatsBuilder || (TooltipEngine.MeleeStatsBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/ModStatBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let ModStatBuilder;
    (function (ModStatBuilder) {
        function build(ctx, itemName) {
            return buildInternal(ctx, itemName, null);
        }
        ModStatBuilder.build = build;
        function buildWithRows(ctx, itemName) {
            var ranges = {};
            var html = buildInternal(ctx, itemName, ranges);
            if (TooltipEngine.as2Equal(html.length, 0))
                return null;
            var rows = [];
            appendRowGroup(ctx, rows, "装配要求", html, ranges.infoStart, ranges.effectStart);
            appendRowGroup(ctx, rows, "属性与效果", html, ranges.effectStart, ranges.descriptionStart);
            appendRowGroup(ctx, rows, "附加说明", html, ranges.descriptionStart, html.length);
            return { kind: "modinfo", title: TooltipEngine.TooltipConstants.LBL_MOD_INFO,
                rows: rows, html: html.join("") };
        }
        ModStatBuilder.buildWithRows = buildWithRows;
        function appendRowGroup(ctx, rows, title, html, start, end) {
            if (TooltipEngine.as2GreaterEqual(start, end))
                return;
            rows.push({ name: title, depth: 0 });
            var text = "";
            for (var i = start; TooltipEngine.as2Less(i, end); i++)
                text += String(html[i]);
            var lines = text.split("<BR>");
            for (var j = 0; TooltipEngine.as2Less(j, lines.length); j++) {
                if (TooltipEngine.as2Equal(lines[j].length, 0))
                    continue;
                rows.push({ depth: 1, effect: lines[j] });
            }
        }
        function buildInternal(ctx, itemName, ranges) {
            var result = [];
            // The AS2 registry has already accepted/rejected and resolved this standalone mod.
            // A catalog row is descriptive data, never proof of publication/eligibility.
            const registeredName = ctx.projection.registeredModName;
            const modData = registeredName == null ? null : ctx.catalog.mods[registeredName];
            if (registeredName != null && !modData)
                throw new TooltipEngine.InputError('catalog_mod_missing');
            if (!modData)
                return result;
            result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_MOD_INFO + "</font><BR>");
            if (TooltipEngine.as2NotEqual(ranges, null))
                ranges.infoStart = result.length;
            result.push(TooltipEngine.TooltipConstants.LBL_MOD_USE_TYPE, "：", modData.use, "<BR>");
            if (modData.tagValue) {
                result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INFO + "'>" + TooltipEngine.TooltipConstants.LBL_MOD_SLOT + "：</font>", modData.tagValue, "<BR>");
            }
            if (modData.weapontype) {
                result.push(TooltipEngine.TooltipConstants.LBL_MOD_WEAPON_TYPE, "：", modData.weapontype, "<BR>");
            }
            if (modData.excludeWeapontype) {
                result.push("<font color='" + TooltipEngine.TooltipConstants.COL_ROUT + "'>" + TooltipEngine.TooltipConstants.LBL_MOD_EXCLUDE_WEAPON_TYPE + "：</font>", modData.excludeWeapontype, "<BR>");
            }
            if (modData.grantsUse) {
                result.push("<font color='" + TooltipEngine.TooltipConstants.COL_ENHANCE + "'>" + TooltipEngine.TooltipConstants.LBL_MOD_GRANTS_USE + "：</font>", modData.grantsUse, "<BR>");
            }
            if (modData.grantsWeapontype) {
                result.push("<font color='" + TooltipEngine.TooltipConstants.COL_ENHANCE + "'>" + TooltipEngine.TooltipConstants.LBL_MOD_GRANTS_WEAPON_TYPE + "：</font>", modData.grantsWeapontype, "<BR>");
            }
            if (modData.provideTagDict) {
                var provideTags = [];
                for (var pTag of TooltipEngine.as2Keys(modData.provideTagDict)) {
                    if (TooltipEngine.isInternalKey(pTag))
                        continue;
                    provideTags.push(pTag);
                }
                if (TooltipEngine.as2Greater(provideTags.length, 0)) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_ENHANCE + "'>" + TooltipEngine.TooltipConstants.LBL_PROVIDE_TAGS + "：</font>", provideTags.join(", "), "<BR>");
                }
            }
            if (modData.requireTagDict) {
                var requireTags = [];
                for (var rTag of TooltipEngine.as2Keys(modData.requireTagDict)) {
                    if (TooltipEngine.isInternalKey(rTag))
                        continue;
                    requireTags.push(rTag);
                }
                if (TooltipEngine.as2Greater(requireTags.length, 0)) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_ROUT + "'>" + TooltipEngine.TooltipConstants.LBL_REQUIRE_TAGS + "：</font>", requireTags.join(", "), "<BR>");
                }
            }
            if (modData.excludeBulletTypeDict) {
                var excludeNames = bulletTypeDictToNames(ctx, modData.excludeBulletTypeDict);
                if (TooltipEngine.as2Greater(excludeNames.length, 0)) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_ROUT + "'>" + TooltipEngine.TooltipConstants.LBL_EXCLUDE_BULLET_TYPES + "：</font>", excludeNames.join(", "), "<BR>");
                }
            }
            if (modData.requireBulletTypeDict) {
                var requireNames = bulletTypeDictToNames(ctx, modData.requireBulletTypeDict);
                if (TooltipEngine.as2Greater(requireNames.length, 0)) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INSTALL_COND + "'>" + TooltipEngine.TooltipConstants.LBL_REQUIRE_BULLET_TYPES + "：</font>", requireNames.join(", "), "<BR>");
                }
            }
            const installConditions = modData.installCondList || displayConditionList(modData.installCondition);
            if (installConditions) {
                var condLines = buildInstallConditionText(ctx, installConditions);
                if (TooltipEngine.as2Greater(condLines.length, 0)) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INSTALL_COND + "'>" + TooltipEngine.TooltipConstants.LBL_INSTALL_CONDITION + "：</font><BR>");
                    for (var ci = 0; TooltipEngine.as2Less(ci, condLines.length); ci++) {
                        result.push("  " + condLines[ci] + "<BR>");
                    }
                }
            }
            if (TooltipEngine.as2NotEqual(ranges, null))
                ranges.effectStart = result.length;
            var stats = modData.stats;
            TooltipEngine.UseSwitchStatsBuilder.buildStatBlock(ctx, result, stats, "");
            TooltipEngine.UseSwitchStatsBuilder.buildBaseSwitchDetailed(ctx, result, stats);
            TooltipEngine.UseSwitchStatsBuilder.buildDetailed(ctx, result, stats);
            TooltipEngine.TagSwitchStatsBuilder.buildDetailed(ctx, result, stats);
            TooltipEngine.UseSwitchStatsBuilder.buildBulletSwitchDetailed(ctx, result, stats);
            if (modData.subweapon) {
                result = result.concat(TooltipEngine.TooltipTextBuilder.buildSubweaponInfo(ctx, modData.subweapon));
            }
            if (modData.skill && !modData.skillSwitch) {
                result = result.concat(TooltipEngine.TooltipTextBuilder.buildSkillInfo(ctx, modData.skill));
            }
            appendSkillSwitchInfo(ctx, result, modData);
            var lighting = TooltipEngine.EquipmentLightingInfoBuilder.build(ctx, modData, null, true);
            for (var li = 0; TooltipEngine.as2Less(li, lighting.length); li++)
                result.push(lighting[li]);
            if (TooltipEngine.as2NotEqual(ranges, null))
                ranges.descriptionStart = result.length;
            if (typeof modData.description === "string") {
                result.push(TooltipEngine.TooltipFormatter.normalizeDescription(modData.description), TooltipEngine.TooltipFormatter.br());
            }
            return result;
        }
        function bulletTypeDictToNames(ctx, typeDict) {
            var names = [];
            var nameMap = TooltipEngine.TooltipConstants.BULLET_TYPE_NAMES;
            for (var key of TooltipEngine.as2Keys(typeDict)) {
                if (TooltipEngine.isInternalKey(key))
                    continue;
                var name = nameMap[key];
                names.push(name ? name : key);
            }
            return names;
        }
        function appendSkillSwitchInfo(ctx, result, modData) {
            if (!modData || !modData.skillSwitch)
                return;
            var useCases = modData.skillSwitch.useCases;
            if (!useCases) {
                if (Array.isArray(modData.skillSwitch.use)) {
                    useCases = modData.skillSwitch.use;
                }
                else if (modData.skillSwitch.use) {
                    useCases = [modData.skillSwitch.use];
                }
            }
            if (!useCases || TooltipEngine.as2LessEqual(useCases.length, 0))
                return;
            var rows = [];
            var namedCount = 0;
            var hasDefault = false;
            for (var i = 0; TooltipEngine.as2Less(i, useCases.length); i++) {
                var useCase = useCases[i];
                if (!useCase)
                    continue;
                var skill = useCase.skill ? useCase.skill : useCase;
                if (!skill || !skill.skillname)
                    continue;
                var isDefault = (useCase._isDefault || !useCase.name);
                var useLabel = isDefault
                    ? TooltipEngine.TooltipConstants.TIP_DEFAULT_BRANCH
                    : TooltipEngine.UseSwitchStatsBuilder.getUseCaseDisplayName(ctx, useCase.name);
                if (isDefault) {
                    hasDefault = true;
                }
                else {
                    namedCount++;
                }
                rows.push({ label: useLabel, skill: skill, isDefault: isDefault });
            }
            if (modData.skill && !hasDefault) {
                rows.push({ label: TooltipEngine.TooltipConstants.TIP_DEFAULT_BRANCH, skill: modData.skill, isDefault: true });
            }
            if (TooltipEngine.as2LessEqual(rows.length, 0))
                return;
            if (TooltipEngine.as2Equal(rows.length, 1) && TooltipEngine.as2Equal(namedCount, 0)) {
                var singleInfo = TooltipEngine.TooltipTextBuilder.buildSkillInfo(ctx, rows[0].skill);
                for (var si = 0; TooltipEngine.as2Less(si, singleInfo.length); si++) {
                    result.push(singleInfo[si]);
                }
                return;
            }
            result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>", TooltipEngine.TooltipConstants.LBL_ACTIVE_SKILL, "</font>按装备类型切换<BR>");
            for (var ri = 0; TooltipEngine.as2Less(ri, rows.length); ri++) {
                appendSkillSwitchSkillLine(ctx, result, rows[ri].label, rows[ri].skill);
            }
        }
        function appendSkillSwitchSkillLine(ctx, result, label, skill) {
            var skillLabel = skill.skillname;
            result.push("  <font color='" + TooltipEngine.TooltipConstants.COL_USE_SWITCH + "'>[", label, "]</font> ", skillLabel);
            var summary = buildSkillSwitchSkillSummary(ctx, skill);
            if (TooltipEngine.as2Greater(summary.length, 0)) {
                result.push("：", summary);
            }
            result.push("<BR>");
        }
        function buildSkillSwitchSkillSummary(ctx, skill) {
            if (!skill)
                return "";
            if (skill.information)
                return String(skill.information);
            var parts = [];
            if (hasSkillValue(ctx, skill.cd)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_COOLDOWN + (TooltipEngine.as2Number(skill.cd) / 1000) + TooltipEngine.TooltipConstants.SUF_SECOND);
            }
            if (hasSkillValue(ctx, skill.hp) && TooltipEngine.as2NotEqual(TooltipEngine.as2Number(skill.hp), 0)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_COST + skill.hp + TooltipEngine.TooltipConstants.SUF_HP);
            }
            if (hasSkillValue(ctx, skill.mp) && TooltipEngine.as2NotEqual(TooltipEngine.as2Number(skill.mp), 0)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_COST + skill.mp + TooltipEngine.TooltipConstants.SUF_MP);
            }
            if (TooltipEngine.as2Greater(parts.length, 0))
                return parts.join("，") + "。";
            if (skill.description)
                return TooltipEngine.TooltipFormatter.normalizeDescription(skill.description);
            return "";
        }
        function hasSkillValue(ctx, value) {
            return TooltipEngine.as2NotEqual(value, undefined) && TooltipEngine.as2NotEqual(value, null) && TooltipEngine.as2Greater(String(value).length, 0);
        }
        const pathNames = Object.freeze({
            actiontype: "动作类型", "data.damagetype": "伤害类型", "data.interval": "攻击间隔",
            "data.power": "威力", "data.defence": "防御", "data.weight": "重量", "data.hp": "生命值",
            "data.mp": "魔法值", "data.accuracy": "精准", "data.diffusion": "散布", "data.velocity": "弹速",
            "data.capacity": "弹匣容量", "data.damage": "伤害", "data.force": "力度", "data.punch": "冲击",
            "data.bullet": "子弹类型", "data.magictype": "魔法属性", "data.criticalhit": "暴击",
            "data.bulletsize": "纵向范围", "data.modslot": "插件槽", "data.split": "霰弹值"
        });
        const opSymbols = Object.freeze({
            is: " 为 ", isNot: " ≠ ", above: " > ", atLeast: " ≥ ", below: " &lt; ", atMost: " ≤ ",
            oneOf: " ∈ ", noneOf: " ∉ ", contains: " 包含 ", range: "", exists: " 存在", missing: " 不存在"
        });
        function getPathNameMap(ctx) { return pathNames; }
        function getOpSymbolMap(ctx) { return opSymbols; }
        // Catalogs retain authored XML nodes. Normalize their display shape only;
        // registration and installation eligibility remain the AS2 projection's authority.
        function displayConditionList(raw) {
            if (!raw)
                return null;
            const conditions = [];
            const nodes = (value) => value == null ? [] : Array.isArray(value) ? value : [value];
            for (const leaf of nodes(raw.cond)) {
                if (!leaf || !leaf.op)
                    continue;
                const condition = { type: 'cond', op: leaf.op, path: leaf.path || '' };
                if (leaf.op === 'range') {
                    condition.min = TooltipEngine.as2Number(leaf.min);
                    condition.max = TooltipEngine.as2Number(leaf.max);
                }
                else if (leaf.op !== 'exists' && leaf.op !== 'missing') {
                    condition.value = leaf.value;
                }
                conditions.push(condition);
            }
            for (const group of nodes(raw.group)) {
                const nested = displayConditionList(group);
                if (nested) {
                    nested.type = 'group';
                    conditions.push(nested);
                }
            }
            return conditions.length ? { mode: raw.mode || 'all', conditions } : null;
        }
        function buildInstallConditionText(ctx, condList) {
            var lines = [];
            if (!condList || !condList.conditions)
                return lines;
            var pathNames = getPathNameMap(ctx);
            var opSymbols = getOpSymbolMap(ctx);
            var conditions = condList.conditions;
            for (var i = 0; TooltipEngine.as2Less(i, conditions.length); i++) {
                var cond = conditions[i];
                if (!cond)
                    continue;
                if (TooltipEngine.as2Equal(cond.type, "group")) {
                    var subLines = buildInstallConditionText(ctx, cond);
                    var modeLabel = (TooltipEngine.as2Equal(cond.mode, "any")) ? "任一满足" : "全部满足";
                    lines.push("<font color='" + TooltipEngine.TooltipConstants.COL_INSTALL_COND + "'>[" + modeLabel + "]</font>");
                    for (var s = 0; TooltipEngine.as2Less(s, subLines.length); s++) {
                        lines.push("  " + subLines[s]);
                    }
                    continue;
                }
                var line;
                if (TooltipEngine.as2Equal(cond.path, "data.interval")) {
                    var rateValue = Math.floor(10000 / TooltipEngine.as2Number(cond.value)) / 10;
                    line = "射速" + reverseIntervalOp(ctx, cond.op) + rateValue + TooltipEngine.TooltipConstants.SUF_FIRE_RATE;
                }
                else {
                    var pathLabel = pathNames[cond.path] || cond.path;
                    var opSymbol = opSymbols[cond.op] || " " + cond.op + " ";
                    if (TooltipEngine.as2Equal(cond.op, "exists") || TooltipEngine.as2Equal(cond.op, "missing")) {
                        line = pathLabel + opSymbol;
                    }
                    else if (TooltipEngine.as2Equal(cond.op, "range")) {
                        line = pathLabel + " ∈ [" + cond.min + ", " + cond.max + "]";
                    }
                    else if (TooltipEngine.as2Equal(cond.op, "oneOf") || TooltipEngine.as2Equal(cond.op, "noneOf")) {
                        line = pathLabel + opSymbol + "{" + cond.value + "}";
                    }
                    else {
                        line = pathLabel + opSymbol + mapCondValue(ctx, cond.path, cond.value);
                    }
                }
                lines.push(line);
            }
            return lines;
        }
        function reverseIntervalOp(ctx, op) {
            if (TooltipEngine.as2Equal(op, "above"))
                return " &lt; ";
            if (TooltipEngine.as2Equal(op, "atLeast"))
                return " ≤ ";
            if (TooltipEngine.as2Equal(op, "below"))
                return " &gt; ";
            if (TooltipEngine.as2Equal(op, "atMost"))
                return " ≥ ";
            return " = ";
        }
        function mapCondValue(ctx, path, value) {
            if (TooltipEngine.as2Equal(path, "data.damagetype") && TooltipEngine.as2Equal(value, TooltipEngine.TooltipConstants.TXT_MAGIC)) {
                return "属性";
            }
            return value;
        }
    })(ModStatBuilder = TooltipEngine.ModStatBuilder || (TooltipEngine.ModStatBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/ModsBlockBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let ModsBlockBuilder;
    (function (ModsBlockBuilder) {
        function build(ctx, result, baseItem, item, value) {
            buildWithRows(ctx, result, baseItem, item, value);
        }
        ModsBlockBuilder.build = build;
        function buildWithRows(ctx, result, baseItem, item, value) {
            var collected = collect(ctx, baseItem, item, value);
            if (TooltipEngine.as2Equal(collected, null))
                return null;
            result.push(collected.titleHtml);
            var rows = collected.rows;
            var attachments = [];
            for (var i = 0; TooltipEngine.as2Less(i, rows.length); i++) {
                var row = rows[i];
                result.push("  • ", row.name, row.tagHtml, row.percentageHtml, row.multiplierHtml);
                if (TooltipEngine.as2Greater(row.overrideParts.length, 0)) {
                    if (row.hasNumeric)
                        result.push("<BR>    ");
                    result.push(row.overrideParts.join(""));
                }
                result.push("<BR>");
                var effect = row.tagHtml + row.percentageHtml + row.multiplierHtml;
                if (TooltipEngine.as2Greater(row.overrideParts.length, 0)) {
                    effect += " " + row.overrideParts.join("");
                }
                var outRow = { name: row.name, effect: effect };
                if (TooltipEngine.as2NotEqual(row.icon, null))
                    outRow.icon = row.icon;
                attachments.push(outRow);
            }
            return {
                kind: "attachments",
                title: TooltipEngine.TooltipConstants.LBL_INSTALLED_MODS + rows.length
                    + TooltipEngine.TooltipConstants.LBL_MOD_COUNT_SUFFIX,
                rows: attachments
            };
        }
        ModsBlockBuilder.buildWithRows = buildWithRows;
        function collect(ctx, baseItem, item, value) {
            if (TooltipEngine.as2Equal(value, null) || !value.mods || TooltipEngine.as2LessEqual(value.mods.length, 0)) {
                return null;
            }
            var titleHtml = "<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>"
                + TooltipEngine.TooltipConstants.LBL_INSTALLED_MODS + value.mods.length
                + TooltipEngine.TooltipConstants.LBL_MOD_COUNT_SUFFIX + "：</font><BR>";
            var rawItemData = baseItem ? TooltipEngine.lookupItem(ctx, baseItem.name) : null;
            var baseBulletType = (rawItemData && rawItemData.data && rawItemData.data.bullet) ? rawItemData.data.bullet : "";
            var rows = [];
            for (var i = 0; TooltipEngine.as2Less(i, value.mods.length); i++) {
                var modName = value.mods[i];
                if (!modName)
                    continue;
                const published = TooltipEngine.projectedMod(ctx, modName);
                var modInfo = published.present === false ? null : ctx.catalog.mods[modName];
                if (published.present !== false && !modInfo)
                    throw new TooltipEngine.InputError('catalog_mod_missing');
                var row = {
                    name: modName,
                    icon: null,
                    tagHtml: "",
                    percentageHtml: "",
                    multiplierHtml: "",
                    overrideParts: [],
                    hasNumeric: false
                };
                var modItemData = TooltipEngine.lookupItem(ctx, modName);
                if (TooltipEngine.as2NotEqual(modItemData, null) && TooltipEngine.as2NotEqual(modItemData.icon, undefined) && TooltipEngine.as2NotEqual(modItemData.icon, "")) {
                    row.icon = String(modItemData.icon);
                }
                if (modInfo && modInfo.tagValue) {
                    row.tagHtml = " <font color='" + TooltipEngine.TooltipConstants.COL_INFO + "'>["
                        + modInfo.tagValue + "]</font>";
                }
                if (modInfo && modInfo.stats && modInfo.stats.percentage) {
                    var enhancements = [];
                    var percentage = modInfo.stats.percentage;
                    for (var prop of TooltipEngine.as2Keys(percentage)) {
                        var percentValue = TooltipEngine.as2Number(percentage[prop]);
                        if (!TooltipEngine.as2IsNaN(percentValue) && TooltipEngine.as2NotEqual(percentValue, 0)) {
                            var sign = TooltipEngine.as2Greater(percentValue, 0) ? "+" : "";
                            var percent = Math.round(percentValue * 100);
                            enhancements.push(sign + percent + "%");
                        }
                    }
                    if (TooltipEngine.as2Greater(enhancements.length, 0)) {
                        row.percentageHtml = " <font color='" + TooltipEngine.TooltipConstants.COL_ENHANCE
                            + "'>(" + enhancements.join(", ") + ")</font>";
                        row.hasNumeric = true;
                    }
                }
                if (modInfo && modInfo.stats && modInfo.stats.multiplier) {
                    var multiplierEnhancements = [];
                    var multiplier = modInfo.stats.multiplier;
                    for (var mprop of TooltipEngine.as2Keys(multiplier)) {
                        var mValue = TooltipEngine.as2Number(multiplier[mprop]);
                        if (!TooltipEngine.as2IsNaN(mValue) && TooltipEngine.as2NotEqual(mValue, 0)) {
                            var mtext;
                            if (TooltipEngine.as2Less(mValue, 0)) {
                                var multiplierValue = 1 + mValue;
                                var displayValue = Math.round(multiplierValue * 100) / 100;
                                mtext = "×" + displayValue;
                            }
                            else {
                                var mpercent = Math.round(mValue * 100);
                                mtext = "×+" + mpercent + "%";
                            }
                            multiplierEnhancements.push(mtext);
                        }
                    }
                    if (TooltipEngine.as2Greater(multiplierEnhancements.length, 0)) {
                        row.multiplierHtml = " <font color='" + TooltipEngine.TooltipConstants.COL_MULTIPLIER
                            + "'>{" + multiplierEnhancements.join(", ") + "}</font>";
                        row.hasNumeric = true;
                    }
                }
                var overrideEffectParts = [];
                if (modInfo && modInfo.stats && modInfo.stats.override && modInfo.stats.override.silence) {
                    var silenceDesc = TooltipEngine.SilenceEffectBuilder.getShortDescription(ctx, modInfo.stats.override.silence);
                    if (TooltipEngine.as2NotEqual(silenceDesc, "")) {
                        overrideEffectParts.push(" <font color='" + TooltipEngine.TooltipConstants.COL_SILENCE + "'>[" + silenceDesc + "]</font>");
                    }
                }
                if (modInfo && modInfo.stats && modInfo.stats.override && TooltipEngine.as2NotEqual(modInfo.stats.override.singleshoot, undefined)) {
                    var singleshootVal = (TooltipEngine.as2Equal(modInfo.stats.override.singleshoot, true) || TooltipEngine.as2Equal(modInfo.stats.override.singleshoot, "true"));
                    var fireModeDesc = singleshootVal ? TooltipEngine.TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipEngine.TooltipConstants.TIP_FIRE_MODE_AUTO;
                    overrideEffectParts.push(" <font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>[" + TooltipEngine.TooltipConstants.LBL_FIRE_MODE + ": " + fireModeDesc + "]</font>");
                }
                if (modInfo && modInfo.stats && modInfo.stats.override && TooltipEngine.as2NotEqual(modInfo.stats.override.reloadType, undefined)) {
                    var reloadTypeVal = modInfo.stats.override.reloadType;
                    var reloadTypeDesc = (TooltipEngine.as2Equal(reloadTypeVal, "tube")) ? TooltipEngine.TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipEngine.TooltipConstants.TIP_RELOAD_TYPE_MAG;
                    overrideEffectParts.push(" <font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>[" + TooltipEngine.TooltipConstants.LBL_RELOAD_TYPE + ": " + reloadTypeDesc + "]</font>");
                }
                var hasMatchedBranchHitBehavior = false;
                var defaultBranchHitBehavior = null;
                if (modInfo && modInfo.stats && modInfo.stats.useSwitch && modInfo.stats.useSwitch.useCases) {
                    var useCases = TooltipEngine.projectedMod(ctx, modName).useCases;
                    var useSwitchHints = [];
                    for (var ucIdx = 0; TooltipEngine.as2Less(ucIdx, useCases.length); ucIdx++) {
                        var useCase = useCases[ucIdx];
                        if (!useCase)
                            continue;
                        if (useCase._isDefault || !useCase.name) {
                            if (!defaultBranchHitBehavior) {
                                defaultBranchHitBehavior = (useCase.override && useCase.override.hitBehavior)
                                    ? useCase.override.hitBehavior
                                    : ((useCase.merge && useCase.merge.hitBehavior) ? useCase.merge.hitBehavior : null);
                            }
                            continue;
                        }
                        var effects = [];
                        if (useCase.multiplier) {
                            for (var mKey of TooltipEngine.as2Keys(useCase.multiplier)) {
                                if (TooltipEngine.isInternalKey(mKey))
                                    continue;
                                var mVal = TooltipEngine.as2Number(useCase.multiplier[mKey]);
                                if (!TooltipEngine.as2IsNaN(mVal) && TooltipEngine.as2NotEqual(mVal, 0)) {
                                    var displayText;
                                    if (TooltipEngine.as2Less(mVal, 0)) {
                                        var multValue = 1 + mVal;
                                        var dispValue = Math.round(multValue * 100) / 100;
                                        displayText = TooltipEngine.TooltipConstants.TAG_MULTIPLIER_ZONE + "×" + dispValue;
                                    }
                                    else {
                                        var mPercent = Math.round(mVal * 100);
                                        displayText = TooltipEngine.TooltipConstants.TAG_MULTIPLIER_ZONE + "×+" + mPercent + "%";
                                    }
                                    effects.push(displayText);
                                    break;
                                }
                            }
                        }
                        if (TooltipEngine.as2Equal(effects.length, 0) && useCase.percentage) {
                            for (var pKey of TooltipEngine.as2Keys(useCase.percentage)) {
                                if (TooltipEngine.isInternalKey(pKey))
                                    continue;
                                var pVal = TooltipEngine.as2Number(useCase.percentage[pKey]);
                                if (!TooltipEngine.as2IsNaN(pVal) && TooltipEngine.as2NotEqual(pVal, 0)) {
                                    var pPercent = Math.round(pVal * 100);
                                    var sign = TooltipEngine.as2Greater(pPercent, 0) ? "+" : "";
                                    var pLabel = TooltipEngine.TooltipConstants.PROPERTY_DICT[pKey] || pKey;
                                    effects.push(pLabel + sign + pPercent + "%");
                                    break;
                                }
                            }
                        }
                        var branchHitBehavior = (useCase.override && useCase.override.hitBehavior)
                            ? useCase.override.hitBehavior
                            : ((useCase.merge && useCase.merge.hitBehavior) ? useCase.merge.hitBehavior : null);
                        if (branchHitBehavior) {
                            hasMatchedBranchHitBehavior = true;
                            var hitBehaviorSummary = TooltipEngine.UseSwitchStatsBuilder.buildHitBehaviorSummary(ctx, branchHitBehavior);
                            if (TooltipEngine.as2Greater(hitBehaviorSummary.length, 0)) {
                                effects.push(hitBehaviorSummary);
                            }
                        }
                        if (TooltipEngine.as2Greater(effects.length, 0)) {
                            var useName = TooltipEngine.UseSwitchStatsBuilder.getUseCaseDisplayName(ctx, useCase.name);
                            useSwitchHints.push(TooltipEngine.TooltipConstants.TIP_FOR + useName + ":" + effects.join(","));
                        }
                    }
                    if (TooltipEngine.as2Greater(useSwitchHints.length, 0)) {
                        overrideEffectParts.push(" <font color='" + TooltipEngine.TooltipConstants.COL_USE_SWITCH + "'>[" + useSwitchHints.join("; ") + "]</font>");
                    }
                }
                if (!hasMatchedBranchHitBehavior && modInfo && modInfo.stats) {
                    var baseHitBehavior = defaultBranchHitBehavior;
                    if (!baseHitBehavior) {
                        baseHitBehavior = (modInfo.stats.override && modInfo.stats.override.hitBehavior)
                            ? modInfo.stats.override.hitBehavior
                            : ((modInfo.stats.merge && modInfo.stats.merge.hitBehavior) ? modInfo.stats.merge.hitBehavior : null);
                    }
                    if (baseHitBehavior) {
                        var baseHitBehaviorSummary = TooltipEngine.UseSwitchStatsBuilder.buildHitBehaviorSummary(ctx, baseHitBehavior);
                        if (TooltipEngine.as2Greater(baseHitBehaviorSummary.length, 0)) {
                            overrideEffectParts.push(" <font color='" + TooltipEngine.TooltipConstants.COL_USE_SWITCH + "'>[" + baseHitBehaviorSummary + "]</font>");
                        }
                    }
                }
                if (modInfo && modInfo.stats && modInfo.stats.bulletSwitch && modInfo.stats.bulletSwitch.bulletCases) {
                    var matchedCases = TooltipEngine.projectedMod(ctx, modName).bulletCases;
                    if (matchedCases && TooltipEngine.as2Greater(matchedCases.length, 0)) {
                        var bsHints = [];
                        for (var bci = 0; TooltipEngine.as2Less(bci, matchedCases.length); bci++) {
                            var bCase = matchedCases[bci];
                            var bEffects = [];
                            if (bCase.override) {
                                for (var oKey of TooltipEngine.as2Keys(bCase.override)) {
                                    if (TooltipEngine.isInternalKey(oKey))
                                        continue;
                                    var oLabel = TooltipEngine.TooltipConstants.PROPERTY_DICT[oKey] || oKey;
                                    bEffects.push(oLabel + "→" + bCase.override[oKey]);
                                    break;
                                }
                            }
                            if (TooltipEngine.as2Equal(bEffects.length, 0) && bCase.percentage) {
                                for (var bpKey of TooltipEngine.as2Keys(bCase.percentage)) {
                                    if (TooltipEngine.isInternalKey(bpKey))
                                        continue;
                                    var bpVal = TooltipEngine.as2Number(bCase.percentage[bpKey]);
                                    if (!TooltipEngine.as2IsNaN(bpVal) && TooltipEngine.as2NotEqual(bpVal, 0)) {
                                        var bpPercent = Math.round(bpVal * 100);
                                        var bpSign = TooltipEngine.as2Greater(bpPercent, 0) ? "+" : "";
                                        var bpLabel = TooltipEngine.TooltipConstants.PROPERTY_DICT[bpKey] || bpKey;
                                        bEffects.push(bpLabel + bpSign + bpPercent + "%");
                                        break;
                                    }
                                }
                            }
                            if (TooltipEngine.as2Greater(bEffects.length, 0)) {
                                var bLabel;
                                if (bCase._isDefault || !bCase.name) {
                                    bLabel = TooltipEngine.TooltipConstants.TIP_DEFAULT_BRANCH;
                                }
                                else {
                                    var bNames = bCase.name.split(",");
                                    var bDisplayNames = [];
                                    for (var bni = 0; TooltipEngine.as2Less(bni, bNames.length); bni++) {
                                        var bTrimmed = bNames[bni];
                                        while (TooltipEngine.as2Equal(bTrimmed.charAt(0), " "))
                                            bTrimmed = bTrimmed.substr(1);
                                        while (TooltipEngine.as2Equal(bTrimmed.charAt(bTrimmed.length - 1), " "))
                                            bTrimmed = bTrimmed.substr(0, bTrimmed.length - 1);
                                        var bCnName = TooltipEngine.TooltipConstants.BULLET_TYPE_NAMES[bTrimmed];
                                        bDisplayNames.push(bCnName ? bCnName : bTrimmed);
                                    }
                                    bLabel = bDisplayNames.join("/");
                                }
                                bsHints.push(bLabel + ":" + bEffects.join(","));
                            }
                        }
                        if (TooltipEngine.as2Greater(bsHints.length, 0)) {
                            overrideEffectParts.push(" <font color='" + TooltipEngine.TooltipConstants.COL_BULLET_SWITCH + "'>[" + bsHints.join("; ") + "]</font>");
                        }
                    }
                }
                if (modInfo && modInfo.skillSwitch) {
                    var resolvedSkill = TooltipEngine.projectedMod(ctx, modName).skill;
                    if (resolvedSkill && resolvedSkill.skillname) {
                        overrideEffectParts.push(" <font color='" + TooltipEngine.TooltipConstants.COL_USE_SWITCH + "'>" + TooltipEngine.TooltipConstants.LBL_ACTIVE_SKILL + resolvedSkill.skillname + "</font>");
                    }
                }
                if (modInfo && modInfo.subweapon) {
                    var subweaponName = modInfo.subweapon.name ? modInfo.subweapon.name : modName;
                    overrideEffectParts.push(" <font color='" + TooltipEngine.TooltipConstants.COL_USE_SWITCH + "'>" + TooltipEngine.TooltipConstants.LBL_SUBWEAPON + subweaponName + "</font>");
                }
                row.overrideParts = overrideEffectParts;
                rows.push(row);
            }
            return { titleHtml: titleHtml, rows: rows };
        }
    })(ModsBlockBuilder = TooltipEngine.ModsBlockBuilder || (TooltipEngine.ModsBlockBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/NativeTooltipDocument.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let NativeTooltipDocument;
    (function (NativeTooltipDocument) {
        NativeTooltipDocument.ROLE_INTRO = "intro";
        NativeTooltipDocument.ROLE_DESCRIPTION = "description";
        NativeTooltipDocument.ROLE_BODY = "body";
        NativeTooltipDocument.ROLE_SUB = "sub";
        NativeTooltipDocument.PROFILE_SIMPLE = "simple";
        NativeTooltipDocument.PROFILE_DENSE = "dense";
        NativeTooltipDocument.PROFILE_PINNED = "pinned";
        function buildItem(name, itemData, iconData, introHtml, descHtml, subHtmls, extras) {
            var iconName = null;
            var title = null;
            if (iconData != null) {
                if (iconData.icon != undefined && iconData.icon != "")
                    iconName = String(iconData.icon);
                if (iconData.displayname != undefined && iconData.displayname != "")
                    title = String(iconData.displayname);
            }
            if (iconName == null && itemData != null
                && itemData.icon != undefined && itemData.icon != "") {
                iconName = String(itemData.icon);
            }
            if (title == null && itemData != null
                && itemData.displayname != undefined && itemData.displayname != "") {
                title = String(itemData.displayname);
            }
            if (title == null)
                title = name;
            var sections = [];
            if (descHtml != null && extras != null && extras.upgrades != null) {
                var upgradeStart = descHtml.lastIndexOf(TooltipEngine.TooltipConstants.LBL_UPGRADE_PATH);
                if (upgradeStart >= 0) {
                    var headerStart = descHtml.toLowerCase().lastIndexOf("<font", upgradeStart);
                    descHtml = descHtml.substring(0, headerStart >= 0 ? headerStart : upgradeStart);
                }
            }
            pushSection(sections, NativeTooltipDocument.ROLE_INTRO, introHtml);
            pushSection(sections, NativeTooltipDocument.ROLE_DESCRIPTION, descHtml);
            if (subHtmls != null) {
                for (var si = 0; si < subHtmls.length; si++) {
                    var subEntry = subHtmls[si];
                    if (typeof subEntry == "string") {
                        pushSection(sections, NativeTooltipDocument.ROLE_SUB, String(subEntry));
                    }
                    else if (subEntry != null) {
                        pushAttachments(sections, subEntry);
                    }
                }
            }
            title = dedupeTitleLine(title, sections);
            var icon = (iconName != null) ? { kind: "item", name: iconName } : null;
            var doc = buildSectioned(title, icon, sections, NativeTooltipDocument.PROFILE_DENSE);
            var typeName = (itemData != null && itemData.type != undefined) ? String(itemData.type) : "";
            if (typeName == "消耗品" && itemData.use != undefined)
                typeName = String(itemData.use);
            doc.layoutType = (typeName == "武器" || typeName == "防具" || typeName == "技能" || typeName == "药剂") ? "wide" : "narrow";
            attachExtras(doc, extras);
            return doc;
        }
        NativeTooltipDocument.buildItem = buildItem;
        function attachExtras(doc, extras) {
            if (extras == null)
                return;
            if (Array.isArray(extras.rail)) {
                var rail = [];
                for (var i = 0; i < extras.rail.length && i < 2; i++) {
                    var text = safeText(extras.rail[i]);
                    if (text == null)
                        continue;
                    if (rail.length > 0 && rail[rail.length - 1] == text)
                        continue;
                    rail.push(text);
                }
                if (rail.length > 0)
                    doc.rail = rail;
            }
            var mag = extras.magazine;
            if (mag != null) {
                var magName = safeText(mag.name);
                if (magName != null) {
                    var magazine = { name: magName };
                    var magIcon = safeText(mag.icon);
                    if (magIcon != null)
                        magazine.icon = magIcon;
                    var magAmmo = safeText(mag.ammo);
                    if (magAmmo != null)
                        magazine.ammo = magAmmo;
                    doc.magazine = magazine;
                }
            }
            if (extras.upgrades != null) {
                pushAttachments(doc.sections, extras.upgrades, NativeTooltipDocument.ROLE_DESCRIPTION);
            }
        }
        function pushAttachments(sections, entry, targetRole) {
            if (targetRole == null)
                targetRole = NativeTooltipDocument.ROLE_SUB;
            var kind = (entry != null && entry.kind != undefined) ? String(entry.kind) : null;
            if (kind != "attachments" && kind != "acquisition" && kind != "modinfo"
                && kind != "upgrades") {
                if (entry != null && entry.html != undefined) {
                    pushSection(sections, targetRole, String(entry.html));
                }
                return;
            }
            var title = safeText(entry.title);
            var rows = [];
            var fallback = [];
            if (title != null) {
                fallback.push({ text: title + "：", bold: true });
                fallback.push({ text: "\n" });
            }
            var source = (Array.isArray(entry.rows)) ? entry.rows : [];
            for (var i = 0; i < source.length; i++) {
                var raw = source[i];
                if (raw == null)
                    continue;
                var rowName = safeText(raw.name);
                if (rowName == null && kind != "modinfo")
                    continue;
                var effectHtml = (raw.effect == undefined || raw.effect == null)
                    ? "" : String(raw.effect);
                var row = { name: (rowName != null ? rowName : ""), runs: htmlToRuns(effectHtml) };
                if (rowName == null && row.runs.length == 0)
                    continue;
                var rowIcon = safeText(raw.icon);
                if (rowIcon != null)
                    row.icon = rowIcon;
                if (TooltipEngine.as2Number(raw.depth) === 1)
                    row.depth = 1;
                rows.push(row);
                var fallbackPrefix = row.depth === 1 ? "    • "
                    : (kind == "attachments" ? "  • " : "");
                fallback.push({ text: fallbackPrefix + (rowName != null ? rowName : "") });
                var effectRuns = row.runs;
                for (var r = 0; r < effectRuns.length; r++)
                    fallback.push(effectRuns[r]);
                fallback.push({ text: "\n" });
            }
            if (rows.length == 0)
                return;
            var section = { role: targetRole, kind: kind, rows: rows };
            if (title != null)
                section.title = title;
            section.runs = fallback;
            sections.push(section);
        }
        function safeText(value) {
            if (value == null || value == undefined)
                return null;
            var s = trimBlank(String(value));
            if (s.length == 0 || s == "null" || s == "undefined")
                return null;
            return s;
        }
        function buildSkill(skillName, introHtml, descHtml) {
            var sections = [];
            pushSection(sections, NativeTooltipDocument.ROLE_INTRO, introHtml);
            pushSection(sections, NativeTooltipDocument.ROLE_DESCRIPTION, descHtml);
            var icon = (skillName != null && skillName != "")
                ? { kind: "skill", name: String(skillName) } : null;
            var doc = buildSectioned(dedupeTitleLine(skillName, sections), icon, sections, NativeTooltipDocument.PROFILE_DENSE);
            doc.layoutType = "wide";
            return doc;
        }
        NativeTooltipDocument.buildSkill = buildSkill;
        function buildBody(bodyHtml, profile) {
            var sections = [];
            pushSection(sections, NativeTooltipDocument.ROLE_BODY, bodyHtml);
            return buildSectioned(null, null, sections, (profile != null && profile != "") ? profile : NativeTooltipDocument.PROFILE_SIMPLE);
        }
        NativeTooltipDocument.buildBody = buildBody;
        function buildSectioned(title, icon, sections, profile) {
            var doc = { version: 1 };
            if (title != null && title != "")
                doc.title = String(title);
            if (icon != null && icon.name != undefined && icon.name != "") {
                doc.icon = {
                    kind: (icon.kind != undefined && icon.kind != "") ? String(icon.kind) : "item",
                    name: String(icon.name)
                };
            }
            doc.profile = (profile != null && profile != "") ? String(profile) : NativeTooltipDocument.PROFILE_SIMPLE;
            doc.sections = (sections != null) ? sections : [];
            return doc;
        }
        NativeTooltipDocument.buildSectioned = buildSectioned;
        function makeSection(role, html) {
            return { role: role, runs: htmlToRuns(html) };
        }
        NativeTooltipDocument.makeSection = makeSection;
        function pushSection(sections, role, html) {
            var section = makeSection(role, html);
            if (section.runs.length > 0)
                sections.push(section);
        }
        function dedupeTitleLine(title, sections) {
            if (title == null || title == "" || sections == null || sections.length == 0)
                return title;
            var sec = sections[0];
            if (sec.role != NativeTooltipDocument.ROLE_INTRO || sec.runs == null || sec.runs.length == 0)
                return title;
            var first = String(sec.runs[0].text);
            var match = (first == title);
            if (!match && first.length > title.length
                && first.substring(first.length - title.length) == title) {
                var prefix = first.substring(0, first.length - title.length);
                match = prefix.length > 2
                    && prefix.charAt(0) == "["
                    && prefix.charAt(prefix.length - 1) == "]";
            }
            if (!match)
                return title;
            if (sec.runs.length > 1 && sec.runs[1].text != "\n")
                return title;
            var rest = sec.runs.slice(1);
            if (rest.length > 0 && rest[0].text == "\n")
                rest.shift();
            if (rest.length == 0)
                sections.shift();
            else
                sec.runs = rest;
            return first;
        }
        NativeTooltipDocument.dedupeTitleLine = dedupeTitleLine;
        function htmlToRuns(html) {
            var runs = [];
            if (html == null)
                return runs;
            var s = String(html);
            var len = s.length;
            if (len == 0)
                return runs;
            var stack = [];
            var pending = "";
            var i = 0;
            while (i < len) {
                var code = s.charCodeAt(i);
                if (code == 60) {
                    var tagEndIndex = s.indexOf(">", i + 1);
                    if (tagEndIndex < 0) {
                        pending += "<";
                        i++;
                        continue;
                    }
                    var tagBody = s.substring(i + 1, tagEndIndex);
                    var kind = classifyTag(tagBody);
                    if (kind == 1) {
                        pending = flushPending(runs, pending, stack);
                        pushRun(runs, "\n", null, false, false, false, NaN, null);
                    }
                    else if (kind == 2) {
                        pending = flushPending(runs, pending, stack);
                        if (runs.length > 0)
                            pushRun(runs, "\n", null, false, false, false, NaN, null);
                    }
                    else if (kind == 3) {
                        pending = flushPending(runs, pending, stack);
                        stack.push({
                            color: parseFontColor(tagBody),
                            size: parseFontSize(tagBody),
                            face: parseFontFace(tagBody),
                            font: true, bold: false, italic: false, underline: false
                        });
                    }
                    else if (kind == 4) {
                        pending = flushPending(runs, pending, stack);
                        popStyle(stack, "font");
                    }
                    else if (kind == 5) {
                        pending = flushPending(runs, pending, stack);
                        stack.push({ bold: true });
                    }
                    else if (kind == 6) {
                        pending = flushPending(runs, pending, stack);
                        popStyle(stack, "bold");
                    }
                    else if (kind == 7) {
                        pending = flushPending(runs, pending, stack);
                        stack.push({ italic: true });
                    }
                    else if (kind == 8) {
                        pending = flushPending(runs, pending, stack);
                        popStyle(stack, "italic");
                    }
                    else if (kind == 9) {
                        pending = flushPending(runs, pending, stack);
                        stack.push({ underline: true });
                    }
                    else if (kind == 10) {
                        pending = flushPending(runs, pending, stack);
                        popStyle(stack, "underline");
                    }
                    i = tagEndIndex + 1;
                    continue;
                }
                if (code == 38) {
                    var semi = s.indexOf(";", i + 1);
                    if (semi > i && semi - i <= 10) {
                        var decoded = decodeEntity(s.substring(i + 1, semi));
                        if (decoded != null) {
                            pending += decoded;
                            i = semi + 1;
                            continue;
                        }
                    }
                    pending += "&";
                    i++;
                    continue;
                }
                if (code == 13) {
                    pending += "\n";
                    i++;
                    if (i < len && s.charCodeAt(i) == 10)
                        i++;
                    continue;
                }
                pending += s.charAt(i);
                i++;
            }
            flushPending(runs, pending, stack);
            return runs;
        }
        NativeTooltipDocument.htmlToRuns = htmlToRuns;
        function flushPending(runs, pending, stack) {
            if (pending.length > 0) {
                pushRun(runs, pending, currentColor(stack), currentBold(stack), currentFlag(stack, "italic"), currentFlag(stack, "underline"), currentFontSize(stack), currentFontFace(stack));
            }
            return "";
        }
        function pushRun(runs, text, color, bold, italic, underline, fontSize, fontFace) {
            if (text == null || text.length == 0)
                return;
            var run = { text: text };
            if (color != null && color != "")
                run.color = color;
            if (bold === true)
                run.bold = true;
            if (italic === true)
                run.italic = true;
            if (underline === true)
                run.underline = true;
            if (!TooltipEngine.as2IsNaN(fontSize))
                run.fontSize = fontSize;
            if (fontFace != null && fontFace != "")
                run.fontFace = fontFace;
            runs.push(run);
        }
        function currentColor(stack) {
            for (var i = stack.length - 1; i >= 0; i--) {
                if (stack[i].color != null)
                    return stack[i].color;
            }
            return null;
        }
        function currentBold(stack) {
            return currentFlag(stack, "bold");
        }
        function currentFlag(stack, flag) {
            for (var i = stack.length - 1; i >= 0; i--) {
                if (stack[i][flag] === true)
                    return true;
            }
            return false;
        }
        function currentFontSize(stack) {
            for (var i = stack.length - 1; i >= 0; i--) {
                if (stack[i].size != null && !TooltipEngine.as2IsNaN(stack[i].size))
                    return stack[i].size;
            }
            return NaN;
        }
        function currentFontFace(stack) {
            for (var i = stack.length - 1; i >= 0; i--) {
                if (stack[i].face != null && stack[i].face != "")
                    return stack[i].face;
            }
            return null;
        }
        function popStyle(stack, flag) {
            for (var i = stack.length - 1; i >= 0; i--) {
                if (stack[i][flag] === true) {
                    stack.splice(i);
                    return;
                }
            }
            if (flag == "font" && stack.length > 0)
                stack.pop();
        }
        function classifyTag(tagBody) {
            if (tagBody == null)
                return 0;
            var t = trimBlank(tagBody);
            if (t.length == 0)
                return 0;
            var closing = (t.charAt(0) == "/");
            var name = closing ? t.substring(1) : t;
            var end = name.length;
            for (var k = 0; k < name.length; k++) {
                var c = name.charCodeAt(k);
                if (c == 32 || c == 9 || c == 10 || c == 13 || c == 47) {
                    end = k;
                    break;
                }
            }
            name = name.substring(0, end).toLowerCase();
            if (name == "br")
                return 1;
            if (name == "p")
                return closing ? 0 : 2;
            if (name == "font")
                return closing ? 4 : 3;
            if (name == "b" || name == "strong")
                return closing ? 6 : 5;
            if (name == "i" || name == "em")
                return closing ? 8 : 7;
            if (name == "u")
                return closing ? 10 : 9;
            return 0;
        }
        function readFontAttr(tagBody, name) {
            if (tagBody == null)
                return null;
            var lower = tagBody.toLowerCase();
            var nameLen = name.length;
            var from = 0;
            while (true) {
                var idx = lower.indexOf(name, from);
                if (idx < 0)
                    return null;
                if (idx > 0) {
                    var prev = lower.charCodeAt(idx - 1);
                    if (!(prev == 32 || prev == 9 || prev == 10 || prev == 13 || prev == 47)) {
                        from = idx + 1;
                        continue;
                    }
                }
                var after = idx + nameLen;
                if (after < lower.length) {
                    var nc = lower.charCodeAt(after);
                    if (!(nc == 32 || nc == 9 || nc == 10 || nc == 13 || nc == 61)) {
                        from = idx + 1;
                        continue;
                    }
                }
                var attributeEqualsAt = tagBody.indexOf("=", after);
                if (attributeEqualsAt < 0)
                    return null;
                var mid = tagBody.substring(after, attributeEqualsAt);
                var clean = true;
                for (var m = 0; m < mid.length; m++) {
                    var mc = mid.charCodeAt(m);
                    if (!(mc == 32 || mc == 9 || mc == 10 || mc == 13)) {
                        clean = false;
                        break;
                    }
                }
                if (!clean) {
                    from = after;
                    continue;
                }
                var tail = trimEdge(tagBody.substring(attributeEqualsAt + 1), " \t\r\n");
                if (tail.length == 0)
                    return null;
                var quote = tail.charAt(0);
                if (quote == "'" || quote == "\"") {
                    var qend = tail.indexOf(quote, 1);
                    if (qend < 0)
                        return null;
                    return tail.substring(1, qend);
                }
                var vend = 0;
                while (vend < tail.length && " \t\r\n".indexOf(tail.charAt(vend)) < 0)
                    vend++;
                return tail.substring(0, vend);
            }
        }
        function parseFontColor(tagBody) {
            return normalizeHexColor(readFontAttr(tagBody, "color"));
        }
        function normalizeHexColor(value) {
            if (value == null)
                return null;
            var hex = trimEdge(value, " \t\r\n");
            if (hex.charAt(0) == "#") {
                hex = hex.substring(1);
            }
            else if (hex.length > 2 && hex.substring(0, 2).toLowerCase() == "0x") {
                hex = hex.substring(2);
            }
            if (hex.length == 3) {
                hex = hex.charAt(0) + hex.charAt(0)
                    + hex.charAt(1) + hex.charAt(1)
                    + hex.charAt(2) + hex.charAt(2);
            }
            if (hex.length != 6)
                return null;
            for (var k = 0; k < 6; k++) {
                var c = hex.charCodeAt(k);
                var isHex = (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
                if (!isHex)
                    return null;
            }
            return "#" + hex.toUpperCase();
        }
        function parseFontSize(tagBody) {
            var raw = readFontAttr(tagBody, "size");
            if (raw == null)
                return NaN;
            var i = 0;
            var n = raw.length;
            while (i < n && isSpaceCode(raw.charCodeAt(i)))
                i++;
            var sign = 1;
            if (i < n) {
                var sc = raw.charCodeAt(i);
                if (sc == 43)
                    i++;
                else if (sc == 45) {
                    sign = -1;
                    i++;
                }
            }
            var v = 0;
            var digits = 0;
            while (i < n) {
                var c = raw.charCodeAt(i);
                if (c < 48 || c > 57)
                    break;
                v = v * 10 + (c - 48);
                digits++;
                i++;
            }
            if (digits == 0)
                return NaN;
            v *= sign;
            return (v >= 1 && v <= 96) ? v : NaN;
        }
        function parseFontFace(tagBody) {
            var raw = readFontAttr(tagBody, "face");
            if (raw == null)
                return null;
            var out = "";
            var n = raw.length;
            for (var i = 0; i < n; i++) {
                var c = raw.charCodeAt(i);
                if (c == 32) {
                    if (out.length > 0 && out.charCodeAt(out.length - 1) != 32)
                        out += " ";
                    continue;
                }
                if (isFaceChar(c))
                    out += TooltipEngine.as2FromCharCode(c);
            }
            while (out.length > 0 && out.charCodeAt(out.length - 1) == 32) {
                out = out.substring(0, out.length - 1);
            }
            if (out.length > 64)
                out = out.substring(0, 64);
            return (out.length > 0) ? out : null;
        }
        function isFaceChar(c) {
            return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
                || c == 95 || c == 45 || (c >= 0x4E00 && c <= 0x9FA5);
        }
        function isSpaceCode(c) {
            return c == 32 || (c >= 9 && c <= 13) || c == 0xA0 || c == 0x1680
                || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029
                || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF;
        }
        function decodeEntity(entity) {
            if (entity == null || entity.length == 0)
                return null;
            var lower = entity.toLowerCase();
            if (lower == "amp")
                return "&";
            if (lower == "lt")
                return "<";
            if (lower == "gt")
                return ">";
            if (lower == "quot")
                return "\"";
            if (lower == "apos")
                return "'";
            if (lower == "nbsp")
                return " ";
            if (entity.charAt(0) == "#") {
                var hex = entity.length > 1 && (entity.charAt(1) == "x" || entity.charAt(1) == "X");
                var digits = entity.substring(hex ? 2 : 1);
                if (digits.length == 0)
                    return null;
                var v = 0;
                for (var d = 0; d < digits.length; d++) {
                    var dc = digits.charCodeAt(d);
                    var digit;
                    if (dc >= 48 && dc <= 57)
                        digit = dc - 48;
                    else if (hex && dc >= 65 && dc <= 70)
                        digit = dc - 55;
                    else if (hex && dc >= 97 && dc <= 102)
                        digit = dc - 87;
                    else
                        return null;
                    v = hex ? v * 16 + digit : v * 10 + digit;
                    if (v > 0xFFFF)
                        return null;
                }
                return TooltipEngine.as2FromCharCode(v);
            }
            return null;
        }
        function trimBlank(s) {
            return trimEdge(s, " \t\r\n");
        }
        function trimEdge(s, chars) {
            var a = 0;
            var b = s.length;
            while (a < b && chars.indexOf(s.charAt(a)) >= 0)
                a++;
            while (b > a && chars.indexOf(s.charAt(b - 1)) >= 0)
                b--;
            return s.substring(a, b);
        }
    })(NativeTooltipDocument = TooltipEngine.NativeTooltipDocument || (TooltipEngine.NativeTooltipDocument = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/ObtainMethodsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let ObtainMethodsBuilder;
    (function (ObtainMethodsBuilder) {
        function build(ctx, itemName) {
            var result = [];
            buildWithRows(ctx, result, itemName);
            return result;
        }
        ObtainMethodsBuilder.build = build;
        function buildWithRows(ctx, result, itemName) {
            var records = ctx.projection.obtainRecords;
            if (!records || TooltipEngine.as2Equal(records.length, 0))
                return null;
            var crafts = [];
            var shops = [];
            var kshops = [];
            var stageDrops = [];
            var enemyDrops = [];
            var arenaDrops = [];
            var quests = [];
            for (var i = 0; TooltipEngine.as2Less(i, records.length); i++) {
                var rec = records[i];
                switch (rec.kind) {
                    case "craft":
                        crafts.push(rec);
                        break;
                    case "shop":
                        shops.push(rec);
                        break;
                    case "kshop":
                        kshops.push(rec);
                        break;
                    case "drop":
                        if (rec.dropType === "stage") {
                            stageDrops.push(rec);
                        }
                        else if (rec.dropType === "enemy") {
                            enemyDrops.push(rec);
                        }
                        else if (rec.dropType === "arena") {
                            arenaDrops.push(rec);
                        }
                        break;
                    case "quest":
                        quests.push(rec);
                        break;
                }
            }
            if (TooltipEngine.as2Equal(crafts.length, 0) && TooltipEngine.as2Equal(shops.length, 0) && TooltipEngine.as2Equal(kshops.length, 0) && TooltipEngine.as2Equal(stageDrops.length, 0) && TooltipEngine.as2Equal(enemyDrops.length, 0)
                && TooltipEngine.as2Equal(arenaDrops.length, 0) && TooltipEngine.as2Equal(quests.length, 0)) {
                return null;
            }
            var rows = [];
            result.push(TooltipEngine.TooltipFormatter.br());
            result.push("<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>");
            result.push(TooltipEngine.TooltipConstants.LBL_OBTAIN_METHODS);
            result.push("</FONT>");
            result.push(TooltipEngine.TooltipFormatter.br());
            var maxCrafts = TooltipEngine.TooltipConstants.OBTAIN_MAX_CRAFTS;
            var craftCount = Math.min(crafts.length, maxCrafts);
            if (TooltipEngine.as2Greater(craftCount, 0))
                rows.push({ name: labelOf(ctx, TooltipEngine.TooltipConstants.TIP_OBTAIN_CRAFT), effect: "" });
            for (var c = 0; TooltipEngine.as2Less(c, craftCount); c++) {
                var craft = crafts[c];
                var craftLabel = craftLocationLabel(ctx, String(craft.category));
                result.push("  <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_CRAFT + "'>");
                result.push(TooltipEngine.TooltipConstants.TIP_OBTAIN_CRAFT);
                result.push("</FONT>");
                result.push(craftLabel);
                var craftText = craftLabel;
                var craftPrice = "";
                if (TooltipEngine.as2Greater(craft.price, 0) || TooltipEngine.as2Greater(craft.kprice, 0)) {
                    result.push(" (");
                    if (TooltipEngine.as2Greater(craft.price, 0))
                        result.push("$" + craft.price);
                    if (TooltipEngine.as2Greater(craft.price, 0) && TooltipEngine.as2Greater(craft.kprice, 0))
                        result.push(" + ");
                    if (TooltipEngine.as2Greater(craft.kprice, 0))
                        result.push(craft.kprice + "K");
                    result.push(")");
                    craftText += " (";
                    if (TooltipEngine.as2Greater(craft.price, 0))
                        craftText += "$" + craft.price;
                    if (TooltipEngine.as2Greater(craft.price, 0) && TooltipEngine.as2Greater(craft.kprice, 0))
                        craftText += " + ";
                    if (TooltipEngine.as2Greater(craft.kprice, 0))
                        craftText += craft.kprice + "K";
                    craftText += ")";
                    craftPrice = craftText.substring(craftLabel.length);
                }
                result.push(TooltipEngine.TooltipFormatter.br());
                rows.push({ name: craftLabel, effect: craftPrice, depth: 1 });
            }
            if (TooltipEngine.as2Greater(crafts.length, maxCrafts)) {
                result.push("  <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_CRAFT + "'>");
                result.push(TooltipEngine.TooltipConstants.TIP_OBTAIN_CRAFT);
                result.push("</FONT>");
                result.push(TooltipEngine.TooltipConstants.TIP_ETC + (crafts.length - maxCrafts) + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE);
                result.push(TooltipEngine.TooltipFormatter.br());
                rows.push({ name: TooltipEngine.TooltipConstants.TIP_ETC + (crafts.length - maxCrafts)
                        + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
            }
            if (TooltipEngine.as2Greater(shops.length, 0)) {
                result.push("  <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_SHOP + "'>");
                result.push(TooltipEngine.TooltipConstants.TIP_OBTAIN_SHOP);
                result.push("</FONT>");
                rows.push({ name: "NPC商店", effect: "" });
                var maxShops = TooltipEngine.TooltipConstants.OBTAIN_MAX_SHOPS;
                var shopNames = [];
                var shopCount = Math.min(shops.length, maxShops);
                for (var s = 0; TooltipEngine.as2Less(s, shopCount); s++) {
                    shopNames.push(shops[s].npc);
                    rows.push({ name: String(shops[s].npc), icon: String(shops[s].npc), effect: "", depth: 1 });
                }
                result.push(shopNames.join("、"));
                if (TooltipEngine.as2Greater(shops.length, maxShops)) {
                    result.push(TooltipEngine.TooltipConstants.TIP_ETC + (shops.length - maxShops) + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE);
                    rows.push({ name: TooltipEngine.TooltipConstants.TIP_ETC + (shops.length - maxShops)
                            + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
                }
                result.push(TooltipEngine.TooltipFormatter.br());
            }
            var maxKshops = TooltipEngine.TooltipConstants.OBTAIN_MAX_KSHOPS;
            var kshopCount = Math.min(kshops.length, maxKshops);
            if (TooltipEngine.as2Greater(kshopCount, 0))
                rows.push({ name: labelOf(ctx, TooltipEngine.TooltipConstants.TIP_OBTAIN_KSHOP), effect: "" });
            for (var k = 0; TooltipEngine.as2Less(k, kshopCount); k++) {
                var kitem = kshops[k];
                result.push("  <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_KSHOP + "'>");
                result.push(TooltipEngine.TooltipConstants.TIP_OBTAIN_KSHOP);
                result.push("</FONT>");
                result.push(kitem.type + " (" + kitem.priceK + "K)");
                result.push(TooltipEngine.TooltipFormatter.br());
                rows.push({ name: String(kitem.type), effect: "(" + kitem.priceK + "K)", depth: 1 });
            }
            if (TooltipEngine.as2Greater(kshops.length, maxKshops)) {
                result.push("  <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_KSHOP + "'>");
                result.push(TooltipEngine.TooltipConstants.TIP_OBTAIN_KSHOP);
                result.push("</FONT>");
                result.push(TooltipEngine.TooltipConstants.TIP_ETC + (kshops.length - maxKshops) + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE);
                result.push(TooltipEngine.TooltipFormatter.br());
                rows.push({ name: TooltipEngine.TooltipConstants.TIP_ETC + (kshops.length - maxKshops)
                        + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
            }
            if (TooltipEngine.as2Greater(stageDrops.length, 0)) {
                result.push("  <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_DROP_STAGE + "'>");
                result.push(TooltipEngine.TooltipConstants.TIP_OBTAIN_STAGE);
                result.push("</FONT>");
                rows.push({ name: labelOf(ctx, TooltipEngine.TooltipConstants.TIP_OBTAIN_STAGE), effect: "" });
                var maxStages = TooltipEngine.TooltipConstants.OBTAIN_MAX_STAGES;
                var stageNames = [];
                var stageCount = Math.min(stageDrops.length, maxStages);
                for (var st = 0; TooltipEngine.as2Less(st, stageCount); st++) {
                    stageNames.push(stageDrops[st].stageName);
                    rows.push({ name: String(stageDrops[st].stageName), effect: "", depth: 1 });
                }
                var stageText = stageNames.join("、");
                result.push(stageText);
                if (TooltipEngine.as2Greater(stageDrops.length, maxStages)) {
                    result.push(TooltipEngine.TooltipConstants.TIP_ETC + (stageDrops.length - maxStages) + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE);
                    stageText += TooltipEngine.TooltipConstants.TIP_ETC + (stageDrops.length - maxStages) + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE;
                    rows.push({ name: TooltipEngine.TooltipConstants.TIP_ETC + (stageDrops.length - maxStages)
                            + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
                }
                result.push(TooltipEngine.TooltipFormatter.br());
            }
            if (TooltipEngine.as2Greater(enemyDrops.length, 0)) {
                result.push("  <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_DROP_ENEMY + "'>");
                result.push(TooltipEngine.TooltipConstants.TIP_OBTAIN_ENEMY);
                result.push("</FONT>");
                rows.push({ name: labelOf(ctx, TooltipEngine.TooltipConstants.TIP_OBTAIN_ENEMY), effect: "" });
                var maxEnemies = TooltipEngine.TooltipConstants.OBTAIN_MAX_ENEMIES;
                var enemyNames = [];
                var enemyCount = Math.min(enemyDrops.length, maxEnemies);
                for (var e = 0; TooltipEngine.as2Less(e, enemyCount); e++) {
                    var enemyType = enemyDrops[e].enemyType;
                    var displayName = enemyDrops[e].enemyDisplayName || ctx.catalog.enemyNames?.[enemyType] || enemyType;
                    enemyNames.push(displayName);
                    rows.push({ name: String(displayName), effect: "", depth: 1 });
                }
                var enemyText = enemyNames.join("、");
                result.push(enemyText);
                if (TooltipEngine.as2Greater(enemyDrops.length, maxEnemies)) {
                    result.push(TooltipEngine.TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies) + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE);
                    enemyText += TooltipEngine.TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies) + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE;
                    rows.push({ name: TooltipEngine.TooltipConstants.TIP_ETC + (enemyDrops.length - maxEnemies)
                            + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
                }
                result.push(TooltipEngine.TooltipFormatter.br());
            }
            var maxArenas = TooltipEngine.TooltipConstants.OBTAIN_MAX_ARENAS;
            var arenaCount = Math.min(arenaDrops.length, maxArenas);
            var arenaCategoryAdded = false;
            for (var a = 0; TooltipEngine.as2Less(a, arenaCount); a++) {
                var arena = arenaDrops[a];
                var carrierLabel;
                if (TooltipEngine.as2Equal(arena.carrierScope, "specific_carrier")) {
                    carrierLabel = TooltipEngine.TooltipConstants.TIP_OBTAIN_ARENA_SPECIFIC_CARRIER;
                }
                else if (TooltipEngine.as2Equal(arena.carrierScope, "carrier")) {
                    carrierLabel = TooltipEngine.TooltipConstants.TIP_OBTAIN_ARENA_CARRIER;
                }
                else {
                    continue;
                }
                if (!arenaCategoryAdded) {
                    rows.push({ name: labelOf(ctx, TooltipEngine.TooltipConstants.TIP_OBTAIN_ARENA), effect: "" });
                    arenaCategoryAdded = true;
                }
                result.push("  <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_DROP_ARENA + "'>");
                result.push(TooltipEngine.TooltipConstants.TIP_OBTAIN_ARENA);
                result.push("</FONT>");
                result.push(carrierLabel);
                result.push(TooltipEngine.TooltipFormatter.br());
                rows.push({ name: String(carrierLabel), effect: "", depth: 1 });
            }
            if (TooltipEngine.as2Greater(arenaDrops.length, maxArenas)) {
                result.push("  <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_DROP_ARENA + "'>");
                result.push(TooltipEngine.TooltipConstants.TIP_OBTAIN_ARENA);
                result.push("</FONT>");
                result.push(TooltipEngine.TooltipConstants.TIP_ETC
                    + (arenaDrops.length - maxArenas) + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE);
                result.push(TooltipEngine.TooltipFormatter.br());
                if (arenaCategoryAdded) {
                    rows.push({ name: TooltipEngine.TooltipConstants.TIP_ETC + (arenaDrops.length - maxArenas)
                            + TooltipEngine.TooltipConstants.TIP_OBTAIN_MORE, effect: "", depth: 1 });
                }
            }
            var title = TooltipEngine.TooltipConstants.LBL_OBTAIN_METHODS;
            if (TooltipEngine.as2Equal(title.charAt(0), "【") && TooltipEngine.as2Equal(title.charAt(title.length - 1), "】")) {
                title = title.substring(1, title.length - 1);
            }
            return { kind: "acquisition", title: title, rows: rows };
        }
        ObtainMethodsBuilder.buildWithRows = buildWithRows;
        function labelOf(ctx, tip) {
            if (TooltipEngine.as2Equal(tip, null))
                return "";
            var last = tip.charAt(tip.length - 1);
            if (TooltipEngine.as2Equal(last, "：") || TooltipEngine.as2Equal(last, ":"))
                return tip.substring(0, tip.length - 1);
            return tip;
        }
        function craftLocationLabel(ctx, category) {
            if (TooltipEngine.as2Equal(category, "属性武器"))
                return "堕落城商业区 → 升阶与涂装";
            return category;
        }
    })(ObtainMethodsBuilder = TooltipEngine.ObtainMethodsBuilder || (TooltipEngine.ObtainMethodsBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/PurifyTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let PurifyTooltipBuilder;
    (function (PurifyTooltipBuilder) {
        function build(ctx, effectData) {
            var result = [];
            var value = TooltipEngine.as2Number(effectData.value);
            var scaleWithAlchemy = effectData.scaleWithAlchemy !== false;
            if (TooltipEngine.as2IsNaN(value) || TooltipEngine.as2LessEqual(value, 0))
                return result;
            result.push(TooltipEngine.TooltipConstants.LBL_CLEAN + "：" + value);
            result.push(TooltipEngine.DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
            result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            return result;
        }
        PurifyTooltipBuilder.build = build;
    })(PurifyTooltipBuilder = TooltipEngine.PurifyTooltipBuilder || (TooltipEngine.PurifyTooltipBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/RegenTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let RegenTooltipBuilder;
    (function (RegenTooltipBuilder) {
        function build(ctx, effectData) {
            var result = [];
            var hp = effectData.hp;
            var mp = effectData.mp;
            var duration = TooltipEngine.as2Number(effectData.duration);
            var interval = TooltipEngine.as2Number(effectData.interval);
            var mode = effectData.mode || "perTick";
            var scaleWithAlchemy = effectData.scaleWithAlchemy !== false;
            var stack = effectData.stack || "refresh";
            if (TooltipEngine.as2IsNaN(interval) || TooltipEngine.as2LessEqual(interval, 0))
                interval = 30;
            if (TooltipEngine.as2IsNaN(duration) || TooltipEngine.as2LessEqual(duration, 0))
                return result;
            var durationSec = TooltipEngine.DrugTooltipUtil.framesToSeconds(ctx, duration);
            var intervalSec = TooltipEngine.DrugTooltipUtil.framesToSeconds(ctx, interval);
            var hpStr = TooltipEngine.DrugTooltipUtil.formatValue(ctx, hp);
            var mpStr = TooltipEngine.DrugTooltipUtil.formatValue(ctx, mp);
            var hpNum = TooltipEngine.as2Number(hp);
            var mpNum = TooltipEngine.as2Number(mp);
            var parts = [];
            if (!TooltipEngine.as2IsNaN(hpNum) && TooltipEngine.as2NotEqual(hpNum, 0) || TooltipEngine.as2GreaterEqual(String(hp).indexOf("%"), 0)) {
                var hpText;
                if (TooltipEngine.as2Equal(mode, "total")) {
                    hpText = hpStr + "hp/" + durationSec + "s";
                }
                else {
                    hpText = hpStr + "hp/" + intervalSec + "s/" + durationSec + "s";
                }
                parts.push(TooltipEngine.DrugTooltipUtil.color(ctx, hpText, TooltipEngine.TooltipConstants.COL_HP));
            }
            if (!TooltipEngine.as2IsNaN(mpNum) && TooltipEngine.as2NotEqual(mpNum, 0) || TooltipEngine.as2GreaterEqual(String(mp).indexOf("%"), 0)) {
                var mpText;
                if (TooltipEngine.as2Equal(mode, "total")) {
                    mpText = mpStr + "mp/" + durationSec + "s";
                }
                else {
                    mpText = mpStr + "mp/" + intervalSec + "s/" + durationSec + "s";
                }
                parts.push(TooltipEngine.DrugTooltipUtil.color(ctx, mpText, TooltipEngine.TooltipConstants.COL_MP));
            }
            if (TooltipEngine.as2Equal(parts.length, 0))
                return result;
            result.push(TooltipEngine.DrugTooltipUtil.color(ctx, TooltipEngine.TooltipConstants.LBL_DRUG_REGEN + "：", TooltipEngine.TooltipConstants.COL_HL));
            result.push(parts.join(" "));
            var alchemyStr = TooltipEngine.DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy);
            if (TooltipEngine.as2Greater(alchemyStr.length, 0)) {
                result.push(" ");
                result.push(alchemyStr);
            }
            result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            if (TooltipEngine.as2Equal(stack, "refresh") && !effectData.id) {
                result.push(TooltipEngine.DrugTooltipUtil.color(ctx, TooltipEngine.TooltipConstants.LBL_DRUG_REGEN_OVERRIDE, TooltipEngine.TooltipConstants.COL_INFO));
                result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            }
            return result;
        }
        RegenTooltipBuilder.build = build;
    })(RegenTooltipBuilder = TooltipEngine.RegenTooltipBuilder || (TooltipEngine.RegenTooltipBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/ResistanceBlockBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let ResistanceBlockBuilder;
    (function (ResistanceBlockBuilder) {
        function build(ctx, result, baseItem, item, data, equipData) {
            var finalData = equipData ? equipData : data;
            if (!finalData.magicdefence && !data.magicdefence) {
                return;
            }
            var resistanceTypes = {};
            if (data.magicdefence) {
                for (var key of TooltipEngine.as2Keys(data.magicdefence)) {
                    if (TooltipEngine.isInternalKey(key))
                        continue;
                    resistanceTypes[key] = true;
                }
            }
            if (finalData.magicdefence) {
                for (var key of TooltipEngine.as2Keys(finalData.magicdefence)) {
                    if (TooltipEngine.isInternalKey(key))
                        continue;
                    resistanceTypes[key] = true;
                }
            }
            for (var key of TooltipEngine.as2Keys(resistanceTypes)) {
                var baseResist = (data.magicdefence && data.magicdefence[key]) ? data.magicdefence[key] : null;
                var finalResist = (finalData.magicdefence && finalData.magicdefence[key]) ? finalData.magicdefence[key] : null;
                if ((TooltipEngine.as2Equal(baseResist, null) || TooltipEngine.as2Equal(TooltipEngine.as2Number(baseResist), 0)) && (TooltipEngine.as2Equal(finalResist, null) || TooltipEngine.as2Equal(TooltipEngine.as2Number(finalResist), 0)))
                    continue;
                var displayName = (TooltipEngine.as2Equal(key, TooltipEngine.TooltipConstants.TXT_BASE) ? TooltipEngine.TooltipConstants.TXT_ENERGY : key);
                var label = displayName + TooltipEngine.TooltipConstants.SUF_RESISTANCE;
                if (!equipData || TooltipEngine.as2Equal(finalResist, baseResist) || TooltipEngine.as2Equal(finalResist, null)) {
                    if (TooltipEngine.as2NotEqual(baseResist, null) && TooltipEngine.as2NotEqual(TooltipEngine.as2Number(baseResist), 0)) {
                        result.push(label, "：", baseResist, "<BR>");
                    }
                }
                else {
                    if (TooltipEngine.as2NotEqual(finalResist, null) && TooltipEngine.as2NotEqual(TooltipEngine.as2Number(finalResist), 0)) {
                        result.push(label, "：<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", finalResist, "</FONT>");
                        if (TooltipEngine.as2Equal(baseResist, null))
                            baseResist = 0;
                        var baseNum = TooltipEngine.as2Number(baseResist);
                        var finalNum = TooltipEngine.as2Number(finalResist);
                        if (TooltipEngine.as2IsNaN(finalNum) || TooltipEngine.as2IsNaN(baseNum)) {
                            result.push(" (覆盖", baseResist, ")<BR>");
                        }
                        else {
                            var enhance = finalNum - baseNum;
                            var sign;
                            if (TooltipEngine.as2Less(enhance, 0)) {
                                enhance = -enhance;
                                sign = " - ";
                            }
                            else {
                                sign = " + ";
                            }
                            result.push(" (", baseResist, sign, enhance, ")<BR>");
                        }
                    }
                }
            }
        }
        ResistanceBlockBuilder.build = build;
    })(ResistanceBlockBuilder = TooltipEngine.ResistanceBlockBuilder || (TooltipEngine.ResistanceBlockBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/ResistanceBuffTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let ResistanceBuffTooltipBuilder;
    (function (ResistanceBuffTooltipBuilder) {
        function build(ctx, effectData) {
            var result = [];
            var rawValue = (TooltipEngine.as2Equal(effectData.value, undefined) || TooltipEngine.as2Equal(effectData.value, ""))
                ? NaN : TooltipEngine.as2Number(effectData.value);
            var value = NaN;
            if (!TooltipEngine.as2IsNaN(rawValue) && TooltipEngine.as2NotEqual(rawValue, 0))
                value = rawValue;
            var rawMult = (TooltipEngine.as2Equal(effectData.mult_positive, undefined) || TooltipEngine.as2Equal(effectData.mult_positive, ""))
                ? NaN : TooltipEngine.as2Number(effectData.mult_positive);
            var mult = NaN;
            if (!TooltipEngine.as2IsNaN(rawMult) && TooltipEngine.as2NotEqual(rawMult, 1))
                mult = rawMult;
            if (TooltipEngine.as2IsNaN(value) && TooltipEngine.as2IsNaN(mult))
                return result;
            var duration = TooltipEngine.as2Number(effectData.duration);
            var durationSuffix = "";
            if (!TooltipEngine.as2IsNaN(duration) && TooltipEngine.as2Greater(duration, 0)) {
                durationSuffix = "（" + TooltipEngine.DrugTooltipUtil.framesToSeconds(ctx, duration)
                    + TooltipEngine.TooltipConstants.TIP_DRUG_SECOND + "）";
            }
            var label = TooltipEngine.DrugTooltipUtil.color(ctx, TooltipEngine.TooltipConstants.LBL_DRUG_BUFF + "：", TooltipEngine.TooltipConstants.COL_HL);
            var property = effectData.property;
            var baseName = "全属性抗性 ";
            if (property && TooltipEngine.as2Greater(property.length, 0)) {
                var displayName = (TooltipEngine.as2Equal(property, TooltipEngine.TooltipConstants.TXT_BASE))
                    ? TooltipEngine.TooltipConstants.TXT_ENERGY : property;
                baseName = displayName + TooltipEngine.TooltipConstants.SUF_RESISTANCE + " ";
            }
            if (!TooltipEngine.as2IsNaN(mult)) {
                result.push(label);
                result.push(baseName + "×" + mult);
                result.push(durationSuffix);
                result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            }
            if (!TooltipEngine.as2IsNaN(value)) {
                result.push(label);
                result.push(baseName + (TooltipEngine.as2Greater(value, 0) ? "+" : "") + value);
                result.push(durationSuffix);
                result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            }
            return result;
        }
        ResistanceBuffTooltipBuilder.build = build;
    })(ResistanceBuffTooltipBuilder = TooltipEngine.ResistanceBuffTooltipBuilder || (TooltipEngine.ResistanceBuffTooltipBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/SilenceEffectBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let SilenceEffectBuilder;
    (function (SilenceEffectBuilder) {
        function build(ctx, result, baseItem, item, data, equipData) {
            var baseSilence = data ? data.silence : null;
            var finalSilence = equipData ? equipData.silence : null;
            var silenceValue = TooltipEngine.as2NotEqual(finalSilence, null) ? finalSilence : baseSilence;
            if (TooltipEngine.as2Equal(silenceValue, null) || TooltipEngine.as2Equal(silenceValue, undefined)) {
                return;
            }
            var silenceStr = String(silenceValue);
            if (TooltipEngine.as2Greater(silenceStr.indexOf("%"), 0)) {
                buildPercentageSilence(ctx, result, silenceStr, baseSilence, finalSilence);
            }
            else {
                buildDistanceSilence(ctx, result, silenceValue, baseSilence, finalSilence);
            }
        }
        SilenceEffectBuilder.build = build;
        function buildPercentageSilence(ctx, result, silenceStr, baseSilence, finalSilence) {
            var percentIndex = silenceStr.indexOf("%");
            var percentValue = silenceStr.substring(0, percentIndex);
            var percentNum = TooltipEngine.as2Number(percentValue);
            if (TooltipEngine.as2IsNaN(percentNum) || TooltipEngine.as2Less(percentNum, 0) || TooltipEngine.as2Greater(percentNum, 100)) {
                return;
            }
            result.push("<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_SILENCE + "'>" + TooltipEngine.TooltipConstants.LBL_SILENCE_EFFECT + "：</FONT>");
            if (TooltipEngine.as2NotEqual(finalSilence, null) && TooltipEngine.as2NotEqual(baseSilence, null) && TooltipEngine.as2NotEqual(finalSilence, baseSilence)) {
                var baseStr = String(baseSilence);
                var isTypeSwitched = (TooltipEngine.as2Less(baseStr.indexOf("%"), 0));
                result.push("<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_HL + "'>", percentValue, "%</FONT> " + TooltipEngine.TooltipConstants.TIP_SILENCE_PERCENT + " <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>(" + TooltipEngine.TooltipConstants.TIP_SILENCE_ORIG);
                if (isTypeSwitched) {
                    result.push(TooltipEngine.TooltipConstants.SUF_DISTANCE + " ", baseSilence);
                }
                else {
                    result.push(baseSilence);
                }
                result.push(")</FONT><BR>");
            }
            else {
                result.push(percentValue, "% " + TooltipEngine.TooltipConstants.TIP_SILENCE_PERCENT + "<BR>");
            }
            result.push("<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>  [" + TooltipEngine.TooltipConstants.TIP_SILENCE_PERCENT_DESC + " ", percentValue, "% " + TooltipEngine.TooltipConstants.TIP_SILENCE_PERCENT_DESC2 + "]</FONT><BR>");
        }
        function buildDistanceSilence(ctx, result, silenceValue, baseSilence, finalSilence) {
            var distanceValue = TooltipEngine.as2Number(silenceValue);
            if (TooltipEngine.as2IsNaN(distanceValue) || TooltipEngine.as2LessEqual(distanceValue, 0)) {
                return;
            }
            result.push("<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_SILENCE + "'>" + TooltipEngine.TooltipConstants.LBL_SILENCE_EFFECT + "：</FONT>");
            if (TooltipEngine.as2NotEqual(finalSilence, null) && TooltipEngine.as2NotEqual(baseSilence, null) && TooltipEngine.as2NotEqual(finalSilence, baseSilence)) {
                var baseStr = String(baseSilence);
                var isTypeSwitched = (TooltipEngine.as2Greater(baseStr.indexOf("%"), 0));
                result.push(TooltipEngine.TooltipConstants.LBL_SILENCE_DISTANCE + " <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_HL + "'>", distanceValue, "</FONT> <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>(" + TooltipEngine.TooltipConstants.TIP_SILENCE_ORIG);
                if (isTypeSwitched) {
                    result.push(TooltipEngine.TooltipConstants.SUF_PERCENT + " ", baseSilence);
                }
                else {
                    result.push(baseSilence);
                }
                result.push(")</FONT><BR>");
            }
            else {
                result.push(TooltipEngine.TooltipConstants.LBL_SILENCE_DISTANCE + " <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_HL + "'>", distanceValue, "</FONT><BR>");
            }
            result.push("<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>  [" + TooltipEngine.TooltipConstants.TIP_SILENCE_DIST_DESC + " ", "<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_HL + "'>", distanceValue, "</FONT>", " " + TooltipEngine.TooltipConstants.TIP_SILENCE_DIST_DESC2 + "]</FONT><BR>");
        }
        function getShortDescription(ctx, silenceValue) {
            if (TooltipEngine.as2Equal(silenceValue, null) || TooltipEngine.as2Equal(silenceValue, undefined)) {
                return "";
            }
            var silenceStr = String(silenceValue);
            if (TooltipEngine.as2Greater(silenceStr.indexOf("%"), 0)) {
                return silenceStr + TooltipEngine.TooltipConstants.TIP_SILENCE_SHORT;
            }
            var distanceValue = TooltipEngine.as2Number(silenceValue);
            if (!TooltipEngine.as2IsNaN(distanceValue) && TooltipEngine.as2Greater(distanceValue, 0)) {
                return ">" + distanceValue + TooltipEngine.TooltipConstants.TIP_SILENCE_SHORT;
            }
            return "";
        }
        SilenceEffectBuilder.getShortDescription = getShortDescription;
    })(SilenceEffectBuilder = TooltipEngine.SilenceEffectBuilder || (TooltipEngine.SilenceEffectBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/SlayEffectBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let SlayEffectBuilder;
    (function (SlayEffectBuilder) {
        function buildFlat(ctx, result, slayValue) {
            if (TooltipEngine.as2Equal(slayValue, null) || TooltipEngine.as2Equal(slayValue, undefined)) {
                return;
            }
            var n = TooltipEngine.as2Number(slayValue);
            if (TooltipEngine.as2IsNaN(n) || n === 0) {
                return;
            }
            var sign = " + ";
            if (TooltipEngine.as2Less(n, 0)) {
                n = -n;
                sign = " - ";
            }
            var label = TooltipEngine.TooltipConstants.PROPERTY_DICT["slay"];
            if (!label)
                label = TooltipEngine.TooltipConstants.LBL_SLAY_SHORT + "线";
            result.push(label, sign, n, TooltipEngine.TooltipConstants.SUF_BLOOD, "<BR>");
        }
        SlayEffectBuilder.buildFlat = buildFlat;
        function buildOverride(ctx, result, slayValue) {
            if (TooltipEngine.as2Equal(slayValue, null) || TooltipEngine.as2Equal(slayValue, undefined)) {
                return;
            }
            var n = TooltipEngine.as2Number(slayValue);
            if (TooltipEngine.as2IsNaN(n)) {
                return;
            }
            var label = TooltipEngine.TooltipConstants.PROPERTY_DICT["slay"];
            if (!label)
                label = TooltipEngine.TooltipConstants.LBL_SLAY_SHORT + "线";
            result.push(label, " -> ", n, TooltipEngine.TooltipConstants.SUF_BLOOD, "<BR>");
        }
        SlayEffectBuilder.buildOverride = buildOverride;
        function getShortDescription(ctx, slayValue) {
            if (TooltipEngine.as2Equal(slayValue, null) || TooltipEngine.as2Equal(slayValue, undefined)) {
                return "";
            }
            var n = TooltipEngine.as2Number(slayValue);
            if (TooltipEngine.as2IsNaN(n) || n === 0) {
                return "";
            }
            return n + TooltipEngine.TooltipConstants.SUF_PERCENT + TooltipEngine.TooltipConstants.LBL_SLAY_SHORT;
        }
        SlayEffectBuilder.getShortDescription = getShortDescription;
    })(SlayEffectBuilder = TooltipEngine.SlayEffectBuilder || (TooltipEngine.SlayEffectBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/StateTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let StateTooltipBuilder;
    (function (StateTooltipBuilder) {
        const _stateKeyDisplayMap = {
            淬毒: null
        };
        function build(ctx, effectData) {
            var result = [];
            var key = effectData.key;
            var value = TooltipEngine.as2Number(effectData.value);
            var scaleWithAlchemy = effectData.scaleWithAlchemy !== false;
            if (!key || TooltipEngine.as2IsNaN(value))
                return result;
            if (TooltipEngine.as2Equal(key, "淬毒")) {
                result.push(TooltipEngine.DrugTooltipUtil.color(ctx, TooltipEngine.TooltipConstants.LBL_POISON + "：" + value, TooltipEngine.TooltipConstants.COL_POISON));
                result.push(TooltipEngine.DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
                result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
                return result;
            }
            var displayName = _stateKeyDisplayMap[key];
            if (TooltipEngine.as2Equal(displayName, undefined)) {
                displayName = key;
            }
            result.push(displayName + "：" + value);
            result.push(TooltipEngine.DrugTooltipUtil.alchemyTag(ctx, scaleWithAlchemy));
            result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            return result;
        }
        StateTooltipBuilder.build = build;
    })(StateTooltipBuilder = TooltipEngine.StateTooltipBuilder || (TooltipEngine.StateTooltipBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/TagSwitchStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let TagSwitchStatsBuilder;
    (function (TagSwitchStatsBuilder) {
        function buildDetailed(ctx, result, stats) {
            if (!stats || !stats.tagSwitch || !stats.tagSwitch.tagCases) {
                return;
            }
            var tagCases = stats.tagSwitch.tagCases;
            if (TooltipEngine.as2Equal(tagCases.length, 0)) {
                return;
            }
            result.push("<font color='" + TooltipEngine.TooltipConstants.COL_TAG_SWITCH + "'>" + TooltipEngine.TooltipConstants.LBL_TAG_SWITCH_EFFECT + "</font><BR>");
            for (var tcIdx = 0; TooltipEngine.as2Less(tcIdx, tagCases.length); tcIdx++) {
                var tagCase = tagCases[tcIdx];
                if (tagCase._isDefault || !tagCase.name) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INFO + "'>" + TooltipEngine.TooltipConstants.TIP_DEFAULT_BRANCH + "：</font><BR>");
                }
                else {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INFO + "'>" + TooltipEngine.TooltipConstants.TIP_WHEN_HAS + " " + tagCase.name + " " + TooltipEngine.TooltipConstants.TIP_TAG_SUFFIX + "：</font><BR>");
                }
                TooltipEngine.UseSwitchStatsBuilder.buildStatBlock(ctx, result, tagCase, "  ");
            }
        }
        TagSwitchStatsBuilder.buildDetailed = buildDetailed;
    })(TagSwitchStatsBuilder = TooltipEngine.TagSwitchStatsBuilder || (TooltipEngine.TagSwitchStatsBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/TooltipComposer.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let TooltipComposer;
    (function (TooltipComposer) {
        function generateItemDescriptionText(ctx, item, baseItem) {
            return generateItemDescriptionTextEx(ctx, item, baseItem, null);
        }
        TooltipComposer.generateItemDescriptionText = generateItemDescriptionText;
        function generateItemDescriptionTextEx(ctx, item, baseItem, subBlocks, docSubs) {
            var buffer = [];
            var itemName = item.name;
            var nightVisionBuffer = (TooltipEngine.as2NotEqual(subBlocks, null) && TooltipEngine.isEquipment(ctx, itemName)) ? [] : null;
            append(ctx, buffer, TooltipEngine.TooltipTextBuilder.buildBasicDescription(ctx, item, baseItem, nightVisionBuffer));
            if (TooltipEngine.isInformation(ctx, itemName)) {
                append(ctx, buffer, TooltipEngine.TooltipTextBuilder.buildStoryTip(ctx, item));
                append(ctx, buffer, TooltipEngine.TooltipTextBuilder.buildSynthesisMaterials(ctx, item));
            }
            else if (TooltipEngine.isMaterial(ctx, itemName)) {
                var modEntry = TooltipEngine.TooltipTextBuilder.buildModStatWithRows(ctx, itemName);
                if (TooltipEngine.as2NotEqual(modEntry, null))
                    pushSub(ctx, buffer, subBlocks, docSubs, [modEntry.html], modEntry);
            }
            else if (TooltipEngine.isEquipment(ctx, itemName)) {
                append(ctx, buffer, TooltipEngine.TooltipTextBuilder.buildBladeSkillMultipliers(ctx, item, baseItem));
                var skillToDisplay = item.skill;
                var subweaponToDisplay = item.subweapon;
                var lightingItem = item;
                var lightingMods = null;
                if (baseItem && TooltipEngine.as2NotEqual(baseItem.getData, undefined)) {
                    var calculatedData = baseItem.getData();
                    if (calculatedData)
                        lightingItem = calculatedData;
                    if (calculatedData && calculatedData.skill !== undefined) {
                        skillToDisplay = calculatedData.skill;
                    }
                    if (calculatedData && calculatedData.subweapon !== undefined) {
                        subweaponToDisplay = calculatedData.subweapon;
                    }
                }
                if (baseItem && baseItem.value)
                    lightingMods = baseItem.value.mods;
                pushSub(ctx, buffer, subBlocks, docSubs, subweaponToDisplay
                    ? TooltipEngine.TooltipTextBuilder.buildSubweaponInfo(ctx, subweaponToDisplay)
                    : TooltipEngine.TooltipTextBuilder.buildSkillInfo(ctx, skillToDisplay));
                if (baseItem) {
                    var modsBuffer = [];
                    var modsEntry = TooltipEngine.ModsBlockBuilder.buildWithRows(ctx, modsBuffer, baseItem, item, baseItem.value);
                    pushSub(ctx, buffer, subBlocks, docSubs, modsBuffer, modsEntry);
                }
                pushSub(ctx, buffer, subBlocks, docSubs, nightVisionBuffer);
                var featBuffer = [];
                append(ctx, featBuffer, TooltipEngine.TooltipTextBuilder.buildLifecycleInfo(ctx, item.lifecyle));
                append(ctx, featBuffer, TooltipEngine.EquipmentLightingInfoBuilder.build(ctx, lightingItem, lightingMods, false));
                pushSub(ctx, buffer, subBlocks, docSubs, featBuffer);
                append(ctx, buffer, TooltipEngine.TooltipTextBuilder.buildUpgradePath(ctx, item, baseItem));
            }
            var obtainBuffer = [];
            var obtainEntry = TooltipEngine.ObtainMethodsBuilder.buildWithRows(ctx, obtainBuffer, itemName);
            pushSub(ctx, buffer, subBlocks, docSubs, obtainBuffer, obtainEntry);
            return buffer.join("");
        }
        TooltipComposer.generateItemDescriptionTextEx = generateItemDescriptionTextEx;
        function pushSub(ctx, buffer, subBlocks, docSubs, block, docEntry) {
            if (TooltipEngine.as2Equal(block, null) || TooltipEngine.as2Equal(block.length, 0))
                return;
            var html = block.join("");
            if (TooltipEngine.as2NotEqual(subBlocks, null)) {
                subBlocks.push(html);
                if (TooltipEngine.as2NotEqual(docSubs, null))
                    docSubs.push(TooltipEngine.as2NotEqual(docEntry, null) ? docEntry : html);
                return;
            }
            append(ctx, buffer, block);
        }
        function getUpgradePathInfo(ctx, item, baseItem) {
            if (TooltipEngine.as2Equal(item, null) || !TooltipEngine.isEquipment(ctx, item.name))
                return null;
            return TooltipEngine.TooltipTextBuilder.buildUpgradePathWithRows(ctx, item, baseItem);
        }
        TooltipComposer.getUpgradePathInfo = getUpgradePathInfo;
        function getRailText(ctx, item, baseItem) {
            if (TooltipEngine.as2Equal(item, null))
                return null;
            var actionEquipment = (TooltipEngine.as2Equal(item.use, "刀") || TooltipEngine.as2Equal(item.use, "手部装备"));
            if (TooltipEngine.as2NotEqual(String(item.type), "武器") && !actionEquipment)
                return null;
            var top = item.use;
            var bottom = actionEquipment ? item.actiontype : item.weapontype;
            if (TooltipEngine.as2NotEqual(baseItem, null) && TooltipEngine.as2NotEqual(baseItem.getData, undefined)) {
                var calc = baseItem.getData();
                if (TooltipEngine.as2NotEqual(calc, null)) {
                    if (calc.use !== undefined && TooltipEngine.as2NotEqual(calc.use, ""))
                        top = calc.use;
                    if (actionEquipment && calc.actiontype !== undefined && TooltipEngine.as2NotEqual(calc.actiontype, "")) {
                        bottom = calc.actiontype;
                    }
                    else if (!actionEquipment && calc.weapontype !== undefined && TooltipEngine.as2NotEqual(calc.weapontype, "")) {
                        bottom = calc.weapontype;
                    }
                }
            }
            if (actionEquipment && (TooltipEngine.as2Equal(bottom, null) || TooltipEngine.as2Equal(bottom, "")))
                bottom = "默认";
            if (TooltipEngine.as2Equal(top, TooltipEngine.ItemUseTypes.MELEE))
                top = "冷兵器";
            var rail = [];
            if (TooltipEngine.as2NotEqual(top, null) && TooltipEngine.as2NotEqual(top, ""))
                rail.push(String(top));
            if (TooltipEngine.as2NotEqual(bottom, null) && TooltipEngine.as2NotEqual(bottom, "")) {
                var bottomText = String(bottom);
                if (TooltipEngine.as2Equal(rail.length, 0) || TooltipEngine.as2NotEqual(rail[0], bottomText))
                    rail.push(bottomText);
            }
            return TooltipEngine.as2Greater(rail.length, 0) ? rail : null;
        }
        TooltipComposer.getRailText = getRailText;
        function getMagazineInfo(ctx, baseItem, item, externalValue) {
            if (TooltipEngine.as2Equal(item, null) || !TooltipEngine.ItemUseTypes.isGun(item.use))
                return null;
            var value = baseItem && baseItem.value ? baseItem.value : (externalValue ? externalValue : 1);
            var upgradeLevel = value.level ? value.level : 1;
            var data = ctx.projection.baselineData;
            if (TooltipEngine.as2Equal(data, null))
                return null;
            var clipName = data.clipname;
            if (TooltipEngine.as2NotEqual(baseItem, null) && TooltipEngine.as2NotEqual(baseItem.getData, undefined) && (TooltipEngine.as2Greater(upgradeLevel, 1) || value.mods)) {
                var equipData = baseItem.getData().data;
                if (TooltipEngine.as2NotEqual(equipData, null) && equipData.clipname !== undefined)
                    clipName = equipData.clipname;
            }
            if (TooltipEngine.as2Equal(clipName, null) || TooltipEngine.as2Equal(clipName, ""))
                return null;
            var clipData = TooltipEngine.lookupItem(ctx, clipName);
            if (TooltipEngine.as2Equal(clipData, null))
                return null;
            var displayName = clipData.displayname;
            if (TooltipEngine.as2Equal(displayName, undefined) || TooltipEngine.as2Equal(displayName, ""))
                displayName = clipName;
            var out = { name: String(displayName) };
            if (TooltipEngine.as2NotEqual(clipData.icon, undefined) && TooltipEngine.as2NotEqual(clipData.icon, ""))
                out.icon = String(clipData.icon);
            var baseBullet = data.bulletrename ? data.bulletrename : data.bullet;
            var finalBullet = baseBullet;
            if (TooltipEngine.as2NotEqual(baseItem, null) && TooltipEngine.as2NotEqual(baseItem.getData, undefined) && (TooltipEngine.as2Greater(upgradeLevel, 1) || value.mods)) {
                var bulletData = baseItem.getData().data;
                if (TooltipEngine.as2NotEqual(bulletData, null) && bulletData.bullet) {
                    finalBullet = bulletData.bulletrename ? bulletData.bulletrename : bulletData.bullet;
                }
            }
            if (TooltipEngine.as2NotEqual(finalBullet, null) && TooltipEngine.as2NotEqual(finalBullet, ""))
                out.ammo = String(finalBullet);
            return out;
        }
        TooltipComposer.getMagazineInfo = getMagazineInfo;
        function generateIntroPanelContent(ctx, baseItem, item, value, nativeOpt) {
            var buffer = [];
            append(ctx, buffer, TooltipEngine.TooltipTextBuilder.buildIntroHeader(ctx, baseItem, item, value, nativeOpt));
            append(ctx, buffer, TooltipEngine.TooltipTextBuilder.buildStats(ctx, baseItem, item, value, nativeOpt));
            if (item.type === "武器" || item.type === "防具") {
                append(ctx, buffer, TooltipEngine.TooltipTextBuilder.buildEquipmentTagInfo(ctx, item));
            }
            return buffer.join("");
        }
        TooltipComposer.generateIntroPanelContent = generateIntroPanelContent;
        function append(ctx, destination, source) {
            if (TooltipEngine.as2Equal(source, null))
                return;
            var index = 0;
            var length = source.length;
            while (TooltipEngine.as2Less(index, length)) {
                destination.push(source[index]);
                index++;
            }
        }
    })(TooltipComposer = TooltipEngine.TooltipComposer || (TooltipEngine.TooltipComposer = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/TooltipConstants.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let TooltipConstants;
    (function (TooltipConstants) {
        TooltipConstants.COL_HL = "#FFCC00";
        TooltipConstants.COL_AMMO_CHAMBER = "#9BE0E9";
        TooltipConstants.COL_AMMO_GHOST = "#FFCC70";
        TooltipConstants.COL_AMMO_REWARD = "#CAADFF";
        TooltipConstants.COL_HP = "#00FF00";
        TooltipConstants.COL_MP = "#00FFFF";
        TooltipConstants.COL_CRIT = "#DD4455";
        TooltipConstants.COL_POISON = "#66dd00";
        TooltipConstants.COL_VAMP = "#bb00aa";
        TooltipConstants.COL_ROUT = "#FF3333";
        TooltipConstants.COL_DMG = "#0099FF";
        TooltipConstants.COL_BREAK_LIGHT = "#66bcf5";
        TooltipConstants.COL_BREAK_MAIN = "#CC6600";
        TooltipConstants.COL_INFO = "#FFCC00";
        TooltipConstants.COL_ENHANCE = "#88FF88";
        TooltipConstants.COL_SILENCE = "#9999FF";
        TooltipConstants.COL_MULTIPLIER = "#FF6600";
        TooltipConstants.COL_MULTIPLIER_HINT = "#FF9944";
        TooltipConstants.COL_CURVE = "#66DDAA";
        TooltipConstants.COL_USE_SWITCH = "#FFCC66";
        TooltipConstants.COL_TAG_SWITCH = "#88CCFF";
        TooltipConstants.COL_COND_PROVIDE = "#99FF99";
        TooltipConstants.COL_INSTALL_COND = "#FFAA44";
        TooltipConstants.COL_BULLET_SWITCH = "#FF99CC";
        TooltipConstants.COL_CRAFT = "#99CCFF";
        TooltipConstants.COL_SHOP = "#99FF99";
        TooltipConstants.COL_KSHOP = "#FFCC99";
        TooltipConstants.COL_DROP_STAGE = "#FFFF99";
        TooltipConstants.COL_DROP_ENEMY = "#FF99CC";
        TooltipConstants.COL_DROP_ARENA = "#FFCC66";
        TooltipConstants.COL_QUEST = "#CC99FF";
        TooltipConstants.SUF_PERCENT = "%";
        TooltipConstants.SUF_HP = "HP";
        TooltipConstants.SUF_MP = "MP";
        TooltipConstants.SUF_SP = "SP";
        TooltipConstants.SUF_BLOOD = "%血量";
        TooltipConstants.SUF_SECOND = "秒";
        TooltipConstants.SUF_FIRE_RATE = "发/秒";
        TooltipConstants.SUF_KG = "kg";
        TooltipConstants.SUF_DISTANCE = "距离";
        TooltipConstants.SUF_RESISTANCE = "抗性";
        TooltipConstants.TXT_NONE = "无";
        TooltipConstants.TXT_ENERGY = "能量";
        TooltipConstants.TXT_MAGIC = "魔法";
        TooltipConstants.TXT_BREAK = "破击";
        TooltipConstants.TXT_BASE = "基础";
        TooltipConstants.TXT_OVERRIDE = "覆盖";
        TooltipConstants.TXT_MERGE = "合并";
        TooltipConstants.TXT_GROUP = "群体";
        TooltipConstants.LBL_SKILL_BONUS = "【技能加成】";
        TooltipConstants.LBL_ACTIVE_SKILL = "【主动战技】";
        TooltipConstants.LBL_SKILL_INFO = "【战技信息】";
        TooltipConstants.LBL_SUBWEAPON = "【副武器】";
        TooltipConstants.LBL_SUBWEAPON_INFO = "【副武器信息】";
        TooltipConstants.LBL_AFFIX_INFO = "【词条信息】";
        TooltipConstants.LBL_MOD_INFO = "【配件信息】";
        TooltipConstants.LBL_USE_SWITCH_EFFECT = "【按装备类型追加效果】";
        TooltipConstants.LBL_TAG_SWITCH_EFFECT = "【按结构标签追加效果】";
        TooltipConstants.LBL_BULLET_SWITCH_EFFECT = "【按弹药类型追加效果】";
        TooltipConstants.LBL_COND_PROVIDE_TAGS = "条件性提供结构";
        TooltipConstants.LBL_COND_REQUIRE_TAGS = "条件性前置需求";
        TooltipConstants.TAG_OVERRIDE = "[覆盖]";
        TooltipConstants.TAG_MERGE = "[合并]";
        TooltipConstants.TAG_MULTIPLIER_ZONE = "[独立乘区]";
        TooltipConstants.TAG_CURVE = "[曲线]";
        TooltipConstants.LBL_CURVE_COMPRESSION_LEVEL = "压缩等级";
        TooltipConstants.LBL_CLIP_NAME = "使用弹夹";
        TooltipConstants.LBL_BULLET_TYPE = "子弹类型";
        TooltipConstants.LBL_CAPACITY = "弹夹容量";
        TooltipConstants.LBL_BURST_COUNT = "点射弹数";
        TooltipConstants.LBL_PELLET_COUNT = "弹丸数量";
        TooltipConstants.LBL_FIRE_RATE = "射速";
        TooltipConstants.LBL_IMPACT = "冲击力";
        TooltipConstants.LBL_BULLET_SIZE = "纵向攻击范围";
        TooltipConstants.LBL_FIRE_MODE = "射击模式";
        TooltipConstants.TIP_FIRE_MODE_AUTO = "全自动";
        TooltipConstants.TIP_FIRE_MODE_SEMI = "半自动";
        TooltipConstants.LBL_RELOAD_TYPE = "装填形式";
        TooltipConstants.LBL_GHOST_LIMIT = "幽灵装填上限";
        TooltipConstants.TIP_RELOAD_TYPE_MAG = "整匣换弹";
        TooltipConstants.TIP_RELOAD_TYPE_TUBE = "逐发装填";
        TooltipConstants.LBL_RELOAD_PENALTY = "换弹延迟";
        TooltipConstants.LBL_RELOAD_BONUS = "换弹加速";
        TooltipConstants.SUF_RELOAD_PENALTY = "帧";
        TooltipConstants.LBL_POWER = "威力";
        TooltipConstants.LBL_SHARPNESS = "锋利度";
        TooltipConstants.LBL_BULLET_POWER = "子弹威力";
        TooltipConstants.LBL_ACTION = "动作";
        TooltipConstants.LBL_ACTION_TYPE = "动作类型";
        TooltipConstants.LBL_WEAPON_TYPE = "武器类型";
        TooltipConstants.LBL_UPGRADE_LEVEL = "强化等级";
        TooltipConstants.LBL_QUANTITY = "数量";
        TooltipConstants.LBL_SYNTHESIS = "合成材料";
        TooltipConstants.LBL_COOLDOWN = "冷却";
        TooltipConstants.LBL_COST = "消耗";
        TooltipConstants.LBL_CLEAN = "净化度";
        TooltipConstants.LBL_POISON = "剧毒性";
        TooltipConstants.LBL_INSTALLED_MODS = "已安装";
        TooltipConstants.LBL_LIGHTING_INFO = "【照明效果】";
        TooltipConstants.LBL_MOD_COUNT_SUFFIX = "个配件";
        TooltipConstants.LBL_SLAY_SHORT = "斩杀";
        TooltipConstants.LBL_MOD_USE_TYPE = "适用装备类型";
        TooltipConstants.LBL_MOD_SLOT = "插件位置";
        TooltipConstants.LBL_MOD_WEAPON_TYPE = "适用武器子类";
        TooltipConstants.LBL_MOD_EXCLUDE_WEAPON_TYPE = "排除武器子类";
        TooltipConstants.LBL_PROVIDE_TAGS = "提供结构";
        TooltipConstants.LBL_REQUIRE_TAGS = "前置需求";
        TooltipConstants.LBL_EXCLUDE_BULLET_TYPES = "排斥弹药类型";
        TooltipConstants.LBL_REQUIRE_BULLET_TYPES = "要求弹药类型";
        TooltipConstants.LBL_INSTALL_CONDITION = "安装条件";
        TooltipConstants.LBL_INHERENT_TAGS = "固有结构";
        TooltipConstants.LBL_BLOCKED_TAGS = "禁止挂点";
        TooltipConstants.LBL_MOD_GRANTS_USE = "扩展装备类型池";
        TooltipConstants.LBL_MOD_GRANTS_WEAPON_TYPE = "扩展武器子类";
        TooltipConstants.LBL_SCOPE_USE = "装备类型";
        TooltipConstants.LBL_SCOPE_WEAPON_TYPE = "武器子类";
        TooltipConstants.LBL_HIT_BEHAVIOR = "命中行为标记";
        TooltipConstants.LBL_GRAY_GOO_BEHAVIOR = "灰蛊蚀刻";
        TooltipConstants.LBL_MARK_DURATION = "命中维持";
        TooltipConstants.LBL_BREAK_EXTEND = "破韧续时";
        TooltipConstants.LBL_MAX_DURATION = "持续上限";
        TooltipConstants.LBL_MAX_STACKS = "最多叠加";
        TooltipConstants.LBL_DAMAGE_PER_STACK = "每层易伤";
        TooltipConstants.LBL_DECAY_DELAY = "停火衰减等待";
        TooltipConstants.LBL_DECAY_INTERVAL = "逐层衰减间隔";
        TooltipConstants.LBL_HIT_STACKS = "每次命中沉积";
        TooltipConstants.LBL_BREAK_STACKS = "真实破韧追加";
        TooltipConstants.LBL_MILESTONE_INTERVAL = "击溃节点";
        TooltipConstants.LBL_CRUMBLE_PER_MILESTONE = "节点击溃";
        TooltipConstants.LBL_EXECUTE_AT_MAX = "满层斩杀";
        TooltipConstants.TIP_SAME_SOURCE_ONLY = "仅施加者破韧可叠层";
        TooltipConstants.BULLET_TYPE_NAMES = {
            pierce: "穿刺",
            melee: "近战",
            chain: "联弹",
            grenade: "手雷",
            explosive: "爆炸",
            normal: "普通",
            vertical: "纵向",
            transparency: "透明"
        };
        TooltipConstants.LBL_OBTAIN_METHODS = "【获取方式】";
        TooltipConstants.TIP_OBTAIN_CRAFT = "合成：";
        TooltipConstants.TIP_OBTAIN_SHOP = "商店：";
        TooltipConstants.TIP_OBTAIN_KSHOP = "K点商城：";
        TooltipConstants.TIP_OBTAIN_STAGE = "关卡：";
        TooltipConstants.TIP_OBTAIN_ENEMY = "掉落：";
        TooltipConstants.TIP_OBTAIN_ARENA = "竞技场：";
        TooltipConstants.TIP_OBTAIN_ARENA_CARRIER = "携带该装备的佣兵";
        TooltipConstants.TIP_OBTAIN_ARENA_SPECIFIC_CARRIER = "携带该装备的特定佣兵";
        TooltipConstants.TIP_OBTAIN_QUEST = "任务：";
        TooltipConstants.LBL_UPGRADE_PATH = "【升阶路线】";
        TooltipConstants.TIP_UPGRADE_FROM = "升自：";
        TooltipConstants.TIP_UPGRADE_TO = "可升：";
        TooltipConstants.TIP_TIER_OPTIONS = "可进阶：";
        TooltipConstants.TIP_TIER_CURRENT = "「当前」";
        TooltipConstants.UPGRADE_MAX_TO_PRODUCTS = 3;
        TooltipConstants.LBL_DAMAGE_ATTR = "伤害属性";
        TooltipConstants.LBL_EXTRA_DAMAGE = "附加伤害";
        TooltipConstants.LBL_BREAK_TYPE = "破击类型";
        TooltipConstants.LBL_DAMAGE_TYPE = "伤害类型";
        TooltipConstants.LBL_SILENCE_EFFECT = "消音效果";
        TooltipConstants.LBL_SILENCE_DISTANCE = "距离 >";
        TooltipConstants.TIP_SILENCE_PERCENT = "概率消音成功";
        TooltipConstants.TIP_SILENCE_PERCENT_DESC = "攻击时有";
        TooltipConstants.TIP_SILENCE_PERCENT_DESC2 = "几率不触发敌人仇恨";
        TooltipConstants.TIP_SILENCE_DIST_DESC = "攻击超过";
        TooltipConstants.TIP_SILENCE_DIST_DESC2 = "距离的目标不触发仇恨";
        TooltipConstants.TIP_SILENCE_SHORT = "消音";
        TooltipConstants.TIP_SILENCE_ORIG_DIST = "原距离";
        TooltipConstants.TIP_SILENCE_ORIG_PERCENT = "原概率";
        TooltipConstants.TIP_SILENCE_ORIG = "原";
        TooltipConstants.LBL_CRIT = "暴击";
        TooltipConstants.TIP_CRIT_CHANCE = "概率造成1.5倍伤害";
        TooltipConstants.TIP_CRIT_FULL_HP = "满血暴击";
        TooltipConstants.TIP_CRIT_FULL_HP_DESC = "对满血敌人造成1.5倍伤害";
        TooltipConstants.TIP_INFO_LOCATION = "详细信息可在物品栏的情报界面查阅";
        TooltipConstants.TIP_ALLY_EFFECT = "全体友方有效";
        TooltipConstants.TIP_NO_BONUS_DATA = "无加成数据";
        TooltipConstants.TIP_EQUIP_BONUS_PREFIX = "对装备";
        TooltipConstants.TIP_EQUIP_BONUS_SUFFIX = "的加成";
        TooltipConstants.TIP_SHARPNESS_BONUS = "锋利度增益";
        TooltipConstants.TIP_USE = "使用";
        TooltipConstants.TIP_ENJOY = "享受";
        TooltipConstants.TIP_CAP_UPPER = "增益上限";
        TooltipConstants.TIP_CAP_LOWER = "减益下限";
        TooltipConstants.TIP_FOR = "对";
        TooltipConstants.TIP_ETC = "等";
        TooltipConstants.TIP_OBTAIN_MORE = "个";
        TooltipConstants.TIP_WHEN_HAS = "当存在";
        TooltipConstants.TIP_TAG_SUFFIX = "时";
        TooltipConstants.TIP_BULLET_FOR = "对于";
        TooltipConstants.TIP_BULLET_SUFFIX = "类子弹";
        TooltipConstants.TIP_DEFAULT_BRANCH = "其他情况";
        TooltipConstants.LBL_DRUG_REGEN = "缓释";
        TooltipConstants.LBL_DRUG_BUFF = "Buff";
        TooltipConstants.LBL_DRUG_GRANT = "获得";
        TooltipConstants.LBL_DRUG_GRANT_HIDDEN = "可能获得额外物品";
        TooltipConstants.LBL_DRUG_NO_ALCHEMY = "(无炼金)";
        TooltipConstants.LBL_DRUG_REGEN_OVERRIDE = "（覆盖同类缓释）";
        TooltipConstants.TIP_DRUG_SECOND = "秒";
        TooltipConstants.TIP_DRUG_PER_TICK = "/次";
        TooltipConstants.TIP_DRUG_INTERVAL = "，每";
        TooltipConstants.TIP_DRUG_RECOVER = "秒恢复";
        TooltipConstants.TIP_DRUG_CHANCE = "概率";
        TooltipConstants.OBTAIN_MAX_CRAFTS = 3;
        TooltipConstants.OBTAIN_MAX_SHOPS = 5;
        TooltipConstants.OBTAIN_MAX_KSHOPS = 2;
        TooltipConstants.OBTAIN_MAX_STAGES = 4;
        TooltipConstants.OBTAIN_MAX_ENEMIES = 4;
        TooltipConstants.OBTAIN_MAX_ARENAS = 2;
        TooltipConstants.OBTAIN_MAX_QUESTS = 3;
        TooltipConstants.FRAME_INTRO = "简介";
        TooltipConstants.FRAME_EQUIPMENT = "装备";
        TooltipConstants.ICON_PREFIX = "图标-";
        TooltipConstants.SUFFIX_TEXTBOX = "文本框";
        TooltipConstants.SUFFIX_BG = "背景";
        TooltipConstants.BASE_NUM = 200;
        TooltipConstants.RATE = 0.6;
        TooltipConstants.BASE_SCALE = 486.8;
        TooltipConstants.BASE_OFFSET = 7.5;
        TooltipConstants.MIN_W = 150;
        TooltipConstants.MAX_W = 650;
        TooltipConstants.TEXT_PAD = 10;
        TooltipConstants.BG_HEIGHT_OFFSET = 20;
        TooltipConstants.SPLIT_THRESHOLD = 96;
        TooltipConstants.CHAR_CJK_WIDTH = 8;
        TooltipConstants.CHAR_LATIN_WIDTH = 5;
        TooltipConstants.CHAR_AVG_WIDTH = 0.5;
        TooltipConstants.MAIN_CHAR_AVG_WIDTH = 0.75;
        TooltipConstants.OFFSET_X = 0;
        TooltipConstants.OFFSET_Y = 0;
        TooltipConstants.TEXT_Y_EQUIPMENT = 210;
        TooltipConstants.TEXT_Y_BASE = 10;
        TooltipConstants.MOUSE_OFFSET = 20;
        TooltipConstants.HEIGHT_ADJUST = 10;
        TooltipConstants.ICON_SCALE = 150;
        TooltipConstants.ICON_OFFSET = 19;
        TooltipConstants.DEPTH_INCREMENT = 1;
        TooltipConstants.SMART_TOTAL_MULTIPLIER = 2;
        TooltipConstants.SMART_DESC_DIVISOR = 2;
        TooltipConstants.LINE_WIDTH_SCALE = 5.5;
        TooltipConstants.LINE_GUTTER = 20;
        TooltipConstants.INTRO_MAX_W = 300;
        TooltipConstants.DUAL_PANEL_MARGIN = 40;
        TooltipConstants.PIX_PER_UNIT = 6.0;
        TooltipConstants.LINE_HEIGHT = 15;
        TooltipConstants.RATIO_MIN = 0.618;
        TooltipConstants.RATIO_MAX = 1.5;
        TooltipConstants.RATIO_SCORE_CAP = 300;
        TooltipConstants.MAX_RENDERED_LINES = 32;
        TooltipConstants.BALANCE_MAX_ITER = 8;
        TooltipConstants.BALANCE_PRECISION = 2;
        TooltipConstants.MERGE_MAX_INTRO_LINES = 20;
        TooltipConstants.PROPERTY_DICT = {
            level: "等级限制",
            weight: "重量",
            defence: "防御",
            hp: "<FONT COLOR='" + TooltipConstants.COL_HP + "'>HP</FONT>",
            mp: "<FONT COLOR='" + TooltipConstants.COL_MP + "'>MP</FONT>",
            power: "威力",
            damage: "伤害加成",
            punch: "空手加成",
            knifepower: "冷兵器加成",
            gunpower: "枪械加成",
            force: "内力加成",
            clipname: "使用弹夹",
            singleshoot: "射击模式",
            reloadType: "装填形式",
            capacity: "弹夹容量",
            interval: "射击间隔",
            diffusion: "子弹散射度",
            velocity: "出膛速度",
            bulletsize: "纵向攻击范围",
            impact: "冲击力",
            split: "弹丸数量",
            reloadPenalty: "换弹延迟",
            silence: "<FONT COLOR='" + TooltipConstants.COL_SILENCE + "'>消音效果</FONT>",
            accuracy: "命中加成",
            evasion: "挡拆加成",
            toughness: "韧性加成",
            lazymiss: "高危回避",
            poison: "<FONT COLOR='" + TooltipConstants.COL_POISON + "'>剧毒性</FONT>",
            vampirism: "<FONT COLOR='" + TooltipConstants.COL_VAMP + "'>吸血</FONT>",
            rout: "<FONT COLOR='" + TooltipConstants.COL_ROUT + "'>击溃</FONT>",
            slay: "斩杀线",
            magictype: "伤害属性",
            actiontype: "动作类型"
        };
        TooltipConstants.PROPERTY_PRIORITIES = {
            level: 0,
            weight: 1,
            power: 2,
            singleshoot: 10,
            reloadType: 10.5,
            clipname: 11,
            capacity: 12,
            interval: 13,
            diffusion: 14,
            velocity: 15,
            bulletsize: 16,
            impact: 17,
            split: 17.5,
            reloadPenalty: 18,
            silence: 19,
            force: 21,
            damage: 22,
            punch: 23,
            knifepower: 24,
            gunpower: 25,
            accuracy: 31,
            evasion: 32,
            toughness: 33,
            lazymiss: 34,
            poison: 41,
            vampirism: 42,
            rout: 43,
            slay: 44,
            magictype: 51,
            actiontype: 91,
            defence: 101,
            hp: 102,
            mp: 103
        };
    })(TooltipConstants = TooltipEngine.TooltipConstants || (TooltipEngine.TooltipConstants = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/TooltipFormatter.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let TooltipFormatter;
    (function (TooltipFormatter) {
        const DISPLAY_SNAP_EPSILON = 0.000000000001;
        const DISPLAY_SNAP_MAX_DECIMALS = 6;
        function snapDisplayNumber(value) {
            if (TooltipEngine.as2IsNaN(value) || !TooltipEngine.as2IsFinite(value))
                return value;
            var scale = 1;
            for (var digits = 0; TooltipEngine.as2LessEqual(digits, DISPLAY_SNAP_MAX_DECIMALS); digits++) {
                var scaled = value * scale;
                if (!TooltipEngine.as2IsFinite(scaled))
                    return value;
                var snapped = Math.round(scaled) / scale;
                if (TooltipEngine.as2LessEqual(Math.abs(value - snapped), DISPLAY_SNAP_EPSILON)) {
                    return TooltipEngine.as2Equal(snapped, 0) ? 0 : snapped;
                }
                scale *= 10;
            }
            return value;
        }
        function formatDisplayValue(value) {
            if (TooltipEngine.as2NotEqual(typeof value, "number"))
                return String(value);
            return String(snapDisplayNumber(TooltipEngine.as2Number(value)));
        }
        function bold(s) {
            return "<B>" + s + "</B>";
        }
        TooltipFormatter.bold = bold;
        function color(s, hex) {
            return "<FONT COLOR='" + hex + "'>" + s + "</FONT>";
        }
        TooltipFormatter.color = color;
        function br() {
            return "<BR>";
        }
        TooltipFormatter.br = br;
        function normalizeDescription(text) {
            var normalized = text.split("\r\n").join("\n");
            var lines = normalized.split("\n");
            var result = "";
            for (var i = 0; TooltipEngine.as2Less(i, lines.length); i++) {
                var line = lines[i];
                var j = 0;
                while (TooltipEngine.as2Less(j, line.length) && (TooltipEngine.as2Equal(line.charAt(j), " ") || TooltipEngine.as2Equal(line.charAt(j), "\t"))) {
                    j++;
                }
                line = line.substring(j);
                if (TooltipEngine.as2Equal(i, 0)) {
                    result = line;
                }
                else {
                    if (TooltipEngine.as2Equal(line.substring(0, 4).toUpperCase(), "<BR>")) {
                        result += line;
                    }
                    else {
                        result += "<BR>" + line;
                    }
                }
            }
            return result;
        }
        TooltipFormatter.normalizeDescription = normalizeDescription;
        function kv(label, val, suffix) {
            if (suffix === undefined)
                suffix = "";
            return label + "：" + val + suffix;
        }
        TooltipFormatter.kv = kv;
        function numLine(buf, label, val, suffix) {
            if (val === undefined || val === null)
                return;
            var n = TooltipEngine.as2Number(val);
            if (!TooltipEngine.as2IsNaN(n) && n === 0)
                return;
            if (val === "" || TooltipEngine.as2Equal(val, "0") || TooltipEngine.as2Equal(val, "null"))
                return;
            buf.push(label, "：", (TooltipEngine.as2IsNaN(n) ? val : n), (suffix ? suffix : ""), "<BR>");
        }
        TooltipFormatter.numLine = numLine;
        function upgradeLine(buf, data, equipData, property, label, suffix, afterValueHtml) {
            var base = data?.[property];
            var final = equipData?.[property];
            if (!base && !final)
                return;
            if (!label)
                label = TooltipEngine.TooltipConstants.PROPERTY_DICT[property];
            if (!label)
                label = property;
            if (!suffix)
                suffix = "";
            if (!afterValueHtml)
                afterValueHtml = "";
            if (!equipData || TooltipEngine.as2Equal(final, base)) {
                buf.push(label, "：", formatDisplayValue(base), suffix, afterValueHtml, "<BR>");
                return;
            }
            if (TooltipEngine.as2Equal(base, null))
                base = 0;
            if (TooltipEngine.as2IsNaN(final) || TooltipEngine.as2IsNaN(base)) {
                buf.push(label, "：<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_HL + "'>", formatDisplayValue(final), suffix, "</FONT>", afterValueHtml);
                buf.push(" (" + TooltipEngine.TooltipConstants.TXT_OVERRIDE + formatDisplayValue(base) + ")<BR>");
            }
            else {
                var displayBase = snapDisplayNumber(TooltipEngine.as2Number(base));
                var displayFinal = snapDisplayNumber(TooltipEngine.as2Number(final));
                var enhance = snapDisplayNumber(displayFinal - displayBase);
                if (TooltipEngine.as2Equal(enhance, 0)) {
                    buf.push(label, "：", displayFinal, suffix, afterValueHtml, "<BR>");
                    return;
                }
                buf.push(label, "：<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_HL + "'>", displayFinal, suffix, "</FONT>", afterValueHtml);
                var sign;
                if (TooltipEngine.as2Less(enhance, 0)) {
                    enhance = -enhance;
                    sign = " - ";
                }
                else {
                    sign = " + ";
                }
                buf.push(" (", displayBase, sign, enhance, ")<BR>");
            }
        }
        TooltipFormatter.upgradeLine = upgradeLine;
        function colorLine(buf, hex, text) {
            if (TooltipEngine.as2Equal(text, undefined) || TooltipEngine.as2Equal(text, ""))
                return;
            buf.push("<FONT COLOR='" + hex + "'>", text, "</FONT><BR>");
        }
        TooltipFormatter.colorLine = colorLine;
        function enhanceLine(buf, type, data, property, val, label) {
            var base = data?.[property];
            if (!val)
                return;
            if (!label)
                label = TooltipEngine.TooltipConstants.PROPERTY_DICT[property];
            if (!label)
                label = property;
            if (type === "add") {
                var n = TooltipEngine.as2Number(val);
                if (TooltipEngine.as2IsNaN(n) || n === 0)
                    return;
                var sign = " + ";
                if (TooltipEngine.as2Less(n, 0)) {
                    n = -n;
                    sign = " - ";
                }
                buf.push(label, sign, n, "<BR>");
            }
            else if (type === "multiply") {
                if (!base)
                    return;
                var n = (TooltipEngine.as2Number(val) * 100) >> 0;
                var sign = " + ";
                if (TooltipEngine.as2Less(n, 0)) {
                    n = -n;
                    sign = " - ";
                }
                if (TooltipEngine.as2IsNaN(n) || n === 0)
                    return;
                buf.push(label, sign, n, "%<BR>");
            }
            else if (type === "override") {
                buf.push(label, " -> ", val, "<BR>");
            }
        }
        TooltipFormatter.enhanceLine = enhanceLine;
        function statLine(buf, type, property, val, label) {
            if (!val)
                return;
            if (!label)
                label = TooltipEngine.TooltipConstants.PROPERTY_DICT[property];
            if (!label)
                label = property;
            if (type === "add") {
                var n = TooltipEngine.as2Number(val);
                if (TooltipEngine.as2IsNaN(n) || n === 0)
                    return;
                var sign = " + ";
                if (TooltipEngine.as2Less(n, 0)) {
                    n = -n;
                    sign = " - ";
                }
                buf.push(label, sign, n, "<BR>");
            }
            else if (type === "multiply") {
                var n = (TooltipEngine.as2Number(val) * 100) >> 0;
                var sign = " + ";
                if (TooltipEngine.as2Less(n, 0)) {
                    n = -n;
                    sign = " - ";
                }
                if (TooltipEngine.as2IsNaN(n) || n === 0)
                    return;
                buf.push(label, sign, n, "%<BR>");
            }
            else if (type === "override") {
                buf.push(label, " -> ", val, "<BR>");
            }
            else if (type === "merge") {
                buf.push("<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>" + TooltipEngine.TooltipConstants.TAG_MERGE + "</FONT> ", label, " -> ", val, "<BR>");
            }
        }
        TooltipFormatter.statLine = statLine;
    })(TooltipFormatter = TooltipEngine.TooltipFormatter || (TooltipEngine.TooltipFormatter = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/TooltipTextBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let TooltipTextBuilder;
    (function (TooltipTextBuilder) {
        function buildOperationPrefix(ctx, operationType) {
            if (!operationType)
                return "";
            return "<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>[" + operationType + "]</FONT> ";
        }
        function buildBasicDescription(ctx, item, baseItem, nightVisionBuffer) {
            var result = [];
            var description = item.description;
            if (baseItem && TooltipEngine.as2NotEqual(baseItem.getData, undefined)) {
                var calculatedData = baseItem.getData();
                if (calculatedData && calculatedData.description !== undefined) {
                    description = calculatedData.description;
                }
            }
            if (description) {
                var normalized = TooltipEngine.TooltipFormatter.normalizeDescription(description);
                if (TooltipEngine.as2NotEqual(nightVisionBuffer, null)) {
                    normalized = extractNightVisionLines(ctx, normalized, nightVisionBuffer);
                }
                if (normalized)
                    result.push(normalized, TooltipEngine.TooltipFormatter.br());
            }
            return result;
        }
        TooltipTextBuilder.buildBasicDescription = buildBasicDescription;
        function extractNightVisionLines(ctx, normalized, output) {
            var lines = normalized.split("<BR>");
            var mainLines = [];
            for (var i = 0; TooltipEngine.as2Less(i, lines.length); i++) {
                var line = lines[i];
                if (TooltipEngine.as2GreaterEqual(line.indexOf("【夜视】"), 0)) {
                    output.push(line, TooltipEngine.TooltipFormatter.br());
                }
                else {
                    mainLines.push(line);
                }
            }
            return mainLines.join("<BR>");
        }
        function buildStoryTip(ctx, item) {
            var result = [];
            if (TooltipEngine.as2Equal(item.use, TooltipEngine.ItemUseTypes.INFORMATION)) {
                result.push(TooltipEngine.TooltipFormatter.color(TooltipEngine.TooltipConstants.TIP_INFO_LOCATION, TooltipEngine.TooltipConstants.COL_INFO), TooltipEngine.TooltipFormatter.br());
            }
            return result;
        }
        TooltipTextBuilder.buildStoryTip = buildStoryTip;
        function buildSynthesisMaterials(ctx, item) {
            var result = [];
            if (ctx.catalog.recipesUnavailable && TooltipEngine.as2NotEqual(item.synthesis, null)) {
                var targets = ctx.catalog.recipeTargets;
                if (!targets || targets[item.synthesis] || (item.name && targets[item.name])) {
                    result.push(TooltipEngine.TooltipConstants.LBL_SYNTHESIS, "：合成材料暂不可用<BR>");
                }
                return result;
            }
            var synthData = TooltipEngine.lookupRecipe(ctx, item.synthesis);
            if (TooltipEngine.as2NotEqual(item.synthesis, null) && synthData && synthData.materials) {
                var requirements = synthData.materials;
                if (requirements && TooltipEngine.as2Greater(requirements.length, 0)) {
                    result.push(TooltipEngine.TooltipConstants.LBL_SYNTHESIS, "：<BR>");
                    for (var i = 0; TooltipEngine.as2Less(i, requirements.length); i++) {
                        if (requirements[i] && requirements[i].name) {
                            var itemData = TooltipEngine.lookupItem(ctx, requirements[i].name);
                            var displayText = itemData?.displayname;
                            if (requirements[i].isQuantity) {
                                displayText += " x " + requirements[i].value;
                            }
                            else if (TooltipEngine.isEquipment(ctx, requirements[i].name)) {
                                displayText += " +" + requirements[i].value;
                            }
                            else {
                                displayText += "：" + requirements[i].value;
                            }
                            result.push(displayText, "<BR>");
                        }
                    }
                }
            }
            return result;
        }
        TooltipTextBuilder.buildSynthesisMaterials = buildSynthesisMaterials;
        function buildObtainMethods(ctx, itemName) {
            return TooltipEngine.ObtainMethodsBuilder.build(ctx, itemName);
        }
        TooltipTextBuilder.buildObtainMethods = buildObtainMethods;
        function buildUpgradePath(ctx, item, baseItem) {
            return TooltipEngine.UpgradePathBuilder.build(ctx, item, baseItem);
        }
        TooltipTextBuilder.buildUpgradePath = buildUpgradePath;
        function buildUpgradePathWithRows(ctx, item, baseItem) {
            return TooltipEngine.UpgradePathBuilder.buildWithRows(ctx, item, baseItem);
        }
        TooltipTextBuilder.buildUpgradePathWithRows = buildUpgradePathWithRows;
        function buildBladeSkillMultipliers(ctx, item, baseItem) {
            var result = [];
            if (item.use !== TooltipEngine.ItemUseTypes.MELEE)
                return result;
            var baseSkillMultipliers = (item.data && item.data.skillmultipliers) ? item.data.skillmultipliers : null;
            var finalSkillMultipliers = null;
            var hasEquipData = false;
            if (baseItem && TooltipEngine.as2NotEqual(baseItem.getData, undefined)) {
                var calculatedData = baseItem.getData();
                if (calculatedData && calculatedData.data && calculatedData.data.skillmultipliers) {
                    finalSkillMultipliers = calculatedData.data.skillmultipliers;
                    hasEquipData = true;
                }
            }
            if (!finalSkillMultipliers) {
                finalSkillMultipliers = baseSkillMultipliers;
            }
            if (!finalSkillMultipliers && !baseSkillMultipliers)
                return result;
            var skillNames = {};
            if (baseSkillMultipliers) {
                for (var key of TooltipEngine.as2Keys(baseSkillMultipliers)) {
                    if (TooltipEngine.isInternalKey(key))
                        continue;
                    skillNames[key] = true;
                }
            }
            if (finalSkillMultipliers) {
                for (var key of TooltipEngine.as2Keys(finalSkillMultipliers)) {
                    if (TooltipEngine.isInternalKey(key))
                        continue;
                    skillNames[key] = true;
                }
            }
            for (var skillName of TooltipEngine.as2Keys(skillNames)) {
                var baseMultiplier = (baseSkillMultipliers && baseSkillMultipliers[skillName]) ? baseSkillMultipliers[skillName] : null;
                var finalMultiplier = (finalSkillMultipliers && finalSkillMultipliers[skillName]) ? finalSkillMultipliers[skillName] : null;
                var baseNum = TooltipEngine.as2Number(baseMultiplier);
                if (TooltipEngine.as2IsNaN(baseNum) || TooltipEngine.as2LessEqual(baseNum, 1))
                    baseNum = 1;
                var finalNum = TooltipEngine.as2Number(finalMultiplier);
                if (TooltipEngine.as2IsNaN(finalNum) || TooltipEngine.as2LessEqual(finalNum, 1))
                    finalNum = 1;
                if (TooltipEngine.as2Equal(baseNum, 1) && TooltipEngine.as2Equal(finalNum, 1))
                    continue;
                if (!hasEquipData || TooltipEngine.as2Equal(finalNum, baseNum)) {
                    if (TooltipEngine.as2Greater(baseNum, 1)) {
                        result.push(TooltipEngine.TooltipFormatter.color(TooltipEngine.TooltipConstants.LBL_SKILL_BONUS, TooltipEngine.TooltipConstants.COL_HL), TooltipEngine.TooltipConstants.TIP_USE, skillName, TooltipEngine.TooltipConstants.TIP_ENJOY, String((baseNum - 1) * 100), TooltipEngine.TooltipConstants.SUF_PERCENT, TooltipEngine.TooltipConstants.TIP_SHARPNESS_BONUS, TooltipEngine.TooltipFormatter.br());
                    }
                }
                else {
                    var finalPercent = (finalNum - 1) * 100;
                    var basePercent = (baseNum - 1) * 100;
                    var enhance = finalNum - baseNum;
                    var enhancePercent = enhance * 100;
                    result.push(TooltipEngine.TooltipFormatter.color(TooltipEngine.TooltipConstants.LBL_SKILL_BONUS, TooltipEngine.TooltipConstants.COL_HL), TooltipEngine.TooltipConstants.TIP_USE, skillName, TooltipEngine.TooltipConstants.TIP_ENJOY, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>", String(finalPercent), TooltipEngine.TooltipConstants.SUF_PERCENT, "</FONT>", TooltipEngine.TooltipConstants.TIP_SHARPNESS_BONUS);
                    var sign;
                    if (TooltipEngine.as2Less(enhance, 0)) {
                        enhancePercent = -enhancePercent;
                        sign = " - ";
                    }
                    else {
                        sign = " + ";
                    }
                    result.push(" (", String(basePercent), TooltipEngine.TooltipConstants.SUF_PERCENT, sign, String(enhancePercent), TooltipEngine.TooltipConstants.SUF_PERCENT, ")<BR>");
                }
            }
            return result;
        }
        TooltipTextBuilder.buildBladeSkillMultipliers = buildBladeSkillMultipliers;
        function buildSubweaponInfo(ctx, subweapon) {
            var result = [];
            var sub = ctx.projection.subweapon;
            if (!sub)
                return result;
            if (sub.description) {
                result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_SUBWEAPON + "</font>", TooltipEngine.TooltipFormatter.normalizeDescription(sub.description), "<BR>");
            }
            else {
                result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_SUBWEAPON + "</font>", sub.name, "<BR>");
            }
            result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_SUBWEAPON_INFO + "</font>");
            result.push("装填", sub.capacity, "发，弹药", sub.reserveName);
            result.push("，冷却", sub.cd / 1000, TooltipEngine.TooltipConstants.SUF_SECOND);
            result.push("，威力", sub.power, "，子弹", sub.bullet);
            if (sub.damageType)
                result.push("，伤害类型", sub.damageType);
            if (sub.magicType)
                result.push("，属性", sub.magicType);
            if (sub.hp && TooltipEngine.as2NotEqual(sub.hp, 0))
                result.push("，", TooltipEngine.TooltipConstants.LBL_COST, sub.hp, TooltipEngine.TooltipConstants.SUF_HP);
            if (sub.mp && TooltipEngine.as2NotEqual(sub.mp, 0))
                result.push("，", TooltipEngine.TooltipConstants.LBL_COST, sub.mp, TooltipEngine.TooltipConstants.SUF_MP);
            if (TooltipEngine.as2Equal(sub.consumeMode, "onFire")) {
                result.push("，逐发消耗", sub.fireCost, "份");
            }
            else {
                result.push("，每组消耗", sub.clipCostPerLoad, "份");
                if (TooltipEngine.as2Equal(sub.consumeTiming, "linkedFirstFire"))
                    result.push("，主武器换弹联动补装");
                if (TooltipEngine.as2Equal(sub.consumeTiming, "onReloadCommit"))
                    result.push("，装填时扣除备弹");
            }
            result.push("。<BR>");
            return result;
        }
        TooltipTextBuilder.buildSubweaponInfo = buildSubweaponInfo;
        function buildSkillInfo(ctx, skill) {
            var result = [];
            if (!skill)
                return result;
            if (skill.description) {
                result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_ACTIVE_SKILL + "</font>", TooltipEngine.TooltipFormatter.normalizeDescription(skill.description), "<BR><font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_SKILL_INFO + "</font>");
                if (skill.information) {
                    result.push(skill.information);
                }
                else {
                    var cooldown = skill.cd / 1000;
                    result.push(TooltipEngine.TooltipConstants.LBL_COOLDOWN, cooldown, TooltipEngine.TooltipConstants.SUF_SECOND);
                    if (skill.hp && TooltipEngine.as2NotEqual(skill.hp, 0))
                        result.push("，", TooltipEngine.TooltipConstants.LBL_COST, skill.hp, TooltipEngine.TooltipConstants.SUF_HP);
                    if (skill.mp && TooltipEngine.as2NotEqual(skill.mp, 0))
                        result.push("，", TooltipEngine.TooltipConstants.LBL_COST, skill.mp, TooltipEngine.TooltipConstants.SUF_MP);
                    if (skill.sp && TooltipEngine.as2NotEqual(skill.sp, 0))
                        result.push("，", TooltipEngine.TooltipConstants.LBL_COST, skill.sp, TooltipEngine.TooltipConstants.SUF_SP);
                    result.push("。");
                }
                result.push("<BR>");
            }
            else if (TooltipEngine.as2Equal(typeof skill, "object") && !(Array.isArray(skill))
                && !(skill instanceof String)) {
                if (TooltipEngine.as2NotEqual(skill.skillname, undefined) && TooltipEngine.as2Greater(String(skill.skillname).length, 0)) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_ACTIVE_SKILL + "</font>", TooltipEngine.TooltipFormatter.normalizeDescription(String(skill.skillname)));
                    if (skill.information) {
                        result.push("<BR><font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_SKILL_INFO + "</font>", skill.information);
                    }
                    else {
                        var infoText = "";
                        var skillCooldown = TooltipEngine.as2Number(skill.cd) / 1000;
                        if (!TooltipEngine.as2IsNaN(skillCooldown) && TooltipEngine.as2Greater(skillCooldown, 0)) {
                            infoText += TooltipEngine.TooltipConstants.LBL_COOLDOWN + skillCooldown + TooltipEngine.TooltipConstants.SUF_SECOND;
                        }
                        if (skill.hp && TooltipEngine.as2NotEqual(TooltipEngine.as2Number(skill.hp), 0)) {
                            infoText += "，" + TooltipEngine.TooltipConstants.LBL_COST + skill.hp + TooltipEngine.TooltipConstants.SUF_HP;
                        }
                        if (skill.mp && TooltipEngine.as2NotEqual(TooltipEngine.as2Number(skill.mp), 0)) {
                            infoText += "，" + TooltipEngine.TooltipConstants.LBL_COST + skill.mp + TooltipEngine.TooltipConstants.SUF_MP;
                        }
                        if (skill.sp && TooltipEngine.as2NotEqual(TooltipEngine.as2Number(skill.sp), 0)) {
                            infoText += "，" + TooltipEngine.TooltipConstants.LBL_COST + skill.sp + TooltipEngine.TooltipConstants.SUF_SP;
                        }
                        if (TooltipEngine.as2Greater(infoText.length, 0)) {
                            result.push("<BR><font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_SKILL_INFO + "</font>", infoText, "。");
                        }
                    }
                    result.push("<BR>");
                }
            }
            else {
                result.push(TooltipEngine.TooltipFormatter.normalizeDescription(String(skill)), "<BR>");
            }
            return result;
        }
        TooltipTextBuilder.buildSkillInfo = buildSkillInfo;
        function buildLifecycleInfo(ctx, lc) {
            var result = [];
            if (lc && lc.description)
                result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_AFFIX_INFO + "</font>", TooltipEngine.TooltipFormatter.normalizeDescription(lc.description), "<BR>");
            return result;
        }
        TooltipTextBuilder.buildLifecycleInfo = buildLifecycleInfo;
        function buildIntroHeader(ctx, baseItem, item, externalValue, nativeOpt) {
            var value = baseItem && baseItem.value ? baseItem.value : (externalValue ? externalValue : 1);
            var upgradeLevel = value.level ? value.level : 1;
            var displayName = item.displayname;
            if (baseItem && TooltipEngine.as2NotEqual(baseItem.getData, undefined)) {
                var calculatedData = baseItem.getData();
                if (calculatedData && calculatedData.displayname !== undefined) {
                    displayName = calculatedData.displayname;
                }
            }
            var result = [];
            result.push("<B>", (value.tier ? ("[" + value.tier + "]") : ""), displayName, "</B><BR>");
            var omitTypeLines = (TooltipEngine.as2NotEqual(nativeOpt, null) && nativeOpt.omitTypeLines === true);
            if (!omitTypeLines) {
                result.push(item.type, "    ", item.use, "<BR>");
                if (TooltipEngine.ItemUseTypes.isGun(item.use) && item.data && item.weapontype) {
                    result.push(TooltipEngine.TooltipConstants.LBL_WEAPON_TYPE, "：", item.weapontype, "<BR>");
                }
            }
            result.push("$", item.price, "<BR>");
            if (TooltipEngine.as2Greater(upgradeLevel, 1) && (TooltipEngine.as2Equal(item.type, TooltipEngine.ItemUseTypes.TYPE_WEAPON) || TooltipEngine.as2Equal(item.type, TooltipEngine.ItemUseTypes.TYPE_ARMOR))) {
                var levelMultiplier = ctx.projection.levelMultiplier;
                if (levelMultiplier && !TooltipEngine.as2IsNaN(levelMultiplier)) {
                    var enhancement = Math.round((levelMultiplier - 1) * 100);
                    result.push("<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_UPGRADE_LEVEL + "：", upgradeLevel, " (+", enhancement, "%)</FONT><BR>");
                }
                else {
                    result.push("<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_UPGRADE_LEVEL + "：", upgradeLevel, "</FONT><BR>");
                }
            }
            else {
                var quantity = 0;
                if (TooltipEngine.as2Equal(typeof value, "number")) {
                    quantity = TooltipEngine.as2Number(value);
                }
                else if (value) {
                    var candidates = [value.count, value.amount, value.num, value.stack, value.quantity];
                    for (var i = 0; TooltipEngine.as2Less(i, candidates.length); i++) {
                        var candidate = TooltipEngine.as2Number(candidates[i]);
                        if (!TooltipEngine.as2IsNaN(candidate) && TooltipEngine.as2Greater(candidate, 0)) {
                            quantity = candidate;
                            break;
                        }
                    }
                }
                if (TooltipEngine.as2Greater(quantity, 1))
                    result.push(TooltipEngine.TooltipConstants.LBL_QUANTITY, "：", quantity, "<BR>");
            }
            return result;
        }
        TooltipTextBuilder.buildIntroHeader = buildIntroHeader;
        function buildStats(ctx, baseItem, item, externalValue, nativeOpt) {
            if (!item.data)
                return [];
            if (item.use === TooltipEngine.ItemUseTypes.POTION) {
                return TooltipEngine.DrugTooltipComposer.compose(ctx, item, (TooltipEngine.as2NotEqual(nativeOpt, null) && nativeOpt.omitBuff === true) ? nativeOpt.buff : null);
            }
            else {
                return buildEquipmentStats(ctx, baseItem, item, externalValue, nativeOpt);
            }
        }
        TooltipTextBuilder.buildStats = buildStats;
        function buildDrugStats(ctx, item) {
            return TooltipEngine.DrugTooltipComposer.compose(ctx, item);
        }
        TooltipTextBuilder.buildDrugStats = buildDrugStats;
        function buildEquipmentStats(ctx, baseItem, item, externalValue, nativeOpt) {
            var value = baseItem && baseItem.value ? baseItem.value : (externalValue ? externalValue : 1);
            var upgradeLevel = value.level ? value.level : 1;
            var data = ctx.projection.baselineData;
            var equipData = TooltipEngine.as2Greater(upgradeLevel, 1) || value.mods ? baseItem.getData().data : null;
            return TooltipEngine.EquipmentStatsComposer.compose(ctx, baseItem, item, data, equipData, nativeOpt);
        }
        TooltipTextBuilder.buildEquipmentStats = buildEquipmentStats;
        function buildModStat(ctx, itemName) {
            return TooltipEngine.ModStatBuilder.build(ctx, itemName);
        }
        TooltipTextBuilder.buildModStat = buildModStat;
        function buildModStatWithRows(ctx, itemName) {
            return TooltipEngine.ModStatBuilder.buildWithRows(ctx, itemName);
        }
        TooltipTextBuilder.buildModStatWithRows = buildModStatWithRows;
        function buildEquipmentTagInfo(ctx, item) {
            var result = [];
            if (item.inherentTags) {
                var inherentArr = item.inherentTags.split(",");
                var inherentTags = [];
                for (var i = 0; TooltipEngine.as2Less(i, inherentArr.length); i++) {
                    var tag = TooltipEngine.trim(inherentArr[i]);
                    if (TooltipEngine.as2Greater(tag.length, 0)) {
                        inherentTags.push(tag);
                    }
                }
                if (TooltipEngine.as2Greater(inherentTags.length, 0)) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_ENHANCE + "'>" + TooltipEngine.TooltipConstants.LBL_INHERENT_TAGS + "：</font>", inherentTags.join(", "), "<BR>");
                }
            }
            if (item.blockedTags) {
                var blockedArr = item.blockedTags.split(",");
                var blockedTags = [];
                for (var j = 0; TooltipEngine.as2Less(j, blockedArr.length); j++) {
                    var blocked = TooltipEngine.trim(blockedArr[j]);
                    if (TooltipEngine.as2Greater(blocked.length, 0)) {
                        blockedTags.push(blocked);
                    }
                }
                if (TooltipEngine.as2Greater(blockedTags.length, 0)) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_ROUT + "'>" + TooltipEngine.TooltipConstants.LBL_BLOCKED_TAGS + "：</font>", blockedTags.join(", "), "<BR>");
                }
            }
            return result;
        }
        TooltipTextBuilder.buildEquipmentTagInfo = buildEquipmentTagInfo;
        function quickBuildCriticalHit(ctx, criticalhit) {
            if (!TooltipEngine.as2IsNaN(TooltipEngine.as2Number(criticalhit)))
                return "<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_CRIT + "'>" + TooltipEngine.TooltipConstants.LBL_CRIT + "：</FONT><FONT COLOR='" + TooltipEngine.TooltipConstants.COL_CRIT + "'>" + criticalhit + TooltipEngine.TooltipConstants.SUF_PERCENT + TooltipEngine.TooltipConstants.TIP_CRIT_CHANCE + "</FONT><BR>";
            else if (criticalhit === TooltipEngine.TooltipConstants.TIP_CRIT_FULL_HP)
                return "<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_CRIT + "'>" + TooltipEngine.TooltipConstants.LBL_CRIT + "：" + TooltipEngine.TooltipConstants.TIP_CRIT_FULL_HP_DESC + "</FONT><BR>";
            return "";
        }
        TooltipTextBuilder.quickBuildCriticalHit = quickBuildCriticalHit;
        function quickBuildMagicDefence(ctx, magicdefence, operationType) {
            var mdList = [];
            for (var key of TooltipEngine.as2Keys(magicdefence)) {
                if (TooltipEngine.isInternalKey(key))
                    continue;
                var mdName = (key === TooltipEngine.TooltipConstants.TXT_BASE ? TooltipEngine.TooltipConstants.TXT_ENERGY : key);
                var value = magicdefence[key];
                if (value)
                    mdList.push(mdName + ": " + value);
            }
            if (TooltipEngine.as2Greater(mdList.length, 0)) {
                var prefix = buildOperationPrefix(ctx, operationType);
                return prefix + TooltipEngine.TooltipConstants.SUF_RESISTANCE + " -> " + mdList.join(", ") + "<BR>";
            }
            return "";
        }
        TooltipTextBuilder.quickBuildMagicDefence = quickBuildMagicDefence;
        function quickBuildSkillMultipliers(ctx, skillmultipliers, operationType) {
            if (!skillmultipliers)
                return "";
            var result = "";
            for (var skillName of TooltipEngine.as2Keys(skillmultipliers)) {
                if (TooltipEngine.isInternalKey(skillName))
                    continue;
                var multiplier = TooltipEngine.as2Number(skillmultipliers[skillName]);
                if (!TooltipEngine.as2IsNaN(multiplier) && TooltipEngine.as2Greater(multiplier, 1)) {
                    var prefix = buildOperationPrefix(ctx, operationType);
                    result += prefix + TooltipEngine.TooltipFormatter.color(TooltipEngine.TooltipConstants.LBL_SKILL_BONUS, TooltipEngine.TooltipConstants.COL_HL);
                    result += TooltipEngine.TooltipConstants.TIP_USE + skillName + TooltipEngine.TooltipConstants.TIP_ENJOY + String((multiplier - 1) * 100) + TooltipEngine.TooltipConstants.SUF_PERCENT + TooltipEngine.TooltipConstants.TIP_SHARPNESS_BONUS;
                    result += TooltipEngine.TooltipFormatter.br();
                }
            }
            return result;
        }
        TooltipTextBuilder.quickBuildSkillMultipliers = quickBuildSkillMultipliers;
        function quickBuildDamageType(ctx, buf, data) {
            if (!data.damagetype)
                return;
            if (TooltipEngine.as2Equal(data.damagetype, TooltipEngine.TooltipConstants.TXT_MAGIC) && data.magictype) {
                TooltipEngine.TooltipFormatter.colorLine(buf, TooltipEngine.TooltipConstants.COL_DMG, TooltipEngine.TooltipConstants.LBL_DAMAGE_ATTR + "：" + data.magictype);
            }
            else if (TooltipEngine.as2Equal(data.damagetype, TooltipEngine.TooltipConstants.TXT_BREAK) && data.magictype) {
                if (TooltipEngine.isMagicDamage(ctx, data.magictype))
                    TooltipEngine.TooltipFormatter.colorLine(buf, TooltipEngine.TooltipConstants.COL_BREAK_LIGHT, TooltipEngine.TooltipConstants.LBL_EXTRA_DAMAGE + "：" + data.magictype);
                else
                    TooltipEngine.TooltipFormatter.colorLine(buf, TooltipEngine.TooltipConstants.COL_BREAK_MAIN, TooltipEngine.TooltipConstants.LBL_BREAK_TYPE + "：" + data.magictype);
            }
            else {
                TooltipEngine.TooltipFormatter.colorLine(buf, TooltipEngine.TooltipConstants.COL_DMG, TooltipEngine.TooltipConstants.LBL_DAMAGE_TYPE + "：" + (TooltipEngine.as2Equal(data.damagetype, TooltipEngine.TooltipConstants.TXT_MAGIC) ? TooltipEngine.TooltipConstants.TXT_ENERGY : data.damagetype));
            }
        }
        TooltipTextBuilder.quickBuildDamageType = quickBuildDamageType;
        function getSortedAttrList(ctx, data) {
            var list = [];
            var priorities = TooltipEngine.TooltipConstants.PROPERTY_PRIORITIES;
            for (var key of TooltipEngine.as2Keys(data)) {
                if (!TooltipEngine.as2IsNaN(priorities[key]))
                    list.push(key);
            }
            var sortFunc = function (keyA, keyB) {
                return priorities[keyA] - priorities[keyB];
            };
            return list.sort(sortFunc);
        }
        TooltipTextBuilder.getSortedAttrList = getSortedAttrList;
    })(TooltipTextBuilder = TooltipEngine.TooltipTextBuilder || (TooltipEngine.TooltipTextBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/ToughnessBuffTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let ToughnessBuffTooltipBuilder;
    (function (ToughnessBuffTooltipBuilder) {
        function build(ctx, effectData) {
            var result = [];
            var value = TooltipEngine.as2Number(effectData.value);
            if (TooltipEngine.as2IsNaN(value) || TooltipEngine.as2LessEqual(value, 0))
                return result;
            result.push(TooltipEngine.DrugTooltipUtil.color(ctx, TooltipEngine.TooltipConstants.LBL_DRUG_BUFF + "：", TooltipEngine.TooltipConstants.COL_HL));
            result.push("装备韧性 +" + value);
            var duration = TooltipEngine.as2Number(effectData.duration);
            if (!TooltipEngine.as2IsNaN(duration) && TooltipEngine.as2Greater(duration, 0)) {
                result.push("（" + TooltipEngine.DrugTooltipUtil.framesToSeconds(ctx, duration)
                    + TooltipEngine.TooltipConstants.TIP_DRUG_SECOND + "）");
            }
            result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            return result;
        }
        ToughnessBuffTooltipBuilder.build = build;
    })(ToughnessBuffTooltipBuilder = TooltipEngine.ToughnessBuffTooltipBuilder || (TooltipEngine.ToughnessBuffTooltipBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/drug/builders/ToughnessRestoreTooltipBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let ToughnessRestoreTooltipBuilder;
    (function (ToughnessRestoreTooltipBuilder) {
        function build(ctx, effectData) {
            var result = [];
            result.push(TooltipEngine.DrugTooltipUtil.color(ctx, "韧性：", TooltipEngine.TooltipConstants.COL_HL));
            result.push("立即恢复至满");
            result.push(TooltipEngine.DrugTooltipUtil.br(ctx));
            return result;
        }
        ToughnessRestoreTooltipBuilder.build = build;
    })(ToughnessRestoreTooltipBuilder = TooltipEngine.ToughnessRestoreTooltipBuilder || (TooltipEngine.ToughnessRestoreTooltipBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/UpgradePathBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let UpgradePathBuilder;
    (function (UpgradePathBuilder) {
        function isRecipeUnavailableForItem(ctx, item) {
            if (!ctx.catalog.recipesUnavailable || !item)
                return false;
            var targets = ctx.catalog.recipeTargets;
            if (!targets)
                return true;
            return Boolean((item.name && targets[item.name]) || (item.synthesis && targets[item.synthesis]));
        }
        function build(ctx, item, baseItem) {
            var result = [];
            var craftUnavailable = isRecipeUnavailableForItem(ctx, item);
            var fromRecipe = craftUnavailable ? null : (TooltipEngine.lookupRecipe(ctx, item.synthesis) || TooltipEngine.lookupRecipe(ctx, item.name));
            var hasFrom = (!craftUnavailable && TooltipEngine.as2NotEqual(fromRecipe, null) && TooltipEngine.as2NotEqual(fromRecipe.materials, null));
            var toProducts = craftUnavailable ? null : TooltipEngine.lookupRecipesUsing(ctx, item.name);
            var hasTo = (!craftUnavailable && toProducts && TooltipEngine.as2Greater(toProducts.length, 0));
            var supportedTiers = [];
            var rawTierOpts = ctx.projection.tierOptions;
            if (rawTierOpts) {
                for (var i = 0; TooltipEngine.as2Less(i, rawTierOpts.length); i++) {
                    if (rawTierOpts[i].available)
                        supportedTiers.push(rawTierOpts[i]);
                }
            }
            var hasTier = (TooltipEngine.as2Greater(supportedTiers.length, 0));
            if (!craftUnavailable && !hasFrom && !hasTo && !hasTier)
                return result;
            result.push(TooltipEngine.TooltipFormatter.br());
            result.push(TooltipEngine.TooltipFormatter.color(TooltipEngine.TooltipConstants.LBL_UPGRADE_PATH, TooltipEngine.TooltipConstants.COL_INFO));
            result.push(TooltipEngine.TooltipFormatter.br());
            var rendered = false;
            if (craftUnavailable) {
                result.push("  ", "合成材料暂不可用", TooltipEngine.TooltipFormatter.br());
                rendered = true;
            }
            if (hasFrom) {
                renderFrom(ctx, result, fromRecipe);
                rendered = true;
            }
            if (hasTo) {
                if (rendered)
                    result.push(TooltipEngine.TooltipFormatter.br());
                renderTo(ctx, result, toProducts);
                rendered = true;
            }
            if (hasTier) {
                if (rendered)
                    result.push(TooltipEngine.TooltipFormatter.br());
                renderTier(ctx, result, supportedTiers, baseItem);
            }
            return result;
        }
        UpgradePathBuilder.build = build;
        function buildWithRows(ctx, item, baseItem) {
            var html = build(ctx, item, baseItem).join("");
            if (TooltipEngine.as2Equal(html.length, 0))
                return null;
            var rows = [];
            var craftUnavailable = isRecipeUnavailableForItem(ctx, item);
            if (craftUnavailable) {
                rows.push({ name: "合成材料暂不可用", depth: 0 });
            }
            else {
                var fromRecipe = TooltipEngine.lookupRecipe(ctx, item.synthesis) || TooltipEngine.lookupRecipe(ctx, item.name);
                if (TooltipEngine.as2NotEqual(fromRecipe, null) && TooltipEngine.as2NotEqual(fromRecipe.materials, null)) {
                    pushGroup(ctx, rows, TooltipEngine.TooltipConstants.TIP_UPGRADE_FROM, TooltipEngine.TooltipConstants.COL_CRAFT);
                    var requirements = fromRecipe.materials;
                    for (var i = 0; TooltipEngine.as2Less(i, requirements.length); i++) {
                        var req = requirements[i];
                        if (!req || !req.name)
                            continue;
                        var reqData = TooltipEngine.lookupItem(ctx, req.name);
                        var reqName = (reqData && reqData.displayname) ? reqData.displayname : req.name;
                        if (req.isQuantity)
                            reqName += " x" + req.value;
                        else if (TooltipEngine.isEquipment(ctx, req.name))
                            reqName += " +" + req.value;
                        else
                            reqName += "：" + req.value;
                        rows.push({ name: reqName, icon: iconFor(ctx, req.name), depth: 1 });
                    }
                }
                var toProducts = TooltipEngine.lookupRecipesUsing(ctx, item.name);
                if (toProducts && TooltipEngine.as2Greater(toProducts.length, 0)) {
                    pushGroup(ctx, rows, TooltipEngine.TooltipConstants.TIP_UPGRADE_TO, TooltipEngine.TooltipConstants.COL_CRAFT);
                    var shown = Math.min(toProducts.length, TooltipEngine.TooltipConstants.UPGRADE_MAX_TO_PRODUCTS);
                    for (var p = 0; TooltipEngine.as2Less(p, shown); p++) {
                        var prodName = toProducts[p];
                        var prodData = TooltipEngine.lookupItem(ctx, prodName);
                        rows.push({ name: (prodData && prodData.displayname) ? prodData.displayname : prodName,
                            icon: iconFor(ctx, prodName), depth: 1 });
                    }
                    if (TooltipEngine.as2Greater(toProducts.length, shown)) {
                        rows.push({ name: "... " + TooltipEngine.TooltipConstants.TIP_ETC + "共 " + toProducts.length + " 项", depth: 1 });
                    }
                }
            }
            var supportedTiers = [];
            var rawTierOpts = ctx.projection.tierOptions;
            if (rawTierOpts) {
                for (var t = 0; TooltipEngine.as2Less(t, rawTierOpts.length); t++) {
                    if (rawTierOpts[t].available)
                        supportedTiers.push(rawTierOpts[t]);
                }
            }
            if (TooltipEngine.as2Greater(supportedTiers.length, 0)) {
                pushGroup(ctx, rows, TooltipEngine.TooltipConstants.TIP_TIER_OPTIONS, TooltipEngine.TooltipConstants.COL_ENHANCE);
                var currentTier = (baseItem && baseItem.value) ? baseItem.value.tier : null;
                for (var j = 0; TooltipEngine.as2Less(j, supportedTiers.length); j++) {
                    var opt = supportedTiers[j];
                    var row = { name: opt.name, depth: 1 };
                    if (currentTier && opt.name === currentTier)
                        row.name += TooltipEngine.TooltipConstants.TIP_TIER_CURRENT;
                    if (opt.material) {
                        row.icon = iconFor(ctx, opt.material);
                        row.effect = " " + TooltipEngine.TooltipFormatter.color("[" + opt.material + "]", TooltipEngine.TooltipConstants.COL_INFO);
                    }
                    rows.push(row);
                }
            }
            return { kind: "upgrades", title: TooltipEngine.TooltipConstants.LBL_UPGRADE_PATH, rows: rows, html: html };
        }
        UpgradePathBuilder.buildWithRows = buildWithRows;
        function pushGroup(ctx, rows, name, color) {
            rows.push({ name: name, depth: 0, effect: TooltipEngine.TooltipFormatter.color(name, color) });
        }
        function iconFor(ctx, name) {
            if (!name)
                return null;
            var data = TooltipEngine.lookupItem(ctx, name);
            return (data && data.icon) ? String(data.icon) : name;
        }
        function renderFrom(ctx, result, fromRecipe) {
            var requirements = fromRecipe.materials;
            if (!requirements || TooltipEngine.as2Equal(requirements.length, 0))
                return;
            result.push("  ");
            result.push(TooltipEngine.TooltipFormatter.color(TooltipEngine.TooltipConstants.TIP_UPGRADE_FROM, TooltipEngine.TooltipConstants.COL_CRAFT));
            result.push(TooltipEngine.TooltipFormatter.br());
            for (var i = 0; TooltipEngine.as2Less(i, requirements.length); i++) {
                var req = requirements[i];
                if (!req || !req.name)
                    continue;
                var itemData = TooltipEngine.lookupItem(ctx, req.name);
                var displayName = (itemData && itemData.displayname) ? itemData.displayname : req.name;
                result.push("  • ", displayName);
                if (req.isQuantity) {
                    result.push(" x", req.value);
                }
                else if (TooltipEngine.isEquipment(ctx, req.name)) {
                    result.push(" +", req.value);
                }
                else {
                    result.push("：", req.value);
                }
                result.push(TooltipEngine.TooltipFormatter.br());
            }
        }
        function renderTo(ctx, result, toProducts) {
            result.push("  ");
            result.push(TooltipEngine.TooltipFormatter.color(TooltipEngine.TooltipConstants.TIP_UPGRADE_TO, TooltipEngine.TooltipConstants.COL_CRAFT));
            result.push(TooltipEngine.TooltipFormatter.br());
            var maxN = TooltipEngine.TooltipConstants.UPGRADE_MAX_TO_PRODUCTS;
            var total = toProducts.length;
            var shown = Math.min(total, maxN);
            for (var i = 0; TooltipEngine.as2Less(i, shown); i++) {
                var prodName = toProducts[i];
                var itemData = TooltipEngine.lookupItem(ctx, prodName);
                var displayName = (itemData && itemData.displayname) ? itemData.displayname : prodName;
                result.push("  • ", displayName, TooltipEngine.TooltipFormatter.br());
            }
            if (TooltipEngine.as2Greater(total, maxN)) {
                result.push("  • ... ", TooltipEngine.TooltipConstants.TIP_ETC, "共 ", total, " 项", TooltipEngine.TooltipFormatter.br());
            }
        }
        function renderTier(ctx, result, supportedTiers, baseItem) {
            result.push("  ");
            result.push(TooltipEngine.TooltipFormatter.color(TooltipEngine.TooltipConstants.TIP_TIER_OPTIONS, TooltipEngine.TooltipConstants.COL_ENHANCE));
            result.push(TooltipEngine.TooltipFormatter.br());
            var currentTier = (baseItem && baseItem.value) ? baseItem.value.tier : null;
            for (var i = 0; TooltipEngine.as2Less(i, supportedTiers.length); i++) {
                var opt = supportedTiers[i];
                result.push("  • ", opt.name);
                if (currentTier && opt.name === currentTier) {
                    result.push(TooltipEngine.TooltipConstants.TIP_TIER_CURRENT);
                }
                if (opt.material) {
                    result.push(" ");
                    result.push(TooltipEngine.TooltipFormatter.color("[" + opt.material + "]", TooltipEngine.TooltipConstants.COL_INFO));
                }
                result.push(TooltipEngine.TooltipFormatter.br());
            }
        }
    })(UpgradePathBuilder = TooltipEngine.UpgradePathBuilder || (TooltipEngine.UpgradePathBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/UseSwitchStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let UseSwitchStatsBuilder;
    (function (UseSwitchStatsBuilder) {
        function buildBaseSwitchDetailed(ctx, result, stats) {
            if (!stats || !stats.baseSwitch || !stats.baseSwitch.valueCases)
                return;
            var valueCases = stats.baseSwitch.valueCases;
            if (TooltipEngine.as2Equal(valueCases.length, 0))
                return;
            var path = stats.baseSwitch.path || "data.damagetype";
            var pathLabel = (TooltipEngine.as2Equal(path, "data.damagetype")) ? "基础伤害类型" : path;
            result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>按基础属性分档</font><BR>");
            for (var i = 0; TooltipEngine.as2Less(i, valueCases.length); i++) {
                var valueCase = valueCases[i];
                if (!valueCase)
                    continue;
                var label = (valueCase._isDefault || !valueCase.name)
                    ? "其他情况"
                    : pathLabel + "为" + valueCase.name;
                result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INFO + "'>[" + label + "]</font><BR>");
                buildStatBlock(ctx, result, valueCase, "  ");
            }
        }
        UseSwitchStatsBuilder.buildBaseSwitchDetailed = buildBaseSwitchDetailed;
        function buildDetailed(ctx, result, stats) {
            if (!stats || !stats.useSwitch || !stats.useSwitch.useCases) {
                return;
            }
            var useCases = stats.useSwitch.useCases;
            if (TooltipEngine.as2Equal(useCases.length, 0)) {
                return;
            }
            result.push("<font color='" + TooltipEngine.TooltipConstants.COL_HL + "'>" + TooltipEngine.TooltipConstants.LBL_USE_SWITCH_EFFECT + "</font><BR>");
            for (var ucIdx = 0; TooltipEngine.as2Less(ucIdx, useCases.length); ucIdx++) {
                var useCase = useCases[ucIdx];
                if (useCase._isDefault || !useCase.name) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INFO + "'>" + TooltipEngine.TooltipConstants.TIP_DEFAULT_BRANCH + "：</font><BR>");
                }
                else {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INFO + "'>" + TooltipEngine.TooltipConstants.TIP_FOR + " " + getUseCaseDisplayName(ctx, useCase.name) + "：</font><BR>");
                }
                if (useCase.provideTagDict) {
                    var condTags = [];
                    for (var pTag of TooltipEngine.as2Keys(useCase.provideTagDict)) {
                        if (TooltipEngine.isInternalKey(pTag))
                            continue;
                        condTags.push(pTag);
                    }
                    if (TooltipEngine.as2Greater(condTags.length, 0)) {
                        result.push("  <font color='" + TooltipEngine.TooltipConstants.COL_COND_PROVIDE + "'>" + TooltipEngine.TooltipConstants.LBL_COND_PROVIDE_TAGS + "：</font>", condTags.join(", "), "<BR>");
                    }
                }
                if (useCase.requireTagDict) {
                    var requiredTags = [];
                    for (var rTag of TooltipEngine.as2Keys(useCase.requireTagDict)) {
                        if (TooltipEngine.isInternalKey(rTag))
                            continue;
                        requiredTags.push(rTag);
                    }
                    if (TooltipEngine.as2Greater(requiredTags.length, 0)) {
                        result.push("  <font color='" + TooltipEngine.TooltipConstants.COL_INSTALL_COND + "'>" + TooltipEngine.TooltipConstants.LBL_COND_REQUIRE_TAGS + "：</font>", requiredTags.join(", "), "<BR>");
                    }
                }
                buildStatBlock(ctx, result, useCase, "  ");
            }
        }
        UseSwitchStatsBuilder.buildDetailed = buildDetailed;
        function buildStatBlock(ctx, result, statsObj, indent) {
            if (!statsObj)
                return;
            if (statsObj.percentage) {
                var sortedList = TooltipEngine.TooltipTextBuilder.getSortedAttrList(ctx, statsObj.percentage);
                for (var i = 0; TooltipEngine.as2Less(i, sortedList.length); i++) {
                    var key = sortedList[i];
                    if (TooltipEngine.as2Equal(key, "impact"))
                        continue;
                    result.push(indent);
                    TooltipEngine.TooltipFormatter.statLine(result, "multiply", key, statsObj.percentage[key], null);
                }
                if (TooltipEngine.as2NotEqual(statsObj.percentage.impact, undefined)) {
                    var pctImpact = TooltipEngine.as2Number(statsObj.percentage.impact);
                    if (!TooltipEngine.as2IsNaN(pctImpact) && TooltipEngine.as2NotEqual(pctImpact, 0) && TooltipEngine.as2Greater(pctImpact, -1)) {
                        var changePct = Math.round(-pctImpact / (1 + pctImpact) * 100);
                        var pctSign = TooltipEngine.as2GreaterEqual(changePct, 0) ? " + " : " - ";
                        if (TooltipEngine.as2Less(changePct, 0))
                            changePct = -changePct;
                        result.push(indent, TooltipEngine.TooltipConstants.LBL_IMPACT, pctSign, changePct, "%<BR>");
                    }
                }
            }
            if (statsObj.multiplier) {
                var sortedList = TooltipEngine.TooltipTextBuilder.getSortedAttrList(ctx, statsObj.multiplier);
                for (var i = 0; TooltipEngine.as2Less(i, sortedList.length); i++) {
                    var key = sortedList[i];
                    var mValue = statsObj.multiplier[key];
                    var label = TooltipEngine.TooltipConstants.PROPERTY_DICT[key];
                    if (!label)
                        label = key;
                    if (TooltipEngine.as2Equal(key, "impact")) {
                        var rawFactor = 1 + mValue;
                        if (TooltipEngine.as2Less(rawFactor, 0.01))
                            rawFactor = 0.01;
                        var dispFactor = Math.round((1 / rawFactor) * 100) / 100;
                        result.push(indent, "<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_MULTIPLIER + "'>", label, " ×", dispFactor, "</FONT> <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_MULTIPLIER_HINT + "'>" + TooltipEngine.TooltipConstants.TAG_MULTIPLIER_ZONE + "</FONT><BR>");
                        continue;
                    }
                    var factorValue = Math.round((1 + mValue) * 100) / 100;
                    var displayText = "×" + factorValue;
                    result.push(indent, "<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_MULTIPLIER + "'>", label, " ", displayText, "</FONT> <FONT COLOR='" + TooltipEngine.TooltipConstants.COL_MULTIPLIER_HINT + "'>" + TooltipEngine.TooltipConstants.TAG_MULTIPLIER_ZONE + "</FONT><BR>");
                }
            }
            if (statsObj.curve) {
                var sortedList = TooltipEngine.TooltipTextBuilder.getSortedAttrList(ctx, statsObj.curve);
                for (var i = 0; TooltipEngine.as2Less(i, sortedList.length); i++) {
                    var key = sortedList[i];
                    appendCurveLine(ctx, result, indent, key, statsObj.curve[key]);
                }
            }
            if (statsObj.flat) {
                var sortedList = TooltipEngine.TooltipTextBuilder.getSortedAttrList(ctx, statsObj.flat);
                for (var i = 0; TooltipEngine.as2Less(i, sortedList.length); i++) {
                    var key = sortedList[i];
                    if (TooltipEngine.as2Equal(key, "slay"))
                        continue;
                    if (TooltipEngine.as2Equal(key, "impact"))
                        continue;
                    result.push(indent);
                    TooltipEngine.TooltipFormatter.statLine(result, "add", key, statsObj.flat[key], null);
                }
                if (statsObj.flat.slay) {
                    result.push(indent);
                    TooltipEngine.SlayEffectBuilder.buildFlat(ctx, result, statsObj.flat.slay);
                }
                if (TooltipEngine.as2NotEqual(statsObj.flat.impact, undefined)) {
                    var flatImpact = TooltipEngine.as2Number(statsObj.flat.impact);
                    if (!TooltipEngine.as2IsNaN(flatImpact) && TooltipEngine.as2NotEqual(flatImpact, 0)) {
                        var isBuff = (TooltipEngine.as2Less(flatImpact, 0));
                        var flatLabel = isBuff ? "冲击力增强" : "冲击力削弱";
                        var flatColor = isBuff ? TooltipEngine.TooltipConstants.COL_HL : TooltipEngine.TooltipConstants.COL_ROUT;
                        var flatAbs = isBuff ? -flatImpact : flatImpact;
                        var flatRawSign = isBuff ? " -" : " +";
                        result.push(indent, "<FONT COLOR='", flatColor, "'>", flatLabel, "</FONT> (原始", flatRawSign, flatAbs, ")<BR>");
                    }
                }
            }
            if (statsObj.override) {
                var sortedList = TooltipEngine.TooltipTextBuilder.getSortedAttrList(ctx, statsObj.override);
                for (var i = 0; TooltipEngine.as2Less(i, sortedList.length); i++) {
                    var key = sortedList[i];
                    if (TooltipEngine.as2Equal(key, "damagetype") || TooltipEngine.as2Equal(key, "magictype") || TooltipEngine.as2Equal(key, "criticalhit") || TooltipEngine.as2Equal(key, "silence") || TooltipEngine.as2Equal(key, "slay") || TooltipEngine.as2Equal(key, "actiontype") || TooltipEngine.as2Equal(key, "singleshoot") || TooltipEngine.as2Equal(key, "reloadType") || TooltipEngine.as2Equal(key, "impact") || TooltipEngine.as2Equal(key, "bullet") || TooltipEngine.as2Equal(key, "bulletrename") || TooltipEngine.as2Equal(key, "split") || TooltipEngine.as2Equal(key, "hitBehavior"))
                        continue;
                    result.push(indent);
                    TooltipEngine.TooltipFormatter.statLine(result, "override", key, statsObj.override[key], null);
                }
                if (statsObj.override.slay) {
                    result.push(indent);
                    TooltipEngine.SlayEffectBuilder.buildOverride(ctx, result, statsObj.override.slay);
                }
                if (statsObj.override.actiontype) {
                    result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>" + TooltipEngine.TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipEngine.TooltipConstants.LBL_ACTION_TYPE, " → ", statsObj.override.actiontype, "<BR>");
                }
            }
            if (statsObj.merge) {
                var sortedList = TooltipEngine.TooltipTextBuilder.getSortedAttrList(ctx, statsObj.merge);
                for (var i = 0; TooltipEngine.as2Less(i, sortedList.length); i++) {
                    var key = sortedList[i];
                    if (TooltipEngine.as2Equal(key, "magicdefence") || TooltipEngine.as2Equal(key, "skillmultipliers") || TooltipEngine.as2Equal(key, "hitBehavior") || TooltipEngine.as2Equal(key, "switchstrike") || TooltipEngine.as2Equal(key, "overload"))
                        continue;
                    result.push(indent);
                    TooltipEngine.TooltipFormatter.statLine(result, "merge", key, statsObj.merge[key], null);
                }
            }
            if (statsObj.cap) {
                var sortedList = TooltipEngine.TooltipTextBuilder.getSortedAttrList(ctx, statsObj.cap);
                for (var i = 0; TooltipEngine.as2Less(i, sortedList.length); i++) {
                    var key = sortedList[i];
                    var capValue = statsObj.cap[key];
                    var label = TooltipEngine.TooltipConstants.PROPERTY_DICT[key];
                    if (!label)
                        label = key;
                    if (TooltipEngine.as2Greater(capValue, 0)) {
                        result.push(indent, "<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>", label, " " + TooltipEngine.TooltipConstants.TIP_CAP_UPPER + ": +", capValue, "</FONT><BR>");
                    }
                    else if (TooltipEngine.as2Less(capValue, 0)) {
                        result.push(indent, "<FONT COLOR='" + TooltipEngine.TooltipConstants.COL_INFO + "'>", label, " " + TooltipEngine.TooltipConstants.TIP_CAP_LOWER + ": ", capValue, "</FONT><BR>");
                    }
                }
            }
            if (statsObj.override) {
                if (statsObj.override.criticalhit) {
                    result.push(indent, TooltipEngine.TooltipTextBuilder.quickBuildCriticalHit(ctx, statsObj.override.criticalhit));
                }
                if (statsObj.override.magicdefence) {
                    result.push(indent, TooltipEngine.TooltipTextBuilder.quickBuildMagicDefence(ctx, statsObj.override.magicdefence, TooltipEngine.TooltipConstants.TXT_OVERRIDE));
                }
                if (statsObj.override.skillmultipliers) {
                    result.push(indent, TooltipEngine.TooltipTextBuilder.quickBuildSkillMultipliers(ctx, statsObj.override.skillmultipliers, TooltipEngine.TooltipConstants.TXT_OVERRIDE));
                }
                if (statsObj.override.silence) {
                    result.push(indent);
                    TooltipEngine.SilenceEffectBuilder.build(ctx, result, null, null, statsObj.override, null);
                }
                if (TooltipEngine.as2NotEqual(statsObj.override.singleshoot, undefined)) {
                    var singleshootVal = (TooltipEngine.as2Equal(statsObj.override.singleshoot, true) || TooltipEngine.as2Equal(statsObj.override.singleshoot, "true"));
                    var fireModeDesc = singleshootVal ? TooltipEngine.TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipEngine.TooltipConstants.TIP_FIRE_MODE_AUTO;
                    result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>" + TooltipEngine.TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipEngine.TooltipConstants.LBL_FIRE_MODE, " → ", fireModeDesc, "<BR>");
                }
                if (TooltipEngine.as2NotEqual(statsObj.override.reloadType, undefined)) {
                    var reloadTypeVal = statsObj.override.reloadType;
                    var reloadTypeDesc = (TooltipEngine.as2Equal(reloadTypeVal, "tube")) ? TooltipEngine.TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipEngine.TooltipConstants.TIP_RELOAD_TYPE_MAG;
                    result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>" + TooltipEngine.TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipEngine.TooltipConstants.LBL_RELOAD_TYPE, " → ", reloadTypeDesc, "<BR>");
                }
                if (TooltipEngine.as2NotEqual(statsObj.override.impact, undefined)) {
                    var impactRaw = TooltipEngine.as2Number(statsObj.override.impact);
                    if (!TooltipEngine.as2IsNaN(impactRaw) && TooltipEngine.as2Greater(impactRaw, 0)) {
                        result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>" + TooltipEngine.TooltipConstants.TAG_OVERRIDE + " </FONT>");
                        result.push(TooltipEngine.TooltipConstants.LBL_IMPACT, " → ", Math.floor(500 / impactRaw), "<BR>");
                    }
                }
                if (statsObj.override.ammoConversion === "slug") {
                    result.push(indent, TooltipEngine.TooltipConstants.LBL_BULLET_TYPE, " → 独头弹<BR>", indent, "独头基础威力 = 单丸基础威力 × 原弹丸数 ÷ 4<BR>", indent, TooltipEngine.TooltipConstants.LBL_PELLET_COUNT, " → 1<BR>", indent, "基础弹速至少为 80，再计入弹速配件<BR>");
                }
                if (statsObj.override.bullet || statsObj.override.bulletrename) {
                    var bulletDisplay = statsObj.override.bulletrename
                        ? statsObj.override.bulletrename
                        : statsObj.override.bullet;
                    result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>" + TooltipEngine.TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipEngine.TooltipConstants.LBL_BULLET_TYPE, " → ", bulletDisplay, "<BR>");
                }
                if (TooltipEngine.as2NotEqual(statsObj.override.split, undefined)) {
                    result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>" + TooltipEngine.TooltipConstants.TAG_OVERRIDE + " </FONT>");
                    result.push(TooltipEngine.TooltipConstants.LBL_PELLET_COUNT, " → ", statsObj.override.split, "<BR>");
                }
                if (statsObj.override.hitBehavior) {
                    appendHitBehavior(ctx, result, indent, statsObj.override.hitBehavior);
                }
            }
            if (statsObj.merge) {
                TooltipEngine.WeaponAmmoInfoBuilder.appendMerge(ctx, result, statsObj.merge.overload, indent);
                if (statsObj.merge.magicdefence) {
                    result.push(indent, TooltipEngine.TooltipTextBuilder.quickBuildMagicDefence(ctx, statsObj.merge.magicdefence, TooltipEngine.TooltipConstants.TXT_MERGE));
                }
                if (statsObj.merge.skillmultipliers) {
                    result.push(indent, TooltipEngine.TooltipTextBuilder.quickBuildSkillMultipliers(ctx, statsObj.merge.skillmultipliers, TooltipEngine.TooltipConstants.TXT_MERGE));
                }
                if (statsObj.merge.hitBehavior) {
                    appendHitBehavior(ctx, result, indent, statsObj.merge.hitBehavior);
                }
                if (statsObj.merge.switchstrike) {
                    appendSwitchStrike(ctx, result, indent, statsObj.merge.switchstrike);
                }
            }
            if (statsObj.override && statsObj.override.damagetype) {
                result.push(indent);
                TooltipEngine.TooltipTextBuilder.quickBuildDamageType(ctx, result, statsObj.override);
            }
            if (statsObj.softOverride) {
                result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_INFO, "'>【可覆盖设定】</FONT><BR>");
                buildStatBlock(ctx, result, { override: statsObj.softOverride }, indent + "  ");
            }
            if (statsObj.lockOverride) {
                result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_HL, "'>【最终锁定】</FONT><BR>");
                buildStatBlock(ctx, result, { override: statsObj.lockOverride }, indent + "  ");
            }
        }
        UseSwitchStatsBuilder.buildStatBlock = buildStatBlock;
        function appendSwitchStrike(ctx, result, indent, config) {
            if (!config)
                return;
            if (TooltipEngine.as2NotEqual(config.weightCoefficient, undefined)) {
                result.push(indent, "切手技重量系数 → ", config.weightCoefficient, "<BR>");
            }
            if (TooltipEngine.as2NotEqual(config.impactMultiplier, undefined)) {
                result.push(indent, "切手技冲击力 ×", config.impactMultiplier, "<BR>");
            }
        }
        function getUseCaseDisplayName(ctx, rawName) {
            if (!rawName)
                return "";
            var rawParts = rawName.split(",");
            var displayParts = [];
            for (var i = 0; TooltipEngine.as2Less(i, rawParts.length); i++) {
                var token = trimSimple(ctx, String(rawParts[i]));
                if (TooltipEngine.as2Equal(token.indexOf("weapontype:"), 0)) {
                    displayParts.push(TooltipEngine.TooltipConstants.LBL_SCOPE_WEAPON_TYPE + "：" + token.substring(11));
                }
                else if (TooltipEngine.as2Equal(token.indexOf("use:"), 0)) {
                    displayParts.push(TooltipEngine.TooltipConstants.LBL_SCOPE_USE + "：" + token.substring(4));
                }
                else if (TooltipEngine.as2Greater(token.length, 0)) {
                    displayParts.push(token);
                }
            }
            return displayParts.join("/");
        }
        UseSwitchStatsBuilder.getUseCaseDisplayName = getUseCaseDisplayName;
        function buildHitBehaviorSummary(ctx, behavior) {
            if (!behavior)
                return "";
            if (isGrayGooEtchBehavior(ctx, behavior))
                return buildGrayGooEtchSummary(ctx, behavior);
            if (isGrayGooBehavior(ctx, behavior))
                return buildGrayGooSummary(ctx, behavior);
            var parts = [];
            if (TooltipEngine.as2NotEqual(behavior.duration, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_MARK_DURATION + formatFramesAsSeconds(ctx, behavior.duration));
            }
            if (TooltipEngine.as2NotEqual(behavior.damagePerStack, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_DAMAGE_PER_STACK + "+" + formatPercent(ctx, behavior.damagePerStack));
            }
            if (TooltipEngine.as2NotEqual(behavior.maxDuration, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_MAX_DURATION + formatFramesAsSeconds(ctx, behavior.maxDuration));
            }
            if (TooltipEngine.as2NotEqual(behavior.maxStacks, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_MAX_STACKS + behavior.maxStacks + "层");
            }
            if (TooltipEngine.as2NotEqual(behavior.breakExtend, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_BREAK_EXTEND + "+" + formatFramesAsSeconds(ctx, behavior.breakExtend));
            }
            if (TooltipEngine.as2NotEqual(behavior.decayDelay, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_DECAY_DELAY + formatFramesAsSeconds(ctx, behavior.decayDelay));
            }
            if (TooltipEngine.as2NotEqual(behavior.decayInterval, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_DECAY_INTERVAL + formatFramesAsSeconds(ctx, behavior.decayInterval));
            }
            if (TooltipEngine.as2NotEqual(behavior.hitStacks, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_HIT_STACKS + behavior.hitStacks + "格");
            }
            if (TooltipEngine.as2NotEqual(behavior.breakStacks, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_BREAK_STACKS + behavior.breakStacks + "格");
            }
            if (TooltipEngine.as2NotEqual(behavior.milestoneInterval, undefined)) {
                parts.push("每" + behavior.milestoneInterval + "格" + TooltipEngine.TooltipConstants.LBL_MILESTONE_INTERVAL);
            }
            if (TooltipEngine.as2NotEqual(behavior.crumblePerMilestone, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_CRUMBLE_PER_MILESTONE + formatRawPercent(ctx, behavior.crumblePerMilestone));
            }
            if (TooltipEngine.as2NotEqual(behavior.executeAtMax, undefined)) {
                parts.push(TooltipEngine.TooltipConstants.LBL_EXECUTE_AT_MAX + formatRawPercent(ctx, behavior.executeAtMax));
            }
            return parts.join("，");
        }
        UseSwitchStatsBuilder.buildHitBehaviorSummary = buildHitBehaviorSummary;
        function appendHitBehavior(ctx, result, indent, behavior) {
            if (!behavior)
                return;
            if (isGrayGooEtchBehavior(ctx, behavior)) {
                appendGrayGooEtchBehavior(ctx, result, indent, behavior);
                return;
            }
            if (isGrayGooBehavior(ctx, behavior)) {
                appendGrayGooBehavior(ctx, result, indent, behavior);
                return;
            }
            result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_USE_SWITCH, "'>", TooltipEngine.TooltipConstants.LBL_HIT_BEHAVIOR, "</FONT><BR>");
            if (TooltipEngine.as2NotEqual(behavior.duration, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_MARK_DURATION, " ", formatFramesAsSeconds(ctx, behavior.duration), "<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.breakExtend, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_BREAK_EXTEND, " +", formatFramesAsSeconds(ctx, behavior.breakExtend), "<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.maxDuration, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_MAX_DURATION, " ", formatFramesAsSeconds(ctx, behavior.maxDuration), "<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.maxStacks, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_MAX_STACKS, " ", behavior.maxStacks, "层<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.damagePerStack, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_DAMAGE_PER_STACK, " +", formatPercent(ctx, behavior.damagePerStack), "<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.decayDelay, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_DECAY_DELAY, " ", formatFramesAsSeconds(ctx, behavior.decayDelay), "<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.decayInterval, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_DECAY_INTERVAL, " ", formatFramesAsSeconds(ctx, behavior.decayInterval), "<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.hitStacks, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_HIT_STACKS, " ", behavior.hitStacks, "格<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.breakStacks, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_BREAK_STACKS, " ", behavior.breakStacks, "格<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.milestoneInterval, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_MILESTONE_INTERVAL, " 每", behavior.milestoneInterval, "格<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.crumblePerMilestone, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_CRUMBLE_PER_MILESTONE, " ", formatRawPercent(ctx, behavior.crumblePerMilestone), "<BR>");
            }
            if (TooltipEngine.as2NotEqual(behavior.executeAtMax, undefined)) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.LBL_EXECUTE_AT_MAX, " ", formatRawPercent(ctx, behavior.executeAtMax), "<BR>");
            }
            if (TooltipEngine.as2Equal(behavior.sameSourceOnly, true) || TooltipEngine.as2Equal(behavior.sameSourceOnly, "true")) {
                result.push(indent, "  ", TooltipEngine.TooltipConstants.TIP_SAME_SOURCE_ONLY, "<BR>");
            }
        }
        function isGrayGooEtchBehavior(ctx, behavior) {
            return TooltipEngine.as2Equal(String(behavior.type), "grayGooEtch") || TooltipEngine.as2NotEqual(behavior.delayFrames, undefined) || TooltipEngine.as2NotEqual(behavior.detonationCrumble, undefined);
        }
        function buildGrayGooEtchSummary(ctx, behavior) {
            var parts = [];
            if (TooltipEngine.as2NotEqual(behavior.delayFrames, undefined)) {
                parts.push("延迟" + formatFramesAsSeconds(ctx, behavior.delayFrames) + "引爆贴身满伤");
            }
            if (TooltipEngine.as2NotEqual(behavior.detonationCrumble, undefined) && TooltipEngine.as2Greater(TooltipEngine.as2Number(behavior.detonationCrumble), 0)) {
                parts.push("引爆击溃" + formatRawPercent(ctx, behavior.detonationCrumble));
            }
            return parts.join("；");
        }
        function appendGrayGooEtchBehavior(ctx, result, indent, behavior) {
            var summary = buildGrayGooEtchSummary(ctx, behavior);
            if (TooltipEngine.as2Greater(indent.length, 0)) {
                if (TooltipEngine.as2Greater(summary.length, 0))
                    result.push(indent, "  ", summary, "<BR>");
                return;
            }
            result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_USE_SWITCH, "'>", TooltipEngine.TooltipConstants.LBL_GRAY_GOO_BEHAVIOR, "</FONT><BR>");
            if (TooltipEngine.as2Greater(summary.length, 0))
                result.push(indent, "  ", summary, "<BR>");
            result.push(indent, "  蚀刻未引爆期间不叠加不刷新；目标提前阵亡不触发<BR>");
        }
        function isGrayGooBehavior(ctx, behavior) {
            return TooltipEngine.as2Equal(String(behavior.type), "grayGooPrimer") || TooltipEngine.as2NotEqual(behavior.hitStacks, undefined) || TooltipEngine.as2NotEqual(behavior.crumblePerMilestone, undefined) || TooltipEngine.as2NotEqual(behavior.executeAtMax, undefined);
        }
        function buildGrayGooSummary(ctx, behavior) {
            var isBranchProfile = (TooltipEngine.as2NotEqual(behavior.profileId, undefined) && TooltipEngine.as2NotEqual(String(behavior.profileId), "base"));
            var parts = [];
            if (TooltipEngine.as2NotEqual(behavior.hitStacks, undefined) && TooltipEngine.as2Equal(behavior.breakStacks, behavior.hitStacks)) {
                parts.push("命中/破韧+" + behavior.hitStacks + "格");
            }
            else {
                if (TooltipEngine.as2NotEqual(behavior.hitStacks, undefined))
                    parts.push("命中+" + behavior.hitStacks + "格");
                if (TooltipEngine.as2NotEqual(behavior.breakStacks, undefined))
                    parts.push("破韧+" + behavior.breakStacks + "格");
            }
            if (!isBranchProfile && TooltipEngine.as2NotEqual(behavior.maxStacks, undefined))
                parts.push("上限" + behavior.maxStacks + "格");
            if (!isBranchProfile && TooltipEngine.as2NotEqual(behavior.damagePerStack, undefined)) {
                parts.push("每格易伤+" + formatPercent(ctx, behavior.damagePerStack));
            }
            if (TooltipEngine.as2NotEqual(behavior.crumblePerMilestone, undefined)) {
                var milestone = (!isBranchProfile && TooltipEngine.as2NotEqual(behavior.milestoneInterval, undefined))
                    ? "每" + behavior.milestoneInterval + "格" : "节点";
                parts.push(milestone + "击溃" + formatRawPercent(ctx, behavior.crumblePerMilestone));
            }
            if (TooltipEngine.as2NotEqual(behavior.executeAtMax, undefined)) {
                parts.push("满层斩杀" + formatRawPercent(ctx, behavior.executeAtMax));
            }
            if (TooltipEngine.as2NotEqual(behavior.decayDelay, undefined)) {
                parts.push("停火" + formatFramesAsSeconds(ctx, behavior.decayDelay) + "后衰减");
            }
            return parts.join("；");
        }
        function appendGrayGooBehavior(ctx, result, indent, behavior) {
            var isBranchProfile = (TooltipEngine.as2NotEqual(behavior.profileId, undefined) && TooltipEngine.as2NotEqual(String(behavior.profileId), "base")) || TooltipEngine.as2Greater(indent.length, 0);
            var isBase = (TooltipEngine.as2NotEqual(behavior.type, undefined)) && !isBranchProfile;
            if (!isBase) {
                var summary = buildGrayGooSummary(ctx, behavior);
                if (TooltipEngine.as2Greater(summary.length, 0))
                    result.push(indent, "  ", summary, "<BR>");
                return;
            }
            result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_USE_SWITCH, "'>", TooltipEngine.TooltipConstants.LBL_GRAY_GOO_BEHAVIOR, "</FONT><BR>");
            var overview = [];
            if (TooltipEngine.as2NotEqual(behavior.maxStacks, undefined))
                overview.push(behavior.maxStacks + "格");
            if (TooltipEngine.as2NotEqual(behavior.damagePerStack, undefined)) {
                overview.push("每格易伤+" + formatPercent(ctx, behavior.damagePerStack));
            }
            if (TooltipEngine.as2Greater(overview.length, 0))
                result.push(indent, "  ", overview.join("，"), "<BR>");
            var trigger = [];
            if (TooltipEngine.as2NotEqual(behavior.hitStacks, undefined) && TooltipEngine.as2Equal(behavior.breakStacks, behavior.hitStacks)) {
                trigger.push("命中/破韧+" + behavior.hitStacks + "格");
            }
            else {
                if (TooltipEngine.as2NotEqual(behavior.hitStacks, undefined))
                    trigger.push("命中+" + behavior.hitStacks + "格");
                if (TooltipEngine.as2NotEqual(behavior.breakStacks, undefined))
                    trigger.push("破韧+" + behavior.breakStacks + "格");
            }
            if (TooltipEngine.as2NotEqual(behavior.crumblePerMilestone, undefined)) {
                var milestone = TooltipEngine.as2NotEqual(behavior.milestoneInterval, undefined) ? "每" + behavior.milestoneInterval + "格" : "节点";
                trigger.push(milestone + "击溃" + formatRawPercent(ctx, behavior.crumblePerMilestone));
            }
            if (TooltipEngine.as2Greater(trigger.length, 0))
                result.push(indent, "  ", trigger.join("；"), "<BR>");
            var sustain = [];
            if (TooltipEngine.as2NotEqual(behavior.executeAtMax, undefined)) {
                sustain.push("满层斩杀" + formatRawPercent(ctx, behavior.executeAtMax));
            }
            if (TooltipEngine.as2NotEqual(behavior.decayDelay, undefined)) {
                sustain.push("停火" + formatFramesAsSeconds(ctx, behavior.decayDelay) + "后衰减");
            }
            if (TooltipEngine.as2Greater(sustain.length, 0))
                result.push(indent, "  ", sustain.join("；"), "<BR>");
            if (TooltipEngine.as2Equal(behavior.milestoneInterval, 6) && TooltipEngine.as2Equal(behavior.maxStacks, 18)) {
                result.push(indent, "  首跨6/12/18格削上限并伤血（Ⅰ/Ⅱ/Ⅲ阶标记）；退至12/6/0格重装<BR>");
            }
        }
        function formatFramesAsSeconds(ctx, frameValue) {
            var frames = TooltipEngine.as2Number(frameValue);
            if (TooltipEngine.as2IsNaN(frames))
                return String(frameValue);
            var seconds = Math.round(frames / 30 * 10) / 10;
            return seconds + TooltipEngine.TooltipConstants.SUF_SECOND;
        }
        function formatPercent(ctx, value) {
            var numericValue = TooltipEngine.as2Number(value);
            if (TooltipEngine.as2IsNaN(numericValue))
                return String(value);
            return (Math.round(numericValue * 1000) / 10) + TooltipEngine.TooltipConstants.SUF_PERCENT;
        }
        function formatRawPercent(ctx, value) {
            var numericValue = TooltipEngine.as2Number(value);
            if (TooltipEngine.as2IsNaN(numericValue))
                return String(value);
            return (Math.round(numericValue * 10) / 10) + TooltipEngine.TooltipConstants.SUF_PERCENT;
        }
        function trimSimple(ctx, value) {
            while (TooltipEngine.as2Greater(value.length, 0) && TooltipEngine.as2Equal(value.charAt(0), " "))
                value = value.substring(1);
            while (TooltipEngine.as2Greater(value.length, 0) && TooltipEngine.as2Equal(value.charAt(value.length - 1), " "))
                value = value.substring(0, value.length - 1);
            return value;
        }
        function appendCurveLine(ctx, result, indent, key, curveConfig) {
            var label = TooltipEngine.TooltipConstants.PROPERTY_DICT[key];
            if (!label)
                label = key;
            var curveType = "sqrtScale";
            var coefficient = 1;
            var minValue = 1;
            if (TooltipEngine.as2Equal(typeof curveConfig, "object") && TooltipEngine.as2NotEqual(curveConfig, null)) {
                if (TooltipEngine.as2NotEqual(curveConfig.type, undefined)) {
                    curveType = String(curveConfig.type);
                }
                if (TooltipEngine.as2NotEqual(curveConfig.coefficient, undefined)) {
                    coefficient = TooltipEngine.as2Number(curveConfig.coefficient);
                }
                else if (TooltipEngine.as2NotEqual(curveConfig.scale, undefined)) {
                    coefficient = TooltipEngine.as2Number(curveConfig.scale);
                }
                if (TooltipEngine.as2NotEqual(curveConfig.min, undefined)) {
                    minValue = TooltipEngine.as2Number(curveConfig.min);
                }
            }
            else {
                coefficient = TooltipEngine.as2Number(curveConfig);
            }
            if (TooltipEngine.as2IsNaN(coefficient) || TooltipEngine.as2LessEqual(coefficient, 0))
                coefficient = 1;
            if (TooltipEngine.as2IsNaN(minValue))
                minValue = 1;
            result.push(indent, "<FONT COLOR='", TooltipEngine.TooltipConstants.COL_CURVE, "'>", TooltipEngine.TooltipConstants.TAG_CURVE, " ", label, "：");
            if (TooltipEngine.as2Equal(curveType, "sqrtScale") || TooltipEngine.as2Equal(curveType, "sqrt")) {
                result.push(TooltipEngine.TooltipConstants.LBL_CURVE_COMPRESSION_LEVEL, " ", calculateCurveCompressionLevel(ctx, coefficient));
            }
            else if (TooltipEngine.as2Equal(curveType, "saturatingAdd")) {
                var amount = TooltipEngine.as2Number(curveConfig.amount);
                if (!TooltipEngine.as2IsNaN(amount) && TooltipEngine.as2IsFinite(amount) && TooltipEngine.as2GreaterEqual(amount, 0)) {
                    result.push("柔性增加，最多 +", amount);
                    if (TooltipEngine.as2Equal(key, "interval"))
                        result.push("毫秒");
                }
                else {
                    result.push("柔性增加");
                }
            }
            else {
                result.push(curveType);
            }
            result.push("</FONT><BR>");
        }
        function calculateCurveCompressionLevel(ctx, coefficient) {
            var neutralCoefficient = 2;
            var referenceCoefficient = 1.414;
            var referenceLevel = 20;
            var level = Math.round((neutralCoefficient - coefficient) / (neutralCoefficient - referenceCoefficient) * referenceLevel);
            return TooltipEngine.as2Less(level, 0) ? 0 : level;
        }
        function buildBulletSwitchDetailed(ctx, result, stats) {
            if (!stats || !stats.bulletSwitch || !stats.bulletSwitch.bulletCases) {
                return;
            }
            var bulletCases = stats.bulletSwitch.bulletCases;
            if (TooltipEngine.as2Equal(bulletCases.length, 0)) {
                return;
            }
            result.push("<font color='" + TooltipEngine.TooltipConstants.COL_BULLET_SWITCH + "'>" + TooltipEngine.TooltipConstants.LBL_BULLET_SWITCH_EFFECT + "</font><BR>");
            for (var bcIdx = 0; TooltipEngine.as2Less(bcIdx, bulletCases.length); bcIdx++) {
                var bulletCase = bulletCases[bcIdx];
                if (bulletCase._isDefault || !bulletCase.name) {
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INFO + "'>" + TooltipEngine.TooltipConstants.TIP_DEFAULT_BRANCH + "：</font><BR>");
                }
                else {
                    var displayNames = [];
                    var names = bulletCase.name.split(",");
                    for (var ni = 0; TooltipEngine.as2Less(ni, names.length); ni++) {
                        var trimmed = names[ni];
                        while (TooltipEngine.as2Equal(trimmed.charAt(0), " "))
                            trimmed = trimmed.substr(1);
                        while (TooltipEngine.as2Equal(trimmed.charAt(trimmed.length - 1), " "))
                            trimmed = trimmed.substr(0, trimmed.length - 1);
                        var cnName = TooltipEngine.TooltipConstants.BULLET_TYPE_NAMES[trimmed];
                        displayNames.push(cnName ? cnName : trimmed);
                    }
                    result.push("<font color='" + TooltipEngine.TooltipConstants.COL_INFO + "'>" + TooltipEngine.TooltipConstants.TIP_BULLET_FOR + " " + displayNames.join("/") + " " + TooltipEngine.TooltipConstants.TIP_BULLET_SUFFIX + "：</font><BR>");
                }
                buildStatBlock(ctx, result, bulletCase, "  ");
            }
        }
        UseSwitchStatsBuilder.buildBulletSwitchDetailed = buildBulletSwitchDetailed;
    })(UseSwitchStatsBuilder = TooltipEngine.UseSwitchStatsBuilder || (TooltipEngine.UseSwitchStatsBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/WeaponAmmoInfoBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
var TooltipEngine;
(function (TooltipEngine) {
    let WeaponAmmoInfoBuilder;
    (function (WeaponAmmoInfoBuilder) {
        function quota(ctx, value) {
            var n = TooltipEngine.as2Number(value);
            return TooltipEngine.as2Greater(n, 0) && TooltipEngine.as2IsFinite(n) ? Math.min(2, Math.floor(n)) : 0;
        }
        function capacitySuffix(ctx, data) {
            var capacity = Math.floor(TooltipEngine.as2Number(data.capacity));
            if (!(TooltipEngine.as2Greater(capacity, 0)) || !TooltipEngine.as2IsFinite(capacity))
                return "";
            var config = data.overload;
            var chamber = quota(ctx, config?.chamber);
            var ghost = quota(ctx, config?.ghost);
            if (TooltipEngine.as2Greater(ghost, 0))
                ghost = Math.max(ghost, quota(ctx, config?.ghostLimit));
            var result = "";
            if (TooltipEngine.as2Greater(chamber, 0))
                result += colored(ctx, chamber, TooltipEngine.TooltipConstants.COL_AMMO_CHAMBER);
            if (TooltipEngine.as2Greater(ghost, 0))
                result += colored(ctx, ghost, TooltipEngine.TooltipConstants.COL_AMMO_GHOST);
            if (config?.reward)
                result += colored(ctx, capacity, TooltipEngine.TooltipConstants.COL_AMMO_REWARD);
            return result;
        }
        WeaponAmmoInfoBuilder.capacitySuffix = capacitySuffix;
        function colored(ctx, amount, color) {
            return " <FONT COLOR='" + color + "'>+" + amount + "</FONT>";
        }
        function appendMerge(ctx, result, config, indent) {
            var limit = quota(ctx, config?.ghostLimit);
            if (TooltipEngine.as2Equal(limit, 0))
                return;
            result.push(indent, "<font color='", TooltipEngine.TooltipConstants.COL_HL, "'>", TooltipEngine.TooltipConstants.TAG_MERGE, "</font> ", TooltipEngine.TooltipConstants.LBL_GHOST_LIMIT, " → ", limit, "发（需原生支持及冲击连携，不累加）。<BR>");
        }
        WeaponAmmoInfoBuilder.appendMerge = appendMerge;
    })(WeaponAmmoInfoBuilder = TooltipEngine.WeaponAmmoInfoBuilder || (TooltipEngine.WeaponAmmoInfoBuilder = {}));
})(TooltipEngine || (TooltipEngine = {}));
var TooltipEngine;
(function (TooltipEngine) {
    /** Narrow coercions used by migrated content rules, from agentsDoc/as2-anti-hallucination.md.
     * They are not a Flash runtime or an equipment-calculation implementation. */
    function as2Number(value) {
        if (value == null)
            return NaN;
        if (typeof value === 'string' && value.trim().length === 0)
            return NaN;
        if (typeof value === 'object') {
            const primitive = String(value);
            return primitive.trim().length === 0 ? NaN : Number(primitive);
        }
        return Number(value);
    }
    TooltipEngine.as2Number = as2Number;
    function as2IsNaN(value) { return Number.isNaN(as2Number(value)); }
    TooltipEngine.as2IsNaN = as2IsNaN;
    function as2IsFinite(value) { return Number.isFinite(as2Number(value)); }
    TooltipEngine.as2IsFinite = as2IsFinite;
    /** AVM1 array-to-text keeps explicit null and missing entries as words. */
    function as2String(value) {
        if (!Array.isArray(value))
            return String(value);
        const parts = [];
        for (let i = 0; i < value.length; i++)
            parts.push(as2String(value[i]));
        return parts.join(',');
    }
    TooltipEngine.as2String = as2String;
    function as2Less(left, right) {
        return typeof left === 'string' && typeof right === 'string'
            ? left < right : as2Number(left) < as2Number(right);
    }
    TooltipEngine.as2Less = as2Less;
    function as2Greater(left, right) { return as2Less(right, left); }
    TooltipEngine.as2Greater = as2Greater;
    function as2LessEqual(left, right) { return !as2Greater(left, right); }
    TooltipEngine.as2LessEqual = as2LessEqual;
    function as2GreaterEqual(left, right) { return !as2Less(left, right); }
    TooltipEngine.as2GreaterEqual = as2GreaterEqual;
    function as2Equal(left, right) {
        if (left == null || right == null)
            return left == null && right == null;
        if (typeof left === 'number' && typeof right === 'number') {
            // AVM1's observed reflexive NaN equality. Distinct boxed/register NaN provenance
            // is not representable on JSON and remains an explicit fresh-oracle gap.
            return left === right || (Number.isNaN(left) && Number.isNaN(right));
        }
        if (typeof left === typeof right)
            return left === right;
        if (typeof left === 'object' || typeof right === 'object')
            return left == right;
        const a = as2Number(left), b = as2Number(right);
        return !Number.isNaN(a) && !Number.isNaN(b) && a === b;
    }
    TooltipEngine.as2Equal = as2Equal;
    function as2NotEqual(left, right) { return !as2Equal(left, right); }
    TooltipEngine.as2NotEqual = as2NotEqual;
    /** Projection clone + LiteJSON serialize reverses twice, preserving original insertion.
     * Native data objects are JSON-only; prototype properties are excluded at the boundary. */
    function as2Keys(value) {
        return value == null ? [] : Object.keys(value).reverse();
    }
    TooltipEngine.as2Keys = as2Keys;
    function as2FromCharCode(...values) {
        return String.fromCharCode(...values).replace(/\u0000/g, '');
    }
    TooltipEngine.as2FromCharCode = as2FromCharCode;
})(TooltipEngine || (TooltipEngine = {}));
/** Read-only transport contracts. Domain qualification/calculation remains in AS2. */
var TooltipEngine;
(function (TooltipEngine) {
    class InputError extends Error {
        constructor(code) { super(code); this.name = 'TooltipInputError'; this.code = code; }
    }
    TooltipEngine.InputError = InputError;
    function trim(value) {
        return value == null ? '' : String(value).replace(/^[ \t\n\r]+|[ \t\n\r]+$/g, '');
    }
    TooltipEngine.trim = trim;
    function isInternalKey(key) { return key.substr(0, 2) === '__'; }
    TooltipEngine.isInternalKey = isInternalKey;
    function lookupItem(ctx, name) { return ctx.catalog.items[name]; }
    TooltipEngine.lookupItem = lookupItem;
    function isEquipment(ctx, name) {
        if (name === ctx.input.itemName)
            return ctx.projection.isEquipment;
        const item = lookupItem(ctx, name);
        // Only a display label for crafting ingredients, never an equip/transaction decision.
        return !!item && (item.type === '武器' || item.type === '防具');
    }
    TooltipEngine.isEquipment = isEquipment;
    function isMaterial(ctx, name) {
        return name === ctx.input.itemName && ctx.projection.isMaterial;
    }
    TooltipEngine.isMaterial = isMaterial;
    function isInformation(ctx, name) {
        return name === ctx.input.itemName && ctx.projection.isInformation;
    }
    TooltipEngine.isInformation = isInformation;
    function projectedMod(ctx, name) {
        const result = ctx.projection.mods[name];
        if (!result)
            throw new InputError('missing_mod_projection');
        return result;
    }
    TooltipEngine.projectedMod = projectedMod;
    function lookupRecipe(ctx, id) { return ctx.catalog.recipes[id]; }
    TooltipEngine.lookupRecipe = lookupRecipe;
    function lookupRecipesUsing(ctx, name) {
        return ctx.catalog.recipesUsing[name] || [];
    }
    TooltipEngine.lookupRecipesUsing = lookupRecipesUsing;
    function isMagicDamage(ctx, value) {
        return ctx.catalog.magicDamageTypes[value] === true;
    }
    TooltipEngine.isMagicDamage = isMagicDamage;
})(TooltipEngine || (TooltipEngine = {}));
var TooltipEngine;
(function (TooltipEngine) {
    const emptyMap = Object.freeze(Object.create(null));
    const emptyArray = Object.freeze([]);
    let activeCatalog;
    function isMap(value) {
        return value !== null && typeof value === 'object' && !Array.isArray(value);
    }
    function validateCatalog(value) {
        if (!isMap(value) || value.version !== 1 || typeof value.contentVersion !== 'string'
            || !value.contentVersion || value.contentVersion.length > 128)
            throw new TooltipEngine.InputError('invalid_catalog_version');
        for (const field of ['items', 'mods', 'recipes', 'recipesUsing', 'magicDamageTypes']) {
            if (!isMap(value[field]))
                throw new TooltipEngine.InputError('invalid_catalog_' + field);
        }
        if (!isMap(value.levelStatList) && !Array.isArray(value.levelStatList))
            throw new TooltipEngine.InputError('invalid_catalog_levels');
    }
    /** Own-property validation is shared by direct Node callers and the ClearScript entry. */
    function validateTree(value, maxNodes, maxDepth) {
        const stack = [{ value, depth: 0 }];
        let nodes = 0;
        const seen = new Set();
        while (stack.length) {
            const entry = stack.pop();
            if (entry.exit) {
                seen.delete(entry.value);
                continue;
            }
            if (++nodes > maxNodes || entry.depth > maxDepth)
                throw new TooltipEngine.InputError('input_too_large');
            const current = entry.value;
            if (typeof current === 'function' || typeof current === 'symbol' || typeof current === 'bigint')
                throw new TooltipEngine.InputError('invalid_input_value');
            if (typeof current === 'string' && current.length > 131072)
                throw new TooltipEngine.InputError('input_string_too_large');
            if (!current || typeof current !== 'object')
                continue;
            if (seen.has(current))
                throw new TooltipEngine.InputError('cyclic_input');
            seen.add(current);
            stack.push({ value: current, depth: entry.depth, exit: true });
            for (const key of Object.keys(current)) {
                if (key === '__proto__' || key === 'prototype' || key === 'constructor')
                    throw new TooltipEngine.InputError('invalid_input_key');
                stack.push({ value: current[key], depth: entry.depth + 1 });
            }
        }
    }
    function freezeTree(value) {
        if (!value || typeof value !== 'object' || Object.isFrozen(value))
            return;
        for (const key of Object.keys(value))
            freezeTree(value[key]);
        Object.freeze(value);
    }
    /** The sole state is a validated, immutable static catalog, replaced atomically on init. */
    function initCatalog(json) {
        if (typeof json !== 'string' || json.length > 32 * 1024 * 1024)
            throw new TooltipEngine.InputError('invalid_catalog_json');
        const candidate = JSON.parse(json);
        validateCatalog(candidate);
        validateTree(candidate, 1000000, 48);
        freezeTree(candidate);
        activeCatalog = candidate;
        return candidate.contentVersion;
    }
    TooltipEngine.initCatalog = initCatalog;
    /** Restore only the restricted AS2 numeric transport markers, never executable values. */
    function decodeTransport(value) {
        if (!value || typeof value !== 'object')
            return value;
        const keys = Object.keys(value);
        if (Object.prototype.hasOwnProperty.call(value, '__tooltipNumber')) {
            if (keys.length !== 1)
                throw new TooltipEngine.InputError('invalid_number_marker');
            if (value.__tooltipNumber === 'NaN')
                return NaN;
            if (value.__tooltipNumber === 'Infinity')
                return Infinity;
            if (value.__tooltipNumber === '-Infinity')
                return -Infinity;
            throw new TooltipEngine.InputError('invalid_number_marker');
        }
        if (Object.prototype.hasOwnProperty.call(value, '__tooltipUndefined')) {
            if (keys.length !== 1 || value.__tooltipUndefined !== true)
                throw new TooltipEngine.InputError('invalid_undefined_marker');
            return undefined;
        }
        const result = Array.isArray(value) ? new Array(value.length) : {};
        for (const key of keys)
            result[key] = decodeTransport(value[key]);
        return result;
    }
    function validateInput(input) {
        if (!isMap(input) || input.version !== 1)
            throw new TooltipEngine.InputError('invalid_input_version');
        validateTree(input, 8192, 24);
        if (!['item', 'skill', 'body', 'hud'].includes(input.kind))
            throw new TooltipEngine.InputError('invalid_input_kind');
        if (input.presentation != null && !['native', 'inventory', 'web'].includes(input.presentation))
            throw new TooltipEngine.InputError('invalid_presentation');
        if (input.output != null && input.output !== 'details')
            throw new TooltipEngine.InputError('invalid_output');
        if (input.kind !== 'item')
            return;
        if (typeof input.itemName !== 'string' || !input.itemName || input.itemName.length > 512)
            throw new TooltipEngine.InputError('invalid_item_name');
        const p = input.projection;
        if (!isMap(p))
            throw new TooltipEngine.InputError('missing_projection');
        for (const field of ['isEquipment', 'isMaterial', 'isInformation']) {
            if (typeof p[field] !== 'boolean')
                throw new TooltipEngine.InputError('missing_classification');
        }
        for (const field of ['tierOptions', 'drugEffects', 'obtainRecords']) {
            if (!Array.isArray(p[field]))
                throw new TooltipEngine.InputError('missing_' + field);
        }
        if (!isMap(p.mods))
            throw new TooltipEngine.InputError('missing_mods');
        if (p.isMaterial && p.registeredModName !== null && typeof p.registeredModName !== 'string')
            throw new TooltipEngine.InputError('missing_registered_mod');
        for (const name of Object.keys(p.mods)) {
            const mod = p.mods[name];
            if (!isMap(mod) || typeof mod.present !== 'boolean' || !Array.isArray(mod.useCases)
                || !Array.isArray(mod.bulletCases))
                throw new TooltipEngine.InputError('invalid_mod_projection');
        }
        if (p.isEquipment && !isMap(p.baselineData))
            throw new TooltipEngine.InputError('missing_baseline_data');
        if (p.calculated != null && !isMap(p.calculated))
            throw new TooltipEngine.InputError('invalid_calculated_data');
    }
    function contextFor(input, catalog) {
        const decoded = decodeTransport(input);
        const projected = decoded.projection || {
            isEquipment: false, isMaterial: false, isInformation: false,
            tierOptions: emptyArray, drugEffects: emptyArray, mods: emptyMap, obtainRecords: emptyArray
        };
        return { input: decoded, catalog, projection: projected };
    }
    function result(document, introHTML, descHTML, detailsHTML) {
        return { document, introHTML, descHTML,
            details: TooltipEngine.plainText(detailsHTML === undefined ? introHTML + descHTML : detailsHTML).substr(0, 4096) };
    }
    function itemResult(ctx) {
        const input = ctx.input;
        const item = TooltipEngine.lookupItem(ctx, input.itemName);
        if (!item)
            throw new TooltipEngine.InputError('item_data_missing');
        // The legacy stats branch also accepts non-equipment items with data
        // (e.g. battlefield supplies). AS2 projects the same selector result.
        if (item.data && item.use !== TooltipEngine.ItemUseTypes.POTION && !isMap(ctx.projection.baselineData)) {
            throw new TooltipEngine.InputError('missing_baseline_data');
        }
        const calculated = ctx.projection.calculated;
        const base = calculated == null ? null : {
            name: input.itemName, value: input.value == null ? { level: 1 } : input.value,
            getData: () => calculated
        };
        const value = input.value == null ? { level: 1 } : input.value;
        const iconData = { ...calculated };
        if (ctx.projection.displayName !== undefined)
            iconData.displayname = ctx.projection.displayName;
        if (ctx.projection.iconName !== undefined)
            iconData.icon = ctx.projection.iconName;
        const fullDesc = TooltipEngine.TooltipComposer.generateItemDescriptionText(ctx, item, base);
        const fullIntro = TooltipEngine.TooltipComposer.generateIntroPanelContent(ctx, base, item, value);
        if (input.hud?.kind === 'drug') {
            let intro = fullIntro;
            const hud = input.hud;
            if (Math.floor(hud.count) === 1 && intro.indexOf('数量：') < 0)
                intro += '数量：1<BR>';
            const lane = hud.slot % 4;
            intro += '快捷栏：' + (hud.slot < 4 ? 'A' : 'B') + '组' + (lane + 1) + '号格';
            if (hud.key)
                intro += '（快捷键：' + hud.key + '）';
            intro += '<BR>';
            return result(TooltipEngine.NativeTooltipDocument.buildItem(input.itemName, item, iconData, intro, fullDesc), intro, fullDesc);
        }
        const subBlocks = [], docSubs = [];
        const desc = TooltipEngine.TooltipComposer.generateItemDescriptionTextEx(ctx, item, base, subBlocks, docSubs);
        const rail = TooltipEngine.TooltipComposer.getRailText(ctx, item, base);
        const magazine = TooltipEngine.TooltipComposer.getMagazineInfo(ctx, base, item, value);
        const upgrades = TooltipEngine.TooltipComposer.getUpgradePathInfo(ctx, item, base);
        const critSlay = [], buffs = [];
        // Web preview originally rebuilds equipment intro and potion buffs only.
        // Consumable grenades can have crit metadata; their Web intro stays inline.
        const splitEquipmentParts = input.presentation !== 'web' || ctx.projection.isEquipment;
        const intro = TooltipEngine.TooltipComposer.generateIntroPanelContent(ctx, base, item, value, {
            omitTypeLines: splitEquipmentParts && rail != null, omitActionType: splitEquipmentParts && rail != null,
            omitClipName: splitEquipmentParts && magazine != null, omitBulletType: splitEquipmentParts && magazine?.ammo != null,
            omitCritSlay: splitEquipmentParts, critSlay, omitBuff: input.presentation !== 'inventory', buff: buffs
        });
        if (buffs.length) {
            docSubs.unshift(buffs.join(''));
            subBlocks.unshift(buffs.join(''));
        }
        if (critSlay.length) {
            docSubs.unshift(critSlay.join(''));
            subBlocks.unshift(critSlay.join(''));
        }
        const document = TooltipEngine.NativeTooltipDocument.buildItem(input.itemName, item, iconData, intro, desc, docSubs, { rail: splitEquipmentParts ? rail : null, magazine: splitEquipmentParts ? magazine : null, upgrades });
        // ChoiceReward historically reads full intro + inline description. Web's
        // compatibility HTML reorders subpanels and may repeat crit/buff lines;
        // those delivery fragments must never redefine reward details.
        return result(document, fullIntro, input.presentation === 'web' ? desc + subBlocks.join('') : fullDesc, fullIntro + fullDesc);
    }
    function resourceHintHtml(hint) {
        if (!hint || hint.state === 'ready' || hint.state === 'unknown')
            return '';
        const resource = hint.reason === 'mp' ? 'MP' : '消耗品';
        return hint.state === 'blocked'
            ? "<BR><FONT COLOR='#e87864'>" + resource + '不足，无法释放</FONT>'
            : "<BR><FONT COLOR='#e8a080'>当前" + resource + '仅够再释放一次</FONT>';
    }
    TooltipEngine.resourceHintHtml = resourceHintHtml;
    function skillResult(input) {
        if (!isMap(input.skillData) || typeof input.skillName !== 'string')
            throw new TooltipEngine.InputError('invalid_skill_input');
        const skill = input.skillData;
        const state = input.state || {};
        let intro = '<B>' + TooltipEngine.as2String(skill.Name) + '</B><BR>' + TooltipEngine.as2String(skill.Type);
        if (input.mode === 'learn') {
            intro += '<BR>最高等级：' + TooltipEngine.as2String(skill.MaxLevel);
            intro += '<BR>解锁需要技能点数：' + TooltipEngine.as2String(skill.UnlockSP);
            if (skill.MaxLevel > 1)
                intro += '<BR>升级需要技能点数：' + TooltipEngine.as2String(skill.UpgradeSP);
        }
        else {
            const label = skill.Equippable ? (state.equipped === true ? '已装备' : '未装备')
                : (state.enabled === true ? '已启用' : '未启用');
            const active = skill.Equippable ? state.equipped === true : state.enabled === true;
            intro += "   <FONT COLOR='" + (active ? TooltipEngine.TooltipConstants.COL_HP : '#FFDDDD') + "'>" + label + '</FONT>';
        }
        intro += '<BR>冷却秒数：' + Math.floor(TooltipEngine.as2Number(skill.CD) / 100) / 10;
        intro += '<BR>MP消耗：' + TooltipEngine.as2String(skill.MP);
        intro += input.mode === 'learn' ? '<BR>等级限制：' + TooltipEngine.as2String(skill.UnlockLevel) : '<BR>技能等级：' + TooltipEngine.as2String(state.level);
        intro += resourceHintHtml(input.resourceHint);
        const desc = skill.Description ? TooltipEngine.as2String(skill.Description) : '';
        return result(TooltipEngine.NativeTooltipDocument.buildSkill(input.skillName, intro, desc), intro, desc);
    }
    /** Synchronous deterministic content engine. It never reads a host object, clock, I/O or shared request state. */
    function buildProjection(input, catalog) {
        validateCatalog(catalog);
        validateInput(input);
        const ctx = contextFor(input, catalog);
        input = ctx.input;
        switch (input.kind) {
            case 'item': return itemResult(ctx);
            case 'skill': return skillResult(input);
            case 'body': {
                if (input.html != null && typeof input.html !== 'string')
                    throw new TooltipEngine.InputError('invalid_text_input');
                const html = input.html || '';
                return result(TooltipEngine.NativeTooltipDocument.buildBody(html, input.profile || 'simple'), '', html);
            }
            case 'hud': return TooltipEngine.buildHudResult(input);
        }
    }
    TooltipEngine.buildProjection = buildProjection;
    function buildTooltip(input, catalog) {
        return buildProjection(input, catalog).document;
    }
    TooltipEngine.buildTooltip = buildTooltip;
    function readInput(json) {
        if (!activeCatalog)
            throw new TooltipEngine.InputError('catalog_not_initialized');
        if (typeof json !== 'string' || json.length > 256 * 1024)
            throw new TooltipEngine.InputError('input_too_large');
        return JSON.parse(json);
    }
    function buildJson(inputJson) {
        return JSON.stringify(buildTooltip(readInput(inputJson), activeCatalog));
    }
    TooltipEngine.buildJson = buildJson;
    function buildProjectionJson(inputJson) {
        const input = readInput(inputJson);
        const built = buildProjection(input, activeCatalog);
        return JSON.stringify(input.output === 'details' ? { details: built.details } : built);
    }
    TooltipEngine.buildProjectionJson = buildProjectionJson;
    function htmlToRuns(html) { return TooltipEngine.NativeTooltipDocument.htmlToRuns(html); }
    TooltipEngine.htmlToRuns = htmlToRuns;
})(TooltipEngine || (TooltipEngine = {}));
var TooltipEngine;
(function (TooltipEngine) {
    function finite(value) { const n = TooltipEngine.as2Number(value); return Number.isFinite(n) ? n : 0; }
    function text(value) { return value == null ? '' : String(value); }
    function percent(current, maximum) {
        return Number(maximum) > 0 ? Math.floor(Number(current) / Number(maximum) * 100) + '%' : '未就绪';
    }
    /** Presentation of already-authorized HUD snapshots; no resource availability recomputation. */
    function buildHudResult(input) {
        const data = input.data;
        if (!data || typeof data !== 'object' || Array.isArray(data))
            throw new TooltipEngine.InputError('invalid_hud_input');
        let html = '', profile = 'dense';
        let document;
        switch (input.mode) {
            case 'action': {
                html = 'Lee 固定招式。按 ' + text(data.keyLabel) + ' 发动；不消耗 MP。';
                const desc = text(data.description);
                document = TooltipEngine.NativeTooltipDocument.buildSkill(text(data.name), html, desc);
                return { document, introHTML: html, descHTML: desc, details: TooltipEngine.plainText(html + desc).substr(0, 4096) };
            }
            case 'weapon':
                html = '<B>' + text(data.name) + '</B><BR>冷却：' + finite(data.cooldown) / 1000 + ' 秒';
                html += '<BR>MP消耗：' + finite(data.mp);
                if (finite(data.hp) > 0)
                    html += '<BR>生命消耗：' + finite(data.hp);
                if (finite(data.sp) > 0)
                    html += '<BR>技能点消耗：' + finite(data.sp);
                if (text(data.description))
                    html += '<BR>' + text(data.description);
                if (text(data.information))
                    html += '<BR>' + text(data.information);
                html += TooltipEngine.resourceHintHtml(input.resourceHint || data.resourceHint);
                break;
            case 'switch':
                profile = 'simple';
                html = '<B>药剂组 ' + (data.bank === 0 ? 'I' : 'II') + '</B><BR>点击或按 ' + data.switchKey + ' 切换另一组药剂。';
                html += '<BR>同一列共用冷却，换组不会重置冷却。';
                if (!data.otherBankHasStock)
                    html += "<BR><FONT COLOR='#e87864'>另一组没有剩余药剂，暂时无法切换。</FONT>";
                break;
            case 'resources':
                if (!Array.isArray(data.hp) || !Array.isArray(data.mp) || !Array.isArray(data.shield) || !Array.isArray(data.experience))
                    throw new TooltipEngine.InputError('invalid_vitals');
                html = '生命：' + Math.floor(data.hp[0]) + ' / ' + Math.floor(data.hp[1]) + '（' + percent(data.hp[0], data.hp[1]) + '）';
                html += '<BR>护盾：' + (!data.shieldReady ? '未就绪' : data.shieldPresent ? Math.floor(data.shield[0]) + ' / ' + Math.floor(data.shield[1]) : '无护盾');
                html += data.mp[0] === 0 && data.mp[1] === 0 ? '<BR>MP：本单位不使用此资源。'
                    : '<BR>MP：' + Math.floor(data.mp[0]) + ' / ' + Math.floor(data.mp[1]) + '（' + percent(data.mp[0], data.mp[1]) + '）';
                html += '<BR>韧性：' + Math.floor(data.poise * 100) + '%<BR>经验：' + Math.floor(data.experience[0]) + ' / ' + Math.floor(data.experience[2]);
                html += '<BR>技能点：' + Math.floor(data.sp);
                break;
            default: throw new TooltipEngine.InputError('invalid_hud_mode');
        }
        document = TooltipEngine.NativeTooltipDocument.buildBody(html, profile);
        return { document, introHTML: '', descHTML: html, details: TooltipEngine.plainText(html).substr(0, 4096) };
    }
    TooltipEngine.buildHudResult = buildHudResult;
})(TooltipEngine || (TooltipEngine = {}));
// Preserves StringUtils.htmlToPlainTextFast behavior for ChoiceReward.details.
var TooltipEngine;
(function (TooltipEngine) {
    function plainText(input) {
        if (input == null || input == undefined)
            return "";
        var s = String(input);
        var len = s.length;
        var i = 0;
        var out = [];
        var ch;
        while (i < len) {
            ch = s.charCodeAt(i);
            if (ch == 60) {
                var j = i + 1;
                while (j < len) {
                    var c = s.charCodeAt(j);
                    if (c == 32 || c == 9 || c == 10 || c == 13)
                        j++;
                    else
                        break;
                }
                if (j < len && s.charAt(j) == "/")
                    j++;
                while (j < len) {
                    c = s.charCodeAt(j);
                    if (c == 32 || c == 9)
                        j++;
                    else
                        break;
                }
                var start = j;
                while (j < len) {
                    c = s.charCodeAt(j);
                    if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57))
                        j++;
                    else
                        break;
                }
                var tag = s.substring(start, j).toLowerCase();
                while (j < len && s.charAt(j) != ">")
                    j++;
                if (j < len)
                    j++;
                if (tag == "br" || tag == "p" || tag == "div" || tag == "li" || tag == "ul" || tag == "ol" ||
                    tag == "h1" || tag == "h2" || tag == "h3" || tag == "h4" || tag == "h5" || tag == "h6" ||
                    tag == "tr" || tag == "table" || tag == "thead" || tag == "tbody" || tag == "tfoot") {
                    out.push("\n");
                }
                i = j;
                continue;
            }
            if (ch == 38) {
                var k = i + 1;
                var semi = k;
                while (semi < len && s.charAt(semi) != ";")
                    semi++;
                if (semi < len) {
                    var entity = s.substring(k, semi);
                    var decoded = null;
                    if (entity.length > 0 && entity.charAt(0) == "#") {
                        if (entity.length > 1 && (entity.charAt(1) == "x" || entity.charAt(1) == "X")) {
                            var v = 0;
                            var idx = 2;
                            while (idx < entity.length) {
                                var cc = entity.charCodeAt(idx);
                                if (cc >= 48 && cc <= 57)
                                    v = v * 16 + (cc - 48);
                                else if (cc >= 65 && cc <= 70)
                                    v = v * 16 + (cc - 55);
                                else if (cc >= 97 && cc <= 102)
                                    v = v * 16 + (cc - 87);
                                else
                                    break;
                                idx++;
                            }
                            decoded = TooltipEngine.as2FromCharCode(v);
                        }
                        else {
                            var v10 = 0;
                            var idx2 = 1;
                            while (idx2 < entity.length) {
                                var c2 = entity.charCodeAt(idx2);
                                if (c2 >= 48 && c2 <= 57) {
                                    v10 = v10 * 10 + (c2 - 48);
                                    idx2++;
                                }
                                else
                                    break;
                            }
                            decoded = TooltipEngine.as2FromCharCode(v10);
                        }
                    }
                    else {
                        var e = entity.toLowerCase();
                        if (e == "amp")
                            decoded = "&";
                        else if (e == "lt")
                            decoded = "<";
                        else if (e == "gt")
                            decoded = ">";
                        else if (e == "quot")
                            decoded = "\"";
                        else if (e == "apos")
                            decoded = "'";
                        else if (e == "nbsp")
                            decoded = " ";
                    }
                    if (decoded != null) {
                        out.push(decoded);
                        i = semi + 1;
                        continue;
                    }
                }
                out.push("&");
                i++;
                continue;
            }
            if (ch == 13) {
                out.push("\n");
                i++;
                continue;
            }
            out.push(s.charAt(i));
            i++;
        }
        var raw = out.join("");
        var resParts = [];
        var prevSpace = false;
        var nlCount = 0;
        var L = raw.length;
        for (i = 0; i < L; i++) {
            var chs = raw.charAt(i);
            var code = raw.charCodeAt(i);
            if (chs == "\n") {
                if (nlCount < 2)
                    resParts.push("\n");
                nlCount++;
                prevSpace = false;
            }
            else if (code == 32 || code == 9 || code == 160) {
                if (!prevSpace) {
                    resParts.push(" ");
                    prevSpace = true;
                }
            }
            else {
                resParts.push(chs);
                prevSpace = false;
                nlCount = 0;
            }
        }
        var joined = resParts.join("");
        var lines = joined.split("\n");
        for (i = 0; i < lines.length; i++) {
            lines[i] = TooltipEngine.trim(lines[i]);
        }
        var finalStr = lines.join("\n");
        return TooltipEngine.trim(finalStr);
    }
    TooltipEngine.plainText = plainText;
})(TooltipEngine || (TooltipEngine = {}));
