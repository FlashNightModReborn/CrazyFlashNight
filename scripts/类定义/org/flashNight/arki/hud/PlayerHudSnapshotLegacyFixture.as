import org.flashNight.arki.hud.PlayerHudBuffProjection;
import org.flashNight.arki.hud.PlayerHudShieldProjection;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.skill.SkillResourceService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.DrugHudMutationService;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.gesh.tooltip.NativeTooltipBridge;
import org.flashNight.gesh.tooltip.NativeTooltipDocument;
import org.flashNight.arki.hud.PlayerHudShieldProjectionLegacyFixture;
/** Frozen 0c36a08a read paths, with independent mutable compatibility state. */
class org.flashNight.arki.hud.PlayerHudSnapshotLegacyFixture {

    public static var poiseDetailsEnabled:Boolean = false;
    public static var shieldDetailsEnabled:Boolean = false;
    public static var poiseVisualsEnabled:Boolean = false;
    public static var ammo:Array = ["", "", "", ""];
    public static var ammoMode:String = "";
    public static var primaryOwner:Object;
    public static var secondaryOwner:Object;
    public static var lastCombat:Object;
    public static var compat:Object = {玩家必要信息界面:{}};
    public static var modes:Array = ["手枪", "手枪2", "长枪", "兵器", "手雷", "空手", "双枪", "长枪副武器"];
    public static var drugRevision:Number = 0;
    public static var drugSignature:String = "";
    public static var drugItems:Array = [];
    public static var drugCounts:Array = [];
    public static function finiteValue(value):Number { var n:Number = Number(value); return (n - n) == 0 ? n : 0; }
    public static function text(value):String { return value == null ? "" : String(value); }
    public static function readVitals(unit:Object):Object {
        var shield:Object = unit.shield;
        var shieldReady:Boolean = typeof shield.getMaxCapacity == "function";
        var shieldCapacity:Number = shieldReady ? Number(shield.getCapacity()) : 0;
        var shieldMaximum:Number = shieldReady ? Number(shield.getMaxCapacity()) : 0;
        if (!isFinite(shieldCapacity) || !isFinite(shieldMaximum)) shieldReady = false;
        var shieldPresent:Boolean = shieldReady && shieldMaximum > 0;
        var result:Object = {hp:[finiteValue(unit.hp), finiteValue(unit.hp满血值)], mp:[finiteValue(unit.mp), finiteValue(unit.mp满血值)],
            shield:[shieldPresent ? finiteValue(shield.getCapacity()) : 0, shieldPresent ? finiteValue(shield.getMaxCapacity()) : 0],
            shieldPresent:shieldPresent, shieldReady:shieldReady, poise:finiteValue(unit.nonlinearMappingResilience),
            experience:[finiteValue(_root.经验值), finiteValue(_root.上次升级需要经验值), finiteValue(_root.升级需要经验值)],
            level:finiteValue(_root.等级), name:text(_root.角色名), sp:finiteValue(_root.技能点数),
            paused:!!_root.暂停, decorations:_root.__nativeHudDecorations !== false};
        if (poiseDetailsEnabled) result.poiseDetail = readPoiseDetail(unit);
        if (poiseVisualsEnabled) result.poiseVisual = {airborne:!!unit.浮空, rigid:!!(unit.刚体 || unit.man.刚体标签), down:!!unit.倒地};
        if (shieldDetailsEnabled) result.shieldDetail = PlayerHudShieldProjectionLegacyFixture.read(unit);
        return result;
    }
    public static function readPoiseDetail(unit:Object):Object {
        // Consume ImpactHandler's authoritative derived values. Never refresh gameplay
        // attributes, advance decay, or infer a threshold from the rounded HUD percent.
        var cap:Number = Number(unit.韧性上限);
        var boundary:Number = Number(unit.impactStaggerBoundary);
        var impact:Number = Number(unit.remainingImpactForce);
        if (!(cap > 0) || !isFinite(cap) || !isFinite(boundary) || boundary < 0 || !isFinite(impact) || impact < 0)
            return {threshold:0, hasStaggerBand:false, phase:"unavailable"};
        var threshold:Number = Math.max(0, Math.min(1, 1 - Math.sqrt(boundary / cap)));
        var phase:String = unit.浮空 ? "air" : unit.倒地 ? "down" :
            (unit.刚体 || unit.man.刚体标签) ? "rigid" : impact > cap ? "break" :
            impact > boundary ? "stagger" : "buffer";
        return {threshold:threshold, hasStaggerBand:boundary < cap, phase:phase};
    }
    public static function readCombat(unit:Object):Object {
        var mode:String = text(unit.攻击模式);
        var skill:Object = unit.主动战技[unit.攻击模式];
        // 同一特殊槽按装备阶段切换时，就绪的普通战技仍需显示 F 与冷却。
        if (mode == "长枪" && LongGunSubWeaponCore.hasSubweapon(unit)
                && (skill == null || skill.isSubweaponControl === true)) mode = "长枪副武器";
        var valid:Boolean = false;
        for (var i:Number = 0; i < modes.length; i++) if (modes[i] == mode) valid = true;
        if (!valid) return lastCombat != null ? lastCombat : {mode:"", ammo:["", "", "", ""],
            weapon:{visible:false, name:"", mp:0, cooldownMs:0, key:keyLabel("武器技能键")}};
        compat.玩家必要信息界面.mode = mode;
        synchronizeAmmoOwners(unit);
        lastCombat = {mode:mode, ammo:[text(ammo[0]), text(ammo[1]), text(ammo[2]), text(ammo[3])],
            weapon:{visible:skill != null && skill.isSubweaponControl !== true,
            name:weaponName(skill), mp:finiteValue(skill.消耗mp), cooldownMs:finiteValue(skill.冷却时间),
            key:keyLabel("武器技能键")}};
        return lastCombat;
    }
    public static function synchronizeAmmoOwners(unit:Object):Void {
        var mode:String = text(unit.攻击模式);
        var primary:Object = mode == "双枪" ? unit.手枪 : unit[mode];
        var secondary:Object = mode == "双枪" ? unit.手枪2 : (mode == "长枪" ? unit.长枪副武器状态 : null);
        if (mode != ammoMode || primary !== primaryOwner) {
            ammo[0] = ammo[1] = ammo[2] = ammo[3] = "";
        } else if (secondary !== secondaryOwner) {
            ammo[2] = ammo[3] = "";
        }
        ammoMode = mode; primaryOwner = primary; secondaryOwner = secondary;
    }
    public static function weaponName(skill:Object):String {
        return text(skill.名字 != undefined ? skill.名字 : skill.名称);
    }
    public static function keyLabel(name:String):String {
        var code:Number = Number(_root[name]);
        return isFinite(code) && _root.keyshow != undefined ? text(_root.keyshow(code)) : "";
    }
    public static function readLoadout():Object {
        var skills:Object = SkillLoadoutService.getHudDescriptors();
        var bank:Number = DrugInputService.getActiveBank();
        var source:Object = _root.物品栏.药剂栏;
        var signature:String = String(bank);
        var changed:Boolean = false;
        var i:Number;
        for (i = 0; i < 8; i++) {
            var item:Object = source.getItem(String(i));
            var count:Number = item == null ? 0 : finiteValue(item.value);
            if (drugItems[i] !== item || drugCounts[i] != count) changed = true;
            drugItems[i] = item;
            drugCounts[i] = count;
            signature += ";" + text(item.name) + ":" + count;
        }
        if (changed || signature !== drugSignature) { drugSignature = signature; drugRevision++; }
        var drugs:Array = [];
        for (i = 0; i < 4; i++) {
            var slot:Number = bank * 4 + i;
            var current:Object = drugItems[slot];
            var data:Object = current == null ? null : ItemUtil.getItemData(current.name);
            drugs.push({slot:slot, name:text(current.name), icon:text(data.icon), count:drugCounts[slot],
                key:keyLabel(DrugInputService.getKeyName(i))});
        }
        return {revision:finiteValue(skills.revision), skills:skills.slots, drugRevision:drugRevision,
            bank:bank, drugs:drugs, switchKey:keyLabel(DrugInputService.getSwitchKeyName())};
    }
}
