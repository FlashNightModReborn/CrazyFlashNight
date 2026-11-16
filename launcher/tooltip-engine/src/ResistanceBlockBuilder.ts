// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/ResistanceBlockBuilder.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace ResistanceBlockBuilder {
        export function build(ctx: Context, result?: any[], baseItem?: Instance, item?: any, data?: any, equipData?: any): void {
            var finalData: any = equipData ? equipData : data;
            if (!finalData.magicdefence && !data.magicdefence) {
                return;
            }
            var resistanceTypes: any = {};
            if (data.magicdefence) {
                for (var key of as2Keys(data.magicdefence)) {
                    if (isInternalKey(key))
                        continue;
                    resistanceTypes[key] = true;
                }
            }
            if (finalData.magicdefence) {
                for (var key of as2Keys(finalData.magicdefence)) {
                    if (isInternalKey(key))
                        continue;
                    resistanceTypes[key] = true;
                }
            }
            for (var key of as2Keys(resistanceTypes)) {
                var baseResist: any = (data.magicdefence && data.magicdefence[key]) ? data.magicdefence[key] : null;
                var finalResist: any = (finalData.magicdefence && finalData.magicdefence[key]) ? finalData.magicdefence[key] : null;
                if ((as2Equal(baseResist, null) || as2Equal(as2Number(baseResist), 0)) && (as2Equal(finalResist, null) || as2Equal(as2Number(finalResist), 0)))
                    continue;
                var displayName: string = (as2Equal(key, TooltipConstants.TXT_BASE) ? TooltipConstants.TXT_ENERGY : key);
                var label: string = displayName + TooltipConstants.SUF_RESISTANCE;
                if (!equipData || as2Equal(finalResist, baseResist) || as2Equal(finalResist, null)) {
                    if (as2NotEqual(baseResist, null) && as2NotEqual(as2Number(baseResist), 0)) {
                        result.push(label, "：", baseResist, "<BR>");
                    }
                }
                else {
                    if (as2NotEqual(finalResist, null) && as2NotEqual(as2Number(finalResist), 0)) {
                        result.push(label, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalResist, "</FONT>");
                        if (as2Equal(baseResist, null))
                            baseResist = 0;
                        var baseNum: number = as2Number(baseResist);
                        var finalNum: number = as2Number(finalResist);
                        if (as2IsNaN(finalNum) || as2IsNaN(baseNum)) {
                            result.push(" (覆盖", baseResist, ")<BR>");
                        }
                        else {
                            var enhance: number = finalNum - baseNum;
                            var sign: string;
                            if (as2Less(enhance, 0)) {
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
    }
}
