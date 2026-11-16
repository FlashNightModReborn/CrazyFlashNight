// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/TooltipComposer.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace TooltipComposer {
        export function generateItemDescriptionText(ctx: Context, item?: any, baseItem?: Instance): string {
            return generateItemDescriptionTextEx(ctx, item, baseItem, null);
        }
        export function generateItemDescriptionTextEx(ctx: Context, item?: any, baseItem?: Instance, subBlocks?: any[], docSubs?: any[]): string {
            var buffer: any[] = [];
            var itemName: any = item.name;
            var nightVisionBuffer: any[] = (as2NotEqual(subBlocks, null) && isEquipment(ctx, itemName)) ? [] : null;
            append(ctx, buffer, TooltipTextBuilder.buildBasicDescription(ctx, item, baseItem, nightVisionBuffer));
            if (isInformation(ctx, itemName)) {
                append(ctx, buffer, TooltipTextBuilder.buildStoryTip(ctx, item));
                append(ctx, buffer, TooltipTextBuilder.buildSynthesisMaterials(ctx, item));
            }
            else if (isMaterial(ctx, itemName)) {
                var modEntry: any = TooltipTextBuilder.buildModStatWithRows(ctx, itemName);
                if (as2NotEqual(modEntry, null))
                    pushSub(ctx, buffer, subBlocks, docSubs, [modEntry.html], modEntry);
            }
            else if (isEquipment(ctx, itemName)) {
                append(ctx, buffer, TooltipTextBuilder.buildBladeSkillMultipliers(ctx, item, baseItem));
                var skillToDisplay: any = item.skill;
                var subweaponToDisplay: any = item.subweapon;
                var lightingItem: any = item;
                var lightingMods: any[] = null;
                if (baseItem && as2NotEqual(baseItem.getData, undefined)) {
                    var calculatedData: any = baseItem.getData();
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
                    ? TooltipTextBuilder.buildSubweaponInfo(ctx, subweaponToDisplay)
                    : TooltipTextBuilder.buildSkillInfo(ctx, skillToDisplay));
                if (baseItem) {
                    var modsBuffer: any[] = [];
                    var modsEntry: any = ModsBlockBuilder.buildWithRows(ctx, modsBuffer, baseItem, item, baseItem.value);
                    pushSub(ctx, buffer, subBlocks, docSubs, modsBuffer, modsEntry);
                }
                pushSub(ctx, buffer, subBlocks, docSubs, nightVisionBuffer);
                var featBuffer: any[] = [];
                append(ctx, featBuffer, TooltipTextBuilder.buildLifecycleInfo(ctx, item.lifecyle));
                append(ctx, featBuffer, EquipmentLightingInfoBuilder.build(ctx, lightingItem, lightingMods, false));
                pushSub(ctx, buffer, subBlocks, docSubs, featBuffer);
                append(ctx, buffer, TooltipTextBuilder.buildUpgradePath(ctx, item, baseItem));
            }
            var obtainBuffer: any[] = [];
            var obtainEntry: any = ObtainMethodsBuilder.buildWithRows(ctx, obtainBuffer, itemName);
            pushSub(ctx, buffer, subBlocks, docSubs, obtainBuffer, obtainEntry);
            return buffer.join("");
        }
        function pushSub(ctx: Context, buffer?: any[], subBlocks?: any[], docSubs?: any[], block?: any[], docEntry?: any): void {
            if (as2Equal(block, null) || as2Equal(block.length, 0))
                return;
            var html: string = block.join("");
            if (as2NotEqual(subBlocks, null)) {
                subBlocks.push(html);
                if (as2NotEqual(docSubs, null))
                    docSubs.push(as2NotEqual(docEntry, null) ? docEntry : html);
                return;
            }
            append(ctx, buffer, block);
        }
        export function getUpgradePathInfo(ctx: Context, item?: any, baseItem?: Instance): any {
            if (as2Equal(item, null) || !isEquipment(ctx, item.name))
                return null;
            return TooltipTextBuilder.buildUpgradePathWithRows(ctx, item, baseItem);
        }
        export function getRailText(ctx: Context, item?: any, baseItem?: Instance): any[] {
            if (as2Equal(item, null))
                return null;
            var actionEquipment: boolean = (as2Equal(item.use, "刀") || as2Equal(item.use, "手部装备"));
            if (as2NotEqual(String(item.type), "武器") && !actionEquipment)
                return null;
            var top: any = item.use;
            var bottom: any = actionEquipment ? item.actiontype : item.weapontype;
            if (as2NotEqual(baseItem, null) && as2NotEqual(baseItem.getData, undefined)) {
                var calc: any = baseItem.getData();
                if (as2NotEqual(calc, null)) {
                    if (calc.use !== undefined && as2NotEqual(calc.use, ""))
                        top = calc.use;
                    if (actionEquipment && calc.actiontype !== undefined && as2NotEqual(calc.actiontype, "")) {
                        bottom = calc.actiontype;
                    }
                    else if (!actionEquipment && calc.weapontype !== undefined && as2NotEqual(calc.weapontype, "")) {
                        bottom = calc.weapontype;
                    }
                }
            }
            if (actionEquipment && (as2Equal(bottom, null) || as2Equal(bottom, "")))
                bottom = "默认";
            var rail: any[] = [];
            if (as2NotEqual(top, null) && as2NotEqual(top, ""))
                rail.push(String(top));
            if (as2NotEqual(bottom, null) && as2NotEqual(bottom, "")) {
                var bottomText: string = String(bottom);
                if (as2Equal(rail.length, 0) || as2NotEqual(rail[0], bottomText))
                    rail.push(bottomText);
            }
            return as2Greater(rail.length, 0) ? rail : null;
        }
        export function getMagazineInfo(ctx: Context, baseItem?: Instance, item?: any, externalValue?: any): any {
            if (as2Equal(item, null) || !ItemUseTypes.isGun(item.use))
                return null;
            var value: any = baseItem && baseItem.value ? baseItem.value : (externalValue ? externalValue : 1);
            var upgradeLevel: any = value.level ? value.level : 1;
            var data: any = ctx.projection.baselineData;
            if (as2Equal(data, null))
                return null;
            var clipName: any = data.clipname;
            if (as2NotEqual(baseItem, null) && as2NotEqual(baseItem.getData, undefined) && (as2Greater(upgradeLevel, 1) || value.mods)) {
                var equipData: any = baseItem.getData().data;
                if (as2NotEqual(equipData, null) && equipData.clipname !== undefined)
                    clipName = equipData.clipname;
            }
            if (as2Equal(clipName, null) || as2Equal(clipName, ""))
                return null;
            var clipData: any = lookupItem(ctx, clipName);
            if (as2Equal(clipData, null))
                return null;
            var displayName: any = clipData.displayname;
            if (as2Equal(displayName, undefined) || as2Equal(displayName, ""))
                displayName = clipName;
            var out: any = { name: String(displayName) };
            if (as2NotEqual(clipData.icon, undefined) && as2NotEqual(clipData.icon, ""))
                out.icon = String(clipData.icon);
            var baseBullet: string = data.bulletrename ? data.bulletrename : data.bullet;
            var finalBullet: string = baseBullet;
            if (as2NotEqual(baseItem, null) && as2NotEqual(baseItem.getData, undefined) && (as2Greater(upgradeLevel, 1) || value.mods)) {
                var bulletData: any = baseItem.getData().data;
                if (as2NotEqual(bulletData, null) && bulletData.bullet) {
                    finalBullet = bulletData.bulletrename ? bulletData.bulletrename : bulletData.bullet;
                }
            }
            if (as2NotEqual(finalBullet, null) && as2NotEqual(finalBullet, ""))
                out.ammo = String(finalBullet);
            return out;
        }
        export function generateIntroPanelContent(ctx: Context, baseItem?: Instance, item?: any, value?: any, nativeOpt?: any): string {
            var buffer: any[] = [];
            append(ctx, buffer, TooltipTextBuilder.buildIntroHeader(ctx, baseItem, item, value, nativeOpt));
            append(ctx, buffer, TooltipTextBuilder.buildStats(ctx, baseItem, item, value, nativeOpt));
            if (item.type === "武器" || item.type === "防具") {
                append(ctx, buffer, TooltipTextBuilder.buildEquipmentTagInfo(ctx, item));
            }
            return buffer.join("");
        }
        function append(ctx: Context, destination?: any[], source?: any[]): void {
            if (as2Equal(source, null))
                return;
            var index: number = 0;
            var length: number = source.length;
            while (as2Less(index, length)) {
                destination.push(source[index]);
                index++;
            }
        }
    }
}
