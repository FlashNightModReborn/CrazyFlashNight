# 游戏系统索引

---

## 0. 核心代码库速查（org.flashNight 七大包）

| 包 | 职责 |
|----|------|
| **arki** | 游戏引擎核心（战斗/渲染/场景/物品/单位） |
| **aven** | 协调与测试（EventCoordinator、Proxy、测试框架） |
| **gesh** | 通用工具库（array/string/number/object/pratt/path/xml 等） |
| **hana** | 小游戏资源（库符号注入主文件运行时） |
| **naki** | 数据结构与数学（排序、随机数、缓存、插值） |
| **neur** | 事件/控制/计时/状态机（EventBus、计时器三级体系、Tween、导航） |
| **sara** | 物理引擎（粒子、约束、碰撞、复合体） |

核心类库路径：`scripts/类定义/org/flashNight/`

---

## 1. 子弹系统
- **位置**：`scripts/类定义/org/flashNight/arki/bullet/`
- **核心**：BulletFactory（工厂模式创建和管理子弹实例）

## 2. Buff/属性系统
- **位置**：`scripts/类定义/org/flashNight/arki/component/`
- **核心**：BuffCalculator 等组件
- **审查文档**：`tools/BuffSystem_Review_Prompt_CN.md`、`tools/BuffSystem_NestedProperty_Review_Prompt_CN.md`（v2）

## 3. 事件系统
- **位置**：`scripts/类定义/org/flashNight/neur/`
- **核心**：自定义事件总线、EventDispatcher 模式
- **审查文档**：`tools/EventSystem_Review_Prompt_CN.md`

### 场景事件阶段
- `SceneChanged`：场景切换的根事件，用于清理旧场景状态、刷新坐标/表现/UI 快照等直接响应。
- `SceneRuntimeReset`：由 `scripts/通信/通信_fs_帧计时器.as` 在 `EnhancedCooldownWheel.I().deactivateAll()` 和运行时保护状态重置后发布。只用于需要在全局计时任务清理后重建循环、对象池或运行时句柄的子系统，不是 `SceneChanged` 的通用替代。
- 当前明确订阅者：弹壳系统在该阶段重建弹壳池与全局更新循环，避免 `EnhancedCooldownWheel` 全局清理后出现外部 running flag 假活。

## 4. 计时器系统

分层架构：

| 层级 | 组件 | 位置 | 说明 |
|------|------|------|------|
| 帧驱动 | `"frameUpdate"` 事件总线 | `ServerManager.as` 每帧 publish | 全局帧心跳源 |
| 轻量层 | `EnhancedCooldownWheel` | `neur/ScheduleTimer/` | 128 槽位时间轮，最大延迟 **127 帧（~4.2s@30FPS）** |
| 重型层 | `TaskManager` + `CerberusScheduler` | `neur/ScheduleTimer/` | 三级时间轮 + 最小堆，最大延迟 60 分钟，支持重入/暂停/生命周期清理 |
| 通信层 | `_root.帧计时器` | `scripts/通信/通信_fs_帧计时器.as` | TaskManager 全局 API 封装 + PerformanceScheduler |

- **禁用原生 `setTimeout`/`setInterval`**：游戏逻辑与帧动画深度耦合，必须使用帧驱动计时器
- **零间隔持久任务顺序契约**：同一 `TaskManager` 按任务本次进入 `zeroFrameTasks` 的顺序执行；持续留表的 `0→0` 更新不换位，分发外 `0→正→0` 按重新入队排尾。ID 快照在时间轮和 pending reschedule 之后的零间隔分发阶段入口收集：时间轮回调新建零任务本次 `updateFrame()` 执行，零任务回调新建 ID 下次执行。快照时已有 ID 在分发中重入不提供延后保证；生产者必须先于消费者入表
- **审查文档**：`tools/TimerSystem_Review_Prompt_CN.md`

### 选用决策

**默认选 EnhancedCooldownWheel**（轻量、GC 友好）。升级到 TaskManager 的场景：
- 延迟超过 127 帧（CooldownWheel 位运算会回环）
- 需要生命周期自动清理（`addLifecycleTask` + `EventCoordinator.addUnloadCallback`）
- 回调中需要修改其他任务（v1.8 重入契约）
- 需要暂停/恢复/动态延迟调整（`delayTask`）

## 5. 摄像机系统
- **位置**：`scripts/类定义/org/flashNight/arki/camera/`

## 6. 音频系统
- **位置**：`scripts/类定义/org/flashNight/arki/audio/`
- **核心**：LightweightSoundEngine（实现 IMusicEngine 接口）
- 音频资源目录：`music/`、`sounds/`

## 7. 物理引擎
- **位置**：`scripts/类定义/org/flashNight/sara/`
- **功能**：粒子系统、物理约束、表面碰撞检测

## 8. 深度管理（已投入使用）
- **位置**：`scripts/类定义/org/flashNight/gesh/depth/`
- **核心**：DepthManager.as — Twip Trick 模运算 Y 排序，swapDepths 劫持透明接入
- **测试**：DepthManagerTest.as（30 功能 + 性能基准）

## 9. 数据结构与算法
- **位置**：`scripts/类定义/org/flashNight/naki/`
- **内容**：DataStructures（AVL/红黑树/BVH/图/堆/并查集/LRU/BigInt 等）、RandomNumberEngine（LCG/MT/PCG）、Cache、Interpolation、DP、Sort

### 排序子系统（`naki/Sort/`）

**主力排序：TimSort.as**（v3.3，稳定）— `sort()` + `sortIndirect()` 两入口。文件头"AS2/AVM1 平台决策记录"是项目中最详尽的 AVM1 字节码实测总结。其他实现：PDQSort、PowerSort、NaturalMergeSort、InsertionSort、QuickSort。

| 场景 | 推荐 | 原因 |
|------|------|------|
| 极小数据（≤10-20） | 手动插入排序 | 避免 C++ 桥接固定开销 |
| 有序/近似有序、需稳定排序 | TimSort | O(n) 最优，极限优化 |
| 原生 `Array.sort()` | **谨慎** | 朴素快排，有序数据退化 O(n²) |

## 10. 通用工具（gesh，21 个子模块）
- **位置**：`scripts/类定义/org/flashNight/gesh/`

### 高频子模块

| 子目录 | 核心类 | 用途 |
|--------|--------|------|
| `array/` | `ArrayUtil`、`ArrayPool` | ES6 风格数组方法（**仅限测试**）；数组对象池 |
| `number/` | `NumberUtil` | `clamp`/`normalize`/`remap`/`defaultIfNaN`/`toFixed`、角度转换 |
| `object/` | `ObjectUtil` | 深拷贝（循环检测）、`deepEquals`、多格式序列化 |
| `pratt/` | `PrattEvaluator` | 表达式求值引擎，`createForBuff()` 供 Buff 动态公式 |
| `string/` | `StringUtils`、`KMPMatcher` | HTML 编解码、压缩（LZW/Huffman）、KMP 匹配 |
| `path/` | `PathManager` | 资源路径管理与环境检测 |
| `xml/` | — | XML 解析工具（详见 [data-schemas.md](data-schemas.md)） |

> 其余 14 个子模块（func/property/iterator/json/symbol/arguments/depth/text/tooltip/toml/fntl/regexp/paint/init）按需查阅源码目录。

## 11. 小游戏系统（未投入使用）
- **位置**：`scripts/类定义/org/flashNight/hana/`
- 作为资源文件存在，库符号注入主文件运行时（详见 architecture.md「子 SWF 加载与通信」）

## 12. 关卡系统
- **帧脚本**：`scripts/逻辑/关卡系统/`
- **数据**：`data/stages/`

## 13. 装备生命周期系统
- **帧脚本**：`scripts/逻辑/装备函数/`（每个 `.as` 注册 `_root.装备生命周期函数.XXX初始化/周期`，物品 XML `<lifecycle>` 节点按装备绑定，战斗中驱动动画/特效/子弹/buff）
- **用途索引 + API 快查 + 新增 7 步流程**：`scripts/逻辑/装备函数/README.md`（就近 hub）
- **编译真源**：`scripts/asLoaderManifest/frame37.as`（f37_N chunk，**非**旧 `装备函数列表.as`，后者已退役删除）；三方一致性门 `tools/validate-equip-fn-coverage.js`
- ⚠ 与 `org.flashNight.arki.item.equipment`（class 化装备**数值计算**系统）是两套平行系统，勿混

## 14. 套装效果系统（一期实现与实机复核中）
- **设计与验收真源**：[套装系统设计与剑圣一期验收](../docs/套装系统-设计与剑圣一期验收-2026-07-14.md)
- **运行边界**：每单位一个逻辑 `SetEffectController`；一期保留子装备自治 tick 和成员 `<lifecycle>` 完整配置，用 `setGate/effectId/componentId` 在通用 loader 解析前门控。中心 routine 保存必需组件 manifest、共享 context 和 placement 通道；placement 在引用重建后即时校正，预计算任务每帧各采样一次有效肢体的 target-local 基向量，胸甲/腿甲共享 `身体_引用`，手甲消费 `左下臂_引用`，组件 tick 逐帧消费缓存而不重复执行肢体坐标换算。五个 ref 由既有 loader 创建后登记到 effect record，preflight/commit/rollback 保证任一组件失败时整套不提交。头甲的低光夜视与常驻扫描/锁定相互独立。原体抗性表项是开启对应定向破击的负向暴露，不是普通 Buff；一期按 `baseIfMissing=10 + value=75` 聚合为 85，写入层不钳制
- **接线点**：`updateLifeCycles()` 清理后先 `prepare`，再装载单件生命周期，最后由 `_root.主角函数.完成生命周期函数装载()` 执行 `finalize`；一期以仅在五件齐全时激活的剑圣装甲重构作为纵向验收

