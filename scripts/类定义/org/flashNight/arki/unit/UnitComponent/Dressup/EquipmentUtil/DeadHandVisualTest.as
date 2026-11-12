import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.neur.Event.EventDispatcher;

/** 真实 AVM1 MovieClip / 装扮管理器回归；夹具不接触玩家存档或库存。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandVisualTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) { passed++; trace("[PASS] " + label); }
        else { failed++; trace("[FAIL] " + label); }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var oldConfig:Function = _root.长枪配置;
        var oldTimer:Object = _root.帧计时器;
        _root.帧计时器 = {当前帧数:1};
        try {
            runMatrix(false);
            runMatrix(true);
        } catch (error) {
            check(false, "真实挂点回归异常：" + error);
        } finally {
            _root.长枪配置 = oldConfig;
            _root.帧计时器 = oldTimer;
            _root.__deadHandVisualTest.removeMovieClip();
        }
        trace("DeadHandVisualTest Tests Passed: " + passed);
        trace("DeadHandVisualTest Tests Failed: " + failed);
    }
    private static function holder(unit:MovieClip, name:String):MovieClip {
        var outer:MovieClip = unit.man.createEmptyMovieClip(name, unit.man.getNextHighestDepth());
        return outer.createEmptyMovieClip("枪", outer.getNextHighestDepth());
    }
    private static function attach(unit:MovieClip, name:String, slot:String):MovieClip {
        var parent:MovieClip = holder(unit, name);
        var skin:MovieClip = DressupReferenceManager.attach(parent, "TestProbeSkin", "装扮", slot);
        var marker:MovieClip = skin.createEmptyMovieClip("枪口位置", skin.getNextHighestDepth());
        marker._x = 40; marker._y = -5;
        skin.fixtureIdentity = {};
        return skin;
    }
    private static function pistolIntact(skin:MovieClip, identity:Object):Boolean {
        return skin._visible && skin.fixtureIdentity === identity
            && skin._x == 0 && skin._y == 0 && skin._rotation == 0
            && skin.枪口位置._x == 40 && skin.枪口位置._y == -5
            && skin.__deadHandVisualState == undefined;
    }
    private static function runMatrix(occupied:Boolean):Void {
        var unit:MovieClip = _root.createEmptyMovieClip("__deadHandVisualTest", _root.getNextHighestDepth());
        var slots:Array = ["头部装备","上装装备","下装装备","手部装备","脚部装备","颈部装备","长枪","手枪","手枪2","刀","手雷"];
        for (var i:Number = 0; i < slots.length; i++) unit[slots[i]] = null;
        unit.version = 1; unit.hp = 1000; unit.mp = 1000;
        unit.攻击模式 = "手枪"; unit.状态 = "手枪站立";
        unit.刀 = {name:"死者之手",value:{level:1,shot:0,mods:[]}};
        unit.刀属性 = {power:550,damagetype:"物理",magictype:""};
        unit.兵器动作类型 = "刀剑"; unit.兵器伤害类型 = "物理"; unit.兵器魔法伤害属性 = "";
        unit.man = unit.createEmptyMovieClip("man", unit.getNextHighestDepth());
        unit.syncRefs = {}; unit.dispatcher = new EventDispatcher();
        var observed:Object = {initCount:0,shots:0};
        unit.man.初始化长枪射击函数 = function():Void { observed.initCount++; };
        unit.长枪射击 = function(muzzle:MovieClip, props:Object):Boolean { observed.shots++; observed.muzzle = muzzle; return true; };
        var backGun:MovieClip = attach(unit, "背枪", "长枪_引用");
        var blade:MovieClip = attach(unit, "刀", "刀_引用");
        var pistol:MovieClip = attach(unit, "枪", "手枪_引用");
        var pistol2:MovieClip = attach(unit, "枪2", "手枪2_引用");
        var pistolId:Object = pistol.fixtureIdentity, pistol2Id:Object = pistol2.fixtureIdentity;
        if (occupied) {
            unit.长枪 = {name:"已有步枪",value:{level:1,shot:0,mods:[]}};
            unit.长枪属性 = {power:123,capacity:9};
        }
        _root.长枪配置 = function():Void { unit.长枪属性 = {power:550}; };
        RuntimeEquipmentProjection.beginCanonical(unit);
        var ref:Object = {自机:unit,装备类型:"刀",装备名称:"死者之手",版本号:unit.version,生命周期函数列表:[]};
        var functions:Object = _root.装备生命周期函数;
        functions.死者之手初始化(ref, {gunDressup:"TestProbeSkin"});
        check(RuntimeEquipmentProjection.completeCanonical(unit), "真实挂点完成装备投影，长枪占用=" + occupied);
        check(pistolIntact(pistol, pistolId), "持手枪装备死者之手保留原素材、显隐与枪口");
        check(observed.initCount == 0, "手枪动作中不调用长枪射击初始化");
        check(unit.长枪_引用 === backGun && unit.手枪_引用 === pistol, "生命周期不重写规范枪械引用");
        var modes:Array = ["手枪","手枪2","双枪","空手"];
        for (i = 0; i < modes.length; i++) {
            unit.攻击模式 = modes[i];
            functions.死者之手同步视觉(ref);
            check(pistolIntact(pistol, pistolId) && pistolIntact(pistol2, pistol2Id), modes[i] + "模式隔离主副手素材与枪口");
        }
        unit.攻击模式 = "长枪"; unit.状态 = "长枪站立";
        functions.死者之手同步视觉(ref);
        check(pistolIntact(pistol, pistolId), "模式先变化、挂点尚未换帧时仍不接管旧手枪");
        unit.man.枪.removeMovieClip();
        var gun:MovieClip = attach(unit, "枪", "长枪_引用");
        functions.死者之手同步视觉(ref);
        check(occupied ? (gun._visible && gun._rotation == 0 && gun.枪口位置._y == -5)
            : (gun._visible && gun._rotation == -90 && Math.abs(gun._x + 113.6) < 0.06
                && Math.abs(gun._y - 36.25) < 0.06 && Math.abs(gun.枪口位置._y - 330) < 0.06),
            "真实长枪就位后仅借用形态应用专用偏转与枪口");
        unit.长枪射击(null, {});
        check(observed.shots == 1 && (occupied ? observed.muzzle == null : observed.muzzle === gun.枪口位置),
            "借用射击使用已登记的手持枪口，已有长枪保持原调用");
        check(pistolIntact(pistol2, pistol2Id), "长枪形态不改动仍存活的副手手枪");
        unit.man.兵器使用标签 = true;
        functions.死者之手同步视觉(ref);
        check(blade._visible && (occupied || !gun._visible), "长枪模式下临时近战正确显示刀形态");
        delete unit.man.兵器使用标签;
        unit.man.枪.removeMovieClip();
        pistol = attach(unit, "枪", "手枪_引用"); pistolId = pistol.fixtureIdentity;
        unit.攻击模式 = "手枪"; unit.状态 = "手枪站立";
        functions.死者之手同步视觉(ref);
        check(pistolIntact(pistol, pistolId), "同路径由长枪重建为手枪后保持素材与枪口");
        check(pistol.__deadHandVisualState == undefined && unit.手枪_引用 === pistol,
            "拒绝 MovieClip 重定向后遗留的旧长枪登记项");
        backGun._x = 77;
        functions.死者之手卸载(ref);
        check(pistolIntact(pistol, pistolId) && pistolIntact(pistol2, pistol2Id), "卸装不恢复或覆盖同路径的新手枪");
        check(backGun._visible && backGun._x == 77 && backGun._rotation == 0 && backGun.枪口位置._x == 40
            && backGun.枪口位置._y == -5, "卸装恢复自己的视觉与枪口，同时保留后来的坐标写入");
        functions.死者之手卸载(ref);
        check(pistolIntact(pistol, pistolId), "重复卸装保持幂等");
        unit.removeMovieClip();
    }
}