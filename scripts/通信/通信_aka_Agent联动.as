// Agent 联动：不调用 _root.服务器；data/rag/sync_state.json 的 task_publish_version 与 _root.agent.last_task_publish_version（初始 0）比较，非战斗图轮询热更。

_root.agent = {};
_root.agent.npc_state_db_exists = false;
_root.agent.last_task_publish_version = null;
_root.agent.sync_poll_busy = false;
_root.agent.REL_SYNC_STATE = "data/rag/sync_state.json";
_root.agent.REL_NPC_STATE_DB = "data/rag/npc_state_db.json";
_root.agent.REL_LAUNCH_BAT = "data/rag/launch_cfn_rag.bat";
_root.agent.KEY_TASK_PUBLISH_VERSION = "task_publish_version";

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
        _root.重新加载任务数据(
            function():Void {
                r.last_task_publish_version = fileVer;
                _root.最上层发布文字提示("已接收终端任务数据！");
            },
            function():Void {
                r.last_task_publish_version = fileVer;
                _root.最上层发布文字提示("任务数据更新失败！");
            }
        );
    };
    lv.load(fullPath);
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
    var savePath:String = _root.savePath == undefined ? "" : String(_root.savePath);
    var sent:Boolean = _root.server.sendSocketMessage(
        org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "ragchat", "agent_console", [], [{name:"savePath", value:savePath}]
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
