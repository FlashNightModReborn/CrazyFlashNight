# 编码规范与文档注释模板

> 本项目的编码约定，涵盖 AS2、Node.js、XML 和 PowerShell。

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

代码分为两种路径，遵循完全不同的开发范式：

### 非热路径（UI、功能、业务逻辑）
- 按**现代软件开发最佳实践**管理
- 优先可读性、可维护性、清晰的抽象
- 正常的错误处理和防御式编程

### 热路径（引擎级核心组件）
遵循四条极限性能原则：

1. **契约大于防护**
   - 不做运行时防御检查，通过调用方契约保证输入合法
   - 尽可能通过形式化证明确认在契约下是安全的
   - AS2 VM 无 JIT，每条防御指令都是实打实的解释执行开销

2. **允许牺牲可读性换取极限性能**
   - 位运算替代常规算术
   - 宏注入（`#include`）实现编译期代码生成
   - 边界特性利用（如 NaN 行为、原型链特性）
   - 大范围内联展开与代码重复（优于函数调用开销）
   - 副作用语句压行触发 VM 寄存器优化（参阅 `naki/Sort/evalorder.md`）
   - 性能依据参阅 `agentsDoc/as2-performance.md`

3. **零 GC 导向**
   - 热路径零内存分配，避免触发 Flash GC 暂停导致掉帧
   - 对象复用、池化、预分配；避免临时字符串拼接和临时对象创建
   - **阈值缓存模式**（参考 `TimSort._workspace`）：静态数组跨调用复用；清理时 ≤ 阈值保留复用，> 阈值释放防引用泄漏

4. **重入保护与安全降级**（适用于使用静态缓存的热路径组件）
   - `_inUse` 标志防止重入破坏共享状态；检测到重入时**降级**到原生实现并 `trace()` 警告
   - `resetState()` 安全阀：帧初始化时调用，防止异常导致 `_inUse` 永久锁死
   - 参考实现：`TimSort.as`

---

## 4. 代码组织

- 每个类一个文件，文件路径与包路径一致
- 测试文件放在对应目录的 `test/` 子目录下
- 帧脚本按功能分区：展现/引擎/通信/逻辑

## 5. JSDoc 风格文档注释

注释风格参照 JavaScript 最佳实践，随项目学习深入仍在持续演进。**新增代码应跟随所在文件的现有风格**，不要为了统一而大面积改写历史注释。

### 要求
- 所有公开类和方法必须包含 JSDoc 风格注释（**中文撰写**）
- 包含 `@class`、`@param`、`@returns`、`@type` 等标签
- 复杂算法需要描述实现思路

## 6. XML 配置文件规范

- 4空格缩进，属性值双引号，中文注释说明参数用途
- **注释保护**：代码处理 XML 时必须检查中文注释是否被保留（许多解析器/序列化器默认丢弃注释）
- XMLParser 隐式行为（同名节点合并、自动类型转换）及对策详见 [agentsDoc/data-schemas.md](data-schemas.md)

## 7. Node.js 编码规范

> 遵循现代 JS 最佳实践（`const` 优先、箭头函数、解构赋值等）。以下为**项目特有约定**。

### 项目结构

```
tools/Local Server/
├── server.js              # 入口：HTTP + XMLSocket 启动
├── routes/                # Express 路由定义（只做请求分发）
├── controllers/           # 业务逻辑处理器（每种 task 一个文件）
├── services/              # 基础服务（socketServer 等）
└── package.json
```

### 项目特有约定

- **统一响应格式**：`{ success: true/false, result/error }`
- **沙箱执行**：eval 任务使用 VM2，禁止直接 `eval()`
- **本地监听**：服务仅绑定 `localhost`
- **日志**：winston 结构化日志，包含 task 类型、端口号等上下文
- **依赖管理**：`node_modules/` 不入库，部署前 `npm install`；新增依赖前评估必要性

## 8. 调试规范

详见 [as2-anti-hallucination.md](as2-anti-hallucination.md) §3 调试章节。
