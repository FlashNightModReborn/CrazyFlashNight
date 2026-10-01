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
        caps["native"] = false; caps.sceneLightsVersion = 0;
        SceneLightBridge.configureCaps(caps);
        check(SceneLightBridge.flush() == null && SceneLightBridge.snapshot() == null,"capability revocation");
        SceneLightBridge.resetScene();
        _root.gameworld = oldWorld; testWorld.removeMovieClip();
        trace("SceneLightBridgeTest Tests Passed: " + passed);
        trace("SceneLightBridgeTest Tests Failed: " + failed);
    }
}
