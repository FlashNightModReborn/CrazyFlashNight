import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;

/** Read-only source loader. Uses production XML/config parsing and ItemUtil registration. */
class org.flashNight.arki.item.CharacterBuildCf6LoadoutData {
    private static var paths:Array=["data/equipment/equipment_config.xml","data/items/item_sets.xml",
        "data/items/防具_0-19级.xml","data/items/防具_颈部装备.xml",
        "data/items/武器_长枪_突击步枪.xml","data/items/武器_刀_长刀.xml"];
    private static var itemKeys:Array=["itemDataDict","balanceDataDict","itemDataArray","itemNamesByID","maxID",
        "equipmentDict","materialDict","informationMaxValueDict","multiTierDict","itemSetDict","itemSetByItem","itemSetConfigDict"];
    private static var rootKeys:Array=["物品属性列表","物品属性数组","物品套装索引","id物品名对应表","物品最大id","物品总数","物品套装配置索引"];
    private static var savedItems:Object,savedRoots:Object,savedConfig:Object;
    private static var combined:Array;
    private static var index:Number;
    private static var deadline:Number;
    private static var done:Boolean;
    private static var driver:MovieClip;
    private static var actorLoader:LoadVars;
    private static var document:XML;
    public static function load():Void {
        done=false;index=0;combined=[];savedItems={};savedRoots={};
        var api:Object=org.flashNight.arki.item.ItemUtil;
        for(var i:Number=0;i<itemKeys.length;i++) savedItems[itemKeys[i]]=api[itemKeys[i]];
        for(i=0;i<rootKeys.length;i++) savedRoots[rootKeys[i]]=_root[rootKeys[i]];
        savedConfig=EquipmentConfigManager.getFullConfig();
        PathManager.initialize(_root._url);
        driver=_root.createEmptyMovieClip("__characterCf6DataDeadline",_root.getNextHighestDepth());
        deadline=getTimer()+30000;
        driver.onEnterFrame=function():Void {org.flashNight.arki.item.CharacterBuildCf6LoadoutData.tick();};
        next();
    }
    private static function next():Void {
        if(done) return;
        if(index==paths.length) {loadActor();return;}
        var path:String=PathManager.resolvePath(paths[index]);
        if(path==null) {failure("path_unavailable:"+paths[index]);return;}
        document=new XML();document.ignoreWhite=true;
        document.onLoad=function(ok:Boolean):Void {org.flashNight.arki.item.CharacterBuildCf6LoadoutData.xmlReady(ok,this);};
        document.load(path);
    }
    public static function xmlReady(ok:Boolean,doc:XML):Void {
        if(done) return;
        if(!ok) {failure("xml_load_failed:"+paths[index]);return;}
        try {
            var data:Object=XMLParser.parseXMLNode(doc.firstChild);
            if(index==0) {
                // Only the transport is narrowed; this is the actual production config decoder.
                var loader:Object=EquipmentConfigLoader.getInstance();
                var config:Object=loader.parseEquipmentConfig(data);
                if(config.levelStatList.length<12) throw new Error("equipment_config_missing_level11");
                EquipmentUtil.loadEquipmentConfig(config);
            } else if(index==1) combined.itemSets=XMLParser.configureDataAsArray(data.set);
            else {
                var rows:Array=XMLParser.configureDataAsArray(data.item);
                if(rows.length==0) throw new Error("item_xml_empty");
                for(var i:Number=0;i<rows.length;i++) combined.push(rows[i]);
            }
            trace("CHARACTER_CF6_DATA loaded="+paths[index]);index++;next();
        } catch(error) {failure("xml_parse:"+String(error.message==undefined?error:error.message));}
    }
    private static function loadActor():Void {
        var path:String=PathManager.resolvePath("tools/cf6-actor-template/actor.fragment.json");
        if(path==null) {failure("actor_path_unavailable");return;}
        actorLoader=new LoadVars();
        actorLoader.onData=function(text:String):Void {org.flashNight.arki.item.CharacterBuildCf6LoadoutData.actorReady(text);};
        actorLoader.load(path);
    }
    public static function actorReady(text:String):Void {
        if(done) return;
        try {
            if(text==undefined || length(text)==0) throw new Error("actor_json_load_failed");
            var codec:LiteJSON=new LiteJSON();var actor:Object=codec.parse(text).actor;
            if(actor.name!="Andy" || actor.level!==60 || actor.equipment.length!==8) throw new Error("actor_shape_mismatch");
            ItemUtil.loadItemData(combined);
            for(var i:Number=0;i<actor.equipment.length;i++) {
                var row:Object=actor.equipment[i];
                if(!ItemUtil.isEquipment(String(row.name)) || row.enhancement!==11) throw new Error("actor_item_not_real_equipment:"+row.name);
            }
            trace("CHARACTER_CF6_DATA actor=Andy level=60 slots=8 enhancement=11 items="+combined.length);
            driver.removeMovieClip();driver=null;
            org.flashNight.arki.item.CharacterBuildCf6LoadoutTest.runLoaded(actor);
        } catch(error) {failure("actor_setup:"+String(error.message==undefined?error:error.message));}
    }
    public static function tick():Void {if(!done && getTimer()>deadline) failure("data_load_deadline");}
    private static function failure(reason:String):Void {
        if(done) return;
        trace("[FAIL] CharacterBuildCf6Loadout data: "+reason);
        trace("CharacterBuildCf6LoadoutTest Tests Passed: 0");
        trace("CharacterBuildCf6LoadoutTest Tests Failed: 1");
        complete();
    }
    public static function complete():Void {
        if(done) return;done=true;
        if(driver!=null) driver.removeMovieClip();
        var api:Object=org.flashNight.arki.item.ItemUtil;
        for(var i:Number=0;i<itemKeys.length;i++) api[itemKeys[i]]=savedItems[itemKeys[i]];
        for(i=0;i<rootKeys.length;i++) _root[rootKeys[i]]=savedRoots[rootKeys[i]];
        EquipmentUtil.loadEquipmentConfig(savedConfig);
        if(typeof _root.characterCf6LoadoutComplete=="function") _root.characterCf6LoadoutComplete();
    }
}
