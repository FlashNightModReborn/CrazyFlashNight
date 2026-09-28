import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.item.equipment.EquipmentLifecyclePolicy;
import org.flashNight.arki.item.equipment.EquipmentCalculator;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.item.equipment.TagManager;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightDefense;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.gesh.xml.XMLParser;

// Real XML -> production lifecycle loader -> published gun SWF. No player saves.
class org.flashNight.arki.render.EquipmentLightAssetTest {
    private static var passed:Number, failed:Number, completed:Number;
    private static var finished:Boolean;
    private static var oldWorld:Object, oldClock:Object, oldPause:Object, oldCleanup:Function;
    private static var world:MovieClip, actor:MovieClip, gun:MovieClip, watchdog:MovieClip;
    private static var loader:MovieClipLoader, listener:Object;
    private static var definitions:Object, laserMod:Object, torchMod:Object, cases:Array, cycles:Array, oldMods:Array;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("EquipmentLightAssetTest FAIL: " + label); }
    }
    private static function count():Number {
        var value:String = EquipmentLightBridge.payload();
        return value == "" ? 0 : value.split(";").length - 1;
    }
    private static function configure(active:Boolean):Void {
        var caps:Object = {equipmentLights:2}; caps["native"] = active;
        EquipmentLightBridge.configure(caps);
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; completed = 0; finished = false; definitions = {};
        oldWorld = _root.gameworld; oldClock = _root.帧计时器; oldPause = _root.暂停;
        oldCleanup = _root.装备生命周期函数.移除异常周期函数;
        oldMods = ModRegistry.getModList();
        world = _root.createEmptyMovieClip("__equipmentLightAssets", _root.getNextHighestDepth());
        _root.gameworld = world; _root.暂停 = false;
        _root.帧计时器 = {当前帧数:0, taskManager:{addLifecycleTask:function(owner:Object, label:String, callback:Function, interval:Number, args:Array):Number {
            EquipmentLightAssetTest.cycles.push({owner:owner, callback:callback, args:args});
            return EquipmentLightAssetTest.cycles.length;
        }}, 移除生命周期任务:function(owner:Object, label:String):Void {}};
        _root.装备生命周期函数.移除异常周期函数 = function(ref:Object):Void {};
        EquipmentLightBridge.disconnect();
        cases = [
            {name:"XM1014战术版", slot:"长枪", mode:"长枪", linkage:"枪-长枪-XM1014战术版", swf:"../flashswf/arts/things.swf"},
            {name:"战术版莫斯伯格590", slot:"手枪", mode:"双枪", linkage:"枪-手枪-战术版莫斯伯格590", swf:"../flashswf/arts/things切割.swf"},
            {name:"M4A1", slot:"长枪", mode:"长枪", linkage:"枪-长枪-M4A1", swf:"../flashswf/arts/things.swf", plugin:true}
        ];
        watchdog = _root.createEmptyMovieClip("__equipmentLightAssetWatchdog", _root.getNextHighestDepth());
        watchdog.frames = 0;
        watchdog.onEnterFrame = function():Void {
            if (++this.frames >= 600) { EquipmentLightAssetTest.check(false, "asset load timeout"); EquipmentLightAssetTest.finish(); }
        };
        loadXml(0);
    }
    private static function loadXml(index:Number):Void {
        var paths:Array = ["../data/items/武器_长枪_霰弹枪.xml", "../data/items/武器_手枪_霰弹枪.xml", "../data/items/equipment_mods/高等材料_枪械专用.xml", "../data/items/武器_长枪_突击步枪.xml"];
        var document:XML = new XML(); document.ignoreWhite = true;
        document.onLoad = function(success:Boolean):Void {
            if (EquipmentLightAssetTest.finished) return;
            EquipmentLightAssetTest.check(success, "actual XML " + index);
            if (!success) { EquipmentLightAssetTest.finish(); return; }
            var parsed:Object = XMLParser.parseXMLNode(this.firstChild);
            var items:Array = XMLParser.configureDataAsArray(index == 2 ? parsed.mod : parsed.item);
            for (var i:Number = 0; i < items.length; i++) {
                if (items[i].name == "镭射瞄准具") EquipmentLightAssetTest.laserMod = items[i];
                else if (items[i].name == "战术手电") EquipmentLightAssetTest.torchMod = items[i];
                else EquipmentLightAssetTest.definitions[items[i].name] = items[i];
            }
            if (index < 3) EquipmentLightAssetTest.loadXml(index + 1);
            else {
                EquipmentLightAssetTest.check(EquipmentLifecyclePolicy.isIndependentLifecycle(EquipmentLightAssetTest.laserMod.lifecycle), "XML parser retains valid independent mod lifecycle");
                EquipmentLightAssetTest.check(EquipmentLightAssetTest.laserMod.requireTags == "侧导轨挂点" && EquipmentLightAssetTest.laserMod.stats.flat.accuracy == 45
                    && EquipmentLightAssetTest.laserMod.stats.flat.bulletsize == 15, "existing rail and numeric fields preserved");
                var torch:Object = EquipmentLightAssetTest.torchMod;
                EquipmentLightAssetTest.check(torch.lifecycle.attr_equipmentLight.init.initParam.evasionBonus == 20
                    && torch.lifecycle.attr_equipmentLight.init.initParam.electricEvasionBonus == 5
                    && torch.uiRole == "stability", "actual flashlight XML declares defensive 20/25");
                ModRegistry.loadModData([EquipmentLightAssetTest.laserMod, torch]);
                EquipmentLightAssetTest.loadAsset();
            }
        };
        document.load(paths[index]);
    }
    private static function loadAsset():Void {
        cycles = [];
        actor = world.createEmptyMovieClip("actor" + completed, world.getNextHighestDepth());
        listener = {};
        listener.onLoadInit = function(loaded:MovieClip):Void {
            var spec:Object = EquipmentLightAssetTest.cases[EquipmentLightAssetTest.completed];
            EquipmentLightAssetTest.gun = loaded.attachMovie(spec.linkage, "gun", loaded.getNextHighestDepth());
            // Let authored onClipEvent(load) finish before external lifecycle claims visibility.
            loaded.onEnterFrame = function():Void {
                delete this.onEnterFrame;
                try { EquipmentLightAssetTest.runLoaded(); }
                catch (error) { EquipmentLightAssetTest.check(false, "unexpected " + error); EquipmentLightAssetTest.finish(); }
            };
        };
        listener.onLoadError = function(loaded:MovieClip, error:String):Void {
            EquipmentLightAssetTest.check(false, "actual SWF " + error); EquipmentLightAssetTest.finish();
        };
        loader = new MovieClipLoader(); loader.addListener(listener);
        check(loader.loadClip(cases[completed].swf, actor), "submit actual asset " + completed);
    }
    private static function tick():Void {
        _root.帧计时器.当前帧数++;
        for (var i:Number = 0; i < cycles.length; i++) cycles[i].callback.apply(cycles[i].owner, cycles[i].args);
    }
    private static function runLoaded():Void {
        var spec:Object = cases[completed], item:Object = definitions[spec.name];
        if (spec.plugin) { runPluginLoaded(item); return; }
        check(gun._parent === actor && gun.枪口位置._parent === gun, "real linkage and muzzle " + spec.name);
        check(gun.装备光束._parent === gun && !gun.装备光束._visible, "authored beam starts hidden");
        var beam:MovieClip = gun.装备光束;
        var bounds:Object = beam.getBounds(beam);
        var alpha:Number = beam._alpha, rotation:Number = beam._rotation, scale:Number = beam._xscale;
        actor.version = 1; actor.hp = 100; actor.攻击模式 = "空手"; actor.主动战技 = {}; actor.syncRefs = {};
        actor.dispatcher = new EventDispatcher(); actor._x = 80; actor._y = 120;
        actor[spec.slot] = {name:spec.name, value:{level:1, mods:["镭射瞄准具"]}};
        actor[spec.slot + "数据"] = item; actor[spec.slot + "属性"] = item.data;
        actor[spec.slot + "_引用"] = gun;
        var registry:Object = {}; registry[laserMod.name] = laserMod;
        var lifecycle:Object = EquipmentLifecyclePolicy.merge(item.lifecycle, [laserMod.name], registry);
        actor.装载生命周期函数 = _root.主角函数.装载生命周期函数;
        actor.装载生命周期函数(lifecycle, spec.slot);
        check(cycles.length == 2, "production loader registers builtin and plugin");
        var builtin:Object, plugin:Object;
        for (var i:Number = 0; i < cycles.length; i++) {
            var ref:Object = cycles[i].args[0];
            if (ref.来源插件 == laserMod.name) plugin = ref; else builtin = ref;
        }
        check(builtin != undefined && plugin != undefined && builtin.equipmentLight.kind == 1 && plugin.equipmentLight.kind == 2, "source provenance and kinds");
        check(!beam._visible && count() == 0, "stowed does not light");
        actor.攻击模式 = spec.mode; tick();
        check(beam._visible && builtin.lightBeam === beam, "external lifecycle claims authored beam");
        check(builtin.lightFallback === false && !builtin.lightGenerated._parent, "XML false retains original beam only");
        check(plugin.lightBeam._parent === gun && plugin.lightBeam._visible, "actual laser mod creates independent beam");
        check(beam._alpha == alpha && beam._rotation == rotation && beam._xscale == scale && beam.getBounds(beam).xMax == bounds.xMax, "authored geometry and transparency preserved");
        configure(true); tick();
        check(count() == 2, "two kinds coexist in complete native snapshot");
        var origin:Object = {x:0,y:0}; gun.枪口位置.localToGlobal(origin); world.globalToLocal(origin);
        check(Math.abs(builtin.equipmentLight.x - origin.x) < 0.01 && Math.abs(builtin.equipmentLight.y - origin.y) < 0.01, "missing handlight port falls back to real muzzle");
        actor.状态 = spec.mode + "换弹"; tick();
        check(count() == 2 && beam._visible, "reload keeps both lights");
        configure(false); tick();
        check(count() == 0 && beam._visible && plugin.lightBeam._visible, "native capability loss preserves Flash visuals");
        configure(true); actor.攻击模式 = "空手"; tick();
        check(count() == 0 && !beam._visible && !plugin.lightBeam._visible, "stow hides both visuals and projections");
        actor.攻击模式 = spec.mode; tick(); actor.hp = 0; tick();
        check(count() == 0 && !beam._visible, "dead actor does not light");
        actor.hp = 100; tick();
        var dynamicBeam:MovieClip = plugin.lightBeam;
        DressupInitializer.teardownLifeCycles(actor);
        check(beam._parent === gun && !beam._visible && !dynamicBeam._parent && count() == 0, "production teardown retains authored asset and removes plugin beam");
        check(actor.生命周期函数列表.length == 0 && actor.dispatcher["_subCount"] == 0, "all callbacks and placement subscriptions retired");
        nextFixture();
    }
    private static function nextFixture():Void {
        if (actor.buffManager) actor.buffManager.destroy();
        actor.dispatcher.destroy(); loader.removeListener(listener); actor.removeMovieClip(); actor = null;
        completed++;
        if (completed < cases.length) loadAsset(); else finish();
    }
    private static function runPluginLoaded(item:Object):Void {
        var equipment = {name:"M4A1", value:{level:1,mods:[]}};
        check(TagManager.checkModAvailability(equipment,item,"战术手电") == 1,"M4A1 actual rail accepts flashlight");
        var cfg:Object = {levelStatList:[1,1],tierNameToKeyDict:{},defaultTierDataDict:{}};
        var data:Object = EquipmentCalculator.calculatePure(item,{level:1,mods:["战术手电"]},cfg,ModRegistry.getModDict());
        check(data.data.weight == item.data.weight + 0.5,"actual calculator applies flashlight weight");
        check(data.data.evasion == undefined,"conditional evasion is not a permanent inventory stat");
        var rail:String = item.inherentTags; item.inherentTags = "";
        check(TagManager.checkModAvailability(equipment,item,"战术手电") == -16,"missing side rail rejects flashlight");
        item.inherentTags = rail; delete item.inherentTagDict;
        equipment.value.mods = ["镭射瞄准具"];
        check(TagManager.checkModAvailability(equipment,item,"战术手电") == -8,"laser and flashlight compete for side rail");
        equipment.value.mods = [];
        data.skill = {skillname:"fixture",skillLocked:true};
        check(TagManager.checkModAvailability(equipment,data,"战术手电") == 1,"independent flashlight coexists with locked skill");
        actor.version=1;actor.hp=100;actor.攻击模式="空手";actor.主动战技={};actor.syncRefs={};
        actor.dispatcher=new EventDispatcher();actor.buffManager=new BuffManager(actor,{});
        actor.闪避加成=0;actor.躲闪率=3;
        equipment.value.mods=["战术手电"];
        actor.长枪=equipment;actor.长枪数据=data;actor.长枪属性=data.data;actor.长枪_引用=gun;
        actor.装载生命周期函数=_root.主角函数.装载生命周期函数;
        actor.装载生命周期函数(data.lifecycle,"长枪");
        check(cycles.length==1,"actual calculator and production loader register one flashlight lifecycle");
        var ref:Object=cycles[0].args[0];
        check(ref.来源插件=="战术手电" && EquipmentLightDefense.getActiveBonus(actor)==0,"stowed real plugin grants no defense");
        check(gun.枪口位置._parent===gun,"M4A1 real muzzle exists");
        actor.攻击模式="长枪";configure(true);tick();
        check(ref.lightBeam._visible && count()==1,"installed real plugin supplies Flash beam and one compound native light");
        var row:Array=EquipmentLightBridge.payload().split(";")[1].split(",");
        check(row.length==17 && Number(row[15])==140,"native snapshot contains the smaller near field");
        check(EquipmentLightDefense.getActiveBonus(actor)==20 && Math.abs(actor.躲闪率-2.5)<0.00001,"XML-defined defense reaches real BuffManager");
        configure(false);tick();
        check(EquipmentLightDefense.getActiveBonus(actor)==20 && ref.lightBeam._visible,"native revoke preserves the gameplay bonus");
        actor.攻击模式="空手";tick();
        check(EquipmentLightDefense.getActiveBonus(actor)==0 && actor.躲闪率==3,"stowing restores original dodge");
        actor.攻击模式="长枪";tick();DressupInitializer.teardownLifeCycles(actor);
        check(!ref.lightGenerated._parent && actor.躲闪率==3,"production teardown removes both defense and beam");
        check(actor.生命周期函数列表.length==0 && actor.dispatcher["_subCount"]==0,"plugin unload leaves no callbacks");
        nextFixture();
    }
    private static function finish():Void {
        if (finished) return; finished = true;
        delete watchdog.onEnterFrame;
        if (actor) { DressupInitializer.teardownLifeCycles(actor); actor.dispatcher.destroy(); }
        if (loader) loader.removeListener(listener);
        EquipmentLightBridge.disconnect(); world.removeMovieClip(); watchdog.removeMovieClip();
        _root.gameworld = oldWorld; _root.帧计时器 = oldClock; _root.暂停 = oldPause;
        _root.装备生命周期函数.移除异常周期函数 = oldCleanup;
        if (oldMods.length > 0) ModRegistry.loadModData(oldMods);
        trace("EquipmentLightAssetTest Fixtures Completed: " + completed);
        trace("EquipmentLightAssetTest Tests Passed: " + passed);
        trace("EquipmentLightAssetTest Tests Failed: " + failed);
        _root.equipmentLightAssetComplete();
    }
}
