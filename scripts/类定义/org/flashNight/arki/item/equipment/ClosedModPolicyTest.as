import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.equipment.*;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.object.ObjectUtil;

/** Live XML policy through production menu filtering, install gate and modifier calculation; no inventory writes. */
class org.flashNight.arki.item.equipment.ClosedModPolicyTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var saved:Object;
    private static var watchdog:MovieClip;
    private static var completed:Boolean;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[FAIL] ClosedModPolicyTest: "+label);}
    }
    private static function has(values:Array,name:String):Boolean {
        for(var i:Number=0;i<values.length;i++)if(values[i]===name)return true;
        return false;
    }
    private static function itemFor(raw:Object) {
        var item={name:raw.name,value:{level:1,mods:[]},raw:raw};
        item.getData=function():Object {return EquipmentCalculator.calculatePure(this.raw,this.value,{},ModRegistry.getModDict());};
        return item;
    }
    public static function runAllTests():Void {
        passed=failed=0;completed=false;saved={items:ItemUtil.itemDataDict,registry:{},facade:{}};
        var registry:Object=org.flashNight.arki.item.equipment.ModRegistry;
        var facade:Object=org.flashNight.arki.item.EquipmentUtil;
        var keys:Array=["_modDict","_modList","_modUseLists","_modAvailabilityResults","_displayNameToModName","_debugMode"];
        for(var i:Number=0;i<keys.length;i++)saved.registry[keys[i]]=registry[keys[i]];
        keys=["modDict","modList","modUseLists","modAvailabilityResults"];
        for(i=0;i<keys.length;i++)saved.facade[keys[i]]=facade[keys[i]];
        watchdog=_root.createEmptyMovieClip("__closedModPolicyWatch",_root.getNextHighestDepth());watchdog.frames=0;
        watchdog.onEnterFrame=function():Void {if(++this.frames>600){ClosedModPolicyTest.check(false,"fixture timeout");ClosedModPolicyTest.finish();}};
        var doc=new XML();doc.ignoreWhite=true;
        doc.onLoad=function(ok:Boolean):Void {
            if(!ok){ClosedModPolicyTest.check(false,"fixture XML load");ClosedModPolicyTest.finish();return;}
            ClosedModPolicyTest.execute(XMLParser.parseXMLNode(this.firstChild));
        };
        doc.load("../tmp/unified61-review/mod-policy-fixture.xml");
    }
    private static function execute(input:Object):Void {
        try {
            var items:Array=XMLParser.configureDataAsArray(input.items.item);
            var mods:Array=XMLParser.configureDataAsArray(input.mods.mod);
            var excluded:Array=XMLParser.configureDataAsArray(input.excluded.item);
            check(items.length==26,"five armor and twenty-one existing closed tactical weapons");
            check(mods.length>100,"complete live mod catalog loaded");
            check(excluded.length==4,"three open tactical weapons and zero-slot KING variant preserved");
            trace("ClosedModPolicyFixture sourceClosure="+input.sourceClosure+" items="+items.length+" mods="+mods.length);
            mods.push({name:"__policy_future",use:"头部装备,上装装备,下装装备,手部装备,脚部装备,刀,手枪,长枪",tag:"未来挂点",stats:{flat:{power:1}}});
            mods.push({name:"__policy_untagged",use:"头部装备,上装装备,下装装备,手部装备,脚部装备,刀,手枪,长枪",stats:{flat:{power:1}}});
            EquipmentUtil.loadModData(mods);
            ItemUtil.itemDataDict={};
            for(var i:Number=0;i<items.length;i++)ItemUtil.itemDataDict[items[i].name]=items[i];
            for(i=0;i<excluded.length;i++)ItemUtil.itemDataDict[excluded[i].name]=excluded[i];
            for(i=0;i<items.length;i++) {
                var raw:Object=items[i];var item=itemFor(raw);
                check(raw.allowedModTags=="等级校正","explicit allowlist "+raw.name);
                check(TagManager.buildTagContext(item,raw).presentTags.电力===true,"built-in power "+raw.name);
                var available:Array=EquipmentUtil.getAvailableModMaterials(item);
                check(available.length==2 && has(available,"电脑芯片") && has(available,"成长的勋章"),"menu only lists the two level modifiers "+raw.name);
                check(TagManager.checkModAvailability(item,raw,"电脑芯片")==1,"chip install gate "+raw.name);
                check(TagManager.checkModAvailability(item,raw,"成长的勋章")==1,"medal install gate "+raw.name);
                for(var j:Number=0;j<mods.length;j++) {
                    var mod:Object=mods[j];
                    if(mod.name=="电脑芯片" || mod.name=="成长的勋章")continue;
                    check(TagManager.checkModAvailability(item,raw,mod.name)==-64,"deny non-level mod "+raw.name+" / "+mod.name);
                }
                var chip:Object=EquipmentCalculator.calculatePure(raw,{level:1,mods:["电脑芯片"]},{},ModRegistry.getModDict());
                var medal:Object=EquipmentCalculator.calculatePure(raw,{level:1,mods:["成长的勋章"]},{},ModRegistry.getModDict());
                check(Number(chip.data.level)==Number(raw.data.level)-3,"real chip calculation "+raw.name);
                check(Number(medal.data.level)==Number(raw.data.level)-10,"real medal calculation "+raw.name);
                check(chip.data.power===raw.data.power && chip.data.defence===raw.data.defence && chip.data.weight===raw.data.weight,"level adjustment does not strengthen combat values "+raw.name);
                check(item.value.mods.length==0,"queries leave installed mods untouched "+raw.name);
                item.value.mods=["电脑芯片"];
                check(TagManager.checkModAvailability(item,raw,"成长的勋章")<0,"one occupied level slot "+raw.name);
                item.value.mods=[];
                var powerless:Object=ObjectUtil.clone(raw);powerless.inherentTags="";
                check(TagManager.checkModAvailability(item,powerless,"电脑芯片")==-16,"chip still requires power "+raw.name);
                check(TagManager.checkModAvailability(item,powerless,"成长的勋章")==1,"medal needs no power "+raw.name);
            }
            for(i=0;i<excluded.length;i++) {
                raw=excluded[i];item=itemFor(raw);
                check(raw.allowedModTags===undefined,"excluded item has no new policy "+raw.name);
                check(TagManager.checkModAvailability(item,raw,"__policy_future")== (raw.data.modslot===0?-1:1),"excluded installation behavior unchanged "+raw.name);
            }
            var basic:Object={name:"__policy_basic",use:"长枪",inherentTags:"电力",data:{level:40,modslot:2}};
            item=itemFor(basic);
            check(TagManager.checkModAvailability(item,basic,"__policy_untagged")==1,"missing allowlist preserves legacy untagged behavior");
            var malformed:Array=["",null,[],3];
            for(i=0;i<malformed.length;i++) {
                basic.allowedModTags=malformed[i];
                check(TagManager.checkModAvailability(item,basic,"成长的勋章")==-64,"explicit empty or malformed allowlist fails closed "+i);
                check(TagManager.filterAvailableMods(["成长的勋章","__policy_future","__policy_untagged"],item,basic).length==0,"menu agrees with malformed allowlist "+i);
            }
            basic.allowedModTags="等级校正";basic.blockedTags="等级校正";
            check(TagManager.checkModAvailability(item,basic,"电脑芯片")==-64,"deny rules still override an allowed tag");
        } catch(error:Error) {check(false,"exception "+error.message);}
        finish();
    }
    private static function finish():Void {
        if(completed)return;completed=true;
        if(watchdog)watchdog.removeMovieClip();
        ItemUtil.itemDataDict=saved.items;
        var registry:Object=org.flashNight.arki.item.equipment.ModRegistry;
        var facade:Object=org.flashNight.arki.item.EquipmentUtil;
        for(var key:String in saved.registry)registry[key]=saved.registry[key];
        for(key in saved.facade)facade[key]=saved.facade[key];
        trace("ClosedModPolicyTest Tests Passed: "+passed);
        trace("ClosedModPolicyTest Tests Failed: "+failed);
        if(typeof _root.closedModPolicyFocusedComplete=="function")_root.closedModPolicyFocusedComplete();
    }
}
