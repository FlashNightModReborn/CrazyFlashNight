import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil;
import org.flashNight.arki.item.equipment.SubweaponDataUtil;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;

/**
 * 路径: org/flashNight/arki/unit/Action/Shoot/AmmoSupplyService.as
 *
 * AmmoSupplyService - 战场即时补给的弹药补满服务
 *
 * 设计契约：docs/战场即时补给品-技术调研与首批施工准备-2026-09-12.md §13。
 * 补给只增不减：仅 shot>0 的实例写 0 并记收益；shot<=0（满弹/GM6 合法超装）
 * 与 shot==undefined（未初始化满弹）一律跳过，不凭空造收益。
 *
 * scope 四值：
 *   longgun  装备栏长枪槽
 *   pistols  装备栏手枪+手枪2槽（空槽跳过，不读当前攻击模式）
 *   equipped 三槽并集
 *   all      三槽 + 随身背包枪械（不含仓库/暂存等其他容器）
 *
 * 返回 {rejected:String或null, changed:Number, details:Array}
 *   rejected: "invalid"(hero无效/死亡) / "reload"(换弹在途，整包零写) / "scope"(非法scope)
 *   changed:  实际发生补弹的实例数（主仓或副仓任一真实收益）
 *   details:  每把被补枪的最小信息 {name, slot, beforeShot}
 */
class org.flashNight.arki.unit.Action.Shoot.AmmoSupplyService {

    /**
     * 换弹在途判据（PickupEffectService 预检与本服务前置共用的唯一事实源）。
     * 对齐钛合金 readAmmo 的 man.换弹标签，并覆盖长枪副武器换弹请求在途。
     */
    public static function isReloadInProgress(hero:Object):Boolean {
        if (hero == null) return false;
        var man:Object = hero.man;
        if (man == null) return false;
        if (man.换弹标签) return true;
        if (LongGunSubWeaponCore.isSubweaponReloadRequest(man)) return true;
        return false;
    }

    public static function supply(hero:Object, scope:String):Object {
        var result:Object = {rejected: null, changed: 0, details: []};
        if (hero == null || !(hero.hp > 0)) {
            result.rejected = "invalid";
            return result;
        }
        if (isReloadInProgress(hero)) {
            result.rejected = "reload";
            return result;
        }

        var slotNames:Array;
        var includeBag:Boolean = false;
        switch (scope) {
            case "longgun":
                slotNames = ["长枪"];
                break;
            case "pistols":
                slotNames = ["手枪", "手枪2"];
                break;
            case "equipped":
                slotNames = ["长枪", "手枪", "手枪2"];
                break;
            case "all":
                slotNames = ["长枪", "手枪", "手枪2"];
                includeBag = true;
                break;
            default:
                result.rejected = "scope";
                return result;
        }

        // 真实对象引用去重：RuntimeEquipmentProjection 的 slot alias 让两个槽位持有同一
        // 实例（commitSlotAlias 物化为同一 sourceRef），不是额外一把枪；同名不同实例分别处理。
        var processed:Array = [];
        var changedSlots:Array = [];

        for (var i:Number = 0; i < slotNames.length; i++) {
            var slot:String = slotNames[i];
            var item:Object = hero[slot];
            if (item == null || typeof item != "object" || item.value == null || typeof item.value != "object") continue;
            if (containsRef(processed, item)) continue;
            processed.push(item);
            if (!isGun(item.name)) continue;
            if (supplyEquippedInstance(hero, item, slot, result)) changedSlots.push(slot);
        }

        if (includeBag) supplyBag(processed, result);

        if (changedSlots.length > 0) syncEquippedDisplay(hero, changedSlots);
        // 落脏一次，不逐枪完整存盘、不重建背包索引、不重建人物
        if (result.changed > 0 && _root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
        return result;
    }

    /**
     * 已装备槽单实例补弹。主仓按规则写 0；已装备长枪有副武器运行态时走
     * LongGunSubWeaponCore 现有免费补满入口（未满才计收益，含 groupPaid/镜像同步）。
     */
    private static function supplyEquippedInstance(hero:Object, item:Object, slot:String, result:Object):Boolean {
        var value:Object = item.value;
        var changedHere:Boolean = false;
        var beforeShot:Number = value.shot == undefined ? 0 : Number(value.shot);

        if (value.shot != undefined && Number(value.shot) > 0) {
            value.shot = 0;
            changedHere = true;
            // tube 实例（插件可动态附加，读实例权威属性）补后清逐发装填预算，
            // 与引擎 shot<=0 自清一致；非 tube 的战术回收池 reloadCount 一律不动
            var attrs:Object = hero[slot + "属性"];
            if (attrs != null && attrs.reloadType == "tube") value.reloadCount = 0;
            // 吉他喷火机枪形态持久镜像：只写 shot 不清镜像会被陈旧镜像撤销补给
            if (value.machineGunShot != undefined) value.machineGunShot = 0;
        }

        if (slot == "长枪" && LongGunSubWeaponCore.hasSubweapon(hero)) {
            if (LongGunSubWeaponCore.reloadLinkedFree(hero)) changedHere = true;
        }

        if (changedHere) {
            result.changed++;
            result.details.push({name: String(item.name), slot: slot, beforeShot: beforeShot});
        }
        return changedHere;
    }

    /**
     * 随身背包枪械补弹（scope=all）。非枪物品跳过；仓库/暂存等其他容器不触。
     * 背包枪无 unit 运行态，副武器只写镜像字段 subweaponShot/subweaponReloadCount。
     */
    private static function supplyBag(processed:Array, result:Object):Void {
        var inventory:Object = _root.物品栏 == undefined ? null : _root.物品栏.背包;
        if (inventory == null || typeof inventory.getIndexes != "function"
                || typeof inventory.getItem != "function") return;
        var indexes:Array = inventory.getIndexes();
        for (var i:Number = 0; i < indexes.length; i++) {
            var item:Object = inventory.getItem(String(indexes[i]));
            if (item == null || typeof item != "object" || item.value == null || typeof item.value != "object") continue;
            if (containsRef(processed, item)) continue;
            processed.push(item);
            if (!isGun(item.name)) continue;
            if (item.value.shot == undefined) continue;      // 未初始化满弹，不凭空造收益
            if (!(Number(item.value.shot) > 0)) continue;    // 满弹或 GM6 合法超装，只增不减

            var beforeShot:Number = Number(item.value.shot);
            item.value.shot = 0;
            var bagAttrs:Object = resolveInstanceAttrs(item);
            if (bagAttrs != null && bagAttrs.reloadType == "tube") item.value.reloadCount = 0;
            if (item.value.machineGunShot != undefined) item.value.machineGunShot = 0;
            var itemData:Object = _root.getItemData(item.name);
            if (SubweaponDataUtil.getSubweaponData(itemData) != null) {
                item.value.subweaponShot = 0;
                item.value.subweaponReloadCount = 0;
            }
            result.changed++;
            result.details.push({name: String(item.name), slot: "背包", beforeShot: beforeShot});
        }
    }

    /**
     * 已装备枪补弹后同步显示：复用 ReloadManager.updateAmmoDisplay（只写当前攻击模式
     * 的 HUD 字段）与 typed 5 参 updateBullet 发布；非当前装备形态对应字段不推送。
     */
    private static function syncEquippedDisplay(hero:Object, changedSlots:Array):Void {
        var mode:String = hero.攻击模式;
        if (mode != "长枪" && mode != "手枪" && mode != "双枪") return;
        ReloadManager.updateAmmoDisplay(hero.man, hero, _root);

        var dispatcher:Object = hero.dispatcher;
        if (dispatcher == null || typeof dispatcher.publish != "function") return;
        for (var i:Number = 0; i < changedSlots.length; i++) {
            var slot:String = changedSlots[i];
            var field:String = null;
            var state:String = "主手射击中";
            if (slot == "长枪" && mode == "长枪") {
                field = "子弹数";
            } else if (slot == "手枪" && (mode == "手枪" || mode == "双枪")) {
                field = "子弹数";
            } else if (slot == "手枪2" && mode == "双枪") {
                field = "子弹数_2";
                state = "副手射击中";
            }
            if (field == null) continue;
            var attrs:Object = hero[slot + "属性"];
            var capacity:Number = Number(hero[slot + "弹匣容量"]);
            var scale:Number = 1;
            if (attrs != null && BulletTypeUtil.isVertical(attrs.bullet)) scale = Number(attrs.split);
            var remaining:Number = scale * (capacity - Number(hero[slot].value.shot));
            dispatcher.publish("updateBullet", hero, state, remaining, field, slot);
        }
    }

    /** 枪械认定：以物品权威 use 判断（长枪/手枪），不按名称猜。 */
    private static function isGun(itemName:String):Boolean {
        if (itemName == null) return false;
        var itemData:Object = _root.getItemData(itemName);
        return itemData != null && (itemData.use == "长枪" || itemData.use == "手枪");
    }

    /**
     * 背包枪实例权威属性：真实 BaseItem 经 getData() 计算（含插件动态附加的
     * reloadType=tube）；非 BaseItem 形态退回物品静态 data。
     */
    private static function resolveInstanceAttrs(item:Object):Object {
        if (item != null && typeof item.getData == "function") {
            var data:Object = item.getData();
            if (data != null && data.data != null) return data.data;
        }
        var raw:Object = _root.getItemData(item.name);
        return raw == null ? null : raw.data;
    }

    private static function containsRef(list:Array, item:Object):Boolean {
        for (var i:Number = 0; i < list.length; i++) {
            if (list[i] === item) return true;
        }
        return false;
    }
}
