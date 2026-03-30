# 项目技术架构总览

---

## 1. 架构概览

```
┌─────────────────────────────────────┐
│     Flash Player (AS2 客户端)         │
│  ┌─────────┐  ┌──────────────┐      │
│  │ 主 SWF   │  │ 子 SWF/小游戏│      │
│  │(游戏逻辑)│←→│  (hana包)    │      │
│  └────┬─────┘  └──────────────┘      │
│       │ XMLSocket (快车道 F/R + JSON)  │
└───────┼──────────────────────────────┘
        │
┌───────┼──────────────────────────────┐
│  C# Guardian Launcher                │
│  ┌────┴──────┐   ┌──────────────┐    │
│  │XmlSocket  │   │  HTTP API    │    │
│  │ 快车道    │   │ /status      │    │
│  │ F→Frame   │   │ /console     │    │
│  │ R→Reset   │   │ /task        │    │
│  │ JSON→路由 │   │ /logBatch    │    │
│  └───────────┘   └──────────────┘    │
│  ┌──────────────────────────────┐    │
│  │ TaskRegistry (single source) │    │
│  │ toast | gomoku_eval          │    │
│  │ V8Runtime (hit-number)       │    │
│  └──────────────────────────────┘    │
└──────────────────────────────────────┘
        ↑
  cfn-cli.sh / .ps1（外部 CLI 工具）
```

---

## 2. 模块通信流程

### 子 SWF 加载与通信

子 SWF 不作为独立沙箱运行，而是以 **资源注入** 方式集成到主文件中（本质上被视为一种资源文件）：

1. **链接导出**：子 SWF 内的影片剪辑通过 AS 链接（Linkage）导出为可实例化的符号
2. **加载注入**：主 FLA 工程中可显式设置外部 SWF 作为共享库导入（Runtime Shared Library），也可通过 `loadMovie` / `attachMovie` 在运行时加载；两种方式均将子 SWF 库中的链接符号注入到主文件的运行时环境
3. **主文件范围运行**：实例化的影片剪辑在主文件的作用域内运行，可直接访问 `_root`、全局变量和主文件的类库，无跨 SWF 沙箱隔离

> 这意味着子 SWF 与主文件之间不存在显式的消息协议，而是共享同一运行时上下文，直接通过属性和方法调用通信。

### AS2 ↔ C# Guardian Launcher 通信
- 传输：XMLSocket（TCP 长连接，双通道：前缀快车道 + JSON 路由）+ HTTP（辅助通道）
- 端口发现：HTTP `POST /testConnection` 探测 → `GET /getSocketPort` 获取 socket 端口
- 消息分帧：`\0` 终止符
- Task 注册表：`launcher/src/Bus/TaskRegistry.cs`（single source of truth）
- 状态查询：`GET /status`（返回 task 清单 + 连接状态）
- 客户端入口：`org.flashNight.neur.Server.ServerManager`（单例，5 状态 FSM）
- 初始化脚本：`scripts/通信/通信_fs_本地服务器.as`

#### 连接状态机（帧驱动，无 setTimeout/setInterval）

```
S_DISCONNECTED(0)      等待重连延迟（150帧≈5s），retryCount < 5
  │
  v
S_HTTP_PROBING(1)      POST /testConnection → portList 轮询
  │ success → currentPort = port
  v
S_FETCHING_PORT(2)     GET /getSocketPort → socketPort
  │ success → socketPort = port
  v
S_SOCKET_CONNECTING(3) XMLSocket.connect(localhost, socketPort)
  │ success
  v
S_CONNECTED(4)         业务就绪
  │ onSocketClose
  v
S_FETCHING_PORT(2)     关键：重新发现端口（launcher 可能重启在不同端口）
```

- 端口候选列表从 `_root.闪客之夜`（数字种子 "1192433993"）提取 4/5 位有效端口
- 失败路径：任意层失败 → `retryCount++` → S_DISCONNECTED → 等待 delay → 重试
- 所有状态转换由 `transitionTo()` 统一管理，每个异步回调先检查当前状态是否匹配

#### 消息协议

XMLSocket 消息以 `\0` 终止符分帧，采用**双通道分发**：

##### 快车道（前缀协议，绕过 JSON 解析）

高频消息使用固定前缀，由 `XmlSocketServer.HandleMessage` 首字节判断直达处理器：

| 前缀 | 格式 | 处理器 | 频率 |
|------|------|--------|------|
| `F` | `F{cam}\x01{hn}` | `FrameTask.HandleRaw(cam, hn)` | 每帧（30fps） |
| `R` | `R`（无负载） | `FrameTask.HandleReset()` | 场景切换 |

- cam 格式：`gw._x|gw._y|scale`（管道符分隔）
- `\x01`(SOH) 分隔 cam 与 hn（两者内容只含 `|`;数字文本）
- hn 格式：`value|x|y|packed|efText|efEmoji|lifeSteal|shieldAbsorb;...`（分号分条目）

##### 通用路由（JSON）

非快车道消息经 `MessageRouter.ProcessMessage` 路由（JObject.Parse + task 字段分发）：

**客户端 → 服务器**：
```json
{ "task": "toast|gomoku_eval", "payload": ..., "callId": ... }
```

**服务器 → 客户端**：
```json
{ "success": true, "result": ... }
{ "success": false, "error": "错误信息" }
```

| 任务类型 | 处理器 | 类型 | 用途 |
|---------|--------|------|------|
| `toast` | `ToastTask.cs` | sync | UI toast 通知（fire-and-forget） |
| `gomoku_eval` | `GomokuTask.cs` | async | 五子棋 AI 评估（rapfi 引擎，callId 回调） |
| `console` | 服务器推送 → AS2 | push | 远程控制台命令（HTTP /console → XMLSocket） |
| `console_result` | 事件回执 | event | AS2 执行结果回传（触发 OnConsoleResult 事件） |

**HTTP 辅助通道**：`POST /logBatch`（调试日志批量上报，每帧最多一次，`ServerManager.sendMessageBuffer()` 管理缓冲区）

### XML 数据加载

详见 [data-schemas.md](data-schemas.md)。

