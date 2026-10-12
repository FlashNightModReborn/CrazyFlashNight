import org.flashNight.arki.render.*;
/** Controlled TestLoader peer. Catalog digests are fixture identities; it never claims a live Host receipt. */
class org.flashNight.arki.render.WorkerProjectionTestHost {
    private static var saved:Object = null;
    private static var session:Number = 0;
    private static var callback:Function;
    private static var offer:Object;
    private static var done:Boolean;
    public static var preparedReceipt:Object;
    public static var committedReceipt:Object;
    public static var arenaResponse:Object;
    private static var codec:FastJSON;
    public static function install(none:Boolean,ready:Function):Void {
        if(saved==null)saved={server:_root.server,worker:_root.cf7ArenaWorker,id:_root.cf7ArenaWorkerId,
            session:_root.cf7ArenaSessionEpoch,version:_root.cf7WorkerProjectionVersion};
        WorkerProjectionPolicy.retired();FrameBroadcaster.reset();session++;done=false;callback=ready;
        _root.cf7ArenaWorker="1";_root.cf7ArenaWorkerId="worker-fixture";
        _root.cf7ArenaSessionEpoch="worker-fixture-"+session;_root.cf7WorkerProjectionVersion="1";
        codec=new FastJSON();preparedReceipt=committedReceipt=arenaResponse=null;
        _root.server={isSocketConnected:true,sendServerMessage:function(value:String):Void {},
            sendSocketMessage:function(wire:String):Boolean { return WorkerProjectionTestHost.receive(wire); }};
        var digest:String="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        var generation:Number=1000+session;
        var styles:Array=[{ordinaryLinkage:"ordinary",gunChainUnitLinkage:"单元体-普通子弹"}];
        var prefixes:Array=["横向联弹","纵向联弹"];
        BulletVisualProbe.resetScene();BulletVisualProbe.configure({version:1,mode:"native",digest:digest,
            maxOrdinary:1024,maxTotal:16384,styles:styles,gunChainPrefixes:prefixes});
        ChainVisualBridge.resetScene();ChainVisualBridge.configure({version:1,mode:"native",digest:digest,
            maxUnits:15360,styles:styles,gunChainPrefixes:prefixes});
        RayVisualBridge.resetScene();RayVisualBridge.disconnect();
        var rayNames:Array=RayStyleRegistry.getStyleNames(),rayStyles:Array=[];
        for(var i:Number=0;i<rayNames.length;i++)rayStyles.push({index:i,id:rayNames[i]});
        RayVisualBridge.configure({version:1,generation:generation,native:true,digest:digest,styles:rayStyles,
            maxArcs:1024,drawLimit:4096,configLimit:1024,channelVersion:1,lightingVersion:1});
        CombatFxBridge.disconnect();CombatFxBridge.configure({version:1,generation:generation,native:true,digest:digest,
            sceneLightsDigest:digest,equipmentLights:2,equipmentRadialLights:1,sceneLightsVersion:1,
            styles:[{index:0,linkage:"测试弹壳",kind:"casing"},{index:1,linkage:"测试枪火",kind:"muzzle"},{index:2,linkage:"测试命中",kind:"impact"}]});
        var consumers:Object={playerHud:none?"none":"full",ordinaryBullet:none?"none":"full",ray:none?"none":"full",
            chain:none?"none":"full",combatDecoration:none?"none":"full",sceneLighting:"full",equipmentLighting:"full"};
        var hash:String="sha256:"+digest.toLowerCase();
        var token:String="000000000000000000000000"+session.toString(16);while(token.length<32)token="0"+token;
        token=token.substr(token.length-32);
        offer={task:"worker_projection_offer",version:1,workerId:_root.cf7ArenaWorkerId,sessionEpoch:_root.cf7ArenaSessionEpoch,
            connectionGeneration:generation,contractId:token,sequence:1,presentation:"full",readinessKind:"arena.presented.v1",
            projectionConsumers:consumers,controlFrameFormat:"f-visual-v1",ownership:"as2-gameplay-native-model-v1",
            catalogBindings:{bulletStyles:hash,combatFxStyles:hash,rayStyles:hash,sceneLights:hash},
            visualSeedRevision:"visual-event-v1",simulationRngConsumptionRevision:"legacy-global-consume-v1",sessionVisualSeed:104729};
        WorkerProjectionPolicy.handle(offer);
    }
    private static function receive(wire:String):Boolean {
        if(wire.substr(0,1)!="{")return true;
        var message:Object=codec.parse(wire);
        if(message.task=="arena_calibration_response") {
            arenaResponse=message;
        } else if(message.task=="worker_projection_prepared") {
            preparedReceipt=message;
            var commit:Object=codec.parse(codec.stringify(offer));commit.task="worker_projection_commit";commit.sequence=2;
            commit.policyDigest="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
            WorkerProjectionPolicy.handle(commit);
        } else if(message.task=="worker_projection_committed" && !done) {
            committedReceipt=message;done=true;
            var f:Function=callback;callback=null;f();
        } else if(message.task=="worker_projection_rejected") {
            trace("[TEST_FAIL] WorkerProjectionTestHost: "+message.error);
        }
        return true;
    }
    public static function restore():Void {
        WorkerProjectionPolicy.retired();callback=null;
        if(saved!=null) {
            _root.server=saved.server;_root.cf7ArenaWorker=saved.worker;_root.cf7ArenaWorkerId=saved.id;
            _root.cf7ArenaSessionEpoch=saved.session;_root.cf7WorkerProjectionVersion=saved.version;saved=null;
        }
    }
}
