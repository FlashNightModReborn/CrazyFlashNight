import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.*;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.unit.Action.Melee.BladeShootCore;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;

/** 原版真实素材、生产生命周期、三刀口碰撞与切换回收的隔离夹具。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PileBunkerClassicTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var finished:Boolean;
    private static var loaded:MovieClip;
    private static var watchdog:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;
    private static var item:Object;
    private static var unit:MovieClip;
    private static var gun:MovieClip;
    private static var blade:MovieClip;
    private static var ref:Object;
    private static var controller:PileBunkerClassicController;
    private static var queued:Object;
    private static var saved:Object;
    private static var bullets:Array;
    private static var donor:Object;
    private static var time:Number;
    private static var calls:Number;
    private static var subscriptions:Number;
    private static var originalBlade:flash.geom.Matrix;
    private static var originalGun:flash.geom.Matrix;

    private static function check(value:Boolean, name:String):Void {
        if (value) passed++;
        else { failed++; trace("[FAIL] PileBunkerClassicTest: " + name); }
    }
    private static function close(a:Number,b:Number):Boolean { return Math.abs(a-b) < .06; }
    private static function sameMatrix(a:flash.geom.Matrix,b:flash.geom.Matrix):Boolean {
        return close(a.a,b.a) && close(a.b,b.b) && close(a.c,b.c) && close(a.d,b.d) && close(a.tx,b.tx) && close(a.ty,b.ty);
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; finished = false; time = 0; calls = 0;
        bullets = []; donor = {power:130,actiontype:"狂野"};
        saved = {clock:_root.帧计时器,knife:_root.刀配置,shoot:_root.子弹区域shoot传递,
            cleanup:_root.装备生命周期函数.移除异常周期函数,world:_root.gameworld,
            control:_root.控制目标,players:_root.当前玩家总数,paused:_root.暂停};
        _root.当前玩家总数 = 1; _root.暂停 = false;
        _root.帧计时器 = {当前帧数:0,taskManager:{addLifecycleTask:function(owner:Object,label:String,callback:Function,interval:Number,args:Array):Number {
            PileBunkerClassicTest.queued = {owner:owner,callback:callback,args:args}; return 7006;
        }},移除生命周期任务:function():Void {}};
        _root.装备生命周期函数.移除异常周期函数 = function():Void {};
        _root.刀配置 = function(name:String,weapon:String,level:Number):Void {
            PileBunkerClassicTest.calls++;
            var owner:MovieClip = _root.gameworld[name];
            owner.刀 = {name:weapon,value:{level:level,mods:[]}};
            owner.刀属性 = PileBunkerClassicTest.donor;
            owner.刀数据 = {data:{power:130,actiontype:"狂野"}};
        };
        _root.子弹区域shoot传递 = function(value:Object):Void {
            var copy:Object = {};
            for (var key:String in value) copy[key] = value[key];
            PileBunkerClassicTest.bullets.push(copy);
        };
        loaded = _root.createEmptyMovieClip("__pileClassicAssets",_root.getNextHighestDepth());
        watchdog = _root.createEmptyMovieClip("__pileClassicWatchdog",_root.getNextHighestDepth());
        watchdog.count = 0;
        watchdog.onEnterFrame = function():Void {
            if (++this.count > 300) { PileBunkerClassicTest.check(false,"素材加载超时"); PileBunkerClassicTest.finish(); }
        };
        var document:XML = new XML(); document.ignoreWhite = true;
        document.onLoad = function(success:Boolean):Void {
            if (!success) { PileBunkerClassicTest.check(false,"真实物品XML加载"); PileBunkerClassicTest.finish(); return; }
            var values:Object = XMLParser.parseXMLNode(this.firstChild);
            for (var i:Number = 0; i < values.item.length; i++) {
                if (values.item[i].name == "火药燃气液压打桩机") PileBunkerClassicTest.item = values.item[i];
            }
            PileBunkerClassicTest.check(PileBunkerClassicTest.item != null,"唯一原版物品入口");
            PileBunkerClassicTest.loadAssets();
        };
        document.load("../data/items/武器_长枪_近战.xml");
    }
    private static function loadAssets():Void {
        loader = new MovieClipLoader(); listener = {};
        listener.onLoadInit = function(asset:MovieClip):Void { PileBunkerClassicTest.runLoaded(asset); };
        listener.onLoadError = function():Void { PileBunkerClassicTest.check(false,"原版SWF加载"); PileBunkerClassicTest.finish(); };
        loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/fs配置素材.swf",loaded),"提交未改动的原版素材加载");
    }
    private static function configure(withKnife:Boolean):Void {
        unit = loaded.createEmptyMovieClip("classicActor",loaded.getNextHighestDepth());
        var slots:Array = ["头部装备","上装装备","下装装备","手部装备","脚部装备","颈部装备","长枪","手枪","手枪2","刀","手雷"];
        for (var i:Number = 0; i < slots.length; i++) unit[slots[i]] = null;
        unit.version = 1; unit.hp = 1000; unit.mp = 123; unit.攻击模式 = "兵器";
        unit.状态 = "兵器站立"; unit.Z轴坐标 = 0; unit.syncRefs = {}; unit.生命周期函数列表 = [];
        unit.主动战技 = {长枪:{名字:"保留槽位"}};
        unit.长枪 = new BaseItem(item.name,{level:3,shot:2,mods:[]},0);
        unit.长枪数据 = item; unit.长枪属性 = ObjectUtil.clone(item.data);
        // 上游装备结算结果：本控制器只投影一次，不再运行配件或全身防护计算。
        unit.长枪属性.vampirism = 7; unit.长枪属性.slay = 4;
        unit.长枪属性.poison = 5; unit.长枪属性.rout = 2;
        unit.长枪属性.accuracy = 30; unit.长枪属性.criticalhit = "测试暴击";
        unit.长枪_装扮 = item.data.dressup; unit.长枪弹匣容量 = item.data.capacity;
        unit.dispatcher = new EventDispatcher();
        unit.根据模式重新读取武器加成 = _root.主角函数.根据模式重新读取武器加成;
        var zeros:Array = ["基础毒","基础吸血","基础击溃","基础斩杀","基础命中加成","装备刀锋利度加成",
            "hp满血值装备加层","mp满血值装备加层","装备防御力","伤害加成","内力","装备枪械威力加成",
            "空手攻击力","佣兵技能概率抑制基数","韧性加成","闪避加成","懒闪避",
            "兵器毒","兵器吸血","兵器击溃","兵器斩杀","兵器命中加成"];
        for (i = 0; i < zeros.length; i++) unit[zeros[i]] = 0;
        unit.基础命中率 = 100; unit.基础伤害类型 = "物理"; unit.兵器伤害类型 = "物理";
        unit.兵器魔法伤害属性 = null; unit.兵器暴击 = null; unit.兵器动作类型 = "普通";
        if (withKnife) { unit.刀 = {name:"真实刀",value:{level:1}}; unit.兵器吸血 = 9; unit.兵器斩杀 = 6; }
        var api = org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        api["updateProperty"](unit,"长枪",unit.长枪属性); unit.装备刀锋利度加成 = 17;
        unit.基础吸血 = 2; unit.基础斩杀 = 1;
        unit.根据模式重新读取武器加成(unit.攻击模式);
        unit.man = unit.createEmptyMovieClip("man",unit.getNextHighestDepth());
        var outer:MovieClip = unit.man.createEmptyMovieClip("枪",unit.man.getNextHighestDepth());
        var inner:MovieClip = outer.createEmptyMovieClip("枪",outer.getNextHighestDepth());
        gun = DressupReferenceManager.attach(inner,item.data.dressup,"装扮","长枪_引用");
        outer = unit.man.createEmptyMovieClip("刀",unit.man.getNextHighestDepth());
        inner = outer.createEmptyMovieClip("刀",outer.getNextHighestDepth());
        blade = DressupReferenceManager.attach(inner,item.data.dressup,"装扮","刀_引用");
        check(gun.动画._totalframes >= 60 && blade.刀口位置1 == undefined,"原版仍使用旧枪动画且没有烘焙刀口");
        originalBlade = blade.动画.transform.matrix; originalGun = gun.动画.transform.matrix;
        unit.刀口位置生成子弹 = BladeShootCore.shoot;
        DressupInitializer.updateActions(unit,true);
        _root.控制目标 = unit._name;
        RuntimeEquipmentProjection.beginCanonical(unit);
        subscriptions = unit.dispatcher["_subCount"];
        unit.装载生命周期函数 = _root.主角函数.装载生命周期函数;
        unit.装载生命周期函数(item.lifecycle,"长枪");
        ref = queued.args[0]; controller = ref.classicPileBunkerController;
        DressupInitializer.validateAttackMode(unit);
        check(RuntimeEquipmentProjection.completeCanonical(unit),"原版生命周期提交canonical");
    }
    private static function tick():Void {
        _root.帧计时器.当前帧数 = ++time;
        queued.callback.apply(queued.owner,queued.args);
    }
    private static function runLoaded(asset:MovieClip):Void {
        delete watchdog.onEnterFrame; _root.gameworld = asset;
        try {
            check(item.data.reloadPenalty == 200 && item.lifecycle.attr_0.init.initParam.bladePower == 590,"XML绑定590锋利度与+200%换弹");
            check(item.skill == undefined && item.lifecycle.attr_0.init.initParam.flamethrower == undefined,"原版不自动获得进阶技能或燃料系统");
            configure(false);
            check(unit.攻击模式 == "兵器" && unit.兵器动作类型 == "狂野" && unit.刀 === unit.长枪,"切关初始化保留兵器模式并借用空刀槽");
            check(unit.刀属性.power == Math.floor(590*EquipmentConfigManager.getLevelMultiplier(3))+17,"强化倍率及全身锋利度各计算一次");
            check(donor.power == 130 && unit.刀属性 !== donor,"公共吉他供体不被覆写");
            check(unit.兵器吸血 == 7 && unit.兵器斩杀 == 4 && unit.刀属性.vampirism == 7,"已结算词条投影到锤且不重复叠加");
            check(unit.主动战技.长枪.名字 == "保留槽位" && unit.长枪副武器状态 == undefined,"不覆盖F槽、不创建副弹仓");
            check(controller.syncVisual() && controller.getSnapshot().geometryReady,"实际刀装扮首次绑定三个有效判定区");
            var turn:flash.geom.Matrix = new flash.geom.Matrix(); turn.rotate(Math.PI/2);
            var expected:flash.geom.Matrix = originalBlade.clone(); expected.concat(turn);
            check(sameMatrix(blade.动画.transform.matrix,expected) && sameMatrix(gun.动画.transform.matrix,originalGun),"只对刀装扮旋转90度，枪装扮保持原矩阵");
            check(!gun.动画._visible && blade.动画._visible,"兵器模式显示锤并隐藏背枪动画");
            for (var i:Number = 1; i <= 3; i++) {
                var marker:MovieClip = blade["刀口位置"+i]; var rect:Object = marker.getRect(marker);
                check(close(rect.xMax-rect.xMin,40) && close(rect.yMax-rect.yMin,100) && marker._alpha == 0,"刀口"+i+"有真实40x100面积且不显示色块");
            }
            var face:Object = controller.getSnapshot().face;
            check(close(blade.刀口位置2._x,-face.y) && close(blade.刀口位置2._y,face.x),"中央刀口跟随原素材实体前端旋转");
            testCollision();
            var matrix:flash.geom.Matrix = blade.动画.transform.matrix;
            var power:Number = unit.刀属性.power;
            for (i = 0; i < 20; i++) { unit.攻击模式 = i%2 ? "兵器" : "长枪"; controller.syncVisual(); }
            check(sameMatrix(blade.动画.transform.matrix,matrix) && unit.刀属性.power == power && unit.兵器吸血 == 7,"反复切换不累乘矩阵、锋利度或词条");
            unit.攻击模式 = "长枪"; controller.syncVisual();
            check(gun.动画._visible && !blade.动画._visible,"回枪模式恢复旧动画显示");
            unit.dispatcher.publish("长枪射击",unit); tick();
            // 现役FSM在同一tick进入ACTIVE后继续onAction：进入帧2，再自增到首个写回帧3。
            check(ref.fsm.data.currentframe == 3 && gun.动画._currentframe == 3,"原版开火保留进入2再同帧推进到3的既有顺序");
            for (i = 0; i < 57; i++) tick();
            check(ref.fsm.data.currentframe == 60 && gun.动画._currentframe == 60,"原版开火推进到第60帧");
            tick(); tick(); check(ref.fsm.data.currentframe == 1 && gun.动画._currentframe == 1,"原版收枪循环恢复首帧");
            testReplacement();
            unit.兵器吸血 = 77;
            DressupInitializer.teardownLifeCycles(unit);
            check(!controller.isCurrent() && unit.__pileBunkerClassic == undefined && unit.刀 == null,"卸载归还空刀槽并释放控制器");
            check(unit.刀口位置生成子弹 === BladeShootCore.shoot && unit.dispatcher["_subCount"] == subscriptions,"卸载精确恢复入口和订阅");
            check(blade.刀口位置1 == undefined && sameMatrix(blade.动画.transform.matrix,originalBlade),"卸载移除本人判定片并恢复原装扮矩阵");
            check(unit.兵器吸血 == 77 && unit.兵器斩杀 == 0,"卸载恢复自有字段，保留后来接管的词条");
            unit.长枪 = null; unit.攻击模式 = "兵器"; DressupInitializer.validateAttackMode(unit);
            check(unit.攻击模式 == "空手","卸枪后无刀回到合法空手模式");
            unit.dispatcher.destroy(); unit.removeMovieClip();
            var previousCalls:Number = calls; configure(true);
            check(!controller.ownsBlade() && unit.刀.name == "真实刀" && calls == previousCalls,"真实刀槽不被原版锤覆盖");
            check(unit.兵器吸血 == 9 && unit.兵器斩杀 == 6 && unit.刀口位置生成子弹 === BladeShootCore.shoot,"真实刀词条和发射入口保留");
            DressupInitializer.teardownLifeCycles(unit);
            check(unit.刀.name == "真实刀","卸载保留真实刀");
        } catch(error) { check(false,"意外异常 " + error); }
        finish();
    }
    private static function testCollision():Void {
        var props:Object = {子弹威力:777,伤害类型:"魔法",魔法伤害属性:"火"};
        var savedMatrix:flash.geom.Matrix = unit.transform.matrix;
        var hp:Number = unit.hp; var defence:Number = unit.装备防御力;
        for (var facing:Number = 0; facing < 2; facing++) {
            unit._x = 140; unit._y = 180; unit._xscale = facing == 0 ? 75 : -75; unit._yscale = 75; unit._rotation = 17;
            var start:Number = bullets.length;
            unit.刀口位置生成子弹(unit,props);
            check(bullets.length == start+3,"镜像"+facing+"真实刀口核心恰发三次");
            for (var i:Number = start; i < bullets.length; i++) {
                var bullet:Object = bullets[i]; var area:MovieClip = bullet.区域定位area;
                var rect:Object = area.getRect(_root.gameworld);
                BulletInitializer.initializeBulletProperties(bullet);
                var collider = new AABBCollider(0,0,0,0); collider.updateFromBullet(bullet,bullet.子弹区域area);
                var cx:Number = (rect.xMin+rect.xMax)*.5; var cy:Number = (rect.yMin+rect.yMax)*.5;
                check(collider.checkCollision(AABBCollider.fromCenter(cx,cy,1,1),0).isColliding
                    && !collider.checkCollision(AABBCollider.fromCenter(rect.xMax+100,cy,1,1),0).isColliding,"镜像旋转后的锤面内可命中，面外拒绝");
                check(bullet.伤害类型 == "物理" && bullet.魔法伤害属性 == "" && bullet.子弹威力 == 777
                    && bullet.吸血 == 9 && bullet.斩杀 == 5 && bullet.毒 == 5 && bullet.血量上限击溃 == 2,"物理普通锤继承本装配词条及基础加成一次");
            }
        }
        check(unit.mp == 123 && unit.长枪.value.shot == 2 && unit.hp == hp && unit.装备防御力 == defence,"普通挥锤不耗MP、弹药，不重复增加生命防御");
        check(props.伤害类型 == "魔法" && props.魔法伤害属性 == "火" && props.吸血 == undefined,"单次物理投影不污染原始攻击参数");
        unit.transform.matrix = savedMatrix;
        unit.攻击模式 = "手枪"; unit.根据模式重新读取武器加成("手枪");
        unit.man.兵器使用标签 = true; unit.刀口位置生成子弹(unit,props);
        check(bullets[bullets.length-1].吸血 == 9 && bullets[bullets.length-1].斩杀 == 5,"其他模式临时借刀技能仍继承打桩机词条");
        delete unit.man.兵器使用标签; unit.攻击模式 = "兵器";
        var count:Number = bullets.length; unit.man.换弹标签 = true; unit.刀口位置生成子弹(unit,props);
        check(bullets.length == count,"换弹期间不旁路发出普通锤"); delete unit.man.换弹标签;
    }
    private static function testReplacement():Void {
        var token:Object = blade.__pileBunkerClassicOwner;
        var parent:MovieClip = blade._parent; blade.removeMovieClip();
        blade = DressupReferenceManager.attach(parent,item.data.dressup,"装扮","刀_引用");
        controller.syncVisual();
        check(blade.__pileBunkerClassicOwner !== token && blade.刀口位置3 != undefined,"同路径装扮重建使用新持有者及判定片");
        var rotated:flash.geom.Matrix = originalBlade.clone(); var turn:flash.geom.Matrix = new flash.geom.Matrix(); turn.rotate(Math.PI/2); rotated.concat(turn);
        check(sameMatrix(blade.动画.transform.matrix,rotated),"同路径重建不叠加上一装扮的旋转");
    }
    private static function finish():Void {
        if (finished) return; finished = true;
        if (controller) controller.dispose();
        if (unit) { unit.dispatcher.destroy(); unit.removeMovieClip(); }
        delete watchdog.onEnterFrame; loader.removeListener(listener); loaded.removeMovieClip(); watchdog.removeMovieClip();
        _root.帧计时器 = saved.clock; _root.刀配置 = saved.knife; _root.子弹区域shoot传递 = saved.shoot;
        _root.装备生命周期函数.移除异常周期函数 = saved.cleanup; _root.gameworld = saved.world;
        _root.控制目标 = saved.control; _root.当前玩家总数 = saved.players; _root.暂停 = saved.paused;
        trace("PileBunkerClassicTest Tests Passed: " + passed);
        trace("PileBunkerClassicTest Tests Failed: " + failed);
        _root.pileBunkerClassicFocusedComplete();
    }
}
