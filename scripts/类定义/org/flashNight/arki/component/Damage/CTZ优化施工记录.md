# CTZ 优化施工记录 — DamageManagerFactory.createEvaluator

## 变更摘要

将 `createEvaluator` 从三分支特化实现（&&二分/Math.log/线性扫描）统一为 **Modulo 37 合并方案**。

- **修改文件**：DamageManagerFactory.as `createEvaluator` 方法
- **修改日期**：2026-03-22
- **修改类型**：性能优化 + bug 修复（bit31 NaN/签名错误）

---

## 旧实现的问题

### 三分支结构

| 分支 | 条件 | 算法 | 指令数 | ns/op | 已知缺陷 |
|------|------|------|--------|-------|---------|
| 1 | `hlen <= 8` | `&&` 短路二分搜索 | 40 | 1598 | `&&` 编译为 PushDuplicate+Not+If+Pop（4条/次×2） |
| 2 | `hlen < 32` | `Math.log` 对数 | 14 | 1315 | `Math.log(1<<31)=NaN`，bit31 返回 0 |
| 3 | `hlen == 32` | 线性扫描 `>>>1` | O(32) | 1359 | 每位都要判断，即使 popcount 很小 |

### bit31 bug

`1 << 31` = `-2147483648`（AS2 有符号 Int32），导致：
- 分支1：`(-2147483648) >= 16` → `false`（负数比较），索引计算错误
- 分支2：`Math.log(-2147483648)` → `NaN` → `(NaN + 0.5) | 0` → `0`
- 分支3：使用 `>>> 1` 无符号右移，正确但 O(32) 慢

---

## 新实现：Modulo 37 合并方案

### 数学基础

37 是素数，2 是 mod 37 的原根（阶为 36 > 32）。因此对任意 `i, j ∈ {0,...,31}` 且 `i ≠ j`：

```
(2^i) % 37 ≠ (2^j) % 37
```

完美哈希，零冲突。

**bit31 安全性**：`(-2147483648) % 37 = -22`。Object 的键自动 `toString()`，`"-22"` 作为字符串键无任何符号问题。

### 实现结构

```actionscript
// 工厂初始化时（一次性）
var hlut:Object = {};
for (i = 0; i < hlen; i++) {
    hlut[(1 << i) % 37] = h[i];  // 预合并：hash → handler 引用
}

// 热路径闭包（每次调用）
return function(bitmask:Number):DamageManager {
    var handles:Array = [];
    var len:Number = 0;
    do {
        handles[len++] = hlut[(bitmask & (-bitmask)) % 37];
    } while ((bitmask &= (bitmask - 1)) != 0);
    return new DamageManager(handles);
};
```

### 关键优化：预合并查找表

传统 CTZ 方案需要两级查找：`CTZ(lsb) → index → h[index]`。
合并方案直接 `hlut[hash] → handler`，单次 `GetMember` 完成。

---

## 实验数据

### 实验方法

- 4 轮迭代实验，TestLoader + JPEXS P-code 反编译
- 7 种 CTZ 方案对比（&&二分/De Bruijn/直接LUT/Math.log/if-else/Modulo37/嵌入立即数）
- 3 个位宽（8/16/32-bit），含 bit31 极端值测试
- 9 轮交替测量，IQR 过滤，取中位数
- Gemini 2.5 Pro Deep Think × 2 + GPT-5.4 Thinking 交叉验证数学证明

### 性能对比（模拟真实闭包热路径，含函数调用+数组构建开销）

| 位宽 | 旧方案 (ns/op) | Mod37 合并 (ns/op) | 加速比 |
|------|---------------|-------------------|--------|
| 8-bit | 1598（&&二分） | **1064** | **1.50×** |
| 16-bit | 1315（Math.log） | **820** | **1.60×** |
| 32-bit | 1359（线性扫描） | **841** | **1.62×** |

### P-code 指令数对比（闭包内 do-while 循环体）

| 方案 | 循环体指令数 | 备注 |
|------|------------|------|
| &&二分（旧8bit） | ~40 | PushDuplicate+Not+If+Pop 模式 ×2 |
| Math.log（旧<32bit） | ~14 | CallMethod ~500ns 单条极贵 |
| 线性扫描（旧32bit） | ~15/位 | O(32) 总指令 ~480 |
| **Mod37 合并（新）** | **8** | GetVariable+LSB隔离+Modulo+GetMember |

### 淘汰方案记录

| 方案 | 淘汰原因 |
|------|---------|
| 闭包寄存器持表（5指令） | AS2/CS6 编译器不将闭包变量放入寄存器，仍用 GetVariable scope chain 查找 |
| 全域LUT（3指令） | 同上，闭包开销 2.5× 慢于全局变量 |
| Magic Shift Register | 浮点乘法器 2.813 在 AVM1 中精度不足，i=6 时失败 |
| De Bruijn 32-bit split | 精度屏障是伪命题（2^i × c 的有效位 = c 的有效位 < 53），UNSAFE 版本完全正确 |
| Embedded LUT（立即数内嵌） | 16 指令，不如 Mod37 的 9 指令 |

### 数学证明摘要

1. **单乘法直接哈希不存在**：滑动窗口重叠性质导致 `h(i)=i` 在 `1→2` 处矛盾
2. **32-bit De Bruijn c < 2^22 不存在**：L-bit 常数最多 L+5 个不同 5-bit 窗口，L≤22 → 27 < 32
3. **53-bit 精度屏障是伪命题**：`c × 2^i` 的有效位数 = c 的有效位数（27 < 53），乘以 2 的幂只改变指数字段

---

## 影响范围

- `createEvaluator` 是 `private` 方法，仅在构造函数中调用一次
- 返回的闭包通过 `_evaluator` 字段被 `_resolve` 调用（热路径）
- 所有公开 API（`getDamageManager` / `getDamageManager1` / `getDamageManager2`）行为不变
- 无需修改任何调用方
