// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/TooltipTextBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace TooltipTextBuilder {
        function buildOperationPrefix(ctx: Context, operationType?: string): string {
            if (!operationType)
                return "";
            return "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>[" + operationType + "]</FONT> ";
        }
        export function buildBasicDescription(ctx: Context, item?: any, baseItem?: Instance, nightVisionBuffer?: any[]): any[] {
            var result: any = [];
            var description: string = item.description;
            if (baseItem && as2NotEqual(baseItem.getData, undefined)) {
                var calculatedData: any = baseItem.getData();
                if (calculatedData && calculatedData.description !== undefined) {
                    description = calculatedData.description;
                }
            }
            if (description) {
                var normalized: string = TooltipFormatter.normalizeDescription(description);
                if (as2NotEqual(nightVisionBuffer, null)) {
                    normalized = extractNightVisionLines(ctx, normalized, nightVisionBuffer);
                }
                if (normalized)
                    result.push(normalized, TooltipFormatter.br());
            }
            return result;
        }
        function extractNightVisionLines(ctx: Context, normalized?: string, output?: any[]): string {
            var lines: any[] = normalized.split("<BR>");
            var mainLines: any[] = [];
            for (var i: number = 0; as2Less(i, lines.length); i++) {
                var line: string = lines[i];
                if (as2GreaterEqual(line.indexOf("【夜视】"), 0)) {
                    output.push(line, TooltipFormatter.br());
                }
                else {
                    mainLines.push(line);
                }
            }
            return mainLines.join("<BR>");
        }
        export function buildStoryTip(ctx: Context, item?: any): any[] {
            var result: any = [];
            if (as2Equal(item.use, ItemUseTypes.INFORMATION)) {
                result.push(TooltipFormatter.color(TooltipConstants.TIP_INFO_LOCATION, TooltipConstants.COL_INFO), TooltipFormatter.br());
            }
            return result;
        }
        export function buildSynthesisMaterials(ctx: Context, item?: any): any[] {
            var result: any = [];
            var synthData: any = lookupRecipe(ctx, item.synthesis);
            if (as2NotEqual(item.synthesis, null) && synthData && synthData.materials) {
                var requirements: any = synthData.materials;
                if (requirements && as2Greater(requirements.length, 0)) {
                    result.push(TooltipConstants.LBL_SYNTHESIS, "：<BR>");
                    for (var i: any = 0; as2Less(i, requirements.length); i++) {
                        if (requirements[i] && requirements[i].name) {
                            var itemData: any = lookupItem(ctx, requirements[i].name);
                            var displayText: any = itemData?.displayname;
                            if (requirements[i].isQuantity) {
                                displayText += " x " + requirements[i].value;
                            }
                            else if (isEquipment(ctx, requirements[i].name)) {
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
        export function buildObtainMethods(ctx: Context, itemName?: string): any[] {
            return ObtainMethodsBuilder.build(ctx, itemName);
        }
        export function buildUpgradePath(ctx: Context, item?: any, baseItem?: Instance): any[] {
            return UpgradePathBuilder.build(ctx, item, baseItem);
        }
        export function buildUpgradePathWithRows(ctx: Context, item?: any, baseItem?: Instance): any {
            return UpgradePathBuilder.buildWithRows(ctx, item, baseItem);
        }
        export function buildBladeSkillMultipliers(ctx: Context, item?: any, baseItem?: Instance): any[] {
            var result: any = [];
            if (item.use !== ItemUseTypes.MELEE)
                return result;
            var baseSkillMultipliers: any = (item.data && item.data.skillmultipliers) ? item.data.skillmultipliers : null;
            var finalSkillMultipliers: any = null;
            var hasEquipData: any = false;
            if (baseItem && as2NotEqual(baseItem.getData, undefined)) {
                var calculatedData: any = baseItem.getData();
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
            var skillNames: any = {};
            if (baseSkillMultipliers) {
                for (var key of as2Keys(baseSkillMultipliers)) {
                    if (isInternalKey(key))
                        continue;
                    skillNames[key] = true;
                }
            }
            if (finalSkillMultipliers) {
                for (var key of as2Keys(finalSkillMultipliers)) {
                    if (isInternalKey(key))
                        continue;
                    skillNames[key] = true;
                }
            }
            for (var skillName of as2Keys(skillNames)) {
                var baseMultiplier: any = (baseSkillMultipliers && baseSkillMultipliers[skillName]) ? baseSkillMultipliers[skillName] : null;
                var finalMultiplier: any = (finalSkillMultipliers && finalSkillMultipliers[skillName]) ? finalSkillMultipliers[skillName] : null;
                var baseNum: any = as2Number(baseMultiplier);
                if (as2IsNaN(baseNum) || as2LessEqual(baseNum, 1))
                    baseNum = 1;
                var finalNum: any = as2Number(finalMultiplier);
                if (as2IsNaN(finalNum) || as2LessEqual(finalNum, 1))
                    finalNum = 1;
                if (as2Equal(baseNum, 1) && as2Equal(finalNum, 1))
                    continue;
                if (!hasEquipData || as2Equal(finalNum, baseNum)) {
                    if (as2Greater(baseNum, 1)) {
                        result.push(TooltipFormatter.color(TooltipConstants.LBL_SKILL_BONUS, TooltipConstants.COL_HL), TooltipConstants.TIP_USE, skillName, TooltipConstants.TIP_ENJOY, String((baseNum - 1) * 100), TooltipConstants.SUF_PERCENT, TooltipConstants.TIP_SHARPNESS_BONUS, TooltipFormatter.br());
                    }
                }
                else {
                    var finalPercent: any = (finalNum - 1) * 100;
                    var basePercent: any = (baseNum - 1) * 100;
                    var enhance: any = finalNum - baseNum;
                    var enhancePercent: any = enhance * 100;
                    result.push(TooltipFormatter.color(TooltipConstants.LBL_SKILL_BONUS, TooltipConstants.COL_HL), TooltipConstants.TIP_USE, skillName, TooltipConstants.TIP_ENJOY, "<FONT COLOR='", TooltipConstants.COL_HL, "'>", String(finalPercent), TooltipConstants.SUF_PERCENT, "</FONT>", TooltipConstants.TIP_SHARPNESS_BONUS);
                    var sign: string;
                    if (as2Less(enhance, 0)) {
                        enhancePercent = -enhancePercent;
                        sign = " - ";
                    }
                    else {
                        sign = " + ";
                    }
                    result.push(" (", String(basePercent), TooltipConstants.SUF_PERCENT, sign, String(enhancePercent), TooltipConstants.SUF_PERCENT, ")<BR>");
                }
            }
            return result;
        }
        export function buildSubweaponInfo(ctx: Context, subweapon?: any): any[] {
            var result: any = [];
            var sub: any = ctx.projection.subweapon;
            if (!sub)
                return result;
            if (sub.description) {
                result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_SUBWEAPON + "</font>", TooltipFormatter.normalizeDescription(sub.description), "<BR>");
            }
            else {
                result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_SUBWEAPON + "</font>", sub.name, "<BR>");
            }
            result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_SUBWEAPON_INFO + "</font>");
            result.push("装填", sub.capacity, "发，弹药", sub.reserveName);
            result.push("，冷却", sub.cd / 1000, TooltipConstants.SUF_SECOND);
            result.push("，威力", sub.power, "，子弹", sub.bullet);
            if (sub.damageType)
                result.push("，伤害类型", sub.damageType);
            if (sub.magicType)
                result.push("，属性", sub.magicType);
            if (sub.hp && as2NotEqual(sub.hp, 0))
                result.push("，", TooltipConstants.LBL_COST, sub.hp, TooltipConstants.SUF_HP);
            if (sub.mp && as2NotEqual(sub.mp, 0))
                result.push("，", TooltipConstants.LBL_COST, sub.mp, TooltipConstants.SUF_MP);
            if (as2Equal(sub.consumeMode, "onFire")) {
                result.push("，逐发消耗", sub.fireCost, "份");
            }
            else {
                result.push("，每组消耗", sub.clipCostPerLoad, "份");
                if (as2Equal(sub.consumeTiming, "linkedFirstFire"))
                    result.push("，主武器换弹联动补装");
                if (as2Equal(sub.consumeTiming, "onReloadCommit"))
                    result.push("，装填时扣除备弹");
            }
            result.push("。<BR>");
            return result;
        }
        export function buildSkillInfo(ctx: Context, skill?: any): any[] {
            var result: any = [];
            if (!skill)
                return result;
            if (skill.description) {
                result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_ACTIVE_SKILL + "</font>", TooltipFormatter.normalizeDescription(skill.description), "<BR><font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_SKILL_INFO + "</font>");
                if (skill.information) {
                    result.push(skill.information);
                }
                else {
                    var cooldown: any = skill.cd / 1000;
                    result.push(TooltipConstants.LBL_COOLDOWN, cooldown, TooltipConstants.SUF_SECOND);
                    if (skill.hp && as2NotEqual(skill.hp, 0))
                        result.push("，", TooltipConstants.LBL_COST, skill.hp, TooltipConstants.SUF_HP);
                    if (skill.mp && as2NotEqual(skill.mp, 0))
                        result.push("，", TooltipConstants.LBL_COST, skill.mp, TooltipConstants.SUF_MP);
                    if (skill.sp && as2NotEqual(skill.sp, 0))
                        result.push("，", TooltipConstants.LBL_COST, skill.sp, TooltipConstants.SUF_SP);
                    result.push("。");
                }
                result.push("<BR>");
            }
            else if (as2Equal(typeof skill, "object") && !(Array.isArray(skill))
                && !(skill instanceof String)) {
                if (as2NotEqual(skill.skillname, undefined) && as2Greater(String(skill.skillname).length, 0)) {
                    result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_ACTIVE_SKILL + "</font>", TooltipFormatter.normalizeDescription(String(skill.skillname)));
                    if (skill.information) {
                        result.push("<BR><font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_SKILL_INFO + "</font>", skill.information);
                    }
                    else {
                        var infoText: string = "";
                        var skillCooldown: number = as2Number(skill.cd) / 1000;
                        if (!as2IsNaN(skillCooldown) && as2Greater(skillCooldown, 0)) {
                            infoText += TooltipConstants.LBL_COOLDOWN + skillCooldown + TooltipConstants.SUF_SECOND;
                        }
                        if (skill.hp && as2NotEqual(as2Number(skill.hp), 0)) {
                            infoText += "，" + TooltipConstants.LBL_COST + skill.hp + TooltipConstants.SUF_HP;
                        }
                        if (skill.mp && as2NotEqual(as2Number(skill.mp), 0)) {
                            infoText += "，" + TooltipConstants.LBL_COST + skill.mp + TooltipConstants.SUF_MP;
                        }
                        if (skill.sp && as2NotEqual(as2Number(skill.sp), 0)) {
                            infoText += "，" + TooltipConstants.LBL_COST + skill.sp + TooltipConstants.SUF_SP;
                        }
                        if (as2Greater(infoText.length, 0)) {
                            result.push("<BR><font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_SKILL_INFO + "</font>", infoText, "。");
                        }
                    }
                    result.push("<BR>");
                }
            }
            else {
                result.push(TooltipFormatter.normalizeDescription(String(skill)), "<BR>");
            }
            return result;
        }
        export function buildLifecycleInfo(ctx: Context, lc?: any): any[] {
            var result: any = [];
            if (lc && lc.description)
                result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_AFFIX_INFO + "</font>", TooltipFormatter.normalizeDescription(lc.description), "<BR>");
            return result;
        }
        export function buildIntroHeader(ctx: Context, baseItem?: Instance, item?: any, externalValue?: any, nativeOpt?: any): any[] {
            var value: any = baseItem && baseItem.value ? baseItem.value : (externalValue ? externalValue : 1);
            var upgradeLevel: any = value.level ? value.level : 1;
            var displayName: string = item.displayname;
            if (baseItem && as2NotEqual(baseItem.getData, undefined)) {
                var calculatedData: any = baseItem.getData();
                if (calculatedData && calculatedData.displayname !== undefined) {
                    displayName = calculatedData.displayname;
                }
            }
            var result: any = [];
            result.push("<B>", (value.tier ? ("[" + value.tier + "]") : ""), displayName, "</B><BR>");
            var omitTypeLines: boolean = (as2NotEqual(nativeOpt, null) && nativeOpt.omitTypeLines === true);
            if (!omitTypeLines) {
                result.push(item.type, "    ", item.use, "<BR>");
                if (ItemUseTypes.isGun(item.use) && item.data && item.weapontype) {
                    result.push(TooltipConstants.LBL_WEAPON_TYPE, "：", item.weapontype, "<BR>");
                }
            }
            result.push("$", item.price, "<BR>");
            if (as2Greater(upgradeLevel, 1) && (as2Equal(item.type, ItemUseTypes.TYPE_WEAPON) || as2Equal(item.type, ItemUseTypes.TYPE_ARMOR))) {
                var levelMultiplier: number = ctx.projection.levelMultiplier;
                if (levelMultiplier && !as2IsNaN(levelMultiplier)) {
                    var enhancement: number = Math.round((levelMultiplier - 1) * 100);
                    result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_UPGRADE_LEVEL + "：", upgradeLevel, " (+", enhancement, "%)</FONT><BR>");
                }
                else {
                    result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_UPGRADE_LEVEL + "：", upgradeLevel, "</FONT><BR>");
                }
            }
            else {
                var quantity: number = 0;
                if (as2Equal(typeof value, "number")) {
                    quantity = as2Number(value);
                }
                else if (value) {
                    var candidates: any = [value.count, value.amount, value.num, value.stack, value.quantity];
                    for (var i: any = 0; as2Less(i, candidates.length); i++) {
                        var candidate: any = as2Number(candidates[i]);
                        if (!as2IsNaN(candidate) && as2Greater(candidate, 0)) {
                            quantity = candidate;
                            break;
                        }
                    }
                }
                if (as2Greater(quantity, 1))
                    result.push(TooltipConstants.LBL_QUANTITY, "：", quantity, "<BR>");
            }
            return result;
        }
        export function buildStats(ctx: Context, baseItem?: Instance, item?: any, externalValue?: any, nativeOpt?: any): any[] {
            if (!item.data)
                return [];
            if (item.use === ItemUseTypes.POTION) {
                return DrugTooltipComposer.compose(ctx, item, (as2NotEqual(nativeOpt, null) && nativeOpt.omitBuff === true) ? nativeOpt.buff : null);
            }
            else {
                return buildEquipmentStats(ctx, baseItem, item, externalValue, nativeOpt);
            }
        }
        export function buildDrugStats(ctx: Context, item?: any): any[] {
            return DrugTooltipComposer.compose(ctx, item);
        }
        export function buildEquipmentStats(ctx: Context, baseItem?: Instance, item?: any, externalValue?: any, nativeOpt?: any): any[] {
            var value: any = baseItem && baseItem.value ? baseItem.value : (externalValue ? externalValue : 1);
            var upgradeLevel: any = value.level ? value.level : 1;
            var data: any = ctx.projection.baselineData;
            var equipData: any = as2Greater(upgradeLevel, 1) || value.mods ? baseItem.getData().data : null;
            return EquipmentStatsComposer.compose(ctx, baseItem, item, data, equipData, nativeOpt);
        }
        export function buildModStat(ctx: Context, itemName?: string): any[] {
            return ModStatBuilder.build(ctx, itemName);
        }
        export function buildModStatWithRows(ctx: Context, itemName?: string): any {
            return ModStatBuilder.buildWithRows(ctx, itemName);
        }
        export function buildEquipmentTagInfo(ctx: Context, item?: any): any[] {
            var result: any[] = [];
            if (item.inherentTags) {
                var inherentArr: any[] = item.inherentTags.split(",");
                var inherentTags: any[] = [];
                for (var i: number = 0; as2Less(i, inherentArr.length); i++) {
                    var tag: string = trim(inherentArr[i]);
                    if (as2Greater(tag.length, 0)) {
                        inherentTags.push(tag);
                    }
                }
                if (as2Greater(inherentTags.length, 0)) {
                    result.push("<font color='" + TooltipConstants.COL_ENHANCE + "'>" + TooltipConstants.LBL_INHERENT_TAGS + "：</font>", inherentTags.join(", "), "<BR>");
                }
            }
            if (item.blockedTags) {
                var blockedArr: any[] = item.blockedTags.split(",");
                var blockedTags: any[] = [];
                for (var j: number = 0; as2Less(j, blockedArr.length); j++) {
                    var blocked: string = trim(blockedArr[j]);
                    if (as2Greater(blocked.length, 0)) {
                        blockedTags.push(blocked);
                    }
                }
                if (as2Greater(blockedTags.length, 0)) {
                    result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_BLOCKED_TAGS + "：</font>", blockedTags.join(", "), "<BR>");
                }
            }
            return result;
        }
        export function quickBuildCriticalHit(ctx: Context, criticalhit?: any): string {
            if (!as2IsNaN(as2Number(criticalhit)))
                return "<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>" + TooltipConstants.LBL_CRIT + "：</FONT><FONT COLOR='" + TooltipConstants.COL_CRIT + "'>" + criticalhit + TooltipConstants.SUF_PERCENT + TooltipConstants.TIP_CRIT_CHANCE + "</FONT><BR>";
            else if (criticalhit === TooltipConstants.TIP_CRIT_FULL_HP)
                return "<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>" + TooltipConstants.LBL_CRIT + "：" + TooltipConstants.TIP_CRIT_FULL_HP_DESC + "</FONT><BR>";
            return "";
        }
        export function quickBuildMagicDefence(ctx: Context, magicdefence?: any, operationType?: string): string {
            var mdList: any = [];
            for (var key of as2Keys(magicdefence)) {
                if (isInternalKey(key))
                    continue;
                var mdName: any = (key === TooltipConstants.TXT_BASE ? TooltipConstants.TXT_ENERGY : key);
                var value: any = magicdefence[key];
                if (value)
                    mdList.push(mdName + ": " + value);
            }
            if (as2Greater(mdList.length, 0)) {
                var prefix: any = buildOperationPrefix(ctx, operationType);
                return prefix + TooltipConstants.SUF_RESISTANCE + " -> " + mdList.join(", ") + "<BR>";
            }
            return "";
        }
        export function quickBuildSkillMultipliers(ctx: Context, skillmultipliers?: any, operationType?: string): string {
            if (!skillmultipliers)
                return "";
            var result: any = "";
            for (var skillName of as2Keys(skillmultipliers)) {
                if (isInternalKey(skillName))
                    continue;
                var multiplier: any = as2Number(skillmultipliers[skillName]);
                if (!as2IsNaN(multiplier) && as2Greater(multiplier, 1)) {
                    var prefix: any = buildOperationPrefix(ctx, operationType);
                    result += prefix + TooltipFormatter.color(TooltipConstants.LBL_SKILL_BONUS, TooltipConstants.COL_HL);
                    result += TooltipConstants.TIP_USE + skillName + TooltipConstants.TIP_ENJOY + String((multiplier - 1) * 100) + TooltipConstants.SUF_PERCENT + TooltipConstants.TIP_SHARPNESS_BONUS;
                    result += TooltipFormatter.br();
                }
            }
            return result;
        }
        export function quickBuildDamageType(ctx: Context, buf?: any[], data?: any): void {
            if (!data.damagetype)
                return;
            if (as2Equal(data.damagetype, TooltipConstants.TXT_MAGIC) && data.magictype) {
                TooltipFormatter.colorLine(buf, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_ATTR + "：" + data.magictype);
            }
            else if (as2Equal(data.damagetype, TooltipConstants.TXT_BREAK) && data.magictype) {
                if (isMagicDamage(ctx, data.magictype))
                    TooltipFormatter.colorLine(buf, TooltipConstants.COL_BREAK_LIGHT, TooltipConstants.LBL_EXTRA_DAMAGE + "：" + data.magictype);
                else
                    TooltipFormatter.colorLine(buf, TooltipConstants.COL_BREAK_MAIN, TooltipConstants.LBL_BREAK_TYPE + "：" + data.magictype);
            }
            else {
                TooltipFormatter.colorLine(buf, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_TYPE + "：" + (as2Equal(data.damagetype, TooltipConstants.TXT_MAGIC) ? TooltipConstants.TXT_ENERGY : data.damagetype));
            }
        }
        export function getSortedAttrList(ctx: Context, data?: any): any[] {
            var list: any[] = [];
            var priorities: any = TooltipConstants.PROPERTY_PRIORITIES;
            for (var key of as2Keys(data)) {
                if (!as2IsNaN(priorities[key]))
                    list.push(key);
            }
            var sortFunc: any = function (keyA: string, keyB: string) {
                return priorities[keyA] - priorities[keyB];
            };
            return list.sort(sortFunc);
        }
    }
}
