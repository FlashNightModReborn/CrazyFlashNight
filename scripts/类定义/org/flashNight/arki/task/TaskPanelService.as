/**
 * 文件：org/flashNight/arki/task/TaskPanelService.as
 * 说明：WebView 任务面板的 AS2 端桥。
 *
 * 同步管道（与 PetPanelService / ArenaPanelService 同构）：
 *   Web → C# TaskTask → Flash gameCommands:
 *     taskSnapshot       — 返回玩家当前所有任务概要
 *     taskDetail         — 返回单个任务详细信息
 *     tasksTooltip       — 物品注释（name-keyed，复用 _root.Web物品注释HTML）
 *     taskFinish         — 交付任务（写操作，按 taskId 解析 index，taskCompleteCheck 门控）
 *     taskDelete         — 放弃任务（写操作，按 taskId 解析 index，主线任务拒绝）
 *     taskNavigateFinish — 前往交付（便利增强，复用地图 NPC→hotspot 跳转，回 closePanel）
 *     taskTreeState      — 事件日志/任务树 动态进度小叠加（WS6，只读：链进度+已完成 id 集+进行中 id）
 *     taskReplayDialogue — 剧情对话回放（WS6，按需回传单任务对话文本行供 web 内联展开，不关面板）
 *     taskPanelOpen      — 面板打开通知（当前为空操作）
 *     taskPanelClose     — 面板关闭通知（当前为空操作）
 *
 * 关键不变量：
 *   - 只读命令从 _root.tasks_to_do 和 TaskUtil.tasks 读取，不写入
 *   - 写命令复用游戏权威函数 _root.FinishTask / _root.DeleteTask（不在此重写 splice/标脏逻辑）
 *   - 响应格式：{ task: "task_response", callId: callId, success: true/false, ... }
 *   - 使用 LiteJSON 序列化（与 PetPanelService 相同）
 *
 * 写操作 index 偏移契约（重要）：
 *   _root.tasks_to_do 在 FinishTask/DeleteTask 后会 splice，导致其后所有 index 偏移。
 *   因此写命令一律按【taskId】（稳定主键，tasks_to_do 内唯一）解析当前 index，
 *   绝不信任 Web 端传来的 index；并在回包里附带刷新后的 tasks 概要，让面板原子重渲。
 *
 * 交付门控（安全要求）：
 *   _root.FinishTask 自身不校验完成度（原版门控在 NPCTaskCheck）。面板交付必须先过
 *   _root.taskCompleteCheck(index)，否则客户端可交付未完成任务骗取奖励。此为服务端硬门控。
 *
 * 远程交付开关（可选玩法增强 finish_remote）：
 *   任务数据新增布尔字段 finish_remote（data/task/*.json，缺省=false）。面板「交付」按钮
 *   只对 finish_remote==true 的任务开放远程直接交付；其余任务保持原版玩法——必须前往
 *   finish_npc 处由 NPCTaskCheck→FinishTask 交付。handleFinish 对非远程任务回 requires_npc
 *   （服务端硬门控，不信客户端）；handleDetail 回 finishRemote 供面板决定按钮态。
 *   NPC 交付路径不经 handleFinish，因此该开关不影响任何原版任务的正常交付。
 *
 * 前往交付（便利增强 taskNavigateFinish）：
 *   非远程任务面板按钮变为「前往交付」——复用地图跳转把玩家直送到 finish_npc 的地图位置
 *   （MapTaskNpcRegistry.findMarker → MapPanelService.canNavigateToHotspot/navigateToHotspot）。
 *   只负责"前往"，到达后仍由玩家点击 NPC 正常交付。可达性 = 非战斗地图 + 热点已登记 + 所在组解锁；
 *   不可达（或注册/目录未就绪）则按钮禁用、服务端回 not_navigable。handleDetail 回 finishNavigable。
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
        _root.gameCommands["taskFinish"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleFinish(params);
        };
        _root.gameCommands["taskDelete"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleDelete(params);
        };
        _root.gameCommands["taskNavigateFinish"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleNavigateFinish(params);
        };
        _root.gameCommands["taskTreeState"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleTreeState(params);
        };
        _root.gameCommands["taskReplayDialogue"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleReplayDialogue(params);
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
    // buildTaskList — 构造当前任务概要数组（snapshot 与写操作回包共用）
    //   单一口径：snapshot、taskFinish、taskDelete 回包的 tasks 形状完全一致，
    //   Web 端可走同一条渲染路径，写后无需额外往返重拉。
    // ═══════════════════════════════════════════════════════════
    private static function buildTaskList():Array {
        var tasks:Array = [];
        var tasksToDo:Array = _root.tasks_to_do;
        if (tasksToDo == undefined || tasksToDo.length == 0) return tasks;

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
        return tasks;
    }

    // index 偏移安全：按 taskId 在当前 tasks_to_do 中解析 index（找不到返回 -1）。
    // tasks_to_do 内 taskId 唯一（GetTask/AddTask 拒绝重复接取），解析无歧义。
    private static function resolveIndexByTaskId(taskId):Number {
        var tasksToDo:Array = _root.tasks_to_do;
        if (tasksToDo == undefined) return -1;
        var key:String = String(taskId);
        for (var i:Number = 0; i < tasksToDo.length; i++) {
            if (tasksToDo[i] != undefined && String(tasksToDo[i].id) == key) return i;
        }
        return -1;
    }

    // ═══════════════════════════════════════════════════════════
    // handleSnapshot — 返回玩家当前所有任务概要
    // ═══════════════════════════════════════════════════════════
    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        sendResponse({ task: "task_response", callId: callId, success: true, tasks: buildTaskList() });
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

        // 前往交付可达性：finish_npc → marker.hotspotId（MapTaskNpcRegistry）→ 可否直接跳转
        // （MapPanelService.canNavigateToHotspot：非战斗地图 + NAVIGATE_TARGETS 命中 + 所在组已解锁）。
        // 面板据此对「非远程但可前往」的任务把按钮变为可点的「前往交付」。注册/目录未就绪时回 false（优雅降级）。
        var finishNavigable:Boolean = false;
        if (npcName != "") {
            var navMarker:Object = org.flashNight.arki.map.MapTaskNpcRegistry.findMarker(npcName);
            if (navMarker != undefined) {
                finishNavigable = org.flashNight.arki.map.MapPanelService.canNavigateToHotspot(String(navMarker.hotspotId));
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
            rewards: rewards,
            // 共享判定条件进度（可选字段 conditions；与成就 progressOf 同口径 {label,cur,target}，
            // cur 为运行态实时读数——必须由 AS2 回，web catalog 只有静态 target）
            conditions: TaskUtil.conditionsProgress(taskData, entry),
            // 远程交付开关：仅 finish_remote==true 的任务允许面板直接交付，否则须前往 NPC
            finishRemote: (taskData.finish_remote == true),
            // 前往交付：该任务 finish_npc 当前是否可一键跳转到其地图位置
            finishNavigable: finishNavigable
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
    // handleFinish — 交付任务（写操作）
    //   按 taskId 解析 index → taskCompleteCheck 硬门控 → _root.FinishTask。
    //   回包附带刷新后的 tasks（splice + 任务链自动接取后已变化）。
    // ═══════════════════════════════════════════════════════════
    public static function handleFinish(params:Object):Void {
        var callId = params.callId;
        var index:Number = resolveIndexByTaskId(params.taskId);

        if (index < 0) {
            // 任务已不在列表（可能已被其它路径交付/删除）：回失败 + 刷新列表让面板重同步。
            sendResponse({ task: "task_response", callId: callId, success: false, error: "task_not_found", tasks: buildTaskList() });
            return;
        }

        // 远程交付门控（可选功能增强）：面板直接交付仅对显式标记 finish_remote 的任务开放，
        // 其余任务保持原版玩法——必须前往 finish_npc 处由 NPCTaskCheck→FinishTask 交付。
        // 默认（字段缺省）= 不允许远程，等价于还原原版行为。NPC 交付路径不经本函数，不受影响。
        var fTaskData:Object = TaskUtil.tasks[_root.tasks_to_do[index].id];
        if (!(fTaskData != undefined && fTaskData.finish_remote == true)) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "requires_npc", tasks: buildTaskList() });
            return;
        }

        // 服务端硬门控：未满足交付条件绝不交付（FinishTask 自身不校验）。
        if (_root.taskCompleteCheck(index) != true) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "not_satisfied", tasks: buildTaskList() });
            return;
        }

        // FinishTask 返回 false 仅在「背包无法装下奖励」时（此时未 splice，任务仍在）。
        var ok:Boolean = (_root.FinishTask(index) == true);
        if (!ok) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "inventory_full", tasks: buildTaskList() });
            return;
        }

        sendResponse({ task: "task_response", callId: callId, success: true, tasks: buildTaskList() });
    }

    // ═══════════════════════════════════════════════════════════
    // handleDelete — 放弃任务（写操作）
    //   按 taskId 解析 index → 主线任务拒绝 → _root.DeleteTask。回包附带刷新后的 tasks。
    // ═══════════════════════════════════════════════════════════
    public static function handleDelete(params:Object):Void {
        var callId = params.callId;
        var index:Number = resolveIndexByTaskId(params.taskId);

        if (index < 0) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "task_not_found", tasks: buildTaskList() });
            return;
        }

        // 预判主线：返清晰错误码且不触发 DeleteTask 内的「无法删除主线」游戏内提示。
        var taskData:Object = TaskUtil.tasks[_root.tasks_to_do[index].id];
        if (taskData != undefined && taskData.chain != undefined && String(taskData.chain[0]) == "主线") {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "cannot_delete_main", tasks: buildTaskList() });
            return;
        }

        var ok:Boolean = (_root.DeleteTask(index) == true);
        if (!ok) {
            // 兜底：DeleteTask 仅对主线返 false（上面已预判），此处理论不达；保险起见回失败 + 刷新。
            sendResponse({ task: "task_response", callId: callId, success: false, error: "delete_failed", tasks: buildTaskList() });
            return;
        }

        sendResponse({ task: "task_response", callId: callId, success: true, tasks: buildTaskList() });
    }

    // ═══════════════════════════════════════════════════════════
    // handleNavigateFinish — 前往交付（复用地图跳转，便利性增强）
    //   按 taskId 解析 finish_npc → MapTaskNpcRegistry 找 hotspot → MapPanelService 跳转。
    //   成功回 closePanel:true（与地图面板 navigate 同语义，前端关面板让场景淡出跳转）。
    //   实际交付仍由玩家到达后点击 NPC 完成（本功能只负责"前往"，不自动交付）。
    // ═══════════════════════════════════════════════════════════
    public static function handleNavigateFinish(params:Object):Void {
        var callId = params.callId;
        var index:Number = resolveIndexByTaskId(params.taskId);
        if (index < 0) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "task_not_found", tasks: buildTaskList() });
            return;
        }

        var taskData:Object = TaskUtil.tasks[_root.tasks_to_do[index].id];
        var npc:String = (taskData != undefined && taskData.finish_npc != undefined) ? String(taskData.finish_npc) : "";
        if (npc == "") {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "npc_not_on_map" });
            return;
        }

        var marker:Object = org.flashNight.arki.map.MapTaskNpcRegistry.findMarker(npc);
        if (marker == undefined) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "npc_not_on_map" });
            return;
        }

        var hid:String = String(marker.hotspotId);
        // 二次硬门控：可达性按当前游戏态实时判定（战斗地图/未解锁/目录未就绪都拒绝）
        if (!org.flashNight.arki.map.MapPanelService.canNavigateToHotspot(hid)) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "not_navigable" });
            return;
        }

        var ok:Boolean = org.flashNight.arki.map.MapPanelService.navigateToHotspot(hid);
        sendResponse({
            task: "task_response",
            callId: callId,
            success: ok,
            closePanel: ok,
            error: ok ? undefined : "navigate_failed"
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleTreeState — 事件日志/任务树 的动态进度小叠加（WS6，只读）
    //   静态任务目录由 build 派生的 task-catalog.json 供 web 直读（零 AS2 传输）；
    //   本命令只回【可变存档态】：各链进度 + 已完成 id 集 + 当前进行 id。载荷极小（数字+id），非全表。
    //   web 用 catalog.chains + 本叠加渲染树并标 完成/进行 态。绝不在此回任何静态展示文本。
    // ═══════════════════════════════════════════════════════════
    public static function handleTreeState(params:Object):Void {
        var callId = params.callId;

        // 各链进度（链名→数字，复制 _root.task_chains_progress）
        var progress:Object = {};
        var src:Object = _root.task_chains_progress;
        if (src != undefined) {
            for (var k:String in src) { progress[k] = src[k]; }
        }

        // 已完成 id 集（_root.tasks_finished 中值 >0 的键）
        var finished:Array = [];
        var fin:Object = _root.tasks_finished;
        if (fin != undefined) {
            for (var fk:String in fin) {
                if (Number(fin[fk]) > 0) finished.push(fk);
            }
        }

        // 当前进行的任务 id（tasks_to_do）
        var active:Array = [];
        var todo:Array = _root.tasks_to_do;
        if (todo != undefined) {
            for (var i:Number = 0; i < todo.length; i++) {
                if (todo[i] != undefined) active.push(todo[i].id);
            }
        }

        sendResponse({
            task: "task_response", callId: callId, success: true,
            chainsProgress: progress, finished: finished, active: active
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleReplayDialogue — 剧情对话回放（WS6，轻量内联文本）
    //   按需回传【单条任务】的对话文本行供 web 面板内联展开（不关面板，体验连续）。对话文本仍单权威
    //   留 AS2（catalog 不含对话本体，仅 hasGetConv/hasFinishConv 布尔），点击才按需回传一条任务的对话，
    //   载荷小、懒加载。返回解析后的 {speaker,sub,text} 行（name/title 经 getDialogueSpecialString 解析
    //   $PC/$PC_TITLE 等特殊串，与原版对话框口径一致）。富立绘对话框留待对话框整体迁 web 后替换本文本态。
    //   按 taskId 取任务即可（双键陷阱见审计：副本任务中文 title 键是 stage-select 活路径，勿删；此处用 id）。
    // ═══════════════════════════════════════════════════════════
    public static function handleReplayDialogue(params:Object):Void {
        var callId = params.callId;
        var taskData:Object = TaskUtil.tasks[params.taskId];
        if (taskData == undefined) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "task_not_found" });
            return;
        }

        var which:String = (params.which == "finish") ? "finish" : "get";

        // 防剧透硬门控（服务端权威，不依赖前端隐藏按钮——前端可被绕过直发 replayDialogue）：
        //   只回放玩家【已经历】的对话。接取对话=任务进行中(tasks_to_do)或已完成(tasks_finished>0)；
        //   完成对话=仅已完成（未完成不该能读到完成剧情）。否则回 locked，绝不吐对话本体。
        var idStr:String = String(params.taskId);
        var isFinished:Boolean = Number(_root.tasks_finished[idStr]) > 0;
        var isActive:Boolean = false;
        var todo:Array = _root.tasks_to_do;
        if (todo != undefined) {
            for (var ti:Number = 0; ti < todo.length; ti++) {
                if (todo[ti] != undefined && String(todo[ti].id) == idStr) { isActive = true; break; }
            }
        }
        var allowed:Boolean = (which == "finish") ? isFinished : (isActive || isFinished);
        if (!allowed) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "locked" });
            return;
        }

        var convKey = (which == "finish") ? taskData.finish_conversation : taskData.get_conversation;
        var conv = TaskUtil.getTaskText(convKey);
        if (conv == undefined || conv.length == 0) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "no_dialogue" });
            return;
        }

        var hasResolver:Boolean = (typeof _root.getDialogueSpecialString == "function");
        var lines:Array = [];
        for (var i:Number = 0; i < conv.length; i++) {
            var ln:Object = conv[i];
            if (ln == undefined) continue;
            var speaker = hasResolver ? _root.getDialogueSpecialString(ln.name) : ln.name;
            var sub = hasResolver ? _root.getDialogueSpecialString(ln.title) : ln.title;
            lines.push({
                speaker: (speaker != undefined ? String(speaker) : ""),
                sub: (sub != undefined ? String(sub) : ""),
                text: (ln.text != undefined ? String(ln.text) : "")
            });
        }

        sendResponse({ task: "task_response", callId: callId, success: true, which: which, lines: lines });
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
