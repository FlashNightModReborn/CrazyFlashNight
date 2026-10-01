import org.flashNight.arki.render.SceneLightBridge;

class org.flashNight.arki.render.SceneLightAssetTest {
    private static var oldWorld:MovieClip;
    private static var world:MovieClip;
    private static var ticker:MovieClip;
    private static var token:String;
    private static var frames:Number;
    private static var definitions:Array;
    public static function setRunId(runId:String):Void { token = runId; }
    public static function runAllTests():Void {
        frames = 0; oldWorld = _root.gameworld;
        world = _root.createEmptyMovieClip("__sceneAssetWorld",_root.getNextHighestDepth());
        _root.gameworld = world; SceneLightBridge.resetScene();
        var caps:Object = {sceneLightsVersion:1}; caps["native"] = true; SceneLightBridge.configureCaps(caps);
        definitions = [];
        var files:Array = ["灯光","昏暗街头灯光","演唱会灯"];
        for (var i:Number = 0; i < files.length; i++) {
            var key:String = "external" + i;
            var holder:MovieClip = world.createEmptyMovieClip(key,i+1); holder._x = 200+i*200; holder._y = 300;
            SceneLightBridge.loadSource(holder,"../flashswf/backgrounds/elements/"+files[i]+".swf",key);
            definitions.push({Key:key,AttachTo:key,OffsetX:20,OffsetY:-20});
        }
        SceneLightBridge.configure(definitions,null,"actual-swf-assets");
        ticker = _root.createEmptyMovieClip("__sceneAssetTicker",_root.getNextHighestDepth());
        ticker.onEnterFrame = org.flashNight.arki.render.SceneLightAssetTest.tick;
    }
    private static function tick():Void {
        frames++;
        var snapshot:Object = SceneLightBridge.snapshot();
        if (snapshot != null && snapshot.poses.length == 3
            && snapshot.poses[0][6] == 1 && snapshot.poses[1][6] == 1 && snapshot.poses[2][6] == 1) {
            var passed:Number = 0;
            for (var i:Number = 0; i < 3; i++) {
                var holder:MovieClip = world["external"+i];
                if (holder.getBytesLoaded() == holder.getBytesTotal() && holder.getBytesTotal()>0) passed++;
                if (Math.abs(snapshot.poses[i][1]-(220+i*200))<0.1 && Math.abs(snapshot.poses[i][2]-280)<0.1) passed++;
            }
            SceneLightBridge.flush();world._x = -33.4; world._y = 71.3;world._xscale = world._yscale = 137.5;
            if (SceneLightBridge.flush() == null) passed++;
            finish(passed,7-passed); return;
        }
        if (frames > 150) finish(0,7);
    }
    private static function finish(passed:Number, failed:Number):Void {
        trace("SceneLightAssetTest Tests Passed: " + passed);
        trace("SceneLightAssetTest Tests Failed: " + failed);
        trace("FocusedTestRunId scene-lighting Complete: " + token);
        SceneLightBridge.resetScene(); _root.gameworld = oldWorld; world.removeMovieClip(); ticker.removeMovieClip();
    }
}
