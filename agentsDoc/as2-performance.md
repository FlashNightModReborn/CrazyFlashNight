# AS2 性能特性与优化指引

> 本项目在 `scripts/优化随笔/` 下积累了 24 篇深度 AS2 性能研究。
> 本文档提供分类索引与关键结论摘要，用于在性能敏感场景下快速查阅。

---

## 1. 索引：按主题分类

### 位运算与底层优化
| 文件 | 主题 |
|------|------|
| `AS2 中 Number 类型的位运算与内存优化.md` | Number 类型的位运算特性 |
| `位运算加速.md` | 位运算替代常规算术的加速方案 |
| `字符串下的位运算表现.md` | 字符串与位运算的交互性能 |
| `ActionScript 2 (AS2) 分支预测性能试验技术总结.md` | 分支预测对性能的影响 |
| `分支预测视角下的优化指引.md` | 基于分支预测的优化决策指引 |
| `ActionScript 2  标志位组合算法性能微基准实验报告.md` | 标志位组合算法的基准测试 |
| `ActionScript 2 中 NaN-Boxing 技术评估报告.md` | NaN-Boxing 技术可行性评估 |

### 循环与迭代
| 文件 | 主题 |
|------|------|
| `循环展开优化因子的选择测试.md` | 循环展开的最优因子 |
| `for in 循环性能优化尝试.md` | for...in 循环的性能特性 |
| `ActionScript 2.0 for...in 循环中动态修改对象属性的安全性及行为特性研究报告.md` | for...in 中动态修改的安全性 |
| `数组填充移除性能测试评估.md` | 数组操作的性能评估 |

### 运算与表达式
| 文件 | 主题 |
|------|------|
| `运算符性能测试评估.md` | 各运算符的性能对比 |
| `逻辑运算符性能测试评估.md` | 逻辑运算符的性能特性 |
| `交换变量的性能评估.md` | 变量交换的最优方式 |
| `对降低abs取绝对值操作开销的探索.md` | Math.abs 替代方案 |
| `对降低floor取整操作开销的探索.md` | Math.floor 替代方案 |

### 字符串与对象
| 文件 | 主题 |
|------|------|
| `字符串性能评估.md` | 字符串操作的性能特性 |
| `分析 AS2 中对象属性的哈希函数实现.md` | 对象属性哈希机制分析 |
| `原型链注入的性能评估.md` | 原型链注入对性能的影响 |

### 运行时与内存
| 文件 | 主题 |
|------|------|
| `EnterFrame事件的性能分析报告.md` | EnterFrame 事件的性能开销 |
| `as2环境下的缓存命中优化评估.md` | 缓存命中率优化策略 |
| `异常兜底措施的性能评估与优化.md` | try-catch 的性能影响 |

### AVM1 字节码与编译器行为
| 文件 | 主题 |
|------|------|
| `scripts/类定义/org/flashNight/naki/Sort/evalorder.md` | AS2 求值顺序规则文档 |
| `scripts/类定义/org/flashNight/naki/Sort/EvalOrderTest.as` | 求值顺序验证测试 |
| `scripts/类定义/org/flashNight/naki/Sort/TimSort.as`（文件头注释）| AVM1 平台决策记录：偏移寻址、StoreRegister、隐式布尔转换 |

> 注：`evalorder.md` 记录的是求值顺序本身的规则。`TimSort.as` 文件头的"AS2/AVM1 平台决策记录"
> 是目前项目中对 AVM1 字节码行为最详尽的实测总结，涵盖偏移寻址 vs 自增、StoreRegister 机制、
> 隐式布尔转换快速路径等，均附有字节码反汇编验证。副作用压行触发寄存器优化的性能收益来自长期
> 工程实践验证，非单一基准测试。

### 综合与工程
| 文件 | 主题 |
|------|------|
| `对as2本身一些性能优化点的测试探索.md` | 综合性能优化探索 |
| `GitHub项目瘦身记录.md` | 仓库体积优化 |

---

## 2. 关键性能结论摘要

<!-- 格式：▸ [主题] — [关键结论] -->
<!-- 持续补充：每次阅读优化随笔或深度优化代码时，在此追加一行摘要 -->

▸ **偏移寻址 vs 自增** — 批量拷贝用 `arr[d+k]...d+=4` 优于 `arr[d++]×4`。AVM1 中 `d++` 编译为 4 条字节码（read-dup-increment-store），`d+k` 仅 3 条（push-k-add），每 4 路展开净省 4 条指令。尾部余量仍用 `d++`（仅 0-3 次，不值得展开）。来源：`TimSort.as` 平台决策记录，实测 d++ 版本性能回退已确认

▸ **StoreRegister 机制** — AVM1 编译器仅在**副作用语句**中生成 StoreRegister（store-without-pop，值留栈继续参与运算）。独立语句 `j--` 走 GetVariable/SetVariable 变量名查找路径，开销显著更高。因此 `arr[--j+2]=tmp` 优于分离的 `arr[j+1]=tmp; j--;`。根因：AVM1 时代 CPU 寄存器稀缺，编译器仅副作用上下文分配寄存器。来源：`TimSort.as` 平台决策记录 + `evalorder.md` 验证测试

▸ **隐式布尔转换优于三元** — `compare(a,b)<=0` 返回 Boolean，AVM1 的 ActionSubtract 等算术指令内部硬连线 Boolean→Number 快速路径，比显式三元 `(cond ? 1 : 0)` 更快。勿尝试"装箱消除"优化。来源：`TimSort.as` 平台决策记录

▸ **间接排序键预提取** — 当排序键需要通过函数调用或属性访问获取时，先提取到独立 Number 数组，用内联 `keys[X] OP keys[Y]` 替代 `compare(X,Y)` 函数调用，可获得 **38%~67% 性能提升**（全数据模式均受益）。来源：`TimSort.sortIndirect()` 基准测试

▸ **哨兵搬运 + do-while** — 如果能预先确定首输出元素的归属（如合并前 pre-trim），可将 `while` 循环转为 `do-while`，省去入口条件检查。TimSort 合并阶段均使用此手法。来源：`TIMSORT_MERGE.as` P3 优化

▸ **算法参数应随比较开销调整** — TimSort `sort()` 使用 MIN_GALLOP=9（函数调用比较，延迟进入 gallop 更优），`sortIndirect()` 使用 MIN_GALLOP=7（内联比较，更早进入 gallop 有利）。算法参数不能照搬教科书默认值，需根据平台实际比较开销做 benchmark 调优。来源：`TimSort.as` 两个入口的参数差异

▸ **GC 阈值缓存策略** — 静态工作区跨调用复用减少 `new Array()` GC 压力；清理时大于阈值（如 256）释放防止引用泄漏，小于阈值保留复用。来源：`TimSort.as` _workspace 管理

▸ **重入保护 + 安全降级** — 使用静态缓存的热路径组件需 `_inUse` 标志防重入 + `resetState()` 安全阀防异常后永久锁死 + trace 警告 + 降级到原生实现而非崩溃。来源：`TimSort.as` 重入保护机制

▸ **属性索引缓存（var 包裹）** — AS2 中每次属性索引（`obj.prop`）都走哈希查找 + 作用域链遍历，开销远高于局部变量读取。**同一属性出现 2 次以上就值得 `var` 缓存**。典型模式：`var gameWorld:MovieClip = _root.gameworld;` 后续全部用 `gameWorld`。对嵌套属性（`_root.gameworld[bullet.发射者名]`）、数组元素（`areas.xMin`）同样适用。来源：`BulletQueueProcessor.as` processQueue() 大量实践（行 1680-1741），`分析 AS2 中对象属性的哈希函数实现.md`

▸ **长类名 var 别名** — 项目类名普遍极长（如 `ColliderFactoryRegistry`、`BulletCancelQueueProcessor`），在热路径中应将类引用、静态方法、静态属性缓存到局部 `var`，同时缩短名称。例：`var Dodge:Object = DodgeHandler;` `var CFR:Object = ColliderFactoryRegistry;` `var PolyFactoryId:String = ColliderFactoryRegistry.PolygonFactory;`。既减少属性查找开销，又降低字节码中字符串常量的重复存储。来源：`BulletQueueProcessor.as` 行 1688-1694

▸ **宏注入静态常量** — 通过 `#include "../macros/FLAG_CHAIN.as"` 将标志位等常量在编译期注入为文本替换，使其成为函数内的局部 `var` 定义。优于静态类属性（省去类名查找）和字面量硬编码（保留语义命名）。适用于位掩码、状态标志、阈值等不变量。组合常量可预计算：`var MELEE_EXPLOSIVE_MASK:Number = FLAG_MELEE | FLAG_EXPLOSIVE;`。来源：`BulletQueueProcessor.as` 行 568-572、1670-1682

▸ **变量声明提升到函数顶部** — 在大型热路径函数中，将所有 `var` 声明集中到函数入口（而非循环内部），避免 AVM1 对循环内 `var` 的重复初始化开销。来源：`BulletQueueProcessor.as` 行 1748-1835 统一声明区域

▸ **静态对象复用（零分配热路径）** — 在同步处理保证安全的前提下，使用静态预分配对象在帧间复用：`_rayHitResult`（碰撞结果）、`_rayHitCtx`（命中上下文打包对象）。避免每次命中 `new Object()` 产生 GC 压力。来源：`BulletQueueProcessor.as` 行 119-130

▸ **位运算编码紧凑状态** — 将多维状态（帧 ID + 队列 UID + 模式）编码为单个 Number：`token = (queueStamp << 2) | mode`，验证时 `(token >>> 2)` 解码。避免每个子弹分配 Object 存储状态。来源：`BulletQueueProcessor.as` cancelToken 编码（行 174-193）

▸ **结构体数组（SoA）替代对象数组（AoS）** — 将对象数组拆为多个平行数组（`xMinArr`、`xMaxArr`、`yMinArr`…），紧密循环中按索引访问比逐对象属性查找更快，且对缓存更友好。来源：`BulletQueueProcessor.as` 消弹区域缓存（行 1711-1741）

---

## 3. 优化决策快查表

<!-- 持续补充：每次发现新的优化决策规则时追加 -->

| 场景 | 推荐方案 | 依据 |
|------|----------|------|
| 同一属性访问 ≥ 2 次 | `var local = obj.prop;` 缓存到局部变量 | 属性索引走哈希查找 + 作用域链，局部变量直接寄存器/栈访问。`BulletQueueProcessor.as` 全面实践 |
| 类名极长（如 `ColliderFactoryRegistry`） | `var CFR:Object = ColliderFactoryRegistry;` 别名缓存类引用、方法、属性 | 减少属性查找 + 缩短字节码字符串常量。`BulletQueueProcessor.as:1688-1694` |
| 位掩码/状态标志等不变量 | 通过 `#include` 宏注入为函数内局部 `var`，组合常量预计算 | 编译期文本替换，零运行时类名查找开销。`BulletQueueProcessor.as:1670-1682` |
| 多步计算需要临时变量 | 利用副作用语句压行，触发 StoreRegister 寄存器快速路径 | `evalorder.md` + `TimSort.as` 平台决策：副作用上下文中 `--j` 走 StoreRegister（3 字节码），独立 `j--` 走 GetVariable/SetVariable 名查找路径（更慢） |
| 批量数组拷贝 | 4 路展开 + **偏移寻址** `arr[d+k]...d+=4`，不用 `arr[d++]×4` | `TimSort.as` 平台决策：`d+k` = 3 字节码，`d++` = 4 字节码，每 4 路展开净省 4 条指令。尾部余量(len&3)仍用 `d++` |
| 布尔值参与算术运算 | 直接使用比较结果（Boolean），不要用三元 `(cond ? 1 : 0)` 显式装箱 | `TimSort.as` 平台决策：AVM1 ActionSubtract 硬连线 Boolean→Number 快速路径 |
| 按计算键排序 | 先提取键到独立 Number 数组，用内联 `keys[X] OP keys[Y]` 替代比较器函数调用 | `TimSort.sortIndirect()` 基准：38%~67% 提升 |
| 循环首次迭代可保证执行 | 哨兵搬运（预移走一个确定元素）+ 转为 `do-while` 省去入口条件 | `TIMSORT_MERGE.as` P3 优化 |
| 字符串拼接 | 裸 `+` 拼接，不用 `Array.join()` | `字符串性能评估.md` |
| 取绝对值 | 位运算替代 `Math.abs()` | `对降低abs取绝对值操作开销的探索.md` |
| 取整 | 位运算替代 `Math.floor()` | `对降低floor取整操作开销的探索.md` |
| 热路径组件使用静态缓存 | 阈值释放策略（小缓存保留复用，大缓存释放防 GC 泄漏）+ `_inUse` 重入保护 + `resetState()` 安全阀 | `TimSort.as` 静态 workspace 管理 |
| 大型热路径函数内的变量声明 | 所有 `var` 集中到函数入口，不在循环内部声明 | 避免 AVM1 循环内重复初始化。`BulletQueueProcessor.as:1748-1835` |
| 帧间复用的临时数据（同步处理） | 静态预分配对象复用（`_rayHitResult`、`_rayHitCtx`），不 `new` | 零 GC 压力。`BulletQueueProcessor.as:119-130` |
| 多维状态紧凑存储 | 位运算编码到单个 Number（`(id << N) \| mode`），避免分配 Object | `BulletQueueProcessor.as` cancelToken 编码 |
| 紧密循环访问对象属性数组 | SoA 拆分：对象数组 → 多个平行基元数组，按索引访问 | `BulletQueueProcessor.as` 消弹区域缓存（行 1711-1741） |

---

## 4. 使用说明

- 在编写性能敏感代码时，先检查本文档是否有相关主题的研究
- 如有，进入 `scripts/优化随笔/` 阅读完整研究报告后再做决策
- 新的性能发现应按照 `agentsDoc/self-optimization.md` 流程归档
