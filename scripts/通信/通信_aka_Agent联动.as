// Agent 联动：不调用 _root.服务器；data/rag/sync_state.json 的 task_publish_version 与 _root.agent.last_task_publish_version（初始 0）比较，非战斗图轮询热更。
import org.flashNight.gesh.path.*;

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
    var fullPath:String = PathManager.resolvePath(_root.agent.REL_NPC_STATE_DB);
    if (fullPath == null) {
        return;
    }
    var lv:LoadVars = new LoadVars();
    var self:Object = _root.agent;
    lv.onData = function(raw:String):Void {
        if (raw != undefined && raw.length > 0) {
            self.npc_state_db_exists = true;
        } else {
            self.npc_state_db_exists = false;
        }
        _root.agent.注册同步轮询();
    };
    lv.load(fullPath);
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
    // 退出全屏模式，确保浏览器窗口能正常弹出
    fscommand("fullscreen", "false");
    // 使用fscommand执行fscommand目录下的代理启动器
    // fscommand("exec")只能在独立Flash Player中工作，且只能执行fscommand子目录中的文件
    fscommand("exec", "launch_rag.bat");
};

_root.agent.检测npc状态库文件();
