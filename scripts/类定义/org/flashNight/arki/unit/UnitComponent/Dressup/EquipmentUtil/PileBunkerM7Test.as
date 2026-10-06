import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.*;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.equipment.TierSystem;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;
import org.flashNight.arki.unit.Action.Shoot.ShootCore;
import org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Melee.BladeShootCore;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletHitEffectRegistry;
import org.flashNight.arki.component.Damage.UniversalDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.item.equipment.EquipmentCalculator;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.component.Damage.LifeStealDamageHandle;
import org.flashNight.arki.component.Damage.ExecuteDamageHandle;
import org.flashNight.arki.component.Damage.DamageCalculator;
import org.flashNight.arki.component.Shield.AdaptiveShield;

/** 真实MovieClip、生产生命周期、射击核心与近战发射链的隔离回归。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PileBunkerM7Test {
    private static var passed:Number;
    private static var failed:Number;
    private static var finished:Boolean;
    private static var loaded:MovieClip;
    private static var watchdog:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;
    private static var itemConfig:Object;
    private static var unit:MovieClip;
    private static var gun:MovieClip;
    private static var blade:MovieClip;
    private static var ref:Object;
    private static var controller:PileBunkerM7Controller;
    private static var queued:Object;
    private static var oldClock:Object;
    private static var oldInput:Function;
    private static var oldKnife:Function;
    private static var oldShoot:Function;
    private static var oldCleanup:Function;
    private static var oldWorld:MovieClip;
    private static var oldControl:String;
    private static var oldRootMode:String;
    private static var oldPlayers:Number;
    private static var oldPaused:Boolean;
    private static var held:Boolean;
    private static var emitted:Number;
    private static var knifeConfigCalls:Number;
    private static var attackCalls:Number;
    private static var time:Number;
    private static var lastPower:Number;
    private static var lastSplit:Number;
    private static var lastArea:MovieClip;
    private static var lastAreaBounds:Object;
    private static var props:Object;
    private static var baselineSubscriptions:Number;
    private static var poseData:Object;
    private static var poseLease:Object;
    private static var posePath:String;
    private static var canceledCallback:Boolean;
    private static var knifeDonor:Object;
    private static var effects:Array;
    private static var lastBullet:Object;
    private static var oldWeaponRoute:Object;
    private static var routedSkill:String;
    private static var fxLibrary:MovieClip;
    private static var fxLoader:MovieClipLoader;
    private static var fxListener:Object;
    private static var liveEffects:Array;

    private static function check(value:Boolean, name:String):Void {
        if (value) passed++;
        else { failed++; trace("[FAIL] PileBunkerM7Test: " + name); }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; finished = false; held = false;
        emitted = 0; knifeConfigCalls = 0; attackCalls = 0; time = 0;
        queued = null; ref = null; controller = null;
        posePath = "data/weapon-animations/pilebunker-m7.json";
        canceledCallback = false;
        knifeDonor = {power:130,actiontype:"狂野"};
        effects = []; liveEffects = []; routedSkill = "";
        oldWeaponRoute = _root.战技路由;
        // 本夹具验证 F 槽、扣费和路由请求；完整角色动作仍由现役战技容器负责。
        _root.战技路由 = {战技标签跳转_旧:function(owner:MovieClip,name:String):Void {
            PileBunkerM7Test.routedSkill = name; owner.技能名 = name; owner.状态 = "战技";
        }};
        check(NamedPoseDataStore.inspect(posePath).status == "absent","未装备时不读取或驻留姿态数据");
        oldClock = _root.帧计时器; oldInput = _root.按键输入检测;
        oldKnife = _root.刀配置; oldShoot = _root.子弹区域shoot传递;
        oldCleanup = _root.装备生命周期函数.移除异常周期函数;
        oldWorld = _root.gameworld; oldControl = _root.控制目标;
        oldRootMode = _root.攻击模式; oldPlayers = _root.当前玩家总数; oldPaused = _root.暂停;
        _root.当前玩家总数 = 1; _root.暂停 = false;
        _root.帧计时器 = {当前帧数:0,taskManager:{addLifecycleTask:function(owner:Object,label:String,callback:Function,interval:Number,args:Array):Number {
            PileBunkerM7Test.queued = {owner:owner,callback:callback,args:args}; return 7007;
        }},移除生命周期任务:function():Void {},添加冷却任务:function():Void {}};
        _root.按键输入检测 = function():Boolean { return PileBunkerM7Test.held; };
        _root.装备生命周期函数.移除异常周期函数 = function():Void {};
        _root.刀配置 = function(name:String, donor:String, tier:Number):Void {
            PileBunkerM7Test.knifeConfigCalls++;
            var owner:MovieClip = _root.gameworld[name];
            owner.刀 = {name:donor,value:{level:tier,mods:[]}};
            owner.刀属性 = PileBunkerM7Test.knifeDonor;
            owner.刀数据 = {data:{power:130,actiontype:"狂野"}};
        };
        _root.子弹区域shoot传递 = function(bullet:Object):Void {
            var copy:Object = {};
            for (var key:String in bullet) copy[key] = bullet[key];
            if (bullet.子弹种类 != "近战联弹" && bullet.子弹种类 != "近战子弹") {
                PileBunkerM7Test.effects.push(copy); return;
            }
            PileBunkerM7Test.emitted++;
            PileBunkerM7Test.lastBullet = copy;
            PileBunkerM7Test.lastPower = bullet.子弹威力;
            PileBunkerM7Test.lastSplit = bullet.霰弹值;
            PileBunkerM7Test.lastArea = bullet.区域定位area;
            PileBunkerM7Test.lastAreaBounds = bullet.区域定位area.getRect(_root.gameworld);
        };
        loaded = _root.createEmptyMovieClip("__pileM7Assets",_root.getNextHighestDepth());
        watchdog = _root.createEmptyMovieClip("__pileM7Watchdog",_root.getNextHighestDepth());
        watchdog.count = 0;
        watchdog.onEnterFrame = function():Void {
            if (++this.count > 300) { PileBunkerM7Test.check(false,"素材加载超时"); PileBunkerM7Test.finish(); }
        };
        var document:XML = new XML(); document.ignoreWhite = true;
        document.onLoad = function(success:Boolean):Void {
            if (!success) { PileBunkerM7Test.check(false,"真实物品XML加载"); PileBunkerM7Test.finish(); return; }
            var values:Object = XMLParser.parseXMLNode(this.firstChild);
            for (var i:Number = 0; i < values.item.length; i++) {
                if (values.item[i].name == "火药燃气液压打桩机") PileBunkerM7Test.itemConfig = values.item[i];
            }
            PileBunkerM7Test.check(PileBunkerM7Test.itemConfig != null,"原版物品仍是试跑入口");
            var raw:Object = PileBunkerM7Test.itemConfig;
            PileBunkerM7Test.check(raw.data.weight == 80 && raw.data.dressup == "枪-长枪-火药燃气液压打桩机"
                && raw.skill == undefined && raw.lifecycle.attr_0.init.initRoutines == "火药燃气液压打桩机初始化","基础物品恢复原版外观、生命周期并保留身份");
            var effective:Object = ObjectUtil.clone(raw);
            TierSystem.applyTierData(effective,"重锤",{tierNameToKeyDict:{重锤:"data_pilebunker_m7"},defaultTierDataDict:{}});
            PileBunkerM7Test.check(effective.name == raw.name && effective.displayname == "重锤燃气打桩机"
                && effective.data.level == 55 && effective.data.weight == 150,"真实TierSystem在同一物品身份应用55级重锤进阶");
            PileBunkerM7Test.check(raw.data.weight == 80 && raw.data_pilebunker_m7.weight == 150,"进阶展开不污染基础物品源数据");
            PileBunkerM7Test.itemConfig = effective;
            PileBunkerM7Test.loadPluginDefinitions();
        };
        document.load("../data/items/武器_长枪_近战.xml");
    }

    private static function loadPluginDefinitions():Void {
        var document:XML = new XML(); document.ignoreWhite = true;
        document.onLoad = function(success:Boolean):Void {
            if (!success) { PileBunkerM7Test.check(false,"真实插件XML加载"); PileBunkerM7Test.finish(); return; }
            var values:Object = XMLParser.parseXMLNode(this.firstChild);
            ModRegistry.loadModData(values.mod);
            PileBunkerM7Test.check(ModRegistry.getModData("动力液压杆") != null && ModRegistry.getModData("绯红忆弦轮") != null,"真实斩杀/吸血插件进入生产注册表");
            PileBunkerM7Test.loadPoses();
        };
        document.load("../data/items/equipment_mods/高等材料_通用.xml");
    }

    private static function loadPoses():Void {
        check(itemConfig.lifecycle.attr_0.init.initParam.poseData == posePath,"物品明确声明按需姿态文件");
        poseLease = NamedPoseDataStore.acquire(posePath,function(data:Object):Void {
            PileBunkerM7Test.poseData = data;
            PileBunkerM7Test.check(!PileBunkerM7Test.canceledCallback,"已释放请求不消费迟到的JSON");
            PileBunkerM7Test.testData();
            PileBunkerM7Test.loadAssets();
        },function(error:String):Void {
            PileBunkerM7Test.check(false,"真实JSON读取失败 " + error); PileBunkerM7Test.finish();
        });
        var canceled:Object = NamedPoseDataStore.acquire(posePath,function():Void {
            PileBunkerM7Test.canceledCallback = true;
        },function():Void { PileBunkerM7Test.canceledCallback = true; });
        check(NamedPoseDataStore.inspect(posePath).refs == 2,"同时请求共享同一加载事务");
        NamedPoseDataStore.release(canceled);
        check(NamedPoseDataStore.inspect(posePath).refs == 1,"释放未完成请求立即解绑");
    }

    private static function testData():Void {
        var data:Object = poseData;
        var same:Boolean = false;
        var shared:Object = NamedPoseDataStore.acquire(posePath,function(other:Object):Void { same = other === data; },function():Void {});
        check(same,"已读取数据共享同一份对象，不重复解析");
        NamedPoseDataStore.release(shared);
        check(data.targets.length == 93 && data.poses.length == 417,"外置JSON完整姿态无丢失");
        check(data.matrices.length == 3795 && data.states.length == 5711,"矩阵和状态数量");
        var enter:Object = NamedPosePlayer.composePath(data,[{clip:"charge"},{clip:"hammer_enter"}],15);
        check(enter.poses.length == 15 && enter.poses[0] == data.clips.idle.frames[0],"冷态入锤15帧与首姿态");
        check(enter.poses[14] == data.clips.hammer_hold.frames[0],"冷态入锤终点锁定");
        var leave:Object = NamedPosePlayer.composePath(data,[{clip:"hammer_exit"},{clip:"cancel_ready"}],15);
        check(leave.poses[0] == data.clips.hammer_hold.frames[0] && leave.poses[14] == data.clips.idle.frames[0],"出锤链完整回普通枪态");
        check(NamedPosePlayer.composePath(data,[{clip:"missing"}],15) == null,"缺失动作拒绝且不进入NaN循环");
        check(NamedPosePlayer.composePath(data,[{clip:"charge",from:-1}],15) == null,"非法源帧拒绝");
        check(NamedPosePlayer.composePath(data,[{clip:"charge"}],Number("bad")) == null,"非法预算拒绝");
        var release:Object = NamedPosePlayer.composePath(data,[{clip:"N1"}],57);
        check(release.poses[0] == data.clips.N1.frames[0] && release.poses[1] == data.clips.N1.frames[1],"蓄力击发首两帧不丢失");
    }
    private static function loadAssets():Void {
        loader = new MovieClipLoader(); listener = {};
        listener.onLoadInit = function(asset:MovieClip):Void { PileBunkerM7Test.runLoaded(asset); };
        listener.onLoadError = function():Void { PileBunkerM7Test.check(false,"真实SWF加载"); PileBunkerM7Test.finish(); };
        loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/Codex专用素材.swf",loaded),"提交真实CS6素材加载");
    }

    private static function runLoaded(asset:MovieClip):Void {
        delete watchdog.onEnterFrame;
        try {
            _root.gameworld = asset;
            gun = asset.attachMovie("枪-长枪-Codex-打桩机M7","liveGun",asset.getNextHighestDepth());
            blade = asset.attachMovie("枪-长枪-Codex-打桩机M7","liveBlade",asset.getNextHighestDepth());
            check(gun.动画._totalframes == 1 && blade.动画._totalframes == 1,"真实单帧接入总装");
            check(Math.abs(gun.枪口位置._x - 424.1) < .051 && Math.abs(gun.枪口位置._y - 6.45) < .051,"素材保留原始接口，装备生命周期负责运行时枪口定位");
            check(blade.刀口位置1 != undefined && blade.刀口位置3 != undefined,"三处近战判定接口");
            testNativePoses();
            configureUnit(asset,false);
            testChargeAndFire();
            testBurstAmmunition();
            testGunRegions();
            testFuelModes();
            testHammerFuelWindow();
            testFormsAndMarkers();
            testBoundaryRecovery();
            testTransitionMeleeMode(asset);
            testHammerPluginProjection(asset);
            testCleanupAndRealBlade(asset);
        } catch (error) { check(false,"意外异常 " + error); }
        loadLiveEffects();
    }

    private static function testNativePoses():Void {
        var data:Object = poseData;
        var player:NamedPosePlayer = new NamedPosePlayer(data);
        check(player.bind(gun.动画),"93个真实命名对象全部绑定");
        var identities:Array = [];
        for (var i:Number = 0; i < data.targets.length; i++) identities[i] = gun.动画[data.targets[i].name];
        var allMatrices:Boolean = true;
        var allIdentities:Boolean = true;
        var frames:Number = 0;
        for (var name:String in data.clips) {
            var clip:Object = data.clips[name];
            for (var f:Number = 0; f < clip.frames.length; f++) {
                var pid:Number = clip.frames[f];
                if (!player.applyPose(pid)) allMatrices = false;
                for (i = 0; i < data.targets.length; i++) {
                    var node:MovieClip = gun.动画[data.targets[i].name];
                    if (node !== identities[i]) allIdentities = false;
                    var state:String = data.states[data.poses[pid].charCodeAt(i)-1];
                    var matrix:String = data.matrices[state.charCodeAt(1)-1];
                    var values:Array = [];
                    for (var component:Number = 0; component < 6; component++) values.push(data.numbers[matrix.charCodeAt(component)-1]);
                    var actual:Object = node.transform.matrix;
                    if (Math.abs(actual.a-values[0]) > .00002 || Math.abs(actual.b-values[1]) > .00002
                            || Math.abs(actual.c-values[2]) > .00002 || Math.abs(actual.d-values[3]) > .00002
                            || Math.abs(actual.tx-values[4]) > .051 || Math.abs(actual.ty-values[5]) > .051) allMatrices = false;
                }
                frames++;
            }
        }
        check(frames == 589 && allMatrices,"589帧真实AS2完整矩阵写入");
        check(allIdentities,"跳帧回放保持常驻对象身份");
        player.applyPose(data.clips.ready.frames[0]); player.applyPose(data.clips.ready.frames[0]);
        check(player.lastWriteCount == 0,"驻留不重复写93个矩阵");
        player.setAmmo(2);
        check(gun.动画.part_ammo_1.live._visible && gun.动画.part_ammo_3.spent._visible,"实际弹药示意覆盖变体状态");
        check(gun.动画.part_ammo_3.spent._alpha == 100,"初始隐藏变体透明度恢复");
        player.reset();
    }

    private static function configureUnit(asset:MovieClip, withBlade:Boolean, configured:Object, installedMods:Array, bladeBonus:Number, initialMode:String):Void {
        unit = asset.createEmptyMovieClip(withBlade ? "actorWithKnife" : "actualActor",asset.getNextHighestDepth());
        var slots:Array = ["头部装备","上装装备","下装装备","手部装备","脚部装备","颈部装备","长枪","手枪","手枪2","刀","手雷"];
        for (var i:Number = 0; i < slots.length; i++) unit[slots[i]] = null;
        unit.version = 1; unit.hp = 1000; unit.mp = 1000; unit.攻击模式 = initialMode ? initialMode : "长枪";
        unit.状态 = unit.攻击模式 + "站立"; unit.Z轴坐标 = 0; unit.enableShoot = true;
        unit.syncRefs = {}; unit.主动战技 = {}; unit.生命周期函数列表 = [];
        var effective:Object = configured != null ? configured : itemConfig;
        unit.长枪 = new BaseItem("火药燃气液压打桩机",{level:1,tier:"重锤",shot:0,mods:installedMods != null ? installedMods : []},0);
        unit.长枪数据 = effective; unit.长枪属性 = effective.data;
        unit.长枪弹匣容量 = itemConfig.data.capacity; unit.长枪_装扮 = itemConfig.data.dressup;
        unit.长枪_引用 = gun; unit.刀_引用 = blade;
        if (withBlade) unit.刀 = {name:"真实冷兵器",value:{level:1,mods:[]}};
        unit.dispatcher = new EventDispatcher();
        unit.根据模式重新读取武器加成 = _root.主角函数.根据模式重新读取武器加成;
        var zeroFields:Array = ["基础毒","基础吸血","基础击溃","基础斩杀","基础命中加成","装备刀锋利度加成",
            "hp满血值装备加层","mp满血值装备加层","装备防御力","伤害加成","内力","装备枪械威力加成",
            "空手攻击力","佣兵技能概率抑制基数","韧性加成","闪避加成","懒闪避",
            "兵器毒","兵器吸血","兵器击溃","兵器斩杀","兵器命中加成"];
        for (i = 0; i < zeroFields.length; i++) unit[zeroFields[i]] = 0;
        unit.基础命中率 = 100; unit.基础伤害类型 = "物理";
        unit.兵器伤害类型 = "物理"; unit.兵器魔法伤害属性 = null; unit.兵器暴击 = null;
        if (withBlade) { unit.兵器吸血 = 9; unit.兵器斩杀 = 4; }
        var propertyApi = org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        propertyApi["updateProperty"](unit,"长枪",effective.data);
        if (isFinite(bladeBonus)) unit.装备刀锋利度加成 = bladeBonus;
        unit.根据模式重新读取武器加成(unit.攻击模式);
        unit.man = unit.createEmptyMovieClip("man",unit.getNextHighestDepth());
        unit.man.射击许可标签 = true;
        props = {子弹种类:"近战联弹",子弹威力:itemConfig.data.power,霰弹值:itemConfig.data.split,
            子弹速度:0,站立子弹散射度:0,移动子弹散射度:0,ammoCost:1};
        unit.man.子弹属性 = props; unit.man.射击速度 = itemConfig.data.interval;
        unit.man.开始射击 = function():Void {
            PileBunkerM7Test.attackCalls++;
            ShootCore.startShooting(this._parent,this,ShootCore.primaryParams);
        };
        attachSkins();
        unit.长枪射击 = WeaponFireCore.LONG_GUN_SHOOT;
        unit.刀口位置生成子弹 = BladeShootCore.shoot;
        unit.攻击 = _root.主角函数.攻击;
        unit.装载主动战技 = _root.主角函数.装载主动战技;
        unit.释放主动战技 = _root.主角函数.释放主动战技;
        DressupInitializer.updateActions(unit,true);
        DressupInitializer.updateWeqaponSkills(unit);
        check(unit.主动战技.长枪.名字 == "打桩过载" && unit.主动战技.长枪.战技函数 === _root.主动战技函数.长枪.打桩过载,"实际装备战技装载和函数绑定");
        _root.控制目标 = unit._name;
        RuntimeEquipmentProjection.beginCanonical(unit);
        FireEventComponent.initialize(unit); baselineSubscriptions = unit.dispatcher["_subCount"];
        unit.装载生命周期函数 = _root.主角函数.装载生命周期函数;
        unit.装载生命周期函数(effective.lifecycle,"长枪");
        check(queued != null && queued.args[0].装备名称 == "火药燃气液压打桩机","生产生命周期装载入口");
        ref = queued.args[0]; controller = ref.pileBunkerController;
        DressupInitializer.validateAttackMode(unit);
        check(RuntimeEquipmentProjection.completeCanonical(unit),"真实canonical与alias提交");
    }
    private static function attachSkins():Void {
        var outer:MovieClip = unit.man.createEmptyMovieClip("枪",unit.man.getNextHighestDepth());
        var inner:MovieClip = outer.createEmptyMovieClip("枪",outer.getNextHighestDepth());
        gun = DressupReferenceManager.attach(inner,itemConfig.data.dressup,"装扮","长枪_引用");
        outer = unit.man.createEmptyMovieClip("刀",unit.man.getNextHighestDepth());
        inner = outer.createEmptyMovieClip("刀",outer.getNextHighestDepth());
        blade = DressupReferenceManager.attach(inner,itemConfig.data.dressup,"装扮","刀_引用");
        check(gun.动画._parent != undefined && blade.动画._parent != undefined,"生产装扮管理器装配真实枪刀引用");
    }
    private static function tick():Void {
        _root.帧计时器.当前帧数 = ++time;
        queued.callback.apply(queued.owner,queued.args);
    }
    private static function ticks(count:Number):Void { for (var i:Number = 0; i < count; i++) tick(); }
    private static function chargeReady():Void {
        held = false;
        while (time < controller.getSnapshot().chargeNotBeforeFrame || controller.getSnapshot().phase == "recovery") tick();
        held = true; ticks(30); held = false; ticks(14);
    }

    private static function testChargeAndFire():Void {
        check(unit.刀 === unit.长枪 && controller.getSnapshot().alias,"空刀槽借用确切长枪物件");
        check(unit.兵器动作类型 == "狂野" && unit.刀_刀口数 == 3,"狂野模组与三刀口");
        check(unit.刀属性.power == 890,"锤击按独立负1层锋利度890投影");
        check(knifeDonor.power == 130 && unit.刀属性 !== knifeDonor,"借用属性不污染公共供体字典");
        held = true; ticks(29);
        check(controller.getSnapshot().phase == "idle" && !unit.chargeComplete,"阈值前不播放机械准备");
        held = false; tick(); check(ref.chargeCount == 28,"未满松键计数衰减");
        held = true; ticks(2);
        check(controller.getSnapshot().phase == "preparing" && !controller.canFire(),"满充提交准备并门控攻击");
        held = false; ticks(14);
        check(controller.canSkill() && unit.chargeComplete,"松键不撤销已提交准备");
        var pose:Number = controller.getSnapshot().poseId;
        unit.dispatcher.publish("长枪_引用",unit); unit.dispatcher.publish("长枪_引用",unit);
        check(controller.getSnapshot().poseId == pose,"placement不推进状态时钟");
        unit.长枪射击(gun.枪口位置,props);
        var chargedShotFrame:Number = time;
        check(controller.getSnapshot().lastBranch == "N1" && unit.长枪.value.shot == 1,"蓄力普攻成功提交且只耗一发");
        check(lastPower == itemConfig.data.power * itemConfig.lifecycle.attr_0.init.initParam.chargedPowerMultiplier
            && props.子弹威力 == itemConfig.data.power,"N1只增强本次发射，不污染普通射击模板");
        check(!unit.chargeComplete && ref.chargeCount == 0,"成功提交才消耗满充");
        check(Math.abs(gun.动画.part_main_shaft._x - 137.7) < .051,"N1提交首帧立即出桩");
        tick(); check(Math.abs(gun.动画.part_main_shaft._x - 306) < .051,"N1第二帧到峰值");
        var count:Number = emitted;
        check(!unit.长枪射击(gun.枪口位置,props) && emitted == count && unit.长枪.value.shot == 1,"回收期间拒绝重入无耗弹");
        held = true; ticks(55);
        check(ref.chargeCount == 0,"N1回收完成但2秒间隔未到，不提前累计蓄力");
        ticks(4);
        check(ref.chargeCount == 0,"射后满60帧仍不提前计入首个蓄力帧");
        chargeReady();
        check(controller.canSkill(),"回收后可重新满充");
        check(time - chargedShotFrame == 104,"N1再就绪确实花费60帧间隔加44帧蓄力");
        unit.长枪.value.shot = unit.长枪弹匣容量;
        check(!unit.长枪射击(gun.枪口位置,props) && unit.chargeComplete,"空弹拒绝仍保留满充");
        check(!controller.releaseSkill() && emitted == count,"空弹战技拒绝无输出");
        unit.长枪.value.shot = 1;
        var mp:Number = unit.mp;
        ManualCooldownService.reset(ManualCooldownService.WEAPON_SKILL_KEY);
        unit.mp = itemConfig.skill.mp - 1;
        var rejected:Object = _root.武器技能输入控制器.update(unit,true);
        check(!rejected.released && !rejected.startSharedCooldown && unit.长枪.value.shot == 1
            && unit.chargeComplete,"MP不足拒绝战技，不耗弹、不吃蓄力、不启动共享冷却");
        check(unit.mp == itemConfig.skill.mp - 1,"拒绝战技不会扣成负MP");
        _root.武器技能输入控制器.update(unit,false); unit.mp = mp;
        // class 调用必须读取角色模式；故意让调用时间轴带有不同模式，复现旧裸变量漏洞。
        _root.攻击模式 = "兵器";
        check(typeof _root.武器技能输入控制器.update == "function","测试启动完成真实F按键桥接装载");
        var inputResult:Object = _root.武器技能输入控制器.update(unit,true);
        check(inputResult.released && inputResult.startSharedCooldown,"F键服务通过真实战技槽与生产释放函数");
        check(inputResult.cooldownTime == itemConfig.skill.cd,"成功战技使用现役XML冷却时长");
        check(!_root.武器技能输入控制器.update(unit,true),"F按住锁存防止重复释放");
        _root.武器技能输入控制器.update(unit,false);
        check(controller.getSnapshot().lastBranch == "S1" && unit.长枪.value.shot == 3,"S1一次耗尽当前2发，不额外消耗首发");
        check(unit.mp == mp - itemConfig.skill.mp
            && Math.abs(lastPower - itemConfig.data.power * itemConfig.lifecycle.attr_0.init.initParam.skillMiddlePowerMultiplier) < .00001
            && lastSplit == itemConfig.data.split && props.子弹威力 == itemConfig.data.power,"S1一次扣MP并按倍率投影，保留联弹段数及模板");
        check(Math.abs(gun.动画.part_main_shaft._x - 161.1) < .051,"S1提交首帧立即出桩");
        tick(); check(Math.abs(gun.动画.part_main_shaft._x - 358) < .051,"S1第二帧到峰值");
        ticks(67);
        ShootCore.cleanup(unit);
        unit.长枪.value.shot = 0;
        check(unit.长枪射击(gun.枪口位置,props),"普通攻击走真实射击核心");
        check(controller.getSnapshot().lastBranch == "N0" && unit.长枪.value.shot == 1,"N0分支与单发消耗");
        check(lastPower == itemConfig.data.power,"蓄力和战技之后普通射击威力恢复");
        ticks(35);
    }

    private static function testBurstAmmunition():Void {
        var param:Object = itemConfig.lifecycle.attr_0.init.initParam;
        var hudRemaining:Number = -1;
        var hudHandler:Function = function(owner:MovieClip, state:String, remaining:Number):Void { hudRemaining = remaining; };
        unit.dispatcher.subscribe("updateBullet",hudHandler,ref);
        // 两种真实订阅次序都走WeaponFireCore；验证补扣与基础shot++可交换。
        for (var order:Number = 0; order < 2; order++) {
            if (order == 1) {
                unit.dispatcher.unsubscribe("processShot",FireEventComponent.processShot,unit);
                unit.dispatcher.subscribe("processShot",FireEventComponent.processShot,unit);
            }
            for (var remaining:Number = 1; remaining <= 3; remaining++) {
                ShootCore.cleanup(unit);
                unit.长枪.value.shot = 3 - remaining;
                chargeReady();
                var mp:Number = unit.mp;
                var before:Number = emitted;
                var shots:Number = controller.getSnapshot().shots;
                // 足量MP只用于隔离样本；真实扣费仍由生产原子释放完成。
                unit.mp = 1000; hudRemaining = -1;
                check(controller.releaseSkill(),"余弹" + remaining + "订阅次序" + order + "战技提交");
                var multiplier:Number = remaining == 1 ? 1.5 : (remaining == 2 ? 2 : 3);
                check(unit.长枪.value.shot == 3 && controller.getSnapshot().lastAmmoCost == remaining,
                    "余弹" + remaining + "精确清空，无第四发或负弹药");
                check(emitted == before + 1 && controller.getSnapshot().shots == shots + 1
                    && Math.abs(lastPower - itemConfig.data.power * multiplier) < .00001,
                    "余弹" + remaining + "只生成一份按1.5/2/3档位结算的联弹");
                check(unit.mp == 880 && hudRemaining == 0 && !unit.动作A,"一次扣120MP、HUD归零并恢复攻击键");
                controller["onShot"](unit,"长枪",unit.长枪);
                check(unit.长枪.value.shot == 3 && controller.getSnapshot().shots == shots + 1,"迟到或重复回执不再次扣弹");
                check(!controller.releaseSkill() && unit.mp == 880 && emitted == before + 1,"同帧重复释放不耗弹不扣费");
                unit.mp = mp;
            }
        }
        var capacities:Array = [1,2,4,6];
        for (var c:Number = 0; c < capacities.length; c++) {
            var capacity:Number = capacities[c];
            unit.长枪弹匣容量 = capacity;
            for (var r:Number = 1; r <= capacity; r++) {
                ShootCore.cleanup(unit); unit.长枪.value.shot = capacity-r;
                chargeReady(); unit.mp = 1000;
                var tier:Number = Math.ceil(r * 3 / capacity);
                var expected:Number = tier == 1 ? 1.5 : (tier == 2 ? 2 : 3);
                var prior:Number = emitted;
                check(controller.releaseSkill() && unit.长枪.value.shot == capacity && emitted == prior+1,
                    "弹容"+capacity+"余弹"+r+"仍单次联弹并耗尽");
                check(Math.abs(lastPower-itemConfig.data.power*expected) < .00001 && unit.mp == 880,
                    "弹容"+capacity+"余弹"+r+"按机械指示窗档位结算");
            }
        }
        unit.长枪弹匣容量 = 3;
        ShootCore.cleanup(unit); unit.长枪.value.shot = 0;
        var burstShotFrame:Number = time;
        held = true; ticks(68);
        check(ref.chargeCount == 0,"S1回收68帧结束时不提前累计蓄力");
        chargeReady();
        check(time - burstShotFrame == 112,"S1再次就绪需68帧回收加44帧蓄力");
        var ammo:Number = unit.长枪.value.shot;
        var mpBefore:Number = unit.mp;
        var bullets:Number = emitted;
        ManualCooldownService.reset(ManualCooldownService.WEAPON_SKILL_KEY);
        unit.man.射击许可标签 = false;
        var denied:Object = _root.武器技能输入控制器.update(unit,true);
        check(!denied.released && !denied.startSharedCooldown && unit.长枪.value.shot == ammo && unit.mp == mpBefore
            && unit.chargeComplete && emitted == bullets,"射击许可拒绝保留全部弹药、MP、蓄力且不启动冷却");
        _root.武器技能输入控制器.update(unit,false); unit.man.射击许可标签 = true;
        var savedFire:Function = controller["oldFire"];
        controller["oldFire"] = function():Boolean { return false; };
        check(!controller.releaseSkill() && unit.长枪.value.shot == ammo && unit.mp == mpBefore && unit.chargeComplete,
            "射击核心拒绝不补扣弹药、不消耗蓄力或MP");
        controller["oldFire"] = savedFire;
        unit.长枪.value.shot = -1;
        check(!controller.canSkill(),"非法负耗弹不能换取超满匣倍率");
        unit.长枪.value.shot = .5;
        check(!controller.canSkill(),"小数耗弹不能绕过整数弹药合同");
        unit.长枪.value.shot = ammo;
        var originalShot:Function = controller["oldFire"];
        controller["oldFire"] = function(muzzle:MovieClip, bulletProps:Object):Boolean {
            // 错物件回执不能提交；随后仍由实际核心产生正确回执。
            PileBunkerM7Test.controller["onShot"](PileBunkerM7Test.unit,"长枪",{value:{shot:0}});
            PileBunkerM7Test.check(PileBunkerM7Test.unit.chargeComplete,"错误装备回执不能抢占本次提交");
            var result:Boolean = originalShot.call(this,muzzle,bulletProps);
            PileBunkerM7Test.controller["onShot"](PileBunkerM7Test.unit,"长枪",PileBunkerM7Test.unit.长枪);
            PileBunkerM7Test.check(PileBunkerM7Test.unit.长枪.value.shot == 3,"同一发尚未返回时重复回执也不追加耗弹");
            PileBunkerM7Test.check(!PileBunkerM7Test.unit.长枪射击(muzzle,bulletProps),"发射栈内重入不产生第二发");
            return result;
        };
        check(controller.releaseSkill() && emitted == bullets + 1,"拒绝后的满充仍可成功释放一次");
        controller["oldFire"] = originalShot;
        unit.dispatcher.unsubscribe("updateBullet",hudHandler,ref);
        ShootCore.cleanup(unit); held = false; ticks(68); unit.长枪.value.shot = 0;
    }

    private static function testGunRegions():Void {
        var originalMatrix:flash.geom.Matrix = unit.transform.matrix;
        var branches:Array = ["N0","N1","S1"];
        for (var facing:Number = 0; facing < 2; facing++) {
            unit._x = 170; unit._y = 120;
            unit._xscale = facing == 0 ? 75 : -75; unit._yscale = 90; unit._rotation = 17;
            for (var branch:Number = 0; branch < branches.length; branch++) {
                ShootCore.cleanup(unit); ticks(68); unit.长枪.value.shot = 0; unit.mp = 1000;
                if (branch > 0) chargeReady();
                // 故意移走旧枪口；本次桩击必须仍由实际出桩姿态提供区域。
                gun.枪口位置._x += 2000; gun.枪口位置._y -= 300;
                var before:Number = emitted;
                var ok:Boolean = branch == 2 ? controller.releaseSkill() : unit.长枪射击(gun.枪口位置,props);
                var label:String = branches[branch] + (facing == 0 ? "右向" : "左向");
                check(ok && emitted == before + 1 && lastSplit == 3,label + "仍只提交一次原有三段联弹");
                check(lastArea === controller["strikeArea"] && lastArea !== gun.动画.part_main_shaft && lastArea !== gun.枪口位置,
                    label + "主桩击使用完整出桩轮廓的一次快照");
                var firstFrame:Object = gun.动画.part_main_shaft.getRect(_root.gameworld);
                var displayPose:Number = controller.getSnapshot().poseId;
                var nativePlayer = controller["gunPlayer"];
                nativePlayer.applyPose(poseData.clips[branches[branch]].frames[poseData.config.strikeFrames0[branches[branch]]]);
                var fullStroke:Object = gun.动画.part_main_shaft.getRect(_root.gameworld);
                var localRect:Object = gun.动画.part_main_shaft.getRect(gun.动画.part_main_shaft);
                var outerTip:Object = {x:localRect.xMax-2,y:(localRect.yMin+localRect.yMax)*.5};
                gun.动画.part_main_shaft.localToGlobal(outerTip); _root.gameworld.globalToLocal(outerTip);
                nativePlayer.applyPose(displayPose);
                var current:Object = lastArea.getRect(_root.gameworld);
                check(Math.abs(current.xMin-fullStroke.xMin) < .06 && Math.abs(current.xMax-fullStroke.xMax) < .06
                    && Math.abs(current.yMin-fullStroke.yMin) < .06 && Math.abs(current.yMax-fullStroke.yMax) < .06,
                    label + "碰撞轮廓等于真实素材完整出桩峰值");
                check(Math.abs(lastAreaBounds.xMin-current.xMin) < .051 && Math.abs(lastAreaBounds.xMax-current.xMax) < .051
                    && Math.abs(lastAreaBounds.yMin-current.yMin) < .051 && Math.abs(lastAreaBounds.yMax-current.yMax) < .051,
                    label + "子弹发出时就取得完整行程快照");
                var probe:Object = {发射者:unit._name,子弹种类:"近战联弹",shootX:lastBullet.shootX,shootY:lastBullet.shootY,shootZ:unit.Z轴坐标,区域定位area:lastArea};
                BulletInitializer.initializeBulletProperties(probe);
                check(probe.子弹区域area === lastArea,label + "生产初始化保留独立区域引用");
                var collider = new AABBCollider(0,0,0,0);
                collider.updateFromBullet(probe,probe.子弹区域area);
                if (branch > 0) {
                    var target:AABBCollider = AABBCollider.fromCenter(outerTip.x,outerTip.y,1,1);
                    var shortBox:AABBCollider = new AABBCollider(firstFrame.xMin,firstFrame.xMax,firstFrame.yMin,firstFrame.yMax);
                    check(!shortBox.checkCollision(target,0).isColliding && collider.checkCollision(target,0).isColliding,
                        label + "首帧范围外的完整杆尖目标现在可命中");
                }
                var centerX:Number = (current.xMin + current.xMax) * .5;
                var centerY:Number = (current.yMin + current.yMax) * .5;
                check(collider.checkCollision(AABBCollider.fromCenter(centerX,centerY,1,1),0).isColliding,
                    label + "镜像旋转缩放后的杆内目标可碰撞");
                check(!collider.checkCollision(AABBCollider.fromCenter(current.xMax+100,centerY,1,1),0).isColliding,
                    label + "杆外目标不因旧远端枪口获得命中");
                var point:Object = {x:0,y:0};
                gun.动画.anchor_tip.localToGlobal(point); _root.gameworld.globalToLocal(point);
                check(Math.abs(lastBullet.shootX-point.x) < .06 && Math.abs(lastBullet.shootY-point.y) < .06,
                    label + "发射坐标同本次杆尖对齐且不受监听顺序影响");
                check(props.区域定位area == undefined,label + "不污染公共主枪属性模板");
            }
        }
        unit.transform.matrix = originalMatrix;
        ShootCore.cleanup(unit); ticks(68); unit.长枪.value.shot = 0;
        controller.syncVisual();
    }

    private static function testFuelModes():Void {
        ShootCore.cleanup(unit); unit.长枪.value.shot = 0;
        LongGunSubWeaponCore.setFiredCount(unit,0);
        check(unit.主动战技.长枪.isSubweaponControl && controller.canSpray(),"未蓄力的同一特殊槽为副武器补装");
        var spray:Object = LongGunSubWeaponCore.prepareManBulletProps(unit,unit.man);
        check(spray.子弹威力 == 850 && spray.Z轴攻击范围 == 25 && spray.子弹速度 == 45
            && unit.长枪副武器配置.cd == 220 && unit.长枪副武器弹匣容量 == 12,"原样映射战术喷火参数并缩为12格");
        var shots:Number = controller.getSnapshot().shots;
        check(LongGunSubWeaponCore.executeShot(unit,gun.枪口位置,spray),"副喷火走实际副武器提交链");
        check(controller.getSnapshot().fuel == 11 && unit.长枪.value.shot == 0
            && controller.getSnapshot().shots == shots,"K只消费共享燃料，不触发主枪回收或扣榴弹");
        var sprayOrigin:Object = {x:0,y:0};
        gun.动画.anchor_tip.localToGlobal(sprayOrigin); _root.gameworld.globalToLocal(sprayOrigin);
        check(Math.abs(effects[effects.length-1].shootX-sprayOrigin.x) < .06
            && Math.abs(effects[effects.length-1].shootY-sprayOrigin.y) < .06,"实际副喷火从收拢杆尖发出而非旧远端枪口");
        chargeReady();
        check(unit.主动战技.长枪.名字 == "打桩过载" && !controller.canSpray(),"机械准备完成才把F槽交给过载");
        check(!LongGunSubWeaponCore.executeShot(unit,gun.枪口位置,spray) && controller.getSnapshot().fuel == 11,"就绪阶段在副射击提交点拒绝K且不耗油");
        var mp:Number = unit.mp;
        held = true; tick(); held = false; ticks(14);
        check(controller.getSnapshot().phase == "idle" && !unit.chargeComplete && unit.主动战技.长枪.isSubweaponControl,
            "再次按Q经卸压动作回到副武器槽");
        check(unit.mp == mp && unit.长枪.value.shot == 0 && controller.getSnapshot().fuel == 11,"Q切换不扣弹不扣费也不赠送燃料");

        for (var grenades:Number = 1; grenades <= 3; grenades++) {
            for (var fuel:Number = 0; fuel <= 3; fuel++) {
                ShootCore.cleanup(unit); unit.mp = 1000;
                unit.长枪.value.shot = 3 - grenades;
                LongGunSubWeaponCore.setFiredCount(unit,12 - fuel);
                chargeReady();
                var before:Number = effects.length;
                var expected:Number = Math.min(grenades,fuel);
                check(controller.releaseSkill(),"主弹" + grenades + "燃料" + fuel + "仍允许机械过载");
                check(unit.长枪.value.shot == 3 && controller.getSnapshot().fuel == fuel - expected
                    && controller.getSnapshot().lastFuelCost == expected,"主弹与已付油量各自只提交一次");
                check(effects.length == before + expected && unit.mp == 880,"只生成能付费的火焰档数，MP按一次过载扣除");
                for (var i:Number = 0; i < expected; i++) {
                    check(effects[before+i].子弹种类 == itemConfig.lifecycle.attr_0.init.initParam["flame_"+i].bullet
                        && effects[before+i].hitBehavior.fuelUnits == 1,"缺油只保留从弱档开始的付费火焰");
                }
                check(lastBullet.血量上限击溃 == 1 && lastBullet.斩杀 == 13,"机械过载独立保留击溃与斩杀");
                controller["onShot"](unit,"长枪",unit.长枪);
                check(controller.getSnapshot().fuel == fuel - expected,"重复主枪回执不会再扣油");
            }
        }
        ShootCore.cleanup(unit); ticks(68); unit.长枪.value.shot = 0;
        LongGunSubWeaponCore.setFiredCount(unit,0);
        var normalBefore:Number = effects.length;
        unit.长枪射击(gun.枪口位置,props);
        check(effects.length == normalBefore && controller.getSnapshot().fuel == 12,
            "普通满弹匣开火只耗一榴弹，不扣燃料也不追加火焰");
        check(!(lastBullet.血量上限击溃 > 0) && !(lastBullet.斩杀 > 0),"N0不继承先前蓄力/过载专属属性");
        chargeReady();
        unit.长枪射击(gun.枪口位置,props);
        check(effects.length == normalBefore && controller.getSnapshot().fuel == 12,
            "蓄力普攻同样不扣燃料也不追加火焰，燃爆仅限战技");
        check(lastBullet.血量上限击溃 == 1 && !(lastBullet.斩杀 > 0),"N1仍保留蓄力击溃且不借用过载斩杀");
        ticks(56);
    }

    private static function testHammerFuelWindow():Void {
        unit.攻击模式 = "兵器"; unit.状态 = "兵器站立"; tick(); ticks(14);
        check(unit.主动战技.兵器.名字 == "燃气破坏" && controller.canHammerSkill(),"借用刀槽装入自己的锤战技");
        unit.状态 = "兵器一段中";
        var before:Number = effects.length;
        var fuel:Number = controller.getSnapshot().fuel;
        unit.刀口位置生成子弹(unit,{子弹威力:1780});
        unit.刀口位置生成子弹(unit,{子弹威力:1780});
        check(effects.length == before + 1 && effects[before].子弹种类 == "碎石飞扬"
            && controller.getSnapshot().fuel == fuel,"常态碎石按动作节点触发，不按刀口或重复判定发射");
        check(lastBullet.伤害类型 == "破击" && lastBullet.魔法伤害属性 == "装甲","本体锤击为装甲破击");
        unit.状态 = "兵器站立"; tick(); ticks(15); unit.mp = 1000;
        ManualCooldownService.reset(ManualCooldownService.WEAPON_SKILL_KEY);
        _root.武器技能输入控制器.update(unit,false);
        var result:Object = _root.武器技能输入控制器.update(unit,true);
        check(result.released && result.cooldownTime == 10000 && unit.mp == 950 && routedSkill == "破坏殆尽",
            "锤F沿真实战技装载/扣费入口请求破坏殆尽");
        _root.武器技能输入控制器.update(unit,false);
        check(controller.getSnapshot().hammerBuffUntil == time + 180,"战技成功事件开启6秒窗口");
        before = effects.length;
        unit.刀口位置生成子弹(unit,{子弹威力:2670});
        check(lastBullet.血量上限击溃 == .05 && lastBullet.斩杀 == 6,"强化窗口只投影锤的刀口属性");
        check(effects.length == before + 1 && effects[before].子弹种类 == "终极打击"
            && controller.getSnapshot().fuel == fuel - 1 && unit.mp == 950,"重砸额外付一格油产生烈焰，附加效果不再扣MP");
        unit.技能名 = ""; unit.状态 = "兵器站立"; tick(); ticks(15);
        LongGunSubWeaponCore.setFiredCount(unit,12);
        unit.状态 = "兵器四段中"; before = effects.length;
        unit.刀口位置生成子弹(unit,{子弹威力:1780});
        check(effects.length == before + 1 && effects[before].子弹种类 == "碎石飞扬"
            && effects[before].hitBehavior == undefined,"缺油时强化节点退回免费碎石，不授予立场破击");
        unit.状态 = "兵器站立"; ticks(180);
        unit.刀口位置生成子弹(unit,{子弹威力:1780});
        check(!(lastBullet.血量上限击溃 > 0) && !(lastBullet.斩杀 > 0),"窗口到期后不残留斩杀击溃");
        unit.攻击模式 = "长枪"; unit.状态 = "长枪站立"; tick(); ticks(14);
        check(controller.getSnapshot().fuel == 0 && unit.主动战技.长枪.isSubweaponControl,"枪锤往返不会回填燃料");
        check(!ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY),"模式切换不清除已提交的共享战技冷却");
    }

    private static function loadLiveEffects():Void {
        fxLibrary = _root.createEmptyMovieClip("__pileM7Fx",_root.getNextHighestDepth());
        fxLoader = new MovieClipLoader(); fxListener = {};
        fxListener.onLoadError = function():Void { PileBunkerM7Test.check(false,"真实烈焰素材加载"); PileBunkerM7Test.finish(); };
        fxListener.onLoadInit = function():Void {
            var names:Array = ["碎石飞扬","熔炎裂渊","烈炎斜升","终极打击"];
            for (var i:Number = 0; i < names.length; i++) {
                var node:MovieClip = PileBunkerM7Test.fxLibrary.attachMovie(names[i],"fx"+i,100+i,
                    {发射者名:PileBunkerM7Test.unit._name,伤害类型:"物理"});
                PileBunkerM7Test.check(node != undefined,"真实特效linkage " + names[i]);
                node.gotoAndStop(1); PileBunkerM7Test.liveEffects.push(node);
            }
            PileBunkerM7Test.watchdog.onEnterFrame = function():Void {
                delete this.onEnterFrame;
                PileBunkerM7Test.testLiveEffectDamage(); PileBunkerM7Test.finish();
            };
        };
        fxLoader.addListener(fxListener);
        fxLoader.loadClip("../flashswf/arts/new/雾人整合特效.swf",fxLibrary);
    }

    private static function testLiveEffectDamage():Void {
        var shooter:Object = {};
        var target:Object = {防御力:900,魔法抗性:{立场:50,热:0}};
        for (var i:Number = 1; i < liveEffects.length; i++) {
            var bullet:MovieClip = liveEffects[i];
            check(bullet.伤害类型 == "魔法" && bullet.魔法伤害属性 == "热","真实素材首帧的热伤覆盖被纳入回归");
            bullet.hitBehavior = {type:"pileBunkerFuel",fuelUnits:1}; bullet.破坏力 = 850;
            BulletHitEffectRegistry.prepare(bullet,shooter,target);
            UniversalDamageHandle.getInstance().handleBulletDamage(bullet,shooter,target,null,new DamageResult());
            check(target.损伤值 == 425 && bullet.魔法伤害属性 == "立场","付费快照在真实伤害处理器中恢复立场破击");
        }
        var unpaid:Object = {伤害类型:"物理",hitBehavior:{type:"pileBunkerFuel",fuelUnits:0}};
        BulletHitEffectRegistry.prepare(unpaid,shooter,target);
        check(unpaid.伤害类型 == "物理","无付费资格不额外获得立场类型");
        testShieldAndExecuteOrdering();
    }

    private static function testShieldAndExecuteOrdering():Void {
        // 与地狱魔女相同的护盾参数规则：20%生命容量、防御+等级*5强度、60帧回满、30帧延迟。
        var target:Object = {hp:20000,hp满血值:20000,等级:50,防御力:100,魔法抗性:{基础:35}};
        var shield:AdaptiveShield = AdaptiveShield.createRechargeable(target.hp满血值*.2,target.防御力+target.等级*5,
            target.hp满血值*.2/60,30,"雪女冰盾");
        shield.setOwner(target); target.shield = shield;
        check(target.魔法抗性.立场 > 35 && shield.getStrength() == 350,"真实常驻充能护盾提供立场抗性字段");
        var flame:Object = {伤害类型:"魔法",魔法伤害属性:"热",子弹威力:850,破坏力:850,hitBehavior:{type:"pileBunkerFuel",fuelUnits:1}};
        var result:DamageResult = new DamageResult(); result.actualScatterUsed = 1;
        BulletHitEffectRegistry.prepare(flame,{},target);
        UniversalDamageHandle.getInstance().handleBulletDamage(flame,{},target,null,result);
        check(result._efText == "立场" && (result._efFlags & 16) != 0 && target.损伤值 > 637.5,
            "存活带盾目标被付费火焰命中时得到额外立场伤害与破击标签");
        target.hp = 500; flame.斩杀 = 13;
        ExecuteDamageHandle.getInstance().handleBulletDamage(flame,{},target,null,result);
        check(target.hp == 0 && (result._efFlags & 4) != 0 && (result._efFlags & 16) != 0 && result._efText == "立场",
            "同一发火焰随后触发斩杀也不会跳过或抹去立场破击");
        shield.clear(); shield.setOwner(null);

        target = {hp:20000,hp满血值:20000,等级:50,防御力:100,魔法抗性:{基础:35}};
        shield = AdaptiveShield.createRechargeable(4000,350,4000/60,30,"雪女冰盾");
        shield.setOwner(target); target.shield = shield;
        var main:Object = {伤害类型:"物理",子弹威力:100000,破坏力:100000,斩杀:13};
        result = new DamageResult(); result.actualScatterUsed = 1;
        UniversalDamageHandle.getInstance().handleBulletDamage(main,{},target,null,result);
        ExecuteDamageHandle.getInstance().handleBulletDamage(main,{},target,null,result);
        check(target.hp == 0 && (result._efFlags & 4) != 0 && (result._efFlags & 16) == 0,
            "高威力机械主桩可以独立处决带盾目标且本身没有立场标签");
        flame.damageManager = {};
        check(DamageCalculator.calculateDamage(flame,{},target,1,"") === DamageResult.NULL,
            "稍后到达的火焰遇到已死亡目标不再进入伤害与破击显示链");
        shield.clear(); shield.setOwner(null);
    }

    private static function testFormsAndMarkers():Void {
        unit.攻击模式 = "兵器"; tick();
        check(controller.getSnapshot().phase == "toHammer" && !controller.canMelee(),"冷态转锤须先完成准备");
        var before:Number = attackCalls; unit.攻击();
        check(attackCalls == before,"未锁定不调用狂野攻击入口");
        var bullets:Number = emitted; unit.刀口位置生成子弹(unit,{子弹威力:1});
        check(emitted == bullets,"未锁定不生成近战判定");
        ticks(14); check(controller.canMelee() && !unit.chargeComplete,"15帧完成转锤且不赠送满充");
        check(!gun.动画._visible && blade.动画._visible,"刀枪唯一显示形态");
        unit.刀口位置生成子弹(unit,{子弹威力:1});
        check(emitted == bullets + 3 && lastArea === blade.刀口位置3,"现役BladeShootCore使用真实三刀口");
        var area:Object = blade.刀口位置1.getBounds(blade.刀口位置1);
        check(area.xMax-area.xMin > 30 && area.yMax-area.yMin > 90,"近战判定是实体区域而非空参考点");
        unit.攻击模式 = "长枪"; tick();
        check(controller.getSnapshot().phase == "toGun" && !controller.canFire(),"出锤期间关闭击发");
        ticks(14); check(controller.canFire() && controller.getSnapshot().phase == "idle","15帧卸载并回普通枪态");
        held = true; ticks(30); ticks(3); held = false;
        var previousPose:Number = controller.getSnapshot().poseId;
        unit.攻击模式 = "兵器"; tick();
        check(controller.getSnapshot().poseId == previousPose,"准备中转锤从当前完整姿态衔接");
        unit.攻击模式 = "长枪"; ticks(14); tick(); ticks(14);
        check(controller.canFire() && !controller.canMelee(),"快速切换只追随最终目标并在安全端点转向");
        var oldIdentity:Object = gun.动画.__namedPoseIdentity;
        gun = DressupReferenceManager.attach(unit.man.枪.枪,itemConfig.data.dressup,"装扮","长枪_引用");
        check(gun.动画.__namedPoseIdentity !== oldIdentity && gun.动画.part_main_shaft != undefined,"同路径重建重新绑定，不依赖MC引用身份");
        unit.攻击模式 = "兵器"; tick(); ticks(14);
        unit.攻击模式 = "空手"; tick();
        check(controller.getSnapshot().phase == "toGun" && controller.getSnapshot().clip == "hammer_exit","切到空手仍先播放收锤");
        var firstExitPose:Number = controller.getSnapshot().poseId;
        tick();
        check(controller.getSnapshot().poseId != firstExitPose,"收锤过程中姿态实际推进");
        var retained:Object = controller.getSnapshot();
        gun = DressupReferenceManager.attach(unit.man.枪.枪,itemConfig.data.dressup,"装扮","长枪_引用");
        check(controller.getSnapshot().poseId == retained.poseId && gun.动画.__namedPoseIdentity != undefined,"placement恢复收锤姿态且不推进时钟");
        unit.攻击模式 = "手枪"; ticks(13);
        check(controller.getSnapshot().phase == "idle" && !controller.canFire(),"跨其他武器完成收锤而不授权长枪击发");
        unit.攻击模式 = "兵器"; tick(); ticks(14);
        unit.攻击模式 = "长枪"; tick();
        var heldPose:Number = controller.getSnapshot().poseId;
        var previousMan:MovieClip = unit.man;
        unit.man = unit.createEmptyMovieClip("newMan",unit.getNextHighestDepth());
        ticks(20);
        check(controller.getSnapshot().phase == "toGun" && controller.getSnapshot().poseId == heldPose,"旧man仍存活也不能吞完收锤动画");
        attachSkins();
        check(unit.长枪_引用 === gun && unit.dressupRegistry["长枪_引用#1@装扮"] == undefined,"成熟装扮管理器接管活动man规范引用");
        ticks(14); tick();
        check(controller.getSnapshot().phase == "idle" && controller.canFire(),"新显示就位后完成剩余收锤");
        previousMan.removeMovieClip();
    }

    private static function testBoundaryRecovery():Void {
        unit.攻击模式 = "长枪"; unit.状态 = "技能";
        unit.man.createEmptyMovieClip("兵器使用标签",unit.man.getNextHighestDepth());
        var bullets:Number = emitted;
        unit.刀口位置生成子弹(unit,{子弹威力:1});
        check(emitted == bullets + 3,"刀技首个判定不依赖下一次装备周期或攻击模式切换");
        check(blade.动画._visible && !gun.动画._visible,"刀技借用锤态且刀枪唯一显示");
        tick();
        unit.man.兵器使用标签.removeMovieClip(); unit.状态 = "长枪站立"; tick();
        check(controller.canFire() && gun.动画._visible && !blade.动画._visible,"刀技结束恢复原枪态");

        unit.长枪.value.shot = 0;
        unit.长枪射击(gun.枪口位置,props);
        unit.攻击模式 = "手枪"; tick(); unit.攻击模式 = "长枪"; tick();
        check(controller.getSnapshot().phase == "recovery" && !controller.canFire(),"切出再切回不能清掉射后回收锁");
        unit.状态 = "技能";
        unit.man.createEmptyMovieClip("兵器使用标签",unit.man.getNextHighestDepth());
        bullets = emitted; unit.刀口位置生成子弹(unit,{子弹威力:1}); tick();
        check(emitted == bullets + 3 && controller.getSnapshot().phase == "recovery","回收期间借用刀技不吞判定且保留回收时钟");
        unit.man.兵器使用标签.removeMovieClip(); unit.状态 = "长枪站立";
        ticks(32);
        check(controller.canFire(),"跨模式回收在原期限结束后恢复击发");

        var oldEntry:Number = poseData.config.normalFireEntry0;
        poseData.config.normalFireEntry0 = 8.5;
        controller["onDataReady"](poseData);
        check(controller.getSnapshot().phase == "failed" && controller.canFire(),"小数源帧在入口拒绝并保留普通射击");
        poseData.config.normalFireEntry0 = oldEntry;
        controller["onDataReady"](poseData);
        controller["begin"]("recovery",[{clip:"missing"}],15,"idle",time);
        check(controller.getSnapshot().phase == "failed" && controller.canFire(),"路径生成失败不会留下无出口的回收状态");
        controller["onDataReady"](poseData); tick();
    }

    private static function testTransitionMeleeMode(asset:MovieClip):Void {
        DressupInitializer.teardownLifeCycles(unit); unit.dispatcher.destroy(); unit.removeMovieClip();
        configureUnit(asset,false,null,null,0,"兵器");
        check(unit.攻击模式 == "兵器" && unit.状态 == "兵器站立" && unit.刀 === unit.长枪,
            "按过场保存的兵器模式重建角色时不因canonical空刀槽切空手");
        check(unit.兵器动作类型 == "狂野","延后模式校验保留M7生命周期装入的狂野动作");
        tick(); ticks(14);
        check(controller.canMelee() && controller.getSnapshot().phase == "hammer",
            "重建后自动完成锤形态准备并允许近战");
        var shots:Number = emitted; unit.刀口位置生成子弹(unit,{子弹威力:1780});
        check(emitted == shots+3,"重建保持的兵器模式可通过真实刀口链攻击");
    }

    private static function testHammerPluginProjection(asset:MovieClip):Void {
        var sets:Array = [["动力液压杆"],["纳米执行单元","绯红忆弦轮"]];
        for (var index:Number = 0; index < sets.length; index++) {
            DressupInitializer.teardownLifeCycles(unit); unit.dispatcher.destroy(); unit.removeMovieClip();
            var mods:Array = sets[index];
            var calculated:Object = EquipmentCalculator.calculatePure(itemConfig,{level:1,mods:mods},EquipmentConfigManager.getFullConfig(),ModRegistry.getModDict());
            configureUnit(asset,false,calculated,mods,27);
            check(unit.刀属性.power == 917,"独立锋利度890只叠一次全身刀锋利度加成，不复制主枪威力");
            check(unit.hp满血值装备加层 == calculated.data.hp && unit.装备防御力 == calculated.data.defence,
                "刀槽借用不重复计入宿主插件生命和防御");
            check(itemConfig.data.slay == undefined && itemConfig.data.vampirism == undefined && knifeDonor.power == 130,
                "计算真实插件和借刀投影不污染基础武器或供体");
            unit.基础吸血 = 2; unit.基础斩杀 = 2;
            unit.攻击模式 = "兵器"; unit.状态 = "兵器站立"; tick(); ticks(14);
            unit.根据模式重新读取武器加成("兵器");
            unit.刀口位置生成子弹(unit,{子弹威力:1780});
            BulletInitializer.inheritShooterAttributes(lastBullet,unit);
            if (index == 0) {
                check(calculated.data.slay == 8 && unit.兵器斩杀 == 8 && lastBullet.斩杀 == 10,
                    "真实动力液压杆8%斩杀与基础2%通过兵器槽和子弹继承各计一次");
                var result:DamageResult = new DamageResult(); result.actualScatterUsed = 1;
                var enemy:Object = {hp:120,hp满血值:1000,损伤值:30,shield:{getStrength:function():Number {return 0;},getCapacity:function():Number {return 0;}}};
                ExecuteDamageHandle.getInstance().handleBulletDamage(lastBullet,unit,enemy,null,result);
                check(enemy.hp == 0 && enemy.损伤值 == 120,"继承的斩杀在真实处理器中处决阈值内目标");
                unit.长枪毒 = 3; unit.长枪击溃 = .2;
                var crit:Function = function():Number {return 1.5;}; unit.长枪暴击 = crit;
                unit.刀口位置生成子弹(unit,{子弹威力:1780});
                check(lastBullet.毒 == 3 && lastBullet.血量上限击溃 == .2 && lastBullet.暴击 === crit
                    && lastBullet.命中率 == 400,"毒击溃暴击命中沿同一已结算词条投影");
            } else {
                check(calculated.data.vampirism == 5 && unit.兵器吸血 == 5 && lastBullet.吸血 == 7,
                    "真实忆弦轮5%吸血与基础2%在兵器攻击中各计一次");
                var healer:Object = {hp:500,hp满血值:1000};
                var healResult:DamageResult = new DamageResult(); healResult.actualScatterUsed = 1;
                LifeStealDamageHandle.getInstance().handleBulletDamage(lastBullet,healer,{hp:1000,损伤值:100},null,healResult);
                check(healer.hp == 507,"继承的吸血在真实处理器中恢复7点HP");
                var source:Object = {子弹威力:1780,吸血:20,斩杀:30};
                unit.刀口位置生成子弹(unit,source);
                check(lastBullet.吸血 == 20 && lastBullet.斩杀 == 30 && source.伤害类型 == undefined,
                    "技能明确更高的吸血斩杀保留且不污染输入模板");
            }
            for (var cycle:Number = 0; cycle < 3; cycle++) {
                unit.攻击模式 = "长枪"; unit.根据模式重新读取武器加成("长枪"); tick(); ticks(14);
                unit.攻击模式 = "兵器"; unit.根据模式重新读取武器加成("兵器"); tick(); ticks(14);
            }
            unit.刀口位置生成子弹(unit,{子弹威力:1780});
            check(lastBullet.斩杀 == (index == 0 ? 10 : 2) && lastBullet.吸血 == (index == 0 ? 2 : 7),
                "反复枪锤切换不累计插件百分比");
            unit.攻击模式 = "手枪"; unit.状态 = "技能";
            unit.根据模式重新读取武器加成("手枪");
            unit.man.createEmptyMovieClip("兵器使用标签",unit.man.getNextHighestDepth());
            unit.刀口位置生成子弹(unit,{子弹威力:1780});
            check(lastBullet.斩杀 == (index == 0 ? 10 : 2) && lastBullet.吸血 == (index == 0 ? 2 : 7),
                "其他攻击模式临时借用刀技仍接收这把锤的插件词条");
            unit.man.兵器使用标签.removeMovieClip();
            if (index == 0) unit.兵器吸血 = 77;
            DressupInitializer.teardownLifeCycles(unit);
            check(unit.兵器斩杀 == 0 && unit.兵器吸血 == (index == 0 ? 77 : 0),
                "卸载恢复自己投影的属性并保留后来接管的字段");
        }
        unit.dispatcher.destroy(); unit.removeMovieClip();
        configureUnit(asset,false);
    }

    private static function testCleanupAndRealBlade(asset:MovieClip):Void {
        var fire:Function = WeaponFireCore.LONG_GUN_SHOOT;
        DressupInitializer.teardownLifeCycles(unit);
        check(!controller.getSnapshot().active && unit.__pileBunkerM7 == undefined,"生产卸载清理控制器");
        check(unit.长枪射击 === fire && unit.刀口位置生成子弹 === BladeShootCore.shoot,"恢复本人持有的攻击入口");
        check(unit.刀 == null,"统一projection卸载归还空刀槽");
        check(controller["strikeArea"] == null && unit.兵器斩杀 == 0 && unit.兵器吸血 == 0,
            "卸载清理判定区域和本装备借用的战斗词条");
        check(unit.dispatcher["_subCount"] == baselineSubscriptions,"控制器精确退订，不移除基础开火事件");
        unit.dispatcher.destroy(); unit.removeMovieClip();
        var calls:Number = knifeConfigCalls;
        configureUnit(asset,true);
        check(!controller.getSnapshot().alias && unit.刀.name == "真实冷兵器" && knifeConfigCalls == calls,"已有冷兵器不被借用或配置覆盖");
        check(unit.兵器吸血 == 9 && unit.兵器斩杀 == 4,"真实冷兵器已有吸血斩杀不被长枪词条覆盖");
        unit.version++;
        controller.tick();
        check(!controller.getSnapshot().active,"版本失配释放旧状态");
        DressupInitializer.teardownLifeCycles(unit);
        check(unit.刀.name == "真实冷兵器","stale清理保留真实刀槽");
    }

    private static function finish():Void {
        if (finished) return;
        finished = true;
        if (controller) controller.dispose();
        NamedPoseDataStore.release(poseLease); poseLease = null; poseData = null;
        check(NamedPoseDataStore.inspect(posePath).status == "absent","最后租用者卸载后释放姿态缓存");
        if (unit) { unit.dispatcher.destroy(); unit.removeMovieClip(); }
        delete watchdog.onEnterFrame; loader.removeListener(listener);
        loaded.removeMovieClip(); watchdog.removeMovieClip();
        if (fxLoader) fxLoader.removeListener(fxListener);
        if (fxLibrary) fxLibrary.removeMovieClip();
        _root.战技路由 = oldWeaponRoute;
        _root.帧计时器 = oldClock; _root.按键输入检测 = oldInput; _root.刀配置 = oldKnife;
        _root.子弹区域shoot传递 = oldShoot; _root.装备生命周期函数.移除异常周期函数 = oldCleanup;
        _root.gameworld = oldWorld; _root.控制目标 = oldControl;
        _root.攻击模式 = oldRootMode; _root.当前玩家总数 = oldPlayers; _root.暂停 = oldPaused;
        trace("PileBunkerM7Test Tests Passed: " + passed);
        trace("PileBunkerM7Test Tests Failed: " + failed);
        _root.pileBunkerM7FocusedComplete();
    }
}
