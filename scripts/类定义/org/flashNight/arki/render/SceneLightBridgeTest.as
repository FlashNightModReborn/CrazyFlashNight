import org.flashNight.arki.render.SceneLightBridge;

class org.flashNight.arki.render.SceneLightBridgeTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++; else { failed++; trace("[TEST_FAIL] SceneLightBridgeTest: " + name); }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var oldWorld:MovieClip = _root.gameworld;
        var oldInfraSys:Object = _root.基建系统;
        var testWorld:MovieClip = _root.createEmptyMovieClip("__sceneLightSuiteWorld",_root.getNextHighestDepth());
        _root.gameworld = testWorld;
        SceneLightBridge.resetScene();
        var caps:Object = {sceneLightsVersion:1}; caps["native"] = true;
        SceneLightBridge.configureCaps(caps);
        SceneLightBridge.configure([{Key:"fixed",X:10,Y:20,Radius:100}],[{Key:"fixed",Energy:0.4}],"test");
        var snap:Object = SceneLightBridge.snapshot();
        check(snap.definitions.length == 1,"override merges stable key");
        check(snap.definitions[0].Radius == 100,"override preserves base field");
        check(snap.definitions[0].Energy == 0.4,"override applies per scene");
        check(snap.poses[0][1] == 10 && snap.poses[0][2] == 20,"world coordinate pose");
        SceneLightBridge.sent();
        check(SceneLightBridge.snapshot() == null,"static definition sent once");
        check(SceneLightBridge.flush() != null,"first pose snapshot");
        check(SceneLightBridge.flush() == null,"static pose not resent");
        check(SceneLightBridge.setEnabled("fixed",false),"explicit state API");
        var wire:String = SceneLightBridge.flush();
        check(wire.split(";")[1].split(",")[6] == "0","state off projected");
        check(!SceneLightBridge.setEnabled("missing",true),"missing state key rejected");
        SceneLightBridge.resetScene();
        var lamp:MovieClip = testWorld.createEmptyMovieClip("lamp",1);
        lamp._x = 100; lamp._y = 120;
        SceneLightBridge.track(lamp,"lamp");
        SceneLightBridge.configure([{Key:"bound",AttachTo:"lamp",OffsetX:10,OffsetY:20}],null,"bound");
        snap = SceneLightBridge.snapshot();
        check(snap.poses[0][1] == 110 && snap.poses[0][2] == 140,"bound local offset");
        SceneLightBridge.flush();
        lamp._x = 140; wire = SceneLightBridge.flush();
        check(Number(wire.split(";")[1].split(",")[1]) == 150,"bound follows movement");
        lamp._visible = false; wire = SceneLightBridge.flush();
        check(wire.split(";")[1].split(",")[6] == "0","hidden source turns off");
        lamp._visible = true; lamp._alpha = 0; SceneLightBridge.flush();
        lamp._alpha = 100; wire = SceneLightBridge.flush();
        check(wire.split(";")[1].split(",")[6] == "1","visible source restores");
        lamp.liveLamp = false;
        SceneLightBridge.configure([{Key:"bound",AttachTo:"lamp",StatePath:"liveLamp"}],null,"state");
        snap = SceneLightBridge.snapshot();check(snap.poses[0][6] == 0,"boolean state path");
        lamp.liveLamp = true; wire = SceneLightBridge.flush();check(wire.split(";")[1].split(",")[6] == "1","state path update");
        SceneLightBridge.configure([{Key:"bound",AttachTo:"lamp",FollowRotation:true,FollowScale:true}],null,"mirror");
        lamp._xscale = -200; lamp._yscale = 200; lamp._rotation = 90;
        snap = SceneLightBridge.snapshot();
        check(Math.abs(snap.poses[0][3]) < 0.05 && snap.poses[0][4] < -0.95,"mirrored rotated basis");
        check(Math.abs(snap.poses[0][5]-2) < 0.05 && snap.poses[0][7] == -1,"scale and handedness");
        SceneLightBridge.configure([{Key:"bound",AttachTo:"lamp",FollowScale:false}],null,"world-radius");
        snap = SceneLightBridge.snapshot();check(snap.poses[0][5] == 1,"world size independent of art scale");
        SceneLightBridge.flush();testWorld._x = 80; testWorld._y = -40; testWorld._xscale = testWorld._yscale = 125;
        check(SceneLightBridge.flush() == null,"camera changes do not dirty fixed source");
        lamp.removeMovieClip();var replacement:MovieClip = testWorld.createEmptyMovieClip("lamp",1);
        wire = SceneLightBridge.flush();check(wire.split(";")[1].split(",")[6] == "0","same path replacement does not revive old binding");
        SceneLightBridge.track(replacement,"lamp");wire = SceneLightBridge.flush();
        check(wire.split(";")[1].split(",")[6] == "1","explicit new binding restores source");
        var second:MovieClip = testWorld.createEmptyMovieClip("secondLamp",2);
        second._x = 40; second._y = 60;
        SceneLightBridge.track(second,"second");
        SceneLightBridge.configure([{Key:"first",AttachTo:"lamp"},{Key:"second",AttachTo:"second"}],null,"row-cache");
        wire = SceneLightBridge.flush();
        var oldSecond:String = wire.split(";")[2];
        var frozen:Array = SceneLightBridge.snapshot().poses[1];
        replacement._x = 15; wire = SceneLightBridge.flush();
        check(wire.split(";").length == 3,"one changed attachment still sends the original row set");
        check(wire.split(";")[2] === oldSecond,"unchanged row keeps exact original encoding");
        check(SceneLightBridge.flush() == null,"unchanged attachments do not resend");
        second._y = 80; wire = SceneLightBridge.flush();
        check(Number(wire.split(";")[2].split(",")[2]) == 80,"second attachment invalidates its own row");
        check(frozen[2] == 60,"cached encoding does not mutate an earlier full pose");
        SceneLightBridge.track(replacement,"second");
        SceneLightBridge.configure([{Key:"bound",AttachTo:"second"},{Key:"healthy",X:10,Y:20}],null,"anchor-isolation");
        snap = SceneLightBridge.snapshot();
        check(snap.poses[0][6] == 0 && snap.poses[1][6] == 1,"ambiguous anchor hides only its bound light");
        SceneLightBridge.configure([{Key:"invalid",FrameCurve:"bad"},{Key:"dup"},{Key:"dup"},{Key:"healthy"}],null,"author-isolation");
        snap = SceneLightBridge.snapshot();
        check(snap.definitions.length == 1 && snap.definitions[0].Key == "healthy","invalid curve and duplicate key leave sibling lamp live");
        SceneLightBridge.configure([{Key:"gate-example",X:10,Y:20}],null,"non-base");
        check(!SceneLightBridge.hasActiveBaseLighting() && SceneLightBridge.baseCharacterInfoMinOpacity() == 0,"a key prefix cannot turn unrelated scenery into a base");
        var baseRig:MovieClip = testWorld.createEmptyMovieClip("基地灯光",3);
        var glowLayer:MovieClip = baseRig.createEmptyMovieClip("发光层",1);
        var beaconLayer:MovieClip = baseRig.createEmptyMovieClip("信标层",2);
        SceneLightBridge.configure([{Key:"gate-door-sconce-l",BasePowerTier:0,X:135,Y:275},{Key:"roof-antenna-beacon",BasePowerTier:0,BaseBeacon:true,X:1445,Y:68}],null,"base-ambient",true);
        SceneLightBridge.syncAmbientLight(7,testWorld);
        snap = SceneLightBridge.snapshot();
        check(snap.poses[0][6] == 0 && Math.abs(snap.poses[1][6]-0.35) < 0.02 && glowLayer._visible == false && Math.abs(beaconLayer._alpha-45) < 1,"daytime turns off base illumination and dims beacon");
        SceneLightBridge.sent(); SceneLightBridge.flush();
        SceneLightBridge.syncAmbientLight(4,testWorld);
        wire = SceneLightBridge.flush();
        check(Math.abs(Number(wire.split(";")[1].split(",")[6])-0.55) < 0.02 && wire.split(";")[2].split(",")[6] == "1" && glowLayer._visible == true && Math.abs(glowLayer._alpha-55) < 1 && Math.abs(beaconLayer._alpha-100) < 1,"dusk warms up base lights to half power");
        SceneLightBridge.syncAmbientLight(1,testWorld);
        wire = SceneLightBridge.flush();
        check(wire.split(";")[1].split(",")[6] == "1" && glowLayer._visible == true && Math.abs(glowLayer._alpha-100) < 1,"night restores full base lighting power");
        baseRig.removeMovieClip();
        delete testWorld.基地灯光;
        var deadbody:MovieClip = testWorld.createEmptyMovieClip("deadbody",4);
        _global.ASSetPropFlags(testWorld,["deadbody"],1,false);
        var mockDict:Object = {};
        mockDict["基地供电与照明"] = {};
        _root.基建系统 = {dict:mockDict, infrastructure:{}};
        SceneLightBridge.configure([
            {Key:"gate-door-sconce-l",BasePowerTier:0,X:155,Y:380},
            {Key:"garage-workbay-se-lamp",BasePowerTier:0,X:1135,Y:585},
            {Key:"garage-truss-flood-w",BasePowerTier:1,X:330,Y:145},
            {Key:"roof-helipad-flood-l",BasePowerTier:2,X:165,Y:235},
            {Key:"renamed-emblem",BasePowerTier:3,X:615,Y:365}
        ],null,"base-infra-tiers",true);
        SceneLightBridge.syncAmbientLight(1,testWorld);
        snap = SceneLightBridge.snapshot();
        check(_root.基建系统.infrastructure["基地供电与照明"] == undefined && snap.poses[0][6] == 0.84375 && snap.poses[1][6] == 0.84375 && snap.poses[2][6] == 0 && snap.poses[3][6] == 0 && snap.poses[4][6] == 0,"Lv.0 projection never discovers infrastructure; full walkable emergency and stall lamps active while higher-tier floods remain locked");
        check(testWorld.基地灯光 == undefined && deadbody.__baseLightRig == undefined && Math.abs(SceneLightBridge.effectiveAmbientLight(1)-1.0) < 0.01 && SceneLightBridge.baseCharacterInfoMinOpacity() == 100,"Lv.0 creates no procedural vector stickers and preserves deep night ambient with 100% readable nameplates");
        _root.基建系统.infrastructure["基地供电与照明"] = 1;
        SceneLightBridge.syncAmbientLight(1,testWorld);
        snap = SceneLightBridge.snapshot();
        check(snap.poses[0][6] == 0.90625 && snap.poses[1][6] == 0.90625 && snap.poses[2][6] == 0.875 && snap.poses[3][6] == 0 && snap.poses[4][6] == 0 && Math.abs(SceneLightBridge.effectiveAmbientLight(1)-1.15) < 0.01 && SceneLightBridge.baseCharacterInfoMinOpacity() == 100,"Lv.1 unlocks industrial wall-wash and truss workbay floods while keeping watchtower searchlights locked");
        _root.基建系统.infrastructure["基地供电与照明"] = 2;
        SceneLightBridge.syncAmbientLight(1,testWorld);
        snap = SceneLightBridge.snapshot();
        check(snap.poses[0][6] == 0.953125 && snap.poses[1][6] == 0.953125 && snap.poses[2][6] == 0.953125 && snap.poses[3][6] == 0.90625 && snap.poses[4][6] == 0 && Math.abs(SceneLightBridge.effectiveAmbientLight(1)-1.3) < 0.01 && SceneLightBridge.baseCharacterInfoMinOpacity() == 100,"Lv.2 unlocks watchtower diagonal searchlights and central high-bay floods");
        _root.基建系统.infrastructure["基地供电与照明"] = 3;
        SceneLightBridge.syncAmbientLight(1,testWorld);
        snap = SceneLightBridge.snapshot();
        check(snap.poses[0][6] == 1 && snap.poses[1][6] == 1 && snap.poses[2][6] == 1 && snap.poses[3][6] == 1 && snap.poses[4][6] == 1 && Math.abs(SceneLightBridge.effectiveAmbientLight(1)-1.45) < 0.01 && SceneLightBridge.baseCharacterInfoMinOpacity() == 100,"Lv.3 unlocks BPK cyan underglow and perimeter accents at full optical power");
        caps["native"] = false; caps.sceneLightsVersion = 0;
        SceneLightBridge.configureCaps(caps);
        check(SceneLightBridge.flush() == null && SceneLightBridge.snapshot() == null,"capability revocation");
        SceneLightBridge.resetScene();
        _root.基建系统 = oldInfraSys;
        _root.gameworld = oldWorld; testWorld.removeMovieClip();
        trace("SceneLightBridgeTest Tests Passed: " + passed);
        trace("SceneLightBridgeTest Tests Failed: " + failed);
    }
}
