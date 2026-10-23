/** 所有存档 owner 均为内存替身；不访问玩家 SharedObject。 */
class org.flashNight.arki.ui.MeridianPanelServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    public static function runAllTests():Void {
        passed = failed = 0;
        var api:Object = org.flashNight.arki.ui.MeridianPanelService;
        var rootKeys:Array = ["存档系统","savePath","_saveExt","虚拟币","gameworld","控制目标","记录玩家货币变化","获取虚拟币值","__meridianSaves","__meridianSaveOk","__meridianSwap"];
        var apiKeys:Array = ["_config","_nodeIndex","_caps","_cache","_raw","_dirty","_lightResults","_skillMods","_contextOwner","_contextSlot","_contextExt","_contextToken","_contextStatToken"];
        var rootBefore:Object = {}; var apiBefore:Object = {};
        var i:Number;
        for (i=0;i<rootKeys.length;i++) rootBefore[rootKeys[i]] = _root[rootKeys[i]];
        for (i=0;i<apiKeys.length;i++) apiBefore[apiKeys[i]] = api[apiKeys[i]];
        try {
            var node:Object = {id:"hp1",name:"HP",cost:100,bonusType:"hp",bonusAmount:50,requiredInfo:[]};
            var config:Array = [{id:"m",requiredInfo:[],nodes:[node]}];
            api._config = config; api._nodeIndex = {hp1:{node:node,meridianId:"m",order:0}};
            api._caps = {innerPower:50,hp:1000,mp:1000,defense:500};
            _root.gameworld = {}; _root.控制目标 = "no-actor";
            _root.记录玩家货币变化 = function():Void {};
            _root.获取虚拟币值 = function():Void {};
            _root.__meridianSaves = 0; _root.__meridianSaveOk = true; _root.__meridianSwap = false;
            var owner:Object = {markDirty:function():Void {},flushDurableNow:function():Boolean {
                _root.__meridianSaves++;
                if (_root.__meridianSwap) org.flashNight.arki.ui.MeridianPanelServiceTest.replaceContext({meridians:{v:1,nodes:{}}});
                return _root.__meridianSaveOk;
            }};
            _root.存档系统 = owner; _root.savePath = "isolated-meridian-A";
            var extA:Object = {meridians:{v:1,nodes:{}}}; _root._saveExt = extA; _root.虚拟币 = 1000;
            api.resetContext();
            var result:Object = api.executeLight("hp1");
            check(result.applied && result.success && _root.虚拟币==900,"A lights and charges once");
            check(api.getBonus("hp")==50,"A bonus follows lit set");
            result = api.executeLight("hp1");
            check(result.success && _root.虚拟币==900 && _root.__meridianSaves==1,"duplicate has no fee or save replay");
            var context:Object=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().contextToken();
            _root._saveExt={meridians:{v:1,nodes:{hp1:true}},rewardInbox:{v:2}};
            result=api.executeLight("hp1");
            check(result.success && api.getBonus("hp")==50 && _root.虚拟币==900 && _root.__meridianSaves==1
                    && org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().contextToken()===context,
                "ordinary reward ext clone preserves character generation and the exact node receipt");
            _root.savePath = "isolated-meridian-B"; _root._saveExt = {meridians:{v:1,nodes:{}}}; _root.虚拟币 = 0;
            check(api.getBonus("hp")==0,"A bonus cannot leak into B");
            check(api.executeLight("hp1").error=="insufficient_funds","B cannot reuse A receipt");
            _root.savePath = "isolated-meridian-A"; _root._saveExt = extA;
            check(api.getBonus("hp")==50 && api.executeLight("hp1").error=="already_lit","A return recomputes without old operation cache");
            replaceContext({meridians:{v:1,nodes:{}}});
            check(api.getBonus("hp")==0,"same owner and slot reload has a fresh identity");
            _root.虚拟币 = 1000; _root.__meridianSaveOk = false;
            result = api.executeLight("hp1");
            var saves:Number = _root.__meridianSaves;
            check(result.applied && result.savePending && _root.虚拟币==900,"pending save retains committed memory");
            _root._saveExt={meridians:{v:1,nodes:{hp1:true}},rewardInbox:{v:2}};
            _root.__meridianSaveOk = true;
            result = api.executeLight("hp1");
            check(result.success && !result.savePending && _root.虚拟币==900 && _root.__meridianSaves==saves+1,"exact pending retry saves only");
            check(api._config===config,"context changes retain read-only configuration");
            api.resetContext();
            check(api.getBonus("hp")==50 && api.executeLight("hp1").error=="already_lit","explicit reset also discards same-ext receipts");
            replaceContext({meridians:{v:1,nodes:{}}}); _root.虚拟币=1000; _root.__meridianSwap=true;
            result=api.executeLight("hp1");
            check(result.error=="context_changed" && api.getBonus("hp")==0,"late owner completion cannot publish into replacement context");
            _root.__meridianSwap=false; _root.虚拟币=0;
            check(api.executeLight("hp1").error=="insufficient_funds","replacement context has no stale applied receipt");
        } catch (error) { check(false,"unexpected exception: "+error); }
        finally {
            for (i=0;i<rootKeys.length;i++) _root[rootKeys[i]]=rootBefore[rootKeys[i]];
            for (i=0;i<apiKeys.length;i++) api[apiKeys[i]]=apiBefore[apiKeys[i]];
        }
        trace("MeridianPanelServiceTest Tests Passed: "+passed);
        trace("MeridianPanelServiceTest Tests Failed: "+failed);
    }
    private static function replaceContext(ext:Object):Void {
        // 与 SaveManager 的真实替换边界相同：先换 generation/detach，再安装新输入。
        org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().resetContext(_root.存档系统,String(_root.savePath),ext);
        _root._saveExt=ext;
    }
    private static function check(ok:Boolean,label:String):Void {
        if(ok) { passed++;trace("[PASS] Meridian: "+label); }
        else { failed++;trace("[FAIL] Meridian: "+label); }
    }
}
