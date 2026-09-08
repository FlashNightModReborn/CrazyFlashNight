import org.flashNight.neur.Event.*;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;

// 使用真实物品XML、真实CS6素材和生产生命周期装载器；捕获原有子弹API，不写存档。
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.BloodSwordLifecycleTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var finished:Boolean;
    private static var item:Object;
    private static var container:MovieClip;
    private static var watch:MovieClip;
    private static var unit:MovieClip;
    private static var primary:MovieClip;
    private static var secondary:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;
    private static var cycles:Array;
    private static var shots:Array;
    private static var rolls:Array;
    private static var rollCount:Number;
    private static var ref:Object;
    private static var pausedFrames:Object;
    private static var oldClock:Object;
    private static var oldCleanup:Function;
    private static var oldShoot:Function;
    private static var oldWorld:MovieClip;

    private static function check(value:Boolean, label:String):Void {
        if (value) passed++;
        else { failed++; trace("[FAIL] BloodSwordLifecycleTest: " + label); }
    }
    private static function die(label:String):Void {
        failed++; trace("[FAIL] BloodSwordLifecycleTest: " + label); finish();
    }
    private static function nextRoll():Boolean {
        rollCount++;
        return rolls.length ? Boolean(rolls.shift()) : false;
    }
    private static function tick():Void {
        _root.帧计时器.当前帧数++;
        for (var i:Number = 0; i < cycles.length; i++) cycles[i].callback.apply(cycles[i].owner, cycles[i].args);
    }
    private static function position(marker:MovieClip):Object {
        var point:Object = {x:0,y:0}; marker.localToGlobal(point); _root.gameworld.globalToLocal(point); return point;
    }
    private static function captureShot():Void {
        var row:Array = [];
        for (var i:Number = 0; i < arguments.length; i++) row.push(arguments[i]);
        shots.push(row);
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; finished = false; cycles = []; shots = []; rolls = []; rollCount = 0;
        oldClock = _root.帧计时器; oldCleanup = _root.装备生命周期函数.移除异常周期函数;
        oldShoot = _root.子弹区域shoot; oldWorld = _root.gameworld;
        _root.帧计时器 = {当前帧数:0, taskManager:{addLifecycleTask:function(owner:Object,label:String,callback:Function,interval:Number,args:Array):Number {
            BloodSwordLifecycleTest.cycles.push({owner:owner,callback:callback,args:args}); return BloodSwordLifecycleTest.cycles.length;
        }}, 移除生命周期任务:function(owner:Object,label:String):Void {}};
        _root.装备生命周期函数.移除异常周期函数 = function(value:Object):Void {};
        _root.子弹区域shoot = captureShot;
        container = _root.createEmptyMovieClip("__bloodSwordAssets", _root.getNextHighestDepth());
        watch = _root.createEmptyMovieClip("__bloodSwordWatch", _root.getNextHighestDepth());
        watch.waitTicks = 0;
        watch.onEnterFrame = function():Void { if (++this.waitTicks >= 300) BloodSwordLifecycleTest.die("素材加载超时"); };
        var document:XML = new XML(); document.ignoreWhite = true;
        document.onLoad = function(ok:Boolean):Void {
            if (!ok) { BloodSwordLifecycleTest.die("实际物品XML加载失败"); return; }
            var parsed:Object = XMLParser.parseXMLNode(this.firstChild);
            for (var i:Number = 0; i < parsed.item.length; i++) {
                if (parsed.item[i].name == "血色光剑天秤") BloodSwordLifecycleTest.item = parsed.item[i];
            }
            if (!BloodSwordLifecycleTest.item) { BloodSwordLifecycleTest.die("实际物品缺失"); return; }
            BloodSwordLifecycleTest.loadAssets();
        };
        document.load("../data/items/武器_刀_直剑.xml");
    }
    private static function loadAssets():Void {
        listener = {};
        listener.onLoadInit = function(loaded:MovieClip):Void {
            if (BloodSwordLifecycleTest.finished) return;
            delete BloodSwordLifecycleTest.watch.onEnterFrame;
            try { BloodSwordLifecycleTest.runLoaded(loaded); }
            catch (error) { BloodSwordLifecycleTest.die("意外异常 " + error); }
        };
        listener.onLoadError = function(loaded:MovieClip,error:String):Void { BloodSwordLifecycleTest.die("素材加载失败 " + error); };
        loader = new MovieClipLoader(); loader.addListener(listener);
        if (!loader.loadClip("../flashswf/arts/new/Codex专用素材.swf",container)) die("提交素材加载失败");
    }
    private static function runLoaded(loaded:MovieClip):Void {
        check(item.name == "血色光剑天秤" && item.data.level == 50, "保留物品身份与等级");
        check(item.data.power == 999 && item.data.weight == -99 && item.data.hp == -999, "保留威力、负重与HP代价");
        check(item.price == 500000 && item.data.bladeCount == 3 && item.data.skillmultipliers.凶斩 == 2, "保留售价、刀口数与战技倍率");
        check(item.icon == "Codex-血色光剑天秤" && item.data.dressup == "刀-Codex-血色光剑天秤", "切换新素材映射");
        check(item.lifecycle.attr_0.init.initRoutines == "通用刀光初始化" && item.lifecycle.attr_0.init.initParam.basicStyle == "烈焰残焰", "原刀光节点保留");
        check(item.lifecycle.attr_1.init.initRoutines == "血色光剑初始化" && item.lifecycle.attr_1.cycle.cycleRoutines == "血色光剑周期", "真实XML绑定新周期");
        unit = loaded.createEmptyMovieClip("bloodActor",loaded.getNextHighestDepth());
        unit._x = 140; unit._y = 180; unit.version = 1; unit.hp = 1000; unit.状态 = "站立"; unit.syncRefs = {}; unit.主动战技 = {};
        unit.createEmptyMovieClip("man",1); unit.man.兵器使用标签 = false;
        unit.刀 = new BaseItem(item.name,{level:1,mods:[]},0); unit.刀数据 = item; unit.刀属性 = item.data;
        unit.dispatcher = new EventDispatcher(); unit.装载生命周期函数 = _root.主角函数.装载生命周期函数;
        primary = unit.man.attachMovie(item.data.dressup,"mainSword",2);
        secondary = unit.man.attachMovie(item.data.dressup,"backSword",3);
        secondary._x = 60;
        unit.刀_引用 = primary; unit.刀1_引用 = secondary; _root.gameworld = loaded;
        check(primary._parent === unit.man && secondary._parent === unit.man, "两份真实素材实例挂在所属单位内");
        check(primary.剑体.fxGrip._totalframes == 54 && primary.剑体.fxBreath._totalframes == 84, "柄灯与呼吸真实帧数");
        check(primary.剑体.fxFlow._totalframes == 54 && primary.剑体.fxBurst._totalframes == 12, "纹路与爆发真实帧数");
        check(primary._totalframes == 1 && primary.剑体._totalframes == 1, "外壳和总装保持单帧");
        check(Math.abs(primary.刀口位置1._x + 11.35) < .06 && Math.abs(primary.刀口位置1._y - 96.95) < .06, "刀口1原坐标");
        check(Math.abs(primary.刀口位置2._y - 211.95) < .06 && Math.abs(primary.刀口位置3._y - 305.1) < .06, "刀口2与3原坐标");
        unit.装载生命周期函数({attr_1:item.lifecycle.attr_1},"刀");
        check(cycles.length == 1 && cycles[0].args[0].生命周期函数 == "血色光剑周期", "生产装载器只注册一次专属周期");
        ref = cycles[0].args[0];
        check(ref.bloodRoll === _root.装备生命周期函数.血色光剑随机, "生产默认五择一函数");
        ref.bloodRoll = nextRoll;
        check(primary.剑体.fxGrip._visible && secondary.剑体.fxGrip._visible, "常态两实例柄灯可见");
        check(!primary.剑体.fxBreath._visible && !primary.剑体.fxFlow._visible && !primary.剑体.fxBurst._visible, "常态关闭附加刃效");
        for (var i:Number = 0; i < 54; i++) tick();
        check(primary.剑体.fxGrip._currentframe == 1 && primary.剑体.fxBreath._currentframe == 1, "柄灯一轮循环与隐藏帧停止");
        check(rollCount == 0 && shots.length == 0 && unit.hp == 1000, "待机没有概率判定或扣血");
        unit.man.兵器使用标签 = true; tick();
        check(primary.剑体.fxBreath._visible && primary.剑体.fxFlow._visible, "持刀开启呼吸与纹路");
        check(!secondary.剑体.fxBreath._visible && !secondary.剑体.fxFlow._visible, "背负实例不播放持刀刃效");
        var phase:Number = ref.bloodFlowFrame;
        unit.dispatcher.publish("刀_引用",unit); unit.dispatcher.publish("刀_引用",unit);
        check(ref.bloodFlowFrame == phase && rollCount == 0 && unit.hp == 1000, "placement不推进时钟也不结算");
        tick(); check(ref.bloodFlowFrame == phase + 1, "重复持刀不重置循环相位");
        unit.状态 = "兵器攻击"; rolls = [true,true]; rollCount = 0; shots = []; tick();
        check(rollCount == 2 && shots.length == 2, "同一攻击帧两路独立结算");
        check(unit.hp == 996, "两路成功累计扣4HP");
        check(shots[0][4] == "血爆炸" && shots[0][5] == 999 && shots[1][4] == "血滴落" && shots[1][5] == 100, "保留两种子弹与固定威力");
        check(shots[0][1] == 1 && shots[0][6] == 0 && shots[0][7] == 100 && shots[0][14] == 1 && shots[0].length == 16, "保留弹数速度范围和击倒参数");
        check(shots[0][11] == unit._y && shots[0][12] == unit._y && shots[0][13] === true && shots[0][9] == unit._name, "保留发射者平面和敌我归属");
        check(ref.bloodBurstFrame == 1 && primary.剑体.fxBurst._visible && !secondary.剑体.fxBurst._visible, "两路共用一次本剑爆发反馈");
        cycles[0].callback.apply(cycles[0].owner,cycles[0].args);
        check(rollCount == 2 && shots.length == 2 && unit.hp == 996, "同一时钟帧重复回调不重扣");
        phase = ref.bloodFlowFrame; rolls = [true,true]; tick();
        check(ref.bloodBurstFrame == 2 && ref.bloodFlowFrame == phase + 1, "连续触发保留爆发进度和循环相位");
        check(unit.hp == 992 && shots.length == 4, "视觉合并不吞第二帧结算");
        primary._rotation = 21; primary._xscale = -120; primary._yscale = 80; unit.man._rotation = -9;
        var p3:Object = position(primary.刀口位置3); var p2:Object = position(primary.刀口位置2);
        shots = []; rolls = [true,true]; tick();
        check(Math.abs(shots[0][10] - p3.x) < .1 && Math.abs(shots[1][10] - p2.x) < .1, "完整镜像旋转链后的真实刀口X");
        check(shots[0][11] == unit._y && shots[1][12] == unit._y, "变换后仍使用旧地面Y/Z约定");
        shots = []; rolls = [false,true]; unit.是否为敌人 = true; var hp:Number = unit.hp; tick();
        check(shots.length == 1 && shots[0][4] == "血滴落" && unit.hp == hp - 1 && shots[0][13] === false, "敌人小分支的1HP与敌我参数");
        shots = []; rolls = [true,false]; hp = unit.hp; tick();
        check(shots.length == 1 && shots[0][4] == "血爆炸" && unit.hp == hp - 3, "大分支单独成功扣3HP");
        shots = []; rolls = [false,false]; hp = unit.hp; tick();
        check(shots.length == 0 && unit.hp == hp, "两路失败不扣血不发射");
        rolls = []; unit.状态 = "站立";
        for (i = 0; i < 12; i++) tick();
        check(ref.bloodBurstFrame == 0 && !primary.剑体.fxBurst._visible && primary.剑体.fxBurst._currentframe == 1, "爆发结束隐藏复位");
        check(primary.剑体.fxBreath._visible && primary.剑体.fxFlow._visible, "爆发结束不影响持刀循环");
        for (i = 0; i < 168; i++) tick();
        check(primary.剑体.fxFlow._currentframe == ref.bloodFlowFrame && primary.剑体.fxBreath._currentframe == ref.bloodBreathFrame, "跨多轮真实时间轴保持独立相位");
        unit.man.兵器使用标签 = false; tick();
        check(!primary.剑体.fxFlow._visible && primary.剑体.fxFlow._currentframe == 1 && primary.剑体.fxGrip._visible, "收刀隐藏停回刃效首帧");
        var subscriptions:Number = unit.dispatcher["_subCount"];
        _root.装备生命周期函数.血色光剑初始化(ref,{}); ref.bloodRoll = nextRoll;
        check(unit.dispatcher["_subCount"] == subscriptions, "重复初始化不累加订阅");
        var cleanupCount:Number = 0;
        for (i = 0; i < unit.生命周期函数列表.length; i++) if (unit.生命周期函数列表[i] === ref.bloodCleanup) cleanupCount++;
        check(cleanupCount == 1, "卸载回调只登记一次");
        var previous:MovieClip = primary;
        primary = unit.man.attachMovie(item.data.dressup,"replacementSword",4); unit.刀_引用 = primary;
        rollCount = 0; hp = unit.hp; unit.dispatcher.publish("刀_引用",unit);
        check(!previous.剑体.fxGrip._visible && previous._cf7BloodSwordOwner == undefined, "替换外观清理旧实例");
        check(primary._cf7BloodSwordOwner === ref && primary.剑体.fxGrip._visible && rollCount == 0 && unit.hp == hp, "新实例即时接入且不补发战斗事件");
        unit.状态 = "兵器攻击"; unit.man.兵器使用标签 = true; unit.man._visible = false; shots = []; rolls = [true,true]; tick();
        check(shots.length == 0 && unit.hp == hp && rollCount == 0, "隐藏祖先阻止幽灵扣血");
        check(!primary.剑体.fxGrip._visible && !primary.剑体.fxBurst._visible, "隐藏祖先同时关闭光效");
        unit.man._visible = true; rolls = [false,false]; tick();
        check(primary.剑体.fxGrip._visible && primary.剑体.fxFlow._visible, "重新显示恢复当前装备状态");
        unit.刀1_引用 = primary; unit.dispatcher.publish("刀1_引用",unit);
        check(ref.bloodViews.length == 1 && !secondary.剑体.fxGrip._visible, "重复引用去重并清理离开的背负实例");
        unit.状态 = "站立"; rolls = [];
        pausedFrames = {grip:primary.剑体.fxGrip._currentframe,flow:primary.剑体.fxFlow._currentframe,breath:primary.剑体.fxBreath._currentframe,hp:unit.hp};
        watch.waitTicks = 0;
        watch.onEnterFrame = function():Void {
            if (++this.waitTicks == 3) {
                delete this.onEnterFrame;
                try { BloodSwordLifecycleTest.finishChecks(); }
                catch (error) { BloodSwordLifecycleTest.die("异步检查异常 " + error); }
            }
        };
    }
    private static function finishChecks():Void {
        check(primary.剑体.fxGrip._currentframe == pausedFrames.grip && primary.剑体.fxFlow._currentframe == pausedFrames.flow && primary.剑体.fxBreath._currentframe == pausedFrames.breath, "三个真实播放帧内无装备tick则光效不自行推进");
        check(unit.hp == pausedFrames.hp, "素材影片剪辑不自行扣血");
        unit.version++; unit.dispatcher.publish("刀_引用",unit);
        check(!ref.bloodActive && !primary.剑体.fxGrip._visible && unit.dispatcher["_subCount"] == 0, "版本失效即时关闭并精确退订");
        _root.装备生命周期函数.血色光剑初始化(ref,{}); ref.bloodRoll = nextRoll;
        var oldHandler:Function = ref.bloodHandlers[0].handler;
        check(primary.剑体.fxGrip._visible && unit.dispatcher["_subCount"] == 2, "新版本重新初始化");
        unit.刀 = new BaseItem("其它武器",{},0); tick();
        check(!ref.bloodActive && !primary.剑体.fxGrip._visible, "同版本替换装备对象也失效");
        unit.刀 = new BaseItem(item.name,{},0); _root.装备生命周期函数.血色光剑初始化(ref,{}); ref.bloodRoll = nextRoll;
        primary.剑体.body._alpha = 87;
        var bodyAlpha:Number = primary.剑体.body._alpha;
        DressupInitializer.teardownLifeCycles(unit);
        check(!ref.bloodActive && !primary.剑体.fxGrip._visible && !primary.剑体.fxFlow._visible && unit.dispatcher["_subCount"] == 0, "生产卸载入口清理全部光效和订阅");
        oldHandler();
        check(!primary.剑体.fxGrip._visible && unit.dispatcher["_subCount"] == 0, "迟到回调不复活已卸载外观");
        check(primary._parent === unit.man && primary.剑体.body._alpha == bodyAlpha && primary.剑体.baseBlade._visible,
            "卸载不删除实体与常在红刃；alpha=" + primary.剑体.body._alpha + "/" + bodyAlpha);
        finish();
    }
    private static function finish():Void {
        if (finished) return; finished = true;
        delete watch.onEnterFrame;
        if (unit) { DressupInitializer.teardownLifeCycles(unit); unit.dispatcher.destroy(); }
        if (loader) loader.removeListener(listener);
        container.removeMovieClip(); watch.removeMovieClip();
        _root.帧计时器 = oldClock; _root.装备生命周期函数.移除异常周期函数 = oldCleanup;
        _root.子弹区域shoot = oldShoot; _root.gameworld = oldWorld;
        trace("BloodSwordLifecycleTest Tests Passed: " + passed);
        trace("BloodSwordLifecycleTest Tests Failed: " + failed);
        _root.bloodSwordFocusedComplete();
    }
}
