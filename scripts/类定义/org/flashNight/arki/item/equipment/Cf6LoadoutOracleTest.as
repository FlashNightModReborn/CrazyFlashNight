import org.flashNight.arki.item.*;
import org.flashNight.arki.item.equipment.*;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader;

/** Read-only real XML -> ItemUtil -> BaseItem -> menu/install gate -> final calculation. */
class org.flashNight.arki.item.equipment.Cf6LoadoutOracleTest {
    private static var passed:Number,failed:Number,completed:Boolean,watch:MovieClip;
    private static var cases:Array,cursor:Number,expanded:Number,sidearms:Number,carbineEligible:Number,ready:Boolean;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[FAIL] Cf6LoadoutOracleTest "+label);}
    }
    private static function contains(values:Array,name:String):Boolean {
        for(var i:Number=0;i<values.length;i++)if(values[i]===name)return true;
        return false;
    }
    public static function runAllTests():Void {
        passed=failed=0;completed=ready=false;cursor=expanded=sidearms=carbineEligible=0;
        watch=_root.createEmptyMovieClip("__cf6LoadoutOracle",_root.getNextHighestDepth());watch.frames=0;
        watch.onEnterFrame=function():Void {if(++this.frames>15000){Cf6LoadoutOracleTest.check(false,"fixture deadline");Cf6LoadoutOracleTest.finish();}else Cf6LoadoutOracleTest.tick();};
        var doc:XML=new XML();doc.ignoreWhite=true;
        doc.onLoad=function(ok:Boolean):Void {
            if(!ok){Cf6LoadoutOracleTest.check(false,"fixture load");Cf6LoadoutOracleTest.finish();return;}
            Cf6LoadoutOracleTest.execute(XMLParser.parseXMLNode(this.firstChild));
        };
        doc.load("../tmp/cf6-loadout-oracle/fixture.xml");
    }
    private static function execute(input:Object):Void {
        try {
            var loader:Object=EquipmentConfigLoader.getInstance();
            EquipmentUtil.loadEquipmentConfig(loader.parseEquipmentConfig(input.config));
            ItemUtil.loadItemData(XMLParser.configureDataAsArray(input.items.item));
            EquipmentUtil.loadModData(XMLParser.configureDataAsArray(input.mods.mod));
            cases=XMLParser.configureDataAsArray(input.cases["case"]);
            check(cases.length==282,"all 282 physical gun slots");
            trace("Cf6LoadoutOracle planSha256="+input.planSha256+" slots="+cases.length);
            ready=true;
        } catch(error:Error) {check(false,"setup exception "+error.message);finish();}
    }
    /** One physical slot per frame avoids AVM1's synchronous script timeout. */
    public static function tick():Void {
        if(!ready || completed)return;
        if(cursor>=cases.length){
            check(expanded==145 && sidearms==124,"145 rail longguns and 124 independent sidearms");
            trace("Cf6LoadoutOracle counts expanded="+expanded+" sidearms="+sidearms+" carbineEligibleSlots="+carbineEligible);
            finish();return;
        }
        try {
            var i:Number=cursor++;
                var row:Object=cases[i],value:Object={level:row.enhancement,mods:[],shot:0};
                if(row.tier!="" && row.tier!=undefined)value.tier=row.tier;
                var item:BaseItem=new BaseItem(row.name,value,1);
                var baseline:Object=item.getData();
                var selected:Array=(row.selected=="" || row.selected==undefined)?[]:String(row.selected).split(",");
                var full:Array=[];
                for(var j:Number=0;j<selected.length;j++) {
                    check(contains(EquipmentUtil.getAvailableModMaterials(item),selected[j]),row.id+" menu "+selected[j]);
                    check(EquipmentUtil.isModMaterialAvailable(item,item.getData(),selected[j])==1,row.id+" ordered install "+selected[j]);
                    full.push(selected[j]);item.value.mods=full.concat();item.update(j+2);
                }
                var result:Object=item.getData();
                check(Number(result.data.power)==Number(row.expectedPower),row.id+" exact raw power got="+result.data.power+" expected="+row.expectedPower);
                check(Number(result.data.modslot)==Number(row.expectedSlots),row.id+" final slot count "+result.data.modslot);
                check(result.data.bullet===baseline.data.bullet && result.data.split===baseline.data.split,row.id+" original projectile type/count");
                check(result.actiontype===baseline.actiontype && result.data.singleshoot===baseline.data.singleshoot,row.id+" original fire action");
                if(selected[0]=="战术鱼骨零件")expanded++;
                if(row.sidearm===true){sidearms++;check(selected.length<=1 && !contains(selected,"手枪卡宾转换套件"),row.id+" independent sidearm slot");}
                var empty:BaseItem=new BaseItem(row.name,{level:row.enhancement,tier:value.tier,mods:[]},1);
                if(contains(EquipmentUtil.getAvailableModMaterials(empty),"手枪卡宾转换套件") && EquipmentUtil.isModMaterialAvailable(empty,empty.getData(),"手枪卡宾转换套件")==1)carbineEligible++;
                trace("CF6_LOADOUT_SLOT "+row.id+" power="+result.data.power+" slots="+result.data.modslot+" mods="+selected.join(","));
        } catch(error:Error) {check(false,"slot exception "+cursor+" "+error.message);finish();}
    }
    private static function finish():Void {
        if(completed)return;completed=true;if(watch)watch.removeMovieClip();
        trace("Cf6LoadoutOracleTest Tests Passed: "+passed);
        trace("Cf6LoadoutOracleTest Tests Failed: "+failed);
        if(typeof _root.cf6LoadoutOracleComplete=="function")_root.cf6LoadoutOracleComplete();
    }
}
