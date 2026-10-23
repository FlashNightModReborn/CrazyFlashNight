/** Real AVM1 installed-getter proof; one fresh, read-only TestLoader root. */
class org.flashNight.arki.ui.MeridianGetterRegistrationTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,label:String):Void {
        if(value){passed++;trace("[PASS] "+label);}else{failed++;trace("[FAIL] "+label);}
    }
    public static function runAllTests():Void {
        passed=failed=0;
        var api:Object=org.flashNight.arki.ui.MeridianPanelService;
        var names:Array=["经脉内力加成","经脉HP加成","经脉MP加成","经脉防御加成"];
        var apiKeys:Array=["_installed","_loading","_config","_nodeIndex","_caps","_cache","_raw","_dirty","_lightResults","_skillMods","_contextOwner","_contextSlot","_contextExt","_contextToken","_contextStatToken"];
        var rootKeys:Array=["存档系统","savePath","_saveExt","gameCommands","虚拟币"];
        var oldApi:Object={};var oldRoot:Object={};var ownedRoot:Object={};
        for(var i:Number=0;i<apiKeys.length;i++)oldApi[apiKeys[i]]=api[apiKeys[i]];
        for(i=0;i<rootKeys.length;i++){var key:String=rootKeys[i];oldRoot[key]=_root[key];ownedRoot[key]=_root.hasOwnProperty(key);}
        var installedOwned:Boolean=false;
        var probe:MovieClip=_root.createEmptyMovieClip("__meridianGetterNativeControl",_root.getNextHighestDepth());
        try {
            var propertyFunction:Function=probe.addProperty;
            var twoArgs=propertyFunction.apply(probe,["twoArgs",function():Number{return 7;}]);
            var threeArgs=propertyFunction.apply(probe,["threeArgs",function():Number{return 9;},null]);
            trace("MeridianGetterNativeControl: twoArgsReturn="+twoArgs+" twoArgsValue="+probe.twoArgs+" threeArgsReturn="+threeArgs+" threeArgsValue="+probe.threeArgs);
            check(twoArgs===false && probe.twoArgs===undefined,"native omitted-setter registration is rejected");
            check(probe.threeArgs===9,"native explicit-null read-only getter control returns9");
            for(i=0;i<names.length;i++)if(_root.hasOwnProperty(names[i]))throw new Error("getter probe requires fresh exclusively owned root");
            _root.存档系统={};_root.savePath="meridian-getter-test";_root.虚拟币=1000;_root.gameCommands={};
            _root._saveExt={meridians:{v:1,nodes:{inner1:true,hp1:true,mp1:true,def1:true}}};
            api._installed=false;api._loading=true;api._dirty=true;
            api._caps={innerPower:50,hp:1000,mp:1000,defense:500};
            api._config=[{id:"getter",nodes:[{id:"inner1",bonusType:"innerPower",bonusAmount:1},{id:"hp1",bonusType:"hp",bonusAmount:50},{id:"mp1",bonusType:"mp",bonusAmount:20},{id:"def1",bonusType:"defense",bonusAmount:5}]}];
            installedOwned=true;api.install();
            check(api.getBonus("innerPower")===1,"direct service reads the actual lit-node bonus1");
            check(_root.经脉内力加成===1,"production-installed innerPower getter reads1");
            check(_root.经脉HP加成===50,"production-installed HP getter reads50");
            check(_root.经脉MP加成===20,"production-installed MP getter reads20");
            check(_root.经脉防御加成===5,"production-installed defense getter reads5");
            check(_root.虚拟币===1000,"installed getters do not charge or issue a node commit");
        } catch(error){check(false,"getter probe exception "+error);}
        finally {
            if(installedOwned)for(i=0;i<names.length;i++)delete _root[names[i]];
            for(i=0;i<rootKeys.length;i++){key=rootKeys[i];if(ownedRoot[key])_root[key]=oldRoot[key];else delete _root[key];}
            for(i=0;i<apiKeys.length;i++)api[apiKeys[i]]=oldApi[apiKeys[i]];
            probe.removeMovieClip();
        }
        trace("MeridianGetterRegistrationTest Tests Passed: "+passed);
        trace("MeridianGetterRegistrationTest Tests Failed: "+failed);
    }
}
