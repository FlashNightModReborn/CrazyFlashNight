// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/builder/EquipmentStatsComposer.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace EquipmentStatsComposer {
        export function compose(ctx: Context, baseItem?: Instance, item?: any, data?: any, equipData?: any, nativeOpt?: any): any[] {
            var result: any[] = [];
            TooltipFormatter.upgradeLine(result, data, equipData, "level", null, null);
            TooltipFormatter.upgradeLine(result, data, equipData, "weight", null, TooltipConstants.SUF_KG);
            switch (item.use) {
                case ItemUseTypes.MELEE:
                    MeleeStatsBuilder.build(ctx, result, baseItem, item, data, equipData);
                    break;
                case ItemUseTypes.GRENADE:
                    GrenadeStatsBuilder.build(ctx, result, baseItem, item, data, equipData);
                    break;
                case ItemUseTypes.RIFLE:
                case ItemUseTypes.PISTOL:
                    GunStatsBuilder.build(ctx, result, baseItem, item, data, equipData, nativeOpt);
                    break;
            }
            CommonStatsBuilder.build(ctx, result, baseItem, item, data, equipData, nativeOpt);
            CriticalBlockBuilder.build(ctx, critSlayTarget(ctx, nativeOpt, result), baseItem, item, data, equipData);
            DamageTypeBuilder.build(ctx, result, baseItem, item, data, equipData);
            ResistanceBlockBuilder.build(ctx, result, baseItem, item, data, equipData);
            return result;
        }
        function critSlayTarget(ctx: Context, nativeOpt?: any, result?: any[]): any[] {
            if (as2NotEqual(nativeOpt, null) && nativeOpt.omitCritSlay === true && as2NotEqual(nativeOpt.critSlay, null)) {
                return nativeOpt.critSlay;
            }
            return result;
        }
    }
}
