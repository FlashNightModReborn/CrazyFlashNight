import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.hud.PlayerHudBuffProjection;

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
            runAttackPaths();
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
    // 两次都从满能开始。仅截获最终弹体，不直接调用雷电函数。
    private static function runAttackPaths():Void {
        var world:MovieClip = _root.createEmptyMovieClip("__deadHandArena",_root.getNextHighestDepth());
        var saved:Object = {world:_root.gameworld, chance:_root.成功率, bullet:_root.子弹区域shoot传递, pause:_root.暂停};
        var unit:MovieClip = world.createEmptyMovieClip("hero",1);
        var enemy:MovieClip = world.createEmptyMovieClip("enemy",2);
        var ref:Object;
        var fns:Object = _root.装备生命周期函数;
        try {
            _root.gameworld = world; _root.暂停 = false;
            _root.成功率 = function(chance:Number):Boolean { return true; };
            var emitted:Array = [];
            _root.子弹区域shoot传递 = function(props:Object):Void {
                emitted.push({kind:props.子弹种类,x:props.shootX,z:props.shootZ});
            };
            world.dispatcher = new EventDispatcher();
            unit.version=5; unit.hp=100; unit.是否为敌人=false;
            unit._x=600; unit._y=160; unit.Z轴坐标=160;
            enemy._x=940; enemy._y=180; enemy.Z轴坐标=180; enemy.hp=100; enemy.是否为敌人=true;
            enemy.aabbCollider={left:930,right:950,top:130,bottom:180};
            unit.aabbCollider={left:590,right:610,top:110,bottom:160};
            TargetCacheManager.initialize(); TargetCacheManager.addUnit(unit); TargetCacheManager.addUnit(enemy);
            unit.刀={name:"死者之手",value:{level:1,shot:0,mods:[]}};
            unit.刀属性={power:550,damagetype:"物理",magictype:""};
            unit.兵器动作类型="刀剑"; unit.兵器伤害类型="物理"; unit.兵器魔法伤害属性="";
            unit.长枪=null; unit.攻击模式="兵器"; unit.状态="兵器站立";
            unit.man=unit.createEmptyMovieClip("man",1);
            unit.dispatcher=new EventDispatcher(); unit.enableShoot=true;
            FireEventComponent.initialize(unit);
            unit.长枪射击=WeaponFireCore.LONG_GUN_SHOOT;
            var blade:MovieClip=attach(unit,"刀","刀_引用");
            var gun:MovieClip=attach(unit,"枪","长枪_引用");
            _root.长枪配置=function():Void { unit.长枪属性={power:550}; };
            RuntimeEquipmentProjection.beginCanonical(unit);
            ref={自机:unit,装备类型:"刀",装备名称:"死者之手",版本号:unit.version,生命周期函数列表:[]};
            fns.死者之手初始化(ref,{gunDressup:"TestProbeSkin"});
            check(RuntimeEquipmentProjection.completeCanonical(unit), "普攻夹具建立真实空长枪槽借用");
            var hud:PlayerHudBuffProjection = new PlayerHudBuffProjection();
            for (var mode:Number=0; mode<2; mode++) {
                unit.攻击模式=mode==0?"兵器":"长枪";
                unit.状态=unit.攻击模式+"站立";
                fns.死者之手处理武器切换(ref);
                _root.帧计时器.当前帧数+=10;
                unit.dispatcher.publish("WeaponSkill",unit.攻击模式);
                check(ref.超载模式 && ref.超载能量==120 && ref.当前战技阶段==2,
                    unit.攻击模式+"初次战技从满能进入二段");
                var start:Number=emitted.length;
                _root.帧计时器.当前帧数+=7;
                if (mode==0) {
                    unit.状态="兵器攻击";
                    unit.man.兵器使用标签=true; unit.man.兵器攻击标签=true;
                    fns.死者之手周期(ref,{});
                    delete unit.man.兵器使用标签; delete unit.man.兵器攻击标签;
                    check(emitted.length==start+1 && emitted[start].kind==ref.子弹配置.子弹种类,
                        "普通兵器攻击标签经装备周期只发一次雷电");
                } else {
                    var before:Number=unit.长枪.value.shot;
                    var shot:Object={ammoCost:1,霰弹值:1,子弹速度:20,站立子弹散射度:0};
                    var fired:Boolean=unit.长枪射击(null,shot);
                    check(fired && unit.长枪.value.shot==before+1 && emitted.length==start+2,
                        "借用长枪走公共出弹/扣弹与武器订阅，分别发出枪弹和雷电");
                    var lightning:Object=emitted[start].kind==ref.子弹配置.子弹种类 ? emitted[start] : emitted[start+1];
                    check(lightning.kind==ref.子弹配置.子弹种类 && lightning.x==enemy._x && lightning.z==enemy.Z轴坐标,
                        "借枪雷电由真实寻敌缓存投到目标的横纵位置");
                }
                unit.状态=unit.攻击模式+"站立";
                for (var tick:Number=0; tick<20; tick++) {
                    _root.帧计时器.当前帧数++;
                    fns.死者之手周期(ref,{});
                }
                var rows:Array=hud.snapshotFor(unit);
                check(ref.超载模式 && ref.超载能量==105 && ref.当前战技阶段==2 &&
                    unit.主动战技.兵器.名字=="凶斩" && rows[0].info.description.indexOf("105/120")>=0,
                    unit.攻击模式+"一次有效触发后恢复站立仍保有105能量、二段与状态卡");
                check((mode==0 ? blade._visible && !gun._visible : gun._visible && !blade._visible && ref.握柄当前帧==46)
                    && ref.御坂当前帧==16, unit.攻击模式+"动作结束后超载制御板及对应武器外观保持展开");
                trace("[DEAD_HAND_ATTACK] mode="+unit.攻击模式+" energy="+ref.超载能量+" stage="+ref.当前战技阶段+
                    " blade="+blade._visible+" gun="+gun._visible+" grip="+ref.握柄当前帧+" board="+ref.御坂当前帧);
                // 开始第二个独立满能样本前，结束第一个样本，不产生一次额外雷电。
                fns.死者之手结束超载(ref,false,false);
            }
        } finally {
            if (ref) fns.死者之手卸载(ref);
            TargetCacheManager.removeUnit(enemy); TargetCacheManager.removeUnit(unit);
            world.removeMovieClip();
            _root.gameworld=saved.world; _root.暂停=saved.pause; _root.成功率=saved.chance; _root.子弹区域shoot传递=saved.bullet;
        }
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
        var spearArt:MovieClip = blade.createEmptyMovieClip("枪头组件", blade.getNextHighestDepth());
        spearArt._y = 19;
        var edge:MovieClip = blade.createEmptyMovieClip("刀口位置1", blade.getNextHighestDepth());
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
        unit.攻击模式 = "兵器"; unit.状态 = "兵器站立";
        functions.死者之手同步视觉(ref);
        functions.死者之手切换冷兵器形态(ref, null);
        functions.死者之手同步视觉(ref);
        check(ref.冷兵器模式 == "长矛" && spearArt._y == 7 && edge._y == 460 && blade._y == 0,
            "长矛可见素材上移十二像素，刀口与整个武器挂点保持原判定");
        functions.死者之手同步视觉(ref);
        check(spearArt._y == 7 && pistolIntact(pistol, pistolId), "重复同步不累加偏移或改写手枪");
        functions.死者之手切换冷兵器形态(ref, null);
        check(spearArt._y == 19 && edge._y == 285, "切换镰刀恢复绘制基准与该形态刀口");
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