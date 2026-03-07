# AS2 性能特性与优化指引

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

## 2. 热路径编码规范（R01~R29）

> 完整规范含数据支撑、字节码验证、适用边界：`性能基准评估/AVM1性能基准总结与热路径编码规范.md` §10

### 访问
- **R01** 热循环中，外部变量首次使用前必须 `var local = xxx` 局部化
- **R02** 链式访问 `a.b.c` 循环内使用 >=2 次，必须缓存中间对象
- **R03** MovieClip 属性批量读写前，缓存 MC 引用到局部变量

### 调用
- **R04** 轻量 helper / 空 ctor / 纯转发函数必须确认触发 DF2（函数体中引用参数）
- **R05** 热路径禁止 `arguments`，用显式参数
- **R06** 热路径避免方法调用(`o.m()`)，优先缓存函数引用后直接调用
- **R07** 热路径禁止 `new`，使用对象池

### 字符串
- **R08** 字符串长度一律用 `length(s)`(14ns)，禁止 `s.length`(580ns) — 41x 差距，StringLength opcode vs GetMember
- **R09** 热路径禁止反复 `split()`，一次 split 后缓存结果
- **R10** 数字转换一律用 `Number(s)`，禁止 `+s`（AS2 编译器 bug：不生成 ToNumber）

### 类型与比较
- **R11** 热路径和可能跨类型的比较用 `===`（跨类型 `==` 贵 5.6x）
- **R12** 布尔转换一律用 `!!x`(28ns)，禁止 `Boolean(x)`(193ns) — 7x 差距
- **R13** NaN 检测用 `isNaN()`，禁止 `n != n`（AS2 中 NaN==NaN 为 true，n!=n 始终 false）

### 数学
- **R14** 热路径取整用 `(x|0)`(29ns)（仅限正数/截断语义），负数用缓存 Math.floor 引用
- **R15** 热路径 min/max/abs/clamp 用三元表达式(30~58ns)，不用 Math.xxx(249~264ns)
- **R16** 不能内联的 Math(sin/cos/sqrt/atan2) 缓存引用：`var msin:Function = Math.sin;`(省~44%)
- **R17** 禁止 `~~x` 取整(69ns,4ops)，用 `x|0`(29ns,1op)

### 控制流
- **R18** 热路径禁止 `for-in`(2200~7800ns/iter)，用预存键数组 + `while(i--)`
- **R19** 热路径禁止 `with`(409ns)
- **R20** 热路径禁止 `try-catch`，异常处理放外层
- **R21** 逻辑短路：最可能 false 的条件放 `&&` 左侧

### 容器
- **R22** 热路径禁止 `splice`(4231ns)/`concat`(1673ns)/`unshift`(973ns)；队列用 head/tail index
- **R23** 清空数组用 `arr.length=0`(69ns)，不用 `arr=[]`(550ns+GC)

### GC 与分配
- **R24** 热路径禁止创建临时对象/数组字面量，复用预分配静态对象
- **R25** `apply` 参数数组必须预分配复用

### host/native 与生命周期
- **R26** 热路径禁止 `delete` 驱动生命周期，用 active flag / null 置空
- **R27** 热路径禁止依赖属性 miss 作控制流，预初始化所有可能读取的属性
- **R28** 输入采样每帧集中读取一次到 snapshot，逻辑层不直接调 `Key.isDown`(417ns)
- **R29** 逻辑层不得频繁直接读写 `_mc`，统一走 view flush

---

## 3. 索引：研究文档分类

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

## 4. 优化决策快查表

<!-- 持续补充：每次发现新的优化决策规则时追加 -->

| 场景 | 推荐方案 | 关键原理 | 来源 |
|------|----------|----------|------|
| 同一属性访问 ≥ 2 次 | `var local = obj.prop;` 缓存到局部变量 | 局部=register直读(0ns) vs 成员=GetMember(144ns) | 基准 `obj_dot_hit`、`BQP.as` |
| 类名极长 | `var CFR:Object = ColliderFactoryRegistry;` 别名缓存 | 减少属性查找 + 缩短字节码字符串常量 | `BQP.as:1688-1694` |
| 位掩码/状态标志等不变量 | `#include` 宏注入为函数内局部 `var`，组合常量预计算 | 编译期文本替换，零运行时类名查找 | `BQP.as:1670-1682` |
| 多步计算临时变量 | 副作用语句压行（`arr[--j+2]=tmp`），触发 StoreRegister | AVM1 副作用上下文走 StoreRegister（3 字节码），独立 `j--` 走名查找（更慢） | `TimSort.as` + `evalorder.md` |
| 批量数组拷贝 | 4 路展开 + 偏移寻址 `arr[d+k]...d+=4` | `d+k` = 3 字节码，`d++` = 4 字节码，每 4 路净省 4 条指令 | `TimSort.as` 平台决策 |
| 布尔参与算术 | 直接使用比较结果，不用 `(cond ? 1 : 0)` | AVM1 ActionSubtract 硬连线 Boolean→Number 快速路径 | `TimSort.as` 平台决策 |
| 按计算键排序 | 预提取键到 Number 数组，内联比较 | 消除比较器函数调用开销(485ns/call)，38%~67% 提升 | `TimSort.sortIndirect()` |
| 循环首次迭代可保证执行 | 哨兵搬运 + `do-while` | do-while 305ns/iter vs while 336ns/iter | `TIMSORT_MERGE.as` P3 |
| 字符串拼接 | 裸 `+` 拼接(54ns)，不用 `Array.join()`(495ns) | join 走 CallMethod | `字符串性能评估.md` + 基准 |
| 取绝对值 | `x<0?-x:x`(58ns)，不用 `Math.abs()`(249ns) | 三元=内联opcode vs Math=GetVariable+CallMethod | 基准 `abs_ternary` |
| 取整 | `x\|0`(29ns)，不用 `Math.floor()`(254ns)。**仅限正数/截断语义** | BitOr 1op vs 三步查找+调用 | 基准 `floor_bitor0` |
| clamp | `a<lo?lo:(a>hi?hi:a)`(40ns)，不用 `Math.min(Math.max())`(274ns) | 6.8x 差距 | 基准 `clamp_ternary` |
| 字符串长度 | `length(s)`(14ns)，不用 `s.length`(580ns) | StringLength opcode vs GetMember | 基准 `str_length_as1` |
| 布尔转换 | `!!x`(28ns)，不用 `Boolean(x)`(193ns) | Not+Not vs CallFunction | 基准 `to_bool_doublenot` |
| 数字转换 | `Number(s)`(76ns)，禁止 `+s`(不转换!) | `+s` 无 ToNumber opcode（AS2 编译器 bug） | 基准 + BytecodeProbe |
| NaN 检测 | `isNaN(n)`，禁止 `n!=n` | AS2 中 NaN==NaN=true（违反 IEEE754） | BytecodeProbe 探针 B |
| 热路径静态缓存 | 阈值释放（≤256 保留，>256 释放）+ `_inUse` 重入保护 | 小缓存复用减 GC，大缓存释放防泄漏 | `TimSort.as` workspace |
| 大型函数变量声明 | 所有 `var` 集中到函数入口 | 避免 AVM1 循环内重复初始化 | `BQP.as:1748-1835` |
| 帧间临时数据（同步） | 静态预分配对象复用，不 `new` | new=847ns+GC压力 | `BQP.as:119-130` + 基准 |
| 多维状态紧凑存储 | 位运算编码到单个 Number（`(id << N) \| mode`） | 避免每实例分配 Object(900ns) | `BQP.as` cancelToken |
| 紧密循环对象属性数组 | SoA 拆分：对象数组 → 多个平行基元数组 | 索引访问(35ns) vs 成员访问(144ns) | `BQP.as:1711-1741` |
| 空函数/ctor 调用 | 确保触发 DF2（函数体引用参数） | DF1=1079ns vs DF2=485ns(2.2x) | 基准 `call_empty_df1/df2` |
| 队列操作 | head/tail index，禁止 shift/unshift | shift=405ns, unshift=973ns, splice=4231ns | 基准 `arr_shift/unshift/splice` |
| 实体删除 | 标记删除+定期压缩，禁止 splice | splice=4231ns，delete=166ns | 基准 |
| Math.sin/cos 等 | `var ms:Function=Math.sin;` 缓存引用 | 直调 265ns → 缓存 147ns(省44%) | 基准 `cached_math_sin` |
| 输入采样 | 每帧集中读一次 snapshot | Key.isDown=417ns/次 | 基准 `native_keyisdown` |

> **BQP** = `BulletQueueProcessor.as`（缩写，避免表格过宽）

---

## 5. 不应通用化的经验策略

> 以下结论不够硬，不能写进编码规范，仅供特定场景参考：

- "AOS 一定比 SOA 快" — benchmark workload 不对称（AOS 有局部别名，SOA 用全局数组）
- "所有函数都要强制 DF2" — 仅限 tiny wrapper/ctor，函数体有实质逻辑时差异被稀释
- "`===` 总比 `==` 快" — 同类型差异仅 ~2ns
- "do-while 比 for 快" — ~9% 差异，远不如减访问/调用层级
- "缓存 Math.xxx 就够了" — 缓存只减查找税(~110ns)，能内联的应优先内联
- "switch vs if-else" — 差异仅 ~13%，适合热状态机专题策略
- "typed vs untyped 影响性能" — 字节码完全一致，运行时擦除

---

## 6. 使用说明

- 编写性能敏感代码时，**先查 §2 热路径规范**确认是否有硬性约束
- 做工程决策时，查 §4 快查表 找对应场景
- 需要详细数据支撑时，进入 `scripts/优化随笔/性能基准评估/AVM1性能基准总结与热路径编码规范.md` 阅读完整报告
- 遇到前人研究的细分主题，查 §3 索引定位对应文档
- 新的性能发现应按照 `agentsDoc/self-optimization.md` 流程归档
