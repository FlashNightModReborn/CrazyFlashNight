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
import org.flashNight.arki.item.ItemUtil;
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

        // ── 副本任务（委托任务）面板：旧 FLA Symbol 1873(_root.委托任务界面) 的 web 等价 ──
        //   dungeonDetail   — 单副本详情（限制词条键名数组/可负担性/等级门/是否已接，只读）
        //   dungeonBriefing — 委托简报对话（接取前 get_conversation，去防剧透 gate，只读）
        //   dungeonEnter    — 进图（写：服务端硬门控 金钱/等级/K点 → 扣费+AddTask+委托界面进入关卡）
        //   openWebDungeon  — AS2 内部：NPC「获得任务」触发，发 panel_request 打开 web 副本视图（携 taskId）
        _root.gameCommands["dungeonDetail"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleDungeonDetail(params);
        };
        _root.gameCommands["dungeonBriefing"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleDungeonBriefing(params);
        };
        _root.gameCommands["dungeonEnter"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleDungeonEnter(params);
        };
        _root.gameCommands["openWebDungeon"] = function(params) {
            org.flashNight.arki.task.TaskPanelService.handleOpenWebDungeon(params);
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

    private static function itemIconName(itemName:String):String {
        var itemData:Object = ItemUtil.getRawItemData(itemName);
        if (itemData != undefined && itemData.icon != undefined && String(itemData.icon) != "") {
            return String(itemData.icon);
        }
        return itemName;
    }

    private static function parseItemStack(raw, kind:String):Object {
        var parts:Array = String(raw).split("#");
        var itemName:String = String(parts[0]);
        var count:Number = parts[1] != undefined ? Number(parts[1]) : 1;
        if (isNaN(count)) count = 1;
        var o:Object = { name: itemName, count: count, icon: itemIconName(itemName) };
        if (kind != undefined && kind != "") o.kind = kind;
        return o;
    }

    private static function parseItemStacks(src:Array, kind:String):Array {
        var out:Array = [];
        if (src == undefined || src.length == undefined) return out;
        for (var i:Number = 0; i < src.length; i++) {
            out.push(parseItemStack(src[i], kind));
        }
        return out;
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
            itemReqs = itemReqs.concat(parseItemStacks(taskData.finish_submit_items, "submit"));
        }
        if (taskData.finish_contain_items != undefined && taskData.finish_contain_items.length > 0) {
            itemReqs = itemReqs.concat(parseItemStacks(taskData.finish_contain_items, "contain"));
        }

        // 解析提交NPC
        var npcName:String = taskData.finish_npc != undefined ? String(taskData.finish_npc) : "";
        var npcHotspot:String = taskData.finish_npc_hotspot != undefined ? String(taskData.finish_npc_hotspot) : "";

        // 解析奖励 (rewards: ["itemName#quantity", ...])
        var rewards:Array = parseItemStacks(taskData.rewards, undefined);

        // 前往交付可达性：finish_npc → marker.hotspotId（MapTaskNpcRegistry）→ 可否直接跳转
        // （MapPanelService.canNavigateToHotspot：非战斗地图 + NAVIGATE_TARGETS 命中 + 所在组已解锁）。
        // 面板据此对「非远程但可前往」的任务把按钮变为可点的「前往交付」。注册/目录未就绪时回 false（优雅降级）。
        var finishNavigable:Boolean = false;
        if (npcName != "") {
            var navMarker:Object = org.flashNight.arki.map.MapTaskNpcRegistry.findMarker(npcName, npcHotspot);
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
            // 运行态完成判定（与 snapshot.satisfied 同口径 taskCompleteCheck）：随详情实时回，
            // 供 web 缓存命中后台复查纠正陈旧 satisfied（conditions 进度可无事件翻转完成态）
            satisfied: (_root.taskCompleteCheck(index) == true),
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
            iconName: itemIconName(itemName),
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
        var npcHotspot:String = (taskData != undefined && taskData.finish_npc_hotspot != undefined) ? String(taskData.finish_npc_hotspot) : "";
        if (npc == "") {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "npc_not_on_map" });
            return;
        }

        var marker:Object = org.flashNight.arki.map.MapTaskNpcRegistry.findMarker(npc, npcHotspot);
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
            var rawChar:String = (ln.char != undefined ? String(ln.char) : "");
            var charParts:Array = rawChar.split("#");
            var rawCharBase:String = (charParts.length > 0 ? String(charParts[0]) : "");
            var expression:String = (charParts.length > 1 && charParts[1] != undefined) ? String(charParts[1]) : "普通";
            var charBase = hasResolver ? _root.getDialogueSpecialString(rawCharBase) : rawCharBase;
            var portraitType:String = (rawCharBase == "$PC_CHAR" || charBase == "玩家" || charBase == "主角模板") ? "hero" : "npc";
            var line:Object = {
                speaker: (speaker != undefined ? String(speaker) : ""),
                sub: (sub != undefined ? String(sub) : ""),
                text: (ln.text != undefined ? String(ln.text) : ""),
                char: rawChar,
                charBase: (charBase != undefined ? String(charBase) : ""),
                expression: expression,
                portraitType: portraitType
            };
            if (ln.target != undefined) line.target = String(ln.target);
            if (ln.imageurl != undefined) line.imageurl = String(ln.imageurl);
            lines.push(line);
        }

        sendResponse({
            task: "task_response",
            callId: callId,
            success: true,
            which: which,
            lines: lines,
            heroPortrait: buildHeroPortraitState()
        });
    }

    private static function buildHeroPortraitState():Object {
        var hero:Object = undefined;
        if (_root.gameworld != undefined && _root.控制目标 != undefined) {
            hero = _root.gameworld[_root.控制目标];
        }

        var equipment:Object = {};
        var slots:Array = ["头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "长枪", "手枪", "手枪2", "刀"];
        for (var i:Number = 0; i < slots.length; i++) {
            var slot:String = String(slots[i]);
            var value = (hero != undefined) ? hero[slot] : undefined;
            if (value != undefined && value != "") equipment[slot] = String(value);
        }

        var appearance:Object = {};
        var face = (hero != undefined && hero.脸型 != undefined) ? hero.脸型 : _root.脸型;
        var hair = (hero != undefined && hero.发型 != undefined) ? hero.发型 : _root.发型;
        if (face != undefined && face != "") appearance["脸型"] = String(face);
        if (hair != undefined && hair != "") appearance["发型"] = String(hair);

        var keyMap:Object = {};
        if (hero != undefined && hero.hasDressup === true) {
            var holderFields:Array = ["面具", "身体", "上臂", "左下臂", "右下臂", "左手", "右手", "屁股", "左大腿", "右大腿", "小腿", "脚", "刀", "长枪", "手枪", "手枪2"];
            for (var j:Number = 0; j < holderFields.length; j++) {
                var field:String = String(holderFields[j]);
                var skinKey = hero[field];
                if (skinKey != undefined && skinKey != "") keyMap[field] = String(skinKey);
            }
        }

        var gender = (hero != undefined && hero.性别 != undefined) ? hero.性别 : _root.性别;
        return {
            gender: (gender != undefined && gender != "" ? String(gender) : "男"),
            equipment: equipment,
            appearance: appearance,
            keyMap: keyMap
        };
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

    // ═══════════════════════════════════════════════════════════
    // 副本任务（委托任务）面板 —— 旧 FLA Symbol 1873(_root.委托任务界面) 的 web 等价。
    //   入口严格 NPC 领取：NPC「获得任务」→ handleOpenWebDungeon 发 panel_request 带 taskId。
    //   权威数据一律读 TaskUtil.tasks[taskId]（不信 web 传来的金额/限制/难度）。
    // ═══════════════════════════════════════════════════════════

    // 副本任务 = chain "委托"（AS2 TaskUtil.tasks 的 chain 是原始 "委托" 字符串）
    private static function isDungeonTask(taskData:Object):Boolean {
        if (taskData == undefined) return false;
        var chain = taskData.chain;
        if (typeof chain == "string") return String(chain).split("#")[0] == "委托";
        if (chain instanceof Array) return String(chain[0]) == "委托";
        return false;
    }
    private static function dungeonStageName(taskData:Object):String {
        if (taskData == undefined || !(taskData.finish_requirements instanceof Array) || taskData.finish_requirements.length == 0) return "";
        return String(taskData.finish_requirements[0]).split("#")[0];
    }
    private static function dungeonStageDifficulty(taskData:Object):String {
        if (taskData == undefined || !(taskData.finish_requirements instanceof Array) || taskData.finish_requirements.length == 0) return "";
        var parts:Array = String(taskData.finish_requirements[0]).split("#");
        return parts.length > 1 ? String(parts[1]) : "";
    }
    private static function isTaskInTodo(taskId):Boolean {
        var todo:Array = _root.tasks_to_do;
        if (todo == undefined) return false;
        var idStr:String = String(taskId);
        for (var i:Number = 0; i < todo.length; i++) {
            if (todo[i] != undefined && String(todo[i].id) == idStr) return true;
        }
        return false;
    }
    private static function limitationArray(raw):Array {
        if (raw == undefined || raw == "" || typeof _root.配置数据为数组 != "function") return [];
        var arr:Array = _root.配置数据为数组(raw);
        return (arr == undefined || arr == null) ? [] : arr;
    }

    // ── dungeonDetail（只读）：单副本详情 + 运行态门控可视化 ──
    public static function handleDungeonDetail(params:Object):Void {
        var callId = params.callId;
        var taskData:Object = TaskUtil.tasks[params.taskId];
        if (!isDungeonTask(taskData)) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "not_dungeon_task" });
            return;
        }
        var stageName:String = dungeonStageName(taskData);
        var stageInfo:Object = (stageName != "") ? _root.StageInfoDict[stageName] : undefined;

        var hasChallenge:Boolean = (taskData.challenge != undefined && taskData.challenge != null);
        var challengeLimits:Array = (hasChallenge && (taskData.challenge.limitations instanceof Array)) ? taskData.challenge.limitations : [];

        var deposit:Number = taskData.deposit > 0 ? Number(taskData.deposit) : 0;
        var kDeposit:Number = taskData.Kdeposit > 0 ? Number(taskData.Kdeposit) : 0;
        var restrictedLevel:Number = taskData.restricted_level > 0 ? Number(taskData.restricted_level) : 1;

        sendResponse({
            task: "task_response",
            callId: callId,
            success: true,
            detail: {
                taskId: taskData.id,
                stageName: stageName,
                stageDifficulty: dungeonStageDifficulty(taskData),
                stageFound: (stageInfo != undefined),
                // 展示字段（让 web 副本视图单次 dungeonDetail 自洽，不依赖静态 catalog）
                title: String(TaskUtil.getTaskText(taskData.title)),
                description: String(TaskUtil.getTaskText(taskData.description)),
                npcName: String(taskData.get_npc != undefined ? taskData.get_npc : (taskData.finish_npc != undefined ? taskData.finish_npc : "")),
                rewards: parseItemStacks(taskData.rewards, undefined),
                imageurl: (taskData.imageurl != undefined ? String(taskData.imageurl) : ""),
                hasChallenge: hasChallenge,
                challengeDifficulty: hasChallenge ? String(taskData.challenge.difficulty) : "",
                normalLimits: (stageInfo != undefined) ? limitationArray(stageInfo.Limitation) : [],
                challengeLimits: challengeLimits,
                limitLevel: (stageInfo != undefined && stageInfo.LimitLevel != undefined) ? String(stageInfo.LimitLevel) : "",
                deposit: deposit,
                kDeposit: kDeposit,
                restrictedLevel: restrictedLevel,
                recommendedLevel: (taskData.recommended_level != undefined) ? String(taskData.recommended_level) : "",
                // 运行态门控可视化（web 禁用按钮仅 UX；真门控在 handleDungeonEnter）
                playerMoney: Number(_root.金钱),
                playerVCoin: Number(_root.虚拟币),
                playerLevel: Number(_root.等级),
                affordMoney: Number(_root.金钱) >= deposit,
                affordVCoin: (kDeposit <= 0) || (Number(_root.虚拟币) >= kDeposit),
                levelOk: Number(_root.等级) >= restrictedLevel,
                alreadyActive: isTaskInTodo(taskData.id)
            }
        });
    }

    // ── dungeonBriefing（只读）：委托简报对话 lines（接取前 get_conversation，无防剧透 gate）──
    public static function handleDungeonBriefing(params:Object):Void {
        var callId = params.callId;
        var taskData:Object = TaskUtil.tasks[params.taskId];
        if (!isDungeonTask(taskData)) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "not_dungeon_task" });
            return;
        }
        var conv = TaskUtil.getTaskText(taskData.get_conversation);
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
            var rawChar:String = (ln.char != undefined ? String(ln.char) : "");
            var charParts:Array = rawChar.split("#");
            var rawCharBase:String = (charParts.length > 0 ? String(charParts[0]) : "");
            var expression:String = (charParts.length > 1 && charParts[1] != undefined) ? String(charParts[1]) : "普通";
            var charBase = hasResolver ? _root.getDialogueSpecialString(rawCharBase) : rawCharBase;
            var portraitType:String = (rawCharBase == "$PC_CHAR" || charBase == "玩家" || charBase == "主角模板") ? "hero" : "npc";
            var line:Object = {
                speaker: (speaker != undefined ? String(speaker) : ""),
                sub: (sub != undefined ? String(sub) : ""),
                text: (ln.text != undefined ? String(ln.text) : ""),
                char: rawChar,
                charBase: (charBase != undefined ? String(charBase) : ""),
                expression: expression,
                portraitType: portraitType
            };
            if (ln.target != undefined) line.target = String(ln.target);
            if (ln.imageurl != undefined) line.imageurl = String(ln.imageurl);
            lines.push(line);
        }
        sendResponse({
            task: "task_response",
            callId: callId,
            success: true,
            lines: lines,
            heroPortrait: buildHeroPortraitState()
        });
    }

    // ── dungeonEnter（写）：服务端硬门控 + 扣费 + 进图（复刻 Symbol 1873 按钮+虚拟币支付）──
    public static function handleDungeonEnter(params:Object):Void {
        var callId = params.callId;
        var taskData:Object = TaskUtil.tasks[params.taskId];
        if (!isDungeonTask(taskData)) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "not_dungeon_task" });
            return;
        }
        var mode:String = (params.mode == "challenge") ? "challenge" : "normal";
        var hasChallenge:Boolean = (taskData.challenge != undefined && taskData.challenge != null);
        if (mode == "challenge" && !hasChallenge) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "no_challenge" });
            return;
        }

        // 关卡存在性（在任何状态写入前校验，避免扣费后进图失败）
        var stageName:String = dungeonStageName(taskData);
        if (stageName == "" || _root.StageInfoDict[stageName] == undefined) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "stage_not_found" });
            return;
        }

        var deposit:Number = taskData.deposit > 0 ? Number(taskData.deposit) : 0;
        var kDeposit:Number = taskData.Kdeposit > 0 ? Number(taskData.Kdeposit) : 0;
        var restrictedLevel:Number = taskData.restricted_level > 0 ? Number(taskData.restricted_level) : 1;

        // 服务端硬门控（复刻 Symbol 1873 按钮 :244-253 + 虚拟币支付 :83-148）
        if (Number(_root.金钱) < deposit) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "insufficient_money" });
            return;
        }
        if (Number(_root.等级) < restrictedLevel) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "insufficient_level" });
            return;
        }
        if (kDeposit > 0 && Number(_root.虚拟币) < kDeposit) {
            sendResponse({ task: "task_response", callId: callId, success: false, error: "insufficient_kpoint" });
            return;
        }

        // 扣费（与 虚拟币支付 同序：扣金钱契约金；K点路径再扣虚拟币）
        _root.金钱 -= deposit;
        if (kDeposit > 0) _root.虚拟币 -= kDeposit;
        if (typeof _root.获取虚拟币值 == "function") _root.获取虚拟币值();
        // ⚠ 扣费改写了 金钱/虚拟币（权威存档态），必须显式标脏。重进同一副本时 AddTask 命中
        //   已在进行的任务会 return false 且只在实际 push 后才 dirtyMark（通信_鸡蛋_任务系统.as:419-421），
        //   不在此处补标脏的话：重进扣费成功却不落盘 → 下次存档/读档费用回滚（外部审阅 P1b）。
        _root.存档系统.dirtyMark = true;

        // 接取任务
        _root.AddTask(taskData.id);

        // 进图：内联复刻 委托界面进入关卡（关卡系统_lsy_无限过图.as:33-55），显式读 StageInfo + 显式 _root 赋值。
        // ⚠ 不挂普通对象 ctx 调用原函数：该函数读裸名 当前关卡名/起点帧/淡出跳转帧，AVM1 仅当 this 是
        //   MovieClip（在 scope chain 上）才解析到实例属性；普通对象会误解析为 _root.* → 进图错帧。
        //   逻辑值与旧 clip 一致，权威读 StageInfoDict + TaskUtil.tasks（不重写经济/限制语义）。
        var enterDifficulty:String = (mode == "challenge") ? String(taskData.challenge.difficulty) : dungeonStageDifficulty(taskData);
        var si:Object = _root.StageInfoDict[stageName];
        _root.载入关卡数据(si.Type, si.url);
        _root.当前通关的关卡 = "";
        _root.当前关卡难度 = enterDifficulty ? enterDifficulty : _root.当前关卡难度;
        _root.难度等级 = _root.计算难度等级(_root.当前关卡难度);
        _root.当前关卡名 = si.Name;
        _root.场景进入位置名 = "出生地";
        _root.关卡类型 = si.Type;
        if (si.StartFrame) _root.关卡地图帧值 = si.StartFrame;
        var normalLimits:Array = limitationArray(si.Limitation);
        if (normalLimits.length > 0) _root.限制系统.openEntries(normalLimits);
        if (si.LimitLevel) _root.限制系统.addLimitLevel(si.LimitLevel);
        if (mode == "challenge" && (taskData.challenge.limitations instanceof Array) && taskData.challenge.limitations.length > 0) {
            _root.限制系统.openEntries(taskData.challenge.limitations);
        }
        if (_root.soundEffectManager != undefined && _root.soundEffectManager.stopBGMForTransition != undefined) {
            _root.soundEffectManager.stopBGMForTransition();
        }

        // 进图前关闭可能残留的旧对话框（复刻 Symbol 1873:100-101/132-133）：新 NPC 流程已不经
        // SetDialogue，但若有前置剧情对话框开着，fade-out 期间会露脸（场景转换 清除游戏世界组件 要等
        // 全黑才 关闭()）；这里先隐藏，与旧版"进图前 _root.对话框界面._visible = false"对齐，零成本兜底。
        if (_root.对话框界面 != undefined) _root.对话框界面._visible = false;

        // 先回包再触发淡出跳转（场景切换后 socket 仍在；web 收 entered 关面板）
        sendResponse({ task: "task_response", callId: callId, success: true, entered: true, mode: mode });
        _root.淡出动画.淡出跳转帧(si.FadeTransitionFrame);
    }

    // ── openWebDungeon（AS2 内部）：NPC「获得任务」触发，发 panel_request 打开 web 副本视图 ──
    public static function handleOpenWebDungeon(params:Object):Void {
        var taskId = (params != undefined) ? params.taskId : undefined;
        if (taskId == undefined) return;
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return;
        sendResponse({
            task: "panel_request",
            panel: "tasks",
            source: "npc_dungeon",
            initData: { view: "dungeon", taskId: taskId }
        });
    }
}
