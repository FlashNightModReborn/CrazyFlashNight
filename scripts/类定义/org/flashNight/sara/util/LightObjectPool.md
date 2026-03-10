new org.flashNight.sara.util.LightObjectPoolTest();

Starting Basic Functionality Tests...
[PASS] Initial pool size is zero
[PASS] getObject returns a new object
[PASS] Pool size remains zero after getting new object
[PASS] releaseObject adds object back to the pool
[PASS] getObject returns the previously released object
[PASS] Pool size decrements after retrieving an object
[PASS] Releasing undefined does not throw error
Basic Functionality Tests Completed.
Starting Clear Pool Tests...
[PASS] Pool size is 5 after releasing 5 distinct objects
[PASS] clearPool sets pool size to 0
Clear Pool Tests Completed.
Starting Performance Tests...
Performed 10000 getObject and releaseObject operations in 26 ms
[PASS] Performance: 10000 getObject/releaseObject operations < 100 ms
Performed 10000 continuous getObject and releaseObject operations in 25 ms
[PASS] Performance: 10000 continuous getObject/releaseObject operations < 100 ms
Performance Tests Completed.
Starting Practical Performance Tests...
Performed 10000 mixed operations in 30 ms
[PASS] Performance: 10000 mixed operations < 150 ms
Practical Performance Tests Completed.
----- Test Results -----
------------------------
Total Tests: 12, Passed: 12, Failed: 0

## A/B/C Benchmark (2026-03-10, 100K iterations x 7 rounds)

对比三种实现：
- A = Original (当前 head/tail 双属性 + getObject 局部缓存)
- B = Packed (head/tail 位压缩到单个 _ht Number, 高16位=head 低16位=tail)
- C = Cached (在 A 基础上给 releaseObject 补全 mask/head 局部缓存)

### Scenario 1: get+release alternating
| 版本 | 中位数 | vs Original |
|------|--------|-------------|
| A(Original) | 243ms | baseline |
| B(Packed) | 277ms | +14.0% 慢 |
| C(Cached) | 244ms | +0.4% 持平 |

### Scenario 2: bulk release then bulk get
| 版本 | 中位数 | vs Original |
|------|--------|-------------|
| A(Original) | 263ms | baseline |
| B(Packed) | 296ms | +12.5% 慢 |
| C(Cached) | 263ms | 持平 |

### Scenario 3: getPoolSize high-freq
| 版本 | 中位数 | vs Original |
|------|--------|-------------|
| A(Original) | 76ms | baseline |
| B(Packed) | 79ms | +3.9% 慢 |
| C(Cached) | 75ms | -1.3% 略快 |

### 结论

**原版 (A) 已经是最优实现，不需要修改。**

---

## 否决的优化路线

### 路线 B：State Packing（游标压缩）

**假说**：将 head 和 tail 打包到单个 Number 的高低 16 位（`_ht = (head << 16) | tail`），
热路径每次调用省 1 次 GetMember (~144ns)，代价是 3-4 次位运算 (~60-90ns)，预期净赚 ~50-80ns/call。

**实现要点**：
- 取 head: `s >>> 16`; 取 tail: `s & 0xFFFF`
- releaseObject 中 `(s & 0xFFFF0000) | nextT` 保留 head 直接替换 tail
- getPoolSize 同余魔法: `(s - (s >>> 16)) & mask`（因 65536 mod 2^k = 0，故 65535 mod 2^k = -1）
- 容量上限 32768（16 位安全区间），项目最大使用 512，不构成限制

**否定原因（实测 +12~14% 慢）**：
- AVM1 中所有 Number 底层是 64 位 IEEE-754 双精度浮点。执行 `&`/`>>>`/`<<`/`|` 时，
  VM 在 C++ 底层做 float64→int32 强转，计算完再 int32→float64 转回
- 成本阶梯表中位运算 0-30ns 是**单次简单操作**的度量，
  但 packed 方案每次调用需 `>>>16` + `& 0xFFFF` + `<< 16` + `|` **组合使用**，
  4 次强转的累积开销约 120-150ns，追平甚至超过了省下的 1 次 GetMember
- 这是一个"理论上更底层，实测上更慢"的典型案例

**在其他平台上的适用性**：
此方案在强类型整数的平台（AS3 的 uint、C#/TypeScript 的 int）上会真正起飞，
因为位运算直接映射到 CPU 寄存器单周期指令，无类型强转。**仅在 AVM1/AS2 的 Number-only 类型系统下不划算。**

### 路线 C：releaseObject 完整局部缓存

**假说**：原版 releaseObject 中 `this.mask` 和 `this.head` 没有缓存到局部变量，
额外做局部缓存可省 2 次 GetMember。

**否定原因（实测持平，无显著差异）**：
- `this.mask` 和 `this.head` 在 releaseObject 中各**仅读 1 次**
- 缓存到局部变量的收益（省 1 次 GetMember ~144ns）被额外的 `var` 声明 + 赋值开销抵消
- H01 规则"热循环中外部变量首次使用前必须局部化"的前提是**使用 >= 2 次**，
  仅使用 1 次时局部化反而不划算

### 设计启示

- **AVM1 优化的黄金法则**：局部缓存仅对**同一属性使用 >= 2 次**的场景有效（H01）
- **位运算打包在 AVM1 中是反优化**：float64↔int32 强转的隐性开销远超预期
- **原版 LightObjectPool 的设计恰好踩在了 AVM1 成本模型的最优点上**：
  getObject 中 head/tail/pool 各用 >= 2 次 → 正确缓存；
  releaseObject 中 mask/head 各用 1 次 → 正确地没有缓存
