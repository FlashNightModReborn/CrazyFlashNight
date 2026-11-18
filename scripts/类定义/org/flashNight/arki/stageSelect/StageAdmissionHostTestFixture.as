import org.flashNight.arki.stageSelect.StageAdmissionBridge;
import org.flashNight.arki.stageSelect.StageAdmissionFacts;
import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.neur.Server.ServerManager;

/** TestLoader-only transport. Tests specify the decisions returned by their synthetic host.
    Binding, fresh Flash fact capture, sealing, rollback and stage start still use the real bridge. */
class org.flashNight.arki.stageSelect.StageAdmissionHostTestFixture {
    private static var saved:Object;
    private static var answers:Object;
    private static var requests:Object;
    private static var bootstrap:Object;

    public static function install():Void {
        var net:Object = ServerManager;
        var map:Object = MapDomainBridge;
        var facts:Object = StageAdmissionFacts;
        saved = {server:net.getInstance, boot:map.getBootstrap, scene:map.getSceneEpoch, ready:facts.ready};
        bootstrap = {contentDigest:"fixture-tasks", sessionToken:"fixture-map"};
        answers = {};
        requests = {};
        StageAdmissionBridge.reset();
        net.getInstance = function():Object {
            return {isSocketConnected:true, sendTaskWithCallback:StageAdmissionHostTestFixture.receive};
        };
        map.getBootstrap = function():Object { return bootstrap; };
        map.getSceneEpoch = function():Number { return 1; };
        facts.ready = function():Boolean { return true; };
    }

    public static function restore():Void {
        var net:Object = ServerManager;
        var map:Object = MapDomainBridge;
        var facts:Object = StageAdmissionFacts;
        net.getInstance = saved.server;
        map.getBootstrap = saved.boot;
        map.getSceneEpoch = saved.scene;
        facts.ready = saved.ready;
        StageAdmissionBridge.reset();
    }

    public static function decision(stage:String, nativeOpen:Boolean, canEnter:Boolean, reason:String):Void {
        answers[stage] = {nativeUnlocked:nativeOpen, unlocked:canEnter, reason:reason};
    }

    private static function receive(task:String, msg:Object, unused, cb:Function):Void {
        if (task != "stage_admission") { cb({success:false,error:"unexpected_task"}); return; }
        var result:Object = {operation:msg.operation};
        if (msg.op == "bind") {
            result.binding = "fixture-binding"; result.catalog = "fixture-catalog";
            result.taskDigest = bootstrap.contentDigest;
        } else if (msg.op == "prepare") {
            requests[msg.operation] = msg;
            result.scope = {chains:[], clears:[], tasks:{}};
            if (msg.selector.taskId != null) {
                result.scope.tasks[String(msg.selector.taskId)] = ["active","finished"];
                if (msg.kind == "dungeon_task") result.scope.assets = ["level","money","kpoints"];
            }
        } else if (msg.op == "decide") {
            var req:Object = requests[msg.operation];
            var stage:String = req.names[0];
            result.decisions = {};
            for (var i:Number=0; i<req.names.length; i++) {
                var name:String = req.names[i];
                result.decisions[name] = answers[name] || {nativeUnlocked:true,unlocked:true,reason:""};
            }
            if (req.intent == "enter") {
                if (!result.decisions[stage].unlocked) { cb({success:false,error:"locked"}); return; }
                result.state = "granted"; result.stage = stage; result.kind = req.kind;
                result.difficulty = req.difficulty; result.owner = req.owner; result.scene = req.scene;
                result.binding = msg.binding; result.catalog = msg.catalog;
            }
        } else if (msg.op == "confirm_load") {
            result.binding = msg.binding; result.state = "load_confirmed";
        } else if (msg.op != "outcome") {
            cb({success:false,error:"unexpected_operation"}); return;
        }
        cb({success:true,result:result});
    }
}
