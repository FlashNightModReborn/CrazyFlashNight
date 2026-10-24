import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.hud.*;
import org.flashNight.neur.Event.*;

/** Production wristblade lifecycle through the read-only HUD projection. */
class org.flashNight.arki.hud.PlayerHudWristbladeTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] PlayerHudWristbladeTest: " + message); }
    }
    private static function row(rows:Array, id:String):Object {
        for (var i:Number = 0; i < rows.length; i++)
            if (rows[i].id.indexOf(":" + id) >= 0) return rows[i];
        return null;
    }
    private static function mod(row:Object, property:String):Object {
        if (row == null || row.mods == null) return null;
        for (var i:Number = 0; i < row.mods.length; i++)
            if (row.mods[i].property == property) return row.mods[i];
        return null;
    }
    private static function checkMod(row:Object, property:String, expected:Number, message:String):Void {
        var value:Object = mod(row, property);
        check(value != null && value.calc == "add" && value.value == expected, message);
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var previousRegistrar:Function = _root.装备生命周期函数.剑圣套装登记Buff;
        _root.装备生命周期函数.剑圣套装登记Buff = function(ref:Object, manager:Object, id:String):Boolean { return true; };
        var target:MovieClip = _root.createEmptyMovieClip("__wristbladeHudTest", _root.getNextHighestDepth());
        target.装备刀锋利度加成 = 200;
        target.空手攻击力 = 0;
        target.技能名 = "刀剑乱舞";
        target.dispatcher = new EventDispatcher();
        var manager:BuffManager = new BuffManager(target, null);
        target.buffManager = manager;
        var projection:PlayerHudBuffProjection = new PlayerHudBuffProjection();
        projection.setDetailsEnabled(true);
        projection.initialize(manager);
        var ref:Object = {自机:target, knifeConvertRate:0.5, baseRatio:0.3, burstRatio:0.7, burstDurationFrames:90};
        try {
            check(_root.装备生命周期函数.剑圣手甲初始化Buff系统(ref) === true, "production wristblade initialization succeeds");
            var initial:Array = projection.snapshot();
            check(initial.length == 2, "controller and effect remain separate raw rows");
            var controller:Object = row(initial, "剑圣腕刃控制器");
            var effect:Object = row(initial, "剑圣腕刃增强");
            check(controller != null && effect != null, "registration-time presentation is visible to the subscribed projection");
            check(controller.group != null && effect.group != null && controller.group.id == effect.group.id,
                "both rows share an explicit group");
            check(controller.group.primary === true && effect.group.primary === false, "controller is the stable primary");
            check(controller.info.name == "腕刃强化" && controller.activation.active === false &&
                controller.activation.total == 90 && controller.activation.remaining == 0, "idle activation uses real event duration");
            check(effect.mods.length == 1, "idle effect exposes the actual injected Pod");
            checkMod(effect, "空手攻击力", 30, "idle unarmed modifier is 30");
            var idleIncarnation:String = effect.incarnation;

            target.dispatcher.publish("WeaponSkill", "空手");
            var burst:Array = projection.snapshot();
            check(burst !== initial, "activation publishes a new immutable array");
            var burstController:Object = row(burst, "剑圣腕刃控制器");
            var burstEffect:Object = row(burst, "剑圣腕刃增强");
            check(burstController.activation.active === true && burstController.activation.remaining == 90 &&
                burstController.activation.activeLabel == "爆发中", "event activation and remaining frames reach the HUD");
            check(burstEffect.incarnation != idleIncarnation, "same external ID replacement advances the display incarnation");
            check(burstEffect.mods.length == 2, "burst exposes both actual injected corrections");
            checkMod(burstEffect, "空手攻击力", 100, "burst unarmed modifier is the full 100");
            checkMod(burstEffect, "装备刀锋利度加成", -70, "burst knife correction is -70");
            checkMod(effect, "空手攻击力", 30, "the previous idle snapshot is not overwritten");

            manager.update(30);
            var ticking:Array = projection.snapshot();
            check(row(ticking, "剑圣腕刃控制器").activation.remaining == 60, "the event clock advances through BuffManager");
            target.dispatcher.publish("WeaponSkill", "空手");
            var refreshed:Array = projection.snapshot();
            check(row(refreshed, "剑圣腕刃控制器").activation.remaining == 90, "retrigger refreshes the real activation timer");
            check(row(refreshed, "剑圣腕刃增强").incarnation == burstEffect.incarnation,
                "refresh does not manufacture a replacement effect");

            manager.update(90);
            var expired:Array = projection.snapshot();
            var expiredController:Object = row(expired, "剑圣腕刃控制器");
            var expiredEffect:Object = row(expired, "剑圣腕刃增强");
            check(expiredController != null && expiredController.activation.active === false &&
                expiredController.activation.remaining == 0, "expiry returns the controller to idle without killing it");
            checkMod(expiredEffect, "空手攻击力", 30, "expiry restores the base modifier");
            check(expiredEffect.mods.length == 1 && expiredEffect.incarnation != burstEffect.incarnation,
                "expiry replaces the effect without retaining burst corrections");
            target.dispatcher.publish("WeaponSkill", "空手");
            var repeated:Array = projection.snapshot();
            check(row(repeated, "剑圣腕刃控制器").activation.active === true &&
                row(repeated, "剑圣腕刃控制器").activation.remaining == 90, "the surviving controller can trigger again");
            checkMod(row(repeated, "剑圣腕刃增强"), "空手攻击力", 100, "the second burst uses actual full modifiers");

            projection.setDetailsEnabled(false);
            var legacy:Array = projection.snapshot();
            check(legacy[0].incarnation === undefined && legacy[0].group === undefined &&
                legacy[0].activation === undefined && legacy[0].mods === undefined,
                "retiring the capability restores the exact legacy field set");
        } catch (error) {
            failed++;
            trace("[FAIL] PlayerHudWristbladeTest exception: " + error);
        } finally {
            projection.deinitialize();
            manager.destroy();
            target.dispatcher.destroy();
            target.removeMovieClip();
            if (previousRegistrar === undefined) delete _root.装备生命周期函数.剑圣套装登记Buff;
            else _root.装备生命周期函数.剑圣套装登记Buff = previousRegistrar;
        }
        trace("PlayerHudWristbladeTest Tests Passed: " + passed);
        trace("PlayerHudWristbladeTest Tests Failed: " + failed);
    }
}
