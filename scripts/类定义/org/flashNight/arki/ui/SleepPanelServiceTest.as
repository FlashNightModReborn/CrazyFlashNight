import org.flashNight.arki.ui.SleepPanelService;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.neur.Event.EventBus;

class org.flashNight.arki.ui.SleepPanelServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] Sleep: " + message); }
    }
    private static function setup():Void {
        SleepPanelService._resetForTests();
        if (_root.__sleepTestWorld) _root.__sleepTestWorld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("__sleepTestWorld", 9201);
        _root.savePath = "sleep-test-slot"; _root.关卡标志 = "sleep-test-scene";
        _root.帧计时器 = {当前帧数:100};
        _root.__sleepRefreshes = 0;
        _root.帧计时器.添加或更新任务 = function() { _root.__sleepRefreshes++; };
        _root.server = {sendSocketMessage:function(message) { _root.__sleepWire = message; return !_root.__sleepSendFails; }};
        _root.__sleepSendFails = false;
        var weather:WeatherSystem = WeatherSystem.getInstance();
        weather.enableDayNightCycle = true; weather.pauseDayNightCycle = false;
        weather.currentTime = 9.5; weather.currentFrame = 100; weather.hourFrames = 1125;
    }
    private static function open():String {
        SleepPanelService.openPanel();
        var parser:LiteJSON = new LiteJSON();
        return parser.parse(_root.__sleepWire).initData.token;
    }
    private static function invoke(command:String, token:String, target):Object {
        var params:Object = {v:1, token:token};
        if (target !== undefined) params.targetMinutes = target;
        return SleepPanelService.execute(command, params);
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        SleepPanelService.install(); setup();
        var token:String = open();
        var state:Object = invoke("snapshot", token);
        check(state.phase == "editing" && state.currentMinutes == 570 && state.canSleep, "bed creates editable snapshot");
        check(WeatherSystem.getInstance().currentTime == 9.5 && _root.__sleepRefreshes == 0, "opening does not jump time");
        check(invoke("commit", token, -1).error == "invalid_payload", "negative minute rejected");
        check(invoke("commit", token, 1440).error == "invalid_payload", "24:00 rejected");
        check(invoke("commit", token, 12.5).error == "invalid_payload", "fraction rejected");
        check(invoke("commit", token, "390").error == "invalid_payload", "string minute rejected");
        check(invoke("commit", token, Number.NaN).error == "invalid_payload", "NaN rejected");
        check(SleepPanelService.execute("commit", {v:1, token:token, targetMinutes:390, heal:true}).error == "invalid_payload", "extra write rejected");
        check(invoke("snapshot", "sleep.fake").error == "stale_token", "unauthorized token rejected");
        check(SleepPanelService.execute("snapshot", {v:2,token:token}).error == "unsupported_version", "version rejected");
        _root.帧计时器.当前帧数 = 450;
        state = invoke("commit", token, 390);
        check(state.phase == "applied" && state.targetMinutes == 390 && state.changed, "exact minute applied");
        check(WeatherSystem.getInstance().currentTime == 6.5, "fractional hour written");
        check(WeatherSystem.getInstance().currentFrame == 450, "frame baseline synchronized");
        check(WeatherSystem.getInstance().getCurrentTime() == 6.5, "next read does not add old delta");
        check(_root.__sleepRefreshes == 1, "one weather refresh");
        invoke("commit", token, 390);
        check(_root.__sleepRefreshes == 1, "duplicate commit not replayed");
        check(invoke("commit", token, 391).error == "token_conflict", "changed draft cannot reuse token");
        check(invoke("query", token).phase == "applied", "query recovers applied receipt");
        var previous:String = token; token = open();
        check(token != previous && invoke("query", previous).phase == "applied", "reopen retains completed receipt");
        check(invoke("snapshot", previous).error == "stale_token", "old snapshot cannot claim new bed");
        previous = token; token = open();
        check(invoke("commit", previous, 0).phase == "expired", "superseded editing token cannot write");
        check(invoke("query", previous).changed == false, "expired query proves not applied");
        _root.savePath = "another-slot";
        check(invoke("commit", token, 0).phase == "expired", "save slot change invalidates session");
        setup(); token = open();
        var oldWorld:MovieClip = _root.gameworld;
        _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("__sleepTestWorld", 9201);
        check(invoke("commit", token, 0).phase == "expired", "real MovieClip same-path replacement invalidated");
        setup(); token = open();
        EventBus.getInstance().publish("SceneChanged");
        check(invoke("commit", token, 0).phase == "expired", "scene event retires bed");
        setup(); WeatherSystem.getInstance().enableDayNightCycle = false; token = open();
        check(!invoke("snapshot", token).canSleep, "disabled cycle displayed");
        check(invoke("commit", token, 0).error == "cycle_disabled", "disabled cycle cannot silently accept");
        setup(); WeatherSystem.getInstance().pauseDayNightCycle = true; token = open();
        state = invoke("commit", token, 1439);
        check(state.phase == "applied" && state.cyclePaused, "frozen cycle allows exact selection");
        check(Math.abs(WeatherSystem.getInstance().currentTime - (23 + 59 / 60)) < 0.00001, "23:59 supported");
        setup(); token = open(); state = invoke("commit", token, 0);
        check(state.phase == "applied" && WeatherSystem.getInstance().currentTime == 0, "midnight supported");
        setup(); token = open(); _root.帧计时器.当前帧数 = Number.NaN;
        check(invoke("commit", token, 360).error == "clock_unavailable", "invalid frame clock rejected");
        setup(); _root.__sleepSendFails = true;
        check(SleepPanelService.openPanel() == false, "failed opener reports failure");
        setup();
        SleepPanelService.handle("snapshot", {v:1,token:open(),callId:42});
        var wire:Object = new LiteJSON().parse(_root.__sleepWire);
        check(wire.task == "sleep_response" && wire.callId == 42, "wire correlation preserved");
        trace("SleepPanelServiceTest Tests Passed: " + passed);
        trace("SleepPanelServiceTest Tests Failed: " + failed);
    }
}