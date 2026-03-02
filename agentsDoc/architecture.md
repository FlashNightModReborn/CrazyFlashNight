# 项目技术架构总览

> 闪客快打7佣兵帝国 MOD 的整体技术架构与模块间关系。

---

## 1. 架构概览

```
┌─────────────────────────────────┐
│     Flash Player (AS2 客户端)     │
│  ┌─────────┐  ┌──────────────┐  │
│  │ 主 SWF   │  │ 子 SWF/小游戏│  │
│  │(游戏逻辑)│←→│  (hana包)    │  │
│  └────┬─────┘  └──────────────┘  │
│       │ XMLSocket                 │
└───────┼───────────────────────────┘
        │
┌───────┼───────────────────────────┐
│  Node.js 本地服务器               │
│  ┌────┴─────┐  ┌──────────────┐  │
│  │XMLSocket │  │  HTTP/REST   │  │
│  │ 服务     │  │   服务       │  │
│  └──────────┘  └──────────────┘  │
│  ┌──────────────────────────────┐│
│  │ 任务处理器(eval/regex/音频等)  ││
│  └──────────────────────────────┘│
└───────────────────────────────────┘
```

---

## 2. 模块通信流程

### 子 SWF 加载与通信

子 SWF 不作为独立沙箱运行，而是以 **资源注入** 方式集成到主文件中（本质上被视为一种资源文件）：

1. **链接导出**：子 SWF 内的影片剪辑通过 AS 链接（Linkage）导出为可实例化的符号
2. **加载注入**：主 FLA 工程中可显式设置外部 SWF 作为共享库导入（Runtime Shared Library），也可通过 `loadMovie` / `attachMovie` 在运行时加载；两种方式均将子 SWF 库中的链接符号注入到主文件的运行时环境
3. **主文件范围运行**：实例化的影片剪辑在主文件的作用域内运行，可直接访问 `_root`、全局变量和主文件的类库，无跨 SWF 沙箱隔离

> 这意味着子 SWF 与主文件之间不存在显式的消息协议，而是共享同一运行时上下文，直接通过属性和方法调用通信。

### AS2 ↔ Node.js 通信
- 协议：XMLSocket（TCP 长连接）+ HTTP（辅助通道）
- 端口：通过 HTTP `GET /getSocketPort` 获取
- 消息格式：JSON over XMLSocket（`\0` 终止符分帧）
- 详细文档：`tools/Local Server/server.md`
- 客户端入口：`org.flashNight.neur.Server.ServerManager`（单例）
- 初始化脚本：`scripts/通信/通信_fs_本地服务器.as`

#### 连接建立流程

```
1. 端口发现：从 _root.闪客之夜 提取候选端口列表
2. HTTP 探测：POST /testConnection → status=success
3. 获取 Socket 端口：GET /getSocketPort → socketPort=9999
4. XMLSocket 连接：连接 localhost:{socketPort}
5. 断线重连：最多 5 次，间隔 300 帧（≈10s）
```

#### 消息协议

**客户端 → 服务器**（XMLSocket，JSON + `\0`）：
```json
{ "task": "eval|regex|computation|audio", "payload": ..., "extra": ... }
```

**服务器 → 客户端**：
```json
{ "success": true, "result": ... }
{ "success": false, "error": "错误信息" }
```

| 任务类型 | 处理器 | 用途 |
|---------|--------|------|
| `eval` | `controllers/evalTask.js` | VM2 沙箱执行 JavaScript 表达式 |
| `regex` | `controllers/regexTask.js` | 正则匹配（AS2 正则能力有限，委托服务端） |
| `computation` | `controllers/computationTask.js` | 数值计算任务 |
| `audio` | `controllers/audioTask.js` | 音频控制（play/pause/stop/setVolume） |

**HTTP 辅助通道**（调试日志批量上报）：
```
POST /logBatch  →  frame={帧号}&messages={msg1|msg2|msg3}
```
每帧最多发送一次，消息以 `|` 分隔，由 `ServerManager.sendMessageBuffer()` 管理缓冲区。

### XML 数据加载

数据加载体系（XMLParser 隐式行为、数据目录结构、专用加载器列表、使用模式）详见 [agentsDoc/data-schemas.md](data-schemas.md)。

---

## 3. 代码组织层次

<!-- TODO: 补充各层之间的依赖关系图 -->

| 层次 | 位置 | 职责 |
|------|------|------|
| 帧脚本层 | `scripts/展现/`、`scripts/引擎/`、`scripts/逻辑/`、`scripts/通信/` | 运行在时间轴上的脚本，直接操作舞台 |
| 类库层 | `scripts/类定义/org/flashNight/` | 七大包：核心逻辑与工具的面向对象实现 |
| FLA 资源层 | `flashswf/` | Flash 可视化资源与元件，需 Flash CS6 编辑 |
| 数据层 | `data/`、`config/` | XML 配置与游戏数据，可直接修改 |
| 服务端 | `tools/Local Server/` | Node.js 服务，为 AS2 客户端提供扩展能力 |

---

## 4. 关键技术决策记录

<!-- TODO: 在自优化环节中记录重要的架构决策及其原因 -->

> 此节在自优化环节中逐步填充。
