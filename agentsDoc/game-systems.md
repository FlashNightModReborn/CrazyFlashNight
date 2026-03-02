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
- **位置**：`scripts/类定义/org/flashNight/neur/Timer/`、`scripts/类定义/org/flashNight/neur/ScheduleTimer/`
- **核心**：FrameTimer.as（帧计时器）、EnhancedCooldownWheel.as（冷却轮调度器）
- **惯例**：AS2 原生 `setTimeout`/`setInterval` 可用但一般不使用，优先用帧计时器或 EnhancedCooldownWheel
- **审查文档**：`tools/TimerSystem_Review_Prompt_CN.md`
<!-- TODO: 补充 FrameTimer 与 EnhancedCooldownWheel 的选用场景区分 -->

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
- **内容**：高级矩阵运算、随机数引擎（LCG、MersenneTwister）、数据结构

### 排序子系统（`naki/Sort/`）
本项目最深度优化的基建之一，包含多种排序算法实现和完整基准测试体系：

| 文件 | 算法 | 说明 |
|------|------|------|
| `TimSort.as` | TimSort（稳定） | **主力排序**。v3.3，包含 `sort()` 和 `sortIndirect()` 两个入口。文件头的"AS2/AVM1 平台决策记录"是项目中对 AVM1 字节码行为最详尽的实测总结 |
| `PDQSort.as` | Pattern-Defeating QuickSort | 不稳定但对特定模式更快 |
| `PowerSort.as` | PowerSort | 基于 power 的合并策略 |
| `NaturalMergeSort.as` | Natural Merge Sort | 自然归并排序 |
| `InsertionSort.as` | Insertion Sort | 小数组专用 |
| `QuickSort.as` | QuickSort | 经典快排 |

**关键优化技术**（均以 TimSort 为核心示范）：
- **宏内联**：合并逻辑通过 `#include "../macros/TIMSORT_MERGE.as"` 内联，零函数调用开销
- **间接排序**：`sortIndirect(arr, keys)` 预提取键数组，内联比较替代函数调用，38%~67% 提升
- **AVM1 字节码调优**：偏移寻址 vs 自增、StoreRegister 副作用快速路径、隐式布尔转换
- **GC 管理**：静态 workspace 跨调用复用 + 阈值释放策略
- **重入保护**：`_inUse` + `resetState()` + 降级回退

**辅助文件**：
- `evalorder.md` — AVM1 求值顺序规则（50 个测试用例验证 LHS-first）
- `EvalOrderTest.as` — 求值顺序验证测试
- `TimSort.md` — 完整基准测试报告
- `MicroBenchmark.as` / `MicroBenchmark.md` — 微基准测试框架
- 各排序算法均有对应 `.md` 设计文档和 `*Test.as` 测试文件

<!-- TODO: 补充各排序算法的选用场景区分（何时用 TimSort vs PDQSort vs 原生 Array.sort） -->

## 10. 通用工具
- **位置**：`scripts/类定义/org/flashNight/gesh/`
- **内容**：数组工具、字符串解析（EvalParser）、算法实现

### 子模块与关键类

| 子目录 | 核心类 | 用途 |
|--------|--------|------|
| `array/` | `ArrayUtil` | ES6 风格数组方法：`forEach`、`map`、`filter`、`reduce`、`find`、`flat`、`groupBy`、`unique`、`shuffle`、`chunk`、`zip` 等 |
| `array/` | `ArrayPool` | 数组对象池（继承 `LightObjectPool`），减少 GC 开销 |
| `number/` | `NumberUtil` | 安全数值运算（`safeAdd`/`safeDivide`/`defaultIfNaN`）、`clamp`/`normalize`/`remap`/`wrap`、角度转换（`deg2rad`/`rad2deg`）、ES262 规范的 `toFixed` |
| `string/` | `StringUtils` | HTML 实体编解码、字符转义、字符串压缩（LZW/RLE/Huffman/Hex16）、填充/裁剪/大小写转换 |
| `string/` | `KMPMatcher` | KMP 模式匹配算法 |
| `object/` | `ObjectUtil` | 深拷贝（带循环检测）、`deepEquals`、序列化/反序列化（JSON/Base64/FNTL/TOML/压缩格式） |
| `func/` | `FunctionUtil` | 基于类型的函数重载分派 |
| `func/` | `LazyValue` | 惰性求值 + 自优化缓存（首次调用计算，后续直接返回） |
| `pratt/` | `PrattEvaluator` | Pratt 算法表达式求值引擎，支持变量绑定和内建函数（`min`/`max`/`clamp`/`abs`/`floor`/`ceil`/`round` 等），工厂方法 `createForBuffSystem()` 供 Buff 系统使用 |
| `property/` | `PropertyAccessor` | 动态属性访问器，支持计算属性、校验和变更回调 |
| `iterator/` | `IIterator` 接口 | 迭代器模式（`next`/`hasNext`/`reset`/`dispose`），实现类：`ArrayIterator`、`ObjectIterator`、`TreeSetMinimalIterator`、`OrderedMapMinimalIterator` |
| `json/` | `JSONLoader` | 异步 JSON 文件加载器，支持 `"JSON"`/`"LiteJSON"`/`"FastJSON"` 三种解析器 |
| `symbol/` | `Symbol` | UUID 唯一符号生成与全局注册表 |
| `arguments/` | `ArgumentsUtil` | `arguments` 对象操作：`slice`/`toArray`/`forEach`/`map`/`reduce`/`combineArgs` |
| `depth/` | `DepthManager` | AVL 树深度排序管理器（懒处理模式）——当前未投入使用（见第 8 节） |
| `path/` | `PathManager` | 资源路径管理与环境检测（resource/browser/Steam） |
| `text/` | `IntelligenceTextLoader` | 智能文本加载器（自动编码检测） |
| `tooltip/` | `TooltipComposer` | 格式化提示文本合成，含 `SkillTooltipComposer` 技能专用子类 |
| `toml/` | `TOMLParser` | TOML 格式解析器 |
| `fntl/` | `FNTLParser` | FNTL（FlashNight Text Language）自定义数据格式解析器 |
| `regexp/` | `RegExp` | 自定义正则表达式实现 |
| `paint/` | `RendererVM` | 图形渲染指令虚拟机 |
| `xml/` | — | XML 解析与操作工具 |

### 高频使用示例

```actionscript
// 数组操作
var evens:Array = ArrayUtil.filter(arr, function(x) { return x % 2 == 0; });
var grouped:Object = ArrayUtil.groupBy(items, function(item) { return item.type; });

// 安全数值
var clamped:Number = NumberUtil.clamp(value, 0, 100);
var safe:Number = NumberUtil.defaultIfNaN(parsed, 0);

// 对象深拷贝与序列化
var copy:Object = ObjectUtil.clone(original);
var json:String = ObjectUtil.toJSON(data);

// 表达式求值（Buff 系统等动态公式）
var eval:PrattEvaluator = PrattEvaluator.createForBuffSystem();
eval.setVariable("攻击力", 150);
var result = eval.evaluate("攻击力 * 1.5 + 20");
```

## 11. 小游戏系统（尚未投入使用）
- **位置**：`scripts/类定义/org/flashNight/hana/`
- **状态**：当前尚未投入使用
- **定位**：作为资源文件存在，主要提供各类 AS 链接影片剪辑等资源。子 SWF 本身被视为一种资源文件，加载后其库符号注入主文件运行时环境，在主文件作用域内运行（详见架构文档「子 SWF 加载与通信」一节）

## 12. 关卡系统
- **帧脚本**：`scripts/逻辑/关卡系统/`
- **数据**：`data/stages/`
<!-- TODO: 补充关卡系统的运行流程 -->
