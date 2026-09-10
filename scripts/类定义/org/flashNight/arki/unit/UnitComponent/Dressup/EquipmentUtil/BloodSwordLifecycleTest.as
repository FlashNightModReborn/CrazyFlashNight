import org.flashNight.neur.Event.*;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.component.Effect.EffectSystem;

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
    private static var oldBulletInit:Function;
    private static var oldSkillRoute:Object;
    private static var waveUnit:MovieClip;
    private static var waveAssets:MovieClip;
    private static var bindProtection:Boolean;
    private static var bladeFrames:Array;
    private static var bindCount:Number;
    private static var finishCount:Number;
    private static var cancelledShots:Number;
    private static var oldEffect:Function;
    private static var effectFrames:Array;
    private static var lastTail:MovieClip;
    private static var effectBaseline:Number;
    private static var tailFrame:Number;
    private static var tailPosition:Object;

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
    private static function captureShot(props:Object):Void {
        shots.push(props);
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; finished = false; cycles = []; shots = []; rolls = []; rollCount = 0;
        oldClock = _root.帧计时器; oldCleanup = _root.装备生命周期函数.移除异常周期函数;
        oldShoot = _root.子弹区域shoot传递; oldWorld = _root.gameworld;
        oldBulletInit = _root.子弹属性初始化; oldSkillRoute = _root.战技路由;
        oldEffect = _root.效果;
        _root.帧计时器 = {当前帧数:0, taskManager:{addLifecycleTask:function(owner:Object,label:String,callback:Function,interval:Number,args:Array):Number {
            BloodSwordLifecycleTest.cycles.push({owner:owner,callback:callback,args:args}); return BloodSwordLifecycleTest.cycles.length;
        }}, 移除生命周期任务:function(owner:Object,label:String):Void {}};
        _root.装备生命周期函数.移除异常周期函数 = function(value:Object):Void {};
        _root.子弹区域shoot传递 = captureShot;
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
        check(shots[0].子弹种类 == "血爆炸" && shots[0].子弹威力 == 999 && shots[1].子弹种类 == "血滴落" && shots[1].子弹威力 == 100, "保留两种子弹与固定威力");
        check(shots[0].霰弹值 == 1 && shots[0].子弹速度 == 0 && shots[0].Z轴攻击范围 == 100 && shots[0].击倒率 == 1, "保留弹数速度范围和击倒参数");
        check(shots[0].shootY == unit._y && shots[0].shootZ == unit._y && shots[0].发射者 == unit._name, "保留发射者及所在平面，敌我归属由发射器解析");
        check(ref.bloodBurstFrame == 1 && primary.剑体.fxBurst._visible && !secondary.剑体.fxBurst._visible, "两路共用一次本剑爆发反馈");
        cycles[0].callback.apply(cycles[0].owner,cycles[0].args);
        check(rollCount == 2 && shots.length == 2 && unit.hp == 996, "同一时钟帧重复回调不重扣");
        phase = ref.bloodFlowFrame; rolls = [true,true]; tick();
        check(ref.bloodBurstFrame == 2 && ref.bloodFlowFrame == phase + 1, "连续触发保留爆发进度和循环相位");
        check(unit.hp == 992 && shots.length == 4, "视觉合并不吞第二帧结算");
        primary._rotation = 21; primary._xscale = -120; primary._yscale = 80; unit.man._rotation = -9;
        var p3:Object = position(primary.刀口位置3); var p2:Object = position(primary.刀口位置2);
        shots = []; rolls = [true,true]; tick();
        check(Math.abs(shots[0].shootX - p3.x) < .1 && Math.abs(shots[1].shootX - p2.x) < .1, "完整镜像旋转链后的真实刀口X");
        check(shots[0].shootY == unit._y && shots[1].shootZ == unit._y, "变换后仍使用旧地面Y/Z约定");
        shots = []; rolls = [false,true]; unit.是否为敌人 = true; var hp:Number = unit.hp; tick();
        check(shots.length == 1 && shots[0].子弹种类 == "血滴落" && unit.hp == hp - 1 && shots[0].发射者 == unit._name, "敌人小分支的1HP与发射者身份");
        shots = []; rolls = [true,false]; hp = unit.hp; tick();
        check(shots.length == 1 && shots[0].子弹种类 == "血爆炸" && unit.hp == hp - 3, "大分支单独成功扣3HP");
        shots = []; rolls = [false,false]; hp = unit.hp; tick();
        check(shots.length == 0 && unit.hp == hp, "两路失败不扣血不发射");
        check(unit.血量上限击溃 == undefined && unit.斩杀 == undefined, "普通装备未污染人物击溃斩杀属性");
        unit.__titaniumType61 = {calls:0, ownerMatches:true, projectBloodAttack:function(owner:Object,sword:Object,props:Object):Void {
            this.calls++; this.ownerMatches = this.ownerMatches && owner === BloodSwordLifecycleTest.unit && sword === owner.刀;
            props.血量上限击溃 = 0.09; props.斩杀 = 9;
        }};
        rolls = [true,true]; tick();
        check(unit.__titaniumType61.calls == 2 && unit.__titaniumType61.ownerMatches, "两路均传递当前人物与装备身份");
        check(shots[0] !== shots[1] && shots[0].血量上限击溃 == 0.09 && shots[1].斩杀 == 9 && unit.hp == hp - 4, "两路独立属性快照，投射不额外扣血");
        delete unit.__titaniumType61;
        shots = []; rolls = [true,false]; tick();
        check(shots[0].血量上限击溃 == undefined && shots[0].斩杀 == undefined, "离开套装后的新血爆不继承旧弹属性");
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
        unit.dispatcher.destroy(); unit.removeMovieClip(); unit = null;
        loadWave();
    }
    // 实际加载已发布战技，捕获边界调用；碰撞伤害由钛合金专项另行验证。
    private static function loadWave():Void {
        loader.removeListener(listener);
        listener = {};
        listener.onLoadInit = function(loaded:MovieClip):Void {
            // 素材预载结束后下一帧再装配，保持与生产中先预载、后触发战技一致。
            BloodSwordLifecycleTest.watch.loadedWave = loaded;
            BloodSwordLifecycleTest.watch.onEnterFrame = function():Void {
                delete this.onEnterFrame;
                BloodSwordLifecycleTest.startWave(this.loadedWave);
            };
        };
        listener.onLoadError = function(loaded:MovieClip,error:String):Void { BloodSwordLifecycleTest.die("血浪素材加载失败 " + error); };
        loader.addListener(listener);
        watch.waitTicks = 0;
        watch.onEnterFrame = function():Void { if (++this.waitTicks >= 300) BloodSwordLifecycleTest.die("血浪素材加载超时"); };
        waveAssets = _root.createEmptyMovieClip("__bloodWaveAssets", _root.getNextHighestDepth());
        if (!loader.loadClip("../flashswf/arts/things0.swf", waveAssets)) die("血浪素材无法提交加载");
    }
    private static function startWave(loaded:MovieClip):Void {
        _root.gameworld = loaded;
        loaded.createEmptyMovieClip("效果", 1048000); loaded.effectPools = {};
        effectFrames = []; effectBaseline = EffectSystem.getCurrentEffectCount();
        _root.效果 = captureTail;
        shots = []; bladeFrames = []; bindCount = 0; finishCount = 0; bindProtection = false;
        waveUnit = loaded.createEmptyMovieClip("waveActor", loaded.getNextHighestDepth());
        waveUnit._x = 240; waveUnit._y = 260;
        waveUnit.hp = 1000; waveUnit.mp = 100;
        waveUnit.刀口位置生成子弹 = function(owner:Object,props:Object):Void { BloodSwordLifecycleTest.bladeFrames.push(this.man._currentframe); };
        waveUnit.__titaniumType61 = {
            bindBloodPactAnimation:function(man:MovieClip):Boolean {
                BloodSwordLifecycleTest.bindCount++;
                BloodSwordLifecycleTest.bindProtection = man.无敌标签._parent === man;
                return true;
            },
            prepareBloodPactAttack:function(man:MovieClip,props:Object):Boolean { return true; },
            finishBloodPact:function(man:MovieClip,id:Number):Void { BloodSwordLifecycleTest.finishCount++; }
        };
        _root.子弹属性初始化 = function(marker:MovieClip,kind:String,owner:MovieClip):Object {
            return {sourceFrame:marker._parent._currentframe, sourceOwner:owner,
                bounds:marker.getBounds(_root.gameworld), 子弹种类:kind};
        };
        _root.战技路由 = {动画完毕:function(man:MovieClip,owner:MovieClip):Void {
            man.stop(); BloodSwordLifecycleTest.checkFullWave();
        }};
        waveUnit.attachMovie("战技容器-猩红天秤", "man", 1, {_xscale:27.69, _yscale:27.69});
        check(waveUnit.man._totalframes == 46, "已发布血浪容器为46帧；实际=" + waveUnit.man._totalframes
            + ", current=" + waveUnit.man._currentframe + ", loaded=" + waveUnit.man._framesloaded
            + ", path=" + waveUnit.man + ", url=" + loaded._url);
        watch.waitTicks = 0;
        watch.onEnterFrame = function():Void {
            if (++this.waitTicks >= 100) BloodSwordLifecycleTest.die("血浪时间轴未到达结束帧；frame="
                + BloodSwordLifecycleTest.waveUnit.man._currentframe + ", bind=" + BloodSwordLifecycleTest.bindCount);
        };
    }
    private static function checkFullWave():Void {
        check(bindProtection, "实际首帧绑定时已有无敌标签");
        check(bladeFrames.join(",") == "9,26", "实际SWF两次刀口发射帧");
        var frames:Array = []; var boundsValid:Boolean = true; var advancing:Boolean = true;
        for (var i:Number = 0; i < shots.length; i++) {
            var shot:Object = shots[i]; frames.push(shot.sourceFrame);
            var width:Number = shot.bounds.xMax - shot.bounds.xMin;
            boundsValid = boundsValid && shot.sourceOwner === waveUnit && width > 170 && width < 190
                && shot.子弹种类 == "近战联弹" && shot.霰弹值 == 5 && shot.最小霰弹值 == 3;
            if (i > 0) advancing = advancing && shot.bounds.xMin > shots[i - 1].bounds.xMin;
        }
        check(frames.join(",") == "26,29,32,35,38,41,44", "实际SWF仅七波判定，视觉不额外发射");
        check(boundsValid, "发射关键帧已有有效区域、联弹参数和发射者");
        check(advancing, "实际判定区域随血浪向前推进");
        check(waveUnit.hp == 1000 && waveUnit.mp == 100, "时间轴血爆血滴不自行扣除HP或MP");
        check(bindCount == 1 && finishCount == 1, "实际首尾只绑定及结束一次");
        check(effectFrames.join(",") == "44", "余波仅在最后44帧释放一次");
        check(lastTail._totalframes == 9 && lastTail._currentframe > 1 && lastTail._currentframe < 9 && lastTail._visible,
            "身体46帧结束后真实9帧余波仍在播放");
        check(lastTail._parent === waveAssets.效果, "余波挂在世界效果层而非身体动作");
        waveUnit.man.removeMovieClip(); shots = []; bladeFrames = [];
        waveUnit.attachMovie("战技容器-猩红天秤", "man", 1, {_xscale:27.69, _yscale:27.69});
        watch.waitTicks = 0; cancelledShots = -1;
        watch.onEnterFrame = function():Void {
            if (BloodSwordLifecycleTest.cancelledShots < 0 && BloodSwordLifecycleTest.waveUnit.man._currentframe >= 28) {
                BloodSwordLifecycleTest.cancelledShots = BloodSwordLifecycleTest.shots.length;
                BloodSwordLifecycleTest.check(BloodSwordLifecycleTest.cancelledShots == 1, "取消前仅第一浪已发射");
                BloodSwordLifecycleTest.waveUnit.man.removeMovieClip(); this.waitTicks = 0;
            }
            if (++this.waitTicks >= 60) BloodSwordLifecycleTest.die("取消样本未到达指定帧");
            if (BloodSwordLifecycleTest.cancelledShots >= 0 && this.waitTicks >= 12) {
                BloodSwordLifecycleTest.check(BloodSwordLifecycleTest.shots.length == BloodSwordLifecycleTest.cancelledShots
                    && BloodSwordLifecycleTest.finishCount == 1, "移除动作后无后续血浪、额外判定或迟到结束");
                BloodSwordLifecycleTest.check(BloodSwordLifecycleTest.effectFrames.join(",") == "44",
                    "44帧前取消不新增余波释放");
                BloodSwordLifecycleTest.checkTailPool();
            }
        };
    }
    private static function captureTail(kind:String,x:Number,y:Number,scaleX:Number,force:Boolean):MovieClip {
        effectFrames.push(waveUnit.man._currentframe);
        lastTail = EffectSystem.Effect(kind,x,y,scaleX,force);
        return lastTail;
    }
    private static function tailPoint(clip:MovieClip,x:Number,y:Number):Object {
        var point:Object = {x:x,y:y}; clip.localToGlobal(point); waveAssets.效果.globalToLocal(point); return point;
    }
    private static function near(a:Object,b:Object):Boolean {
        return Math.abs(a.x-b.x) < .15 && Math.abs(a.y-b.y) < .15;
    }
    private static function checkTailPool():Void {
        // 原70项取消用例已等候28+12帧，首个9帧余波应自然完成。
        var pool:Array = waveAssets.effectPools["特效-猩红天秤余波"];
        check(pool.length == 1 && pool[0] === lastTail && !lastTail._visible
            && EffectSystem.getCurrentEffectCount() == effectBaseline,
            "余波自然终帧回收且活动数恢复；pool=" + pool.length + ", count=" + EffectSystem.getCurrentEffectCount());
        var reused:MovieClip = EffectSystem.Effect("特效-猩红天秤余波",240,260,100,true);
        check(reused === lastTail && reused._visible && reused._currentframe == 1,
            "真实EffectSystem复用同一余波并恢复可见首帧");
        reused.removeMovieClip();
        startMirrorTail();
    }
    private static function startMirrorTail():Void {
        waveUnit._x = 240; waveUnit._y = 260;
        waveUnit._xscale = -82; waveUnit._yscale = 130; waveUnit._rotation = 11;
        shots = []; bladeFrames = []; effectFrames = [];
        _root.战技路由 = {动画完毕:function(man:MovieClip,owner:MovieClip):Void { man.stop(); }};
        waveUnit.attachMovie("战技容器-猩红天秤", "man", 1, {_xscale:27.69,_yscale:27.69});
        watch.waitTicks = 0;
        watch.onEnterFrame = function():Void {
            if (++this.waitTicks > 75) { BloodSwordLifecycleTest.die("44帧镜像余波样本超时"); return; }
            if (BloodSwordLifecycleTest.waveUnit.man._currentframe < 45) return;
            var man:MovieClip = BloodSwordLifecycleTest.waveUnit.man;
            var tail:MovieClip = BloodSwordLifecycleTest.lastTail;
            BloodSwordLifecycleTest.check(BloodSwordLifecycleTest.near(BloodSwordLifecycleTest.tailPoint(man,0,0),BloodSwordLifecycleTest.tailPoint(tail,0,0)),
                "镜像旋转父变换下余波世界注册点一致");
            BloodSwordLifecycleTest.check(BloodSwordLifecycleTest.near(BloodSwordLifecycleTest.tailPoint(man,100,0),BloodSwordLifecycleTest.tailPoint(tail,100,0))
                && BloodSwordLifecycleTest.near(BloodSwordLifecycleTest.tailPoint(man,0,100),BloodSwordLifecycleTest.tailPoint(tail,0,100)),
                "余波矩阵保留左向、非等比Y和父旋转");
            BloodSwordLifecycleTest.tailFrame = tail._currentframe;
            BloodSwordLifecycleTest.tailPosition = BloodSwordLifecycleTest.tailPoint(tail,0,0);
            man.removeMovieClip();
            BloodSwordLifecycleTest.waveUnit._x += 61; BloodSwordLifecycleTest.waveUnit._y += 31;
            this.waitTicks = 0;
            this.onEnterFrame = function():Void {
                if (++this.waitTicks != 2) return;
                BloodSwordLifecycleTest.check(BloodSwordLifecycleTest.lastTail._visible
                    && BloodSwordLifecycleTest.lastTail._currentframe > BloodSwordLifecycleTest.tailFrame
                    && BloodSwordLifecycleTest.near(BloodSwordLifecycleTest.tailPosition,BloodSwordLifecycleTest.tailPoint(BloodSwordLifecycleTest.lastTail,0,0)),
                    "44帧后删除动作并移动人物，余波固定世界位置继续收散");
                BloodSwordLifecycleTest.check(BloodSwordLifecycleTest.effectFrames.join(",") == "44" && BloodSwordLifecycleTest.shots.length == 7
                    && BloodSwordLifecycleTest.bladeFrames.join(",") == "9,26", "最后一波后取消不补发攻击或尾迹");
                this.waitTicks = 0;
                this.onEnterFrame = function():Void {
                    if (++this.waitTicks < 12) return;
                    var pool:Array = BloodSwordLifecycleTest.waveAssets.effectPools["特效-猩红天秤余波"];
                    BloodSwordLifecycleTest.check(pool.length == 1 && pool[0] === BloodSwordLifecycleTest.lastTail
                        && !BloodSwordLifecycleTest.lastTail._visible, "取消后的余波仍完成自身9帧并回收");
                    BloodSwordLifecycleTest.startNullTail();
                };
            };
        };
    }
    private static function startNullTail():Void {
        waveUnit._x = 240; waveUnit._y = 260; waveUnit._xscale = 100; waveUnit._yscale = 100; waveUnit._rotation = 0;
        shots = []; bladeFrames = []; effectFrames = [];
        _root.效果 = function(kind:String,x:Number,y:Number,scaleX:Number,force:Boolean):MovieClip {
            BloodSwordLifecycleTest.effectFrames.push(BloodSwordLifecycleTest.waveUnit.man._currentframe); return null;
        };
        waveUnit.attachMovie("战技容器-猩红天秤", "man", 1, {_xscale:27.69,_yscale:27.69});
        watch.waitTicks = 0;
        watch.onEnterFrame = function():Void {
            if (++this.waitTicks > 90) { BloodSwordLifecycleTest.die("空余波返回样本超时"); return; }
            if (BloodSwordLifecycleTest.waveUnit.man._currentframe < 46) return;
            BloodSwordLifecycleTest.check(BloodSwordLifecycleTest.effectFrames.join(",") == "44", "余波剔除null分支仅44帧请求一次");
            var frames:Array = [];
            for (var i:Number=0;i<BloodSwordLifecycleTest.shots.length;i++) frames.push(BloodSwordLifecycleTest.shots[i].sourceFrame);
            BloodSwordLifecycleTest.check(BloodSwordLifecycleTest.bladeFrames.join(",") == "9,26" && frames.join(",") == "26,29,32,35,38,41,44",
                "余波返回null不吞末波或其它既有攻击");
            var active:MovieClip = EffectSystem.Effect("特效-猩红天秤余波",240,260,100,true);
            this.unloadWasActive = active._parent === BloodSwordLifecycleTest.waveAssets.效果;
            this.unloadActive = active; this.unloadPath = active._target;
            this.unloadWorld = BloodSwordLifecycleTest.waveAssets;
            this.unloadDepth = BloodSwordLifecycleTest.waveAssets.getDepth(); this.unloadName = BloodSwordLifecycleTest.waveAssets._name;
            BloodSwordLifecycleTest.waveAssets.removeMovieClip(); this.waitTicks = 0;
            this.onEnterFrame = function():Void {
                if (++this.waitTicks == 1) { this.unloadFrame = this.unloadActive._currentframe; return; }
                var reachable:Object = BloodSwordLifecycleTest.resolveDisplayPath(this.unloadPath);
                var depthOwner:MovieClip = _root.getInstanceAtDepth(this.unloadDepth);
                BloodSwordLifecycleTest.check(this.unloadWasActive && reachable == undefined && depthOwner !== this.unloadWorld
                    && _root[this.unloadName] !== this.unloadWorld && this.unloadActive._currentframe == this.unloadFrame,
                    "世界卸载后余波路径不可达且停止推进；path=" + this.unloadPath + ", resolved=" + reachable
                    + ", depthOwner=" + depthOwner + ", frames=" + this.unloadFrame + "/" + this.unloadActive._currentframe);
                BloodSwordLifecycleTest.finish();
            };
        };
    }
    private static function resolveDisplayPath(path:String):Object {
        var segments:Array = path.split("/"); var found:Object = _root;
        for (var i:Number=0;i<segments.length;i++) if (segments[i] != "") found = found[segments[i]];
        return found;
    }
    private static function finish():Void {
        if (finished) return; finished = true;
        delete watch.onEnterFrame;
        if (unit) { DressupInitializer.teardownLifeCycles(unit); unit.dispatcher.destroy(); }
        if (loader) loader.removeListener(listener);
        container.removeMovieClip(); waveAssets.removeMovieClip(); watch.removeMovieClip();
        _root.帧计时器 = oldClock; _root.装备生命周期函数.移除异常周期函数 = oldCleanup;
        _root.子弹区域shoot传递 = oldShoot; _root.gameworld = oldWorld;
        _root.子弹属性初始化 = oldBulletInit; _root.战技路由 = oldSkillRoute;
        _root.效果 = oldEffect;
        trace("BloodSwordLifecycleTest Tests Passed: " + passed);
        trace("BloodSwordLifecycleTest Tests Failed: " + failed);
        _root.bloodSwordFocusedComplete();
    }
}
