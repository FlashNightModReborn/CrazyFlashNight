/**
 * 任务面板 TaskPanelService 的 wire 契约 focused 测试；不连接运行中的游戏。
 *
 * 核心契约：跨异步回包后 callId 必须保持数字型——Host TaskTask.TryReadBackendCallId
 * 只接受 JTokenType.Integer，字符串化 callId 会被整包丢弃（task_response_dropped
 * reason=invalid_backend_call_id），Web 端随之等到超时。2026-09-07 e131182909
 * 曾把 handleDetail / handleNavigateFinish 的 callId 字符串化（String(params.callId)），
 * 本套件钉死该回归：断言原始 wire 上是 "callId":71 而非 "callId":"71"，
 * 且乱序/失败/同步拒绝路径各自保留请求编号。
 */
import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.map.MapPanelService;
import org.flashNight.arki.task.TaskPanelService;
import org.flashNight.arki.task.TaskUtil;

class org.flashNight.arki.task.TaskPanelServiceTest {
    private static var _passed:Number;
    private static var _failed:Number;
    private static var _wires:Array;
    private static var _responses:Array;
    private static var _snapshotCalls:Array;
    private static var _navCalls:Array;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) { _passed++; trace("[PASS] " + label); }
        else { _failed++; trace("[FAIL] " + label); }
    }
    private static function snapshotFields(object:Object, fields:Array):Object {
        var result:Object = {};
        for (var i:Number = 0; i < fields.length; i++) result[fields[i]] = object[fields[i]];
        return result;
    }
    private static function restoreFields(object:Object, fields:Array, saved:Object):Void {
        for (var i:Number = 0; i < fields.length; i++) object[fields[i]] = saved[fields[i]];
    }
    private static function recordWire(wire:String):Void {
        org.flashNight.arki.task.TaskPanelServiceTest._wires.push(wire);
        org.flashNight.arki.task.TaskPanelServiceTest._responses.push((new JSON(false)).parse(wire));
        trace("TaskPanelServiceTest wire: " + wire);
    }

    public static function runAllTests():Void {
        _passed = 0; _failed = 0;
        _wires = []; _responses = []; _snapshotCalls = []; _navCalls = [];
        trace("=== TaskPanelServiceTest start ===");
        var panel:Object = TaskPanelService;
        var bridge:Object = MapDomainBridge;
        var mapPanel:Object = MapPanelService;
        var taskUtil:Object = TaskUtil;
        var oldSnapshot:Function = bridge.snapshot;
        var oldEndpoint:Function = bridge.endpoint;
        var oldNpcLabel:Function = bridge.taskNpcLabel;
        var oldNavigateToTask:Function = mapPanel.navigateToTask;
        var savedPanel:Object = snapshotFields(panel, ["_json"]);
        var savedUtil:Object = snapshotFields(taskUtil, ["tasks"]);
        var savedRoot:Object = snapshotFields(_root, ["server", "tasks_to_do", "taskCompleteCheck"]);
        try {
            panel._json = new LiteJSON();
            _root.server = {sendSocketMessage:function(wire:String):Void {
                org.flashNight.arki.task.TaskPanelServiceTest.recordWire(wire);
            }};
            _root.tasks_to_do = [
                {id:"1", requirements:{stages:[]}},
                {id:"4", requirements:{stages:[]}},
                {id:"70001", requirements:{stages:[]}}
            ];
            _root.taskCompleteCheck = function(index:Number):Boolean { return index == 1; };
            var tasksDict:Object = {};
            tasksDict["1"] = {id:"1", title:"讨伐试炼", description:"击败新兵教官", chain:["主线"]};
            tasksDict["4"] = {id:"4", title:"防线情报", description:"带回情报", chain:["主线"],
                finish_requirements:["废弃防线#冒险"], finish_submit_items:["情报#1"],
                rewards:["金币#100"]};
            tasksDict["70001"] = {id:"70001", title:"铁枪委托", description:"建设前线指挥部", chain:["铁枪链", 1]};
            taskUtil.tasks = tasksDict;
            bridge.snapshot = function(callback:Function, ids:Array):Void {
                org.flashNight.arki.task.TaskPanelServiceTest._snapshotCalls.push({callback:callback, ids:ids});
            };
            bridge.endpoint = function(taskId:String, role:String):Object {
                return {navigable:true, reason:""};
            };
            bridge.taskNpcLabel = function(taskId:String, role:String):String { return "Blue"; };
            mapPanel.navigateToTask = function(taskId:String, callback:Function, guard:Function):Void {
                org.flashNight.arki.task.TaskPanelServiceTest._navCalls.push({taskId:taskId, callback:callback, guard:guard});
            };

            // ── taskDetail：乱序成功回包各自保持数字 callId ──
            var first:Object = {callId:71, index:0};
            TaskPanelService.handleDetail(first);
            TaskPanelService.handleDetail({callId:72, index:1});
            first.callId = 999; // 调用方事后改写入参不得污染已受理请求
            check(_responses.length == 0 && _snapshotCalls.length == 2,
                "task detail waits for its asynchronous map snapshot");
            _snapshotCalls[1].callback(true, "");
            _snapshotCalls[0].callback(true, "");
            check(_snapshotCalls[0].ids[0] == "1" && _snapshotCalls[1].ids[0] == "4",
                "snapshot interest carries the requested task ids");
            check(_responses.length == 2 && _responses[0].callId === 72 && _responses[1].callId === 71,
                "out-of-order detail callbacks preserve separate numeric callIds after the caller returns");
            check(_wires[0].indexOf("\"callId\":72") >= 0 && _wires[1].indexOf("\"callId\":71") >= 0
                && _wires[0].indexOf("\"callId\":\"") < 0 && _wires[1].indexOf("\"callId\":\"") < 0,
                "detail wires carry integer callId accepted by Host strict parsing");
            check(_responses[1].task == "task_response" && _responses[1].success === true
                && _responses[1].taskData.taskId == "1" && _responses[1].taskData.type == "主线"
                && _responses[1].taskData.npcName == "Blue" && _responses[1].taskData.finishNavigable === true,
                "detail wire contains the production response envelope and payload");
            check(_responses[0].taskData.taskId == "4" && _responses[0].taskData.stageReq.name == "废弃防线"
                && _responses[0].taskData.itemReqs.length == 1 && _responses[0].taskData.satisfied === true,
                "stage and item requirements survive the fresh detail round trip");

            // ── taskDetail：地图事实失败回包保持原编号 ──
            TaskPanelService.handleDetail({callId:73, index:2});
            _snapshotCalls[2].callback(false, "map_domain_not_ready");
            check(_responses[2].callId === 73 && _responses[2].success === false
                && _responses[2].error == "map_domain_not_ready"
                && _wires[2].indexOf("\"callId\":73") >= 0 && _wires[2].indexOf("\"callId\":\"") < 0,
                "detail failure retains its original numeric callId");

            // ── taskDetail：Host 编号上限不字符串化 ──
            TaskPanelService.handleDetail({callId:2147483647, index:0});
            _snapshotCalls[3].callback(true, "");
            check(_responses[3].callId === 2147483647 && _wires[3].indexOf("\"callId\":2147483647") >= 0,
                "task wire preserves the maximum positive Host callId without string coercion");

            // ── taskDetail：非法下标同步拒绝，编号仍是数字 ──
            var beforeSync:Number = _snapshotCalls.length;
            TaskPanelService.handleDetail({callId:76, index:99});
            check(_snapshotCalls.length == beforeSync && _responses[4].callId === 76
                && _responses[4].success === false && _responses[4].error == "invalid_index"
                && _wires[4].indexOf("\"callId\":76") >= 0,
                "invalid index rejects synchronously with a numeric callId and no snapshot wait");

            // ── taskNavigateFinish：乱序回包 + closePanel 语义 ──
            TaskPanelService.handleNavigateFinish({callId:77, taskId:"1"});
            TaskPanelService.handleNavigateFinish({callId:78, taskId:"4"});
            check(_responses.length == 5 && _navCalls.length == 2
                && _navCalls[0].taskId == "1" && _navCalls[1].taskId == "4",
                "navigate finish waits for its asynchronous navigation result");
            _navCalls[1].callback(false, "not_navigable");
            _navCalls[0].callback(true, "");
            check(_responses[5].callId === 78 && _responses[5].success === false
                && _responses[5].closePanel === false && _responses[5].error == "not_navigable",
                "rejected navigation keeps its callId and does not close the panel");
            check(_responses[6].callId === 77 && _responses[6].success === true
                && _responses[6].closePanel === true
                && _wires[6].indexOf("\"callId\":77") >= 0 && _wires[6].indexOf("\"callId\":\"") < 0,
                "successful navigation keeps its numeric callId and exact close result");

            // ── taskNavigateFinish：守卫按 taskId 复核当前任务列表 ──
            check(_navCalls[0].guard() === true, "navigation guard accepts a task still on the live list");
            _root.tasks_to_do.splice(1, 1); // 移除 id "4"
            check(_navCalls[1].guard() === false && _navCalls[0].guard() === true,
                "navigation guard re-resolves the task id against the live list");

            // ── taskNavigateFinish：未知任务同步拒绝 ──
            TaskPanelService.handleNavigateFinish({callId:80, taskId:"missing"});
            check(_responses[7].callId === 80 && _responses[7].success === false
                && _responses[7].error == "task_not_found" && _responses[7].tasks.length == 2
                && _wires[7].indexOf("\"callId\":80") >= 0 && _wires[7].indexOf("\"callId\":\"") < 0,
                "unknown task rejects synchronously with a numeric callId and refreshed list");
        } catch(error) { _failed++; trace("[FAIL] unexpected task panel test exception: " + error); }
        finally {
            bridge.snapshot = oldSnapshot; bridge.endpoint = oldEndpoint; bridge.taskNpcLabel = oldNpcLabel;
            mapPanel.navigateToTask = oldNavigateToTask;
            restoreFields(panel, ["_json"], savedPanel);
            restoreFields(taskUtil, ["tasks"], savedUtil);
            restoreFields(_root, ["server", "tasks_to_do", "taskCompleteCheck"], savedRoot);
        }
        trace("TaskPanelServiceTest Tests Passed: " + _passed);
        trace("TaskPanelServiceTest Tests Failed: " + _failed);
        trace("=== TaskPanelServiceTest end ===");
    }
}
