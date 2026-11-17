// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/ModsBlockBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace ModsBlockBuilder {
        export function build(ctx: Context, result?: any[], baseItem?: Instance, item?: any, value?: any): void {
            buildWithRows(ctx, result, baseItem, item, value);
        }
        export function buildWithRows(ctx: Context, result?: any[], baseItem?: Instance, item?: any, value?: any): any {
            var collected: any = collect(ctx, baseItem, item, value);
            if (as2Equal(collected, null))
                return null;
            result.push(collected.titleHtml);
            var rows: any[] = collected.rows;
            var attachments: any[] = [];
            for (var i: number = 0; as2Less(i, rows.length); i++) {
                var row: any = rows[i];
                result.push("  • ", row.name, row.tagHtml, row.percentageHtml, row.multiplierHtml);
                if (as2Greater(row.overrideParts.length, 0)) {
                    if (row.hasNumeric)
                        result.push("<BR>    ");
                    result.push(row.overrideParts.join(""));
                }
                result.push("<BR>");
                var effect: string = row.tagHtml + row.percentageHtml + row.multiplierHtml;
                if (as2Greater(row.overrideParts.length, 0)) {
                    effect += " " + row.overrideParts.join("");
                }
                var outRow: any = { name: row.name, effect: effect };
                if (as2NotEqual(row.icon, null))
                    outRow.icon = row.icon;
                attachments.push(outRow);
            }
            return {
                kind: "attachments",
                title: TooltipConstants.LBL_INSTALLED_MODS + rows.length
                    + TooltipConstants.LBL_MOD_COUNT_SUFFIX,
                rows: attachments
            };
        }
        function collect(ctx: Context, baseItem?: Instance, item?: any, value?: any): any {
            if (as2Equal(value, null) || !value.mods || as2LessEqual(value.mods.length, 0)) {
                return null;
            }
            var titleHtml: string = "<font color='" + TooltipConstants.COL_HL + "'>"
                + TooltipConstants.LBL_INSTALLED_MODS + value.mods.length
                + TooltipConstants.LBL_MOD_COUNT_SUFFIX + "：</font><BR>";
            var rawItemData: any = baseItem ? lookupItem(ctx, baseItem.name) : null;
            var baseBulletType: string = (rawItemData && rawItemData.data && rawItemData.data.bullet) ? rawItemData.data.bullet : "";
            var rows: any[] = [];
            for (var i: number = 0; as2Less(i, value.mods.length); i++) {
                var modName: string = value.mods[i];
                if (!modName)
                    continue;
                const published = projectedMod(ctx, modName);
                var modInfo: any = published.present === false ? null : ctx.catalog.mods[modName];
                if (published.present !== false && !modInfo) throw new InputError('catalog_mod_missing');
                var row: any = {
                    name: modName,
                    icon: null,
                    tagHtml: "",
                    percentageHtml: "",
                    multiplierHtml: "",
                    overrideParts: [],
                    hasNumeric: false
                };
                var modItemData: any = lookupItem(ctx, modName);
                if (as2NotEqual(modItemData, null) && as2NotEqual(modItemData.icon, undefined) && as2NotEqual(modItemData.icon, "")) {
                    row.icon = String(modItemData.icon);
                }
                if (modInfo && modInfo.tagValue) {
                    row.tagHtml = " <font color='" + TooltipConstants.COL_INFO + "'>["
                        + modInfo.tagValue + "]</font>";
                }
                if (modInfo && modInfo.stats && modInfo.stats.percentage) {
                    var enhancements: any[] = [];
                    var percentage: any = modInfo.stats.percentage;
                    for (var prop of as2Keys(percentage)) {
                        var percentValue: number = as2Number(percentage[prop]);
                        if (!as2IsNaN(percentValue) && as2NotEqual(percentValue, 0)) {
                            var sign: string = as2Greater(percentValue, 0) ? "+" : "";
                            var percent: number = Math.round(percentValue * 100);
                            enhancements.push(sign + percent + "%");
                        }
                    }
                    if (as2Greater(enhancements.length, 0)) {
                        row.percentageHtml = " <font color='" + TooltipConstants.COL_ENHANCE
                            + "'>(" + enhancements.join(", ") + ")</font>";
                        row.hasNumeric = true;
                    }
                }
                if (modInfo && modInfo.stats && modInfo.stats.multiplier) {
                    var multiplierEnhancements: any[] = [];
                    var multiplier: any = modInfo.stats.multiplier;
                    for (var mprop of as2Keys(multiplier)) {
                        var mValue: number = as2Number(multiplier[mprop]);
                        if (!as2IsNaN(mValue) && as2NotEqual(mValue, 0)) {
                            var mtext: string;
                            if (as2Less(mValue, 0)) {
                                var multiplierValue: number = 1 + mValue;
                                var displayValue: number = Math.round(multiplierValue * 100) / 100;
                                mtext = "×" + displayValue;
                            }
                            else {
                                var mpercent: number = Math.round(mValue * 100);
                                mtext = "×+" + mpercent + "%";
                            }
                            multiplierEnhancements.push(mtext);
                        }
                    }
                    if (as2Greater(multiplierEnhancements.length, 0)) {
                        row.multiplierHtml = " <font color='" + TooltipConstants.COL_MULTIPLIER
                            + "'>{" + multiplierEnhancements.join(", ") + "}</font>";
                        row.hasNumeric = true;
                    }
                }
                var overrideEffectParts: any[] = [];
                if (modInfo && modInfo.stats && modInfo.stats.override && modInfo.stats.override.silence) {
                    var silenceDesc: string = SilenceEffectBuilder.getShortDescription(ctx, modInfo.stats.override.silence);
                    if (as2NotEqual(silenceDesc, "")) {
                        overrideEffectParts.push(" <font color='" + TooltipConstants.COL_SILENCE + "'>[" + silenceDesc + "]</font>");
                    }
                }
                if (modInfo && modInfo.stats && modInfo.stats.override && as2NotEqual(modInfo.stats.override.singleshoot, undefined)) {
                    var singleshootVal: boolean = (as2Equal(modInfo.stats.override.singleshoot, true) || as2Equal(modInfo.stats.override.singleshoot, "true"));
                    var fireModeDesc: string = singleshootVal ? TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipConstants.TIP_FIRE_MODE_AUTO;
                    overrideEffectParts.push(" <font color='" + TooltipConstants.COL_HL + "'>[" + TooltipConstants.LBL_FIRE_MODE + ": " + fireModeDesc + "]</font>");
                }
                if (modInfo && modInfo.stats && modInfo.stats.override && as2NotEqual(modInfo.stats.override.reloadType, undefined)) {
                    var reloadTypeVal: string = modInfo.stats.override.reloadType;
                    var reloadTypeDesc: string = (as2Equal(reloadTypeVal, "tube")) ? TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipConstants.TIP_RELOAD_TYPE_MAG;
                    overrideEffectParts.push(" <font color='" + TooltipConstants.COL_HL + "'>[" + TooltipConstants.LBL_RELOAD_TYPE + ": " + reloadTypeDesc + "]</font>");
                }
                var hasMatchedBranchHitBehavior: boolean = false;
                var defaultBranchHitBehavior: any = null;
                if (modInfo && modInfo.stats && modInfo.stats.useSwitch && modInfo.stats.useSwitch.useCases) {
                    var useCases: any[] = projectedMod(ctx, modName).useCases;
                    var useSwitchHints: any[] = [];
                    for (var ucIdx: number = 0; as2Less(ucIdx, useCases.length); ucIdx++) {
                        var useCase: any = useCases[ucIdx];
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
                        var effects: any[] = [];
                        if (useCase.multiplier) {
                            for (var mKey of as2Keys(useCase.multiplier)) {
                                if (isInternalKey(mKey))
                                    continue;
                                var mVal: number = as2Number(useCase.multiplier[mKey]);
                                if (!as2IsNaN(mVal) && as2NotEqual(mVal, 0)) {
                                    var displayText: string;
                                    if (as2Less(mVal, 0)) {
                                        var multValue: number = 1 + mVal;
                                        var dispValue: number = Math.round(multValue * 100) / 100;
                                        displayText = TooltipConstants.TAG_MULTIPLIER_ZONE + "×" + dispValue;
                                    }
                                    else {
                                        var mPercent: number = Math.round(mVal * 100);
                                        displayText = TooltipConstants.TAG_MULTIPLIER_ZONE + "×+" + mPercent + "%";
                                    }
                                    effects.push(displayText);
                                    break;
                                }
                            }
                        }
                        if (as2Equal(effects.length, 0) && useCase.percentage) {
                            for (var pKey of as2Keys(useCase.percentage)) {
                                if (isInternalKey(pKey))
                                    continue;
                                var pVal: number = as2Number(useCase.percentage[pKey]);
                                if (!as2IsNaN(pVal) && as2NotEqual(pVal, 0)) {
                                    var pPercent: number = Math.round(pVal * 100);
                                    var sign: string = as2Greater(pPercent, 0) ? "+" : "";
                                    var pLabel: string = TooltipConstants.PROPERTY_DICT[pKey] || pKey;
                                    effects.push(pLabel + sign + pPercent + "%");
                                    break;
                                }
                            }
                        }
                        var branchHitBehavior: any = (useCase.override && useCase.override.hitBehavior)
                            ? useCase.override.hitBehavior
                            : ((useCase.merge && useCase.merge.hitBehavior) ? useCase.merge.hitBehavior : null);
                        if (branchHitBehavior) {
                            hasMatchedBranchHitBehavior = true;
                            var hitBehaviorSummary: string = UseSwitchStatsBuilder.buildHitBehaviorSummary(ctx, branchHitBehavior);
                            if (as2Greater(hitBehaviorSummary.length, 0)) {
                                effects.push(hitBehaviorSummary);
                            }
                        }
                        if (as2Greater(effects.length, 0)) {
                            var useName: string = UseSwitchStatsBuilder.getUseCaseDisplayName(ctx, useCase.name);
                            useSwitchHints.push(TooltipConstants.TIP_FOR + useName + ":" + effects.join(","));
                        }
                    }
                    if (as2Greater(useSwitchHints.length, 0)) {
                        overrideEffectParts.push(" <font color='" + TooltipConstants.COL_USE_SWITCH + "'>[" + useSwitchHints.join("; ") + "]</font>");
                    }
                }
                if (!hasMatchedBranchHitBehavior && modInfo && modInfo.stats) {
                    var baseHitBehavior: any = defaultBranchHitBehavior;
                    if (!baseHitBehavior) {
                        baseHitBehavior = (modInfo.stats.override && modInfo.stats.override.hitBehavior)
                            ? modInfo.stats.override.hitBehavior
                            : ((modInfo.stats.merge && modInfo.stats.merge.hitBehavior) ? modInfo.stats.merge.hitBehavior : null);
                    }
                    if (baseHitBehavior) {
                        var baseHitBehaviorSummary: string = UseSwitchStatsBuilder.buildHitBehaviorSummary(ctx, baseHitBehavior);
                        if (as2Greater(baseHitBehaviorSummary.length, 0)) {
                            overrideEffectParts.push(" <font color='" + TooltipConstants.COL_USE_SWITCH + "'>[" + baseHitBehaviorSummary + "]</font>");
                        }
                    }
                }
                if (modInfo && modInfo.stats && modInfo.stats.bulletSwitch && modInfo.stats.bulletSwitch.bulletCases) {
                    var matchedCases: any[] = projectedMod(ctx, modName).bulletCases;
                    if (matchedCases && as2Greater(matchedCases.length, 0)) {
                        var bsHints: any[] = [];
                        for (var bci: number = 0; as2Less(bci, matchedCases.length); bci++) {
                            var bCase: any = matchedCases[bci];
                            var bEffects: any[] = [];
                            if (bCase.override) {
                                for (var oKey of as2Keys(bCase.override)) {
                                    if (isInternalKey(oKey))
                                        continue;
                                    var oLabel: string = TooltipConstants.PROPERTY_DICT[oKey] || oKey;
                                    bEffects.push(oLabel + "→" + bCase.override[oKey]);
                                    break;
                                }
                            }
                            if (as2Equal(bEffects.length, 0) && bCase.percentage) {
                                for (var bpKey of as2Keys(bCase.percentage)) {
                                    if (isInternalKey(bpKey))
                                        continue;
                                    var bpVal: number = as2Number(bCase.percentage[bpKey]);
                                    if (!as2IsNaN(bpVal) && as2NotEqual(bpVal, 0)) {
                                        var bpPercent: number = Math.round(bpVal * 100);
                                        var bpSign: string = as2Greater(bpPercent, 0) ? "+" : "";
                                        var bpLabel: string = TooltipConstants.PROPERTY_DICT[bpKey] || bpKey;
                                        bEffects.push(bpLabel + bpSign + bpPercent + "%");
                                        break;
                                    }
                                }
                            }
                            if (as2Greater(bEffects.length, 0)) {
                                var bLabel: string;
                                if (bCase._isDefault || !bCase.name) {
                                    bLabel = TooltipConstants.TIP_DEFAULT_BRANCH;
                                }
                                else {
                                    var bNames: any[] = bCase.name.split(",");
                                    var bDisplayNames: any[] = [];
                                    for (var bni: number = 0; as2Less(bni, bNames.length); bni++) {
                                        var bTrimmed: string = bNames[bni];
                                        while (as2Equal(bTrimmed.charAt(0), " "))
                                            bTrimmed = bTrimmed.substr(1);
                                        while (as2Equal(bTrimmed.charAt(bTrimmed.length - 1), " "))
                                            bTrimmed = bTrimmed.substr(0, bTrimmed.length - 1);
                                        var bCnName: string = TooltipConstants.BULLET_TYPE_NAMES[bTrimmed];
                                        bDisplayNames.push(bCnName ? bCnName : bTrimmed);
                                    }
                                    bLabel = bDisplayNames.join("/");
                                }
                                bsHints.push(bLabel + ":" + bEffects.join(","));
                            }
                        }
                        if (as2Greater(bsHints.length, 0)) {
                            overrideEffectParts.push(" <font color='" + TooltipConstants.COL_BULLET_SWITCH + "'>[" + bsHints.join("; ") + "]</font>");
                        }
                    }
                }
                if (modInfo && modInfo.skillSwitch) {
                    var resolvedSkill: any = projectedMod(ctx, modName).skill;
                    if (resolvedSkill && resolvedSkill.skillname) {
                        overrideEffectParts.push(" <font color='" + TooltipConstants.COL_USE_SWITCH + "'>" + TooltipConstants.LBL_ACTIVE_SKILL + resolvedSkill.skillname + "</font>");
                    }
                }
                if (modInfo && modInfo.subweapon) {
                    var subweaponName: string = modInfo.subweapon.name ? modInfo.subweapon.name : modName;
                    overrideEffectParts.push(" <font color='" + TooltipConstants.COL_USE_SWITCH + "'>" + TooltipConstants.LBL_SUBWEAPON + subweaponName + "</font>");
                }
                row.overrideParts = overrideEffectParts;
                rows.push(row);
            }
            return { titleHtml: titleHtml, rows: rows };
        }
    }
}
