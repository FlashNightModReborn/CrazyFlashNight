# 编码规范与文档注释模板

---

## 1. 命名原则

- **注释**：全部中文
- **class 文件**（引擎级）：英文命名（类名/方法名/变量名）
- **_root 挂载函数**（业务层）：中文命名，兼顾非编程背景协作者（如 `_root.发布消息(...)`）

---

## 2. ActionScript 2.0 命名约定（class 文件）

- **类名**：PascalCase — `BulletFactory`、`FrameTimer`
- **方法/变量**：camelCase — `updatePosition`、`createBullet`
- **常量**：UPPER_CASE — `MAX_HEALTH`、`DEFAULT_SPEED`
- **私有成员**：下划线前缀 — `_privateVar`、`_health`
- **接口**：`I` 前缀 — `IMusicEngine`、`IMovable`
- **包路径**：严格遵循 `org.flashNight.[子包].[模块]` 命名空间

## 3. 双轨开发策略

代码分为两条路径，遵循不同范式：

- **非热路径**（UI/功能/业务逻辑）：现代最佳实践——可读性优先、防御式编程、清晰抽象
- **热路径**（引擎级核心组件）：极限性能导向，四条原则：
  1. **契约大于防护** — 无运行时防御，调用方契约保证输入合法（AS2 无 JIT，每条指令都是解释执行开销）
  2. **可读性让位性能** — 位运算、宏注入、内联展开、StoreRegister 压行等（详见 [as2-performance.md](as2-performance.md)）
  3. **零 GC** — 对象复用/池化/预分配，阈值缓存模式（≤阈值保留，>阈值释放）
  4. **重入保护** — `_inUse` 标志 + `resetState()` 安全阀，重入时降级原生实现（参考 `TimSort.as`）

---

## 4. 代码组织

- 每个类一个文件，文件路径与包路径一致
- 测试目录与 TDD 工作流：详见 [testing-guide.md](testing-guide.md) §1 目录组织、§5 TDD 工作流约束
- 帧脚本按功能分区：展现/引擎/通信/逻辑

## 5. JSDoc 风格文档注释

注释风格参照 JavaScript 最佳实践，随项目学习深入仍在持续演进。**新增代码应跟随所在文件的现有风格**，不要为了统一而大面积改写历史注释。

### 要求
- 所有公开类和方法必须包含 JSDoc 风格注释（**中文撰写**）
- 包含 `@class`、`@param`、`@returns`、`@type` 等标签
- 复杂算法需要描述实现思路

## 6. XML 配置文件规范

编写规范与 XMLParser 隐式行为详见 [data-schemas.md](data-schemas.md) §2-§3。

## 7. C# Launcher 编码规范

> Guardian Launcher（`launcher/`）使用 C# 5 / .NET Framework 4.5 / MSBuild 4.0。

### 项目结构

```
launcher/src/
├── Bus/                   # 通信基础设施
│   ├── MessageRouter.cs   # JSON 消息路由（task 字段分发）
│   ├── XmlSocketServer.cs # XMLSocket TCP 服务器（快车道 + JSON 双通道）
│   ├── HttpApiServer.cs   # HTTP REST 接口（/status, /console, /logBatch 等）
│   ├── TaskRegistry.cs    # Task 注册表 — single source of truth
│   └── ...
├── Tasks/                 # Task 处理器
│   ├── FrameTask.cs       # 帧数据处理（快车道 HandleRaw + JSON 回退）
│   ├── GomokuTask.cs      # 五子棋 AI（异步，rapfi 引擎桥接）
│   └── ToastTask.cs       # UI toast 通知（fire-and-forget）
├── V8/V8Runtime.cs        # 持久化 V8 引擎（hit-number 渲染）
└── Guardian/              # WinForms UI、overlay、窗口管理
```

### 项目特有约定

- **Task 注册**：所有 task 必须通过 `TaskRegistry.RegisterAll()` 注册，不在 Program.cs 散装注册
- **Task 元数据**：每个 task 声明 transport/direction/httpCallable，`/status` 端点自动暴露
- **快车道 vs JSON**：高频消息（frame, hn_reset）走前缀协议绕过 JObject.Parse；低频消息走 MessageRouter JSON 路由
- **本地监听**：HTTP 和 XMLSocket 仅绑定 `localhost`
- **C# 5 语法限制**：无 string interpolation、无 null propagation、无 expression-bodied members
- **构建**：`launcher/build.ps1`（NuGet restore → MSBuild → copy DLLs）

## 8. 调试规范

详见 [as2-anti-hallucination.md](as2-anti-hallucination.md) §3「调试」子节。
