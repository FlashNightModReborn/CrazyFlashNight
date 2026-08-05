# Prime Magic Orbit Engine

TypeScript 运行时层，已接入 8 张**离线独立验证过的完整 19 阶质数幻方 seed**。本目录没有把原始半幻方当成完整 seed，也不会在浏览器中做质数判定或约束搜索。

## 已实现

- `Uint32Array` seed、副本与双缓冲；`Uint8Array`/`Uint16Array` 置换。
- xoshiro128** 确定性 PRNG；BigInt 仅用于构造期 seed 扩展，热路径为 32 位整数运算。
- 对反转中心化子的均匀直接采样，不使用随机游走。
- 独立行轴反转与可选 transpose；包含正方形全部 8 个二面体对称。
- `nextInto(output)` 与 `nextView()` 成功热路径不创建数组、对象、闭包或字符串。
- 变换合法性、复合、逆、单位元和 PRNG 状态保存/恢复。
- 基于 `SharedArrayBuffer` 的 Worker 双缓冲布局及无逐帧消息的 Worker 示例。
- 单 draw-call、361 instances 的 WebGL2 示例；数字在 fragment shader 中由整数拆位（可配置 1–10 位），不生成 361 个字符串。
- Node/V8 基准、Chromium 可执行基准、百万次性质压力测试。
- PM19 紧凑二进制加载器：启动期核对 binary SHA-256，再解码 `<4sHHQ + n²·uint32>`。

## 数学定义与证明

令阶数为奇数 `n`，`R(i)=n-1-i`，完整幻方为 `A`，公共和为 `S`。令

```text
C(R) = { π ∈ S_n | πR = Rπ }.
```

采样参数为 `π∈C(R)`、独立轴反转位 `ε∈{0,1}` 与转置位 `τ∈{0,1}`。定义

```text
ρ = R^ε π
κ = π

τ = 0: B[i,j] = A[ρ(i), κ(j)]
τ = 1: B[i,j] = A[ρ(j), κ(i)]
```

### 行列和

`ρ`、`κ` 都是置换。`τ=0` 时每一输出行是某输入行的列重排，每一输出列是某输入列的行重排；`τ=1` 只交换这两个角色。因此所有行列和仍为 `S`。

### 两条对角线

因为 `πR=Rπ`：

- `ε=0, τ=0`：主对角线为 `(π(i),π(i))`；副对角线为 `(π(i),Rπ(i))`。
- `ε=0, τ=1`：主对角线不变；副对角线为 `(Rπ(i),π(i))`，仍只是副对角线重排。
- `ε=1, τ=0`：主对角线成为副对角线重排；副对角线成为主对角线重排。
- `ε=1, τ=1`：同样交换两条对角线的角色。

故两条对角线的和均严格保持为 `S`。元素只被搬运，所以元素集合、互异性和质数性也保持。

### 数量、稳定子与重复

`R` 在 `n=19` 上有一个固定中心和 9 个二元轨道。与 `R` 交换的置换必须固定中心，可以任意排列 9 个二元轨道，并独立翻转每一对，因此

```text
|C(R)| = 9! · 2^9 = 185,794,560.
```

这正是“中心交换置换”的数量，不含额外坐标对称。再加入一个独立轴反转位与 transpose 位，本实现的坐标变换群大小为

```text
4 · |C(R)| = 743,178,240.
```

一般轨道大小为 `|G| / |Stab(A)|`。对于本项目要求的**全局互异元素**，任何非恒等位置置换都会把某个位置换成不同值，所以稳定子为平凡群，单 seed 的轨道恰有 `743,178,240` 个棋盘。当前 8 个 seed 的中心值两两不同，而本群固定奇数阶中心，故 8 个轨道必不相交，总状态数恰为 `5,945,425,920`。

### 均匀性与周期

Fisher–Yates 均匀排列 9 个反转对；每一对用独立随机位决定朝向；`ε`、`τ` 再用两个独立随机位。因此每次 `nextInto` 都直接均匀抽取群元素，不存在随机游走混合时间或短循环偏置。xoshiro128** 状态周期为 `2^128-1`；棋盘重复主要服从有限轨道的生日碰撞，而不是游走回环。

在 100,000 次固定种子测试中观测到 8 次重复，生日近似期望为 6.73 次。该统计是实验检查，不是 PRNG 随机性的形式证明。

## API

```ts
import {
  PrimeMagicOrbitEngine,
  PrimeMagicSeedBankOrbitEngine,
} from "./dist/src/index.js";

const engine = new PrimeMagicOrbitEngine(verifiedSeed, 0x1234n);
const output = new Uint32Array(verifiedSeed.size ** 2);
engine.nextInto(output);       // caller-owned buffer

const transient = engine.nextView(); // internal A/B buffer, every other call覆写

// 推荐正式模式：8 个中心不同的 seed 均匀抽样。
const bankEngine = new PrimeMagicSeedBankOrbitEngine(verifiedSeeds, 0x1234n);
bankEngine.nextInto(output);
```

构造器只检查运行时结构（尺寸、TypedArray、safe integer、checksum 非空），**不会重新验证质数、互异或幻和值**。这避免生成器与运行时验证逻辑同源，也符合“离线验真，在线只走已证明变换”的边界。

Worker 初始化示意（消息只发生一次；之后 Worker 自己定时写共享双缓冲）：

```ts
import {
  acquireSharedFront,
  createSharedOrbitViews,
  releaseSharedFront,
} from "./dist/src/index.js";

const shared = createSharedOrbitViews(verifiedSeed.values.length);
const worker = new Worker("/dist/web/orbit.worker.js", { type: "module" });
worker.postMessage({
  kind: "initialize",
  seed: verifiedSeed,
  randomSeed: "1234",
  storage: shared.storage,
  boardsPerSecond: 10,
});

// RAF 内：bufferSubData 在返回前完成源数据读取，然后释放 reader pin。
const front = acquireSharedFront(shared);
try {
  renderer.updateValues(front);
} finally {
  releaseSharedFront(shared);
}
```

## 构建、测试、基准

```bash
npm install
npm test
npm run test:stress     # 默认 1,000,000 次
npm run bench
npm run demo            # http://127.0.0.1:4173/
```

浏览器基准位于 `http://127.0.0.1:4173/web/benchmark.html`。WebGL demo 默认加载真实 seed00，并可切换全部 8 个 seed；每次加载先核对二进制 SHA-256。普通整数幻方只保留给 `n=5` 小状态空间均匀性单测，不进入 demo、压力测试或 benchmark。

## 集成边界

- `magicSum` 使用 JS safe integer；值使用 uint32。超过该范围的推广应由离线 BigInt 验证，并选择 `BigUint64Array` 或拆分高低位的新运行时实现，不能静默截断。
- binary SHA-256 在资源加载时验证一次；canonical checksum 随 seed 进入引擎，热路径不重复计算 SHA-256。
- `SharedArrayBuffer` 示例要求 COOP/COEP；自带本地服务器已发送对应响应头。
- 单个 19 阶 seed 已有约 7.43 亿个精确状态，但中心值始终固定、反转对结构仍可被长期观察。当前 8 个不同中心 seed 正好提供 8 个可证明不相交的轨道，建议全部打包使用。
