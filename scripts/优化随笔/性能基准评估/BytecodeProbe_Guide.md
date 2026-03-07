# BytecodeProbe 反汇编对照指南

## 使用流程

1. Flash CS6 新建空 FLA（AS2，Flash Player 11）
2. 帧 1 脚本：`#include "BytecodeProbe.as"`
3. 发布为 SWF（不勾选"省略 trace"）
4. JPEXS 打开 SWF → scripts → frame 1 → 切换到 P-code 视图
5. 按下方表格逐函数记录 action 序列

## 逐探针对照清单

### 探针组 A：位运算（解决 bit_not 6.87x）

| 函数 | 对焦点 | 预测 | 记录列 |
|------|--------|------|--------|
| `probe_bit_and` | `b=a&0xFF` 的 action | Push a, Push 0xFF, BitAnd | 实际 action: |
| `probe_bit_or` | `b=a\|1` 的 action | Push a, Push 1, BitOr | 实际 action: |
| `probe_bit_not` | `b=~a` 的 action | Push a, BitNot（是否有额外转换?） | 实际 action: |
| `probe_bit_or_zero` | `b=a\|0` 的 action | Push a, Push 0, BitOr | 实际 action: |
| `probe_double_tilde` | `b=~~a` 的 action | 两条 BitNot？还是其他？ | 实际 action: |

**关键问题**：`~a` 是否比 `a&0xFF` 多出 ToInteger/ToNumber 转换 action？

### 探针组 B：NaN 比较（关键语义验证）

**首先运行 SWF 看 trace 输出**：

| trace 行 | 预测（标准 ECMAScript） | AS2 实际输出 |
|----------|----------------------|-------------|
| NaN == NaN | false | |
| NaN != NaN | true | |
| NaN === NaN | false | |
| NaN !== NaN | true | |
| n == n | false | |
| n != n | true | |

**如果 `NaN != NaN` = true**：`n!=n` 可用于 NaN 检测，源码注释错误
**如果 `NaN != NaN` = false**：`n!=n` 不能检测 NaN，5/9 报告的推荐规则必须删除

然后对比字节码：
| 函数 | 对焦点 |
|------|--------|
| `probe_isnan_selfne` | `n!=n` 生成什么 action |
| `probe_isnan_fn` | `isNaN(n)` 生成什么 action（函数调用 vs 内联？） |

### 探针组 C：一元加（确认编译器 bug）

| 函数 | 对焦点 | 预测 |
|------|--------|------|
| `probe_unary_plus` | `+s` 生成什么 | 可能只是 Push s（无 ToNumber） |
| `probe_number_cast` | `Number(s)` 生成什么 | 应有 CallFunction "Number" |

### 探针组 D：常量折叠

| 函数 | 对焦点 | 预测 |
|------|--------|------|
| `probe_const_fold` | `3+4` | 如果折叠：Push 7；如果未折叠：Push 3, Push 4, Add |
| `probe_var_add` | `a+c` | Push a, Push c, Add（不应折叠） |
| `probe_const_mul` | `6*7` | 如果折叠：Push 42 |

### 探针组 E：函数调用路径

| 函数 | 对焦点 | 预测 |
|------|--------|------|
| `probe_call_void` | `_emptyFn()` 无赋值 | CallFunction + Pop（清栈） |
| `probe_call_assign` | `b=_identityFn(1)` 赋值 | CallFunction（无 Pop，返回值被消费） |
| `probe_call_method` | `_gObj.emptyMethod()` | CallMethod + Pop |
| `probe_call_method_ret` | `b=_gObj.retMethod()` | CallMethod（无 Pop） |

**关键问题**：void 调用是否多一条 ActionPop？方法调用用 CallMethod 还是 CallFunction？

### 探针组 F：变量访问路径

| 函数 | 对焦点 | 预测 |
|------|--------|------|
| `probe_local_read` | 局部变量 `a` | GetRegister（寄存器直读） |
| `probe_global_read` | 全局变量 `_gVar` | GetVariable（作用域链查找） |
| `probe_member_read` | `_gObj.x` | GetVariable + GetMember |
| `probe_bracket_read` | `_gObj["x"]` | 应与 dot 相同 |

**关键问题**：局部变量是否用 register？dot vs bracket 是否生成相同 action？

### 探针组 G：typed vs untyped

| 函数 | 对焦点 | 预测 |
|------|--------|------|
| `probe_typed_local` | `var a:Number=42` | 类型声明可能被擦除，无额外 action |
| `probe_untyped_local` | `var a=42` | 应与 typed 完全相同 |

**关键问题**：`:Number` 类型标注是否生成任何额外的 Convert/Check 指令？

### 探针组 H：String.length vs Array.length

| 函数 | 对焦点 | 预测 |
|------|--------|------|
| `probe_str_length` | `s.length` | GetMember? 或 native getter? |
| `probe_arr_length` | `arr.length` | GetMember（应与 str 相同或不同？） |
| `probe_str_length_as1` | `length(s)` | 可能是专用 ActionStringLength |

**关键问题**：String.length 573ns 是否因为走了不同的 action 路径？

### 探针组 I：Boolean 转换

| 函数 | 对焦点 | 预测 |
|------|--------|------|
| `probe_boolean_cast` | `Boolean(n)` | CallFunction "Boolean"（函数调用开销） |
| `probe_double_not` | `!!n` | Not, Not（两条内联指令） |

### 探针组 J-T：其他探针

按相同模式记录即可，重点关注：
- **J**：`typeof` 是否有专用 ActionTypeOf
- **K**：`Math.floor(a)` 是 GetVariable("Math") + GetMember("floor") + CallMethod？
- **L**：switch 是否有跳表结构
- **M**：`==` vs `===` 用的是 ActionEquals2 vs ActionStrictEquals？
- **N**：new 生成什么 action 序列
- **Q**：局部数组 vs 全局数组的 receiver 查找差异

## 结果记录模板

完成反汇编后，请将每个探针的 P-code 复制到一个文本文件中，格式：

```
=== probe_bit_and ===
[粘贴 JPEXS 的 P-code]

=== probe_bit_not ===
[粘贴 JPEXS 的 P-code]
```

这份记录将用于：
1. 确认/否定 9 份报告中的字节码假说
2. 指导 benchmark v8 的测试项设计
3. 建立"源码写法 → 字节码 → 运行时成本"的三层映射
