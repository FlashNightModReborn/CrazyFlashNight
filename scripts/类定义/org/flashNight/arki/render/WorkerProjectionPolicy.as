import org.flashNight.arki.render.*;
import org.flashNight.arki.merc.ArenaCalibrationService;

/** Fixed Worker consumers. Only a real root-owned EnterFrame may install the offer. */
class org.flashNight.arki.render.WorkerProjectionPolicy {
    private static var pending:Object = null;
    private static var prepared:Object = null;
    private static var committed:Object = null;
    private static var commitMessage:Object = null;
    private static var clock:MovieClip;
    private static var epoch:Number = 0;
    private static var tick:Number = 0;
    private static var attempts:Number = 0;
    private static var bytes:Number = 0;
    private static var started:Number = 0;
    private static var failed:Boolean = false;
    private static var codec:FastJSON;
    private static var consumers:Array = ["playerHud","ordinaryBullet","ray","chain","combatDecoration","sceneLighting","equipmentLighting"];
    private static var catalogs:Array = ["bulletStyles","combatFxStyles","rayStyles","sceneLights"];
    private static var policyKeys:Array = ["presentation","readinessKind","projectionConsumers","controlFrameFormat","ownership","catalogBindings","visualSeedRevision","simulationRngConsumptionRevision","sessionVisualSeed"];
    private static var commonKeys:Array = ["task","version","workerId","sessionEpoch","connectionGeneration","contractId","sequence"];

    public static function isNone(name:String):Boolean { return committed != null && committed.projectionConsumers[name] === "none"; }
    public static function isCommitted():Boolean { return committed != null && !failed; }
    public static function sessionSeed():Number { return isCommitted() ? committed.sessionVisualSeed : 0; }
    public static function retired():Void {
        pending = prepared = committed = commitMessage = null; failed = false; attempts = bytes = tick = 0;
        if (clock != null) clock.removeMovieClip(); clock = null;
    }
    public static function matchesRun(value:Object):Boolean {
        return isCommitted() && keys(value,["version","contractId","connectionGeneration"])
            && value.version === 1 && value.contractId === committed.contractId
            && value.connectionGeneration === committed.connectionGeneration;
    }
    /** Capture the actual installation once, before an asynchronous battle or stage transition. */
    public static function captureResultBinding(value:Object):Object {
        if (!matchesRun(value)) return undefined;
        var receipt:Object = copyPolicy(committed,"worker_projection_committed",2);
        receipt.policyDigest = committed.policyDigest;
        receipt.installClockKind = committed.installClockKind;
        receipt.installEpoch = committed.installEpoch;
        receipt.installTick = committed.installTick;
        var modes:Object = {};
        for (var i:Number = 0; i < consumers.length; i++) modes[consumers[i]] = committed.projectionConsumers[consumers[i]];
        return {presentationPolicy:committed.presentation, projectionConsumers:modes,
            presentationContractVersion:1, presentationContractId:committed.contractId,
            projectionInstallReceipt:receipt, readinessKind:committed.readinessKind,
            visualSeedRevision:committed.visualSeedRevision,
            simulationRngConsumptionRevision:committed.simulationRngConsumptionRevision};
    }
    public static function handle(value:Object):Void {
        if (String(_root.cf7ArenaWorker || "") != "1" || String(_root.cf7WorkerProjectionVersion || "") != "1" || failed) return;
        if (!identity(value)) return;
        if (value.task == "worker_projection_offer") {
            if (!validPolicy(value) || !keys(value,commonKeys.concat(policyKeys)) || value.sequence !== 1) { reject(value,"policy_invalid"); return; }
            if (pending != null) {
                if (!samePolicy(value,pending) || value.contractId !== pending.contractId
                    || value.connectionGeneration !== pending.connectionGeneration) { reject(value,"policy_conflict"); return; }
                if (prepared != null) send(prepared);
                return;
            }
            if (!admit(value)) { reject(value,"control_budget"); return; }
            pending = copyPolicy(value,"worker_projection_offer",1);
            started = getTimer(); tick = 0; epoch++;
            clock = _root.createEmptyMovieClip("__workerProjectionInstallClock",_root.getNextHighestDepth());
            clock.onEnterFrame = function():Void { org.flashNight.arki.render.WorkerProjectionPolicy.onRootFrame(); };
            return;
        }
        if (value.task == "worker_projection_commit") {
            if (pending == null || value.contractId !== pending.contractId || value.connectionGeneration !== pending.connectionGeneration) return;
            if (!keys(value,commonKeys.concat(policyKeys).concat(["policyDigest"])) || value.sequence !== 2
                || !samePolicy(value,pending) || !hash(value.policyDigest)) { reject(value,"commit_invalid"); return; }
            if (committed != null) {
                if (value.policyDigest === committed.policyDigest) send(committed); else reject(value,"digest_conflict");
                return;
            }
            if (prepared == null || !admit(value)) { reject(value,"commit_without_prepare"); return; }
            commitMessage = copyPolicy(value,"worker_projection_commit",2); commitMessage.policyDigest = value.policyDigest;
        }
    }
    private static function onRootFrame():Void {
        tick++;
        if (failed || pending == null) return;
        if (getTimer() - started > 10000 && committed == null) { reject(pending,"installation_timeout"); return; }
        if (prepared == null) {
            var bindings:Object = installedBindings(pending.connectionGeneration);
            if (bindings == null || !same(bindings,pending.catalogBindings,catalogs) || !clean()) return;
            prepared = copyPolicy(pending,"worker_projection_prepared",1);
            prepared.catalogBindings = bindings; prepared.accepted = true; prepared.clean = true;
            send(prepared);
            return;
        }
        if (commitMessage == null || committed != null) return;
        var actual:Object = installedBindings(pending.connectionGeneration);
        if (actual == null || !same(actual,pending.catalogBindings,catalogs) || !clean()) { reject(pending,"installation_not_clean"); return; }
        // No gameplay objects are removed. All producers were observed empty before the single assignment.
        committed = copyPolicy(commitMessage,"worker_projection_committed",2);
        committed.catalogBindings = actual; committed.policyDigest = commitMessage.policyDigest;
        committed.installClockKind = "flashRootEnterFrame"; committed.installEpoch = epoch; committed.installTick = tick;
        VisualRandom.beginWorkerSession(committed.sessionVisualSeed);
        FrameBroadcaster.retireWorkerProjectionSlots();
        // This root-owned clock is only the installation boundary, not the battle or cooldown clock.
        if (clock != null) clock.removeMovieClip(); clock = null;
        send(committed);
    }
    private static function installedBindings(generation:Number):Object {
        var bullet:String = BulletVisualProbe.installedCatalogDigest();
        var chain:String = ChainVisualBridge.installedCatalogDigest();
        var ray:String = RayVisualBridge.installedCatalogDigest(generation);
        var fx:String = CombatFxBridge.installedCatalogDigest(generation);
        var scene:String = SceneLightBridge.installedCatalogDigest();
        if (!hash(bullet) || chain !== bullet || !hash(ray) || !hash(fx) || !hash(scene)) return null;
        return {bulletStyles:bullet,combatFxStyles:fx,rayStyles:ray,sceneLights:scene};
    }
    private static function clean():Boolean {
        var ray:Object = RayVisualBridge.getStats(), chain:Object = ChainVisualBridge.getStats();
        return ArenaCalibrationService.isProjectionInstallClean() && BulletVisualProbe.trackedCount() == 0
            && ray.active == 0 && ray.configs == 0 && ray.queued == 0
            && chain.groups == 0 && chain.reserved == 0 && chain.births == 0 && chain.deaths == 0
            && CombatFxBridge.isDecorationClean() && !FrameBroadcaster.hasPlayerHudPending();
    }
    private static function validPolicy(value:Object):Boolean {
        if (value.presentation !== "full" || value.readinessKind !== "arena.presented.v1"
            || value.controlFrameFormat !== "f-visual-v1" || value.ownership !== "as2-gameplay-native-model-v1"
            || value.visualSeedRevision !== "visual-event-v1" || value.simulationRngConsumptionRevision !== "legacy-global-consume-v1"
            || !integer(value.sessionVisualSeed,1,2147483646) || !keys(value.projectionConsumers,consumers)
            || !keys(value.catalogBindings,catalogs)) return false;
        for (var i:Number=0;i<consumers.length;i++) {
            var name:String=consumers[i], mode:String=value.projectionConsumers[name];
            if (mode !== "full" && mode !== "none") return false;
        }
        if (value.projectionConsumers.sceneLighting !== "full" || value.projectionConsumers.equipmentLighting !== "full") return false;
        for (i=0;i<catalogs.length;i++) if (!hash(value.catalogBindings[catalogs[i]])) return false;
        return true;
    }
    private static function identity(value:Object):Boolean {
        return value != null && value.version === 1 && value.workerId === _root.cf7ArenaWorkerId
            && value.sessionEpoch === _root.cf7ArenaSessionEpoch && integer(value.connectionGeneration,1,1000000000)
            && hex(value.contractId,32);
    }
    private static function copyPolicy(value:Object,task:String,sequence:Number):Object {
        var result:Object={task:task,version:1,workerId:value.workerId,sessionEpoch:value.sessionEpoch,
            connectionGeneration:value.connectionGeneration,contractId:value.contractId,sequence:sequence};
        for (var i:Number=0;i<policyKeys.length;i++) {
            var name:String=policyKeys[i];
            if (name == "projectionConsumers" || name == "catalogBindings") {
                var names:Array=name == "projectionConsumers" ? consumers : catalogs;
                var part:Object={};for (var n:Number=0;n<names.length;n++) part[names[n]]=value[name][names[n]];
                result[name]=part;
            } else result[name]=value[name];
        }
        return result;
    }
    private static function samePolicy(a:Object,b:Object):Boolean {
        for (var i:Number=0;i<policyKeys.length;i++) {
            var name:String=policyKeys[i];
            if (name == "projectionConsumers" || name == "catalogBindings") {
                if (!same(a[name],b[name],name == "projectionConsumers" ? consumers : catalogs)) return false;
            } else if (a[name] !== b[name]) return false;
        }
        return true;
    }
    private static function same(a:Object,b:Object,names:Array):Boolean {
        if (!keys(a,names) || !keys(b,names)) return false;
        for (var i:Number=0;i<names.length;i++) if (a[names[i]] !== b[names[i]]) return false;
        return true;
    }
    private static function keys(value:Object,names:Array):Boolean {
        if (value == null || value instanceof Array || typeof value.hasOwnProperty != "function") return false;
        var count:Number=0;
        for (var key:String in value) {
            if (!value.hasOwnProperty(key)) continue;
            var known:Boolean=false;for (var i:Number=0;i<names.length;i++) if(key===names[i]){known=true;break;}
            if(!known)return false;count++;
        }
        if(count!=names.length)return false;
        for(var n:Number=0;n<names.length;n++)if(!value.hasOwnProperty(names[n]))return false;
        return true;
    }
    private static function integer(value,min:Number,max:Number):Boolean { return typeof value=="number" && isFinite(value) && value>=min && value<=max && value==Math.floor(value); }
    private static function hex(value,size:Number):Boolean {
        if(typeof value!="string" || value.length!=size)return false;
        for(var i:Number=0;i<size;i++){var c:Number=value.charCodeAt(i);if(!((c>=48&&c<=57)||(c>=97&&c<=102)))return false;}
        return true;
    }
    private static function hash(value):Boolean { return typeof value=="string" && value.substr(0,7)=="sha256:" && hex(value.substr(7),64); }
    public static function validCatalogDigest(value):Boolean { return hex(value,64); }
    /** Existing v1 capability catalogs use uppercase hex; the new contract uses canonical lowercase. */
    public static function adoptedCatalogDigest(value):String {
        if(typeof value!="string")return "";
        var canonical:String=value.toLowerCase();return hex(canonical,64)?"sha256:"+canonical:"";
    }
    private static function admit(value:Object):Boolean {
        if(codec==null)codec=new FastJSON();var wire:String=codec.stringify(value);
        // Policy strings are restricted ASCII. UTF-8 bytes therefore equal this bounded wire length.
        if(++attempts>32 || wire.length>32768 || bytes+wire.length>65536)return false;
        bytes+=wire.length;return true;
    }
    private static function send(value:Object):Void { if(codec==null)codec=new FastJSON();_root.server.sendSocketMessage(codec.stringify(value)); }
    private static function reject(value:Object,code:String):Void {
        failed=true;committed=null;
        send({task:"worker_projection_rejected",version:1,workerId:value.workerId,sessionEpoch:value.sessionEpoch,
            connectionGeneration:value.connectionGeneration,contractId:value.contractId,sequence:value.sequence,error:code});
        if(clock!=null)clock.removeMovieClip();clock=null;
    }
}
