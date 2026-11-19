/** Read-only transport contracts. Domain qualification/calculation remains in AS2. */
namespace TooltipEngine {
    export type Data = { [key: string]: any };
    export interface TooltipCatalog {
        version: 1;
        contentVersion: string;
        recipesUnavailable?: boolean;
        recipeTargets?: Data;
        items: Data;
        mods: Data;
        levelStatList: any;
        recipes: Data;
        recipesUsing: { [key: string]: string[] };
        enemyNames?: { [key: string]: string };
        magicDamageTypes: Data;
    }
    export interface ModProjection {
        present: boolean;
        useCases: Data[];
        bulletCases: Data[];
        skill?: Data;
    }
    export interface ItemProjection {
        calculated?: Data;
        displayName?: string;
        iconName?: string;
        registeredModName?: string;
        baselineData?: Data;
        isEquipment: boolean;
        isMaterial: boolean;
        isInformation: boolean;
        levelMultiplier?: number;
        bladeCount?: number;
        isVerticalBullet?: boolean;
        electric?: boolean;
        tierOptions: Data[];
        drugEffects: Data[];
        subweapon?: Data;
        mods: { [name: string]: ModProjection };
        /** Discovery-filtered AS2 source records; never replaced with a full static drop table. */
        obtainRecords: Data[];
    }
    export interface TooltipInput {
        version: 1;
        kind: 'item' | 'skill' | 'body' | 'hud';
        itemName?: string;
        value?: Data | number;
        projection?: ItemProjection;
        presentation?: 'native' | 'inventory' | 'web';
        output?: 'details';
        skillName?: string;
        skillData?: Data;
        state?: Data;
        mode?: string;
        resourceHint?: Data;
        hud?: Data;
        html?: string;
        profile?: string;
        [key: string]: any;
    }
    export interface TooltipDocument {
        version: 1;
        title?: string;
        icon?: { kind: string; name: string };
        profile: string;
        sections: Data[];
        layoutType?: string;
        rail?: string[];
        magazine?: Data;
    }
    export interface TooltipResult {
        document: TooltipDocument;
        descHTML: string;
        introHTML: string;
        details: string;
    }
    export interface Context {
        readonly input: TooltipInput;
        readonly catalog: TooltipCatalog;
        readonly projection: ItemProjection;
    }
    /** Data accessor only. It has no item construction, augmentation or business rules. */
    export interface Instance {
        name: string;
        value: any;
        getData(): Data;
    }
    export class InputError extends Error {
        readonly code: string;
        constructor(code: string) { super(code); this.name = 'TooltipInputError'; this.code = code; }
    }
    export function trim(value: any): string {
        return value == null ? '' : String(value).replace(/^[ \t\n\r]+|[ \t\n\r]+$/g, '');
    }
    export function isInternalKey(key: string): boolean { return key.substr(0, 2) === '__'; }
    export function lookupItem(ctx: Context, name: string): Data { return ctx.catalog.items[name]; }
    export function isEquipment(ctx: Context, name: string): boolean {
        if (name === ctx.input.itemName) return ctx.projection.isEquipment;
        const item = lookupItem(ctx, name);
        // Only a display label for crafting ingredients, never an equip/transaction decision.
        return !!item && (item.type === '武器' || item.type === '防具');
    }
    export function isMaterial(ctx: Context, name: string): boolean {
        return name === ctx.input.itemName && ctx.projection.isMaterial;
    }
    export function isInformation(ctx: Context, name: string): boolean {
        return name === ctx.input.itemName && ctx.projection.isInformation;
    }
    export function projectedMod(ctx: Context, name: string): ModProjection {
        const result = ctx.projection.mods[name];
        if (!result) throw new InputError('missing_mod_projection');
        return result;
    }
    export function lookupRecipe(ctx: Context, id: string): Data { return ctx.catalog.recipes[id]; }
    export function lookupRecipesUsing(ctx: Context, name: string): string[] {
        return ctx.catalog.recipesUsing[name] || [];
    }
    export function isMagicDamage(ctx: Context, value: string): boolean {
        return ctx.catalog.magicDamageTypes[value] === true;
    }
}
