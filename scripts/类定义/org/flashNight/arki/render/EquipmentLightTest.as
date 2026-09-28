import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController;
import org.flashNight.neur.Event.EventDispatcher;

class org.flashNight.arki.render.EquipmentLightTest {
    private static var passed:Number, failed:Number;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("EquipmentLightTest FAIL: " + label); }
    }
    private static function fixture(world:MovieClip, name:String, item:Object):MovieClip {
        var actor:MovieClip = world.createEmptyMovieClip(name, world.getNextHighestDepth());
        actor.hp = 100; actor.version = 1; actor.攻击模式 = "长枪";
        actor.长枪 = item; actor.syncRefs = {}; actor.dispatcher = new EventDispatcher();
        actor._x = 120; actor._y = 90;
        var gun:MovieClip = actor.createEmptyMovieClip("gun", actor.getNextHighestDepth());
        actor.长枪_引用 = gun;
        var muzzle:MovieClip = gun.createEmptyMovieClip("枪口位置", gun.getNextHighestDepth());
        muzzle._x = 35; muzzle._y = -5;
        return actor;
    }
    private static function refFor(actor:MovieClip, plugin:Boolean):Object {
        return {自机:actor, 装备类型:"长枪", 生命周期函数列表:[], 来源插件:plugin ? "fixture" : undefined};
    }
    private static function count():Number {
        var text:String = EquipmentLightBridge.payload();
        return text == "" ? 0 : text.split(";").length - 1;
    }
    private static function first():Array { return EquipmentLightBridge.payload().split(";")[1].split(","); }

    private static function configure(active:Boolean):Void {
        var caps:Object = {equipmentLights:2}; caps["native"] = active; EquipmentLightBridge.configure(caps);
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var savedWorld = _root.gameworld;
        var savedClock = _root.帧计时器;
        var savedPause = _root.暂停;
        var world:MovieClip = _root.createEmptyMovieClip("__equipmentLightFixture", _root.getNextHighestDepth());
        _root.gameworld = world; _root.帧计时器 = {当前帧数:0}; _root.暂停 = false;
        EquipmentLightBridge.disconnect();
        try {
            var item:Object = {name:"fixture", value:{mods:[]}};
            var actor:MovieClip = fixture(world, "actor", item);
            var gun:MovieClip = actor.长枪_引用;
            var ref:Object = refFor(actor, false);
            check(EquipmentLightController.initialize(ref, {kind:"flashlight"}), "初始化独立灯光");
            check(count() == 0 && ref.lightBeam._visible, "未握手保持Flash光束回退");
            configure(true);
            check(count() == 1 && first().length == 17, "完整快照记录与字段数");
            check(Number(first()[7]) == 1000 && Number(first()[8]) == 260 && Math.abs(Number(first()[9]) - 1.45) < 0.000001, "手电的前照长度与柔光覆盖");
            check(Number(first()[13]) == 120 && Number(first()[14]) == 15 && Number(first()[15]) == 140,
                "近身光以持灯者中心定位而非枪口");
            var pose:Array = first();
            check(Number(pose[3]) == 155 && Number(pose[4]) == 85, "缺手电口时回落真实枪口");
            var outlet:MovieClip = gun.createEmptyMovieClip("手电口", gun.getNextHighestDepth());
            outlet._x = 20; outlet._y = 12;
            EquipmentLightController.update(ref); pose = first();
            check(Number(pose[3]) == 140 && Number(pose[4]) == 102, "手电口优先");
            gun._rotation = 30; gun._xscale = -125; gun._yscale = 80;
            EquipmentLightController.update(ref); pose = first();
            var origin:Object = {x:0, y:0}; var ahead:Object = {x:100, y:0};
            outlet.localToGlobal(origin); outlet.localToGlobal(ahead);
            world.globalToLocal(origin); world.globalToLocal(ahead);
            var dx:Number = ahead.x - origin.x, dy:Number = ahead.y - origin.y;
            var norm:Number = Math.sqrt(dx * dx + dy * dy);
            check(Math.abs(Number(pose[3]) - origin.x) < 0.001 && Math.abs(Number(pose[5]) - dx / norm) < 0.001
                && Math.abs(Number(pose[6]) - dy / norm) < 0.001, "旋转镜像走两点完整变换");
            actor.状态 = "长枪换弹"; EquipmentLightController.update(ref);
            check(count() == 1, "长枪模式换弹保留常驻灯");
            actor.攻击模式 = "空手"; EquipmentLightController.update(ref);
            check(count() == 0 && !ref.lightBeam._visible, "收枪清除快照并隐藏素材");
            actor.攻击模式 = "长枪"; actor.hp = 0; EquipmentLightController.update(ref);
            check(count() == 0 && !ref.lightBeam._visible, "死亡立即熄灯");
            actor.hp = 100; actor._visible = false; EquipmentLightController.update(ref);
            check(count() == 0, "隐藏单位不留光");
            actor._visible = true; EquipmentLightController.update(ref);
            gun._visible = false; EquipmentLightController.update(ref);
            check(count() == 0, "隐藏的枪体不留原生光");
            gun._visible = true; actor._x = 10000; EquipmentLightController.update(ref);
            check(count() == 0, "屏外光束不占用原生预算");
            gun._rotation = 0; gun._xscale = 100; gun._yscale = 100;
            actor._x = -300; EquipmentLightController.update(ref);
            check(count() == 1, "屏外原点但光束进入视野仍投影");
            actor._x = 120; EquipmentLightController.update(ref);
            var stableId:String = first()[1]; EquipmentLightController.update(ref);
            check(first()[1] == stableId, "同一绑定保持稳定id");
            var extraNear:Object = refFor(actor, false);
            EquipmentLightController.initialize(extraNear, {kind:"flashlight", channel:"second"});
            var nearRows:Array = EquipmentLightBridge.payload().split(";");
            check(count() == 2 && (Number(nearRows[1].split(",")[15]) + Number(nearRows[2].split(",")[15])) == 140,
                "同单位两盏手电只保留一份近身光");
            EquipmentLightController.dispose(extraNear);
            _root.暂停 = true; _root.帧计时器.当前帧数 = 100;
            check(count() == 1, "暂停保留最后有效光照");
            _root.暂停 = false;
            check(count() == 0, "未续报的光照停止投影");
            EquipmentLightController.update(ref);
            check(count() == 1, "恢复周期后恢复投影");
            outlet.removeMovieClip(); gun.枪口位置.removeMovieClip(); EquipmentLightController.update(ref);
            check(count() == 0 && !ref.lightBeam._visible, "两种锚点缺失时不沿用旧坐标");
            var callbacks:Number = ref.生命周期函数列表.length;
            EquipmentLightController.dispose(ref); EquipmentLightController.dispose(ref);
            check(ref.生命周期函数列表.length == callbacks && count() == 0, "幂等卸载不修改共享清理队列");
            actor.removeMovieClip(); actor = fixture(world, "actor", item); gun = actor.长枪_引用;
            var plugin:Object = refFor(actor, true);
            EquipmentLightController.initialize(plugin, {kind:"laser"});
            check(count() == 1 && Number(first()[2]) == 2, "激光插件独立投影");
            // Decimal wire parsing can differ from an AVM1 numeric literal in the last binary digit.
            check(Number(first()[8]) == 28 && Math.abs(Number(first()[9]) - 0.85) < 0.000001 && Number(first()[15]) == 0,
                "激光收窄柔光带且不附赠近身光 (snapshot=" + first().join(",") + ")");
            var builtin:Object = refFor(actor, false);
            EquipmentLightController.initialize(builtin, {kind:"laser"}); EquipmentLightController.update(plugin);
            check(count() == 1 && !plugin.lightBeam._visible && builtin.lightBeam._visible, "内置同效优先且去重");
            EquipmentLightController.dispose(builtin); EquipmentLightController.update(plugin);
            check(count() == 1 && plugin.lightBeam._visible, "内置退场后插件接替");
            var second:Object = refFor(actor, true);
            EquipmentLightController.initialize(second, {kind:"laser", channel:"second"});
            check(count() == 2, "显式不同发射器允许并存");
            EquipmentLightController.dispose(second);
            item.value.mods.push("changed");
            check(count() == 0, "同引用同版本插件变化使旧绑定失效");
            EquipmentLightController.update(plugin);
            check(plugin.equipmentLight == null && !plugin.lightGenerated._parent, "旧插件绑定完成清理");
            ref = refFor(actor, false); EquipmentLightController.initialize(ref, {kind:"flashlight"});
            EquipmentLightBridge.resetScene();
            check(count() == 0, "场景epoch清空快照");
            EquipmentLightController.update(ref);
            check(count() == 1, "合法存活绑定可在新epoch续报");
            configure(false);
            check(count() == 0 && ref.lightBeam._visible, "能力撤销保留Flash回退");
            configure(true);
            actor.removeMovieClip(); actor = fixture(world, "actor", item);
            check(count() == 0 && !EquipmentLightBridge.isValid(ref), "同路径重建不能复活旧MovieClip所有权");
            EquipmentLightController.dispose(ref);
            var rejected:Object = refFor(actor, false);
            check(!EquipmentLightController.initialize(rejected, {kind:"laser", length:2000}), "非法光源参数拒绝");
        } catch (error:Error) { check(false, "意外异常 " + error); }
        EquipmentLightBridge.disconnect();
        world.removeMovieClip(); _root.gameworld = savedWorld; _root.帧计时器 = savedClock; _root.暂停 = savedPause;
        trace("EquipmentLightTest Tests Passed: " + passed);
        trace("EquipmentLightTest Tests Failed: " + failed);
    }
}
