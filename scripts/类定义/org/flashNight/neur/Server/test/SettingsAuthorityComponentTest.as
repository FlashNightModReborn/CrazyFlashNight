import org.flashNight.neur.Server.SettingsCanonical;
import org.flashNight.neur.Server.SettingsCanonicalSchema;
import org.flashNight.neur.Server.SaveManager;
import org.flashNight.arki.ui.GameSettingsPanelService;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.arki.key.KeyManager;

/** Real services, synthetic root; every apply stops before any SO is obtained. */
class org.flashNight.neur.Server.test.SettingsAuthorityComponentTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++; else { failed++; trace("SettingsAuthorityComponentTest FAIL: " + name); }
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
        passed=0; failed=0;
        var v:Object=sample();
        _root.savePath="cf7_agent_readonly";
        _root.角色名="owned fixture"; _root.等级=1; _root.允许存档=false;
        _root.存档系统={dirtyMark:false};
        _root.默认键值设定=KeyManager.copyKeySettings(v.keys); _root.键值设定=v.keys;
        _root.按键设定表=[[0,0,0,0]];
        _root.刷新键值设定=function():Void {};
        _root.帧计时器={性能等级上限:1};
        _root.是否阴影=true; _root.是否视觉元素=true; _root.cameraZoomToggle=true;
        _root.basicZoomScale=1.2; _root.立绘类型=1;
        var weather:WeatherSystem=WeatherSystem.getInstance();
        weather.enableDayNightCycle=true; weather.pauseDayNightCycle=false; weather.useFilterRendering=true;
        _root.soundEffectManager={globalVolume:42,bgmVolume:55,jukeboxOverride:false,trueRandom:false,playMode:"albumLoop",
            getGlobalVolume:function():Number {return this.globalVolume;}, getBGMVolume:function():Number {return this.bgmVolume;},
            setGlobalVolume:function(n:Number):Void {this.globalVolume=n;}, setBGMVolume:function(n:Number):Void {this.bgmVolume=n;},
            getJukeboxOverride:function():Boolean {return this.jukeboxOverride;}, getTrueRandom:function():Boolean {return this.trueRandom;},
            getPlayMode:function():String {return this.playMode;},setJukeboxOverride:function(n:Boolean):Void {this.jukeboxOverride=n;},
            setTrueRandom:function(n:Boolean):Void {this.trueRandom=n;},setPlayMode:function(n:String):Void {this.playMode=n;},playSound:function():Void {}};
        var manager:SaveManager=SaveManager.getInstance();
        manager._configureSaveFlowForTest({saveInFlight:false});
        check(SaveManager.installSettingsAuthorityBootstrap({protocol:2,contextId:"ctx.fixture",saveOwnerId:"owner.fixture",
            authorityEpoch:"vm.fixture",originNamespaceDigest:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            slot:_root.savePath,writeAdmission:"allowed"}),"trusted metadata installed before authority");
        var params:Object={v:2,contextId:"ctx.fixture",saveOwnerId:"owner.fixture",authorityEpoch:"vm.fixture.1"};
        var wire:Object;
        _root.server={sendSocketMessage:function(text:String):Void {wire=new LiteJSON().parse(text);}};
        GameSettingsPanelService.install();
        var framed:Object={v:2,contextId:params.contextId,saveOwnerId:params.saveOwnerId,authorityEpoch:params.authorityEpoch,
            task:"game_command",action:"settingsSnapshot",callId:17};
        _root.gameCommands.settingsSnapshot(framed);
        check(wire.v===2 && wire.callId===17 && wire.snapshot.keys.length==36,"real registered command preserves transport framing and full v2 body");
        var snap:Object=GameSettingsPanelService.execute("snapshot",params);
        check(snap.success && snap.snapshot.keys.length==36 && snap.state.revision==0,"real service initial committed snapshot");
        check(snap.outcome.applyState=="none" && snap.outcome.applied===null && !snap.state.durable,"no default confirmation");
        var preview:Object={v:2,contextId:params.contextId,saveOwnerId:params.saveOwnerId,authorityEpoch:params.authorityEpoch,
            stateToken:snap.state.stateToken,globalVolume:90,bgmVolume:80,sample:"none"};
        var p:Object=GameSettingsPanelService.execute("preview",preview);
        check(p.success && _root.soundEffectManager.globalVolume==90,"real preview setters run");
        check(manager.packSettings().setGlobalVolume==42 && p.snapshot.settings.setGlobalVolume==42,"save and snapshot mask preview");
        var cancel:Object=GameSettingsPanelService.execute("cancel",params);
        check(cancel.success && _root.soundEffectManager.globalVolume==42 && _root.soundEffectManager.bgmVolume==55,"own preview restored");
        var gate:Object={v:2,contextId:params.contextId,saveOwnerId:params.saveOwnerId,authorityEpoch:params.authorityEpoch,
            sourceAuthorityEpoch:params.authorityEpoch,operationToken:"op.retired",saveAttemptId:"save.retired",
            originMutationRequestDigest:"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",admission:"hold"};
        check(GameSettingsPanelService.execute("authority_gate",gate).success && !manager.settingsWriteAllowed(),"trusted Host hold closes every source writer");
        var retired:Object=GameSettingsPanelService.execute("reconcile",{v:2,contextId:params.contextId,saveOwnerId:params.saveOwnerId,
            authorityEpoch:params.authorityEpoch,sourceAuthorityEpoch:params.authorityEpoch,operationToken:gate.operationToken,
            saveAttemptId:gate.saveAttemptId,originMutationRequestDigest:gate.originMutationRequestDigest});
        check(retired.outcome.applyState=="not_applied" && retired.holdActive,"exact query certifies retired operation without releasing Host metadata gate");
        gate.admission="release";
        check(GameSettingsPanelService.execute("authority_gate",gate).success && manager.settingsWriteAllowed(),"exact Host release after journal settlement");
        // Character switches receive a new trusted owner/VM namespace. Host's
        // first request is .1 even when a previous character already had a view.
        var firstOwner:Object=_root.存档系统;
        var firstSlot:String=_root.savePath;
        var firstAuthority:Object=manager.getSettingsAuthority();
        var managerState:Object=manager;
        _root.savePath="bookrun_fixture"; _root.存档系统={dirtyMark:false};
        managerState._settingsAuthority=null;
        SaveManager.installSettingsAuthorityBootstrap({protocol:2,contextId:"ctx.book",saveOwnerId:"owner.book",
            authorityEpoch:"vm.book",originNamespaceDigest:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            slot:_root.savePath,writeAdmission:"allowed"});
        var bookParams:Object={v:2,contextId:"ctx.book",saveOwnerId:"owner.book",authorityEpoch:"vm.book.1"};
        check(GameSettingsPanelService.execute("snapshot",bookParams).success,
            "fresh character namespace accepts Host's first generation");
        check(!firstAuthority.matches(bookParams),"old character authority cannot claim the temporary actor");
        managerState._settingsAuthority=null;
        check(manager.getSettingsAuthority().epoch()=="vm.book.2"
            && !GameSettingsPanelService.execute("snapshot",bookParams).success,
            "same owner namespace still rejects a retired generation");
        _root.savePath=firstSlot; _root.存档系统={dirtyMark:false}; managerState._settingsAuthority=null;
        SaveManager.installSettingsAuthorityBootstrap({protocol:2,contextId:"ctx.return",saveOwnerId:"owner.return",
            authorityEpoch:"vm.return",originNamespaceDigest:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            slot:_root.savePath,writeAdmission:"allowed"});
        check(GameSettingsPanelService.execute("snapshot",{v:2,contextId:"ctx.return",saveOwnerId:"owner.return",
            authorityEpoch:"vm.return.1"}).success,"returning original character gets the new owner's first generation");
        _root.存档系统=firstOwner; managerState._settingsAuthority=firstAuthority;
        SaveManager.installSettingsAuthorityBootstrap({protocol:2,contextId:"ctx.fixture",saveOwnerId:"owner.fixture",
            authorityEpoch:"vm.fixture",originNamespaceDigest:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            slot:firstSlot,writeAdmission:"allowed"});
        var keys:Array=[];
        for(var i:Number=0;i<v.keys.length;i++)keys.push({id:v.keys[i][1],keyCode:v.keys[i][2]});
        v.settings.setGlobalVolume=43;
        var apply:Object={v:2,contextId:params.contextId,saveOwnerId:params.saveOwnerId,authorityEpoch:params.authorityEpoch,
            operationToken:"op.fixture",saveAttemptId:"save.fixture",originMutationRequestDigest:"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            settingsDigest:"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",expectedRevision:0,baseStateToken:snap.state.stateToken,
            expectedCanonical:SettingsCanonical.encode(v.settings,keys,false),keySchemaVersion:2,settings:v.settings,keys:keys};
        var rejected:Object=GameSettingsPanelService.execute("apply",apply);
        check(!rejected.success && rejected.outcome.applied===false && rejected.outcome.attemptState=="not_sent","before effect refusal explicit");
        _root.允许存档=true;
        apply.operationToken="op.partial";apply.saveAttemptId="save.partial";
        var refreshCalls:Number=0;
        _root.刷新键值设定=function():Void {refreshCalls++;throw new Error("owned partial apply injection");};
        var uncertain:Object=GameSettingsPanelService.execute("apply",apply);
        check(!uncertain.success && uncertain.requiresReconcile && uncertain.outcome.applied===null,"partial setter result never replayable");
        check(uncertain.writeAdmission=="blocked_by_operation" && !manager.settingsWriteAllowed(),"all writers blocked by authority unknown");
        var observed:Object=GameSettingsPanelService.execute("snapshot",params);
        check(observed.requiresReconcile && refreshCalls==1,"ordinary snapshot never clears unknown or runs setters");
        var query:Object={v:2,contextId:params.contextId,saveOwnerId:params.saveOwnerId,authorityEpoch:params.authorityEpoch,
            operationToken:apply.operationToken,saveAttemptId:apply.saveAttemptId,sourceAuthorityEpoch:params.authorityEpoch,
            originMutationRequestDigest:apply.originMutationRequestDigest};
        var reconciled:Object=GameSettingsPanelService.execute("reconcile",query);
        check(reconciled.success && reconciled.requiresReconcile && refreshCalls==1,"exact readonly reconcile retains partial unknown");
        _root.soundEffectManager.getGlobalVolume=function():Number {throw new Error("read only observation failure");return 0;};
        reconciled=GameSettingsPanelService.execute("reconcile",query);
        check(reconciled.state===null && reconciled.snapshot===null && reconciled.outcome.applyState=="unknown","observation failure retains structured history");
        trace("SettingsAuthorityComponentTest Tests Passed: "+passed);
        trace("SettingsAuthorityComponentTest Tests Failed: "+failed);
    }
}
