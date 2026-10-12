import org.flashNight.arki.ui.EggSelectPanelService;

/** U7 彩蛋地图选关的 focused 套件：彩蛋/主线进度门、固定难度与旧进关链语义。 */
class org.flashNight.arki.ui.EggSelectPanelServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] EggSelect: " + message); }
    }
    private static function setup():Void {
        _root.主线任务进度 = 0;
        _root.task_chains_progress = {彩蛋:0};
        _root.场景转换中 = false;
        _root.当前为战斗地图 = false;
        _root.斗兽标定模式 = false;
        delete _root._saveExt;
        _root.StageInfoDict = {
            密林深处:{Type:"无限过图", Name:"密林深处"},
            机器游荡区:{Type:"无限过图", Name:"机器游荡区"},
            密林中央:{Type:"无限过图", Name:"密林中央"}
        };
        _root.__eggWire = null;
        _root.server = {sendSocketMessage:function(value):Boolean { _root.__eggWire = value; return true; }};
        _root.__configured = [];
        _root.配置关卡属性 = function(name):Void {
            _root.__configured.push(name);
            this.当前关卡名 = name;
            this.关卡路径 = "data/stages/副本任务/" + name + ".xml";
        };
        _root.__entered = [];
        _root.__enterResult = true;
        _root.选关界面进入关卡 = function(difficulty):Boolean {
            _root.__entered.push({stage:String(this.当前关卡名), difficulty:difficulty});
            return _root.__enterResult;
        };
    }
    private static function destinationById(state:Object, id:String):Object {
        for (var i:Number = 0; i < state.destinations.length; i++) {
            if (state.destinations[i].id == id) return state.destinations[i];
        }
        return null;
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;

        setup();
        var state:Object = EggSelectPanelService.execute("snapshot", {v:1});
        check(state.success === true && state.operation == "snapshot" && state.v === 1, "snapshot envelope");
        check(state.progress.main === 0 && state.progress.egg === 0, "progress projection");
        check(state.destinations.length == 3
            && state.destinations[0].id == "forest_depth"
            && state.destinations[1].id == "machine_zone"
            && state.destinations[2].id == "forest_center", "three authored destinations in order");
        var depth:Object = destinationById(state, "forest_depth");
        check(depth.unlocked === true && depth.hintLocked === true && depth.lockReason == ""
            && depth.difficulty == "简单" && depth.stageName == "密林深处",
            "depth enterable from start, legacy hint stays");
        var zone:Object = destinationById(state, "machine_zone");
        check(zone.unlocked === false && zone.hintLocked === true
            && zone.lockReason.indexOf("彩蛋进度达到 4") >= 0 && zone.lockReason.indexOf("主线任务进度达到 67") >= 0,
            "zone carries both gate reasons");
        var center:Object = destinationById(state, "forest_center");
        check(center.unlocked === false && center.difficulty == "冒险"
            && center.lockReason.indexOf("彩蛋进度达到 11") >= 0, "center gate projection");

        setup(); _root.task_chains_progress.彩蛋 = 4; _root.主线任务进度 = 66;
        state = EggSelectPanelService.execute("snapshot", {v:1});
        check(destinationById(state, "machine_zone").unlocked === false
            && destinationById(state, "machine_zone").hintLocked === false,
            "zone hint clears at egg 4 but main 66 keeps the gate");
        setup(); _root.task_chains_progress.彩蛋 = 4; _root.主线任务进度 = 67;
        check(destinationById(EggSelectPanelService.execute("snapshot", {v:1}), "machine_zone").unlocked === true,
            "zone unlocks at egg 4 and main 67");
        setup(); _root.task_chains_progress.彩蛋 = 11;
        check(destinationById(EggSelectPanelService.execute("snapshot", {v:1}), "forest_center").unlocked === true,
            "center unlocks at egg 11");

        setup();
        var result:Object = EggSelectPanelService.execute("enter", {v:1, destinationId:"forest_depth"});
        check(result.success === true && result.closePanel === true && result.stageName == "密林深处"
            && result.difficulty == "简单" && result.destinationId == "forest_depth", "depth enter commits");
        check(_root.__configured.length == 1 && _root.__configured[0] == "密林深处"
            && _root.__entered.length == 1 && _root.__entered[0].difficulty == "简单",
            "legacy chain receives configured holder");

        setup(); _root.task_chains_progress.彩蛋 = 11;
        result = EggSelectPanelService.execute("enter", {v:1, destinationId:"forest_center"});
        check(result.success === true && result.difficulty == "冒险"
            && _root.__entered[0].stage == "密林中央", "center enters at fixed adventure difficulty");

        setup(); _root.task_chains_progress.彩蛋 = 10;
        check(EggSelectPanelService.execute("enter", {v:1, destinationId:"forest_center"}).error == "locked",
            "center locked below egg 11");
        check(_root.__entered.length == 0, "locked enter never touches legacy chain");
        check(EggSelectPanelService.execute("enter", {v:1, destinationId:"machine_zone"}).error == "locked",
            "zone locked without both gates");
        check(EggSelectPanelService.execute("enter", {v:1, destinationId:"candy_land"}).error == "unknown_destination",
            "unknown destination rejected");
        check(EggSelectPanelService.execute("enter", {v:1, destinationId:5}).error == "invalid_payload",
            "non-string destination rejected");
        check(EggSelectPanelService.execute("enter", {v:2, destinationId:"forest_depth"}).error == "unsupported_version",
            "version rejected");
        check(EggSelectPanelService.execute("enter", {v:1, destinationId:"forest_depth", debug:true}).error == "invalid_payload",
            "extra key rejected");
        check(EggSelectPanelService.execute("peek", {v:1}).error == "unsupported_cmd",
            "unknown command rejected");

        setup(); delete _root.StageInfoDict["密林深处"];
        check(EggSelectPanelService.execute("enter", {v:1, destinationId:"forest_depth"}).error == "stage_config_unavailable",
            "missing stage config refused");

        setup(); _root.__enterResult = false;
        check(EggSelectPanelService.execute("enter", {v:1, destinationId:"forest_depth"}).error == "enter_refused",
            "legacy refusal surfaces as enter_refused");

        setup(); _root.场景转换中 = true;
        check(EggSelectPanelService.execute("enter", {v:1, destinationId:"forest_depth"}).error == "pending_stage_settlement",
            "scene transition blocks new entry");

        setup();
        check(EggSelectPanelService.openPanel() === true
            && _root.__eggWire.indexOf('"panel":"egg-stage-select"') >= 0
            && _root.__eggWire.indexOf('"source":"world_egg_computer"') >= 0, "real opener envelope");
        EggSelectPanelService.handle("snapshot", {v:1, callId:42});
        check(_root.__eggWire.indexOf('"task":"egg_select_response"') >= 0
            && _root.__eggWire.indexOf('"callId":42') >= 0, "response task and callId echo");

        trace("EggSelectPanelServiceTest Tests Passed: " + passed);
        trace("EggSelectPanelServiceTest Tests Failed: " + failed);
    }
}
