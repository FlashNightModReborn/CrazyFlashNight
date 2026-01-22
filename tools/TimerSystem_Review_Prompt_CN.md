# ActionScript 2.0 定时器系统 v1.0 - 专家级代码审查

## 审查请求

请对附件中的定时器系统进行严格、独立的代码审查。以高级工程师的标准评估这套系统是否适合在商业游戏中作为核心基础设施使用。

---

## 技术背景

**语言：** ActionScript 2.0 (Flash Player)

### AS2语言特性（重要认知校正）

**容错机制：**
- AS2对无效引用**极其宽容**，访问`null`或`undefined`的属性**不会抛出异常**，只会静默返回`undefined`，也不会崩溃
- 例如：`obj.foo.bar.baz` 即使`obj`为`null`也不会报错，整个表达式返回`undefined`
- 这意味着许多在其他语言中会崩溃的代码在AS2中会"静默失败"
- **审查时请勿建议添加大量防御性null检查**，这在AS2中通常是不必要的

**性能约束（核心设计原则）：**
- AS2的执行性能**仅为AS3或现代JavaScript的约1/10**
- 这是虚拟机层面的根本限制，无法通过代码优化弥补
- **任何设计决策都必须将性能作为最高优先级**
- 无法承受的运行时安全检查必须通过**契约化设计**转嫁给调用方
- 宁可假设调用方遵守契约，也不能添加拖慢热路径的防护代码

**调试代码处理：**
- `trace()`语句在SWF编译时**可配置自动剔除**
- 因此代码中的`trace()`调试输出**不构成性能问题**
- 无需建议移除或条件化trace语句

**其他语言限制：**
- 无原生`Map`、`Set`——只有`Object`（哈希表）和`Array`
- 无`const`、无块级作用域——只有函数作用域的`var`
- 基于原型的继承，`class`是语法糖
- 单线程、事件驱动执行模型
- 帧驱动游戏循环（通常30 FPS）

**运行环境：**
- Flash Player 32（最终版本）
- 高频调度场景：战斗系统每帧可能调度数十个定时任务
- 大量活跃任务：单帧可能有100+个活跃定时器
- 游戏过程中频繁创建/取消任务
- 内存管理需要通过显式清理方法实现

---

## 系统架构

该定时器系统提供两套并行的调度框架：

### 1. 重量级框架：TaskManager + CerberusScheduler

**职责：** 支持任意延迟时间、生命周期绑定、精确重调度的完整任务管理系统

**核心组件：**
- **TaskManager.as** - 任务管理API封装，对外接口层
- **CerberusScheduler.as** - 三级时间轮+最小堆混合调度器（核心引擎）
- **Task.as** - 任务数据结构

**设计特点：**
- 三级时间轮：单层(帧级) + 二级(秒级) + 三级(分钟级)
- 最小堆兜底超长延迟或高精度任务
- 支持生命周期绑定（MovieClip卸载时自动取消）
- 支持任意延迟范围（从0帧到数小时）

### 2. 轻量级框架：CooldownWheel + EnhancedCooldownWheel

**职责：** 超高性能的短延迟定时器，适合技能冷却、Buff计时等场景

**核心组件：**
- **CooldownWheel.as** - 128槽位时间轮，极致性能，无任务ID（无法取消）
- **EnhancedCooldownWheel.as** - 包装CooldownWheel，增加任务ID管理，支持取消

**设计特点：**
- 128槽位固定大小，位掩码取模（& 127）
- 最大延迟127帧（约4.2秒@30FPS）
- 零GC压力设计（闭包缓存、对象复用）
- 单例模式，全局共享

### 使用范围统计

| 使用类型 | 数量 |
|----------|------|
| TaskManager直接调用 | **3个文件** |
| EnhancedCooldownWheel调用 | **9个文件，30+次调用** |
| 覆盖游戏模块 | **7个类别** |

**主要使用者模块：**
- Buff系统（BuffBase、BuffSystem）
- 技能系统（NativeActions）
- 场景管理（GameWorld、FightScene）
- 单位控制（UnitComponent）
- 资源加载（LoaderTest）
- 音频系统（延迟播放）
- UI系统（动画延迟）

---

## 代码结构

```
Core/                              # 核心实现
├── TaskManager.as                 # 任务管理API（重量级框架入口）v1.2
├── CerberusScheduler.as           # 三级时间轮+堆调度器
├── Task.as                        # 任务数据结构
├── CooldownWheel.as               # 128槽超轻时间轮（无ID）
└── EnhancedCooldownWheel.as       # 可取消的增强时间轮 v1.2

Dependencies/                      # 依赖组件
├── SingleLevelTimeWheel.as        # 单级时间轮实现
├── FrameTaskMinHeap.as            # 4叉最小堆 v1.2
├── TaskIDNode.as                  # 任务ID节点
├── TaskIDLinkedList.as            # 任务ID链表 v1.2
└── TaskNode.as                    # 堆任务节点

SharedDeps/                        # 共享依赖（与事件系统共用）
├── Delegate.as                    # 函数委托
├── Dictionary.as                  # UID字典
├── EventCoordinator.as            # MovieClip事件协调器
└── ArgumentsUtil.as               # 参数工具

Macros/                            # 宏定义
├── WHEEL_SIZE_MACRO.as            # 时间轮大小宏
└── WHEEL_MASK_MACRO.as            # 位掩码宏

Test/                              # 单元测试
├── TaskManagerTester.as
├── CerberusSchedulerTest.as
├── CooldownWheelTests.as
└── EnhancedCooldownWheelTests.as

Docs/                              # 设计文档
├── TaskManager.md
├── CerberusScheduler.md
├── CooldownWheel.md
├── EnhancedCooldownWheel.md
└── SingleLevelTimeWheel.md
```

---

## 核心组件详解

### 1. CerberusScheduler.as - 三级时间轮调度器

**职责：** 高效管理不同延迟范围的定时任务

**核心机制：**
- 三级时间轮结构：
  - 单层时间轮：0-149帧（约5秒），帧级精度
  - 二级时间轮：0-59秒，秒级精度
  - 三级时间轮：0-59分钟，分钟级精度
- 最小堆兜底：超出时间轮范围或需要高精度的任务
- 精度阈值控制：根据`precisionThreshold`决定任务去向

**关键API：**
- `initialize(singleWheelSize, secondsSize, minutesSize, fps, precision)` - 初始化
- `evaluateAndInsertTask(taskID, delayInFrames):TaskIDNode` - 评估并插入任务
- `tick():TaskIDLinkedList` - 推进时间，返回到期任务链表
- `rescheduleTask(taskID, newDelay)` - 重新调度任务
- `removeTask(taskID)` - 移除任务

**任务流转逻辑：**
1. 任务进入 → 评估延迟和精度
2. 短延迟 → 单层时间轮
3. 中延迟且精度允许 → 二级时间轮（降级后延迟再评估）
4. 长延迟且精度允许 → 三级时间轮
5. 精度不允许或超出范围 → 最小堆

### 2. TaskManager.as - 任务管理器 v1.2

**职责：** 封装CerberusScheduler，提供任务级API

**核心机制：**
- 双存储结构：`taskTable`（正常任务）+ `zeroFrameTasks`（零帧立即任务）
- 支持重复执行（repeatCount）：true为无限循环，数字为有限次数
- 生命周期绑定：通过`taskLabel`实现MovieClip卸载自动清理

**关键API：**
- `addTask(action, interval, repeatCount, obj):String` - 添加任务
- `addDelayedTask(delay, action, obj):String` - 添加延迟任务（单次）
- `removeTask(taskID)` - 移除任务
- `updateFrame()` - 每帧调用，执行到期任务

**v1.2修复：**
- [FIX] 竞态条件：回调中调用removeTask()导致的僵尸任务复活问题
- [FIX] for-in迭代中删除元素的未定义行为

### 3. CooldownWheel.as - 超轻量时间轮

**职责：** 极致性能的短延迟定时器，不支持取消

**核心机制：**
- 128槽位固定数组
- 位掩码取模：`index = (currentSlot + delay) & 127`
- 每槽位存储回调链表
- 单例模式，全局tick驱动

**关键API：**
- `I():CooldownWheel` - 获取单例
- `add(delay, callback)` - 添加定时器（帧为单位）
- `tick()` - 推进一帧

**设计限制：**
- 最大延迟127帧（约4.2秒@30FPS）
- 无任务ID，无法取消
- 适用于"一次性发射后不管"的场景

### 4. EnhancedCooldownWheel.as - 增强时间轮 v1.2

**职责：** 在CooldownWheel基础上增加任务管理能力

**核心机制：**
- 包装CooldownWheel作为内核
- 维护`activeTasks`哈希表（taskId → TaskNode）
- 支持重复执行和取消
- 闭包缓存避免重复分配

**关键API：**
- `I():EnhancedCooldownWheel` - 获取单例
- `addTask(callback, intervalMs, repeatCount, ...args):Number` - 添加任务
- `addDelayedTask(delay, callback, ...args):Number` - 添加延迟任务
- `removeTask(taskId)` - 取消任务
- `getActiveTaskCount():Number` - 获取活跃任务数

**v1.2修复：**
- [FIX] 闭包缓存：每个任务只创建一次trigger闭包，避免GC压力
- [FIX] 移除try-catch，采用契约化设计

### 5. FrameTaskMinHeap.as - 4叉最小堆 v1.2

**职责：** 管理超出时间轮范围的任务

**核心机制：**
- 4叉堆结构（每节点4个子节点）
- 节点池复用减少GC
- 支持通过taskID快速删除

**关键API：**
- `insert(taskID, executeFrame):TaskNode` - 插入任务
- `extractMin():TaskNode` - 提取最小元素
- `peekMin():TaskNode` - 查看最小元素
- `removeNode(node)` - 删除指定节点
- `decreaseKey(node, newFrame)` - 减小执行帧

**v1.2修复：**
- [FIX] removeNode中添加bubbleUp，修复任意删除后堆性质破坏
- [FIX] trimNodePool正确释放引用，避免内存泄漏

### 6. TaskIDLinkedList.as - 任务ID链表 v1.2

**职责：** 存储同一槽位的多个任务ID

**核心机制：**
- 双向链表结构
- 节点持有list引用，支持O(1)删除
- merge/mergeDirect两种合并策略

**v1.2文档补充：**
- [DOC] mergeDirect的使用限制：仅适用于一次性消费场景
- 被合并节点的list引用不更新，不可对其调用remove()

---

## 关键依赖关系

```
TaskManager
    └── CerberusScheduler
            ├── SingleLevelTimeWheel (x3)
            ├── FrameTaskMinHeap
            │       └── TaskNode
            └── TaskIDLinkedList
                    └── TaskIDNode

EnhancedCooldownWheel
    └── CooldownWheel (单例内核)
```

---

## 已知的待审查问题

### 已修复的问题

1. **TaskManager竞态条件** - v1.1修复
   - 问题：回调中调用removeTask()后，任务仍被重调度导致"僵尸任务"
   - 修复：执行回调后检查任务是否仍存在于taskTable

2. **for-in迭代删除** - v1.2修复
   - 问题：zeroFrameTasks遍历中删除元素的未定义行为
   - 修复：先收集ID到数组，再遍历数组执行

3. **EnhancedCooldownWheel闭包泄漏** - v1.2修复
   - 问题：每次重复调度都创建新闭包，造成GC压力
   - 修复：创建任务时缓存trigger闭包

4. **FrameTaskMinHeap任意删除** - v1.2修复
   - 问题：removeNode只做bubbleDown，可能破坏堆性质
   - 修复：先bubbleUp再bubbleDown

5. **FrameTaskMinHeap节点池泄漏** - v1.2修复
   - 问题：trimNodePool未正确释放引用
   - 修复：遍历释放后再截断数组

### 可能仍需关注的问题

1. **TaskManager生命周期标签残留**
   - 问题：手动removeTask()不清理`obj.taskLabel[labelName]`
   - 影响：后续同名任务可能被错误关联

2. **msPerFrame命名歧义**
   - TaskManager中`msPerFrame = frameRate / 1000`，实际是frames per ms
   - EnhancedCooldownWheel中`每帧毫秒 = 1000 / 30`，正确的ms per frame

3. **CooldownWheel无取消能力**
   - 设计如此，但使用者可能误用导致已失效的回调仍被执行

---

## 审查范围

请**独立评估**以下方面：

### 1. 正确性
- 时间轮槽位计算是否正确（特别是边界情况）？
- 任务重调度逻辑是否正确处理repeatCount？
- 多级时间轮降级后的精度是否可接受？
- 堆操作（insert/extract/remove/decreaseKey）是否保持堆性质？

### 2. 内存管理（重点）
- 检查潜在内存泄漏路径（特别是闭包捕获、节点池管理）
- 任务取消后是否完全清理引用？
- 节点池的增长/收缩策略是否合理？
- TaskNode/TaskIDNode的复用是否正确？

### 3. 竞态安全
- tick()过程中添加/取消任务的安全性
- 回调中操作同一个定时器系统的安全性
- 迭代过程中修改集合的处理

### 4. 性能
- **这是最重要的审查维度**
- tick()热路径的分配压力
- 时间轮推进的效率
- 堆操作的复杂度是否符合预期
- 大量任务时的可扩展性

### 5. API设计
- 两套框架的定位是否清晰？
- 使用限制是否有足够文档说明？
- 错误场景的处理是否合理？

---

## 输出格式

请按以下结构组织你的发现：

```
## 严重问题（必须修复）
[可能导致崩溃、数据损坏或内存泄漏的问题]

## 重要问题（建议修复）
[在特定条件下可能引发问题]

## 轻微问题（可考虑修复）
[代码质量改进、小优化]

## 正面评价
[设计良好、值得肯定的方面]
```

对于每个问题，请提供：
- **位置：** 文件名和相关代码段
- **描述：** 问题是什么
- **影响：** 可能导致什么后果
- **建议：** 如何修复（如适用请附代码）

---

## 审查原则

- **深入细致：** 仔细阅读代码，不要走马观花
- **具体明确：** 引用实际代码，而非泛泛而谈
- **独立判断：** 从代码本身得出结论
- **务实导向：** 关注对生产环境真正重要的问题
- **实事求是：** 同时指出问题和设计亮点
- **性能意识：** 任何建议都要考虑AS2的性能约束

**请特别注意：**
1. 不要建议添加在AS2中不必要的null/undefined检查
2. 不要建议会显著影响热路径性能的防护措施
3. trace语句不是性能问题，无需建议移除
4. 理解契约化设计的必要性——某些安全检查由调用方负责
5. 定时器系统是高频调用的热路径，性能至关重要
6. let-it-crash是有意的设计选择，不要建议恢复try/catch

---

## 附件清单

| 目录 | 文件数 | 说明 |
|------|--------|------|
| Core/ | 5个 | 核心实现（TaskManager v1.2、CerberusScheduler、CooldownWheel等） |
| Dependencies/ | 5个 | 依赖组件（SingleLevelTimeWheel、FrameTaskMinHeap v1.2等） |
| SharedDeps/ | 4个 | 共享依赖（Delegate、Dictionary、EventCoordinator、ArgumentsUtil） |
| Macros/ | 2个 | 宏定义（WHEEL_SIZE、WHEEL_MASK） |
| Test/ | 4个 | 单元测试 |
| Docs/ | 5个 | 设计文档 |

**总计25个文件，约423KB代码量**

目标是提供一份专业的代码审查报告，帮助提升定时器系统的可靠性和性能，同时尊重AS2平台的实际约束。
