import org.flashNight.neur.Server.SaveManager;
import org.flashNight.neur.Server.SettingsCanonical;
import org.flashNight.neur.Server.SettingsCanonicalSchema;
import org.flashNight.arki.ui.GameSettingsPanelService;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.arki.key.KeyManager;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.object.ObjectUtil;

/** Real native SO flush, synthetic business root, unique exact owned test slot. */
class org.flashNight.neur.Server.test.SettingsOwnedSolTest {
    private static var passed:Number=0;
    private static var failed:Number=0;
    private static var ammoItem:BaseItem;
    private static var ammoPassed:Number=0;
    private static var ammoFailed:Number=0;
    private static function checkAmmo(ok:Boolean, name:String):Void {
        if(ok)ammoPassed++;else{ammoFailed++;trace("[FAIL] WeaponAmmoOwnedSolTest: "+name);}
    }
    private static function findAmmo(node):Object {
        if (node == null || typeof node != "object") return null;
        if (node.name == "TTI Benelli M4" && node.value.ownedAmmoFixture === true) return node;
        for (var key:String in node) {
            var found:Object = findAmmo(node[key]);
            if (found != null) return found;
        }
        return null;
    }
    private static function check(ok:Boolean,name:String):Void {
        if(ok)passed++;else {failed++;trace("[FAIL] SettingsOwnedSolTest: "+name);}
    }
    private static function sample():Object {
        var values:Array = [42,55,1,1,1,1,12,1,0,1,1,0,0,1];
        var codes:Array = [87,83,65,68,74,75,82,49,50,51,52,53,54,55,56,57,48,
            32,85,73,79,80,76,72,71,67,66,78,77,47,69,70,18,81,16,17];
        var settings:Object = {};
        var keys:Array = [];
        for (var i:Number = 0; i < 14; i++) {
            var booleanField:Boolean = false;
            for (var j:Number = 0; j < SettingsCanonicalSchema.BOOLEAN_INDEXES.length; j++) {
                if (SettingsCanonicalSchema.BOOLEAN_INDEXES[j] == i) booleanField = true;
            }
            settings[SettingsCanonicalSchema.SETTING_IDS[i]] = booleanField ? values[i] == 1 :
                i == 6 ? values[i] / 10 : i == 13 ? SettingsCanonicalSchema.PLAY_MODES[values[i]] : values[i];
        }
        for (var k:Number = 0; k < 36; k++) keys.push(["label", SettingsCanonicalSchema.KEY_IDS[k], codes[k]]);
        return {settings:settings, keys:keys};
    }
    public static function runAllTests():Void {
        var cfg:Object=_root.__ownedSettingsSolConfig;
        if(cfg==null || typeof cfg.slot!="string" || cfg.slot.indexOf("cf7_env_set_")!=0 || cfg.slot.length!=32
            || cfg.metadata.slot!==cfg.slot || cfg.apply.contextId!==cfg.metadata.contextId) {
            trace("[FAIL] SettingsOwnedSolTest: owned slot admission");return;
        }
        var v:Object=sample();
        _root.savePath=cfg.slot;_root.存档系统={dirtyMark:false};_root.允许存档=true;
        _root.角色名="Owned SOL fixture";_root.等级=1;_root.基础身价值=1000;_root.身价=1000;
        _root.金钱=1000;_root.虚拟币=0;_root.经验值=0;_root.技能点数=0;
        _root.tasks_to_do=[];_root.tasks_finished={};_root.task_chains_progress={主线:0};
        _root.主线任务进度=0;_root.基建系统={infrastructure:{__unknownCounter:1}};
        _root.物品栏={背包:{toObject:function():Object{return {}; }},装备栏:{toObject:function():Object{return {}; }},
            药剂栏:{toObject:function():Object{return {}; }},仓库:{toObject:function():Object{return {}; }},战备箱:{toObject:function():Object{return {}; }}};
        // 仅存在于本次已准入的唯一测试槽，走真实物品 toObject 与 SaveManager 原生 flush。
        ammoItem = new BaseItem("TTI Benelli M4", {level:1, mods:[], shot:-3, ownedAmmoFixture:true,
            ammoState:{v:1, capacity:7, chamber:1, ghost:2, reward:0, reserve:4,
                reserveName:"00号鹿弹", paidNormal:7, paidChamber:0}}, 123);
        _root.物品栏.装备栏.toObject = function():Object {
            return {长枪:SettingsOwnedSolTest.ammoItem.toObject()};
        };
        _root.收集品栏={材料:{toObject:function():Object{return {}; }},情报:{toObject:function():Object{return {}; }}};
        _root.宠物信息=[];_root.宠物领养限制=5;_root.商城已购买物品=[];_root.商城购物车=[];
        _root._saveExt={__ownedUnknown:{value:7},ownProbe:{value:1}};
        _root.killStats={total:0,byType:{}};_root.UpdateTaskProgress=function():Void {};
        _root.agent={推送绑定刷新:function():Void {throw new Error("owned post-confirm notification injection");}};
        _root.默认键值设定=KeyManager.copyKeySettings(v.keys);_root.键值设定=v.keys;_root.按键设定表=[[0,0,0,0]];
        _root.刷新键值设定=function():Void {};
        _root.帧计时器={性能等级上限:1};_root.是否阴影=true;_root.是否视觉元素=true;
        _root.cameraZoomToggle=true;_root.basicZoomScale=1.2;_root.立绘类型=1;
        var weather:WeatherSystem=WeatherSystem.getInstance();weather.enableDayNightCycle=true;weather.pauseDayNightCycle=false;weather.useFilterRendering=true;
        _root.soundEffectManager={globalVolume:42,bgmVolume:55,jukeboxOverride:false,trueRandom:false,playMode:"albumLoop",
            getGlobalVolume:function():Number{return this.globalVolume;},getBGMVolume:function():Number{return this.bgmVolume;},
            setGlobalVolume:function(n:Number):Void{this.globalVolume=n;},setBGMVolume:function(n:Number):Void{this.bgmVolume=n;},
            getJukeboxOverride:function():Boolean{return this.jukeboxOverride;},getTrueRandom:function():Boolean{return this.trueRandom;},
            getPlayMode:function():String{return this.playMode;},setJukeboxOverride:function(n:Boolean):Void{this.jukeboxOverride=n;},
            setTrueRandom:function(n:Boolean):Void{this.trueRandom=n;},setPlayMode:function(n:String):Void{this.playMode=n;},playSound:function():Void{}};
        var manager:SaveManager=SaveManager.getInstance();
        manager._configureSaveFlowForTest({saveInFlight:false,flushResult:undefined,beforeLocalCommit:null,resetScheduler:true});
        manager._resetSavePhysicalStatsForTest();
        check(SaveManager.installSettingsAuthorityBootstrap(cfg.metadata),"exact trusted bootstrap");
        var so:SharedObject=SharedObject.getLocal(cfg.slot);
        so.data.__ownedTop={nonce:cfg.slot,value:9};
        var keys:Array=[];for(var i:Number=0;i<v.keys.length;i++)keys.push({id:v.keys[i][1],keyCode:v.keys[i][2]});
        v.settings.setGlobalVolume=43;cfg.apply.settings=v.settings;cfg.apply.keys=keys;
        check(manager.captureSettingsAuthority() && manager.getSettingsAuthority().stateToken()===cfg.apply.baseStateToken,"base identity before first possible write");
        manager._configureSaveFlowForTest({flushResult:false}); // Injection bypasses native flush; it is not a native negative result.
        var applied:Object=GameSettingsPanelService.execute("apply",cfg.apply);
        check(applied.outcome.applied===true,"complete application through real service");
        if(applied.outcome.applied!==true)return;
        check(applied.outcome.durable===false && manager._getSavePhysicalStatsForTest().flushSuccess==0,
            "retry has no previous successful native flush");
        var preview:Object={v:2,contextId:cfg.apply.contextId,saveOwnerId:cfg.apply.saveOwnerId,authorityEpoch:cfg.apply.authorityEpoch,
            stateToken:cfg.apply.operationToken,globalVolume:90,bgmVolume:80,sample:"none"};
        check(GameSettingsPanelService.execute("preview",preview).success && manager.packSettings().setGlobalVolume==43,
            "save retry packs committed settings during new preview");
        manager._configureSaveFlowForTest({flushResult:undefined});
        var retried:Object=GameSettingsPanelService.execute("save",cfg.save);
        check(retried.outcome.durable===true && _root.soundEffectManager.globalVolume==90 && retried.state.revision==1,
            "save-only native retry preserves new preview and does not apply twice");
        check(manager.getSettingsAuthority().readOutcome().durable===true,"native raw flush confirms despite notification throw");
        if(manager.getSettingsAuthority().readOutcome().durable!==true)return;
        check(so.data.test.ext.settingsReceipt.operationToken===cfg.apply.operationToken
            && so.data.test.ext.settingsReceipt.saveAttemptId===cfg.save.saveAttemptId,"receipt shares exact native payload");
        so.data.__cycle=so.data;
        var freezeRejected:Boolean=!manager.beginRewardCommit("cycle."+cfg.slot,null,null);
        delete so.data.__cycle;
        check(freezeRejected && !manager.hasRewardCommitPending(),"complete before freeze failure exposes no candidate");
        var committed:Number=0,rolledBack:Number=0;
        var operation:String="reward."+cfg.slot;
        check(manager.beginRewardCommit(operation,function(ok:Boolean):Boolean {if(ok)committed++;else rolledBack++;return true;},null),"reward owns before image");
        _root.基建系统.infrastructure.__unknownCounter=2;_root.tasks_to_do.push(["owned",1]);_root._saveExt.ownProbe.value=2;
        check(so.data.test.infrastructure.__unknownCounter==1 && so.data.tasks_to_do.length==0,"prepared runtime aliases cannot poison SO");
        var detached:Object=manager.getSOData();detached.test.infrastructure.__unknownCounter=999;
        check(so.data.test.infrastructure.__unknownCounter==1,"mutable SO exit detached during reward");
        manager._configureSaveFlowForTest({beforeLocalCommit:function():Void{throw new Error("owned exposed before flush injection");}});
        var pending:String=manager.commitRewardCandidate(operation,"stage.return_base");
        check(pending=="pending" && rolledBack==0 && manager.hasRewardCommitPending(),"exposure forbids rollback before raw flush");
        _root._saveExt.ownProbe.value=99;
        manager._configureSaveFlowForTest({beforeLocalCommit:null});
        var resolution:String=manager.resolveRewardCommit(operation);
        check(resolution=="committed" && committed==1 && rolledBack==0,"same frozen candidate explicitly confirms once");
        check(so.data.test.ext.ownProbe.value==2 && so.data.test.infrastructure.__unknownCounter==2
            && so.data.__ownedTop.value==9 && so.data.test.ext.__ownedUnknown.value==7,"frozen after preserves unknown serialized fields");
        var domainCalls:Number=0,domainBusiness:Number=0,reentered:String;
        _root._saveExt.ownProbe.value=2;
        var finalizerOperation:String="finalizer."+cfg.slot;
        manager.beginRewardCommit(finalizerOperation,function(ok:Boolean):Boolean {
            if(!ok)return true;
            domainCalls++;
            reentered=manager.resolveRewardCommit(finalizerOperation);
            if(domainBusiness==0)domainBusiness++;
            if(domainCalls==1)throw new Error("owned domain finalizer notification failure");
            return true;
        },null);
        var finalizerPending:String=manager.commitRewardCandidate(finalizerOperation,"stage.return_base");
        check(finalizerPending=="pending" && manager.hasRewardCommitPending(),"raw true with unsettled finalizer retains confirmed candidate");
        check(reentered=="pending" && domainCalls==1 && domainBusiness==1,"finalizer reentry cannot reexecute domain callback");
        var flushes:Number=manager._getSavePhysicalStatsForTest().flushAttempt;
        var finalized:String=manager.resolveRewardCommit(finalizerOperation);
        check(finalized=="committed" && domainCalls==2 && domainBusiness==1,"known finalizer settlement does not duplicate business");
        check(manager._getSavePhysicalStatsForTest().flushAttempt==flushes,"confirmed finalizer retry performs no additional flush");
        check(!manager.hasRewardCommitPending() && manager.getSettingsAuthority().readOutcome().durable===true,"all native write boundaries terminal");
        var durableAmmo:Object = findAmmo(so.data.test);
        checkAmmo(durableAmmo != null,"actual inventory weapon included in native payload");
        checkAmmo(durableAmmo.value.ammoState.chamber == 1 && durableAmmo.value.ammoState.ghost == 2
            && durableAmmo.value.shot == -3,"typed overload survives save packing");
        checkAmmo(durableAmmo.value.ammoState.reserve == 4 && durableAmmo.value.ammoState.reserveName == "00号鹿弹",
            "paid remainder keeps exact ammunition identity");
        checkAmmo(durableAmmo.value.ammoState.paidNormal == 7 && durableAmmo.value.ammoState.paidChamber == 0,
            "funded counters survive native payload");
        ammoItem.value.ammoState.reserve = 0;
        var rebuilt:BaseItem = new BaseItem(durableAmmo.name, ObjectUtil.clone(durableAmmo.value), durableAmmo.lastUpdate);
        checkAmmo(durableAmmo.value.ammoState.reserve == 4 && rebuilt.value.ammoState.ghost == 2
            && rebuilt.value.ammoState.reserve == 4,"saved ammo is detached from subsequent live item mutation");
        trace("WeaponAmmoOwnedSolPayload " + new LiteJSON().stringifySafe(durableAmmo));
        trace("WeaponAmmoOwnedSolTest Tests Passed: "+ammoPassed);
        trace("WeaponAmmoOwnedSolTest Tests Failed: "+ammoFailed);
        trace("SettingsOwnedSolTest slot: "+cfg.slot);
        trace("SettingsOwnedSolTest receipt: "+new LiteJSON().stringifySafe(so.data.test.ext.settingsReceipt));
        trace("SettingsOwnedSolTest Tests Passed: "+passed);trace("SettingsOwnedSolTest Tests Failed: "+failed);
        if(failed==0)trace("SettingsOwnedSolTest NativeRawKnownTerminal: "+cfg.slot);
    }
}
