import org.flashNight.arki.item.equipment.EquipmentCalculator;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.item.equipment.TagManager;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.UnitAI.combat.WeaponDpsEstimator;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightDefense;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.tooltip.builder.EquipmentLightingInfoBuilder;
import org.flashNight.neur.Event.EventDispatcher;

// Real item/mod definitions, production modifier and shooting paths. No save writes.
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.SheriffArsenalTest {
    private static var passed:Number,failed:Number,index:Number;
    private static var definitions:Object,mods:Array,oldMods:Array,files:Array;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else {failed++;trace("SheriffArsenalTest FAIL: "+label);}
    }
    private static function near(a:Number,b:Number):Boolean {return Math.abs(a-b)<0.00001;}
    public static function runAllTests():Void {
        passed=0;failed=0;index=0;definitions={};mods=[];oldMods=ModRegistry.getModList();
        files=["武器_长枪_霰弹枪.xml","武器_手枪_大威力手枪.xml",
            "equipment_mods/中等材料_枪械专用.xml","equipment_mods/高等材料_枪械专用.xml","equipment_mods/中等材料_通用.xml"];
        loadNext();
    }
    private static function loadNext():Void {
        if(index==files.length){runLoaded();return;}
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(success:Boolean):Void {
            SheriffArsenalTest.check(success,"actual XML "+SheriffArsenalTest.index);
            if(!success){SheriffArsenalTest.finish();return;}
            var root:Object=XMLParser.parseXMLNode(this.firstChild);
            var list:Array=XMLParser.configureDataAsArray(SheriffArsenalTest.index<2?root.item:root.mod);
            for(var i:Number=0;i<list.length;i++) {
                if(SheriffArsenalTest.index<2)SheriffArsenalTest.definitions[list[i].name]=list[i];
                else SheriffArsenalTest.mods.push(list[i]);
            }
            SheriffArsenalTest.index++;SheriffArsenalTest.loadNext();
        };
        xml.load("../data/items/"+files[index]);
    }
    private static function runLoaded():Void {
        var oldWorld=_root.gameworld,oldClock=_root.帧计时器,oldPause=_root.暂停;
        var world:MovieClip=_root.createEmptyMovieClip("__sheriffArsenalTest",_root.getNextHighestDepth());
        _root.gameworld=world;_root.帧计时器={当前帧数:0};_root.暂停=false;
        var actor:MovieClip=world.createEmptyMovieClip("actor",1);
        try {
            ModRegistry.loadModData(mods);
            var cfg:Object=EquipmentConfigManager.getFullConfig(), registry:Object=ModRegistry.getModDict();
            var shotgun:Object=definitions["特勤霰弹枪"],pistol:Object=definitions["特勤沙鹰"];
            var names:Array=["八门金锁镇暴弹","战术手电","矢量偏转枪盾","汲丝虹吸匣"];
            var base:Object=ObjectUtil.clone(shotgun),d:Object=base.data;
            d.power=175;d.weight=6;d.split=7;d.diffusion=20;d.impact=20;d.bulletsize=30;
            d.bullet="横向联弹-普通子弹";d.bulletrename="普通子弹";
            delete d.defence;delete d.toughness;delete d.accuracy;delete d.vampirism;
            var expected:Object=EquipmentCalculator.calculatePure(base,{level:1,mods:names},cfg,registry);
            var fields:Array=["power","weight","split","diffusion","impact","bulletsize","bullet","bulletrename","defence","toughness","accuracy","vampirism"];
            for(var i:Number=0;i<fields.length;i++)check(shotgun.data[fields[i]]==expected.data[fields[i]],"four canonical plugins match intrinsic "+fields[i]);
            check(shotgun.data.hp==undefined,"no unearned electric/NOAH health bonus");
            var equipment = {value:{mods:[]}};
            for(i=0;i<names.length;i++)check(TagManager.checkModAvailability(equipment,shotgun,names[i])==-1,"sealed slot rejects "+names[i]);
            check(TagManager.filterAvailableMods(names,equipment,shotgun).length==0,"sealed weapon offers no install candidates");
            check(TagManager.checkModAvailability(equipment,pistol,"汲丝虹吸匣")==1,"ordinary pistol still accepts compatible mod");

            actor.hp=100;actor.version=1;actor.攻击模式="空手";actor.syncRefs={};
            actor.dispatcher=new EventDispatcher();actor.buffManager=new BuffManager(actor,{});
            actor.闪避加成=0;actor.躲闪率=3;
            actor.长枪={name:shotgun.name,value:{level:1,mods:[]}};actor.长枪数据=shotgun;actor.长枪属性=shotgun.data;
            actor.长枪_引用=actor.createEmptyMovieClip("gun",2);actor.长枪_引用.createEmptyMovieClip("手电口",1);
            var param:Object=ObjectUtil.clone(shotgun.lifecycle.attr_equipmentLight.init.initParam);
            param.fallbackVisual=false;
            var ref:Object={自机:actor,装备类型:"长枪",生命周期函数列表:[]};
            EquipmentLightController.initialize(ref,param);
            check(EquipmentLightDefense.getActiveBonus(actor)==0,"sealed light has no holstered bonus");
            actor.攻击模式="长枪";EquipmentLightController.update(ref);
            check(EquipmentLightDefense.getActiveBonus(actor)==20 && near(actor.躲闪率,2.5),"declared built-in flashlight gives actual 20-point dodge pool");
            var text:String=EquipmentLightingInfoBuilder.build(shotgun,[],false).join("");
            check(text.indexOf("20")>=0,"tooltip describes the same built-in bonus");
            actor.hp=0;EquipmentLightController.update(ref);
            check(EquipmentLightDefense.getActiveBonus(actor)==0 && actor.躲闪率==3,"death retires built-in defense");
            EquipmentLightController.dispose(ref);

            var item:Object=EquipmentCalculator.calculatePure(pistol,{level:1,mods:[]},cfg,registry);
            check(item.data.power==550 && item.data.singleHandPowerBonus==-120,"dual 550 and long-gun-model single 430 projected separately");
            check(pistol.data.singleHandPowerBonus==undefined,"raw definition stays immutable");
            actor.手枪数据=item;actor.手枪属性=item.data;actor.手枪2属性=item.data;
            actor.被动技能={枪械攻击:{启用:true,等级:10}};actor.攻击模式="手枪";
            check(near(ShootInitCore.calculateWeaponPower(actor,"手枪",550,false),804),"single inherits long-gun attack formula 430*1.8+30");
            var bullet:Object=ShootInitCore.generateBulletProps(actor,"手枪",item.data,{});
            check(near(bullet.子弹威力,804),"actual bullet generation matches shared display power");
            actor.攻击模式="双枪";
            check(near(ShootInitCore.calculateWeaponPower(actor,"手枪",550,false),652.5),"dual main reverts to pistol profile");
            check(near(ShootInitCore.calculateWeaponPower(actor,"手枪2",550,false),652.5),"dual offhand remains pistol profile");
            check(near(ShootInitCore.generateBulletProps(actor,"手枪",item.data,{}).子弹威力,652.5),"next shot sees mode switch without lifecycle delay");
            check(near(ShootInitCore.calculateWeaponPower(actor,"手枪",550,false,"手枪"),804),"AI candidate mode overrides current dual mode");
            actor.长枪额外攻击加成倍率=0.2;actor.短枪额外攻击加成倍率=0.9;
            actor.被动技能.冲击连携={启用:true,等级:10};actor.攻击模式="手枪";
            check(near(ShootInitCore.calculateWeaponPower(actor,"手枪",550,false),890),"single takes long-gun bonus without pistol-only stacking");
            actor.攻击模式="双枪";
            check(near(ShootInitCore.calculateWeaponPower(actor,"手枪",550,false),1257.5),"dual retains its usual short-gun and combo bonuses");
            check(near(ShootInitCore.calculateWeaponPower(actor,"长枪",350,false),730),"ordinary long-gun calculation unchanged");
            actor.攻击模式="手枪";actor.被动技能={};actor.长枪额外攻击加成倍率=0;actor.短枪额外攻击加成倍率=0;
            check(ShootInitCore.calculateWeaponPower(actor,"手枪",550,false)==430,"disabled passive grants no free skill bonus");
            var values:Array=[{level:5,mods:[]},{level:5,mods:["八门金锁镇暴弹"]}];
            // Direct calculator fixtures verify operator ordering independently of installation eligibility.
            for(i=0;i<values.length;i++) {
                var dual:Object=EquipmentCalculator.calculatePure(pistol,values[i],cfg,registry);
                var singleBase:Object=ObjectUtil.clone(pistol);delete singleBase.singleHand;singleBase.data.power=430;
                var single:Object=EquipmentCalculator.calculatePure(singleBase,values[i],cfg,registry);
                actor.手枪属性=dual.data;
                check(near(ShootInitCore.calculateWeaponPower(actor,"手枪",dual.data.power+37,false),single.data.power+37),"upgrade/modifier order and external flat bonus preserved "+i);
            }
            actor.手枪属性=item.data;actor.手枪={name:pistol.name};actor.手枪2={name:pistol.name};actor.hp=100;
            actor.伤害加成=0;actor.手枪弹匣容量=8;actor.手枪2弹匣容量=8;
            actor.攻击模式="手枪";
            var singleDPS:Number=WeaponDpsEstimator.gunSustainedDPS(actor,"手枪");
            var dualDPS:Number=WeaponDpsEstimator.gunSustainedDPS(actor,"双枪");
            actor.攻击模式="双枪";
            check(singleDPS>0 && near(singleDPS,WeaponDpsEstimator.gunSustainedDPS(actor,"手枪")),"AI single candidate stable across current modes");
            check(dualDPS>0 && near(dualDPS,WeaponDpsEstimator.gunSustainedDPS(actor,"双枪")),"AI dual candidate stable across current modes");
        } catch(error) {check(false,"unexpected "+error);}
        if(actor.buffManager)actor.buffManager.destroy();if(actor.dispatcher)actor.dispatcher.destroy();world.removeMovieClip();
        _root.gameworld=oldWorld;_root.帧计时器=oldClock;_root.暂停=oldPause;
        finish();
    }
    private static function finish():Void {
        ModRegistry.loadModData(oldMods);
        trace("SheriffArsenalTest Tests Passed: "+passed);trace("SheriffArsenalTest Tests Failed: "+failed);
        _root.sheriffArsenalTestComplete();
    }
}
