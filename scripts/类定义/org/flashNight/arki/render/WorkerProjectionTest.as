import org.flashNight.arki.render.*;
import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.hud.PlayerHudService;
import org.flashNight.arki.corpse.DeathEffectRenderer;

class org.flashNight.arki.render.WorkerProjectionTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var saved:Object;
    private static var world:MovieClip;
    private static var baseline:Array;
    private static var randomState:Number;
    private static var randomCalls:Number;
    private static var completeLine:String;
    private static function check(ok:Boolean,label:String):Void { if(ok)passed++;else{failed++;trace("[TEST_FAIL] WorkerProjectionTest: "+label);} }
    private static function randomOffset(span:Number):Number {
        randomState=(randomState*1664525+1013904223)%4294967296;randomCalls++;
        return (randomState/4294967296*2-1)*span;
    }
    public static function runAllTests():Void {
        passed=failed=0;completeLine="FocusedTestRunId worker-projection Complete: "+_root.__workerProjectionRunId;
        saved={world:_root.gameworld,timer:_root.帧计时器,pause:_root.暂停,visual:_root.是否视觉元素,random:_root.随机偏移};
        world=_root.createEmptyMovieClip("__workerProjectionWorld",_root.getNextHighestDepth());
        _root.gameworld=world;_root.帧计时器={当前帧数:1};_root.暂停=false;_root.是否视觉元素=true;_root.随机偏移=randomOffset;
        world.createEmptyMovieClip("子弹区域",1);world.createEmptyMovieClip("效果",2);
        check(!WorkerProjectionPolicy.isNone("ray"),"ordinary session defaults to full");
        WorkerProjectionTestHost.install(false,function():Void { WorkerProjectionTest.fullReady(); });
        check(!WorkerProjectionPolicy.isCommitted(),"offer cannot claim a root-frame installation");
    }
    private static function makeGroup(vertical:Boolean,count:Number):ChainGroup {
        var b:Object={子弹种类:(vertical?"纵向联弹":"横向联弹")+"-普通子弹",baseAsset:vertical?"纵向联弹":"横向联弹",
            霰弹值:count,子弹散射度:7,xmov:3.125,ymov:0,_x:0,_y:-100,_rotation:27,_xscale:-100,_yscale:80,
            _alpha:100,_visible:true,Z轴坐标:0,每帧补弹数:3.25};
        var update:Function=vertical?_root.联弹系统.纵向联弹更新:_root.联弹系统.横向联弹更新;
        var g:ChainGroup=new ChainGroup(null,b,update,_root.联弹系统.渲染组);g.isObject=true;
        g.盒x=vertical?7:-5;g.盒y=-5;g.盒宽=g.盒高=10;g.盒固有半宽=g.盒固有半高=12.5;
        check(ChainVisualBridge.reserveGroup(g),"legitimate migrated ownership retained");
        var assemble:Function=vertical?_root.联弹系统.纵向联弹组装:_root.联弹系统.横向联弹组装;assemble(g);
        return g;
    }
    private static function transcript():Array {
        var out:Array=[];
        for(var mode:Number=0;mode<2;mode++) {
            randomState=19471;randomCalls=0;
            var g:ChainGroup=makeGroup(mode==1,32);
            for(var t:Number=0;t<48;t++) {
                g.bullet._x+=g.bullet.xmov;if(mode==0&&t>20)g.bullet._y+=7;
                if(t==17){g.bullet.xmov*=-0.8;g.bullet._rotation+=37;}
                var update:Function=g.update;update(g);
                var row:Array=[g.盒x,g.盒y,g.盒宽,g.盒高,g.bullet.霰弹值,g.bullet._x,g.bullet._y,
                    g.ma,g.mb,g.mc2,g.md,randomState,randomCalls];
                for(var u:Number=0;u<g.单元体列表.length;u++) {
                    var unit:ChainUnitData=g.单元体列表[u];ChainUnitManager.materializeUnit(g,unit);
                    row.push(unit.x,unit.y,unit.sin,unit.cos,unit.rot,unit.mc==null);
                }
                out.push(row);
                var wire:String=ChainVisualBridge.flush();
                if(WorkerProjectionPolicy.isNone("chain"))check(wire==null,"none never emits chain rows");
                else check(wire!=null,"full preserves actual group wire");
            }
            ChainVisualBridge.releaseGroup(g);
            for(u=0;u<g.单元体列表.length;u++){ChainVisualBridge.removeUnit(g,g.单元体列表[u]);ChainUnitManager.releaseUnitData(g.单元体列表[u]);}
            g.单元体列表.length=0;ChainVisualBridge.flush();
        }
        return out;
    }
    private static function fullReady():Void {
        try {
            check(WorkerProjectionPolicy.isCommitted()&&!WorkerProjectionPolicy.isNone("ray"),"full installs after actual EF");
            check(WorkerProjectionTestHost.committedReceipt.installClockKind=="flashRootEnterFrame"
                && WorkerProjectionTestHost.committedReceipt.installTick>=2,"root EF receipt contains actual progressing ticks");
            baseline=transcript();
            WorkerProjectionTestHost.restore();
            WorkerProjectionTestHost.install(true,function():Void { WorkerProjectionTest.noneReady(); });
        } catch(error){check(false,"full fixture: "+error);finish();}
    }
    private static function equal(a:Array,b:Array):Boolean {
        if(a.length!=b.length)return false;
        for(var i:Number=0;i<a.length;i++) {
            if(a[i] instanceof Array){if(!equal(a[i],b[i]))return false;}else if(a[i]!==b[i])return false;
        }
        return true;
    }
    private static function noneReady():Void {
        try {
            check(WorkerProjectionPolicy.isNone("ordinaryBullet")&&WorkerProjectionPolicy.isNone("ray")&&WorkerProjectionPolicy.isNone("chain"),"D2 installs projectile consumers together");
            check(!WorkerProjectionPolicy.isNone("sceneLighting")&&!WorkerProjectionPolicy.isNone("equipmentLighting"),"D2 retains both lights");
            var current:Array=transcript();check(equal(baseline,current),"full/none exact movement, collision, live unit and RNG transcript");
            var began:Number=getTimer();
            for(var birth:Number=0;birth<45000;birth++) {
                var b:Object={子弹种类:"横向联弹-普通子弹",霰弹值:8};
                var g:ChainGroup=new ChainGroup(null,b,null,null);g.isObject=true;
                if(!ChainVisualBridge.reserveGroup(g))throw "ownership unexpectedly rejected";
                for(var u:Number=0;u<8;u++) {
                    var unit:ChainUnitData=new ChainUnitData();g.单元体列表.push(unit);ChainVisualBridge.addUnit(g,unit);
                    if(!unit.nativeLive)throw "none visual capacity changed live unit";
                }
                var live:Object=ChainVisualBridge.getStats();
                if(live.groups!=1||live.reserved!=8||live.births!=0||live.deaths!=0)throw "unbounded none ledger";
                for(u=0;u<8;u++)ChainVisualBridge.removeUnit(g,g.单元体列表[u]);
                ChainVisualBridge.releaseGroup(g);
            }
            var stats:Object=ChainVisualBridge.getStats();
            check(stats.groups==0&&stats.reserved==0&&stats.births==0&&stats.deaths==0,"360000 births retire without any flush/GC dependency");
            trace("[WORKER_CHAIN_BOUND] groupsBorn=45000 unitsBorn=360000 peakLiveGroups=1 peakReserved=8 projectionRows=0 finalGroups="+stats.groups+" elapsedMs="+(getTimer()-began));
            for(var n:Number=0;n<2048;n++) {
                var clip:MovieClip=world.createEmptyMovieClip("ordinary"+n,world.getNextHighestDepth());clip.子弹种类="ordinary";
                BulletVisualProbe.registerNormal(clip);
                if(!clip.__nativeVisualOwned||clip.__nativeVisualAlpha!=100||clip._alpha!=0)throw "ordinary source ownership changed";
                clip.removeMovieClip();
            }
            check(BulletVisualProbe.trackedCount()==0,"none preserves hidden MC ownership without a tracking array");
            var config:TeslaRayConfig=new TeslaRayConfig();
            for(n=0;n<4096;n++) {
                if(!RayVisualBridge.trySpawn(10,20,30,40,config,null))throw "known none ray not consumed";
                RayVisualBridge.stopFlame("absent",n);RayVfxManager.spawn(10,20,30,40,config,null);
            }
            var ray:Object=RayVisualBridge.getStats();check(ray.active==0&&ray.configs==0&&ray.queued==0&&RayVisualBridge.flush()==null,"none ray records/configs/queues stay empty beyond prior 1024 limit");
            var consumed:Boolean=true;
            for(n=0;n<4096;n++) consumed=CombatFxBridge.tryShell("测试弹壳",NaN,NaN,100,3,0)
                &&CombatFxBridge.tryMuzzle("测试枪火",NaN,NaN,100,0)&&CombatFxBridge.tryImpact("测试命中",NaN,NaN,100,false)&&consumed;
            check(consumed,"audited decoration is consumed before coordinate checks");
            check(!CombatFxBridge.tryShell("unknown",0,0,100,1,100)&&!CombatFxBridge.tryImpact("unknown",0,0,100,false),"unknown/MC-return effects retain old route");
            CombatFxBridge.receiveEvents({version:1,generation:1002,epoch:1,sequence:1,groundHits:3,settled:[]});
            check(CombatFxBridge.isDecorationClean(),"none ignores old feedback and builds no decoration state");
            CombatFxBridge.flush();check(CombatFxBridge.isDecorationClean(),"F6 clock/light flush keeps decoration empty");
            var hud:Object=PlayerHudService,oldHero:Function=hud.hero;var samples:Number=0;
            hud.hero=function():Object {samples++;return null;};PlayerHudService.tick();hud.hero=oldHero;
            check(samples==0,"HUD none gates before hero/sample");
            DeathEffectRenderer.renderCorpse(null,2);DeathEffectRenderer.renderRotatedCorpse(null,2);
            check(true,"corpse none returns before bitmap or coordinate work");
            check(WorkerProjectionPolicy.matchesRun({version:1,contractId:WorkerProjectionTestHost.committedReceipt.contractId,
                connectionGeneration:WorkerProjectionTestHost.committedReceipt.connectionGeneration}),"run binds actual installed contract");
            check(!WorkerProjectionPolicy.matchesRun({version:1,contractId:"00000000000000000000000000000000",connectionGeneration:1002}),"stale contract cannot start a run");
            verifyResultBinding();
        } catch(error){check(false,"none fixture: "+error);}
        finish();
    }
    private static function verifyResultBinding():Void {
        var installed:Object=WorkerProjectionTestHost.committedReceipt;
        var contract:Object={version:1,contractId:installed.contractId,connectionGeneration:installed.connectionGeneration};
        var binding:Object=WorkerProjectionPolicy.captureResultBinding(contract);
        check(org.flashNight.gesh.object.ObjectUtil.deepEquals(binding.projectionInstallReceipt,installed),"result captures the complete actual installation receipt");
        binding.projectionConsumers.ray="full";binding.projectionInstallReceipt.catalogBindings.rayStyles="changed";
        var fresh:Object=WorkerProjectionPolicy.captureResultBinding(contract);
        check(fresh.projectionConsumers.ray=="none"&&fresh.projectionInstallReceipt.catalogBindings.rayStyles==installed.catalogBindings.rayStyles,
            "result snapshot cannot mutate the installed policy or catalogs");
        check(WorkerProjectionPolicy.captureResultBinding({version:1,contractId:"00000000000000000000000000000000",connectionGeneration:installed.connectionGeneration})==undefined,
            "foreign result contract has no installation receipt");
        var oldLoader:Function=_root.加载游戏世界人物;
        var oldCommands:Object=_root.gameCommands;
        org.flashNight.arki.merc.ArenaCalibrationService.install();
        _root.加载游戏世界人物=undefined;
        var hash:String="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        org.flashNight.arki.merc.ArenaCalibrationService.handleRun({callId:987,workerId:_root.cf7ArenaWorkerId,
            sessionEpoch:_root.cf7ArenaSessionEpoch,assignmentId:"binding-assignment",attemptId:"binding-attempt",
            batchId:"binding-batch",manifestHash:hash,caseId:"binding-case",caseHash:hash,runId:"binding-run",repeatIndex:1,
            projectionContract:contract});
        _root.加载游戏世界人物=oldLoader;
        _root.gameCommands=oldCommands;
        var response:Object=WorkerProjectionTestHost.arenaResponse;
        check(response.status=="stage_failed"&&response.presentationContractId==installed.contractId,
            "actual service response retains the captured contract and real loader failure");
        check(org.flashNight.gesh.object.ObjectUtil.deepEquals(response.projectionInstallReceipt,installed)&&response.projectionConsumers.ray=="none",
            "actual service wire includes the installed receipt and consumer policy");
    }
    private static function finish():Void {
        WorkerProjectionTestHost.restore();check(!WorkerProjectionPolicy.isNone("ray"),"disconnect immediately retires consumers");
        ChainVisualBridge.resetScene();BulletVisualProbe.resetScene();RayVisualBridge.resetScene();CombatFxBridge.disconnect();
        world.removeMovieClip();_root.gameworld=saved.world;_root.帧计时器=saved.timer;_root.暂停=saved.pause;
        _root.是否视觉元素=saved.visual;_root.随机偏移=saved.random;
        trace("WorkerProjectionTest Tests Passed: "+passed);trace("WorkerProjectionTest Tests Failed: "+failed);trace(completeLine);
    }
}
