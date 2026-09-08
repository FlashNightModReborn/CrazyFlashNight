import org.flashNight.neur.Event.*;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;

// 真实素材 + 实际生命周期入口，覆盖两个手枪槽和长枪，不写玩家存档。
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.WeaponLaserSightTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var completed:Number;
    private static var finished:Boolean;
    private static var container:MovieClip;
    private static var watchdog:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;
    private static var configs:Object;
    private static var cycles:Array;
    private static var unit:MovieClip;
    private static var oldClock:Object;
    private static var oldCleanup:Function;
    private static var fixture:Object;

    private static function check(value:Boolean, message:String):Void {
        if (value) passed++;
        else { failed++; trace("[FAIL] WeaponLaserSightTest: " + message); }
    }
    private static function point(clip:MovieClip, x:Number, y:Number):Object {
        var p:Object = {x:x, y:y};
        clip.localToGlobal(p);
        return p;
    }
    private static function aligned(gun:MovieClip):Boolean {
        var a:Object = point(gun.激光模组, 0, 0);
        var b:Object = point(gun.激光发射器.出光位置, 0, 0);
        return Math.abs(a.x - b.x) < 0.2 && Math.abs(a.y - b.y) < 0.2;
    }
    private static function sameDirection(gun:MovieClip):Boolean {
        var start:Object = point(gun.激光模组, 0, 0);
        var end:Object = point(gun.激光模组, 100, 0);
        var origin:Object = point(gun.激光发射器.出光位置, 0, 0);
        var forward:Object = point(gun.激光发射器.出光位置, 100, 0);
        var ax:Number = end.x - start.x;
        var ay:Number = end.y - start.y;
        var bx:Number = forward.x - origin.x;
        var by:Number = forward.y - origin.y;
        var scale:Number = Math.sqrt((ax * ax + ay * ay) * (bx * bx + by * by));
        return scale > 0 && ax * bx + ay * by > 0 && Math.abs(ax * by - ay * bx) / scale < 0.005;
    }
    public static function configure(spec:Object):Void { fixture = spec; }
    public static function runAllTests():Void {
        passed = 0; failed = 0; completed = 0; finished = false;
        configs = {}; cycles = [];
        oldClock = _root.帧计时器;
        oldCleanup = _root.装备生命周期函数.移除异常周期函数;
        _root.帧计时器 = {当前帧数:0, taskManager:{addLifecycleTask:function(owner:Object, label:String, callback:Function, interval:Number, args:Array):Number {
            WeaponLaserSightTest.cycles.push({owner:owner, label:label, callback:callback, args:args});
            return WeaponLaserSightTest.cycles.length;
        }}, 移除生命周期任务:function(owner:Object, label:String):Void {}};
        _root.装备生命周期函数.移除异常周期函数 = function(ref:Object):Void {};
        container = _root.createEmptyMovieClip("__weaponLaserAssets", _root.getNextHighestDepth());
        watchdog = _root.createEmptyMovieClip("__weaponLaserWatchdog", _root.getNextHighestDepth());
        watchdog.count = 0;
        watchdog.onEnterFrame = function():Void {
            if (++this.count >= 300) {
                WeaponLaserSightTest.check(false, "真实物品或素材加载超时");
                WeaponLaserSightTest.finish();
            }
        };
        loadConfig(0);
    }
    private static function loadConfig(index:Number):Void {
        var paths:Array = fixture.itemFiles;
        var document:XML = new XML();
        document.ignoreWhite = true;
        document.onLoad = function(success:Boolean):Void {
            if (WeaponLaserSightTest.finished) return;
            WeaponLaserSightTest.check(success, "加载实际物品 XML " + index);
            if (!success) { WeaponLaserSightTest.finish(); return; }
            var parsed:Object = XMLParser.parseXMLNode(this.firstChild);
            for (var i:Number = 0; i < parsed.item.length; i++) {
                var item:Object = parsed.item[i];
                if (item.name == WeaponLaserSightTest.fixture.handgun.itemName || item.name == WeaponLaserSightTest.fixture.longGun.itemName || item.name == WeaponLaserSightTest.fixture.printedItemName) {
                    WeaponLaserSightTest.configs[item.name] = item;
                }
            }
            if (index + 1 < WeaponLaserSightTest.fixture.itemFiles.length) WeaponLaserSightTest.loadConfig(index + 1);
            else WeaponLaserSightTest.loadAssets();
        };
        document.load(paths[index]);
    }
    private static function loadAssets():Void {
        var printed:Object = configs[fixture.printedItemName];
        check(printed.data.level == 33 && printed.data.power == 130 && printed.data.weight == 5, "印花集使用批准数值");
        check(printed.data.capacity == 50 && printed.data.interval == 120 && printed.balance.profiles.data.weightLayers == 1, "印花集容量、节奏与一层投影");
        check(printed.lifecycle.attr_0.init.initRoutines == "P90初始化" && printed.lifecycle.attr_1 == undefined, "旧涂装保留原有纯视觉生命周期");
        var p90:Object = configs[fixture.handgun.itemName];
        check(p90.data.level == 45 && p90.data.power == 170 && p90.data.capacity == 50, "钛合金P90基础值不漂移");
        var qjz:Object = configs[fixture.longGun.itemName];
        check(qjz.data.level == 55 && qjz.data.power == 2345 && qjz.data.criticalhit == 17, "钛合金171基础值不漂移");
        listener = {};
        listener.onLoadInit = function(loaded:MovieClip):Void {
            if (!WeaponLaserSightTest.finished) WeaponLaserSightTest.runLoaded(loaded);
        };
        listener.onLoadError = function(loaded:MovieClip, error:String, status:Number):Void {
            WeaponLaserSightTest.check(false, "真实 SWF 加载失败 " + error);
            WeaponLaserSightTest.finish();
        };
        loader = new MovieClipLoader();
        loader.addListener(listener);
        check(loader.loadClip(fixture.assetSwf, container), "提交实际素材加载");
    }
    private static function findCycle(name:String):Object {
        for (var i:Number = 0; i < cycles.length; i++) {
            if (cycles[i].args[0].生命周期函数 == name) return cycles[i];
        }
        return null;
    }
    private static function tick():Void {
        _root.帧计时器.当前帧数++;
        for (var i:Number = 0; i < cycles.length; i++) cycles[i].callback.apply(cycles[i].owner, cycles[i].args);
    }
    private static function runLoaded(loaded:MovieClip):Void {
        delete watchdog.onEnterFrame;
        try {
            runFixture(loaded, fixture.handgun.itemName, "手枪", fixture.handgun.linkage, 0);
            runFixture(loaded, fixture.handgun.itemName, "手枪2", fixture.handgun.linkage, 1);
            runFixture(loaded, fixture.longGun.itemName, "长枪", fixture.longGun.linkage, 2);
        } catch (error) {
            check(false, "意外异常 " + error);
        }
        finish();
    }
    private static function runFixture(loaded:MovieClip, name:String, slot:String, linkage:String, index:Number):Void {
        cycles = [];
        var item:Object = configs[name];
        var gun:MovieClip = loaded.attachMovie(linkage, "laserFixtureGun" + index, loaded.getNextHighestDepth());
        check(gun != undefined && gun.激光发射器.出光位置 != undefined, slot + "真实发射器及出口");
        check(gun.激光模组 == undefined, slot + "原生枪体不携带长光束");
        unit = loaded.createEmptyMovieClip("laserFixtureActor" + index, loaded.getNextHighestDepth());
        unit.version = 1; unit.攻击模式 = "空手"; unit.syncRefs = {}; unit.主动战技 = {};
        unit[slot] = new BaseItem(name, {level:1, shot:0, mods:[]}, 0);
        unit[slot + "数据"] = item; unit[slot + "属性"] = item.data;
        unit[slot + "_引用"] = gun;
        unit.dispatcher = new EventDispatcher();
        unit.装载生命周期函数 = _root.主角函数.装载生命周期函数;
        unit.装载生命周期函数(item.lifecycle, slot);
        var cycle:Object = findCycle("枪械激光周期");
        check(cycle != null, slot + "生产入口注册激光周期");
        var ref:Object = cycle.args[0];
        check(ref.laserActive && gun.激光模组 == undefined, slot + "非持枪状态不创建光束");
        unit.攻击模式 = slot == "长枪" ? "长枪" : "双枪";
        tick();
        var beam:MovieClip = gun.激光模组;
        check(beam != undefined && beam._cf7LaserOwner === ref, slot + "动态挂载真实导出红束");
        check(gun.激光发射器._visible && beam._visible, slot + "硬件与光束分别显示");
        check(aligned(gun), slot + "光束从真实出口起始");
        var bounds:Object = beam.getBounds(beam);
        check(Math.abs(bounds.xMin) < 0.1 && Math.abs(bounds.xMax - 250) < 0.1, slot + "共用参考束原点与250长度");
        if (slot == "长枪") {
            check(ref.laserFireControl && beam._alpha < 20 && beam._alpha > 15,"无套装时171保留暗淡辅助束");
            unit.__laserFixtureProgress=0.5;
            unit.__titaniumType61={getFireControlProgress:function():Number { return WeaponLaserSightTest.unit.__laserFixtureProgress; }};
            tick();
            check(Math.abs(beam._alpha-59)<0.5,"半档火控使真实红束达到中间透明度");
            unit.__laserFixtureProgress=1; tick();
            check(beam._alpha==100,"满档火控恢复完整红束亮度");
            unit.__laserFixtureProgress=0; tick();
            check(beam._alpha<20,"破盾或失去负重收益后红束立即转暗");
            unit.__laserFixtureProgress=Number("NaN"); tick();
            check(beam._alpha<20,"无效火控读数不能显示强光");
            delete unit.__titaniumType61; tick();
            check(beam._alpha<20,"套装卸载后的红束保持辅助瞄准");
            var animationCycle:Object = findCycle("长枪射击动画周期");
            check(animationCycle.args[0].animationEnd == 10 && gun.动画._totalframes == 10, "171保留十帧动画");
            var emitterX:Number = gun.激光发射器._x;
            var emitterY:Number = gun.激光发射器._y;
            unit.dispatcher.publish("processShot", unit, "长枪", gun.枪口位置, {});
            check(gun.动画._currentframe == 2, "171击发事件继续驱动动画");
            tick();
            check(gun.动画._currentframe == 3 && gun.激光发射器._x == emitterX
                && gun.激光发射器._y == emitterY && aligned(gun), "171枪管后坐不拖动发射器或光束");
        } else {
            check(!ref.laserFireControl && beam._alpha==100,slot + "P90激光不接入171火控调光");
            var shots:Array = [0, 25, 49];
            var frames:Array = [1, 26, 50];
            for (var j:Number = 0; j < shots.length; j++) {
                unit[slot].value.shot = shots[j];
                tick();
                check(gun.弹匣._currentframe == frames[j] && gun.激光发射器._visible,
                    slot + "弹量映射 " + shots[j] + " 不改变固定硬件");
            }
        }
        var savedShot:Number = unit[slot].value.shot;
        var startX:Number = beam._x;
        gun._rotation = 25; gun._xscale = -120; gun._yscale = 80;
        gun.激光发射器._rotation = 17;
        gun.激光发射器.出光位置._x += 8;
        _root.装备生命周期函数.枪械激光视觉更新(ref);
        check(aligned(gun), slot + "旋转和镜像后出口仍对齐");
        check(sameDirection(gun), slot + "光束前向与出口局部前向一致");
        check(Math.abs(beam._x - startX) > 0.5, slot + "移动出口后刷新而非使用硬编码坐标");
        check(unit[slot].value.shot == savedShot, slot + "激光不消耗弹药");
        unit.攻击模式 = "空手";
        tick();
        check(!beam._visible && gun.激光发射器._visible, slot + "收枪仅隐藏光束");
        unit.攻击模式 = slot == "长枪" ? "长枪" : "双枪";
        tick();
        check(gun.激光模组 === beam && beam._visible, slot + "再次持枪复用同一光束");
        var subscriptions:Number = unit.dispatcher["_subCount"];
        var param:Object = item.lifecycle.attr_1.init.initParam;
        _root.装备生命周期函数.枪械激光初始化(ref, param);
        check(unit.dispatcher["_subCount"] == subscriptions, slot + "重复初始化不累加订阅");
        var cleanupCount:Number = 0;
        for (var k:Number = 0; k < unit.生命周期函数列表.length; k++) {
            if (unit.生命周期函数列表[k] === ref.laserCleanup) cleanupCount++;
        }
        check(cleanupCount == 1, slot + "卸载回调只登记一次");
        var oldBeam:MovieClip = gun.激光模组;
        var replacement:MovieClip = loaded.attachMovie(linkage, "laserReplacement" + index, loaded.getNextHighestDepth());
        unit[slot + "_引用"] = replacement;
        unit.dispatcher.publish(slot + "_引用", replacement);
        check(replacement.激光模组._cf7LaserOwner === ref && !oldBeam._parent, slot + "placement替换迁移光束并释放旧光束");
        check(gun.激光发射器._visible, slot + "placement清理不删除旧硬件");
        var foreign:MovieClip = replacement.激光模组;
        foreign._cf7LaserOwner = {};
        _root.装备生命周期函数.枪械激光卸载(ref);
        check(foreign._parent === replacement, slot + "不删除不属于当前ref的同名元件");
        foreign.removeMovieClip();
        _root.装备生命周期函数.枪械激光初始化(ref, param);
        var stale:MovieClip = replacement.激光模组;
        var activeCount:Number = unit.dispatcher["_subCount"];
        unit.version++;
        _root.装备生命周期函数.枪械激光视觉更新(ref);
        check(!stale._parent && !ref.laserActive, slot + "版本失效释放光束");
        check(unit.dispatcher["_subCount"] == activeCount - 1, slot + "版本失效精确退订自身placement");
        _root.装备生命周期函数.枪械激光初始化(ref, param);
        var finalBeam:MovieClip = replacement.激光模组;
        var oldHandler:Function = ref.laserPlacementHandler;
        check(finalBeam != undefined, slot + "卸载前存在实际光束");
        DressupInitializer.teardownLifeCycles(unit);
        check(!finalBeam._parent && !ref.laserActive && replacement.激光发射器._visible, slot + "生产卸载入口只移除动态光束");
        oldHandler();
        check(replacement.激光模组 == undefined, slot + "退订后的迟到回调不重建光束");
        unit.dispatcher.destroy(); unit.removeMovieClip(); unit = null;
        gun.removeMovieClip(); replacement.removeMovieClip();
        completed++;
    }
    private static function finish():Void {
        if (finished) return;
        finished = true;
        delete watchdog.onEnterFrame;
        if (unit) { DressupInitializer.teardownLifeCycles(unit); unit.dispatcher.destroy(); }
        if (loader) loader.removeListener(listener);
        container.removeMovieClip(); watchdog.removeMovieClip();
        _root.帧计时器 = oldClock;
        _root.装备生命周期函数.移除异常周期函数 = oldCleanup;
        trace("WeaponLaserSightTest Fixtures Completed: " + completed);
        trace("WeaponLaserSightTest Tests Passed: " + passed);
        trace("WeaponLaserSightTest Tests Failed: " + failed);
        _root.weaponLaserFocusedComplete();
    }
}
