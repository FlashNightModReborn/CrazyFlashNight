import org.flashNight.gesh.tooltip.builder.EquipmentLightingInfoBuilder;
import org.flashNight.gesh.tooltip.builder.ModStatBuilder;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.tooltip.NativeTooltipDocument;
import org.flashNight.gesh.tooltip.test.TestDataBootstrap;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.equipment.EquipmentLifecyclePolicy;
import org.flashNight.arki.item.equipment.ModRegistry;

class org.flashNight.gesh.tooltip.test.EquipmentLightingTooltipTest {
    private static var passed:Number,failed:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("EquipmentLightingTooltipTest FAIL: "+label);}
    }
    private static function light(kind:String):Object {
        return {skillInteraction:"independent",init:{initRoutines:"装备光源初始化",initParam:{kind:kind}},cycle:{cycleRoutines:"装备光源周期"}};
    }
    private static function emission(group:String,adapter:String):Object {
        return {skillInteraction:"independent",init:{initRoutines:"装备自发光初始化",initParam:{group:group,adapter:adapter,radius:100,energy:0.5,color:0x99BBFF}}};
    }
    private static function text(item:Object,mods:Array,standalone:Boolean):String {
        return EquipmentLightingInfoBuilder.build(item,mods,standalone).join("");
    }
    private static function occurrences(value:String,needle:String):Number {return value.split(needle).length-1;}
    private static function flatten(doc:Object):String {
        var result:String="";
        for(var i:Number=0;i<doc.sections.length;i++)for(var j:Number=0;j<doc.sections[i].runs.length;j++)result+=doc.sections[i].runs[j].text;
        return result;
    }
    public static function runAllTests():Void {
        passed=failed=0;TestDataBootstrap.beginSandbox();
        var oldModDict:Object=EquipmentUtil.modDict;
        EquipmentUtil.modDict=ModRegistry.getModDict();
        var oldMod:Object=EquipmentUtil.modDict["__lightingMod"];
        var oldEquip:Object=ItemUtil.equipmentDict["__lightingGun"];
        try {
            check(text({},null,false)=="","ordinary equipment has no empty lighting heading");
            check(text({lifecycle:{attr_x:{init:{initRoutines:"unknown"}}}},null,false)=="","unrelated callbacks are not described as lights");
            var item:Object={lifecycle:{attr_body:emission("body","static")}};
            var html:String=text(item,null,false);
            check(html.indexOf("【照明效果】")>=0 && html.indexOf("穿戴时")>=0,"armor explains worn illumination");
            item.lifecycle.attr_other=emission("body","static");
            check(occurrences(text(item,null,false),"穿戴时")==1,"multiple body sources share one explanation");
            var adapters:Array=["static","blood","vocalist","libra","inductor","lion","capricorn"];
            var words:Array=["持用兵器","拔剑","光剑形态展开","战技冷却期间","过载","兵器激活期间","激活窗口"];
            for(var i:Number=0;i<adapters.length;i++) {
                item.lifecycle={attr_blade:emission("blade",adapters[i])};
                check(text(item,null,false).indexOf(words[i])>=0,"real activation condition for "+adapters[i]);
            }
            item.lifecycle={attr_blade:emission("blade","unknown")};
            check(text(item,null,false)=="","unknown adapters do not advertise unsupported lighting");
            var builtin:Object=light("flashlight");builtin.init.initParam.evasionBonus=20;builtin.init.initParam.electricEvasionBonus=5;
            item={use:"长枪",lifecycle:{attr_torch:builtin}};
            html=text(item,null,false);
            check(html.indexOf("近身补光")>=0 && html.indexOf("前方照明")>=0,"builtin torch advertises both lighting lobes");
            check(html.indexOf("闪避")==-1,"builtin torch cannot claim a plugin defense bonus");
            item.lifecycle.attr_plugin=light("flashlight");item.lifecycle.attr_plugin.__modName="__lightingMod";
            item.lifecycle.attr_plugin.init.initParam={kind:"flashlight",evasionBonus:20,electricEvasionBonus:5};
            html=text(item,[],false);
            check(occurrences(html,"近身补光")==1 && html.indexOf("闪避加成 +20")>=0,"installed torch deduplicates illumination but retains its actual bonus");
            item.inherentTags="电力";html=text(item,[],false);
            check(html.indexOf("闪避加成 +25")>=0 && html.indexOf("+20")==-1,"electric weapon shows its resolved bonus");
            delete item.inherentTags;item.lifecycle.attr_plugin2=light("flashlight");item.lifecycle.attr_plugin2.__modName="other";
            item.lifecycle.attr_plugin2.init.initParam={kind:"flashlight",evasionBonus:10,electricEvasionBonus:0};
            check(occurrences(text(item,[],false),"闪避加成")==1 && text(item,[],false).indexOf("+30")==-1,"multiple torch bonuses take maximum instead of stacking");
            html=text({lifecycle:{attr_light:builtin}},null,true);
            check(html.indexOf("+20")>=0 && html.indexOf("电力适配时 +25")>=0,"standalone mod explains both supported equipment contexts");
            var mod:Object={name:"__lightingMod",use:"长枪",stats:{},lifecycle:{attr_light:builtin}};
            EquipmentUtil.modDict["__lightingMod"]=mod;
            html=ModStatBuilder.build("__lightingMod").join("");
            check(html.indexOf("【照明效果】")>=0 && html.indexOf("+25")>=0,"material tooltip consumer receives generated lighting and defense");
            var legacy:Object={init:{initRoutines:"枪械激光初始化",initParam:{beamLinkage:"testBeam"}}};
            item={lifecycle:{attr_laser:legacy,attr_plugin:light("laser")}};
            html=text(item,null,false);
            check(occurrences(html,"狭窄束带")==1 && html.indexOf("闪避")==-1,"legacy and generic lasers share one narrow-beam explanation without defense");
            legacy.init.initParam.beamLinkage="";delete item.lifecycle.attr_plugin;
            check(text(item,null,false)=="","invalid legacy beam binding does not claim illumination");
            item.lifecycle={attr_light:light("laser")};item.lifecycle.attr_light.init.initParam.energy=0;
            check(text(item,null,false)=="","disabled light energy is not advertised as illumination");
            var base:Object={name:"__lightingGun",type:"武器",use:"长枪",data:{},description:"original"};
            ItemUtil.equipmentDict[base.name]=true;
            var effective:Object={name:base.name,type:base.type,use:base.use,data:{},lifecycle:EquipmentLifecyclePolicy.merge(null,[mod.name],EquipmentUtil.modDict)};
            var instance={name:base.name,value:{level:1,mods:[mod.name]},effective:effective,getData:function():Object{return this.effective;}};
            html=TooltipComposer.generateItemDescriptionText(base,instance);
            check(html.indexOf("【照明效果】")>=0 && html.indexOf("闪避加成 +20")>=0,"equipment composer reads the merged lifecycle instead of the raw definition");
            var doc:Object=NativeTooltipDocument.buildItem(base.name,base,effective,"",html);
            check(flatten(doc).indexOf("近身补光")>=0 && flatten(doc).indexOf("+20")>=0,"shared native/Web document retains the generated lighting text");
            instance.effective={name:base.name,type:base.type,use:base.use,data:{}};instance.value.mods=[];
            check(TooltipComposer.generateItemDescriptionText(base,instance).indexOf("【照明效果】")==-1,"removing a mod removes its annotation from the effective tooltip");
            base.lifecycle={attr_old:light("laser")};
            check(TooltipComposer.generateItemDescriptionText(base,instance).indexOf("【照明效果】")==-1,"a tier-replaced lifecycle cannot fall back to stale base lighting");
            check(TooltipComposer.generateItemDescriptionText(base,null).indexOf("狭窄束带")>=0,"raw catalog tooltip still describes built-in lighting");
            trace("EquipmentLightingTooltipTest Example: "+text({lifecycle:{attr_light:builtin}},null,true));
        } catch(error) {check(false,"exception "+error);}
        if(oldMod==undefined)delete EquipmentUtil.modDict["__lightingMod"];else EquipmentUtil.modDict["__lightingMod"]=oldMod;
        if(oldEquip==undefined)delete ItemUtil.equipmentDict["__lightingGun"];else ItemUtil.equipmentDict["__lightingGun"]=oldEquip;
        TestDataBootstrap.endSandbox();
        EquipmentUtil.modDict=oldModDict;
        trace("EquipmentLightingTooltipTest Tests Passed: "+passed);
        trace("EquipmentLightingTooltipTest Tests Failed: "+failed);
    }
}
