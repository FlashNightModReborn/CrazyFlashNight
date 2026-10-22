import org.flashNight.arki.item.equipment.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.tooltip.builder.ModStatBuilder;
import org.flashNight.gesh.tooltip.builder.UseSwitchStatsBuilder;

/** 真实XML到运算、安装规则、插件说明与预览；独立TestLoader，零库存/存档写。 */
class org.flashNight.arki.item.equipment.EquipmentIntervalCurveTest {
    private static var paths:Array, items:Object, mods:Array;
    private static var index:Number, passed:Number, failed:Number;
    public static var onComplete:Function;
    private static function check(ok:Boolean, label:String):Void {
        if(ok) passed++; else {failed++;trace("EquipmentIntervalCurveTest FAIL: "+label);}
    }
    private static function same(expected:Number, actual:Number, label:String):Void {
        check(Math.abs(expected-actual)<0.000001,label+" expected="+expected+" actual="+actual);
    }
    public static function runAllTests():Void {
        index=0;passed=0;failed=0;items={};mods=[];
        paths=["武器_手枪_手枪.xml","武器_手枪_冲锋枪.xml","武器_长枪_冲锋枪.xml","武器_长枪_机枪.xml",
            "武器_长枪_压制机枪.xml","武器_长枪_霰弹枪.xml","equipment_mods/高等材料_枪械专用.xml"];
        loadNext();
    }
    private static function loadNext():Void {
        if(index>=paths.length){finish();return;}
        var path:String=paths[index++];
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {
            EquipmentIntervalCurveTest.check(ok,"real XML load "+path);
            if(ok){
                var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
                var list:Array=XMLParser.configureDataAsArray(parsed.item);
                for(var i:Number=0;i<list.length;i++)EquipmentIntervalCurveTest.items[list[i].name]=list[i];
                list=XMLParser.configureDataAsArray(parsed.mod);
                for(var j:Number=0;j<list.length;j++)EquipmentIntervalCurveTest.mods.push(list[j]);
            }
            EquipmentIntervalCurveTest.loadNext();
        };
        xml.load("../data/items/"+path);
    }
    private static function finish():Void {
        var oldItems:Object=ItemUtil.itemDataDict, oldDict:Object=EquipmentUtil.modDict;
        var oldMods:Array=ModRegistry.getModList();
        try{
            mods.push({name:"测试间隔百分比",use:"手枪",stats:{percentage:{interval:-10}}});
            mods.push({name:"测试间隔乘区",use:"手枪",stats:{multiplier:{interval:25}}});
            mods.push({name:"测试间隔固定值",use:"手枪",stats:{flat:{interval:7}}});
            mods.push({name:"测试间隔曲线",use:"手枪",stats:{curve:{interval:{type:"saturatingAdd",amount:16,pivot:48}}}});
            ModRegistry.loadModData(mods);ItemUtil.itemDataDict=items;EquipmentUtil.modDict=ModRegistry.getModDict();
            testOperators();testData();testComposition();testPresentation();testBounds();
            trace("EquipmentIntervalCurveTest Phases: operator,data,composition,presentation,bounds");
        }catch(error){check(false,"exception "+error);}
        ItemUtil.itemDataDict=oldItems;EquipmentUtil.modDict=oldDict;
        if(oldMods.length>0)ModRegistry.loadModData(oldMods);
        trace("--- EquipmentIntervalCurveTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
        onComplete();
    }
    private static function soft(value:Number, settings:Object):Number {
        var data:Object={interval:value};
        PropertyOperators.applyCurve(data,{interval:settings});return data.interval;
    }
    private static function curve():Object {return {type:"saturatingAdd",amount:32,pivot:48};}
    private static function calc(name:String, installed:Array):Object {
        return EquipmentCalculator.calculatePure(items[name],{level:1,mods:installed},
            EquipmentConfigManager.getFullConfig(),ModRegistry.getModDict()).data;
    }
    private static function testOperators():Void {
        same(193,soft(168,curve()),"post-percentage value is amplified");
        same(0,soft(0,curve()),"zero is preserved");same(-1,soft(-1,curve()),"negative is preserved");
        check(isNaN(soft(Number.NaN,curve())),"NaN is preserved");
        check(soft(Number.POSITIVE_INFINITY,curve())==Number.POSITIVE_INFINITY,"infinity is preserved");
        var invalid:Array=[{type:"saturatingAdd",pivot:48},{type:"saturatingAdd",amount:-1,pivot:48},
            {type:"saturatingAdd",amount:32,pivot:0},{type:"saturatingAdd",amount:32,pivot:Number.POSITIVE_INFINITY},
            {type:"saturatingAdd",amount:Number.POSITIVE_INFINITY,pivot:48}];
        for(var i:Number=0;i<invalid.length;i++)same(80,soft(80,invalid[i]),"invalid config leaves input "+i);
        same(80,soft(80,{type:"saturatingAdd",amount:0,pivot:48}),"zero amount is identity");
        same(80,soft(80,{type:"saturatingAdd",amount:32,pivot:48,max:1}),"max cannot reverse amplification");
        var old:Object={zero:0,diffusion:7,impact:500};
        PropertyOperators.applyCurve(old,{zero:1.414,diffusion:1.414,impact:1.4});
        check(old.zero==0 && old.diffusion==4 && old.impact==31,"legacy compression retains zero and inverse-impact behavior");
    }
    private static function testData():Void {
        var names:Array=["TTI 2011 Combat Master","M1A1SMG","M249","PKM机枪","XM214-CageFrame","M134"];
        var expected:Array=[193,78,160,150,30,300];
        for(var i:Number=0;i<names.length;i++){
            check(items[names[i]]!=undefined && items[names[i]].data.interval>0,"real weapon fixture exists "+names[i]);
            var before:Object=items[names[i]].data;
            var after:Object=calc(names[i],["磁稳贯穿弹"]);
            same(expected[i],after.interval,"real XML interval "+names[i]);
            check(after.power==before.power && after.capacity==before.capacity && after.split==before.split,
                "non-interval weapon values preserved "+names[i]);
        }
        check(calc("M134",["磁稳贯穿弹"]).bullet=="纵向机枪联弹-次级穿刺子弹","vertical prefix survives ammo replacement");
        check(calc("雷明登870",["磁稳贯穿弹"]).bullet=="横向联弹-次级穿刺子弹","horizontal prefix survives ammo replacement");
        check(items["TTI 2011 Combat Master"].data.interval==140 && items["TTI 2011 Combat Master"].data.bullet=="普通子弹",
            "pure calculation leaves the raw item unchanged");
        var probe:Object=ObjectUtil.clone(items["TTI 2011 Combat Master"]);probe.data.modslot=3;
        var item={name:"TTI 2011 Combat Master",value:{level:1,mods:[]}};
        same(1,TagManager.checkModAvailability(item,probe,"磁稳贯穿弹"),"ordinary ammunition accepts this mod");
        item.value.mods=["灰蛊裂隙弹"];
        same(-8,TagManager.checkModAvailability(item,probe,"磁稳贯穿弹"),"ammo tag remains exclusive");
        probe=ObjectUtil.clone(items["M60E3"]);probe.data.modslot=3;item.name="M60E3";item.value.mods=[];
        same(-128,TagManager.checkModAvailability(item,probe,"磁稳贯穿弹"),"native piercing ammunition remains excluded");
    }
    private static function testComposition():Void {
        var name:String="TTI 2011 Combat Master", ammo:String="磁稳贯穿弹";
        same(178,calc(name,[ammo,"测试间隔百分比"]).interval,"percentage remains additive before the curve");
        same(178,calc(name,["测试间隔百分比",ammo]).interval,"percentage composition ignores mod order");
        same(243,calc(name,[ammo,"测试间隔乘区","测试间隔固定值"]).interval,"independent multiplier before curve and flat after curve");
        same(180,calc(name,[ammo,"测试间隔曲线"]).interval,"later same-property curve wins by existing contract");
        same(193,calc(name,["测试间隔曲线",ammo]).interval,"reverse curve order explicitly changes the winner");
    }
    private static function stat(name:String, installed:Array):Number {
        var rows:Array=EquipmentStatProjector.project(name,{level:1,mods:installed});
        for(var i:Number=0;i<rows.length;i++)if(rows[i].key=="fireRate")return rows[i].value;
        return Number.NaN;
    }
    private static function testPresentation():Void {
        var html:String=ModStatBuilder.build("磁稳贯穿弹").join("");
        check(html.indexOf("柔性增加，最多 +32毫秒")>=0 && html.indexOf("saturatingAdd")==-1,
            "real standalone mod tooltip uses Chinese instead of an internal type");
        same(7.1,stat("TTI 2011 Combat Master",[]),"TTI before preview");
        same(5.1,stat("TTI 2011 Combat Master",["磁稳贯穿弹"]),"TTI after preview uses the real calculator");
        same(16.5,stat("M134",["磁稳贯穿弹"]),"vertical preview retains split-based shot density");
        var lines:Array=[];UseSwitchStatsBuilder.buildStatBlock(lines,{curve:{diffusion:1.414}},"");
        check(lines.join("").indexOf("压缩等级 20")>=0,"legacy compression tooltip remains intact");
    }
    private static function testBounds():Void {
        var monotone:Boolean=true, bounded:Boolean=true, previous:Number=0;
        for(var i:Number=1;i<=2000;i++){
            var data:Object={interval:i};PropertyOperators.multiply(data,{interval:1.2});
            PropertyOperators.applyCurve(data,{interval:curve()});
            if(data.interval<previous)monotone=false;
            if(data.interval<i || data.interval>2*i || data.interval<=0)bounded=false;
            previous=data.interval;
        }
        check(monotone,"integer intervals 1..2000 preserve weapon speed ordering");
        check(bounded,"integer intervals 1..2000 stay positive and between original and twice original");
    }
}
