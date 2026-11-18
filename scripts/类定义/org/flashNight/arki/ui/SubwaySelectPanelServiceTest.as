import org.flashNight.arki.ui.SubwaySelectPanelService;
import org.flashNight.arki.stageSelect.StageAdmissionHostTestFixture;
import org.flashNight.arki.scene.StageRunSession;

/** U7 地铁线路选关的 focused 套件：mock 旧进关根函数，验证门槛投影与进关语义。 */
class org.flashNight.arki.ui.SubwaySelectPanelServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] SubwaySelect: " + message); }
    }
    private static function execute(command:String, params:Object):Object {
        var result:Object;
        SubwaySelectPanelService.execute(command, params, function(reply:Object):Void { result = reply; });
        return result;
    }
    private static function setup():Void {
        StageRunSession.testOnlyReset();
        _root.gameworld = {};
        _root.savePath = "cf7_agent_stage_entry_test";
        _root.isChallengeMode = function():Boolean { return false; };
        _root.主线任务进度 = 0;
        _root.task_chains_progress = {彩蛋:0};
        _root.任务进度 = {};
        _root.场景转换中 = false;
        _root.当前为战斗地图 = false;
        _root.斗兽标定模式 = false;
        delete _root._saveExt;
        _root.StageInfoDict = {
            总备处站清理:{Type:"无限过图", Name:"总备处站清理"},
            密林深处:{Type:"无限过图", Name:"密林深处"},
            环线东北站:{Type:"无限过图", Name:"环线东北站"}
        };
        _root.__subwayWire = null;
        _root.server = {sendSocketMessage:function(value):Boolean { _root.__subwayWire = value; return true; }};
        for (var name:String in _root.StageInfoDict) {
            _root.StageInfoDict[name].url = "data/stages/副本任务/" + name + ".xml";
            _root.StageInfoDict[name].FadeTransitionFrame = "wuxianguotu_1";
        }
        _root.__configured = [];
        _root.__entered = [];
        _root.__enterResult = true;
        _root.配置关卡属性 = function(name:String):Void {
            _root.__configured.push(name);
            var info:Object = _root.StageInfoDict[name];
            this.当前关卡名 = name;
            this.关卡类型 = info.Type;
            this.关卡路径 = info.url;
            this.淡出跳转帧 = info.FadeTransitionFrame;
        };
        _root.计算难度等级 = function(mode:String):Number { return 1; };
        _root.载入关卡数据 = function(kind:String, url:String, loaded:Function):Void { loaded({}); };
        _root.淡出动画 = {淡出跳转帧:function(frame:String):Boolean {
            var stage:String = _root.当前关卡名;
            _root.__entered.push({stage:stage, difficulty:_root.当前关卡难度, path:_root.StageInfoDict[stage].url});
            return _root.__enterResult;
        }};
        StageAdmissionHostTestFixture.decision("总备处站清理",false,false,"");
        StageAdmissionHostTestFixture.decision("密林深处",false,false,"");
        StageAdmissionHostTestFixture.decision("自由广场防守",false,false,"");
    }
    private static function snapshot():Object {
        return execute("snapshot", {v:1});
    }
    private static function entryById(state:Object, id:String):Object {
        for (var i:Number = 0; i < state.entries.length; i++) {
            if (state.entries[i].id == id) return state.entries[i];
        }
        return null;
    }
    private static function stationById(state:Object, id:String):Object {
        for (var i:Number = 0; i < state.stations.length; i++) {
            if (state.stations[i].id == id) return state.stations[i];
        }
        return null;
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        StageAdmissionHostTestFixture.install();

        setup();
        var state:Object = snapshot();
        check(state.success === true && state.operation == "snapshot" && state.v === 1, "snapshot envelope");
        check(state.progress.main === 0 && state.progress.egg === 0, "progress projection");
        check(state.stations.length == 4 && stationById(state, "总备处站").frame === 4
            && stationById(state, "新市场站").frame === 1
            && stationById(state, "自由广场站").frame === 2
            && stationById(state, "环线东北站").frame === 3, "station frames at zero progress");
        check(state.entries.length == 1 && state.entries[0].id == "explore_stationD"
            && state.entries[0].enterable === true && state.entries[0].highlighted === false,
            "only explore entry at zero progress");

        setup(); _root.主线任务进度 = 50;
        StageAdmissionHostTestFixture.decision("总备处站清理",true,true,"");
        StageAdmissionHostTestFixture.decision("自由广场防守",true,false,"");
        state = snapshot();
        check(entryById(state, "clean_stationA") != null && entryById(state, "clean_stationA").highlighted === true,
            "clean entry visible and highlighted at main 50");
        check(entryById(state, "defend_stationC") != null && entryById(state, "defend_stationC").enterable === false
            && entryById(state, "defend_stationC").highlighted === false, "defend entry is display-only");
        check(entryById(state, "explore_stationD").highlighted === true, "explore highlighted at main 50");
        check(entryById(state, "raid_stationB") == null, "raid hidden without egg progress");

        setup(); _root.主线任务进度 = 67; _root.task_chains_progress.彩蛋 = 4;
        StageAdmissionHostTestFixture.decision("密林深处",true,true,"");
        state = snapshot();
        check(entryById(state, "raid_stationB") != null && entryById(state, "raid_stationB").highlighted === true,
            "raid visible and highlighted at egg 4 main 67");
        check(stationById(state, "新市场站").frame === 3, "station B unlocked frame");

        setup(); _root.主线任务进度 = 20;
        StageAdmissionHostTestFixture.decision("自由广场防守",true,false,""); _root.任务进度 = {自由广场已完成:true};
        check(entryById(snapshot(), "defend_stationC").highlighted === true, "defend highlighted after completion");

        setup(); _root.主线任务进度 = 67; _root.task_chains_progress.彩蛋 = 4;
        StageAdmissionHostTestFixture.decision("密林深处",true,true,"");
        var result:Object = execute("enter", {v:1, entryId:"raid_stationB"});
        check(result.success === true && result.closePanel === true && result.stageName == "密林深处"
            && result.difficulty == "简单" && result.entryId == "raid_stationB", "raid enter commits");
        check(_root.__configured.length == 1 && _root.__configured[0] == "密林深处", "legacy configure called once");
        check(_root.__entered.length == 1 && _root.__entered[0].stage == "密林深处"
            && _root.__entered[0].difficulty == "简单"
            && _root.__entered[0].path == "data/stages/副本任务/密林深处.xml",
            "stage executor receives canonical stage data");

        setup(); _root.主线任务进度 = 50;
        StageAdmissionHostTestFixture.decision("总备处站清理",true,true,"");
        StageAdmissionHostTestFixture.decision("自由广场防守",true,false,"");
        result = execute("enter", {v:1, entryId:"clean_stationA"});
        check(result.success === true && result.stageName == "总备处站清理", "clean enter at main 50");

        setup(); _root.主线任务进度 = 30;
        check(execute("enter", {v:1, entryId:"clean_stationA"}).error == "locked",
            "clean entry locked below main 45");
        setup();
        check(execute("enter", {v:1, entryId:"raid_stationB"}).error == "locked",
            "raid locked without egg progress");
        check(execute("enter", {v:1, entryId:"defend_stationC"}).error == "not_enterable",
            "display-only station cannot start a stage even when hidden");
        setup(); _root.主线任务进度 = 20;
        StageAdmissionHostTestFixture.decision("自由广场防守",true,false,"");
        check(execute("enter", {v:1, entryId:"defend_stationC"}).error == "not_enterable",
            "defend is never enterable");
        check(execute("enter", {v:1, entryId:"fly_stationX"}).error == "unknown_entry",
            "unknown entry rejected");
        check(execute("enter", {v:1, entryId:5}).error == "invalid_payload",
            "non-string entry rejected");
        check(execute("enter", {v:2, entryId:"explore_stationD"}).error == "unsupported_version",
            "version rejected");
        check(execute("enter", {v:1, entryId:"explore_stationD", debug:true}).error == "invalid_payload",
            "extra key rejected");
        check(execute("peek", {v:1}).error == "unsupported_cmd",
            "unknown command rejected");

        setup(); delete _root.StageInfoDict["环线东北站"];
        check(execute("enter", {v:1, entryId:"explore_stationD"}).error == "stage_config_unavailable",
            "missing stage config refused");

        setup(); _root.__enterResult = false;
        check(execute("enter", {v:1, entryId:"explore_stationD"}).error == "stage_transition_failed",
            "a rejected fade rolls the prepared transition back");

        setup(); _root.当前为战斗地图 = true;
        check(execute("enter", {v:1, entryId:"explore_stationD"}).error == "pending_stage_settlement",
            "active stage blocks new entry");
        check(_root.__entered.length == 0, "blocked enter never touches legacy chain");

        setup();
        check(SubwaySelectPanelService.openPanel() === true
            && _root.__subwayWire.indexOf('"panel":"subway"') >= 0
            && _root.__subwayWire.indexOf('"source":"world_subway"') >= 0, "real opener envelope");
        SubwaySelectPanelService.handle("snapshot", {v:1, callId:41});
        check(_root.__subwayWire.indexOf('"task":"subway_select_response"') >= 0
            && _root.__subwayWire.indexOf('"callId":41') >= 0, "response task and callId echo");

        StageAdmissionHostTestFixture.restore();
        trace("SubwaySelectPanelServiceTest Tests Passed: " + passed);
        trace("SubwaySelectPanelServiceTest Tests Failed: " + failed);
    }
}
