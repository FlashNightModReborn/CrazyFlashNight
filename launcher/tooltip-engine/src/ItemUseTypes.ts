// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/ItemUseTypes.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace ItemUseTypes {
        export const MELEE: string = "刀";
        export const PISTOL: string = "手枪";
        export const RIFLE: string = "长枪";
        export const GRENADE: string = "手雷";
        export const ARMOR: string = "防具";
        export const POTION: string = "药剂";
        export const SKILL: string = "技能";
        export const MATERIAL: string = "材料";
        export const INFORMATION: string = "情报";
        export const TYPE_WEAPON: string = "武器";
        export const TYPE_ARMOR: string = "防具";
        export const TYPE_SKILL: string = "技能";
        export const TYPE_CONSUMABLE: string = "消耗品";
        export function isGun(useType?: string): boolean {
            return as2Equal(useType, PISTOL) || as2Equal(useType, RIFLE);
        }
        export function isWeapon(useType?: string): boolean {
            return as2Equal(useType, MELEE) || as2Equal(useType, PISTOL) || as2Equal(useType, RIFLE) || as2Equal(useType, GRENADE);
        }
    }
}
