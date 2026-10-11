import org.flashNight.arki.hud.PlayerHudService;
import org.flashNight.arki.hud.PlayerHudSnapshotLegacyFixture;
import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.skill.SkillResourceService;
import org.flashNight.arki.skill.SkillResourceSnapshotLegacyFixture;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.scene.StageReturnFlow;

class org.flashNight.arki.hud.PlayerHudLoadoutResourceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var api:Object;
    private static var oldApi:Object;
    private static var actor:Object;
    private static var skillRoot:Object;
    private static var rootInventory:Object;
    private static var currentLoadout:Object;
    private static var previous:Object;
    private static var codec:LiteJSON;
    private static var checksum:Number = 0;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] PlayerHudLoadoutResourceTest: " + label); }
    }
    private static function inventory(rows:Array):Object {
        var bag:Object = {rows:rows,indexReads:0,itemReads:0};
        bag.getItem = function(index:String):Object { this.itemReads++; return this.rows[Number(index)]; };
        bag.getIndexes = function():Array {
            this.indexReads++;
            var keys:Array = [];
            for (var i:Number = 0; i < this.rows.length; i++) if (this.rows[i] != null) keys.push(String(i));
            return keys;
        };
        return bag;
    }
    private static function setup():Void {
        skillRoot = {技能表对象:{}, 主角技能表:[], 存档系统:{dirtyMark:false}, 等级:50, 技能点数:100};
        skillRoot.技能表对象.能量盾 = {MaxLevel:10, UnlockLevel:1, UnlockSP:20, UpgradeSP:5, Type:"武术", Passive:false, Equippable:true, MP:10, CD:2000};
        skillRoot.主角技能表 = [["能量盾",1,true,"武术",true]];
        skillRoot.keyshow = function(code:Number):String { return "K" + code; };
        skillRoot.动态更新技能冷却领域 = function():Boolean { return true; };
        for (var i:Number = 1; i < 13; i++) { skillRoot["快捷技能栏"+i] = "能量盾"; skillRoot["快捷技能栏键"+i] = 48+i; }
        SkillLoadoutService.testOnlyUseRoot(skillRoot);
        var rows:Array = [];
        for (i = 0; i < 8; i++) rows.push({name:i == 0 ? "能量电池" : "药剂"+i,value:i+1});
        rootInventory = {背包:inventory([{name:"能量电池",value:1}]), 药剂栏:inventory(rows), 装备栏:inventory([])};
        _root.物品栏 = rootInventory;
        var dict:Object = {};
        dict.能量电池 = {name:"能量电池",use:"药剂",icon:"battery",description:"不会修改的权威元数据", nested:{a:1,b:2}};
        for (i = 1; i < 8; i++) dict["药剂"+i] = {name:"药剂"+i,use:"药剂",icon:"icon"+i,description:"metadata", nested:{a:1,b:2}};
        ItemUtil.itemDataDict = dict;
        _root.控制目标 = "__snapshotActor"; _root.暂停 = false;
        _root.主动战技函数 = {空手:{},长枪:{}};
        _root.收集品栏 = {材料:{getValue:function():Number {return 0;}},情报:{getValue:function():Number {return 0;}}};
        _root.keyshow = function(code:Number):String { return "K"+code; };
        for (i = 1; i < 5; i++) _root["快捷物品栏键"+i] = 48+i;
        _root.药剂组切换键 = 81;
        actor = {_name:"__snapshotActor",hp:100,mp:30,攻击模式:"空手",主动战技:{空手:{名字:"能量盾",消耗mp:10}}};
        var drugApi:Object = org.flashNight.arki.unit.Action.Skill.DrugInputService; drugApi.activeBank = 0;
        api.rawGroups = {}; api.drugRevision = 0; api.drugSignature = ""; api.drugItems = []; api.drugCounts = [];
        oldApi.drugRevision = 0; oldApi.drugSignature = ""; oldApi.drugItems = []; oldApi.drugCounts = [];
        previous = {};
    }
    private static function loadoutParity(label:String):Object {
        var actual:Object = api.readLoadout(), expected:Object = oldApi.readLoadout();
        check(PlayerHudService.testOnlySameProjection(actual,expected), label+" values");
        check(codec.stringifySafe(actual)==codec.stringifySafe(expected), label+" exact wire bytes/order");
        api.rawGroups.loadout = actual; currentLoadout = actual;
        return actual;
    }
    private static function resourceParity(label:String):Object {
        var actual:Object = SkillResourceService.snapshot(actor,currentLoadout,api.rawGroups.resources);
        var expected:Object = SkillResourceSnapshotLegacyFixture.snapshot(actor,currentLoadout);
        check(PlayerHudService.testOnlySameProjection(actual,expected), label+" values");
        check(codec.stringifySafe(actual)==codec.stringifySafe(expected), label+" exact wire bytes/order");
        api.rawGroups.resources=actual; return actual;
    }
    private static function testLoadout():Void {
        var first:Object=loadoutParity("cold loadout"), before:String=codec.stringifySafe(first);
        loadoutParity("warm skill revision");
        rootInventory.药剂栏.rows[0].value=2; loadoutParity("dose changed");
        check(codec.stringifySafe(first)==before,"old loadout and four drug rows remain immutable");
        rootInventory.药剂栏.rows[0].name="药剂1"; loadoutParity("same item reference renamed");
        var revision:Number=api.drugRevision;
        rootInventory.药剂栏.rows[0]={name:"药剂1",value:2}; loadoutParity("equivalent item replaced");
        check(api.drugRevision==revision+1,"identity replacement retains the original write revision gate");
        rootInventory.药剂栏.rows[7].value=9; loadoutParity("inactive bank changed");
        var drugApi:Object=org.flashNight.arki.unit.Action.Skill.DrugInputService;
        drugApi.activeBank=1; loadoutParity("bank switch");
        _root.快捷物品栏键4=90; _root.药剂组切换键=82; loadoutParity("live key bindings");
        ItemUtil.itemDataDict.药剂4.icon="changed-icon";
        check(loadoutParity("same metadata new icon").drugs[0].icon=="changed-icon","raw metadata is reread");
        var authority:String=codec.stringifySafe(ItemUtil.itemDataDict);
        api.rawGroups.loadout.drugs[0].icon="caller-edit";
        loadoutParity("detached caller edit repaired by next sample");
        check(codec.stringifySafe(ItemUtil.itemDataDict)==authority,"display rows never alias item metadata");
        var counts:Array=[0,-1,Number.NaN,Number.POSITIVE_INFINITY,null,undefined,"3",2.5];
        for(var i:Number=0;i<counts.length;i++){rootInventory.药剂栏.rows[4].value=counts[i];loadoutParity("count normalization "+i);}
        rootInventory.药剂栏.rows[4]=null; loadoutParity("empty slot");
        skillRoot.技能表对象.能量盾.MP=12; loadoutParity("skill cost changed");
        skillRoot.快捷技能栏12=""; loadoutParity("last skill slot cleared");
        drugApi.activeBank=0; rootInventory.药剂栏.rows[0]={name:"能量电池",value:1}; loadoutParity("restore resources");
        var full:Object={}; check(api.addGroup(full,"loadout",api.readLoadout(),true),"forced full includes unchanged loadout");
    }
    private static function testResources():Void {
        var first:Object=resourceParity("cold resources"), before:String=codec.stringifySafe(first);
        var mp:Array=[0,9,10,11,19,20,29,30,Number.NaN,Number.POSITIVE_INFINITY,null,undefined,"15"];
        for(var i:Number=0;i<mp.length;i++){actor.mp=mp[i];resourceParity("MP threshold "+i);}
        check(codec.stringifySafe(first)==before,"resource changes preserve all previous hint rows");
        actor.mp=100;
        for(var quantity:Number=0;quantity<3;quantity++){
            rootInventory.背包.rows[0].value=quantity;rootInventory.药剂栏.rows[0].value=0;
            loadoutParity("quantity "+quantity);resourceParity("item threshold "+quantity);
        }
        rootInventory.背包.indexReads=rootInventory.药剂栏.indexReads=0;
        SkillResourceService.snapshot(actor,currentLoadout,api.rawGroups.resources);
        check(rootInventory.背包.indexReads==1 && rootInventory.药剂栏.indexReads==1,"twelve slots plus weapon share only this snapshot's item query");
        rootInventory.背包.rows[0].value=0;
        check(resourceParity("same-frame inventory mutation").weapon.state=="blocked","no cross-frame stock cache");
        actor.__skillResourceNotice={serial:3,kind:"skill",slot:1,reason:"mp",at:getTimer(),world:StageReturnFlow.worldIdentity(_root.gameworld)};
        resourceParity("feedback appears"); actor.__skillResourceNotice.serial=4;resourceParity("new feedback serial");
        actor.__skillResourceNotice.at=getTimer()-601; check(resourceParity("feedback expires").feedback==null,"expired notice retired");
        actor.__skillResourceNotice={serial:5,kind:"switch",slot:0,reason:"empty",at:getTimer(),world:StageReturnFlow.worldIdentity(_root.gameworld)};
        _root.暂停=true;check(resourceParity("pause retires notice").feedback==null,"paused feedback cleared");_root.暂停=false;
        actor.主动战技.空手.战技函数=function():Void{};actor.主动战技.空手.战技函数.原子释放=true;resourceParity("atomic resource rule");
        delete actor.主动战技.空手.战技函数;
        var full:Object={}; check(api.addGroup(full,"resources",SkillResourceService.snapshot(actor,currentLoadout,api.rawGroups.resources),true),"forced full includes unchanged resources");
    }
    private static function read(kind:String,legacy:Boolean):Object {
        var value:Object;
        if(kind=="loadout") value=legacy?oldApi.readLoadout():api.readLoadout();
        else value=legacy?SkillResourceSnapshotLegacyFixture.snapshot(actor,currentLoadout):SkillResourceService.snapshot(actor,currentLoadout,api.rawGroups.resources);
        var groups:Object={};
        if(legacy){if(!PlayerHudService.testOnlySameProjection(previous[kind],value)){previous[kind]=value;groups[kind]=value;}}
        else api.addGroup(groups,kind,value,false);
        return groups;
    }
    private static function time(kind:String,legacy:Boolean,changing:Boolean):Number {
        var start:Number=getTimer();
        for(var i:Number=0;i<100;i++){
            if(changing){actor.mp=(i&1)==0?0:100;rootInventory.药剂栏.rows[0].value=1+(i&1);}
            if(read(kind,legacy)[kind]!=undefined)checksum++;
        }
        return getTimer()-start;
    }
    private static function bench(kind:String,changing:Boolean):Void {
        time(kind,true,changing);time(kind,false,changing);
        var oldValues:Array=[],newValues:Array=[];
        for(var round:Number=0;round<5;round++){
            if((round&1)==0){oldValues.push(time(kind,true,changing));newValues.push(time(kind,false,changing));}
            else{newValues.push(time(kind,false,changing));oldValues.push(time(kind,true,changing));}
        }
        trace("[AS2_HOTPATH_BENCH] "+kind+"_"+(changing?"changing":"unchanged")+"|iterations=100|baselineMs="+oldValues.join(",")+"|candidateMs="+newValues.join(","));
    }
    public static function runAllTests():Void {
        passed=failed=checksum=0;codec=new LiteJSON();api=org.flashNight.arki.hud.PlayerHudService;oldApi=org.flashNight.arki.hud.PlayerHudSnapshotLegacyFixture;
        var keys:Array=["物品栏","收集品栏","控制目标","暂停","主动战技函数","keyshow","快捷物品栏键1","快捷物品栏键2","快捷物品栏键3","快捷物品栏键4","药剂组切换键","gameworld"];
        var fields:Array=["rawGroups","drugRevision","drugSignature","drugItems","drugCounts"];
        var saved:Object={},savedApi:Object={},savedData:Object=ItemUtil.itemDataDict,i:Number;
        for(i=0;i<keys.length;i++)saved[keys[i]]=_root[keys[i]];
        for(i=0;i<fields.length;i++)savedApi[fields[i]]=api[fields[i]];
        var drugApi:Object=org.flashNight.arki.unit.Action.Skill.DrugInputService;var savedBank:Number=drugApi.activeBank;
        var world:MovieClip=_root.createEmptyMovieClip("__loadoutResourceWorld",_root.getNextHighestDepth());_root.gameworld=world;
        try{
            setup();testLoadout();testResources();
            actor.mp=100;rootInventory.背包.rows[0].value=2;currentLoadout=api.readLoadout();
            bench("loadout",false);bench("loadout",true);bench("resources",false);bench("resources",true);
        }finally{
            world.removeMovieClip();for(i=0;i<keys.length;i++)_root[keys[i]]=saved[keys[i]];
            for(i=0;i<fields.length;i++)api[fields[i]]=savedApi[fields[i]];
            ItemUtil.itemDataDict=savedData;drugApi.activeBank=savedBank;SkillLoadoutService.testOnlyReset();
        }
        trace("PlayerHudLoadoutResourceTest Tests Passed: "+passed);
        trace("PlayerHudLoadoutResourceTest Tests Failed: "+failed);
    }
}
