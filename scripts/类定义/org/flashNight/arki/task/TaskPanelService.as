/**
 * 文件：org/flashNight/arki/task/TaskPanelService.as
 * 说明：WebView 任务面板的 AS2 端桥。
 *
 * 同步管道（与 PetPanelService / ArenaPanelService 同构）：
 *   Web → C# TaskTask → Flash gameCommands:
 *     taskSnapshot       — 返回玩家当前所有任务概要
 *     taskDetail         — 返回单个任务详细信息
 *     tasksTooltip       — 物品注释（name-keyed，复用 _root.Web物品注释HTML）
 *     taskPanelOpen      — 面板打开通知（当前为空操作）
 *     taskPanelClose     — 面板关闭通知（当前为空操作）
 *
 * 关键不变量：
 *   - 所有数据从 _root.tasks_to_do 和 TaskUtil.tasks 读取，不写入
 *   - 响应格式：{ task: "task_response", callId: callId, success: true/false, ... }
 *   - 使用 LiteJSON 序列化（与 PetPanelService 相同）
 */
import org.flashNight.arki.task.TaskUtil;
import LiteJSON;

class org.flashNight.arki.task.TaskPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["taskSnapshot"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleSnapshot(params);
        };
        _root.gameCommands["taskDetail"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleDetail(params);
        };
        _root.gameCommands["tasksTooltip"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleTooltip(params);
        };
        _root.gameCommands["taskPanelOpen"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handlePanelOpen(params);
        };
        _root.gameCommands["taskPanelClose"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handlePanelClose(params);
        };

        _inited = true;
    }

    // ═══════════════════════════════════════════════════════════
    // handleSnapshot — 返回玩家当前所有任务概要
    // ═══════════════════════════════════════════════════════════
    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        var tasks:Array = [];
        var tasksToDo:Array = _root.tasks_to_do;

        if (tasksToDo == undefined || tasksToDo.length == 0) {
            sendResponse({ task: "task_response", callId: callId, success: true, tasks: tasks });
            return;
        }

        for (var i:Number = 0; i < tasksToDo.length; i++) {
            var entry:Object = tasksToDo[i];
            if (entry == undefined) continue;
            var taskId = entry.id;
            var taskData:Object = TaskUtil.tasks[taskId];
            if (taskData == undefined) continue;

            var title:String = TaskUtil.getTaskText(taskData.title);
            var type:String = taskData.chain != undefined && taskData.chain[0] != undefined
                ? String(taskData.chain[0])
                : "";

            // 完成判定必须与游戏内交付门槛一致：关卡 + 提交/持有物品 + 特殊需求。
            // 旧逻辑只看 requirements.stages.length，会对交物/持有/特殊型任务显示假完成图标。
            // 复用权威函数 _root.taskCompleteCheck(index)（定义于 通信_鸡蛋_任务系统.as）。
            var satisfied:Boolean = (_root.taskCompleteCheck(i) == true);

            tasks.push({
                taskId: taskId,
                title: title,
                type: type,
                npcName: taskData.get_npc != undefined ? String(taskData.get_npc) : "",
                satisfied: satisfied
            });
        }

        sendResponse({ task: "task_response", callId: callId, success: true, tasks: tasks });
    }

    // ═══════════════════════════════════════════════════════════
    // handleDetail — 返回单个任务详细信息
    // ═══════════════════════════════════════════════════════════
    public static function handleDetail(params:Object):Void {
        var callId = params.callId;
        var index:Number = params.index;

        var tasksToDo:Array = _root.tasks_to_do;
        if (tasksToDo == undefined || index == undefined || isNaN(index) || index < 0 || index >= tasksToDo.length) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "invalid_index" });
            return;
        }

        var entry:Object = tasksToDo[index];
        if (entry == undefined) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "entry_not_found" });
            return;
        }

        var taskId = entry.id;
        var taskData:Object = TaskUtil.tasks[taskId];
        if (taskData == undefined) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "task_data_not_found" });
            return;
        }

        // 解析基本字段
        var title:String = TaskUtil.getTaskText(taskData.title);
        var description:String = TaskUtil.getTaskText(taskData.description);
        var type:String = taskData.chain != undefined && taskData.chain[0] != undefined
            ? String(taskData.chain[0])
            : "";

        // 解析关卡需求 (finish_requirements: ["stageName#difficulty", ...])
        var stageReq:Object = null;
        var finishReqs:Array = taskData.finish_requirements;
        if (finishReqs != undefined && finishReqs.length > 0) {
            var parts:Array = String(finishReqs[0]).split("#");
            stageReq = { name: parts[0], difficulty: parts[1] != undefined ? String(parts[1]) : "" };
        }

        // 解析物品需求 (finish_submit_items / finish_contain_items: ["itemName#quantity", ...])
        var itemReqs:Array = [];
        if (taskData.finish_submit_items != undefined && taskData.finish_submit_items.length > 0) {
            for (var si:Number = 0; si < taskData.finish_submit_items.length; si++) {
                var sParts:Array = String(taskData.finish_submit_items[si]).split("#");
                var sName:String = sParts[0];
                var sCount:Number = sParts[1] != undefined ? Number(sParts[1]) : 1;
                itemReqs.push({ name: sName, count: sCount, kind: "submit" });
            }
        }
        if (taskData.finish_contain_items != undefined && taskData.finish_contain_items.length > 0) {
            for (var ci:Number = 0; ci < taskData.finish_contain_items.length; ci++) {
                var cParts:Array = String(taskData.finish_contain_items[ci]).split("#");
                var cName:String = cParts[0];
                var cCount:Number = cParts[1] != undefined ? Number(cParts[1]) : 1;
                itemReqs.push({ name: cName, count: cCount, kind: "contain" });
            }
        }

        // 解析提交NPC
        var npcName:String = taskData.finish_npc != undefined ? String(taskData.finish_npc) : "";

        // 解析奖励 (rewards: ["itemName#quantity", ...])
        var rewards:Array = [];
        if (taskData.rewards != undefined && taskData.rewards.length > 0) {
            for (var ri:Number = 0; ri < taskData.rewards.length; ri++) {
                var rParts:Array = String(taskData.rewards[ri]).split("#");
                var rName:String = rParts[0];
                var rCount:Number = rParts[1] != undefined ? Number(rParts[1]) : 1;
                rewards.push({ name: rName, count: rCount });
            }
        }

        var dto:Object = {
            taskId: taskId,
            type: type,
            title: title,
            description: description,
            stageReq: stageReq,
            itemReqs: itemReqs,
            npcName: npcName,
            rewards: rewards
        };

        sendResponse({ task: "task_response", callId: callId, success: true, taskData: dto });
    }

    // ═══════════════════════════════════════════════════════════
    // handleTooltip — 物品注释（name-keyed，复用 _root.Web物品注释HTML）
    //   与 intelligenceTooltip 同构（商城系统_WebView.as）。
    //   注意：物品类型字段名用 itemType，绝不能用 type——会与 panel_resp 信封
    //   的 type 字段冲突，导致 Web 端 Bridge 按 data.type 路由时丢包。
    // ═══════════════════════════════════════════════════════════
    public static function handleTooltip(params:Object):Void {
        var callId = params.callId;
        var itemName:String = String(params.itemName != undefined ? params.itemName : "");
        var tt:Object = _root.Web物品注释HTML(itemName);
        if (tt == null) {
            sendResponse({ task: "task_response", callId: callId, success: false, itemName: itemName, error: "item_not_found" });
            return;
        }
        // layoutType 推导对齐 kshop/intelligence：消耗品取 use，其余取 type
        var itemType:String = "";
        if (tt.itemData != undefined) {
            itemType = (tt.itemData.type == "消耗品")
                ? String(tt.itemData.use != undefined ? tt.itemData.use : "")
                : String(tt.itemData.type != undefined ? tt.itemData.type : "");
        }
        sendResponse({
            task: "task_response",
            callId: callId,
            success: true,
            itemName: itemName,
            displayname: tt.displayname,
            descHTML: tt.descHTML,
            introHTML: tt.introHTML,
            itemType: itemType
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handlePanelOpen / handlePanelClose — 面板生命周期通知
    // ═══════════════════════════════════════════════════════════
    public static function handlePanelOpen(params:Object):Void {
        // 当前无需在 AS2 端执行操作，仅确认收到
    }

    public static function handlePanelClose(params:Object):Void {
        // 当前无需在 AS2 端执行操作，仅确认收到
    }

    // ═══════════════════════════════════════════════════════════
    // sendResponse — 统一回包
    // ═══════════════════════════════════════════════════════════
    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
    }
}
