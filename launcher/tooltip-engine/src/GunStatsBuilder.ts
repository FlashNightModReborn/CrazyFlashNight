// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/GunStatsBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace GunStatsBuilder {
        export function build(ctx: Context, result?: any[], baseItem?: Instance, item?: any, data?: any, equipData?: any, nativeOpt?: any): void {
            if (data.clipname && !(as2NotEqual(nativeOpt, null) && nativeOpt.omitClipName === true)) {
                result.push(TooltipConstants.LBL_CLIP_NAME, "：", lookupItem(ctx, data.clipname)?.displayname, "<BR>");
            }
            var baseSingleShoot: boolean = (as2Equal(data.singleshoot, true) || as2Equal(data.singleshoot, "true"));
            var finalSingleShoot: boolean = baseSingleShoot;
            if (equipData && as2NotEqual(equipData.singleshoot, undefined)) {
                finalSingleShoot = (as2Equal(equipData.singleshoot, true) || as2Equal(equipData.singleshoot, "true"));
            }
            var baseFireMode: string = baseSingleShoot ? TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipConstants.TIP_FIRE_MODE_AUTO;
            var finalFireMode: string = finalSingleShoot ? TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipConstants.TIP_FIRE_MODE_AUTO;
            if (baseSingleShoot || (equipData && as2NotEqual(equipData.singleshoot, undefined) && as2NotEqual(finalSingleShoot, baseSingleShoot))) {
                if (equipData && as2NotEqual(finalSingleShoot, baseSingleShoot)) {
                    result.push(TooltipConstants.LBL_FIRE_MODE, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalFireMode, "</FONT> (←", baseFireMode, ")<BR>");
                }
                else {
                    result.push(TooltipConstants.LBL_FIRE_MODE, "：", finalFireMode, "<BR>");
                }
            }
            var baseReloadType: string = data.reloadType ? data.reloadType : "";
            var finalReloadType: string = baseReloadType;
            if (equipData && as2NotEqual(equipData.reloadType, undefined)) {
                finalReloadType = equipData.reloadType;
            }
            var baseReloadDisplay: string = (as2Equal(baseReloadType, "tube")) ? TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipConstants.TIP_RELOAD_TYPE_MAG;
            var finalReloadDisplay: string = (as2Equal(finalReloadType, "tube")) ? TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipConstants.TIP_RELOAD_TYPE_MAG;
            var baseIsTube: boolean = (as2Equal(baseReloadType, "tube"));
            if (baseIsTube || (equipData && as2NotEqual(equipData.reloadType, undefined) && as2NotEqual(finalReloadType, baseReloadType))) {
                if (equipData && as2NotEqual(finalReloadType, baseReloadType)) {
                    result.push(TooltipConstants.LBL_RELOAD_TYPE, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalReloadDisplay, "</FONT> (←", baseReloadDisplay, ")<BR>");
                }
                else {
                    result.push(TooltipConstants.LBL_RELOAD_TYPE, "：", finalReloadDisplay, "<BR>");
                }
            }
            var baseBullet: string = data.bulletrename ? data.bulletrename : data.bullet;
            var finalBullet: string = (equipData && equipData.bullet)
                ? (equipData.bulletrename ? equipData.bulletrename : equipData.bullet)
                : baseBullet;
            if (finalBullet && !(as2NotEqual(nativeOpt, null) && nativeOpt.omitBulletType === true)) {
                if (equipData && as2NotEqual(finalBullet, baseBullet)) {
                    result.push(TooltipConstants.LBL_BULLET_TYPE, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalBullet, "</FONT> (←", baseBullet, ")<BR>");
                }
                else {
                    result.push(TooltipConstants.LBL_BULLET_TYPE, "：", finalBullet, "<BR>");
                }
            }
            var isNotMultiShot: boolean = (data.bullet && ctx.projection.isVerticalBullet === true);
            var baseSplit: number = as2Number(data.split);
            if (as2IsNaN(baseSplit) || as2LessEqual(baseSplit, 1)) {
                baseSplit = 1;
            }
            var splitValue: number = baseSplit;
            if (equipData && as2NotEqual(equipData.split, undefined)) {
                var eqSplit: number = as2Number(equipData.split);
                if (!as2IsNaN(eqSplit) && as2GreaterEqual(eqSplit, 1)) {
                    splitValue = eqSplit;
                }
            }
            var capacity: number = as2Number(data.capacity);
            if (as2IsNaN(capacity)) {
                capacity = 0;
            }
            var magazineCapacity: number = isNotMultiShot ? splitValue : 1;
            if (as2Greater(capacity, 0)) {
                var ammoSuffix: string = WeaponAmmoInfoBuilder.capacitySuffix(ctx, equipData ? equipData : data);
                if (as2Greater(magazineCapacity, 1)) {
                    var baseCap: number = as2Number(data.capacity);
                    var finalCap: number = equipData ? as2Number(equipData.capacity) : baseCap;
                    if (as2IsNaN(baseCap))
                        baseCap = 0;
                    if (as2IsNaN(finalCap))
                        finalCap = baseCap;
                    var baseScaled: number = baseCap * magazineCapacity;
                    var finalScaled: number = finalCap * magazineCapacity;
                    var deltaBase: number = finalCap - baseCap;
                    if (as2NotEqual(deltaBase, 0) && equipData) {
                        result.push(TooltipConstants.LBL_CAPACITY, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalScaled, "</FONT>", ammoSuffix, " (", baseScaled, " + ", deltaBase, "×", magazineCapacity, ")<BR>");
                    }
                    else {
                        result.push(TooltipConstants.LBL_CAPACITY, "：", finalScaled, ammoSuffix, "<BR>");
                    }
                }
                else {
                    TooltipFormatter.upgradeLine(result, data, equipData, "capacity", TooltipConstants.LBL_CAPACITY, null, ammoSuffix);
                }
            }
            TooltipFormatter.upgradeLine(result, data, equipData, "power", TooltipConstants.LBL_BULLET_POWER, null);
            if (as2Greater(splitValue, 1) || as2Greater(baseSplit, 1)) {
                var splitLabel: string = isNotMultiShot ? TooltipConstants.LBL_BURST_COUNT : TooltipConstants.LBL_PELLET_COUNT;
                if (equipData && as2NotEqual(splitValue, baseSplit)) {
                    result.push(splitLabel, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", splitValue, "</FONT> (←", baseSplit, ")<BR>");
                }
                else {
                    result.push(splitLabel, "：", splitValue, "<BR>");
                }
            }
            var baseInterval: number = as2Number(data.interval);
            var finalInterval: number = (equipData && equipData.interval) ? as2Number(equipData.interval) : baseInterval;
            if (!as2IsNaN(finalInterval) && as2Greater(finalInterval, 0)) {
                var finalRate: number = Math.floor(10000 / finalInterval) * magazineCapacity / 10;
                if (equipData && !as2IsNaN(baseInterval) && as2Greater(baseInterval, 0) && as2NotEqual(finalInterval, baseInterval)) {
                    var baseRate: number = Math.floor(10000 / baseInterval) * magazineCapacity / 10;
                    var rateDelta: number = Math.round((finalRate - baseRate) * 10) / 10;
                    var sign: string = as2GreaterEqual(rateDelta, 0) ? " + " : " - ";
                    if (as2Less(rateDelta, 0))
                        rateDelta = -rateDelta;
                    result.push(TooltipConstants.LBL_FIRE_RATE, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalRate, "</FONT> (", baseRate, sign, rateDelta, ")", TooltipConstants.SUF_FIRE_RATE, "<BR>");
                }
                else {
                    result.push(TooltipConstants.LBL_FIRE_RATE, "：", finalRate, TooltipConstants.SUF_FIRE_RATE, "<BR>");
                }
            }
            var baseImpact: number = as2Number(data.impact);
            var finalImpact: number = (equipData && as2NotEqual(equipData.impact, undefined)) ? as2Number(equipData.impact) : baseImpact;
            if (!as2IsNaN(finalImpact) && as2Greater(finalImpact, 0)) {
                var finalImpactDisplay: number = Math.floor(500 / finalImpact);
                if (equipData && !as2IsNaN(baseImpact) && as2Greater(baseImpact, 0) && as2NotEqual(finalImpact, baseImpact)) {
                    var baseImpactDisplay: number = Math.floor(500 / baseImpact);
                    result.push(TooltipConstants.LBL_IMPACT, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalImpactDisplay, "</FONT> (←", baseImpactDisplay, ")<BR>");
                }
                else {
                    result.push(TooltipConstants.LBL_IMPACT, "：", finalImpactDisplay, "<BR>");
                }
            }
            var baseReloadPenalty: number = as2Number(data.reloadPenalty);
            var finalReloadPenalty: number = (equipData && as2NotEqual(equipData.reloadPenalty, undefined))
                ? as2Number(equipData.reloadPenalty) : baseReloadPenalty;
            if (as2IsNaN(baseReloadPenalty))
                baseReloadPenalty = 0;
            if (as2IsNaN(finalReloadPenalty))
                finalReloadPenalty = baseReloadPenalty;
            if (as2NotEqual(finalReloadPenalty, 0) || (equipData && as2NotEqual(finalReloadPenalty, baseReloadPenalty))) {
                if (as2Greater(finalReloadPenalty, 0)) {
                    if (equipData && as2NotEqual(finalReloadPenalty, baseReloadPenalty)) {
                        var delayDelta: number = finalReloadPenalty - baseReloadPenalty;
                        var delaySign: string = as2GreaterEqual(delayDelta, 0) ? " + " : " - ";
                        if (as2Less(delayDelta, 0))
                            delayDelta = -delayDelta;
                        result.push(TooltipConstants.LBL_RELOAD_PENALTY, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>+", finalReloadPenalty, "%</FONT> (+", baseReloadPenalty, "%", delaySign, delayDelta, "%)<BR>");
                    }
                    else {
                        result.push(TooltipConstants.LBL_RELOAD_PENALTY, "：+", finalReloadPenalty, "%<BR>");
                    }
                }
                else if (as2Less(finalReloadPenalty, 0)) {
                    if (equipData && as2NotEqual(finalReloadPenalty, baseReloadPenalty)) {
                        var bonusDelta: number = baseReloadPenalty - finalReloadPenalty;
                        result.push(TooltipConstants.LBL_RELOAD_BONUS, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", -finalReloadPenalty, "%</FONT> (", baseReloadPenalty, "% + ", bonusDelta, "%)<BR>");
                    }
                    else {
                        result.push(TooltipConstants.LBL_RELOAD_BONUS, "：", -finalReloadPenalty, "%<BR>");
                    }
                }
                else if (equipData && as2NotEqual(baseReloadPenalty, 0)) {
                    result.push(TooltipConstants.LBL_RELOAD_PENALTY, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>0%</FONT> (+", baseReloadPenalty, "% - ", baseReloadPenalty, "%)<BR>");
                }
            }
            TooltipFormatter.upgradeLine(result, data, equipData, "bulletsize", TooltipConstants.LBL_BULLET_SIZE, null);
            SilenceEffectBuilder.build(ctx, result, baseItem, item, data, equipData);
        }
    }
}
