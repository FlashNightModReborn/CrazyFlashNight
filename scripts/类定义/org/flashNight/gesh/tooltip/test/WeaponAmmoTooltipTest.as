import org.flashNight.gesh.tooltip.builder.WeaponAmmoInfoBuilder;
import org.flashNight.gesh.tooltip.builder.GunStatsBuilder;
import org.flashNight.gesh.tooltip.builder.UseSwitchStatsBuilder;
import org.flashNight.gesh.tooltip.builder.ModStatBuilder;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.tooltip.NativeTooltipDocument;
import org.flashNight.gesh.tooltip.test.TestDataBootstrap;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;

class org.flashNight.gesh.tooltip.test.WeaponAmmoTooltipTest {
    private static var passed:Number, failed:Number;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("[FAIL] WeaponAmmoTooltipTest: " + label); }
    }
    private static function caption(data:Object, effective:Object):String {
        var lines:Array=[];
        GunStatsBuilder.build(lines,null,{use:"长枪"},data,effective);
        return lines.join("");
    }
    private static function flatten(doc:Object):String {
        var result:String = "";
        for (var i:Number=0; i<doc.sections.length; i++)
            for (var j:Number=0; j<doc.sections[i].runs.length; j++) result += doc.sections[i].runs[j].text;
        return result;
    }
    private static function hasRun(doc:Object,text:String,color:String):Boolean {
        for (var i:Number=0; i<doc.sections.length; i++)
            for (var j:Number=0; j<doc.sections[i].runs.length; j++) {
                var run:Object=doc.sections[i].runs[j];
                if (run.text.indexOf(text)>=0 && String(run.color).toLowerCase()==color.toLowerCase()) return true;
            }
        return false;
    }
    public static function runAllTests():Void {
        passed=failed=0;
        TestDataBootstrap.beginSandbox();
        var oldMods:Object=EquipmentUtil.modDict;
        var oldEquip:Object=ItemUtil.equipmentDict["__ammoTooltipGun"];
        EquipmentUtil.modDict={};
        try {
            check(WeaponAmmoInfoBuilder.capacitySuffix({})=="","missing capacity has no quota badges");
            check(WeaponAmmoInfoBuilder.capacitySuffix({capacity:0,overload:{chamber:1}})=="","invalid capacity cannot advertise extra rounds");
            check(caption({capacity:7},null)=="弹夹容量：7<BR>","ordinary magazine caption stays byte-identical");
            check(caption({capacity:7,reloadType:"tube",overload:{chamber:0,ghost:0}},null).indexOf("COLOR")==-1,"tube alone cannot advertise extra capacity");
            var html:String=caption({capacity:7,overload:{chamber:1,ghost:1}},null);
            check(html.indexOf("7 <FONT COLOR='#9BE0E9'>+1</FONT> <FONT COLOR='#FFCC70'>+1</FONT>")>=0,"capacity is immediately followed by chamber and ghost in HUD source colors");
            check(html.indexOf("【装填机制】")==-1 && html.indexOf("冲击连携")==-1,"per-weapon stats contain no repeated mechanism paragraphs");
            check(html.split("<BR>").length==2,"compact source quotas stay in the capacity line");
            html=caption({capacity:7,overload:{chamber:1,ghost:1,ghostLimit:2}},null);
            check(html.indexOf("#FFCC70'>+2")>=0 && html.indexOf("+3")==-1,"merged ghost quota displays maximum rather than sum");
            check(WeaponAmmoInfoBuilder.capacitySuffix({capacity:7,overload:{ghostLimit:2}})=="","inner kit alone cannot advertise ghost eligibility");
            check(WeaponAmmoInfoBuilder.capacitySuffix({capacity:7,overload:{ghost:0,ghostLimit:2}})=="","explicit zero native eligibility stays zero");
            html=WeaponAmmoInfoBuilder.capacitySuffix({capacity:7,overload:{chamber:9,ghost:1,ghostLimit:99}});
            check(html.indexOf("#9BE0E9'>+2")>=0 && html.indexOf("#FFCC70'>+2")>=0,"compact values obey per-source hard caps");
            html=caption({capacity:5,overload:{chamber:1,reward:1,ghostLimit:2}},null);
            check(html.indexOf("#CAADFF'>+5")>=0,"GM6 skill quota uses purple and ordinary capacity");
            check(html.indexOf("#FFCC70")==-1,"GM6 with inner kit cannot advertise a ghost quota");
            var raw:Object={capacity:7,overload:{chamber:1,ghost:1}};
            var effective:Object={capacity:8,overload:{chamber:1,ghost:1,ghostLimit:2}};
            html=caption(raw,effective);
            check(html.indexOf("8</FONT> <FONT COLOR='#9BE0E9'>+1</FONT> <FONT COLOR='#FFCC70'>+2</FONT> (7 + 1)")>=0,"compact quotas precede and preserve ordinary mod arithmetic");
            html=caption({capacity:7,bullet:"子弹-纵向联弹",split:3,overload:{chamber:1,ghost:1,ghostLimit:2}},null);
            check(html.indexOf("弹夹容量：21 <FONT COLOR='#9BE0E9'>+1</FONT> <FONT COLOR='#FFCC70'>+2</FONT>")>=0,"burst presentation cannot multiply extra source quotas");
            var lines:Array=[];
            UseSwitchStatsBuilder.buildStatBlock(lines,{merge:{overload:{ghostLimit:2}}},"");
            html=lines.join("");
            check(html.indexOf("幽灵装填上限 → 2发")>=0 && html.indexOf("[合并]")>=0,"standalone mod stats retain a short named effect");
            check(html.indexOf("需原生支持及冲击连携，不累加")>=0,"short mod annotation preserves eligibility and non-addition");
            check(html.indexOf("[object Object]")==-1 && html.indexOf("overload")==-1,"mod stats never expose the nested object");
            EquipmentUtil.modDict["__ammoTooltipMod"]={name:"__ammoTooltipMod",use:"长枪",stats:{merge:{overload:{ghostLimit:2}}}};
            check(ModStatBuilder.build("__ammoTooltipMod").join("").indexOf("幽灵装填上限 → 2发")>=0,"material tooltip still reaches the merge annotation");
            var base:Object={name:"__ammoTooltipGun",type:"武器",use:"长枪",data:raw,description:"weapon description"};
            var calculated:Object={name:base.name,type:base.type,use:base.use,data:effective};
            var instance={name:base.name,value:{level:1,shot:-3,ammoState:{ghost:2,reserve:4}},effective:calculated,getData:function():Object{return this.effective;}};
            ItemUtil.equipmentDict[base.name]=true;
            var description:String=TooltipComposer.generateItemDescriptionText(base,instance);
            check(description.indexOf("【装填机制】")==-1 && description.indexOf("幽灵弹")==-1,"main equipment description no longer repeats the lesson");
            check(instance.value.shot==-3 && instance.value.ammoState.reserve==4 && instance.value.ammoState.ghost==2,"compact projection leaves live loaded rounds and paid credit untouched");
            html=caption(raw,effective);
            var doc:Object=NativeTooltipDocument.buildItem(base.name,base,calculated,html,description);
            check(flatten(doc).indexOf("8 +1 +2 (7 + 1)")>=0,"shared document preserves compact capacity and ordinary arithmetic");
            check(hasRun(doc,"+1","#9BE0E9"),"shared Native/Web chamber run keeps cyan");
            check(hasRun(doc,"+2","#FFCC70"),"shared Native/Web ghost run keeps yellow");
            html=caption({capacity:5,overload:{chamber:1,reward:1}},null);
            doc=NativeTooltipDocument.buildItem(base.name,base,calculated,html,description);
            check(hasRun(doc,"+5","#CAADFF"),"shared Native/Web reward run keeps purple");
            html=caption(raw,{capacity:8});
            check(html.indexOf("#9BE0E9")==-1 && html.indexOf("#FFCC70")==-1,"tier-replaced effective data cannot revive stale base quotas");
            html=caption({capacity:13,overload:{chamber:1,ghost:1,ghostLimit:2}},null);
            trace("WeaponAmmoTooltipTest Compact Example: "+html);
        } catch(error) {check(false,"exception "+error);}
        EquipmentUtil.modDict=oldMods;
        if(oldEquip==undefined)delete ItemUtil.equipmentDict["__ammoTooltipGun"];else ItemUtil.equipmentDict["__ammoTooltipGun"]=oldEquip;
        TestDataBootstrap.endSandbox();
        trace("--- WeaponAmmoTooltipTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
    }
}
