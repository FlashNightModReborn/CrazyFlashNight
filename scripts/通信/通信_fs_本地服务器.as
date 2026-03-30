// 通信_fs_本地服务器.as
// 初始化 ServerManager 单例，连接到 C# Guardian Launcher。
// 文件名"本地服务器"是历史遗留（原 Node.js Local Server 已迁移至 C# launcher）。
// 端口提取由 ServerManager.extractPorts() 在构造函数中完成，此处不再重复注入。

import org.flashNight.neur.Server.ServerManager;
import org.flashNight.neur.Event.Delegate;

// 获取 ServerManager 单例实例并存储为全局变量
_root.server = ServerManager.getInstance();

// 旧有的 _root.服务器 对象，保留兼容性
_root.服务器 = {};
_root.服务器.端口列表 = _root.server.portList;
_root.服务器.端口索引 = _root.server.portIndex;
_root.服务器.当前端口 = _root.server.currentPort;

// 使用包装函数而非委托，以支持多参数自动拼接功能(类似 _root.发布消息)
_root.服务器.发布服务器消息 = function() {
    var msg:String = "";
    for (var i = 0; i < arguments.length; i++) {
        if (i > 0) msg += " ";
        msg += arguments[i];
    }
    _root.server.sendServerMessage(msg);
};
_root.服务器.获得可用端口 = Delegate.create(_root.server, _root.server.getAvailablePort);

// 立即发送：绕过帧缓冲，每条消息独立 HTTP 请求，冻结前的检查点也能送达
_root.服务器.立即发送 = function() {
    var msg:String = "";
    for (var i = 0; i < arguments.length; i++) {
        if (i > 0) msg += " ";
        msg += arguments[i];
    }
    _root.server.sendImmediate(msg);
};
