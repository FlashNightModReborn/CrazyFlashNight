# 游戏系统索引

> 闪客快打7 各核心游戏系统的概述与入口文件索引。
> 深入某个系统时先查阅此文档定位关键文件。

---

## 1. 子弹系统
- **位置**：`scripts/类定义/org/flashNight/arki/bullet/`
- **核心**：BulletFactory（工厂模式创建和管理子弹实例）
- **审查文档**：无独立 Review Prompt
<!-- TODO: 补充子弹系统的详细架构描述 -->

## 2. Buff/属性系统
- **位置**：`scripts/类定义/org/flashNight/arki/component/`
- **核心**：BuffCalculator 等组件
- **审查文档**：
  - `tools/BuffSystem_Review_Prompt_CN.md`
  - `tools/BuffSystem_NestedProperty_Review_Prompt_CN.md`
  - `tools/BuffSystem_NestedProperty_Review_Prompt_v2_CN.md`
<!-- TODO: 补充 Buff 系统的计算流程 -->

## 3. 事件系统
- **位置**：`scripts/类定义/org/flashNight/neur/`
- **核心**：自定义事件总线、EventDispatcher 模式
- **审查文档**：`tools/EventSystem_Review_Prompt_CN.md`
<!-- TODO: 补充事件系统的使用模式 -->

## 4. 计时器系统

分层架构：

| 层级 | 组件 | 位置 | 说明 |
|------|------|------|------|
| 帧驱动 | `"frameUpdate"` 事件总线 | `ServerManager.as` 每帧 publish | 全局帧心跳源 |
| 轻量层 | `EnhancedCooldownWheel` | `neur/ScheduleTimer/` | 128 槽位时间轮，最大延迟 **127 帧（~4.2s@30FPS）** |
| 重型层 | `TaskManager` + `CerberusScheduler` | `neur/ScheduleTimer/` | 三级时间轮 + 最小堆，最大延迟 60 分钟，支持重入/暂停/生命周期清理 |
| 通信层 | `_root.帧计时器` | `scripts/通信/通信_fs_帧计时器.as` | TaskManager 全局 API 封装 + PerformanceScheduler |

- **禁用原生 `setTimeout`/`setInterval`**：游戏逻辑与帧动画深度耦合，真实时间驱动会导致不同步。必须使用帧驱动计时器
- **审查文档**：`tools/TimerSystem_Review_Prompt_CN.md`

### 选用决策

**默认选 EnhancedCooldownWheel**（轻量、GC 友好）。升级到 TaskManager 的场景：
- 延迟超过 127 帧（CooldownWheel 位运算会回环）
- 需要生命周期自动清理（`addLifecycleTask` + `EventCoordinator.addUnloadCallback`）
- 回调中需要修改其他任务（v1.8 重入契约）
- 需要暂停/恢复/动态延迟调整（`delayTask`）

## 5. 摄像机系统
- **位置**：`scripts/类定义/org/flashNight/arki/camera/`
<!-- TODO: 补充摄像机系统描述 -->

## 6. 音频系统
- **位置**：`scripts/类定义/org/flashNight/arki/audio/`
- **核心**：LightweightSoundEngine（实现 IMusicEngine 接口）
- 音频资源目录：`music/`、`sounds/`
<!-- TODO: 补充音频系统架构 -->

## 7. 物理引擎
- **位置**：`scripts/类定义/org/flashNight/sara/`
- **功能**：粒子系统、物理约束、表面碰撞检测
<!-- TODO: 补充物理引擎的使用范围和限制 -->

## 8. 深度管理（未投入使用）
- **核心文件**：DepthManager.as
- **设计**：基于 AVL 树管理 MovieClip 深度层级
- **状态**：性能测试未通过，当前未投入使用
- **审查文档**：`tools/BalancedTreeSystem_Review_Prompt_CN.md`
<!-- TODO: 记录性能瓶颈的具体原因和优化方向 -->

## 9. 数据结构与算法
- **位置**：`scripts/类定义/org/flashNight/naki/`
- **内容**：DataStructures（AVL/红黑树/BVH/图/堆/并查集/LRU/BigInt 等 35+ 类）、RandomNumberEngine（LCG/MT/PCG）、Cache、Interpolation、DP、Sort

### 排序子系统（`naki/Sort/`）

**主力排序：TimSort.as**（v3.3，稳定）— `sort()` + `sortIndirect()` 两入口。文件头的"AS2/AVM1 平台决策记录"是项目中对 AVM1 字节码行为最详尽的实测总结。其他实现：PDQSort、PowerSort、NaturalMergeSort、InsertionSort、QuickSort。各算法均有对应 `.md` 设计文档和 `*Test.as` 测试文件。

优化技术详见 [as2-performance.md](as2-performance.md) 优化决策快查表。

**选用决策**：

| 场景 | 推荐 | 原因 |
|------|------|------|
| 极小数据（≤10-20） | 手动插入排序 | 避免 C++ 桥接固定开销 |
| 有序/近似有序数据、需稳定排序 | TimSort | O(n) 最优，极限优化 |
| 原生 `Array.sort()` | **谨慎** | 朴素快排，有序数据退化 O(n²) |

## 10. 通用工具（gesh，22 个子模块）
- **位置**：`scripts/类定义/org/flashNight/gesh/`

### 高频子模块

| 子目录 | 核心类 | 用途 |
|--------|--------|------|
| `array/` | `ArrayUtil`、`ArrayPool` | ES6 风格数组方法（**仅限测试，工程代码性能不足**）；数组对象池 |
| `number/` | `NumberUtil` | `clamp`/`normalize`/`remap`/`defaultIfNaN`/`toFixed`、角度转换 |
| `object/` | `ObjectUtil` | 深拷贝（循环检测）、`deepEquals`、多格式序列化 |
| `pratt/` | `PrattEvaluator` | 表达式求值引擎，`createForBuff()` 供 Buff 系统动态公式 |
| `string/` | `StringUtils`、`KMPMatcher` | HTML 编解码、压缩（LZW/Huffman）、KMP 匹配 |
| `path/` | `PathManager` | 资源路径管理与环境检测（resource/browser/Steam） |
| `xml/` | — | XML 解析工具（详见 [data-schemas.md](data-schemas.md)） |

其他子模块：`func/`（FunctionUtil/LazyValue）、`property/`（PropertyAccessor）、`iterator/`（IIterator 系列）、`json/`（JSONLoader）、`symbol/`（Symbol UUID）、`arguments/`、`depth/`（DepthManager，未投入使用）、`text/`、`tooltip/`、`toml/`、`fntl/`、`regexp/`、`paint/`（RendererVM）— 按需查阅源码目录

## 11. 小游戏系统（尚未投入使用）
- **位置**：`scripts/类定义/org/flashNight/hana/`
- **状态**：当前尚未投入使用
- **定位**：作为资源文件存在，主要提供各类 AS 链接影片剪辑等资源。子 SWF 本身被视为一种资源文件，加载后其库符号注入主文件运行时环境，在主文件作用域内运行（详见架构文档「子 SWF 加载与通信」一节）

## 12. 关卡系统
- **帧脚本**：`scripts/逻辑/关卡系统/`
- **数据**：`data/stages/`
<!-- TODO: 补充关卡系统的运行流程 -->
