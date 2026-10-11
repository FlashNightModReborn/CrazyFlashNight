import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.map.MapFactsSampler;

/** 观察逻辑真实执行；只替换输入来源，逐字段对照冻结的 JSON 指纹语义。 */
class org.flashNight.arki.map.MapSceneObservationTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var source:Object;
    private static var originalWriter:Function;
    private static var legacyWorld:Object;
    private static var legacyStamp:String;
    private static var legacyEpoch:Number;
    private static var codec:LiteJSON;

    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] MapSceneObservationTest: " + label); }
    }
    private static function legacyScene(input:Object):Object {
        return {stageFlag:String(input.关卡标志 || ""), frameLabel:String(input._currentlabel || ""),
            entrance:String(input.场景进入位置名 || ""), mapFrame:String(input.关卡地图帧值 || ""),
            inCombat:input.当前为战斗地图 == true};
    }
    private static function legacyObserve():Number {
        var stamp:String = codec.stringifySafe(legacyScene(source));
        if (legacyWorld !== _root.gameworld || stamp != legacyStamp) {
            legacyWorld = _root.gameworld; legacyStamp = stamp; legacyEpoch++;
        }
        return legacyEpoch;
    }
    private static function compare(label:String):Void {
        var expected:Number = legacyObserve();
        check(MapDomainBridge.getSceneEpoch() === expected, label);
    }
    public static function runAllTests():Void {
        passed = failed = 0; codec = new LiteJSON();
        testNormalization();
        testObservation();
        trace("MapSceneObservationTest Tests Passed: " + passed);
        trace("MapSceneObservationTest Tests Failed: " + failed);
    }
    private static function testNormalization():Void {
        var values:Array = [undefined, null, "", 0, false, 1, true, "1", "true", "中文\"\\\n", Number.NaN];
        var fields:Array = ["关卡标志", "_currentlabel", "场景进入位置名", "关卡地图帧值", "当前为战斗地图"];
        var input:Object = {}, result:Object = {};
        for (var field:Number = 0; field < fields.length; field++) {
            for (var i:Number = 0; i < values.length; i++) {
                input[fields[field]] = values[i];
                MapFactsSampler.writeScene(input, result);
                var expected:Object = legacyScene(input);
                check(result.stageFlag === expected.stageFlag && result.frameLabel === expected.frameLabel
                    && result.entrance === expected.entrance && result.mapFrame === expected.mapFrame
                    && result.inCombat === expected.inCombat, "normalization field=" + field + " value=" + i);
            }
        }
        check(codec.stringifySafe(MapFactsSampler.scene()) === codec.stringifySafe(legacyScene(_root)),
            "public scene preserves the existing facts JSON bytes and field order");
    }
    private static function testObservation():Void {
        var bridge:Object = MapDomainBridge, sampler:Object = MapFactsSampler;
        var fields:Array = ["_installed", "_bootstrap", "_sessionToken", "_projection", "_sceneEpoch",
            "_lastWorld", "_sceneCurrent", "_scenePrevious", "_confirmedSignature", "_force", "_json", "_acceptedRevision"];
        var saved:Object = {};
        for (var i:Number = 0; i < fields.length; i++) saved[fields[i]] = bridge[fields[i]];
        var oldWorld = _root.gameworld;
        var first:MovieClip = _root.createEmptyMovieClip("__mapObserveFirst", _root.getNextHighestDepth());
        var second:MovieClip = _root.createEmptyMovieClip("__mapObserveSecond", _root.getNextHighestDepth());
        originalWriter = sampler.writeScene;
        try {
            source = {关卡标志:"甲", _currentlabel:"scene", 场景进入位置名:"front", 关卡地图帧值:1, 当前为战斗地图:false};
            sampler.writeScene = function(root:Object, result:Object):Void {
                MapSceneObservationTest.originalWriter(MapSceneObservationTest.source, result);
            };
            _root.gameworld = first;
            bridge._installed = true; bridge._bootstrap = {}; bridge._sessionToken = "scene-session";
            bridge._sceneEpoch = 0; bridge._lastWorld = null; bridge._sceneCurrent = {}; bridge._scenePrevious = null;
            bridge._projection = {before:true}; bridge._confirmedSignature = "before"; bridge._force = false;
            bridge._json = {calls:0};
            bridge._json.stringifySafe = function(value:Object):String { this.calls++; return "unused"; };
            legacyWorld = null; legacyStamp = ""; legacyEpoch = 0;
            compare("first observation advances epoch");
            check(bridge._projection == undefined && bridge._confirmedSignature === "" && bridge._force === true,
                "first scene retires projection/signature and requires fresh projection");
            var accepted:Object = {accepted:true};
            bridge._projection = accepted; bridge._acceptedRevision = 7; bridge._force = false;
            check(MapDomainBridge.getProjection() === accepted && MapDomainBridge.getProjectionToken() === "scene-session.7",
                "repeated same-scene getters preserve accepted projection and token");
            compare("repeated getters do not consume another epoch");
            var previous:Object = bridge._scenePrevious;
            source.关卡标志 = "乙";
            compare("same-frame stage flag change is observed");
            check(previous.stageFlag === "甲" && bridge._scenePrevious !== bridge._sceneCurrent,
                "scratch writes never mutate the saved previous scene");
            check(MapDomainBridge.getProjection() == undefined && MapDomainBridge.getProjectionToken() === "",
                "same-frame state change clears both projection and token");
            source._currentlabel = "another"; compare("same-frame root frame label change is observed");
            source.场景进入位置名 = "back"; compare("same-frame entrance change is observed");
            source.关卡地图帧值 = 2; compare("same-frame map frame change is observed");
            source.当前为战斗地图 = true; compare("same-frame combat flag change is observed");
            source.当前为战斗地图 = 1; compare("boolean-equivalent combat value does not advance epoch");
            source.关卡标志 = 0; compare("zero normalizes to empty string");
            source.关卡标志 = ""; compare("empty string has the same normalized scene");
            source.关卡标志 = undefined; compare("missing has the same normalized scene");
            _root.gameworld = second; compare("actual MovieClip world replacement advances epoch");
            bridge._bootstrap = undefined; bridge._sessionToken = "";
            check(MapDomainBridge.getProjection() == undefined && MapDomainBridge.getProjectionToken() === "",
                "disconnected getters cannot expose an accepted projection");
            compare("disconnected unchanged reads retain scene identity");
            source.场景进入位置名 = "during-disconnect"; compare("scene freshness still advances while disconnected");
            bridge._bootstrap = {}; bridge._sessionToken = "new-session"; bridge._projection = {after:true}; bridge._acceptedRevision = 2;
            check(MapDomainBridge.getProjectionToken() === "new-session.2", "new session token uses only its accepted revision");
            check(bridge._json.calls === 0, "scene observation never serializes JSON");
            var epoch:Number = bridge._sceneEpoch;
            bridge._installed = false; source.关卡地图帧值 = 5;
            check(MapDomainBridge.getSceneEpoch() === epoch, "uninstalled observer remains inert");
            bridge._installed = true; compare("re-enabled observer sees the pending field change");
            benchmark(false);
            benchmark(true);
        } finally {
            sampler.writeScene = originalWriter;
            for (i = 0; i < fields.length; i++) bridge[fields[i]] = saved[fields[i]];
            _root.gameworld = oldWorld;
            first.removeMovieClip(); second.removeMovieClip();
            source = null; originalWriter = null;
        }
    }
    private static function timeObservation(legacy:Boolean, changing:Boolean, count:Number):Number {
        var started:Number = getTimer();
        for (var i:Number = 0; i < count; i++) {
            if (changing) source.关卡标志 = "scene" + i;
            if (legacy) legacyObserve(); else MapDomainBridge.getSceneEpoch();
        }
        return getTimer() - started;
    }
    private static function benchmark(changing:Boolean):Void {
        timeObservation(true, changing, 20); timeObservation(false, changing, 20);
        var original:Array = [], candidate:Array = [];
        for (var round:Number = 0; round < 5; round++) {
            if ((round & 1) == 0) {
                original.push(timeObservation(true, changing, 500)); candidate.push(timeObservation(false, changing, 500));
            } else {
                candidate.push(timeObservation(false, changing, 500)); original.push(timeObservation(true, changing, 500));
            }
        }
        trace("[AS2_HOTPATH_BENCH] map_scene_" + (changing ? "changing" : "unchanged")
            + "|iterations=500|baselineMs=" + original.join(",") + "|candidateMs=" + candidate.join(","));
    }
}
