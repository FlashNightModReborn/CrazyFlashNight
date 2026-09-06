import org.flashNight.neur.Event.*;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;

// 样例身份和路径由专用 TestLoader 模板传入；在真实 MovieClip 上验证生产装卸与动画。
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.Qjz171LiveAnimationTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var container:MovieClip;
    private static var watchdog:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;
    private static var unit:MovieClip;
    private static var ref:Object;
    private static var oldClock:Object;
    private static var oldCleanup:Function;
    private static var finished:Boolean;
    private static var itemConfig:Object;
    private static var fixture:Object;
    private static var queuedCycle:Object;
    private static var cycleRemoved:Boolean;

    private static function check(value:Boolean, message:String):Void {
        if (value) passed++;
        else fail(message);
    }
    private static function fail(message:String):Void {
        failed++;
        trace("[FAIL] Qjz171LiveAnimationTest: " + message);
    }
    public static function configure(spec:Object):Void {
        fixture = spec;
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; finished = false;
        oldClock = _root.帧计时器;
        oldCleanup = _root.装备生命周期函数.移除异常周期函数;
        queuedCycle = null; cycleRemoved = false; itemConfig = null;
        _root.帧计时器 = {当前帧数:0, taskManager:{addLifecycleTask:function(owner:Object, label:String, callback:Function, interval:Number, args:Array):Number {
            Qjz171LiveAnimationTest.queuedCycle = {owner:owner, label:label, callback:callback, args:args};
            return 171;
        }}, 移除生命周期任务:function(owner:Object, label:String):Void {
            Qjz171LiveAnimationTest.cycleRemoved = true;
        }};
        _root.装备生命周期函数.移除异常周期函数 = function(value:Object):Void {};
        container = _root.createEmptyMovieClip("__qjzLiveAssets", _root.getNextHighestDepth());
        watchdog = _root.createEmptyMovieClip("__qjzLiveWatchdog", _root.getNextHighestDepth());
        watchdog.count = 0;
        watchdog.onEnterFrame = function():Void {
            if (++this.count >= 120) {
                Qjz171LiveAnimationTest.fail("真实 SWF 加载超时");
                Qjz171LiveAnimationTest.finish();
            }
        };
        var document:XML = new XML();
        document.ignoreWhite = true;
        document.onLoad = function(success:Boolean):Void {
            if (!success) {
                Qjz171LiveAnimationTest.fail("真实物品 XML 加载失败");
                Qjz171LiveAnimationTest.finish(); return;
            }
            var parsed:Object = XMLParser.parseXMLNode(this.firstChild);
            for (var index:Number = 0; index < parsed.item.length; index++) {
                if (parsed.item[index].name == Qjz171LiveAnimationTest.fixture.itemName) Qjz171LiveAnimationTest.itemConfig = parsed.item[index];
            }
            Qjz171LiveAnimationTest.check(Qjz171LiveAnimationTest.itemConfig.lifecycle != undefined, "真实物品 XML 保留动画生命周期");
            if (!Qjz171LiveAnimationTest.itemConfig) { Qjz171LiveAnimationTest.finish(); return; }
            Qjz171LiveAnimationTest.loadAssets();
        };
        document.load(fixture.itemXml);
    }
    private static function loadAssets():Void {
        listener = {};
        listener.onLoadInit = function(loaded:MovieClip):Void { Qjz171LiveAnimationTest.runLoaded(loaded); };
        listener.onLoadError = function(loaded:MovieClip, error:String, status:Number):Void {
            Qjz171LiveAnimationTest.fail("加载失败 " + error + " status=" + status);
            Qjz171LiveAnimationTest.finish();
        };
        loader = new MovieClipLoader();
        loader.addListener(listener);
        var started:Boolean = loader.loadClip(fixture.swf, container);
        check(started, "提交真实素材加载");
        if (!started) finish();
    }
    private static function runLoaded(loaded:MovieClip):Void {
        delete watchdog.onEnterFrame;
        try {
            var gun:MovieClip = loaded.attachMovie(fixture.linkage, "liveGun", loaded.getNextHighestDepth());
            var animation:MovieClip = gun.动画;
            check(gun != undefined && animation != undefined && animation._totalframes >= 3, "真实导出链接及命名 MovieClip 可用");
            if (!gun || !animation) { finish(); return; }
            check(gun.枪口位置 != undefined, "真实枪口接口存在");
            var muzzleX:Number = gun.枪口位置._x;
            var idle:Object = animation.getBounds(animation);
            unit = loaded.createEmptyMovieClip("actualActor", loaded.getNextHighestDepth());
            unit.version = 1; unit.攻击模式 = "长枪"; unit.syncRefs = {};
            unit.长枪 = new BaseItem(fixture.itemName, {level:1, shot:0, mods:[]}, 0);
            unit.长枪数据 = itemConfig; unit.长枪属性 = itemConfig.data;
            unit.长枪_引用 = gun; unit.dispatcher = new EventDispatcher(); unit.主动战技 = {};
            unit.装载生命周期函数 = _root.主角函数.装载生命周期函数;
            check(typeof unit == "movieclip" && unit.长枪 instanceof BaseItem, "真实角色 MovieClip 和物品实例");
            unit.装载生命周期函数(itemConfig.lifecycle, "长枪");
            check(queuedCycle != null && queuedCycle.args[0].装备名称 == fixture.itemName, "生产装载入口注册动画周期");
            ref = queuedCycle.args[0];
            var lastFrame:Number = animation._totalframes;
            check(ref.animationActive && ref.animationEnd == lastFrame, "生产入口初始化真实显示对象");
            check(animation._currentframe == 1, "真实待机帧停止");
            unit.dispatcher.publish("processShot", unit, "长枪", gun.枪口位置, {});
            check(animation._currentframe == 2 && gun.枪口位置._x == muzzleX, "击发帧与枪口接口对齐");
            _root.帧计时器.当前帧数 = 1;
            queuedCycle.callback.apply(queuedCycle.owner, queuedCycle.args);
            check(animation._currentframe == 3, "真实时间轴进入后坐帧");
            var recoil:Object = animation.getBounds(animation);
            check(recoil.xMin > idle.xMin + 0.05, "实际显示列表中的枪管前端后移");
            for (var frame:Number = 2; frame <= lastFrame - 2; frame++) {
                _root.帧计时器.当前帧数 = frame;
                queuedCycle.callback.apply(queuedCycle.owner, queuedCycle.args);
            }
            var returned:Object = animation.getBounds(animation);
            check(animation._currentframe == lastFrame && Math.abs(returned.xMin - idle.xMin) < 0.05,
                "真实末帧回到原始轮廓");
            _root.帧计时器.当前帧数 = lastFrame - 1;
            queuedCycle.callback.apply(queuedCycle.owner, queuedCycle.args);
            check(animation._currentframe == 1, "真实单发周期结束回待机");
            unit.dispatcher.publish("processShot", unit, "长枪", gun.枪口位置, {});
            unit.攻击模式 = "手枪";
            _root.装备生命周期函数.长枪射击动画视觉更新(ref);
            check(animation._currentframe == 1 && ref.animationFrame == 2, "真实姿态切换回位且视觉回调不推进状态");
            DressupInitializer.teardownLifeCycles(unit);
            check(unit.dispatcher["_subCount"] == 0 && !ref.animationActive && cycleRemoved,
                "生产卸载入口清理动画订阅和周期");
        } catch (error) { fail("意外异常 " + error); }
        finish();
    }
    private static function finish():Void {
        if (finished) return;
        finished = true;
        delete watchdog.onEnterFrame;
        if (ref) _root.装备生命周期函数.长枪射击动画卸载(ref);
        if (unit) unit.dispatcher.destroy();
        loader.removeListener(listener);
        container.removeMovieClip(); watchdog.removeMovieClip();
        _root.帧计时器 = oldClock;
        _root.装备生命周期函数.移除异常周期函数 = oldCleanup;
        trace("Qjz171LiveAnimationTest Tests Passed: " + passed);
        trace("Qjz171LiveAnimationTest Tests Failed: " + failed);
        _root.weaponAnimationFocusedComplete();
    }
}
