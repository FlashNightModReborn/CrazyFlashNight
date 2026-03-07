# AS2 性能特性与优化指引

---

## 0. 证据分层说明

本文档使用以下证据标签。**不同标签的结论有不同的使用方式**：

| 标签 | 含义 | 证据基础 | 使用方式 |
|------|------|---------|---------|
| `[T1a]` | **硬规则 · 零前提** | benchmark + BytecodeProbe 双重确认，无语义风险 | 新写代码直接遵循。存量改写范围见 §12 P0（部分为批量搜改，部分为结构重写） |
| `[T1b]` | **硬规则 · 有前提** | benchmark + BytecodeProbe 双重确认，但替换依赖值域/语义/上下文前提 | 逐调用点确认前提条件后替换，不可批量搜改 |
| `[T2]` | **工程策略** | benchmark 证明了成本方向，但替代方案的全链路成本未被基准覆盖 | 按热点模块试点，先 profile 再改写 |
| `[T3]` | **实验策略** | 数据不足、有已知反例、或 workload 不对称 | 仅供参考，不作为改写依据 |
| `[P]` | **平台经验** | 字节码反汇编 / 项目实战验证，但非当前 benchmark 体系产出 | 可信，但证据源独立于 benchmark |

---

## 1. AVM1 成本阶梯（速查）

> 来源：165 项基准测试（bench_gen_v8 / 2M ops / 9 repeats）+ BytecodeProbe 字节码反汇编验证。
> 完整数据与方法学：`性能基准评估/AVM1性能基准总结与热路径编码规范.md`

| 成本带 | per-op | 典型操作 |
|--------|--------|---------|
| **免费** | 0~30ns | 局部变量读写、算术、位运算、typeof、`!!n` |
| **低税** | 30~100ns | 数组索引(~35ns)、`_root`读(~46ns)、三元表达式、`Number(s)`(76ns) |
| **中税** | 100~300ns | 成员读写(~150ns)、native属性(~170ns)、`Math.xxx`(~255ns)、`parseInt`(231ns) |
| **高税** | 300~700ns | 函数调用(485ns)、`s.length`(580ns)、字符串方法(580~760ns)、`with`(409ns) |
| **极重** | 700~1600ns | 方法调用(1340ns)、闭包(1235ns)、`arguments`(1538ns)、`new`(847ns)、`split`(1499ns) |

---

## 2. Tier 1 · 硬规则

### 2a. 零前提（新代码直接遵循）

> 每条均有 benchmark + BytecodeProbe 双重确认，无语义风险。其中部分为写法等价变换（可批量搜改，见 P0），部分为编码准则（新写时遵循，存量按热点逐步改造）。

**访问**

- **H01** `[T1a]` 热循环中，外部变量首次使用前必须 `var local = xxx` 局部化
  - 局部=register 直读(0ns) vs 全局=GetVariable(98ns) vs 成员=GetMember(144ns)
- **H02** `[T1a]` 链式访问 `a.b.c` 循环内使用 >=2 次，必须缓存中间对象
  - 每多一层约 +80ns（chain_depth2=179ns, chain_depth3=230ns）
- **H03** `[T1a]` MovieClip 属性批量读写前，缓存 MC 引用到局部变量

**字符串与类型转换**

- **H04** `[T1a]` 字符串长度一律用 `length(s)`(14ns)，禁止 `s.length`(580ns) — 41x 差距
  - 字节码：`length(s)` → StringLength opcode；`s.length` → GetMember "length"
  - 注意：`length()` 仅对字符串有效，数组长度仍用 `arr.length`
- **H05** `[T1a]` 数字转换一律用 `Number(s)`，**绝对禁止** `+s`
  - AS2 编译器 bug：`+s` 编译为 `Push s`（无 ToNumber），不做任何类型转换
- **H06** `[T1a]` 布尔转换一律用 `!!x`(28ns)，禁止 `Boolean(x)`(193ns) — 7x 差距
  - 字节码：`!!x` → Not, Not；`Boolean(x)` → CallFunction "Boolean"
- **H07** `[T1a]` NaN 检测用 `isNaN()`，禁止 `n != n`
  - AS2 中 `NaN == NaN` 返回 true（违反 IEEE 754），`n != n` 始终 false

**调用**

- **H09** `[T1a]` 热路径禁止 `arguments`，用显式参数
  - arguments.length=1538ns，arguments 读取=1306ns

**数学**

- **H11** `[T1a]` 不能内联的 Math(sin/cos/sqrt/atan2) 缓存引用：`var msin:Function = Math.sin;`
  - 直调 265ns → 缓存 147ns(省44%)
- **H12** `[T1a]` 禁止 `~~x` 取整(69ns, 4ops)，用 `x|0`(29ns, 1op)

**控制流**

- **H16** `[T1a]` 热路径禁止 `for-in`(2200~7800ns/iter)，用预存键数组 + `while(i--)`
- **H17** `[T1a]` 热路径禁止 `with`(409ns)
- **H18** `[T1a]` 热路径禁止 `try-catch` 包裹，异常处理放外层

**容器**

- **H20** `[T1a]` 热路径禁止 `splice`(4231ns)/`concat`(1673ns)/`unshift`(973ns)
  - 队列用 head/tail index 或环形缓冲
- **H21** `[T1a]` 清空数组用 `arr.length=0`(69ns)，不用 `arr=[]`(550ns+GC)

### 2b. 有前提（逐调用点审查后替换）

> benchmark + BytecodeProbe 双重确认性能差距真实存在，但替换有值域/语义前提，不可全局搜改。

**跨类型比较**

- **H08** `[T1b]` 热路径用 `===` 替代 `==`（跨类型 `==` 贵 5.6x）
  - 同类型差异仅 ~2ns，冷路径无需替换
  - ⚠️ **前提**：该比较点不依赖 `==` 的隐式 coercion（如 `"42" == 42` 依赖自动转换则不能直接替换）。安全场景：(a) 类型已在比较前归一化，或 (b) 确认双方始终同类型但想防御混入

**逻辑短路**

- **H19** `[T1b]` 逻辑短路：最可能 false 的条件放 `&&` 左侧
  - ⚠️ **前提**：条件求值无副作用，且不存在 guard 顺序依赖（如 `obj != null && obj.x > 0` 中左侧是右侧的安全前提，不能调换）

**DF2 审计**

- **H10** `[T1b]` 轻量 helper / 空 ctor / 纯转发函数确认触发 DF2（函数体中引用参数）
  - DF1=1079ns vs DF2=485ns(2.2x)
  - 前提：仅限函数体极轻的情况。函数体有实质逻辑时差异被稀释，无需改动

**数学内联替换**

- **H13** `[T1b]` 热路径取整用 `(x|0)`(29ns) 替代 `Math.floor()`(254ns) — **8.7x**
  - ⚠️ **前提（全部必须满足）**：
    - (a) x 是有限数值（NaN|0 → 0，Infinity|0 → 0，静默吞掉异常值）
    - (b) x 在 Int32 范围内（|x| < 2^31，超范围截断为错误值）
    - (c) x≥0，或截断语义可接受（`x|0` 是 toward-zero 截断，`-3.7|0 = -3` 而非 `-4`）
  - 不满足任一前提时，用缓存的 `Math.floor` 引用（142ns）
- **H14** `[T1b]` 热路径 abs 用 `x<0?-x:x`(58ns) 替代 `Math.abs()`(249ns) — **4.3x**
  - ⚠️ **前提**：输入为有限数值。NaN 输入时 `x<0` 为 false，返回原 NaN（行为碰巧一致，但依赖实现细节）
- **H15** `[T1b]` 热路径 min/max/clamp 用三元表达式替代 `Math.min/max`
  - `a<b?a:b`(31ns) vs `Math.min(a,b)`(264ns) — **8.5x**
  - `a<lo?lo:(a>hi?hi:a)`(40ns) vs `Math.min(Math.max())`(274ns) — **6.8x**
  - ⚠️ **前提**：仅限二元、已知有限数值。NaN 输入时三元返回 NaN 或另一个操作数（取决于比较顺序），与 Math.min/max 行为不同

---

## 3. Tier 2 · 工程策略

> benchmark 证明了成本方向，但替代方案的全链路成本未被基准覆盖。每条需按模块 profile 后试点。

### 调用形态

- **S01** `[T2]` 热路径中 `o.m()` 方法调用极贵(1340ns)。优化方向：**减少调用次数**或**改变 API 形态**（如将方法改为接受批量参数的静态函数），而非简单缓存方法引用
  - ⚠️ `var f = o.m; f()` 会丢失 `this` 绑定——AS2 中函数引用不携带 receiver。benchmark 证明了 `o.m()` 贵，但没有覆盖"缓存后直接调用"这个改写路径。安全的做法是：(a) 仅限不依赖 `this` 的纯函数/工具方法，或 (b) 先将方法重构为不依赖 receiver 的形态，再改调用点
- **S02** `[T2]` `new` 本身 847~915ns，是极重操作。但"使用对象池"不是自动更优的替代
  - 当前项目 ObjectPool.as 的 `getObject()` 链路包含：`resetFunc.apply(obj, arguments)`（apply+arguments，极重带）；`createNewObject()` 用 `Delegate.create`（闭包，极重带）；`releaseObject()` 用 `Array.prototype.slice.call(arguments, 1)`（三重极重操作）。池的全链路成本可能不低于直接 `new`
  - 正确做法：(a) 对具体 workload profile 全链路成本（create+use+release），(b) 轻量场景考虑手写 inline 池（无 apply/arguments/Delegate），(c) 不要机械地把所有 `new` 替换为池调用

### 分配与 GC

- **S03** `[T2]` 热路径避免创建临时对象/数组字面量，复用预分配静态对象
  - new Object()=900ns, new Array()=550ns, {}=350ns。方向正确，但"预分配"本身的管理成本（重入保护、生命周期）需要按场景评估
- **S04** `[T2]` `apply` 参数数组应预分配复用，避免每次创建新数组
- **S05** `[T2]` 热路径 `split()` 极贵(1499ns)且每次创建新数组，一次 split 后缓存结果

### host/native 边界

- **S06** `[T2]` 输入采样每帧集中读取一次到 snapshot，逻辑层只消费快照
  - Key.isDown=417ns/次。方向正确，但 InputSnapshot 的具体实现成本取决于采样的按键数量和分发机制
- **S07** `[T2]` 逻辑层不得直接频繁读写 `_mc`(170ns/次)，统一走 view flush
  - 适用于单帧内同一属性被多次读写的场景。如果每帧只读写一次，flush 层反而增加间接成本
- **S08** `[T2]` 热路径避免 `delete` 驱动生命周期，优先用 active flag / null 置空
  - `delete` 在 AS2 中会修改对象哈希结构。但 benchmark 的 `delete_prop`(166ns) 测的是简单属性删除，不代表实体容器删除的成本

### 容器策略

- **S09** `[T2]` 实体列表避免 `splice` 删除(4231ns)。可选方案：标记删除+定期压缩、swap-with-last+pop、或双缓冲切换
  - 具体哪种方案最优取决于删除频率、遍历频率、顺序是否重要。需 profile 实际 workload
- **S10** `[T2]` 属性 miss(读取不存在的属性)有额外成本(~158ns)且返回 undefined。频繁读取的属性应预初始化

---

## 4. Tier 3 · 实验策略

> 数据不足、有已知反例、或 workload 不对称。仅供特定场景参考，不作为改写依据。

| 项 | 为什么在 Tier 3 |
|----|----------------|
| "AOS 一定比 SOA 快" | benchmark 中 AOS 有局部别名缓存，SOA 用全局数组多了作用域查找税，workload 不对称 |
| "所有函数都要强制 DF2" | 仅限 tiny wrapper/ctor，函数体有实质逻辑时差异被稀释 |
| "`===` 总比 `==` 快" | 同类型差异仅 ~2ns |
| "do-while 比 for 快" | ~9% 差异，远不如减访问/调用层级 |
| "缓存 Math.xxx 就够了" | 缓存只减查找税(~110ns)，能内联的应优先内联 |
| "switch vs if-else 要统一换" | 差异仅 ~13%，适合热状态机专题策略 |
| "typed vs untyped 影响性能" | 字节码完全一致，运行时擦除 |
| "脏标记一定比直接写 host 快" | micro workload 落在 1ms timer quantum 边界，数据不可区分 |
| "对象池一定比 new 快" | 池本身的 apply/arguments/Delegate 链路可能抵消 new 的节省，需全链路 profile |

---

## 5. 优化决策快查表

<!-- 持续补充：每次发现新的优化决策规则时追加 -->

| 场景 | 推荐方案 | 标签 | 关键原理 | 来源 |
|------|----------|------|----------|------|
| 同一属性访问 ≥ 2 次 | `var local = obj.prop;` 缓存到局部变量 | T1a | 局部=register直读(0ns) vs 成员=GetMember(144ns) | 基准 `obj_dot_hit` |
| 字符串长度 | `length(s)`(14ns)，不用 `s.length`(580ns) | T1a | StringLength opcode vs GetMember | 基准 `str_length_as1` |
| 布尔转换 | `!!x`(28ns)，不用 `Boolean(x)`(193ns) | T1a | Not+Not vs CallFunction | 基准 `to_bool_doublenot` |
| 数字转换 | `Number(s)`(76ns)，禁止 `+s`(不转换!) | T1a | AS2 编译器 bug | 基准 + BytecodeProbe |
| NaN 检测 | `isNaN(n)`，禁止 `n!=n` | T1a | AS2 中 NaN==NaN=true | BytecodeProbe 探针 B |
| 字符串拼接 | 裸 `+` 拼接(54ns)，不用 `Array.join()`(495ns) | T1a | join 走 CallMethod | `字符串性能评估.md` + 基准 |
| Math.sin/cos 等 | `var ms:Function=Math.sin;` 缓存引用 | T1a | 直调 265ns → 缓存 147ns(省44%) | 基准 `cached_math_sin` |
| 空函数/ctor 调用 | 确保触发 DF2（函数体引用参数） | T1b | DF1=1079ns vs DF2=485ns(2.2x)。前提：函数体极轻 | 基准 `call_empty_df1/df2` |
| 队列操作 | head/tail index，避免 shift/unshift | T1a | shift=405ns, unshift=973ns, splice=4231ns | 基准 `arr_shift/unshift/splice` |
| 取整 | `x\|0`(29ns)，不用 `Math.floor()`(254ns) | T1b | **前提：有限数值 + Int32 范围 + x≥0 或截断可接受** | 基准 `floor_bitor0` |
| 取绝对值 | `x<0?-x:x`(58ns)，不用 `Math.abs()`(249ns) | T1b | **前提：已知有限数值输入** | 基准 `abs_ternary` |
| clamp | `a<lo?lo:(a>hi?hi:a)`(40ns) | T1b | **前提：已知有限数值、仅二元** | 基准 `clamp_ternary` |
| 跨类型比较 | `===` 替代 `==`（跨类型贵 5.6x） | T1b | **前提：不依赖 coercion，或类型已归一化** | 基准 `eq_str_num` |
| 类名极长 | `var CFR:Object = ColliderFactoryRegistry;` 别名缓存 | P | 减少属性查找 + 缩短字节码字符串常量 | `BQP.as:1688-1694` |
| 位掩码/状态标志等不变量 | `#include` 宏注入为函数内局部 `var`，组合常量预计算 | P | 编译期文本替换，零运行时类名查找 | `BQP.as:1670-1682` |
| 多步计算临时变量 | 副作用语句压行（`arr[--j+2]=tmp`），触发 StoreRegister | P | AVM1 副作用上下文走 StoreRegister（3 字节码） | `TimSort.as` + `evalorder.md` |
| 批量数组拷贝 | 4 路展开 + 偏移寻址 `arr[d+k]...d+=4` | P | `d+k` = 3 字节码，每 4 路净省 4 条指令 | `TimSort.as` 平台决策 |
| 布尔参与算术 | 直接使用比较结果，不用 `(cond ? 1 : 0)` | P | AVM1 ActionSubtract 硬连线 Boolean→Number 快速路径 | `TimSort.as` 平台决策 |
| 按计算键排序 | 预提取键到 Number 数组，内联比较 | P | 消除比较器函数调用开销(485ns/call) | `TimSort.sortIndirect()` |
| 大型函数变量声明 | 所有 `var` 集中到函数入口 | P | 避免 AVM1 循环内重复初始化 | `BQP.as:1748-1835` |
| 多维状态紧凑存储 | 位运算编码到单个 Number（`(id << N) \| mode`） | P | 避免每实例分配 Object(900ns) | `BQP.as` cancelToken |
| 循环首次迭代可保证执行 | 哨兵搬运 + `do-while` | T3 | do-while 305ns/iter vs while 336ns/iter，差异小 | `TIMSORT_MERGE.as` P3 |
| 热路径静态缓存 | 阈值释放（≤256 保留，>256 释放）+ `_inUse` 重入保护 | T2 | 小缓存复用减 GC，大缓存释放防泄漏。全链路成本需 profile | `TimSort.as` workspace |
| 帧间临时数据（同步） | 静态预分配对象复用 | T2 | new=847ns+GC压力。但管理成本需按场景评估 | `BQP.as:119-130` + 基准 |
| 实体列表删除 | 标记删除+定期压缩 / swap-with-last+pop | T2 | splice=4231ns。具体方案需按删除/遍历频率 profile | 基准 `arr_splice` |
| 输入采样 | 每帧集中读一次 snapshot | T2 | Key.isDown=417ns/次。具体实现成本取决于采样量 | 基准 `native_keyisdown` |
| 紧密循环对象属性数组 | SoA 拆分：对象数组 → 多个平行基元数组 | T3 | benchmark workload 不对称（AOS 有局部别名） | `BQP.as:1711-1741` |

> **BQP** = `BulletQueueProcessor.as`（缩写，避免表格过宽）

---

## 6. 索引：研究文档分类

> 所有文件均位于 `scripts/优化随笔/`，除非标注完整路径。

**AVM1 基准与字节码**（2026-03，基于 bench_gen_v8 + BytecodeProbe）：
- `性能基准评估/AVM1性能基准总结与热路径编码规范.md` — **综合总结，首读此文**
- `性能基准评估/AS2_NaN陷阱总结.md` — NaN 感染与防御
- `性能基准评估/BytecodeProbe.md` — JPEXS P-code 反汇编记录
- `性能基准评估/BytecodeProbe_Guide.md` — 反汇编操作指南
- `性能基准评估/codex.md` / `gpt5.4pro.md` — 外部交叉审阅报告

**位运算与底层**：Number位运算与内存优化 · 位运算加速 · 字符串下的位运算表现 · 分支预测性能试验 · 分支预测优化指引 · 标志位组合算法微基准 · NaN-Boxing技术评估

**循环与迭代**：循环展开优化因子 · for-in循环性能优化 · for-in动态修改安全性 · 数组填充移除性能

**运算与表达式**：运算符性能 · 逻辑运算符性能 · 交换变量性能 · abs取绝对值 · floor取整

**字符串与对象**：字符串性能评估 · 对象属性哈希函数实现 · 原型链注入性能

**运行时与内存**：EnterFrame性能分析 · 缓存命中优化 · 异常兜底措施性能

**AVM1 字节码（早期）**：
- `naki/Sort/evalorder.md` — 求值顺序规则
- `naki/Sort/TimSort.as`（文件头）— AVM1 平台决策记录（偏移寻址、StoreRegister、隐式布尔转换）

**综合**：as2性能优化探索 · GitHub项目瘦身记录

---

## 7. 使用说明

- 编写性能敏感代码时，**先查 §2a T1a 硬规则**——新代码直接遵循；存量哪些能批量搜改见 §12 P0
- §2b T1b 条目性能差距真实，但有值域/语义前提——逐调用点审查后替换
- 做架构决策时，查 §3 T2 工程策略——需先 profile 再决定
- 做工程决策时，查 §5 快查表找对应场景，注意标签列（T1a/T1b/T2/T3/P）
- `[P]` 标签为平台经验（字节码验证/项目实战），可信但证据源独立于 benchmark
- 需要详细数据支撑时，进入 `scripts/优化随笔/性能基准评估/AVM1性能基准总结与热路径编码规范.md` 阅读完整报告
- 遇到前人研究的细分主题，查 §6 索引定位对应文档
- **不要把 T1b/T2/T3 的结论当作全项目机械改写任务**
- 新的性能发现应按照 `agentsDoc/self-optimization.md` 流程归档
