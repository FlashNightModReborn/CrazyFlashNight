import org.flashNight.neur.Server.ServerManager;
import org.flashNight.neur.Event.Delegate;

// Step 1: 获取ServerManager单例实例并存储为全局变量
_root.server = ServerManager.getInstance();

// Step 2: 提取四位和五位端口号到端口列表中
var eyeOf119:String = _root.闪客之夜.toString();
for (var i:Number = 0; i <= eyeOf119.length - 4; i++) {
    _root.server.portList.push(Number(eyeOf119.substring(i, i + 4)));
}
for (var j:Number = 0; j <= eyeOf119.length - 5; j++) {
    _root.server.portList.push(Number(eyeOf119.substring(j, j + 5)));
}

// 旧有的 _root.服务器 对象，保留兼容性
_root.服务器 = {};
_root.服务器.端口列表 = _root.server.portList;    // 重定向到 ServerManager 的 portList
_root.服务器.端口索引 = _root.server.portIndex;    // 重定向到 ServerManager 的 portIndex
_root.服务器.当前端口 = _root.server.currentPort;  // 重定向到 ServerManager 的 currentPort

// Step 3: 保留原有的函数接口，通过调用新的ServerManager来实现
_root.服务器.发布服务器消息 = Delegate.create(_root.server, _root.server.sendServerMessage);
_root.服务器.获得可用端口 = Delegate.create(_root.server, _root.server.getAvailablePort);


// 发送消息，通过旧接口
_root.服务器.发布服务器消息("This is a test message.");
