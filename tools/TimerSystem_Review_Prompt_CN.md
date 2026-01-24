# ActionScript 2.0 定时器系统 v1.8 - 专家级代码审查

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
├── TaskManager.as                 # 任务管理API（重量级框架入口）v1.8
├── CerberusScheduler.as           # 三级时间轮+堆调度器 v1.7
├── Task.as                        # 任务数据结构
├── CooldownWheel.as               # 128槽超轻时间轮（无ID）
└── EnhancedCooldownWheel.as       # 可取消的增强时间轮 v1.2

Dependencies/                      # 依赖组件
├── SingleLevelTimeWheel.as        # 单级时间轮实现 v1.5
├── FrameTaskMinHeap.as            # 4叉最小堆 v1.6
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

### 1. CerberusScheduler.as - 三级时间轮调度器 v1.7

**职责：** 高效管理不同延迟范围的定时任务

**核心机制：**
- 三级时间轮结构：
  - 单层时间轮：0-149帧（约5秒），帧级精度
  - 二级时间轮：5-59秒，秒级精度（Never-Early保证）
  - 三级时间轮：1-59分钟，分钟级精度（Never-Early保证）
- 最小堆兜底：超出时间轮范围或需要高精度的任务
- **[v1.7变更]** Never-Early路由算法：使用`ceil`公式保证任务绝不提前触发

**关键API：**
- `initialize(singleWheelSize, secondsSize, minutesSize, fps, precision)` - 初始化
  - **[DEPRECATED v1.7]** `precisionThreshold`参数已废弃，不再影响路由决策
- `evaluateAndInsertTask(taskID, delayInFrames):TaskIDNode` - 评估并插入任务（Never-Early）
- `tick():TaskIDLinkedList` - 推进时间，返回到期任务链表
- `rescheduleTaskByNode(node, newDelay):TaskIDNode` - 通过节点重新调度任务
- `removeTaskByNode(node)` - 通过节点移除任务
- `addToMinHeapByID(taskID, delay)` - 直接插入最小堆（高精度场景，注意跨池回收）

**v1.7 Never-Early任务路由算法：**
1. `delayInFrames < singleWheelMaxFrames` → 单层时间轮（帧精度，零误差）
2. `ceil((delayInFrames + counter) / counterLimit) <= secondLevelMaxSeconds` → 二级时间轮
   - 保证：实际触发帧 = `slot * counterLimit - counter >= delayInFrames`
3. `ceil((delayInFrames + thirdLevelOffset) / _thirdTickPeriod) <= thirdLevelMaxMinutes` → 三级时间轮
   - `thirdLevelOffset = secondLevelCounter * counterLimit + counter`
   - 保证：实际触发帧 >= `delayInFrames`
4. 超出范围 → 最小堆（帧精度，O(log n)）

**Never-Early设计原理：**
原算法使用`floor(delay / fps)`计算槽位，但二级时间轮的下一次tick在`(counterLimit - counter)`帧之后，
当counter接近limit时，实际延迟可能远小于请求延迟（任务提前触发）。
v1.7使用`ceil((delay + offset) / period)`公式，数学证明`actualDelay >= requestedDelay`。

**v1.4-v1.7架构变更：**
- [v1.4] 废弃内部taskTable，任务ID管理完全由TaskManager负责
- [v1.5] 统一节点池：二级、三级时间轮共享单层时间轮的节点池
- [v1.6] 废弃precisionThreshold，简化任务路由逻辑
- [v1.7] Never-Early路由算法：ceil公式保证任务绝不提前触发
- [v1.7] 新增`_thirdTickPeriod`预计算参数，避免热路径重复乘法
- [v1.7] `addToMinHeapByID`改用minHeap自身节点池（`minHeap.addTimerByID`）
- [v1.7] `addToSingleLevelByID/addToSecondLevelByID/addToThirdLevelByID`统一使用`singleLevelTimeWheel.acquireNode`
- [v1.7.1] `recycleExpiredNode`添加跨池回收文档说明

### 2. TaskManager.as - 任务管理器 v1.8

**职责：** 封装CerberusScheduler，提供任务级API

**核心机制：**
- 双存储结构：`taskTable`（正常任务）+ `zeroFrameTasks`（零帧立即任务）
- 支持重复执行（repeatCount）：true为无限循环，数字为有限次数
- 生命周期绑定：通过`taskLabel`实现MovieClip卸载自动清理
- **[v1.7]** 分发安全：`_dispatching`标记 + `_pendingRemoval`/`_pendingReschedule`延迟队列
- **[v1.8]** 完整重入安全：addOrUpdateTask/addLifecycleTask也走延迟路径；自延迟repeatCount补扣

**关键API：**
- `addTask(action, interval, repeatCount, parameters):String` - 添加任务
- `addSingleTask(action, interval, parameters):String` - 添加单次任务
- `addLoopTask(action, interval, parameters):String` - 添加循环任务
- `addOrUpdateTask(obj, labelName, action, interval, parameters):String` - 添加或更新任务（v1.8分发安全）
- `addLifecycleTask(obj, labelName, action, interval, parameters):String` - 添加生命周期任务（v1.8分发安全）
- `removeTask(taskID)` - 移除任务（分发期间逻辑删除+孤儿节点入队）
- `removeLifecycleTask(obj, labelName):Boolean` - 通过对象和标签移除生命周期任务
- `locateTask(taskID):Task` - 定位任务（v1.8扩展搜索_pendingReschedule）
- `delayTask(taskID, delayTime):Boolean` - 延迟/暂停/恢复任务
- `updateFrame()` - 每帧调用，执行到期任务

**delayTask特殊语义：**
- `delayTask(taskID, true)` → 暂停任务（pendingFrames = Infinity，路由至minHeap永久驻留）
- `delayTask(taskID, false/其他非数字)` → 恢复任务（pendingFrames = intervalFrames）
- `delayTask(taskID, Number)` → 累加延迟（pendingFrames += ceil(delayTime * framesPerMs)）

**v1.8重入契约：**
1. 回调内允许调用的API（系统保证安全）：
   - `removeTask` / `removeLifecycleTask`
   - `delayTask`
   - `addOrUpdateTask` / `addLifecycleTask`
   - `addTask` / `addSingleTask` / `addLoopTask`（新建任务，不影响当前遍历链）
2. repeatCount语义：
   - 执行即递减：`task.action()`一旦被调用，即视为"执行了一次"
   - 若回调中调用`delayTask(self)`自延迟，repeatCount仍然递减（通过`_fromExpired`标记补扣）
   - `delayTask`仅影响下次触发的时间点，不影响执行计数
3. 时间转换原则（Never-Early）：
   - `add*`系列：ceiling bit-op（`_f = x >> 0; ceil = _f + (x > _f)`），零开销热路径
   - `delayTask`：`Math.ceil`（支持负值减帧语义，非热路径）
   - 保证任务绝不会提前触发（允许延后最多1帧）
4. taskLabel命名空间：
   - 同一`obj + labelName`不得跨TaskManager / EnhancedCooldownWheel混用
   - 两套系统ID类型不同（String vs Number），混用会导致标签互相覆盖

**分发安全机制（v1.7→v1.8演进）：**
- `_dispatching`：updateFrame遍历到期任务链表期间为true
- `_currentDispatchTaskID`：当前正在执行回调的任务ID（v1.8新增，用于区分自延迟/跨任务延迟）
- `_pendingRemoval`：分发期间removeTask仅逻辑删除，物理移除入队
- `_pendingReschedule`：分发期间所有物理操作（removeByNode/rescheduleByNode）暂存于此
- `_fromExpired`标记：自延迟时设置，分发结束后补扣repeatCount（跨任务延迟不标记）
- 分发结束统一处理顺序：`_pendingRemoval`物理移除 → `_pendingReschedule`（repeatCount补扣+重调度）
- **v1.8扩展**：`addOrUpdateTask`/`addLifecycleTask`在分发期间对taskTable中的任务也走延迟路径
- **v1.8扩展**：`removeTask`从`_pendingReschedule`删除时，对仍在调度器中的节点入队物理移除

**版本历史：**
- [FIX v1.1] 竞态条件：回调中调用removeTask()导致的僵尸任务复活问题
- [FIX v1.2] for-in迭代中删除元素的未定义行为（先收集ID再遍历）
- [FIX v1.3] 复用数组避免updateFrame热路径GC压力；幽灵ID检测
- [FIX v1.4] 回收已到期节点到节点池
- [FIX v1.5] 防御性回收：taskTable中找不到Task时也回收节点
- [FIX v1.6] addOrUpdateTask添加幽灵ID检测；新增removeLifecycleTask API
- [FIX v1.7] 分发安全（_dispatching + _pendingRemoval）；typeof替代isNaN；_lifecycleRegistered单注册保证；零帧任务pendingFrames undefined修复
- [FIX v1.7.1] _pendingReschedule延迟重调度队列；NaN自不等性检测（delayTime !== delayTime）；分发期间delayTask物理操作统一延迟
- [FIX v1.7.2] removeTask追加_pendingReschedule检查，阻止"任务复活"
- [FIX v1.8] 完整重入安全：addOrUpdateTask/addLifecycleTask分发期间走_pendingReschedule路径；_currentDispatchTaskID区分自延迟/跨任务延迟；_fromExpired补扣repeatCount；removeTask从_pendingReschedule删除时入队孤儿节点物理移除；locateTask扩展搜索_pendingReschedule；ceiling bit-op优化add*系列时间转换

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

### 5. FrameTaskMinHeap.as - 4叉最小堆 v1.6

**职责：** 管理超出时间轮范围或需要精确帧级延迟的任务

**核心机制：**
- 4叉堆结构（每节点4个子节点），降低堆高度
- 节点池复用减少GC压力
- 通过frameMap[frameIndex]存储同一帧的任务链表
- 循环展开、链式赋值等性能优化

**关键API：**
- `insert(taskID, delay)` - 插入任务
- `addTimerByID(taskID, delay):TaskIDNode` - 通过ID添加定时器
- `addTimerByNode(node, delay):TaskIDNode` - 通过节点添加定时器
- `removeNode(node)` - 删除指定节点
- `tick():TaskIDLinkedList` - 推进帧并返回到期任务
- `extractTasksAtMinFrame():TaskIDLinkedList` - 提取最小帧的任务

**版本历史：**
- [FIX v1.2] removeNode中添加bubbleUp，修复任意删除后堆性质破坏
- [FIX v1.2] trimNodePool正确释放引用，避免内存泄漏
- **[FIX v1.6]** removeNode添加防御性检查：当frameIndex已被extractTasksAtMinFrame删除时，直接回收节点。解决任务回调中调用removeTask()删除自身的边界情况

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

6. **幽灵ID问题** - v1.3修复
   - 问题：手动removeTask后重新addLifecycleTask，旧unload回调持有旧ID
   - 修复：addLifecycleTask中检测幽灵ID并强制生成新ID

7. **节点回收遗漏** - v1.4修复
   - 问题：已到期节点未回收到节点池
   - 修复：TaskManager在任务完成/重调度后调用recycleExpiredNode

8. **统一节点池** - v1.5修复
   - 问题：三级时间轮各自维护节点池，分布不均
   - 修复：二级、三级时间轮共享单层时间轮的节点池

9. **堆节点removeNode边界情况** - v1.6修复
   - 问题：任务回调中调用removeTask删除自身时，frameIndex已被extractTasksAtMinFrame删除
   - 修复：removeNode添加防御性检查，当frameMap条目不存在时直接回收节点

10. **addOrUpdateTask幽灵ID** - v1.6修复
    - 问题：addOrUpdateTask未检测幽灵ID
    - 修复：与addLifecycleTask保持一致的检测逻辑

11. **任务提前触发（S3 bug）** - v1.7修复
    - 问题：二级/三级时间轮使用`floor`计算槽位，当counter接近limit时实际延迟远小于请求延迟
    - 修复：Never-Early算法，使用`ceil((delay + offset) / period)`公式保证`actualDelay >= requestedDelay`

12. **分发期间断链** - v1.7修复
    - 问题：回调中调用removeTask(B)物理断开B节点，导致遍历链后续节点丢失
    - 修复：`_dispatching`标记 + `_pendingRemoval`队列，分发期间仅逻辑删除

13. **isNaN布尔误判** - v1.7修复
    - 问题：AS2中`isNaN(true)`返回false（因为`Number(true)=1`），布尔值被当作数字处理
    - 修复：`delayTask`改用`typeof delayTime != "number"`进行类型判断

14. **生命周期回调累积** - v1.7修复
    - 问题：ghost ID检测时isNewTask变为true，每次add→remove→add循环都注册新的unload回调
    - 修复：`_lifecycleRegistered[labelName]`保证每个obj+label仅注册一次回调

15. **零帧任务pendingFrames未初始化** - v1.7修复
    - 问题：零帧任务的pendingFrames为undefined，`undefined + Number = NaN`
    - 修复：`delayTask`中使用`(task.pendingFrames || 0)`确保安全归零

16. **分发期间delayTask断链** - v1.7.1修复
    - 问题：分发期间`delayTask`调用`rescheduleTaskByNode`等价于物理移除+重插，破坏遍历链
    - 修复：`_pendingReschedule`映射表暂存受影响任务，分发结束后统一处理

17. **NaN走数字分支** - v1.7.1修复
    - 问题：`typeof NaN == "number"`为true，仅靠typeof无法过滤NaN
    - 修复：追加NaN自不等性检测`delayTime !== delayTime`

18. **任务复活** - v1.7.2修复
    - 问题：分发期间A调用delayTask(B)后又调用removeTask(B)，B已从taskTable移至_pendingReschedule，removeTask找不到B，分发结束后B被重新调度
    - 修复：`removeTask`追加`_pendingReschedule[taskID]`检查并删除

19. **addOrUpdateTask/addLifecycleTask分发期间断链** - v1.8修复
    - 问题：回调中调用addOrUpdateTask/addLifecycleTask更新同帧后续任务时，rescheduleTaskByNode物理移除节点导致遍历链断裂
    - 修复：分发期间对taskTable中的任务执行reschedule/removeByNode操作时，逻辑移除后入队`_pendingReschedule`

20. **自延迟repeatCount不递减** - v1.8修复
    - 问题：任务回调中调用`delayTask(self)`自延迟时，任务被移入`_pendingReschedule`，分发循环跳过正常的repeatCount递减流程，导致有限次任务永远不会结束
    - 修复：`_currentDispatchTaskID`记录当前分发任务ID，自延迟时设置`_fromExpired=true`，分发结束后补扣repeatCount（耗尽则不再重调度）

21. **removeTask孤儿节点泄漏** - v1.8修复
    - 问题：分发期间从`_pendingReschedule`移除任务时，若节点仍在调度器中（跨任务延迟场景），节点成为孤儿直到自然到期才被回收
    - 修复：检查`node.ownerType != 0`后将节点入队`_pendingRemoval`，分发结束后统一物理移除

22. **ceiling bit-op优化** - v1.8优化
    - 问题：add*系列使用`((x) + 0.9999999999) | 0`实现ceiling，浮点精度边界有误差风险
    - 修复：改用`_f = x >> 0; ceil = _f + (x > _f)`，数学正确且零开销

23. **locateTask搜索范围不完整** - v1.8修复
    - 问题：分发期间被delayTask/addOrUpdateTask移入`_pendingReschedule`的任务，locateTask无法找到
    - 修复：locateTask扩展搜索`_pendingReschedule`

### 可能仍需关注的问题

1. **TaskManager生命周期标签残留** - v1.6已提供解决方案
   - 问题：手动removeTask()不清理`obj.taskLabel[labelName]`
   - 影响：后续同名任务可能被错误关联
   - **v1.6方案**：使用`removeLifecycleTask(obj, labelName)`代替`removeTask(taskID)`，会同时清理标签

2. **framesPerMs命名歧义** - v1.3已修复
   - TaskManager中`framesPerMs = frameRate / 1000`，表示每毫秒对应的帧数
   - EnhancedCooldownWheel中`每帧毫秒 = 1000 / 30`，表示每帧的毫秒数
   - v1.3已在代码注释中澄清语义

3. **CooldownWheel无取消能力**
   - 设计如此，但使用者可能误用导致已失效的回调仍被执行
   - 需要取消能力时应使用EnhancedCooldownWheel

4. **Never-Early路由的精度损失边界**
   - v1.7的Never-Early保证任务不提前触发，但允许延后触发
   - 二级时间轮最大延后：`counterLimit - 1`帧（约1秒@30FPS）
   - 三级时间轮最大延后：`_thirdTickPeriod - 1`帧（约60秒@默认配置）
   - 需要帧级精度时，应使用`addToMinHeapByID()`绕过时间轮（注意跨池回收开销）

5. **跨池回收问题**
   - `addToMinHeapByID`从minHeap.nodePool获取节点，但到期回收时统一进入singleLevelTimeWheel池
   - 高频使用时minHeap.nodePool无法复用已回收节点，需持续分配新对象
   - 当前场景下使用频率低，开销可忽略；若后续高频使用需按ownerType分发回收

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

### 3. 竞态安全与重入安全
- tick()过程中添加/取消任务的安全性
- 回调中操作同一个定时器系统的安全性（v1.8重入契约）
- 迭代过程中修改集合的处理
- 自延迟（delayTask(self)）与跨任务延迟的正确区分
- `_pendingReschedule`后处理阶段的repeatCount补扣逻辑

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
| Core/ | 5个 | 核心实现（TaskManager v1.8、CerberusScheduler v1.7、CooldownWheel等） |
| Dependencies/ | 5个 | 依赖组件（SingleLevelTimeWheel v1.5、FrameTaskMinHeap v1.6等） |
| SharedDeps/ | 4个 | 共享依赖（Delegate、Dictionary、EventCoordinator、ArgumentsUtil） |
| Macros/ | 2个 | 宏定义（WHEEL_SIZE、WHEEL_MASK） |
| Test/ | 4个 | 单元测试 |
| Docs/ | 5个 | 设计文档 |

**总计26个文件，约648KB代码量**

目标是提供一份专业的代码审查报告，帮助提升定时器系统的可靠性和性能，同时尊重AS2平台的实际约束。
