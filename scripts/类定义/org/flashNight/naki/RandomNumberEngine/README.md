# RandomNumberEngine 随机数引擎模块

## 引擎清单与定位

| 引擎 | 父类 | 定位 | 生产调用情况 |
|------|------|------|--------------|
| `BaseRandomNumberEngine` | — | **抽象基类**，定义助手方法（`randomInteger` / `randomFloat` / `randomOffset` / `successRate` / `shuffleArray` / 高斯采样等），全部通过虚派发的 `this.nextFloat()` 取熵 | 不直接实例化 |
| `LinearCongruentialEngine` | Base | **项目通用引擎**，绑定全部中文名全局函数（`_root.随机整数` / `_root.成功率` / `_root.随机偏移` 等），是绝大多数随机数调用的实际承载者 | 33 个文件、全局热路径 |
| `MersenneTwister` | Base | 限定用途引擎，绑定 `_root.advance_random` 等英文别名，主要服务于需要更长周期的场景（如 `Symbol`） | 2 处 |
| `PinkNoiseEngine` | Base | **特化引擎**，5 层叠加生成 1/f 频谱粉红噪音，专用于伤害波动 | 1 处（`DamageCalculator.伤害波动`） |
| `SeededLinearCongruentialEngine` | Base | 技术储备：可外部指定 `a/c/m` 参数的可配置 LCG | **零生产调用** |
| `PCGEngine` | Base | 技术储备：PCG 系列基础实现 | **零生产调用** |
| `PCGXSHRREngine` | Base | 技术储备：PCG XSH-RR 变体 | **零生产调用** |

## 继承规则（强约束）

> **所有随机数引擎一律直接继承 `BaseRandomNumberEngine`，禁止继承任何具体引擎类。**

### 规则的根因

某些引擎（目前 LCG，未来可能 MT/PinkNoise）出于热路径性能考虑，会在助手方法（`randomFluctuation` / `randomOffset` / `randomInteger` 等）内部把 `nextFloat()` 调用**硬编码展开**成本类底层公式，绕过原型链虚派发——这是 AS2 中消除函数调用开销的标准手段。

但这种"内联到叶类"的优化只对叶类自身正确。一旦被继承：

- 子类即使覆盖了 `nextFloat()`，父类内联版的助手方法**仍执行父类公式**直接读写 `this.seed`，完全绕过子类的 `nextFloat()`
- 子类的随机分布特性（粉噪 1/f 频谱、MT 长周期等）被**静默破坏**，且没有任何运行时报错
- 唯一能感知的是下游分布的统计偏差，定位极其困难

### 推论与替代方案

- 想复用 LCG 的位混合算术？**复制常量**（`1192433993` / `1013904223` / `4294967296` / `2.3283064365386963e-10`），不要 extends
- 想复用 LCG 的实例状态？**HAS-A 组合**（持有一个 LCG 实例并显式调用），不要 extends
- 想新增引擎？直接 `extends BaseRandomNumberEngine`，让 Base 的助手通过虚派发自动适配你的 `nextFloat()`

## 历史踩坑

- **2026-04**：commit `419449763` 把 LCG 的 7 个助手方法内联化以省函数调用开销
- 当时 PinkNoise 仍 `extends LinearCongruentialEngine`，**靠"目前没人在 pink 实例上调用这些助手"维持表面正确**
- 紧随其后的重构把 PinkNoise 改为 `extends BaseRandomNumberEngine`，把"靠静态扫描调用方"的隐性约定升级为结构性保证
- 详见 [`PinkNoiseEngine.as`](PinkNoiseEngine.as) 顶部"继承关系说明"段落、[`LinearCongruentialEngine.as`](LinearCongruentialEngine.as) 顶部"封闭叶类"警告

## 性能与正确性边界

| 调用路径 | 函数调用开销 | 分布正确性 |
|---|---|---|
| `LCG.instance.randomFluctuation(15)` | 单次内联 LCG（最优） | ✓ |
| `Pink.instance.randomFluctuation(15)` | 单次内联 5 层粉噪（最优） | ✓ |
| `Pink.instance.randomOffset(5)`（假想调用） | Base 助手 + 虚派发到 Pink.nextFloat | 慢但正确（5 层粉噪） |
| `（错误示例）某子类 extends LCG 并覆盖 nextFloat，调用 randomOffset` | LCG 内联版（不走虚派发） | ✗ **静默退化为 LCG 均匀分布** |

## 子类如何选择父类（决策表）

```
新引擎需要 nextFloat 之外的特殊助手？
├─ 否 → extends BaseRandomNumberEngine，重写 next() / nextFloat()，收工
└─ 是 → 仍然 extends BaseRandomNumberEngine，自己再实现内联版助手
        （可参考 LCG / PinkNoise.randomFluctuation 的内联模式）
```

任何情况下答案都是 **`extends BaseRandomNumberEngine`**。

## 相关文件

- [`BaseRandomNumberEngine.as`](BaseRandomNumberEngine.as) — 抽象基类，所有助手方法的"可被覆盖"参考实现
- [`LinearCongruentialEngine.as`](LinearCongruentialEngine.as) — 通用引擎，封闭叶类
- [`PinkNoiseEngine.as`](PinkNoiseEngine.as) — 特化引擎，1/f 粉红噪音
- [`PinkNoiseEngine.md`](PinkNoiseEngine.md) — 粉噪 PSD 验证脚本（FFT 测斜率 ≈ -1）
- [`MultinomialSampleBenchmark.md`](MultinomialSampleBenchmark.md) — 多项分布采样性能基准
- 全局绑定入口：[`scripts/引擎/引擎_fs_随机数引擎.as`](../../../../../../引擎/引擎_fs_随机数引擎.as)
