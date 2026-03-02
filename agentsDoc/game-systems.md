# 游戏系统索引

> 各核心游戏系统的概述与入口文件索引。深入某个系统时先查阅此文档定位关键文件。

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

## 4. 计时器系统

分层架构：

| 层级 | 组件 | 位置 | 说明 |
|------|------|------|------|
| 帧驱动 | `"frameUpdate"` 事件总线 | `ServerManager.as` 每帧 publish | 全局帧心跳源 |
| 轻量层 | `EnhancedCooldownWheel` | `neur/ScheduleTimer/` | 128 槽位时间轮，最大延迟 **127 帧（~4.2s@30FPS）** |
| 重型层 | `TaskManager` + `CerberusScheduler` | `neur/ScheduleTimer/` | 三级时间轮 + 最小堆，最大延迟 60 分钟，支持重入/暂停/生命周期清理 |
| 通信层 | `_root.帧计时器` | `scripts/通信/通信_fs_帧计时器.as` | TaskManager 全局 API 封装 + PerformanceScheduler |

- **禁用原生 `setTimeout`/`setInterval`**：游戏逻辑与帧动画深度耦合，必须使用帧驱动计时器
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

## 8. 深度管理（未投入使用）
- **核心文件**：DepthManager.as（基于 AVL 树），性能测试未通过
- **审查文档**：`tools/BalancedTreeSystem_Review_Prompt_CN.md`

## 9. 数据结构与算法
- **位置**：`scripts/类定义/org/flashNight/naki/`
- **内容**：DataStructures（AVL/红黑树/BVH/图/堆/并查集/LRU/BigInt 等 45+ 类）、RandomNumberEngine（LCG/MT/PCG）、Cache、Interpolation、DP、Sort

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

---

## 待补充

<!-- 以下 TODO 统一管理，在自优化环节中逐步填充 -->
- 子弹系统详细架构
- Buff 系统计算流程
- 事件系统使用模式
- 摄像机系统描述
- 音频系统架构
- 物理引擎使用范围与限制
- 深度管理性能瓶颈原因与优化方向
- 关卡系统运行流程
