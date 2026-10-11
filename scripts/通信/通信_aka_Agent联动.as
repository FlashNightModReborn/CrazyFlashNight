// Agent 联动：不调用 _root.服务器；data/rag/sync_state.json 的 task_publish_version 与 _root.agent.last_task_publish_version（初始 0）比较，非战斗图轮询热更。

_root.agent = {};
_root.agent.npc_state_db_exists = false;
_root.agent.last_task_publish_version = null;
_root.agent.sync_poll_busy = false;
_root.agent.sync_apply_busy = false;
// 宿主已换任务内容而游戏侧重载未落地时为 true；下一轮无条件整目录重载补齐。
_root.agent.task_reload_owed = false;
_root.agent.failed_publish_version = null;
_root.agent.REL_SYNC_STATE = "data/rag/sync_state.json";
_root.agent.REL_NPC_STATE_DB = "data/rag/npc_state_db.json";
_root.agent.REL_LAUNCH_BAT = "data/rag/launch_cfn_rag.bat";
_root.agent.KEY_TASK_PUBLISH_VERSION = "task_publish_version";
// 槽位目录同步（G2-3②）：已对齐槽位与防重入。null＝从未对齐。
_root.agent.slot_catalog_aligned = null;
_root.agent.slot_catalog_busy = false;

_root.agent.读取任务发布版本号 = function(raw:String):Number {
    if (raw == undefined || raw.length == 0) {
        return 0;
    }
    var j:LiteJSON = new LiteJSON();
    var obj:Object = j.parse(raw);
    if (obj == undefined || obj == null || typeof obj != "object") {
        return 0;
    }
    var v = obj[_root.agent.KEY_TASK_PUBLISH_VERSION];
    if (v == undefined) {
        return 0;
    }
    var n:Number = Number(v);
    if (isNaN(n)) {
        return 0;
    }
    return n;
};

_root.agent.检测npc状态库文件 = function():Void {
    PathManager.initialize(null);
    if (!PathManager.isEnvironmentValid()) {
        return;
    }
    var self:Object = _root.agent;
    var checkFile:Function;
    // 先检测 npc_state_db.json，不存在则检测 sync_state.json
    checkFile = function(relPath:String, onDone:Function):Void {
        var fullPath:String = PathManager.resolvePath(relPath);
        if (fullPath == null) {
            onDone(false);
            return;
        }
        var lv:LoadVars = new LoadVars();
        lv.onData = function(raw:String):Void {
            var exists:Boolean = (raw != undefined && raw.length > 0);
            onDone(exists);
        };
        lv.load(fullPath);
    };
    // 第一个回调：检测 npc_state_db.json 结果
    var onFirstCheck:Function = function(exists:Boolean):Void {
        if (exists) {
            self.npc_state_db_exists = true;
            _root.agent.注册同步轮询();
        } else {
            // 第一个不存在，检测第二个
            checkFile(self.REL_SYNC_STATE, onSecondCheck);
        }
    };
    // 第二个回调：检测 sync_state.json 结果
    var onSecondCheck:Function = function(exists:Boolean):Void {
        self.npc_state_db_exists = exists;
        _root.agent.注册同步轮询();
    };
    checkFile(self.REL_NPC_STATE_DB, onFirstCheck);
};

_root.agent.轮询同步状态 = function():Void {
    if (_root.当前为战斗地图 == true) {
        return;
    }
    if (_root._taskReloadBusy == true) {
        return;
    }
    if (_root.agent.sync_poll_busy == true) {
        return;
    }
    if (_root.agent.sync_apply_busy == true) {
        return;
    }
    // 槽位对齐检查（G2-3②）：当前槽位与宿主侧目录投影未对齐时先补对齐，本轮不再进行版本轮询。
    var slot:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
    if (slot != "" && _root.agent.slot_catalog_aligned !== slot) {
        _root.agent.请求槽位目录同步();
        return;
    }
    if (!PathManager.isEnvironmentValid()) {
        return;
    }
    var fullPath:String = PathManager.resolvePath(_root.agent.REL_SYNC_STATE);
    if (fullPath == null) {
        return;
    }
    // _root.发布消息("正在轮询……");
    _root.agent.sync_poll_busy = true;
    var lv:LoadVars = new LoadVars();
    var r:Object = _root.agent;
    lv.onData = function(raw:String):Void {
        r.sync_poll_busy = false;
        if (raw == undefined || raw.length == 0) {
            r.last_task_publish_version = 0;
            return;
        }
        var fileVer:Number = r.读取任务发布版本号(raw);
        if (isNaN(fileVer)) {
            r.last_task_publish_version = 0;
            return;
        }
        if (r.last_task_publish_version == null) {
            r.last_task_publish_version = fileVer;
            return;
        }
        if (fileVer == r.last_task_publish_version) {
            return;
        }
        _root.发布消息("正在接收终端任务数据……");
        _root.agent.同步任务热更新(fileVer);
    };
    lv.load(fullPath);
};

// 任务发布版本变化后的收敛流程。宿主是变更权威：由它重读任务目录、判定哪些源文件真的变了，
// 游戏侧只按清单增量重载，最后原子提交宿主回传的新握手（内容摘要 + 会话令牌）。
// finish 与 giveUp 合计恰好执行一次，绝不把桥留在提交窗口里；版本号只在真正收敛后推进。
_root.agent.同步任务热更新 = function(fileVer:Number):Void {
    var r:Object = _root.agent;
    if (r.sync_apply_busy == true || _root._taskReloadBusy == true || r.slot_catalog_busy == true) {
        return;
    }
    r.sync_apply_busy = true;
    var done:Boolean = false;

    function finish():Void {
        if (done) {
            return;
        }
        done = true;
        r.sync_apply_busy = false;
        r.task_reload_owed = false;
        org.flashNight.arki.map.MapDomainBridge.commitTaskSync();
        r.last_task_publish_version = fileVer;
        _root.最上层发布文字提示("已接收终端任务数据！");
    }

    // 宿主已换内容但游戏侧没跟上时，欠账标记让下一轮无条件重载到磁盘真值；
    // 版本号不推进，所以本轮不算同步完成，失败提示同一版本只出一次。
    function giveUp(reason:String):Void {
        if (done) {
            return;
        }
        done = true;
        r.sync_apply_busy = false;
        _root.发布消息("任务热更新未收敛：" + reason);
        if (r.failed_publish_version != fileVer) {
            r.failed_publish_version = fileVer;
            _root.最上层发布文字提示("任务数据更新失败！");
        }
    }

    function reload(changedFiles:Array):Void {
        if (_root._taskReloadBusy == true) {
            giveUp("任务重载已在执行中");
            return;
        }
        _root.重新加载任务数据(
            function():Void {
                finish();
            },
            function():Void {
                if (changedFiles == null) {
                    giveUp("任务数据重载失败");
                    return;
                }
                reload(null);
            },
            changedFiles
        );
    }

    org.flashNight.arki.map.MapDomainBridge.syncTasks(function(ok:Boolean, error:String, result:Object):Void {
        if (ok != true) {
            giveUp(String(error));
            return;
        }
        // 欠账优先：上一轮宿主已换内容而游戏侧没落地，这轮无论宿主怎么答都整目录重载。
        if (r.task_reload_owed == true) {
            reload(null);
            return;
        }
        if (result == undefined || result.changed != true) {
            finish();
            return;
        }
        r.task_reload_owed = true;
        reload((result.listChanged == true || !(result.changedFiles instanceof Array)) ? null : result.changedFiles);
    });
};

// G2-1 载荷投影：ragchat initData 与 rag_bind_refresh 共用的三键形状。
// Host 白名单（LauncherCommandRouter.TryParseRagChatProjection）只收 savePath/character/progress，
// 且 tasks_finished 必须是整数数组、task_chains_progress 必须是对象——违反任何一条整包被拒。
// 数据来源：_root 存档键（角色名；tasks_finished 是「任务id→完成次数」表，投影为完成 id 的整数数组）。
_root.agent.构建存档投影 = function(savePath:String):Object {
    var character:Object = {
        name: (_root.角色名 == undefined || _root.角色名 == null) ? "" : String(_root.角色名)
    };
    var finished:Array = [];
    var finishedMap:Object = _root.tasks_finished;
    if (finishedMap != undefined && finishedMap != null) {
        for (var taskKey in finishedMap) {
            var id:Number = Number(taskKey);
            var count:Number = Number(finishedMap[taskKey]);
            if (!isFinite(id) || id != Math.floor(id) || id < 0) continue;
            if (!isFinite(count) || count < 1) continue;
            finished.push(id);
        }
    }
    var chains:Object = {};
    var chainMap:Object = _root.task_chains_progress;
    if (chainMap != undefined && chainMap != null) {
        for (var chain in chainMap) {
            var progress:Number = Number(chainMap[chain]);
            if (!isFinite(progress)) continue;
            chains[chain] = progress;
        }
    }
    return {
        savePath: savePath,
        character: character,
        progress: {tasks_finished: finished, task_chains_progress: chains}
    };
};

// G2-3③④：durable 落盘与任务完成时的投影刷新出口。经 Host 转发 rag_bind_refresh，
// exe 不在线由 Host 侧静默跳过；本函数不弹任何提示（best-effort）。
_root.agent.推送绑定刷新 = function():Void {
    if (_root.server == undefined || _root.server == null) return;
    if (typeof _root.server.sendTaskToNode != "function") return;
    if (_root.server.isSocketConnected !== true) return;
    var savePath:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
    if (savePath == "") return;
    _root.server.sendTaskToNode("rag_bind_refresh", _root.agent.构建存档投影(savePath), null);
};

// G2-3②：换槽位后的任务目录对齐。宿主按新 savePath 重读覆盖层并回变化清单，
// 游戏侧只重载真正变化的文件（silent=true 不弹提示、不推进任务发布版本号）。
// 失败 trace-only；下一轮 7 秒轮询的对齐检查会重试，task_reload_owed 防止
// 「宿主已换内容而游戏侧没落地」被一个 changed=false 的答复抹掉。
_root.agent.请求槽位目录同步 = function():Void {
    var r:Object = _root.agent;
    var slot:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
    if (slot == "" || r.slot_catalog_busy == true) return;
    if (r.sync_apply_busy == true || _root._taskReloadBusy == true) return;
    if (r.slot_catalog_aligned === slot) return;
    r.slot_catalog_busy = true;
    var done:Boolean = false;

    function finish():Void {
        if (done) return;
        done = true;
        r.slot_catalog_busy = false;
        r.task_reload_owed = false;
        org.flashNight.arki.map.MapDomainBridge.commitTaskSync();
        r.slot_catalog_aligned = slot;
    }

    function giveUp(reason:String):Void {
        if (done) return;
        done = true;
        r.slot_catalog_busy = false;
        trace("[Agent] 槽位目录同步未收敛：" + reason);
    }

    function reload(changedFiles:Array):Void {
        if (_root._taskReloadBusy == true) {
            giveUp("任务重载已在执行中");
            return;
        }
        _root.重新加载任务数据(
            function():Void {
                finish();
            },
            function():Void {
                if (changedFiles == null) {
                    giveUp("任务数据重载失败");
                    return;
                }
                reload(null);
            },
            changedFiles,
            true
        );
    }

    org.flashNight.arki.map.MapDomainBridge.syncTasks(function(ok:Boolean, error:String, result:Object):Void {
        if (ok != true) {
            giveUp(String(error));
            return;
        }
        // 欠账优先：上一轮宿主已换内容而游戏侧没落地，这轮无论宿主怎么答都整目录重载。
        if (r.task_reload_owed == true) {
            reload(null);
            return;
        }
        if (result == undefined || result.changed != true) {
            finish();
            return;
        }
        r.task_reload_owed = true;
        reload((result.listChanged == true || !(result.changedFiles instanceof Array)) ? null : result.changedFiles);
    });
};

// 读档完成点（通信_fs_bootstrap / SaveManager.replacePlayerContext）：
// 换槽位＝向终端重推绑定 + 任务目录按新槽位对齐，两者都 best-effort。
_root.agent.槽位已切换 = function():Void {
    _root.agent.推送绑定刷新();
    _root.agent.请求槽位目录同步();
};

_root.agent.注册同步轮询 = function():Void {
    if(_root.agent.npc_state_db_exists){
        _root.帧计时器.添加循环任务(_root.agent.轮询同步状态, 7000);
    }
};
_root.agent.启动外部RAG工具 = function():Void {
    _root.最上层发布文字提示("正在启动通讯终端，请稍后……");
    // 游戏内嵌集成（阶段一）：改走 Host panel_request —— Host 负责确保 cfn-rag 就绪并把
    // 当前存档绑定给终端，随后以外层 ragchat 面板 iframe 承载终端页面；就绪/绑定失败由
    // Host 经 gameCommand ragChatUnavailable 回 toast，本函数不再直接拉起外部浏览器窗口。
    if (typeof _root.server.sendSocketMessage != "function") {
        _root.最上层发布文字提示("通讯终端暂不可用，请稍后重试。");
        return;
    }
    var savePath:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
    var initFields:Array = [{name:"savePath", value:savePath}];
    if (savePath != "") {
        // G2-1：非空槽位才带全量投影；raw=true 让 PanelRequestEnvelope 原样内联
        // stringifySafe 的输出（对象投影不能走字符串字段的二次转义）。
        var projection:Object = _root.agent.构建存档投影(savePath);
        var json:LiteJSON = new LiteJSON();
        initFields.push({name:"character", value:json.stringifySafe(projection.character), raw:true});
        initFields.push({name:"progress", value:json.stringifySafe(projection.progress), raw:true});
    }
    var sent:Boolean = _root.server.sendSocketMessage(
        org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "ragchat", "agent_console", [], initFields
        )
    );
    if (!sent) {
        _root.最上层发布文字提示("通讯终端暂不可用，请稍后重试。");
    }
    // 旧外部拉起路径（阶段五删除）：
    // fscommand("fullscreen", "false");
    // fscommand("exec", "launch_rag.bat");
};

// Host→AS2 失败回执：面板未开（或前置就绪失败）时给出明确提示；纯提示，不写任何游戏状态。
if (_root.gameCommands == undefined) _root.gameCommands = {};
_root.gameCommands["ragChatUnavailable"] = function(params:Object):Void {
    var message:String = (params == undefined || params.message == undefined) ? "" : String(params.message);
    if (message == "") {
        message = "通讯终端暂不可用，请稍后重试。";
    }
    _root.最上层发布文字提示(message);
};

_root.agent.检测npc状态库文件();
