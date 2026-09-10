import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.P90EnergyGenerator;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.component.Buff.Effect.FireControlVulnerability;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.RespawnEventComponent;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletHitEffectRegistry;

/** 真实XML、通用loader、真实护盾与Buff；只隔离世界时钟和喷气背包美术。 */
class org.flashNight.arki.unit.UnitComponent.Initializer.test.TitaniumSetRuntimeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var configs:Object;
    private static var items:Object;
    private static var weapons:Object;
    private static var oldWorld:Object;
    private static var oldBulletFactory:Function;
    private static var oldUi:Object;
    private static var emitted:Object;
    private static var messages:Array;
    private static var tasks:Array;
    private static var units:Array;
    private static var oldClock:Object;
    private static var oldConfig:Object;
    private static var oldItems:Object;
    private static var oldControl;
    private static var oldMessage:Function;
    private static var oldCleanup:Function;
    private static var oldGetSkill:Function;
    private static var oldJetInit:Function;
    private static var oldJetCycle:Function;
    private static var completed:Boolean;
    private static var watchdog:MovieClip;
    private static var serial:Number;
    private static var slots:Array = ["头部装备", "上装装备", "下装装备", "脚部装备", "手部装备"];

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[FAIL] TitaniumSetRuntimeTest: " + label); }
    }
    private static function near(a:Number, b:Number):Boolean { return Math.abs(a - b) < 0.00001; }

    public static function runAllTests():Void {
        passed = 0; failed = 0; serial = 0; tasks = []; units = []; completed = false;
        oldWorld = _root.gameworld; oldBulletFactory = _root.子弹区域shoot传递; oldUi = _root.玩家信息界面;
        _root.gameworld = _root; _root.玩家信息界面 = {玩家必要信息界面:{}};
        _root.子弹区域shoot传递 = function(props:Object):Void { TitaniumSetRuntimeTest.emitted = props; };
        weapons = {}; messages = [];
        oldClock = _root.帧计时器; oldConfig = ItemUtil.itemSetConfigDict; oldControl = _root.控制目标;
        oldItems = ItemUtil.itemDataDict; ItemUtil.itemDataDict = {};
        oldMessage = _root.发布消息; oldCleanup = _root.装备生命周期函数.移除异常周期函数;
        oldGetSkill = _root.主角函数.获取装备主动战技种类;
        oldJetInit = _root.装备生命周期函数.喷气背包初始化;
        oldJetCycle = _root.装备生命周期函数.喷气背包周期;
        _root.帧计时器 = {当前帧数:0, 帧率:30,
            taskManager:{addLifecycleTask:function(owner:Object, label:String, action:Function, interval:Number, args:Array):String {
                var id:String = "ti-test:" + TitaniumSetRuntimeTest.tasks.length;
                TitaniumSetRuntimeTest.tasks.push({owner:owner,label:label,action:action,args:args,active:true}); return id;
            }},
            移除生命周期任务:function(owner:Object,label:String):Void {
                for (var i:Number = 0; i < TitaniumSetRuntimeTest.tasks.length; i++) {
                    var entry:Object = TitaniumSetRuntimeTest.tasks[i];
                    if (entry.owner === owner && entry.label == label) entry.active = false;
                }
            }};
        _root.发布消息 = function(message):Void { TitaniumSetRuntimeTest.messages.push(message); };
        _root.主角函数.获取装备主动战技种类 = function(slot:String, use:String):String { return null; };
        _root.装备生命周期函数.移除异常周期函数 = function(ref:Object):Void {};
        _root.装备生命周期函数.喷气背包初始化 = function(ref:Object, param:Object):Void { ref.自机.jetpackInitializations++; };
        _root.装备生命周期函数.喷气背包周期 = function(ref:Object, param:Object):Void {};
        watchdog = _root.createEmptyMovieClip("__ti61Watch", _root.getNextHighestDepth());
        watchdog.count = 0;
        watchdog.onEnterFrame = function():Void {
            if (++this.count > 240) { TitaniumSetRuntimeTest.check(false,"XML加载超时"); TitaniumSetRuntimeTest.finish(); }
        };
        loadDocument(0);
    }

    private static function loadDocument(index:Number):Void {
        var document = new XML(); document.ignoreWhite = true; document.testIndex = index;
        document.onLoad = function(ok:Boolean):Void {
            if (!ok) { TitaniumSetRuntimeTest.check(false,"真实XML加载失败"); TitaniumSetRuntimeTest.finish(); return; }
            var parsed:Object = XMLParser.parseXMLNode(this.firstChild);
            if (this.testIndex == 0) {
                TitaniumSetRuntimeTest.configs = {};
                for (var i:Number = 0; i < parsed.set.length; i++) {
                    TitaniumSetRuntimeTest.configs[parsed.set[i].id] = parsed.set[i];
                }
                TitaniumSetRuntimeTest.loadDocument(1);
            } else if (this.testIndex == 1) {
                TitaniumSetRuntimeTest.items = {};
                for (var j:Number = 0; j < parsed.item.length; j++) {
                    var item:Object = parsed.item[j];
                    if (item.setId == "titanium_type_61_armor") TitaniumSetRuntimeTest.items[item.use] = item;
                }
                TitaniumSetRuntimeTest.loadDocument(2);
            } else {
                for (var k:Number = 0; k < parsed.item.length; k++) {
                    TitaniumSetRuntimeTest.weapons[parsed.item[k].name] = parsed.item[k];
                }
                if (this.testIndex < 4) TitaniumSetRuntimeTest.loadDocument(this.testIndex + 1);
                else TitaniumSetRuntimeTest.execute();
            }
        };
        var paths:Array = ["../data/items/item_sets.xml", "../data/items/防具_40+级.xml",
                           "../data/items/武器_手枪_冲锋枪.xml", "../data/items/武器_长枪_机枪.xml", "../data/items/武器_刀_直剑.xml"];
        document.load(paths[index]);
    }

    private static function makeUnit(count:Number, weight:Number, invalid:Boolean, duplicate:Boolean, external:Boolean, bloodLevel:Number):MovieClip {
        var unit:MovieClip = _root.createEmptyMovieClip("__ti61Unit" + (++serial), _root.getNextHighestDepth());
        units.push(unit); _root.控制目标 = unit._name;
        unit.dispatcher = new EventDispatcher();
        unit.man = unit.createEmptyMovieClip("man",1); unit.man.换弹标签 = false;
        unit.enableShoot = true; unit.状态 = "站立"; unit.攻击模式 = "双枪"; unit.Z轴坐标 = 0;
        FireEventComponent.initialize(unit);
        unit.version = serial; unit.等级 = 55; unit.重量 = weight;
        var ratio:Number = org.flashNight.arki.unit.UnitUtil.getWeightSpeedRatio(weight,55);
        unit.行走X速度 = 4 * ratio; unit.起跳速度 = -10 * ratio;
        unit.hp满血值 = 5000; unit.hp = 5000; unit.mp满血值 = 3000; unit.mp = 3000;
        unit.伤害加成 = 440; unit.魔法抗性 = {基础:15}; unit.jetpackInitializations = 0;
        unit.刀 = {name:"血色光剑天秤",value:{level:bloodLevel || 1}};
        unit.生命周期函数列表 = []; unit.主动战技 = {};
        unit.装载生命周期函数 = _root.主角函数.装载生命周期函数;
        unit.完成生命周期函数装载 = _root.主角函数.完成生命周期函数装载;
        unit.shield = AdaptiveShield.createDormant("ti-test"); unit.shield.setOwner(unit);
        unit.buffManager = new BuffManager(unit, {});
        for (var i:Number = 0; i < slots.length; i++) {
            var slot:String = slots[i];
            var source:Object = ObjectUtil.clone(items[slot]);
            if (i >= count) source.setId = "";
            unit[slot] = {name:source.name,value:{level:1}};
            unit[slot + "数据"] = source;
        }
        if (invalid) unit.上装装备数据.lifecycle.attr_0.init.initParam.shieldMpPerPoint = 0;
        if (duplicate) unit.shield.addShield(Shield.createRechargeable(90,8,0,0,TitaniumSetRuntime.SHIELD_NAME), true);
        if (external) {
            unit.externalShield = Shield.createRechargeable(100,7,0,0,"external-test");
            unit.shield.addShield(unit.externalShield,true);
        }
        SetEffectController.prepare(unit);
        for (i = 0; i < slots.length; i++) unit.装载生命周期函数(unit[slots[i] + "数据"].lifecycle,slots[i]);
        unit.完成生命周期函数装载();
        return unit;
    }

    private static function advance(frames:Number):Void {
        for (var n:Number = 0; n < frames; n++) {
            _root.帧计时器.当前帧数++;
            var snapshot:Array = tasks.slice();
            for (var i:Number = 0; i < snapshot.length; i++) {
                var task:Object = snapshot[i];
                if (task.active && task.owner._parent) task.action.apply(task.owner, task.args);
            }
        }
    }
    private static function setTaskCount(unit:MovieClip):Number {
        var n:Number = 0;
        for (var i:Number = 0; i < tasks.length; i++) if (tasks[i].active && tasks[i].owner === unit && tasks[i].label.indexOf("set:") == 0) n++;
        return n;
    }
    private static function closeUnit(unit:MovieClip):Void {
        DressupInitializer.teardownLifeCycles(unit);
        unit.dispatcher.destroy();
        unit.buffManager.destroy();
        unit.removeMovieClip();
    }

    private static function execute():Void {
        ItemUtil.itemSetConfigDict = configs;
        try {
            check(TitaniumSetRuntime.affordableUnits(0.15, Number("0.15"))==1,"十进制配置尾差不吞最后一点治疗");
            check(TitaniumSetRuntime.affordableUnits(0.1499, Number("0.15"))==0,"真实不足仍不授予治疗");
            check(TitaniumSetRuntime.affordableUnits(0, Number("0.15"))==0,"零MP不能靠容差产生治疗");
            for (var count:Number = 0; count < 5; count++) {
                var partial:MovieClip = makeUnit(count,200,false,false,false);
                check(partial.__titaniumType61 == undefined,"不足五甲不激活："+count);
                check(setTaskCount(partial)==0,"不足五甲无套装周期："+count);
                if (count==4) check(partial.jetpackInitializations==1,"四甲仍保留胸甲喷气背包");
                closeUnit(partial);
            }
            var unit:MovieClip = makeUnit(5,200,false,false,true);
            var runtime:TitaniumSetRuntime = unit.__titaniumType61;
            runtime.constrainInitialShieldToPreviousHealth(4999,5000);
            check(runtime != undefined,"五甲真实loader激活");
            check(setTaskCount(unit)==1,"只有胸甲一个中央周期");
            var shield:Shield = Shield(unit.shield.getShieldById(runtime.getShieldId()));
            check(shield.getName()==TitaniumSetRuntime.SHIELD_NAME,"具名专属层");
            check(shield.getCapacity()==0 && shield.getStrength()==0,"创建时零容量零特殊防护");
            check(shield.getRechargeRate()==0 && !shield.getResistBypass(),"禁止免费回盾与抗旁路");
            check(unit.shield.getShieldCount()==2,"与外部护盾并存");
            check(unit.shield.getCapacity()==100,"初始聚合只含外部盾");
            var night:Object = WeatherSystem.getInstance().getNightVisionManager();
            check(night.validate(2,unit)=="高级夜视仪","主角低光夜视");
            check(night.validate(8,unit)==null,"白天停用");
            check(night.validate(2,unit)=="高级夜视仪","昼夜往返可以再次启用");
            advance(1);
            check(near(shield.getCapacity(),62.5),"首脉冲恢复最大盾量5%");
            check(near(unit.mp,2908.75),"启动60加实际充能31.25MP");
            check(near(unit.shield.getCapacity(),162.5),"手动充能刷新多盾缓存");
            check(shield.getStrength()==1250,"正容量后固定满盾强");
            check(unit.重量==184,"在线血剑减重只应用一次");
            check(near(unit.行走X速度,4),"动力伺服恢复正常速度");
            var before:Number = unit.mp;
            runtime.tick(null);
            check(unit.mp==before,"同帧不重复维护");
            advance(120);
            check(shield.getCapacity()==1250,"四秒充满五甲HP的一半");
            check(near(runtime.getDiagnostics().mpSpent,685),"每2盾1MP加启动60");
            check(runtime.getState()=="ONLINE_FULL","满盾状态");
            check(unit.externalShield.getCapacity()==100,"不消费或修复外部盾");
            unit.hp=4980; before=unit.mp; advance(6);
            check(unit.hp>4980,"在线也进行生命维持");
            check(unit.mp<before,"在线治疗按实际恢复付费");
            check(near(unit.伤害加成,440),"在线治疗不启用破盾增伤");
            unit.hp=5000;
            var externalSpeed:String = unit.buffManager.addBuff(new PodBuff("行走X速度",BuffCalculationType.MULT_POSITIVE,1.5),"external-speed");
            unit.buffManager.update(0); advance(6);
            check(near(unit.行走X速度,4.5),"更强速度Buff取高不与伺服相乘");
            unit.buffManager.removeBuff(externalSpeed); unit.buffManager.update(0);
            unit.buffManager.setBaseValue("重量",-5); advance(6);
            check(unit.重量==-21 && near(unit.行走X速度,5),"负重基值重写后实际轻装速度重算");
            unit.mp=0; shield.setCapacity(1); advance(1);
            check(shield.getStrength()==1250,"一点残盾仍固定盾强");
            check(near(shield.absorbDamage(100,false,1),99),"残盾实际只能吸收剩余一点");
            check(shield.getStrength()==0,"破盾立即撤销特殊防护");
            check(unit.重量==-5,"破盾立即撤销减重");
            check(unit.shield.getStrength()==7,"外部盾强不被清零");
            unit.hp=2500; before=unit.mp; advance(6);
            check(unit.hp==2500 && unit.mp==before,"零MP没有免费治疗");
            check(unit.伤害加成>440,"破盾按当前缺血提高通用伤害");
            check(night.validate(2,unit)=="高级夜视仪","破盾零MP仍有夜视");
            unit.hp=5000; unit.mp=60; advance(6);
            check(runtime.getState()=="REBOOTING" && shield.getCapacity()==0,"仅够启动费时不赠一点盾");
            var startupCount:Number = runtime.getDiagnostics().startups;
            unit.hp=4999; advance(6);
            check(runtime.getState()=="BREACHED" && runtime.getDiagnostics().startupPaid,"受伤退回维生并保留启动凭证");
            unit.mp=0.15;
            advance(6);
            check(unit.hp==5000,"最后一点HP可精确付费恢复");
            check(runtime.getDiagnostics().startups==startupCount,"同破碎周期不重复收费");
            unit.mp=8; advance(6);
            check(shield.getCapacity()>0 && !runtime.getDiagnostics().startupPaid,"首次正容量消费启动凭证");
            shield.consumeCapacity(shield.getCapacity()); unit.hp=7500; unit.mp=100; advance(6);
            check(unit.hp==7500 && shield.getCapacity()>0,"超血允许重启且不削掉超血");
            check(unit.伤害加成==440,"超血不产生负缺血增伤");
            unit.shield.removeShieldById(runtime.getShieldId()); advance(1);
            check(runtime.getState()=="OFFLINE" && setTaskCount(unit)==0,"专属层丢失失败关闭并停任务");
            check(unit.externalShield.getCapacity()==100,"维护失败不删外部盾");
            check(unit.重量==-5 && unit.伤害加成==440,"维护失败清理全部套装Buff");
            check(night.validate(2,unit)==null,"维护失败注销夜视");
            closeUnit(unit);
            var bad:MovieClip=makeUnit(5,200,true,false,true);
            check(bad.__titaniumType61==undefined && setTaskCount(bad)==0,"非法参数整组回滚");
            check(bad.shield.getShieldCount()==1,"回滚保留既有外部盾");
            check(WeatherSystem.getInstance().getNightVisionManager().validate(2,bad)==null,"中途初始化失败释放夜视");
            closeUnit(bad);
            var duplicate:MovieClip=makeUnit(5,200,false,true,false);
            check(duplicate.__titaniumType61==undefined,"拒绝同名残留层");
            check(duplicate.shield.getShieldCount()==1,"拒绝初始化不误删残留所有者");
            closeUnit(duplicate);
            var dying:MovieClip=makeUnit(5,200,false,false,false); advance(6);
            dying.hp=0; advance(1);
            check(dying.__titaniumType61!=undefined && setTaskCount(dying)==1,"死亡暂停而不卸掉复活需要的周期");
            check(dying.shield.getCapacity()==0 && dying.shield.getStrength()==0,"死亡清空盾量和盾强");
            var savedRuntime:Object = dying.__titaniumType61;
            var savedManager:Object = dying.buffManager;
            var externalBuff:String = dying.buffManager.addBuff(new PodBuff("伤害加成",BuffCalculationType.ADD,123),"revive-external");
            dying.动画完毕=function():Void { this.状态="兵器站立"; };
            RespawnEventComponent.onRespawn(dying); advance(1);
            check(dying.__titaniumType61===savedRuntime && savedRuntime.isOnline(),"原运行态复活恢复满盾");
            check(dying.buffManager===savedManager && near(dying.伤害加成,563),"复活保留其他Buff和属性基底");
            dying.hp=0; advance(1); RespawnEventComponent.onRespawn(dying); advance(1);
            check(setTaskCount(dying)==1 && dying.shield.getShieldCount()==1,"连续复活不堆周期或护盾");
            dying.shield.getShieldById(savedRuntime.getShieldId()).setCapacity(10);
            RespawnEventComponent.onRespawn(dying);
            check(dying.shield.getCapacity()==10,"存活时重复复活通知不免费刷新盾");
            dying.hp=0; dying._killed=true; RespawnEventComponent.onRespawn(dying);
            check(savedRuntime.isOnline() && dying.shield.getCapacity()==1250,"死亡当帧立即复活也由真实事件恢复");
            closeUnit(dying);
            testInitialShield();
            testEnergyAndAmmo();
            testFireControl();
            testReloadInterleaving();
            testBloodPact();
            testFireControlVulnerability();
            testSecondaryData();
        } catch (error) {
            check(false,"unexpected exception: "+error);
        }
        finish();
    }

    private static function equipWeapon(unit:MovieClip, slot:String, name:String, initialize:Boolean):Object {
        var source:Object = ObjectUtil.clone(weapons[name]);
        check(source != undefined, "武器真实XML：" + name);
        unit[slot + "数据"] = source;
        unit[slot + "属性"] = source.data;
        unit[slot + "弹匣容量"] = Number(source.data.capacity);
        unit[slot] = {name:name, value:{level:1,shot:0,reloadCount:0}};
        if (initialize && source.lifecycle.attr_0) unit.装载生命周期函数({attr_0:source.lifecycle.attr_0},slot);
        return unit[slot];
    }

    private static function shoot(unit:MovieClip, slot:String, guard:Function):Boolean {
        return WeaponFireCore.executeShot(unit, slot, unit.man, {站立子弹散射度:0,移动子弹散射度:1}, guard);
    }

    private static function fillShield(unit:MovieClip):Void {
        var runtime:TitaniumSetRuntime = unit.__titaniumType61;
        var shield:Shield = Shield(unit.shield.getShieldById(runtime.getShieldId()));
        shield.setCapacity(shield.getMaxCapacity());
        advance(1);
    }

    private static function testInitialShield():Void {
        var unit:MovieClip=makeUnit(5,200,false,false,true);
        var runtime:TitaniumSetRuntime=unit.__titaniumType61;
        var shield:Shield=Shield(unit.shield.getShieldById(runtime.getShieldId()));
        unit.mp=0; advance(1);
        check(shield.getCapacity()==1250 && shield.getStrength()==1250,"满血新单位首帧免费满盾且无需MP");
        check(runtime.getDiagnostics().initialShieldGranted==1250 && runtime.getDiagnostics().mpSpent==0,"免费初始盾单独记账不冒充付费充能");
        check(runtime.getDiagnostics().startups==0 && unit.mp==0,"免费初始盾不收启动费");
        check(unit.externalShield.getCapacity()==100 && unit.重量==184,"立即满盾刷新实际伺服且保留外部盾");
        shield.consumeCapacity(100); advance(6);
        check(shield.getCapacity()==1150,"免费初始机会只兑现一次，受损后不重复赠盾");
        shield.consumeCapacity(shield.getCapacity()); unit.mp=68; advance(6);
        check(shield.getCapacity()==16 && unit.mp==0 && runtime.getDiagnostics().startups==1,"战斗破盾后先收60MP，剩余8MP仅转16盾");
        closeUnit(unit);

        unit=makeUnit(5,0,false,false,false); runtime=unit.__titaniumType61;
        unit.hp=4990; var before:Number=unit.mp; advance(1);
        check(runtime.getDiagnostics().initialShieldGranted==0 && unit.mp<before,"带伤新单位保持付费维生，没有免费初始盾");
        unit.hp=5000; advance(6);
        check(runtime.getDiagnostics().capacity<1250 && runtime.getDiagnostics().initialShieldGranted==0,"伤后回满不会补发已错过的免费初始机会");
        closeUnit(unit);

        unit=makeUnit(5,0,false,false,false); runtime=unit.__titaniumType61;
        runtime.constrainInitialShieldToPreviousHealth(4999,6000);
        unit.hp=5000; unit.mp=0; advance(1);
        check(runtime.getDiagnostics().capacity==0,"降低上限将残血变满血仍不能骗取免费满盾");
        closeUnit(unit);

        unit=makeUnit(5,0,false,false,false); runtime=unit.__titaniumType61;
        runtime.constrainInitialShieldToPreviousHealth(5000,5000); unit.hp=7500; unit.mp=17; advance(1);
        check(runtime.getDiagnostics().capacity==1250 && unit.hp==7500 && unit.mp==17,"前后满血重建免费满盾并保留超血和原MP");
        closeUnit(unit);

        unit=makeUnit(5,0,false,false,false); runtime=unit.__titaniumType61;
        runtime.constrainInitialShieldToPreviousHealth(5000,5000); unit.hp=5000; unit.hp满血值=6000; advance(1);
        check(runtime.getDiagnostics().initialShieldGranted==0,"换装抬高上限后当前未满也不能免费生成护盾");
        closeUnit(unit);
    }

    private static function testEnergyAndAmmo():Void {
        var unit:MovieClip = makeUnit(5,100,false,false,false);
        var runtime:TitaniumSetRuntime = unit.__titaniumType61;
        var primary:Object = equipWeapon(unit,"手枪","P90",true);
        var secondary:Object = equipWeapon(unit,"手枪2","钛合金P90",true);
        unit.mp = 1600;
        check(shoot(unit,"手枪",null) && primary.value.shot==1 && unit.mp==1603,"真实普通P90发射仅获套装3MP");
        check(shoot(unit,"手枪2",null) && secondary.value.shot==1 && unit.mp==1609,"双持仅本槽P90额外回3MP");
        check(runtime.synthesizeAmmo("手枪")==0 && primary.value.shot==1,"专属零盾不补弹");
        var before:Number = unit.mp;
        check(!shoot(unit,"手枪2",function():Boolean{return false;}) && unit.mp==before && secondary.value.shot==1,"提交拒绝不回蓝不耗弹");
        secondary.value.shot = unit.手枪2弹匣容量;
        check(!shoot(unit,"手枪2",null) && unit.mp==before,"空弹匣不发电");
        secondary.value.shot--;
        check(shoot(unit,"手枪2",null) && secondary.value.shot==50 && unit.mp==before+6,"弹匣最后一发也只返6MP");
        // 将真实射击计数订阅挪到后面，验证发电不依赖 shot++ 的相对次序。
        unit.dispatcher.unsubscribe("processShot",FireEventComponent.processShot,unit);
        FireEventComponent.initialize(unit);
        secondary.value.shot=49; before=unit.mp; shoot(unit,"手枪2",null);
        check(secondary.value.shot==50 && unit.mp==before+6,"反向订阅顺序不漏末发回蓝");
        unit.mp=2999; secondary.value.shot=0; shoot(unit,"手枪2",null);
        check(unit.mp==3000,"双回蓝来源共享封顶且不保存溢出");
        primary.value.shot=0; secondary.value.shot=0;
        fillShield(unit); unit.mp=1600;
        shoot(unit,"手枪",null); before=unit.mp;
        check(runtime.synthesizeAmmo("手枪")==1 && primary.value.shot==0 && unit.mp==1600,"普通手枪发射加补弹循环MP守恒");
        shoot(unit,"手枪2",null);
        check(runtime.synthesizeAmmo("手枪2")==1 && unit.mp==1603,"套内P90闭环净收入3MP");
        primary.value.shot=5; unit.mp=1506;
        check(runtime.synthesizeAmmo("手枪")==2 && primary.value.shot==3 && unit.mp==1500,"按可支付发数部分合成且守住储备线");
        check(runtime.synthesizeAmmo("手枪")==0 && primary.value.shot==3,"储备线内不造弹");
        unit.mp=1700; primary.value.shot=10;
        check(runtime.synthesizeAmmo("手枪")==3 && primary.value.shot==7 && unit.mp==1691,"每槽每脉冲最多三发");
        unit.man.换弹标签=true; before=unit.mp;
        check(runtime.synthesizeAmmo("手枪")==0 && unit.mp==before && primary.value.shot==7,"手动换弹中无补弹扣费");
        ReloadManager.finishReload(unit.man);
        check(ReloadManager.getReloadGeneration(unit.man)>0,"真实换弹收尾推进代次");
        primary.value.shot=-1; check(runtime.synthesizeAmmo("手枪")==0,"负shot失败关闭");
        primary.value.shot=51; check(runtime.synthesizeAmmo("手枪")==0,"越界shot失败关闭");
        primary.value.shot=0.5; check(runtime.synthesizeAmmo("手枪")==0,"非整数shot失败关闭");
        primary.value.shot=5; unit.手枪弹匣容量=0; check(runtime.synthesizeAmmo("手枪")==0,"零弹容失败关闭");
        unit.手枪弹匣容量=50;
        // 属性读取之间发生 ABA 换弹：最终标签仍为false，只有代次能够识别漂移。
        unit.__capacityReads=0;
        unit.addProperty("手枪弹匣容量",function():Number {
            if (++this.__capacityReads==2) ReloadManager.finishReload(this.man);
            return 50;
        },null);
        before=unit.mp;
        check(runtime.synthesizeAmmo("手枪")==0 && primary.value.shot==5 && unit.mp==before,"提交前换弹代次漂移放弃整笔");
        delete unit.手枪弹匣容量; unit.手枪弹匣容量=50;
        unit.__capacityReads=0;
        unit.addProperty("手枪弹匣容量",function():Number{return ++this.__capacityReads==1?50:60;},null);
        check(runtime.synthesizeAmmo("手枪")==0 && unit.mp==before,"提交前弹容漂移不扣费");
        delete unit.手枪弹匣容量; unit.手枪弹匣容量=50;
        unit.__capacityReads=0;
        unit.addProperty("手枪弹匣容量",function():Number {
            if (++this.__capacityReads==1) this.手枪={name:this.手枪.name,value:{level:1,shot:5,reloadCount:0}};
            return 50;
        },null);
        check(runtime.synthesizeAmmo("手枪")==0 && unit.mp==before && unit.手枪.value.shot==5,"提交前同名武器实例替换不跨写");
        delete unit.手枪弹匣容量; unit.手枪弹匣容量=50; unit.手枪=primary;
        var ammoEvents:Array=[];
        var handler:Function=function(owner:Object,state:String,remaining:Number,field:String,slot:String):Void {
            ammoEvents.push({slot:slot,remaining:remaining,field:field,mp:owner.mp,shot:owner[slot].value.shot});
        };
        unit.dispatcher.subscribe("updateBullet",handler,unit);
        primary.value.shot=2; unit.mp=1600;
        check(runtime.synthesizeAmmo("手枪")==2 && ammoEvents[0].shot==0 && ammoEvents[0].mp==1594,"视觉事件只能观察已同步提交的两种资源");
        check(ammoEvents[0].slot=="手枪" && ammoEvents[0].remaining==50,"补弹事件携带准确主手槽与余弹");
        secondary.value.shot=1; runtime.synthesizeAmmo("手枪2");
        check(ammoEvents[1].slot=="手枪2" && ammoEvents[1].field=="子弹数_2","双枪副手HUD字段正确");
        unit.dispatcher.unsubscribe("updateBullet",handler,unit);
        var badDisplay:Function=function():Void { throw "intentional fixture"; };
        unit.dispatcher.subscribe("updateBullet",badDisplay,unit);
        primary.value.shot=1; before=unit.mp; runtime.synthesizeAmmo("手枪");
        check(primary.value.shot==0 && unit.mp==before-3,"UI刷新抛错不回退或二次收费");
        check(runtime.synthesizeAmmo("手枪")==0 && unit.mp==before-3,"UI失败后下一维护不重复造弹");
        unit.dispatcher.unsubscribe("updateBullet",badDisplay,unit);
        primary.value.shot=2; secondary.value.shot=2; unit.mp=1503; advance(6);
        check(primary.value.shot==1 && secondary.value.shot==2 && unit.mp==1500,"低资源中央周期固定主手先分配");
        primary.value.shot=1; secondary.value.shot=5; unit.mp=1503; advance(6);
        check(primary.value.shot==1 && secondary.value.shot==4 && unit.mp==1500,"不同缺额时优先补缺弹更多的一槽");
        unit.攻击模式="长枪";
        var machine:Object=equipWeapon(unit,"长枪","钛合金QJZ171",false); machine.value.shot=4;
        before=unit.mp;
        check(runtime.synthesizeAmmo("长枪")==0 && machine.value.shot==4 && unit.mp==before,"机枪补弹拒绝且不扣费");
        unit.攻击模式="双枪";
        SetEffectController.teardownGroup(unit,"titanium_type_61_armor:titanium_type_61_full_set");
        before=unit.mp; primary.value.shot=0; shoot(unit,"手枪",null);
        check(unit.__titaniumType61==undefined && unit.mp==before,"套装单独卸载取消基础回蓝");
        secondary.value.shot=0; shoot(unit,"手枪2",null);
        check(unit.mp==before+3,"套装卸载不取消武器固有发电");
        DressupInitializer.teardownLifeCycles(unit); before=unit.mp;
        shoot(unit,"手枪2",null);
        check(unit.mp==before,"dispatcher仍存活时装备卸载也无陈旧回蓝");
        closeUnit(unit);
        var outside:MovieClip=makeUnit(0,0,false,false,false);
        var p:Object=equipWeapon(outside,"手枪","P90",true); outside.mp=100; shoot(outside,"手枪",null);
        check(outside.mp==100 && p.value.shot==1,"套外普通P90不发电");
        p=equipWeapon(outside,"手枪2","钛合金P90",true); shoot(outside,"手枪2",null);
        check(outside.mp==103 && p.value.shot==1,"套外钛合金P90每发3MP");
        outside.version++; before=outside.mp; shoot(outside,"手枪2",null);
        check(outside.mp==before,"旧版本装备回调拒绝新单位代次");
        closeUnit(outside);
    }

    private static function testReloadInterleaving():Void {
        var oldInventory:Object=_root.物品栏;
        var oldCollection:Object=_root.收集品栏;
        var oldSave:Object=_root.存档系统;
        var oldEquipment:Object=ItemUtil.equipmentDict;
        var oldMaterial:Object=ItemUtil.materialDict;
        var oldInfo:Object=ItemUtil.informationMaxValueDict;
        var unit:MovieClip=makeUnit(5,0,false,false,false);
        try {
            var runtime:TitaniumSetRuntime=unit.__titaniumType61;
            var pistol:Object=equipWeapon(unit,"手枪","钛合金P90",true);
            var secondary:Object=equipWeapon(unit,"手枪2","钛合金P90",true);
            fillShield(unit);
            var clip:String=unit.手枪属性.clipname;
            var bag:Object={items:[{name:clip,value:3}]};
            bag.getIndexes=function():Array { return this.items[0] && this.items[0].value>0 ? [0] : []; };
            bag.getItem=function(index:Number):Object { return this.items[index]; };
            bag.addValue=function(index:Number,delta:Number):Void { this.items[index].value+=delta; };
            bag.remove=function(index:Number):Void { this.items[index]=null; };
            var empty:Object={getIndexes:function():Array{return [];}, getValue:function():Number{return 0;}};
            _root.物品栏={背包:bag,药剂栏:empty}; _root.收集品栏={材料:empty,情报:empty};
            _root.存档系统={dirtyMark:false};
            ItemUtil.equipmentDict={}; ItemUtil.materialDict={}; ItemUtil.informationMaxValueDict={};
            unit.被动技能={}; unit.攻击模式="手枪";
            unit.man.使用弹匣名称=clip; unit.man.主手使用弹匣名称=clip; unit.man.副手使用弹匣名称=clip;
            pistol.value.shot=8; unit.mp=1700;
            var generation:Number=ReloadManager.getReloadGeneration(unit.man);
            ReloadManager.startReload(unit.man,unit,_root);
            check(unit.man.换弹标签 && ReloadManager.getReloadGeneration(unit.man)>generation,"真实手枪换弹开始锁住补弹并推进代次");
            var before:Number=unit.mp;
            check(runtime.synthesizeAmmo("手枪")==0 && ItemUtil.getTotal(clip)==3 && unit.mp==before,"换弹动画期不扣蓝也不重复消费库存");
            generation=ReloadManager.getReloadGeneration(unit.man);
            ReloadManager.reloadMagazine(unit.man,unit,_root);
            check(pistol.value.shot==0 && ItemUtil.getTotal(clip)==2 && ReloadManager.getReloadGeneration(unit.man)>generation,"真实换弹提交仅消费一匣并重置shot");
            ReloadManager.finishReload(unit.man);
            check(runtime.synthesizeAmmo("手枪")==0 && unit.mp==before,"换弹先完成时不再向已满弹匣收费");
            shoot(unit,"手枪",null); runtime.synthesizeAmmo("手枪");
            check(pistol.value.shot==0 && unit.mp==before+3 && ItemUtil.getTotal(clip)==2,"换弹后开火与合成守恒且不退还备用库存");
            unit.攻击模式="双枪";
            pistol.value.shot=5; secondary.value.shot=7;
            var state:Object={updateState:function():Void{}, canFinishSubHandReload:function():Boolean{return true;}};
            var reloadHand:Function=ReloadManager.createHandReloadFunction(unit.man,unit,_root,{handPrefix:"副手",weaponType:"手枪2"},state);
            generation=ReloadManager.getReloadGeneration(unit.man); reloadHand();
            check(secondary.value.shot==0 && pistol.value.shot==5 && ItemUtil.getTotal(clip)==1,"真实副手换弹不覆盖主手缺弹");
            check(ReloadManager.getReloadGeneration(unit.man)>generation,"副手换弹提交更新共享代次");
            before=unit.mp; pistol.value.shot=0; secondary.value.shot=0;
            shoot(unit,"手枪",null); shoot(unit,"手枪2",null);
            check(unit.mp==before+12 && pistol.value.shot==1 && secondary.value.shot==1,"双钛合金P90各自发射合计12MP不重复领取");
        } finally {
            closeUnit(unit);
            _root.物品栏=oldInventory; _root.收集品栏=oldCollection; _root.存档系统=oldSave;
            ItemUtil.equipmentDict=oldEquipment; ItemUtil.materialDict=oldMaterial; ItemUtil.informationMaxValueDict=oldInfo;
        }
    }

    private static function testFireControl():Void {
        var unit:MovieClip=makeUnit(5,0,false,false,false);
        var runtime:TitaniumSetRuntime=unit.__titaniumType61;
        var machine:Object=equipWeapon(unit,"长枪","钛合金QJZ171",false);
        unit.攻击模式="长枪"; unit.刀.name="普通刀";
        var template:Object={站立子弹散射度:0,移动子弹散射度:1};
        unit.重量=-17;
        WeaponFireCore.executeShot(unit,"长枪",unit.man,template,null);
        check(emitted.血量上限击溃==undefined,"未付费专属盾没有171贡献");
        fillShield(unit);
        var weights:Array=[0,-8.5,-17,-35];
        var rout:Array=[0,0.075,0.15,0.15];
        var slay:Array=[0,5,10,10];
        for(var i:Number=0;i<weights.length;i++) {
            unit.buffManager.setBaseValue("重量",weights[i]);
            advance(1);
            if (i==1) {
                var diagnostics:Object=runtime.getDiagnostics();
                check(diagnostics.fireControlProgress==0.5 && diagnostics.fireControlRout==0.075 && diagnostics.fireControlSlay==5,"玩家诊断与本枪半档快照共用进度");
                var messageCount:Number=messages.length;
                unit.攻击模式="手枪"; advance(1); unit.攻击模式="长枪"; advance(1);
                unit.攻击模式="空手"; advance(1); unit.攻击模式="长枪"; advance(1);
                check(messages.length==messageCount,"往返切枪也不发布火控文字提示");
            }
            WeaponFireCore.executeShot(unit,"长枪",unit.man,template,null);
            check(near(emitted.血量上限击溃 || 0,rout[i]) && near(emitted.斩杀 || 0,slay[i]),"真实171发射负重映射："+weights[i]);
        }
        check(template.血量上限击溃==undefined && template.斩杀==undefined,"条件贡献不污染持久子弹模板");
        check(unit.击溃==undefined && unit.斩杀==undefined,"不写入人物全局百分比");
        var snapshot:Object=emitted;
        var shield:Shield=Shield(unit.shield.getShieldById(runtime.getShieldId()));
        shield.consumeCapacity(shield.getCapacity());
        check(runtime.getDiagnostics().fireControlProgress==0,"破盾诊断立即显示零火控");
        check(snapshot.血量上限击溃==0.15 && snapshot.斩杀==10,"破盾不追溯修改已发射子弹");
        WeaponFireCore.executeShot(unit,"长枪",unit.man,template,null);
        check(emitted.血量上限击溃==undefined && emitted.斩杀==undefined,"破盾下一发立即停用条件贡献");
        fillShield(unit);
        template.血量上限击溃=0.3; template.斩杀=15;
        WeaponFireCore.executeShot(unit,"长枪",unit.man,template,null);
        check(emitted.血量上限击溃==0.3 && emitted.斩杀==15,"枪械已有更高同类来源取高值");
        unit.击溃=0.4; unit.斩杀=20;
        BulletInitializer.inheritShooterAttributes(emitted,unit);
        check(emitted.击溃==0.4 && emitted.斩杀==20,"真实子弹继承入口继续与人物来源取高");
        template.血量上限击溃=0.02; template.斩杀=2;
        machine.name="QJZ171";
        WeaponFireCore.executeShot(unit,"长枪",unit.man,template,null);
        check(emitted.血量上限击溃==0.02 && emitted.斩杀==2,"普通171不获得钛合金条件贡献");
        machine.name="钛合金QJZ171";
        unit.头部装备={name:"替换头盔"};
        WeaponFireCore.executeShot(unit,"长枪",unit.man,template,null);
        check(emitted.血量上限击溃==0.02 && emitted.斩杀==2,"五甲身份变化在维护前即拒绝新贡献");
        closeUnit(unit);
    }

    private static function bindBloodAnimation(unit:MovieClip):MovieClip {
        var man:MovieClip = unit.createEmptyMovieClip("bloodAnimation" + (++serial), unit.getNextHighestDepth());
        unit.man = man;
        unit.状态 = "战技";
        man.无敌标签 = true;
        man.unloadCalls = 0;
        man.onUnload = function():Void { this.unloadCalls++; };
        unit.bloodBindSucceeded = unit.__titaniumType61.bindBloodPactAnimation(man);
        return man;
    }

    private static function testBloodPact():Void {
        ItemUtil.itemDataDict = weapons;
        var low:MovieClip = makeUnit(5,-5,false,false,false,1);
        check(TitaniumSetRuntime.getBloodLoss(low)==999,"真实血剑一级固有负担");
        check(near(low.__titaniumType61.getDiagnostics().maximum,2748.5),"低强化血剑提供1.5倍额外盾");
        closeUnit(low);
        var unit:MovieClip = makeUnit(5,-5,false,false,true,13);
        var runtime:TitaniumSetRuntime = unit.__titaniumType61;
        var shield:Shield = Shield(unit.shield.getShieldById(runtime.getShieldId()));
        check(TitaniumSetRuntime.getBloodLoss(unit)==3037,"真实血剑十三强化固有负担");
        check(near(shield.getMaxCapacity(),5805.5) && shield.getResistBypass(),"完整专属池抗真伤并绑定强化");
        advance(1);
        check(near(runtime.getLazyDodge(),0.3),"专属盾在线提供30%高危闪避上限");
        unit.损伤值=1000;
        var chainResult:DamageResult=DamageResult.getIMPACT_CHAIN();
        DodgeStateDamageHandle.instance.handleBulletDamage({flags:2,伤害类型:"物理"},{},unit,{dodgeState:""},chainResult);
        check(chainResult.deferChainDodgeState,"护盾懒闪避进入真实联弹分段入口");
        var maximum:Number=shield.getCapacity();
        shield.absorbDamage(100,true,1);
        check(near(shield.getCapacity(),maximum-100),"真伤实际扣专属池");
        shield.consumeCapacity(shield.getCapacity());
        check(runtime.getLazyDodge()==0 && unit.externalShield.getCapacity()==100,"破盾瞬间移除懒闪避，外部盾不代替资格");
        chainResult=DamageResult.getIMPACT_CHAIN();unit.损伤值=1000;
        DodgeStateDamageHandle.instance.handleBulletDamage({flags:2,伤害类型:"物理"},{},unit,{dodgeState:""},chainResult);
        check(!chainResult.deferChainDodgeState,"破盾后的联弹立即失去套装懒闪避");
        unit.攻击模式="长枪"; unit.状态="长枪站立";
        check(!runtime.commitBloodPact() && unit.hp==5000,"持枪不能献血");
        unit.攻击模式="兵器"; unit.状态="兵器站立"; unit.mp=1000;
        check(runtime.commitBloodPact(),"破盾低蓝仍可主动救场");
        var man:MovieClip=bindBloodAnimation(unit);
        check(unit.bloodBindSucceeded,"首帧绑定本次战技动作");
        check(near(runtime.getBloodPulsePower(),303.7),"动作段伤害取强化血剑负担的10%");
        check(unit.hp==3250 && unit.mp==0 && shield.getCapacity()==maximum,"扣35%当前HP与实际可用MP后补满盾");
        var incoming:Object={伤害类型:"物理",flags:0};
        check(DamageCalculator.calculateDamage(incoming,{},unit,1,"")===DamageResult.NULL,"起跳无敌阻挡真实物伤入口");
        incoming.伤害类型="真伤";
        check(DamageCalculator.calculateDamage(incoming,{},unit,1,"")===DamageResult.NULL && unit.hp==3250 && shield.getCapacity()==maximum,"起跳无敌同样阻挡真伤且不抵消主动献血");
        unit.mp=3000;man.无敌标签=false;runtime.grantBloodPactBonus(man);
        check(near(unit.伤害加成,440),"起手抽干MP后中途喝蓝也不能取得增伤");
        runtime.finishBloodPact(man,man.__ti61BloodCastId);
        check(runtime.getBloodPulsePower()==0,"动作结束后不再提供段伤害");
        check(near(unit.伤害加成,440),"抽干MP不给增伤");
        unit.hp=5000;unit.mp=3000;unit.状态="兵器站立";
        check(runtime.commitBloodPact() && unit.mp==3000,"满盾允许施放且补盾费用为零");
        man=bindBloodAnimation(unit);
        check(!runtime.commitBloodPact() && unit.hp==3250,"一次施放未结束不能重复付费");
        check(near(unit.伤害加成,440),"砸地之前尚未开始增伤");
        unit.mp=0;unit.hp=6500;advance(25);
        man.无敌标签=false;runtime.grantBloodPactBonus(man);
        check(near(unit.伤害加成,1502.95),"满血十三强化增伤1062.95，资格采用支付快照");
        check(near(runtime.getBloodPulsePower(),303.7),"砸地配给后仍保留后续低伤多段");
        var expiry:Number=runtime.getDiagnostics().bloodBonusUntil;
        advance(20);runtime.grantBloodPactBonus(man);
        check(runtime.getDiagnostics().bloodBonusUntil==expiry && near(unit.伤害加成,1502.95),"重复砸地不叠加也不刷新八秒计时");
        runtime.finishBloodPact(man,man.__ti61BloodCastId);
        check(runtime.getDiagnostics().bloodBonusUntil==expiry && runtime.getBloodPulsePower()==0,"动画结束只清动作，不重发或续期增伤");
        advance(219);
        check(near(unit.伤害加成,1502.95),"砸地后239帧仍保留增益");
        advance(1);
        check(near(unit.伤害加成,440),"从砸地计算八秒到期清除");
        unit.hp=2500;unit.mp=3000;unit.状态="兵器站立";
        runtime.commitBloodPact();man=bindBloodAnimation(unit);runtime.grantBloodPactBonus(man);runtime.finishBloodPact(man,man.__ti61BloodCastId);
        check(near(unit.hp,1625) && near(unit.伤害加成,971.475),"半血献血量和增伤均减半");
        unit.hp=6500;unit.mp=3000;unit.状态="兵器站立";
        runtime.commitBloodPact();man=bindBloodAnimation(unit);runtime.grantBloodPactBonus(man);runtime.finishBloodPact(man,man.__ti61BloodCastId);
        check(near(unit.hp,4225) && near(unit.伤害加成,1821.835),"溢出治疗按实际献血量增加收益");
        unit.状态="兵器站立";unit.hp=5000;unit.mp=3000;shield.setCapacity(maximum-1000);
        runtime.commitBloodPact();man=bindBloodAnimation(unit);runtime.grantBloodPactBonus(man);
        check(unit.mp==2500 && near(unit.伤害加成,1502.95),"提前施放按1000缺口收500MP并获得增伤");
        expiry=runtime.getDiagnostics().bloodBonusUntil;
        unit.状态="技能";man.onUnload();
        check(!man.无敌标签 && !runtime.getDiagnostics().bloodCasting && man.unloadCalls==1,"取消立即卸载本技保护并保留原路由回调");
        check(near(unit.伤害加成,1502.95) && runtime.getDiagnostics().bloodBonusUntil==expiry,"砸地后取消收招保留已取得增伤");
        advance(240);
        unit.状态="兵器站立";unit.hp=5000;unit.mp=3000;shield.setCapacity(maximum-1000);
        runtime.commitBloodPact();man=bindBloodAnimation(unit);
        unit.状态="技能";man.onUnload();
        check(unit.hp==3250 && unit.mp==2500 && shield.getCapacity()==maximum,"砸地前取消仍保留费用与即时补盾");
        runtime.grantBloodPactBonus(man);
        check(near(unit.伤害加成,440) && runtime.getBloodPulsePower()==0,"提前取消后迟到砸地不能发增益或段伤害");
        var oldMan:MovieClip=man;
        var oldCastId:Number=oldMan.__ti61BloodCastId;
        unit.状态="兵器站立";unit.hp=5000;unit.mp=3000;
        runtime.commitBloodPact();man=bindBloodAnimation(unit);
        oldMan.onUnload();runtime.finishBloodPact(man,oldCastId);runtime.grantBloodPactBonus(oldMan);
        check(runtime.getDiagnostics().bloodCasting && man.无敌标签 && near(unit.伤害加成,440),"旧动作卸载与旧代次不能取消或兑现新动作");
        runtime.grantBloodPactBonus(man);
        check(near(unit.伤害加成,1502.95),"新动作仍能正常砸地兑现一次增益");
        unit.hp=0;advance(1);
        check(near(unit.伤害加成,440) && runtime.getLazyDodge()==0,"死亡清理献血增伤与懒闪避");
        check(!man.无敌标签 && !runtime.getDiagnostics().bloodCasting,"死亡同时清掉未结束动作的保护");
        closeUnit(unit);
        unit=makeUnit(5,-5,false,false,false,13);runtime=unit.__titaniumType61;
        unit.状态="兵器站立";unit.攻击模式="兵器";
        runtime.commitBloodPact();man=bindBloodAnimation(unit);runtime.dispose();
        check(!man.无敌标签 && runtime.getBloodPulsePower()==0,"卸装清理专属动作保护和段伤害");
        runtime.grantBloodPactBonus(man);
        check(near(unit.伤害加成,440),"卸装后的迟到砸地不留下增益");
        closeUnit(unit);
        unit=makeUnit(5,-5,false,false,false,13);runtime=unit.__titaniumType61;
        unit.状态="兵器站立";unit.攻击模式="兵器";
        runtime.commitBloodPact();man=bindBloodAnimation(unit);
        man.__ti61BloodRuntime={};unit.状态="技能";man.onUnload();
        check(man.无敌标签 && !runtime.getDiagnostics().bloodCasting,"旧动作取消不清理已改属其他技能的无敌标签");
        closeUnit(unit);
        unit=makeUnit(5,-5,false,false,false,13);runtime=unit.__titaniumType61;
        unit.状态="兵器站立";unit.攻击模式="兵器";
        runtime.commitBloodPact();man=bindBloodAnimation(unit);
        man.__ti61BloodCastId++;unit.状态="技能";man.onUnload();
        check(man.无敌标签 && !runtime.getDiagnostics().bloodCasting,"同名影片剪辑转入新代次时旧动作清理不误关保护");
        closeUnit(unit);
        ItemUtil.itemDataDict = {};
    }

    private static function testFireControlVulnerability():Void {
        var unit:MovieClip=makeUnit(0,0,false,false,false);
        unit.damageTakenMultiplier=1; unit.ti61CrumbleTakenMultiplier=1;
        var behavior:Object={peak:0.75,durationFrames:30};
        check(FireControlVulnerability.applyToTarget(unit,behavior),"真实Buff管理器接收引导易伤");
        check(near(unit.damageTakenMultiplier,1.75) && near(unit.ti61CrumbleTakenMultiplier,1.75),"普通伤害和击溃同时达峰");
        unit.buffManager.update(15);
        check(near(unit.damageTakenMultiplier,1.375),"半秒线性衰退至半幅");
        FireControlVulnerability.applyToTarget(unit,behavior);
        FireControlVulnerability.applyToTarget(unit,behavior);
        check(near(unit.damageTakenMultiplier,1.75),"重复及多人引导只刷新不叠乘");
        unit.hp=unit.hp满血值=100000;unit.损伤值=0;
        var bullet:Object={击溃:1,子弹威力:999,additionalEffectDamage:0};
        var result:DamageResult=DamageResult.getIMPACT();
        CrumbleDamageHandle.instance.handleBulletDamage(bullet,{},unit,{},result);
        check(unit.hp满血值==98250 && unit.损伤值==1750 && result._crumbleDamage==1750,"击溃上限与配对损伤只放大一次");
        unit.buffManager.update(30);
        check(near(unit.damageTakenMultiplier,1) && near(unit.ti61CrumbleTakenMultiplier,1),"一秒结束清理两种易伤");
        FireControlVulnerability.applyToTarget(unit,behavior);unit.hp=0;unit.buffManager.update(1);
        check(near(unit.damageTakenMultiplier,1) && near(unit.ti61CrumbleTakenMultiplier,1),"死亡清理引导，不跨复活保留");
        check(!BulletHitEffectRegistry.apply({hitBehavior:{type:"titaniumFireControl",peak:0.75,durationFrames:30}}, {}, unit, {dodgeStatus:"MISS"}),"MISS不施加火控易伤");
        if (!DamageManagerFactory.Basic) DamageManagerFactory.init();
        bullet={hitBehavior:{type:"titaniumFireControl"},击溃:20,斩杀:99,吸血:100,nanoToxic:999,固伤:999,百分比伤害:99,暴击:{},霰弹值:9,实际命中强制击杀:true};
        BulletHitEffectRegistry.prepare(bullet,{},unit);
        check(bullet.子弹威力==100 && bullet.霰弹值==1 && bullet.伤害类型=="物理","射线真实命中入口锁定单段100基础物伤");
        check(bullet.击溃==0 && bullet.斩杀==0 && bullet.nanoToxic==0 && bullet.固伤==0 && bullet.百分比伤害==0 && !bullet.实际命中强制击杀,"副射不会继承人物附带伤害和终结");
        unit.hp=unit.hp满血值=10000;unit.防御力=1119;bullet.flags=0;
        DamageCalculator.calculateDamage(bullet,{伤害加成:1000000},unit,1,"");
        check(unit.hp==9979,"引导伤害经过真实防御管线且不吃百万通用固伤");
        bullet.hitBehavior={type:"titaniumBloodPact",directPower:303.7};
        BulletHitEffectRegistry.prepare(bullet,{},unit);
        check(near(bullet.子弹威力,303.7) && bullet.击溃==0,"血剑多段复用独立伤害路径");
        closeUnit(unit);
    }

    private static function testSecondaryData():Void {
        var unit:MovieClip=makeUnit(0,0,false,false,false);
        equipWeapon(unit,"长枪","钛合金QJZ171",false);
        unit.攻击模式="长枪";unit.状态="长枪站立";
        unit.被动技能={冲击连携:{启用:true,等级:10}};unit.装备枪械威力加成=1000000;
        check(LongGunSubWeaponCore.configureUnit(unit,unit.长枪数据),"171真实XML可配置副武器");
        check(LongGunSubWeaponCore.getLoadedCount(unit)==0 && unit.长枪副武器弹匣容量==17,"初次副仓为空，容量17，不凭空赠电池");
        var props:Object=LongGunSubWeaponCore.prepareManBulletProps(unit,unit.man);
        check(props.hitBehavior.type=="titaniumFireControl" && props.hitBehavior.peak==0.75 && props.子弹种类=="钛合金火控射线","声明式副射沿真实配置传入子弹");
        check(props.子弹威力==100 && unit.长枪副武器配置.reserveName=="能量电池","引导不吃冲击连携固伤，使用电池弹药");
        LongGunSubWeaponCore.setFiredCount(unit,8);
        LongGunSubWeaponCore.configureUnit(unit,unit.长枪数据);
        check(LongGunSubWeaponCore.getLoadedCount(unit)==9,"重新配置保留副仓剩余量");
        LongGunSubWeaponCore.clearUnit(unit);
        closeUnit(unit);
    }

    private static function finish():Void {
        if (completed) return; completed=true;
        for (var i:Number=0;i<units.length;i++) if (units[i]._parent) closeUnit(units[i]);
        if (watchdog) watchdog.removeMovieClip();
        _root.gameworld=oldWorld; _root.子弹区域shoot传递=oldBulletFactory; _root.玩家信息界面=oldUi;
        ItemUtil.itemSetConfigDict=oldConfig; _root.帧计时器=oldClock; _root.控制目标=oldControl;
        ItemUtil.itemDataDict=oldItems;
        _root.发布消息=oldMessage; _root.装备生命周期函数.移除异常周期函数=oldCleanup;
        _root.主角函数.获取装备主动战技种类=oldGetSkill;
        _root.装备生命周期函数.喷气背包初始化=oldJetInit;
        _root.装备生命周期函数.喷气背包周期=oldJetCycle;
        trace("TitaniumSetRuntimeTest Tests Passed: "+passed);
        trace("TitaniumSetRuntimeTest Tests Failed: "+failed);
        _root.titaniumSetFocusedComplete();
    }
}
