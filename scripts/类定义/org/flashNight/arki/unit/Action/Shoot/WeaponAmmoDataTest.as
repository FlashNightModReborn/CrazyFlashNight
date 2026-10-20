import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;
import org.flashNight.arki.item.equipment.EquipmentCalculator;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.tooltip.builder.WeaponAmmoInfoBuilder;
import org.flashNight.gesh.tooltip.builder.UseSwitchStatsBuilder;

/** 真实 XML→生产解析器→配件运算器→弹药资格；不向真实库存或存档写入。 */
class org.flashNight.arki.unit.Action.Shoot.WeaponAmmoDataTest {
    private static var paths:Array;
    private static var index:Number;
    private static var items:Object;
    private static var mods:Array;
    private static var passed:Number;
    private static var failed:Number;
    public static var onComplete:Function;
    private static var config:Object;

    private static function check(ok:Boolean, text:String):Void {
        if (ok) passed++;
        else { failed++;trace("[FAIL] WeaponAmmoDataTest: "+text); }
    }
    private static function same(expected:Number, actual:Number, text:String):Void {
        check(Math.abs(expected-actual)<0.00001,text+" expected="+expected+" actual="+actual);
    }
    public static function runAllTests():Void {
        passed=0;failed=0;index=0;items={};mods=[];
        paths=["武器_长枪_霰弹枪.xml","武器_手枪_霰弹枪.xml","武器_长枪_反器材武器.xml",
            "武器_手枪_手枪.xml","equipment_mods/中等材料_枪械专用.xml","equipment_mods/高等材料_枪械专用.xml"];
        config={levelStatList:EquipmentConfigManager.getLevelStatList(),
            tierNameToKeyDict:EquipmentConfigManager.getTierNameToKeyDict()};
        loadNext();
    }
    private static function loadNext():Void {
        if (index>=paths.length) {
            try { runCases(); } catch(error) { check(false,"exception "+error); }
            trace("--- WeaponAmmoDataTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
            onComplete();return;
        }
        var path:String=paths[index++];
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {
            WeaponAmmoDataTest.check(ok,"real XML load "+path);
            if(ok) {
                var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
                var list:Array=XMLParser.configureDataAsArray(parsed.item);
                for(var i:Number=0;i<list.length;i++)WeaponAmmoDataTest.items[list[i].name]=list[i];
                list=XMLParser.configureDataAsArray(parsed.mod);
                for(var j:Number=0;j<list.length;j++)WeaponAmmoDataTest.mods.push(list[j]);
            }
            WeaponAmmoDataTest.loadNext();
        };
        xml.load("../data/items/"+path);
    }
    private static function calc(name:String, installed:Array, level:Number, tier:String):Object {
        return EquipmentCalculator.calculateInPlace(ObjectUtil.clone(items[name]),
            {level:level,mods:installed,tier:tier},config,ModRegistry.getModDict()).data;
    }
    private static function actor(data:Object):Object {
        var u:Object={被动技能:{冲击连携:{启用:true}}};
        u.长枪={value:{level:1,shot:0}};u.长枪属性=data;u.长枪弹匣容量=data.capacity;
        return u;
    }
    private static function runCases():Void {
        ModRegistry.loadModData(mods);
        var inner:String="枪械内构强化套件";
        var choke:String="霰弹枪口收束器";
        var nonbolt:String="非栓式机构";
        var magazine:String="加长弹匣";
        var data:Object=calc("TTI Benelli M4",[],1,null);
        same(7,data.capacity,"TTI ordinary capacity is seven");
        same(1,data.overload.chamber,"TTI chamber separate from capacity");
        same(1,data.overload.ghost,"TTI native ghost quota");
        data=calc("TTI Benelli M4",[inner],1,null);
        same(7,data.capacity,"inner does not inflate ordinary capacity");
        same(2,data.overload.ghostLimit,"real registry deep-merges ghost limit");
        same(2,WeaponAmmoRuntime.ghostLimit(actor(data),"长枪"),"effective eligible quota is merged two");
        var annotation:String=WeaponAmmoInfoBuilder.capacitySuffix(data);
        check(annotation.indexOf("#FFCC70'>+2")>=0 && annotation.indexOf("#9BE0E9'>+1")>=0,"real parsed TTI and inner data reach source-specific annotations");
        var lines:Array=[];
        UseSwitchStatsBuilder.buildStatBlock(lines,ModRegistry.getModDict()[inner].stats,"");
        annotation=lines.join("");
        check(annotation.indexOf("幽灵装填上限 → 2发")>=0 && annotation.indexOf("[object Object]")==-1,"real parsed inner merge receives human-readable annotation");
        data=calc("TTI Benelli M4",[inner,choke],1,null);
        same(3,data.diffusion,"choke remains an independent spread tradeoff");
        same(46,data.velocity,"choke speed retained");
        data=calc("TTI Benelli M4",[inner,magazine],1,null);
        same(8,data.capacity,"ordinary percentage rounding happens before overloading");
        same(2,WeaponAmmoRuntime.ghostLimit(actor(data),"长枪"),"magazine does not recursively inflate ghost cap");
        data=calc("双管白火铳",[],1,null);
        same(2,data.capacity,"double white baseline preserved");
        same(0,WeaponAmmoRuntime.chamberLimit(actor(data),"长枪"),"break action has no native chamber bonus");
        data=calc("双管白火铳",[nonbolt],1,null);
        same(3,data.capacity,"nonbolt current small-cap tuning preserved");
        same(780,data.power,"nonbolt power tradeoff preserved");
        data=calc("双管白火铳",[nonbolt,magazine,inner],1,null);
        same(4,data.capacity,"three mods keep existing rounded capacity");
        same(888,data.power,"three mods keep existing additive power policy");
        same(0,WeaponAmmoRuntime.ghostLimit(actor(data),"长枪"),"tube conversion and inner do not grant structural eligibility");
        data=calc("双管白火铳",[nonbolt,magazine,inner],13,null);
        same(3336,data.power,"level thirteen does not compound percentage penalties independently");
        data=calc("GM6_LYNX",[inner],1,null);
        var u:Object=actor(data);
        same(5,data.capacity,"GM6 ordinary capacity unchanged");
        same(1,WeaponAmmoRuntime.chamberLimit(u,"长枪"),"GM6 chamber enabled");
        same(5,WeaponAmmoRuntime.rewardLimit(u,"长枪"),"GM6 reward cap uses normal capacity only");
        same(0,WeaponAmmoRuntime.ghostLimit(u,"长枪"),"GM6 inner does not invent carrier eligibility");
        annotation=WeaponAmmoInfoBuilder.capacitySuffix(data);
        check(annotation.indexOf("#CAADFF'>+5")>=0 && annotation.indexOf("#FFCC70")==-1,"real GM6 annotation separates reward from unsupported ghost");
        data=calc("XM1014",[inner],1,"狱火");
        same(1,data.overload.chamber,"tier inherits chamber metadata");
        same(2,data.overload.ghostLimit,"tier and inner keep merged quota");
        same(1,calc("M1911",[],1,null).overload.chamber,"other closed-bolt pistol has explicit chamber data");
        same(0,WeaponAmmoRuntime.chamberLimit(actor(calc("鲁格LCR",[],1,null)),"长枪"),"unmarked revolver defaults to no bonus");
        var shotguns:Number=0,ghosts:Number=0;
        for(var key:String in items) {
            var item:Object=items[key];
            if(item.weapontype!="霰弹枪")continue;
            shotguns++;
            check(item.data.overload!=null,"shotgun explicitly classified "+key);
            check(typeof item.data.overload.chamber=="number" && typeof item.data.overload.ghost=="number","XML parser preserves numeric quota types "+key);
            if(item.data.overload.ghost>0)ghosts++;
        }
        same(44,shotguns,"all shotgun records covered");
        same(9,ghosts,"ghost whitelist not inferred from tube or semi-auto");
    }
}
