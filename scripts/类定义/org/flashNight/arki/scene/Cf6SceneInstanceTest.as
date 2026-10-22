import org.flashNight.arki.scene.SceneManager;
import org.flashNight.arki.scene.Cf6SceneInstanceProbe;

/** Real attachMovie constructor timing; no XFL edits, async waits, business writes or NPC RPC. */
class org.flashNight.arki.scene.Cf6SceneInstanceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,label:String):Void {
        if (value) passed++; else {failed++;trace("[FAIL] Cf6SceneInstance: "+label);}
    }
    private static function definition():Object {
        return {Identifier:"TestProbeLeaf",x:240.25,y:350.5,InitializeParametersBeforeAttach:true,
            Parameters:{商店检索名:"cf6.fixture.shop",技能检索名:"cf6.fixture.skills",任务名:"cf6.fixture.tasks",
                可学的技能:{first:"口才",second:"铁匠"},默认对话:[]}};
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var sceneClass:Object=org.flashNight.arki.scene.SceneManager;
        var depthClass:Object=org.flashNight.gesh.depth.DepthManager;
        var oldScene:Object=sceneClass.instance,oldDepth:Object=depthClass.instance;
        var hadWorld:Boolean=_root.hasOwnProperty("gameworld");
        var oldWorld:MovieClip=_root.gameworld;
        var oldConstructs:Number=Cf6SceneInstanceProbe.constructions;
        var manager:SceneManager=SceneManager.getInstance();
        var oldManagerWorld:MovieClip=manager.gameworld;
        var fixture:MovieClip=_root.createEmptyMovieClip("__cf6SceneInstanceFixture",_root.getNextHighestDepth());
        var depthSpy:Object={calls:0,updateDepth:function(mc:MovieClip,y:Number):Boolean {this.calls++;this.lastY=y;return true;}};
        var registered:Boolean=false;
        try {
            manager.gameworld=fixture;_root.gameworld=fixture;depthClass.instance=depthSpy;
            // TestProbeLeaf is an existing exported TestLoader symbol with no class registration in its source.
            var before:MovieClip=fixture.attachMovie("TestProbeLeaf","beforeRegistration",fixture.getNextHighestDepth());
            check(before!=undefined && before._parent===fixture,"existing exported TestProbeLeaf attaches before registration");
            before.removeMovieClip();
            Cf6SceneInstanceProbe.constructions=0;
            registered=Object.registerClass("TestProbeLeaf",org.flashNight.arki.scene.Cf6SceneInstanceProbe);
            check(registered,"real test linkage accepts registered constructor");
            var info:Object=definition();
            var first:MovieClip=manager.addInstance(info,"optIn");
            var seen:Object=first.atConstruction;
            check(first instanceof Cf6SceneInstanceProbe && Cf6SceneInstanceProbe.constructions==1,"real SceneManager attachment runs probe constructor once");
            check(seen.shop=="cf6.fixture.shop" && seen.skillSource=="cf6.fixture.skills" && seen.taskSource=="cf6.fixture.tasks",
                "opt-in constructor sees isolated shop, skill and task identities");
            check(seen.skills.first=="口才" && seen.skills.second=="铁匠","opt-in constructor sees authored skill list");
            check(seen.dialogue instanceof Array && seen.dialogue.length==0,"opt-in constructor sees empty dialogue before an NPC could request defaults");
            check(seen.x==240.25 && seen.y==350.5,"opt-in constructor receives world coordinates at its first instruction");
            check(first._x==240.25 && first._y==350.5 && first.商店检索名=="cf6.fixture.shop","normal post-attach placement and parameter projection retained");
            check(seen.skills!==info.Parameters.可学的技能 && seen.dialogue!==info.Parameters.默认对话,
                "pre-attach nested parameters are detached from the authored source");
            check(first.可学的技能!==info.Parameters.可学的技能 && first.默认对话!==info.Parameters.默认对话,
                "post-attach nested parameters are also detached from the authored source");
            first.可学的技能.first="changed";first.默认对话.push("changed");
            check(info.Parameters.可学的技能.first=="口才" && info.Parameters.默认对话.length==0
                    && info.x==240.25 && info.y==350.5,"mutating an attached instance cannot modify source parameters or coordinates");
            check(!info.Parameters.hasOwnProperty("__dictUID") && !info.Parameters.可学的技能.hasOwnProperty("__dictUID")
                    && !info.Parameters.默认对话.hasOwnProperty("__dictUID"),"opt-in does not stamp hidden clone IDs onto authored parameters");
            var legacyInfo:Object=definition();delete legacyInfo.InitializeParametersBeforeAttach;
            var legacy:MovieClip=manager.addInstance(legacyInfo,"legacy");
            check(legacy.atConstruction.shop===undefined && legacy.atConstruction.skills===undefined && legacy.atConstruction.dialogue===undefined,
                "no flag retains legacy constructor visibility");
            check(legacy.atConstruction.x==0 && legacy.atConstruction.y==0 && legacy._x==240.25 && legacy._y==350.5,
                "no flag retains legacy post-construction coordinate assignment");
            check(legacy.商店检索名=="cf6.fixture.shop" && legacy.可学的技能.first=="口才",
                "no flag still receives the original post-attach parameters");
            var falseInfo:Object=definition();falseInfo.InitializeParametersBeforeAttach=false;
            var falseFlag:MovieClip=manager.addInstance(falseInfo,"falseFlag");
            check(falseFlag.atConstruction.shop===undefined && falseFlag.商店检索名=="cf6.fixture.shop","explicit false does not opt in");
            var stringInfo:Object=definition();stringInfo.InitializeParametersBeforeAttach="true";
            var stringFlag:MovieClip=manager.addInstance(stringInfo,"stringFlag");
            check(stringFlag.atConstruction.shop===undefined && stringFlag.商店检索名=="cf6.fixture.shop","string true does not opt in to the strict boolean gate");
            var coordinateInfo:Object=definition();coordinateInfo.Parameters._x=999;coordinateInfo.Parameters._y=888;
            var coordinate:MovieClip=manager.addInstance(coordinateInfo,"coordinateAuthority");
            check(coordinate.atConstruction.x==240.25 && coordinate.atConstruction.y==350.5,
                "map coordinates override parameter aliases specifically for constructor initialization");
            check(coordinateInfo.Parameters._x==999 && coordinateInfo.Parameters._y==888 && coordinateInfo.x==240.25,
                "coordinate precedence does not rewrite authored parameter aliases");
            check(depthSpy.calls==5 && Cf6SceneInstanceProbe.constructions==5,"all five real attachments still use the existing depth hook exactly once");
            Object.registerClass("TestProbeLeaf",null);registered=false;
            var after:MovieClip=fixture.attachMovie("TestProbeLeaf","afterUnregister",fixture.getNextHighestDepth());
            check(after!=undefined && !(after instanceof Cf6SceneInstanceProbe) && after.atConstruction===undefined
                    && Cf6SceneInstanceProbe.constructions==5,"unregister restores the original unbound test linkage");
        } finally {
            if (registered) Object.registerClass("TestProbeLeaf",null);
            fixture.removeMovieClip();
            manager.gameworld=oldManagerWorld;sceneClass.instance=oldScene;depthClass.instance=oldDepth;
            if (hadWorld) _root.gameworld=oldWorld;else delete _root.gameworld;
            Cf6SceneInstanceProbe.constructions=oldConstructs;
        }
        check(sceneClass.instance===oldScene && manager.gameworld===oldManagerWorld && depthClass.instance===oldDepth
                && (hadWorld ? _root.gameworld===oldWorld : !_root.hasOwnProperty("gameworld")),
            "fixture restores scene singleton, scene world, depth manager and root world presence");
        trace("Cf6SceneInstanceTest Tests Passed: "+passed);
        trace("Cf6SceneInstanceTest Tests Failed: "+failed);
    }
}
