# 编码规范与文档注释模板

> 本项目的编码约定，涵盖 AS2、Node.js、XML 和 PowerShell。

---

## 1. 三大命名原则

### 原则一：注释全部中文
- 所有代码注释（包括 class 文件和帧脚本）**必须使用中文**，方便所有协作者查看

### 原则二：class 文件（引擎级）— 英文命名
- class 文件视作**引擎级代码**，不考虑无编程背景的协作者
- 类名、方法名、变量名尽可能使用英文
- 在不涉及外部中文耦合的情况下，保持英文规范

### 原则三：_root 挂载函数（业务层）— 中文命名
- `_root` 上的函数是**功能业务层**，需兼顾无编程背景的协作者
- 函数名、参数名尽可能使用中文，保证其他协作者可以无障碍阅读并自行修改
- 例：`_root.发布消息(...)`、`_root.服务器.发布服务器消息(...)`

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
遵循三条极限性能原则：

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
   - 对象复用、池化、预分配
   - 避免临时字符串拼接和临时对象创建
   - **阈值缓存模式**（参考 `TimSort._workspace`）：
     - 静态数组跨调用复用，避免反复 `new Array()`
     - 清理时按阈值决策：小于阈值保留复用，大于阈值释放防止引用泄漏
     ```actionscript
     // 示例：TimSort 的 workspace 管理
     private static var _workspace:Array = null;
     private static var _wsLen:Number    = 0;
     // 使用时：需求 <= 缓存大小则直接复用，否则新建并缓存
     // 清理时：
     if (_wsLen > 256) { _workspace = null; _wsLen = 0; }
     // 小 workspace 保留供下次调用复用
     ```

4. **重入保护与安全降级**（适用于使用静态缓存的热路径组件）
   - `_inUse` 标志防止重入破坏共享状态
   - 检测到重入时 **降级**到原生实现而非崩溃，并 `trace()` 警告
   - `resetState()` 安全阀：在帧初始化时调用，防止 `compare()` 异常导致 `_inUse` 永久锁死
   ```actionscript
   // 示例：TimSort 的重入保护
   private static var _inUse:Boolean = false;
   public static function resetState():Void { _inUse = false; }

   public static function sort(arr:Array, cmp:Function):Array {
       if (_inUse) {
           trace("[TimSort] Warning: reentrant call detected, falling back");
           arr.sort(cmp); // 降级到原生排序
           return arr;
       }
       _inUse = true;
       // ... 核心逻辑 ...
       _inUse = false;
       return arr;
   }
   ```

---

## 4. 代码组织

- 每个类一个文件，文件路径与包路径一致
- 测试文件放在对应目录的 `test/` 子目录下
- 帧脚本按功能分区：展现/引擎/通信/逻辑

## 5. JSDoc 风格文档注释

<!-- TODO: 从实际代码中提取典型的 JSDoc 示例作为模板 -->
<!-- 参考文件：scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as -->

### 要求
- 所有公开类和方法必须包含 JSDoc 风格注释（**中文撰写**）
- 包含 `@class`、`@param`、`@returns`、`@type` 等标签
- 复杂算法需要描述实现思路

## 6. XML 配置文件规范

- 4空格缩进
- 属性值使用双引号
- 添加中文注释说明参数用途
- 保持结构层次清晰
- **注释保护**：通过代码处理 XML 进行数据迁移或批量修改时，必须检查 XML 中的中文注释是否被保留。许多 XML 解析器/序列化器会默认丢弃注释，需确保写回时注释完整
- **列表字段归一化**：`XMLParser` 会将同名节点自动合并为数组，但**仅出现一次时返回单值而非数组**。消费侧对语义上「一定是列表」的字段，必须用 `XMLParser.configureDataAsArray()` 或 `if (!(x instanceof Array)) x = [x]` 归一化，不得假设其类型
- **注意自动类型转换**：`XMLParser` 会将纯数字字符串自动转为 Number（`"007"` → `7`）、`"true"`/`"false"` 转为 Boolean。对必须保持字符串的字段（如编号、代码），在 XML 中避免纯数字格式，或在消费侧显式 `String()` 转回

## 7. Node.js 编码规范

> 以下为通用最佳实践，新增或重构服务端代码时应遵循。

### 项目结构

```
tools/Local Server/
├── server.js              # 入口：HTTP + XMLSocket 启动
├── routes/                # Express 路由定义
├── controllers/           # 业务逻辑处理器（每种 task 一个文件）
├── services/              # 基础服务（socketServer 等）
└── package.json
```

- **职责分层**：路由（routes）只做请求分发，业务逻辑放 controllers，底层能力放 services
- **每种 task 类型独立文件**：`controllers/evalTask.js`、`controllers/regexTask.js` 等，避免单文件膨胀

### 命名约定

- 文件名：camelCase — `evalTask.js`、`socketServer.js`
- 变量/函数：camelCase — `handleRequest`、`socketPort`
- 常量：UPPER_CASE — `MAX_TIMEOUT`、`DEFAULT_PORT`
- 类/构造函数：PascalCase — `TaskRouter`

### 编码风格

- **严格模式**：文件顶部 `'use strict';`
- **const 优先**：不变的绑定用 `const`，需重赋值才用 `let`，禁用 `var`
- **模板字符串**：拼接字符串用模板字面量，不用 `+` 拼接
- **箭头函数**：回调优先用箭头函数，需要 `this` 绑定时才用 `function`
- **解构赋值**：从对象/数组中提取字段时使用解构

### 错误处理

- **统一响应格式**：所有响应遵循 `{ success: true/false, result/error }` 结构
- **try-catch 包裹**：controller 中的业务逻辑用 try-catch 包裹，捕获后返回结构化错误
- **不吞异常**：catch 块中必须记录日志或返回错误，禁止空 catch
- **超时保护**：执行外部代码（如 `eval` 任务）必须设置超时，防止无限阻塞

### 安全

- **沙箱执行**：eval 任务使用 VM2 等沙箱，禁止直接 `eval()`
- **输入校验**：校验 `task` 字段存在性和类型，未知 task 返回明确错误
- **本地监听**：服务仅绑定 `localhost`，不暴露到外部网络

### 日志

- 使用 winston 进行结构化日志
- 日志级别：`error` → 异常和故障，`warn` → 非预期但可恢复，`info` → 关键流程节点，`debug` → 开发调试
- 日志中包含上下文（task 类型、端口号等），方便定位问题

### 依赖管理

- `package.json` 中锁定依赖版本（精确版本号或 `~` 补丁范围）
- 新增依赖前评估必要性，能用 Node.js 内建模块解决的不引入第三方包
- `node_modules/` 已 gitignore，部署前 `npm install`

## 8. 调试规范

- 详见 `agentsDoc/as2-anti-hallucination.md` 调试章节
- `trace()` 可在热路径使用（编译时剔除）
- `_root.发布消息`/`_root.服务器.发布服务器消息` 热路径测试后必须注释掉
