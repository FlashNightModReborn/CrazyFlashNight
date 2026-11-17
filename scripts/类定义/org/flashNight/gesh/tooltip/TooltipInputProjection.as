import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.item.equipment.SubweaponDataUtil;
import org.flashNight.arki.item.equipment.TagManager;
import org.flashNight.arki.item.equipment.TierSystem;
import org.flashNight.arki.item.drug.DrugEffectNormalizer;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil;
import org.flashNight.gesh.tooltip.TooltipDataSelector;
import org.flashNight.gesh.string.StringUtils;

/**
 * TooltipInput v1 producer. AS2 owns instance calculation and discovery; Launcher
 * owns all tooltip wording and TooltipDocument generation. No callbacks or waits.
 *
 * One item only: no item/mod/recipe database crosses this hover boundary. The
 * calculated DTO is an allowlisted read of the real BaseItem.getData() result;
 * runtime matchers/normalizers remain in their existing domain implementations.
 */
class org.flashNight.gesh.tooltip.TooltipInputProjection {
    private static var _bladeCounts:Object = {};
    private static var CALCULATED_FIELDS:Array = [
        "description", "displayname", "icon", "use", "weapontype", "actiontype",
        "data", "skill", "subweapon", "lifecycle"
    ];
    private static var VALUE_FIELDS:Array = [
        "level", "tier", "mods", "count", "amount", "num", "stack", "quantity"
    ];
    private static var SKILL_FIELDS:Array = [
        "Name", "Type", "MaxLevel", "UnlockSP", "UpgradeSP", "CD", "MP",
        "UnlockLevel", "Description", "Equippable"
    ];
    private static var OBTAIN_FIELDS:Array = [
        "kind", "category", "price", "kprice", "npc", "type", "priceK",
        "dropType", "stageName", "enemyType", "carrierScope"
    ];

    public static function forItem(name:String, externalValue, baseItem:Object,
                                    presentation:String):Object {
        if (name == undefined || name == null || name == "") return null;
        var itemData:Object = ItemUtil.getItemData(name);
        if (itemData == undefined || itemData == null) return null;
        var equipment:Boolean = ItemUtil.isEquipment(name);
        var hasInstance:Boolean = baseItem != null && typeof baseItem == "object"
            && typeof baseItem.getData == "function" && typeof baseItem.value == "object";
        var value = hasInstance ? baseItem.value : externalValue;
        if (value == undefined || value == null) value = {level:1};
        var calculated:Object = hasInstance ? baseItem.getData() : null;
        // Failed authoritative calculation is not a base-catalog preview.
        if (hasInstance && (calculated === null || calculated === undefined)) return null;
        // The legacy stats path reads data for every non-drug item, including
        // materials such as battlefield medkits; equipment classification is separate.
        var baseline:Object = itemData.data && itemData.use != "药剂"
            ? TooltipDataSelector.getEquipmentData(itemData, value.tier) : null;
        var mods:Array = hasInstance && value.mods instanceof Array ? value.mods : null;
        var projection:Object = {
            isEquipment:equipment,
            isMaterial:ItemUtil.isMaterial(name),
            isInformation:ItemUtil.isInformation(name) === true,
            calculated:calculated == null ? null : select(calculated, CALCULATED_FIELDS),
            baselineData:copy(baseline, 0),
            mods:matchedMods(itemData, mods),
            tierOptions:[], drugEffects:[], subweapon:null,
            electric:false, isVerticalBullet:false, registeredModName:null,
            obtainRecords:obtainRecords(name)
        };
        if (equipment) {
            projection.tierOptions = copy(TierSystem.getAllTierOptionsByName(name), 0);
            var level = value.level ? value.level : 1;
            projection.levelMultiplier = copy(EquipmentUtil.levelStatList[level], 0);
            projection.isVerticalBullet = baseline.bullet
                ? BulletTypeUtil.isVertical(baseline.bullet) : false;
            var lightItem:Object = calculated != null ? calculated : itemData;
            var tags:Object = TagManager.buildPresentTagsDict(mods, lightItem, ModRegistry.getModDict());
            projection.electric = !!tags["电力"];
            if (itemData.use == "刀") {
                projection.bladeCount = baseline.bladeCount > 0
                    ? Number(baseline.bladeCount)
                    : bladeCount(baseline.dressup ? String(baseline.dressup) : null, itemData.icon);
            }
            var sub = calculated != null && calculated.subweapon !== undefined
                ? calculated.subweapon : itemData.subweapon;
            projection.subweapon = copy(SubweaponDataUtil.normalizeSubweapon(sub), 0);
        }
        if (projection.isMaterial) {
            var modData:Object = EquipmentUtil.modDict[name];
            if (!modData) modData = ModRegistry.getModDataByDisplayName(name);
            if (!modData) {
                var trimmed:String = StringUtils.trim(name);
                modData = EquipmentUtil.modDict[trimmed];
                if (!modData) modData = ModRegistry.getModDataByDisplayName(trimmed);
            }
            if (modData) projection.registeredModName = String(modData.name);
            if (modData && modData.subweapon) {
                projection.subweapon = copy(SubweaponDataUtil.normalizeSubweapon(modData.subweapon), 0);
            }
        }
        if (itemData.use == "药剂") {
            projection.drugEffects = copy(DrugEffectNormalizer.normalize(itemData.data), 0);
        }
        return {
            version:1, kind:"item", itemName:String(name),
            value:typeof value == "object" ? select(value, VALUE_FIELDS) : copy(value, 0),
            presentation:presentation == "native" || presentation == "inventory"
                ? presentation : "web",
            projection:projection
        };
    }

    /** Legacy-named Web entry still returns data synchronously; HTML comes from Host. */
    public static function preview(name:String):Object {
        var input:Object = forItem(name, {level:1}, null, "web");
        if (input == null) return null;
        var meta:Object = ItemUtil.getItemData(name);
        return {displayname:String(meta.displayname || name), itemData:meta,
            descHTML:"", introHTML:"", tooltipInput:input};
    }

    public static function loadoutSkill(index:Number):Object {
        var state:Array = _root.主角技能表[index];
        if (state == null) return null;
        var name:String = state[0];
        var meta:Object = _root.技能表对象[name];
        if (meta == null) return null;
        return {version:1, kind:"skill", mode:"loadout", skillName:name,
            skillData:select(meta, SKILL_FIELDS),
            state:{level:copy(state[1],0), equipped:state[2] == true, enabled:state[4] == true}};
    }

    public static function learningSkill(index:Number):Object {
        var meta:Object = _root.技能表[index];
        if (meta == null) return null;
        return {version:1, kind:"skill", mode:"learn", skillName:String(meta.Name),
            skillData:select(meta, SKILL_FIELDS)};
    }

    public static function body(html:String, profile:String):Object {
        return {version:1, kind:"body", html:html == null ? "" : String(html),
            profile:profile == "dense" ? "dense" : "simple"};
    }

    /** Only the existing matcher decides which installed-mod branches are active. */
    private static function matchedMods(item:Object, mods:Array):Object {
        var out:Object = {};
        if (mods == null || mods.length == 0) return out;
        var granted:Object = null;
        for (var i:Number = 0; i < mods.length; i++) {
            var info:Object = EquipmentUtil.modDict[mods[i]];
            if (info != null && info.grantsUseDict != null) {
                if (granted == null) granted = {};
                for (var useName:String in info.grantsUseDict) granted[useName] = true;
            }
        }
        var lookup:Object = ModRegistry.buildItemUseLookup(
            item.use ? item.use : "", item.weapontype ? item.weapontype : "", granted);
        var bullet:String = item.data.bullet ? item.data.bullet : "";
        for (i = 0; i < mods.length; i++) {
            var name:String = mods[i];
            if (!name) continue;
            info = EquipmentUtil.modDict[name];
            // Empty arrays/null explicitly mean no match; the TS engine never guesses.
            out[name] = {
                present:info != null,
                useCases:info == null ? [] : copy(ModRegistry.matchUseSwitchAll(info, lookup), 0),
                bulletCases:info == null ? [] : copy(ModRegistry.matchBulletSwitchAll(info, bullet), 0),
                skill:info == null ? null : copy(ModRegistry.resolveSkillForUse(info, lookup), 0)
            };
        }
        return out;
    }

    /** The discovered-source set is save-dependent, not a static catalog. */
    private static function obtainRecords(name:String):Array {
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        if (!index.isIndexBuilt()) return [];
        var records:Array = index.getObtainRecords(name);
        var out:Array = [];
        for (var i:Number = 0; i < records.length; i++) {
            var record:Object = select(records[i], OBTAIN_FIELDS);
            if (record.enemyType != undefined) {
                var props:Object = _root.敌人属性表 == null ? null : _root.敌人属性表[record.enemyType];
                record.enemyDisplayName = props != null && props.displayname
                    ? String(props.displayname) : String(record.enemyType);
            }
            out.push(record);
        }
        return out;
    }

    private static function select(source:Object, fields:Array):Object {
        var out:Object = {};
        for (var i:Number = 0; i < fields.length; i++) {
            var key:String = fields[i];
            if (source[key] !== undefined) out[key] = copy(source[key], 0);
        }
        return out;
    }

    /** Data only; internal cache/prototype links never reach the wire. */
    private static function copy(value, depth:Number) {
        var type:String = typeof value;
        if (type == "number") {
            if (isFinite(value)) return value;
            return {__tooltipNumber:isNaN(value) ? "NaN" : (value > 0 ? "Infinity" : "-Infinity")};
        }
        if (value === null || type == "string" || type == "boolean") return value;
        if (type != "object") return undefined;
        if (depth > 16) throw "tooltip_projection_depth";
        if (value instanceof Array) {
            var array:Array = [];
            for (var i:Number = 0; i < value.length; i++) {
                array.push(value[i] === undefined ? {__tooltipUndefined:true} : copy(value[i], depth + 1));
            }
            return array;
        }
        var out:Object = {};
        for (var key:String in value) {
            if (!value.hasOwnProperty(key) || key == "_parent" || key == "_root" || key == "_level0"
                || key == "constructor" || key == "prototype") continue;
            // __modName is real lifecycle ownership data used by the lighting formatter.
            if (key.substr(0, 2) == "__" && key != "__modName") continue;
            var child = copy(value[key], depth + 1);
            if (child !== undefined) out[key] = child;
        }
        return out;
    }

    /** Flash-only exception: preserve the original bounded linkage probe, no text. */
    private static function bladeCount(dressup:String, icon:String):Number {
        if (!dressup && !icon) return 0;
        var key:String = dressup ? "dressup:" + dressup : "icon:" + icon;
        if (_bladeCounts[key] !== undefined) return _bladeCounts[key];
        var count:Number = dressup ? probeBlade(dressup) : 0;
        if (!(count > 0) && icon) count = probeBlade("刀-" + icon);
        _bladeCounts[key] = count;
        return count;
    }

    private static function probeBlade(linkage:String):Number {
        var container:MovieClip = _root._tooltipTempContainer;
        if (!container) {
            container = _root.createEmptyMovieClip("_tooltipTempContainer", 99999);
            container._visible = false;
        }
        if (container.tempBlade) container.tempBlade.removeMovieClip();
        var blade:MovieClip = container.attachMovie(linkage, "tempBlade", container.getNextHighestDepth());
        if (!blade) return 0;
        var count:Number = searchBlade(blade, 4);
        blade.removeMovieClip();
        return count;
    }

    private static function searchBlade(clip:MovieClip, depth:Number):Number {
        if (!clip || depth <= 0) return 0;
        var best:Number = 0;
        if (clip["刀口位置1"] != undefined) {
            for (var i:Number = 1; i <= 6; i++) {
                if (clip["刀口位置" + i] == undefined) break;
                best++;
            }
            if (best == 6) return best;
        }
        for (var childName:String in clip) {
            var child = clip[childName];
            if (child instanceof MovieClip && child._parent == clip) {
                var count:Number = searchBlade(child, depth - 1);
                if (count > best) best = count;
                if (best == 6) return best;
            }
        }
        return best;
    }
}
