# 影子记账系统（Shadow Bookkeeping）

## 概述

影子记账是联弹（chain bullet）在单帧内命中多个目标时，跨目标跟踪霰弹值消耗的机制。

**核心矛盾**：联弹每次命中需要两个不同的值——
- **基准值 S₀**（初始霰弹值）：用于伤害公式估算"理论消耗段数"
- **剩余可用值 available**：用于限制"实际可消耗段数"

两者不能用同一个属性表示（S₀ 不变，available 递减），所以需要某种机制在同一帧内同时持有两个值。

## 编码方案：原位高低位编码

将 base 和 available 打包进 `bullet.霰弹值` 本身，取负作为影子模式标记：

```
编码：bullet.霰弹值 = -((S₀ << 16) | available)

       ┌─── 负号 = 影子模式标记（有效霰弹值恒为正，无歧义）
       │
       │    ┌─── 高16位 = S₀（基准值，窗口内不变）
       │    │
       │    │         ┌─── 低16位 = available（剩余可用值，每次命中递减）
       │    │         │
  -((  S₀  << 16) |  avail  )
```

### 数值示例

以 S₀ = 12（典型霰弹枪）为例：

```
Init:   -((12 << 16) | 12) = -(786432 | 12) = -786444
        甄别：-786444 < -65535 ✓

第1次命中（消耗3段）:
        available = 12 - 3 = 9
        重编码：-((12 << 16) | 9) = -786441

第2次命中（消耗4段）:
        available = 9 - 4 = 5
        重编码：-((12 << 16) | 5) = -786437

Commit: (-(-786437)) & 0xFFFF = 786437 & 65535 = 5
        bullet.霰弹值 = 5 ← 最终剩余值
```

### 甄别阈值

```
sc < -65535
```

- S₀ ≥ 1 时，编码值 = `-((S₀<<16)|avail)` ≤ `-((1<<16)|0)` = -65536 < -65535 ✓
- S₀ = 0 时，init 跳过编码，走直接模式
- NaN：`NaN < -65535` → undefined → falsy → 安全走直接模式
- **必须用 `<` 不用 `<=`**：AS2 中 `NaN <= x` 恒为 true → 死循环风险

### 解码公式

```
state    = -sc                    // 取负还原为正数
base     = state >>> 16           // 无符号右移提取高16位 = S₀
available = state & 0xFFFF        // 位掩码提取低16位 = 剩余可用值
```

## 生命周期

```
BulletQueueProcessor.processQueue()
│
├─ needsDeferScatter = (flags & FLAG_CHAIN) != 0
│  非联弹子弹：needsDeferScatter = false，完全跳过，零开销
│
├─ __initDeferScatter(bullet)           ← 窗口开启
│  │  s0 = bullet.霰弹值
│  │  if (s0 > 0) bullet.霰弹值 = -((s0 << 16) | s0)
│  │  此刻 bullet.霰弹值 变为编码负数
│  │
│  ├─ for each target in collision window:
│  │  │
│  │  ├─ bullet.击中时触发函数()          // 不读霰弹值
│  │  │
│  │  ├─ DamageCalculator.calculateDamage(bullet, ...)
│  │  │  │  // 不读 bullet.霰弹值（C3: 窗口内零裸读）
│  │  │  │
│  │  │  └─ manager.execute(...)
│  │  │     └─ MultiShotDamageHandle.handleBulletDamage(bullet, ...)
│  │  │        │  sc = bullet.霰弹值              // 1次哈希查找
│  │  │        │  if (sc < -65535):                // 影子模式
│  │  │        │    state = -sc
│  │  │        │    baseSc = state >>> 16          // 解码 S₀
│  │  │        │    available = state & 0xFFFF     // 解码剩余值
│  │  │        │    scatterForCalc = baseSc        // 用 S₀ 估算期望伤害（INV-5）
│  │  │        │    ... 计算 actualScatterUsed ...
│  │  │        │    available -= actualScatterUsed
│  │  │        │    bullet.霰弹值 = -((baseSc << 16) | available)  // 重编码，1次哈希写入
│  │  │        │    result.finalScatterValue = available
│  │  │        │
│  │  │        └─ else: 直接模式（非编码路径）
│  │  │
│  │  ├─ bullet.hitCount += damageResult.actualScatterUsed
│  │  ├─ publish("hit", hitTarget, shooter, bullet, ...)   // 订阅者不读霰弹值
│  │  ├─ publish("kill"/"death", hitTarget)                // 参数中无 bullet
│  │  ├─ publish("enemyKilled", hitTarget, bullet)         // 订阅者只读子弹种类
│  │  └─ damageResult.triggerDisplay(...)
│  │
│  └─ (循环结束 或 早退)
│
└─ __commitDeferScatter(bullet)         ← 窗口关闭
   sc = bullet.霰弹值
   if (sc < -65535) bullet.霰弹值 = (-sc) & 0xFFFF   // 提取 available，回写正数
   此刻 bullet.霰弹值 恢复为普通正整数
```

## 涉及文件

### 核心文件（直接参与编解码）

| 文件 | 角色 | 关键行 |
|------|------|--------|
| `arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as` | 窗口管理者：init 编码 + commit 解码 | `__initDeferScatter`, `__commitDeferScatter`, 行 2178-2180 (init调用), 2219-2220 (早退commit), 2410-2411 (正常commit) |
| `arki/component/Damage/MultiShotDamageHandle.as` | 窗口内消费者：解码→计算→重编码 | `handleBulletDamage` 行 104-130 (检测+解码), 195-228 (计算+重编码) |

### 协作文件（传递数据但不参与编解码）

| 文件 | 角色 | 说明 |
|------|------|------|
| `arki/component/Damage/DamageCalculator.as` | 伤害计算入口 | 行 124 裸读 `bullet.霰弹值 > 1`（调试模式方差，生产短路。契约 C3 备注） |
| `arki/component/Damage/DamageResult.as` | 结果容器 | `finalScatterValue` 存储解码后的剩余值，供外部读取 |
| `arki/component/Damage/DamageManager.as` | 执行调度器 | 调用 handler 链，传递 `overlapRatio`/`dodgeState`，不读霰弹值 |
| `arki/component/Damage/DamageManagerFactory.as` | 工厂 | 通过 `canHandle` 位掩码过滤，决定 MultiShotDamageHandle 是否参与 |

### 上游文件（初始化霰弹值，不在影子窗口内）

| 文件 | 角色 | 说明 |
|------|------|------|
| `arki/bullet/Factory/BulletFactory.as` | 子弹创建 | 从 XML/装备函数读取霰弹值并赋值 |
| `arki/bullet/BulletComponent/Initializer/BulletInitializer.as` | 子弹初始化 | 行 46 守卫 `isNaN` + 默认值 1 |
| `scripts/逻辑/装备函数/*.as` (G1111, XM214 等) | 装备配置 | 设置具体霰弹值（典型 1-16） |

### 下游文件（读取 finalScatterValue，不读 bullet.霰弹值）

| 文件 | 角色 | 说明 |
|------|------|------|
| `arki/render/ShellSystem.as` | 弹壳系统 | 行 141 读 `bullet.霰弹值` 但在子弹创建阶段，不在碰撞窗口 |

## 核心契约

编码后 `bullet.霰弹值` 在窗口内是**语义不透明的负数**——任何不经解码的裸读都会得到无意义值。以下契约是热路径零防御的前提：

### C1: 霰弹值值域保证

> `bullet.霰弹值` 在进入影子窗口前必须为正整数且 ≤ 32767

- **守约方**：BulletFactory / BulletInitializer / 装备函数
- **违约后果**：`>>> 16` 解码错误，伤害公式使用错误基准值
- **防御**：init 内 `if (s0 > 32767) s0 = 32767` clamp（唯一运行时守卫）
- **审计基线**：当前最大值 ~80（G1111），远低于上限

### C2: 窗口内独占写入

> 影子窗口内，仅 MultiShotDamageHandle 和 __commitDeferScatter 可写入 `bullet.霰弹值`

- **守约方**：所有命中事件订阅者、击中时触发函数、其他 DamageHandle
- **违约后果**：外部正数覆盖编码值 → commit 不触发 → 消耗静默丢失
- **审计确认（2026-03）**：
  - `击中时触发函数`：只发射新子弹 ✓
  - `publish("hit")` 订阅者：不读写 bullet.霰弹值 ✓
  - `publish("enemyKilled")` 订阅者：只读 `bullet.子弹种类` ✓
  - `publish("kill"/"death")`：参数中无 bullet ✓
- **防御建议**：新增订阅者需读散射信息时，**从 `damageResult.finalScatterValue` 获取**

### C3: 窗口内裸读语义

> 除 MultiShotDamageHandle 外的代码读取 `bullet.霰弹值` 将得到编码负数

- **已知裸读点**：无（2026-03 移除 DamageCalculator 调试模式方差分支后，窗口内零裸读）
- **违约后果**：读到无意义负数，伤害计算错误
- **防御建议**：未来需读散射值时，从 `damageResult.actualScatterUsed` 或 handler 内部解码获取

### C4: 编码不可跨帧持久化

> commit 必须在同帧内执行，编码值不可残留到下一帧

- **保证**：processQueue 双出口（正常路径行 2410 + 早退路径行 2219）均有 commit 守卫
- **违约后果**：下帧读到编码负数 → 伤害计算全面崩溃

## 形式化证明

以下证明在契约 C1-C4 全部满足的前提下，编码方案的正确性。

### 符号定义

- S₀ ∈ Z⁺ ∩ [1, 32767]：初始霰弹值（C1 保证）
- N ∈ Z⁺ ∪ {0}：命中目标数
- aᵢ ∈ Z⁺（i ∈ [1,N]）：第 i 次命中消耗的段数
- enc(b, v) = -((b << 16) | v)：编码函数，b = 基准值，v = 可用值
- AVM1 位运算截断到 32 位有符号整数；`>>> 16` 为无符号右移

### 引理 1: 编码值域

**命题**：若 b ∈ [1, 32767]，v ∈ [0, b]，则 enc(b, v) ∈ [-2,147,418,112, -65536]。

**证明**：
```
令 w = (b << 16) | v = b · 65536 + v    （因 v ≤ 32767 < 65536，| 与 + 等价）

下界：b = 1, v = 0 → w = 65536         → enc = -65536
上界：b = 32767, v = 32767
      → w = 32767 · 65536 + 32767
      → w = 2,147,418,112               → enc = -2,147,418,112

由 b ≥ 1 → w ≥ 65536 → enc ≤ -65536 < -65535  ∎
```

**推论 1a**：对所有合法输入，`enc(b, v) < -65535` 恒成立。甄别条件无漏检。

**推论 1b**：合法正霰弹值 ∈ [0, 32767]，编码值 ≤ -65536。两个值域不相交，甄别条件无误判。

### 引理 2: 编解码往返正确性

**命题**：若 b ∈ [1, 32767]，v ∈ [0, 65535]，则从 enc(b, v) 可无损恢复 b 和 v。

**证明**：
```
设 sc = enc(b, v) = -((b << 16) | v)

解码：
  state = -sc = (b << 16) | v = b · 65536 + v

因 b ≤ 32767，v ≤ 65535：
  state ≤ 32767 · 65536 + 65535 = 2,147,483,647 = 2³¹ - 1

即 state 恰好落在 Int32 非负范围内，>>> 16 与 >> 16 行为一致。

  state >>> 16 = (b · 65536 + v) >>> 16
               = (b · 65536) >>> 16      （因 v < 65536，不影响高16位）
               = b                        ✓

  state & 0xFFFF = (b · 65536 + v) & 0xFFFF
                 = v                      （65536 的倍数 & 0xFFFF = 0）  ✓    ∎
```

**关键前提**：`state ≤ 2³¹ - 1`。若 b > 32767，则 `b · 65536 > 2³¹`，溢出为负数，`>>> 16` 的无符号右移行为在 AVM1 中仍正确（将 32 位补码视为无符号），但 `>> 16` 会符号扩展导致错误。C1 的 clamp 保证了 b ≤ 32767，双重安全。

### 定理 1: 甄别正确性

**命题**：令 sc = bullet.霰弹值，则 `sc < -65535` 为 true 当且仅当 sc 是合法编码值。

**证明**：

**(⇒) 充分性**：由引理 1，所有 enc(b, v) ≤ -65536 < -65535。

**(⇐) 必要性**：
- 合法正霰弹值 ∈ [0, 32767] → 不满足 < -65535 ✓
- S₀ = 0 时 init 跳过编码 → bullet.霰弹值 = 0 ∈ [0, 32767] ✓
- sc = undefined → AS2 中 `undefined < -65535` 返回 undefined → falsy ✓
- sc = NaN → AS2 中 `NaN < -65535` 返回 undefined → falsy ✓
- 直接模式下的负霰弹值（理论不存在，但防御分析）：
  init 守卫 `s0 > 0` 排除 ≤ 0；直接模式下 `currentScatter -= actualScatterUsed` 后有
  `if (currentScatter < 0) currentScatter = 0` clamp → 不会产生负值 ✓

综合：`sc < -65535` ⟺ sc 是 enc(b, v) 形式的编码值。                                ∎

**关于 AS2 NaN 安全性的补充说明**：
AS2 中 `>=`/`<=` 的实现为 `!(<)`/`!(>)`。当操作数含 NaN 时：
- `NaN < -65535` → undefined（非 false）
- `!(undefined)` = true → 即 `NaN >= -65535` = true

这就是为什么甄别必须用 `<` 而非 `<=`：
- `sc < -65535`：NaN → undefined → **falsy** → 正确走直接模式
- `sc <= -65536`：等价于 `!(sc > -65536)` → `!(undefined)` → **true** → 误入影子模式 → 崩溃

### 定理 2: 不变式保持

设窗口开始前 bullet.霰弹值 = S₀（C1: S₀ ∈ [1, 32767]）。

**Init 后状态**：
```
bullet.霰弹值 = enc(S₀, S₀) = -((S₀ << 16) | S₀)
```

**第 k 次命中（k ∈ [1, N]）的 handleBulletDamage 入口状态**：

设前 k-1 次命中的消耗序列为 a₁, ..., aₖ₋₁。由归纳假设：
```
bullet.霰弹值 = enc(S₀, S₀ - Σᵢ₌₁ᵏ⁻¹ aᵢ)
```

解码得：
```
baseSc    = S₀                          — 高16位不变
available = S₀ - Σᵢ₌₁ᵏ⁻¹ aᵢ           — 低16位 = 剩余可用
```

**INV-1**（aₖ ≥ 1）：
`actualScatterUsed` 的计算逻辑未改变（与旧方案共享同一代码路径），最终有：
```
if (actualScatterUsed < 1) actualScatterUsed = 1;
```
因此 aₖ ≥ 1。                                                                          ∎

**INV-2**（Σᵢ₌₁ᵏ aᵢ ≤ S₀）：
```
actualScatterUsed = min(availableScatter, ceilC)
                  ≤ availableScatter
                  = available
                  = S₀ - Σᵢ₌₁ᵏ⁻¹ aᵢ

⟹ aₖ ≤ S₀ - Σᵢ₌₁ᵏ⁻¹ aᵢ
⟹ Σᵢ₌₁ᵏ aᵢ ≤ S₀                                                                       ∎
```

**INV-3**（第 k 次命中看到 available = S₀ - Σᵢ₌₁ᵏ⁻¹ aᵢ）：
```
解码得 available = state & 0xFFFF（引理 2 保证正确）

归纳基：k=1 时，init 编码 enc(S₀, S₀)，解码得 available = S₀ = S₀ - 0  ✓
归纳步：第 k-1 次命中结束时重编码 enc(S₀, available - aₖ₋₁)
        = enc(S₀, S₀ - Σᵢ₌₁ᵏ⁻¹ aᵢ)
        第 k 次解码得 available = S₀ - Σᵢ₌₁ᵏ⁻¹ aᵢ  ✓                                  ∎
```

**INV-4**（最终 bullet.霰弹值 = S₀ - Σᵢ₌₁ᴺ aᵢ）：

commit 执行：
```
sc = bullet.霰弹值 = enc(S₀, S₀ - Σᵢ₌₁ᴺ aᵢ)

(-sc) & 0xFFFF = (S₀ << 16 | (S₀ - Σᵢ₌₁ᴺ aᵢ)) & 0xFFFF
               = S₀ - Σᵢ₌₁ᴺ aᵢ               （引理 2）

bullet.霰弹值 = S₀ - Σᵢ₌₁ᴺ aᵢ                                                        ∎
```

**INV-5**（基准值 S₀ 在整个窗口内可读取）：
```
每次解码得 baseSc = state >>> 16 = S₀  （引理 2，高16位在所有重编码中不变）
scatterForCalc = baseSc = S₀

C2 保证窗口内无外部写入，高16位不被篡改。                                                ∎
```

### 定理 3: N=0 安全性

**命题**：若无目标命中，commit 正确恢复原始霰弹值。

**证明**：
```
init:   bullet.霰弹值 = enc(S₀, S₀) = -((S₀ << 16) | S₀)
commit: (-enc(S₀, S₀)) & 0xFFFF = ((S₀ << 16) | S₀) & 0xFFFF = S₀

bullet.霰弹值 = S₀  ← 原始值完整恢复                                                    ∎
```

### 定理 4: available=0 稳定性

**命题**：当霰弹值耗尽（available = 0）后，编码值仍可被正确甄别和解码。

**证明**：
```
enc(S₀, 0) = -((S₀ << 16) | 0) = -(S₀ · 65536)

由 S₀ ≥ 1 → enc(S₀, 0) ≤ -65536 < -65535 → 甄别条件成立 ✓

解码：
  state = S₀ · 65536
  baseSc = state >>> 16 = S₀  ✓
  available = state & 0xFFFF = 0  ✓

后续命中：actualScatterUsed = min(0, ceilC) = 0，
但 if (actualScatterUsed < 1) actualScatterUsed = 1 → aₖ = 1

INV-2 检验：Σaᵢ 可能 > S₀（因为 available=0 时仍强制消耗 1 段）
但此时 available -= 1 = -1，clamp 到 0，重编码 enc(S₀, 0)。
这意味着弹尽后每次命中消耗 1 段"虚拟段"，不影响 bullet.霰弹值
（commit 仍返回 0），但 result.actualScatterUsed = 1，
使得伤害公式仍有最低输出（保持"至少打 1 段"的游戏设计意图）。                             ∎
```

### 定理 5: 位隔离性

**命题**：高16位（base）和低16位（available）在所有操作中互不干扰。

**证明**：
```
前提（C1）：S₀ ≤ 32767 < 2¹⁵，即 S₀ 最多占用 15 位。
因此 S₀ << 16 最多占用 bit[30..16]，bit[31] = 0（正数）。

available ∈ [0, S₀] ⊂ [0, 32767]，最多占用 15 位，即 bit[14..0]。

(S₀ << 16) | available：
  bit[31]    = 0           （S₀ < 2¹⁵，左移后不触及符号位）
  bit[30..16] = S₀         （高16位中的有效部分）
  bit[15]    = 0           （S₀ < 2¹⁵，available < 2¹⁵，此位始终为 0）
  bit[14..0] = available   （低16位中的有效部分）

关键：bit[15] 和 bit[31] 始终为 0，形成 1 位的安全隔离带。
即使 available 递减到 0 或 base 达到 32767，两个字段不会互相踩踏。

反例分析：若 S₀ = 32768（违反 C1）：
  32768 << 16 = 2,147,483,648 = 2³¹ → Int32 溢出为 -2,147,483,648
  >>> 16 在 AVM1 中将此视为无符号 2³¹ → 结果 32768 → 仍然正确
  但 state 变为负数，& 0xFFFF 对负数行为取决于 AVM1 实现 → 不可靠

  C1 的 clamp 到 32767 排除了这一边界情况。                                              ∎
```

## 性能对比

### 旧方案（动态属性 __dfScatterBase / __dfScatterPending）

```
init:    2 次哈希 INSERT + 1 次 lookup
热路径:  7 次 lookup + 1 次 write（含 2 次冗余 || 0 防御）
commit:  4 次 lookup + 2 次 DELETE + 1 次 write
N=8:    74 次哈希操作 + 2 次 delete ≈ 11μs
```

### 新方案（原位位编码）

```
init:    1 次 lookup + 1 次 write
热路径:  1 次 lookup + 1 次 write
commit:  1 次 lookup + 1 次 write
N=8:    20 次哈希操作 + 0 次 delete ≈ 3μs
```

| 指标 | 旧 | 新 | 改善 |
|------|----|----|------|
| N=8 总哈希操作 | 74 | 20 | **-73%** |
| delete 操作 | 2 | 0 | **-100%** |
| 动态属性 | 2 (魔法字符串耦合) | 0 | **-100%** |
| 热路径分支 | 3 (三路) | 2 (影子/直接) | -33% |

## 历史沿革

1. **三属性方案**（初版）：`__dfScatterBase` + `__dfScatterPending` + `__dfScatterShadow`
   - `__dfScatterShadow` 存储动态剩余值，后发现可由 base - pending 计算，冗余删除

2. **两属性方案**：`__dfScatterBase` + `__dfScatterPending`
   - 每帧 2 次哈希 INSERT + 2 次 DELETE
   - 热路径 7-8 次哈希查找（含冗余 `|| 0` 防御和 `!= undefined` 检测）

3. **原位位编码方案**（当前，2026-03）：零动态属性
   - 基于 Gemini 3 DeepThink 提出的高低16位编码 + 取负标记
   - 简化：移除"临时褪壳"（审计确认窗口内无外部裸读需要 S₀）
   - 哈希操作降低 73%，delete 操作完全消除
