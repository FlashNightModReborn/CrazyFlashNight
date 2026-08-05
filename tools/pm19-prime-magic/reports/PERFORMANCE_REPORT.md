# 性能报告

## 结论

数学热路径不是帧率风险：真实完整 seed 的单次随机合法群变换与 361 次 `Uint32Array` 搬运，中位 `1.091 µs`、P99 `1.572 µs`。8-seed bank 中位 `1.172 µs`、P99 `1.612 µs`。因此默认不引入 WASM，也不为这一步单独启用 Worker。

浏览器/GPU 数字尚未取得。本环境的云端 Chromium 安全策略拒绝访问容器 localhost，并明确禁止用页面注入绕过。交付的 `runtime/web/benchmark.html` 可在目标 Chromium 一键测量所有要求项；下表把未执行项标为 `NOT MEASURED`，不用 Node 结果冒充浏览器结果。

## Node/V8 可复现实测

- 时间：2026-08-05 UTC
- CPU：AMD EPYC 9V74 80-Core Processor（容器暴露 9 logical CPUs）
- OS：Linux x64
- Node：24.14.0；V8：13.6.233.17-node.41
- seed：真实 `prime_magic_19_seed_00`；canonical SHA-256 `a5e002e9047e02dba2608428ef7416493a0b1ce9148e6e77f3d57be04084413d`
- warmup：25,000；samples：250,000/操作
- 延迟包含每次 `performance.now()` 的计时开销

| 操作 | Median | P95 | P99 | Max | ops/s | GC 后 retained heap delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 单 seed：随机群元素 + U32 copy | 1.091 µs | 1.172 µs | 1.572 µs | 226.036 µs | 849,247 | -2,000 B |
| 8 seed：均匀选 seed + 随机群元素 + U32 copy | 1.172 µs | 1.252 µs | 1.612 µs | 354.156 µs | 775,469 | -1,712 B |
| 固定置换 + `Uint32Array` | 0.530 µs | 0.531 µs | 0.551 µs | 112.958 µs | 1,752,240 | +6,272 B |
| 固定置换 + packed `Array<number>` | 0.341 µs | 0.351 µs | 0.370 µs | 1,780.684 µs | 2,558,664 | +4,040 B |

heap delta 是显式 GC 前后的保留堆差，不是累计分配字节。正负几 KiB 均不能证明“零分配”；热路径零显式分配由源码结构和百万次压力测试共同支持，最终仍应在 Chrome Allocation instrumentation 复核。普通 Array 在这台 V8 的纯 copy 更快，但 U32 在 Worker、GPU upload、定宽语义和无装箱边界上更合适，因此不改运行时接口。

机器可读原始结果：`node_runtime_benchmark.json`。

## 频率预算

以下只把 8-seed bank 的中位 CPU 时间线性换算为单核占用，不含 renderer，属于工程估计而非浏览器实测：

| 真实棋盘频率 | 数学层 CPU 时间/秒 | 单核时间占比 |
| ---: | ---: | ---: |
| 5 Hz | 5.86 µs | 0.000586% |
| 10 Hz | 11.72 µs | 0.001172% |
| 30 Hz | 35.16 µs | 0.003516% |
| 60 Hz（压力上界） | 70.32 µs | 0.007032% |
| 144 Hz（非推荐） | 168.77 µs | 0.016877% |

产品建议仍是棋盘 5–30 Hz、RAF 60–144 Hz；高频视觉变化由 shader 时间 uniform 驱动。

## 百万次正确性/性能压力

`npm run test:all` 在真实 seed00 上执行 1,000,000 次独立均匀合法变换，用时 `1.381 s`。每次检查变换结构、两条对角线和轮换行列，每 4,096 次全量重算行列、对角线与互异性；15/15 tests 通过。8 个 PM19 binary 的 file SHA、canonical SHA、质数、互异与全部 40 条线也由独立测试重新核对。

Python 参考实现另对小阶群穷尽 identity/inverse/closure，对 19 阶执行 1,000,000 次完整性质测试并通过。二者不是同源实现。

## Chromium 基准覆盖与当前状态

| 要求项 | benchmark 实现 | 本环境结果 |
| --- | --- | --- |
| `nextInto` Median/P95/P99/Max | 100,000 samples + 10,000 warmup | NOT MEASURED |
| main vs Web Worker | 同 seed、同样本；记录 Worker batch wall time | NOT MEASURED |
| TypedArray vs普通 Array | 固定相同置换 | Node 已测；Chromium NOT MEASURED |
| 361 DOM text nodes | 含字符串生成与 forced layout | NOT MEASURED |
| Canvas2D | 10-glyph atlas，不逐格 `fillText` | NOT MEASURED |
| WebGL2 shader off/on | 361 instances、1,444-byte upload、draw + 悲观 `gl.finish` | NOT MEASURED |
| UA/CPU/DPR | 自动记录 | NOT MEASURED |
| heap/GC | `performance.memory`、UA-specific memory、GC entries（若浏览器支持） | NOT MEASURED |
| 60/144 Hz CPU/GPU | 需 Chrome Performance trace | NOT MEASURED |
| WebGPU | 未实现；当前无收益证据 | N/A |

运行方法：

```bash
cd runtime
npm ci
npm run demo
# 打开 http://127.0.0.1:4173/web/benchmark.html 并点击 Run benchmark
```

服务器发送 COOP/COEP，使 `SharedArrayBuffer` Worker 路径可测。结果面板输出完整 JSON，可直接归档。WebGL 测试中的 `gl.finish` 是刻意悲观的同步端到端测量，实际游戏不能每帧调用。

## 渲染成本判断

| 路线 | CPU/GC 风险 | GPU/实现风险 | 决策 |
| --- | --- | --- | --- |
| 361 DOM nodes | 361 字符串、style/layout/paint、GC | 无 | 只用于调试，正式拒绝 |
| Canvas2D glyph atlas | 棋盘切换时重绘；RAF 可只合成 | 兼容性最好 | fallback，建议 ≤10 Hz board |
| WebGL2 instancing | 每次 1,444 B U32 upload，1 draw | fragment fill-rate/辉光是主要变量 | 默认 |
| WebGPU | 对单个 19×19 无可见收益 | 多一套初始化与管线 | 仅在主 renderer 已使用时复用 |

shader 负责扫描线、辉光、色偏、cell noise、同步脉冲、UV 抖动与 FAULT mask。CPU 只切换合法 board、更新状态机和少量 uniform。device-pixel-ratio 默认封顶 1.5；144 Hz/集显档可降到 1.0。

## Worker 与 WASM 停止条件

- 默认主线程：30 Hz 数学层中位只约 `35.16 µs/s`，消息与调度通常更贵。
- Worker 保留：若主线程有布局尖峰或 renderer 整体迁移 OffscreenCanvas，则使用现成 `SharedArrayBuffer` 双缓冲与原子 reader pin，避免逐帧 transferable。
- 不用 WASM：TypeScript 余量约五个数量级，361 次间接读写也不利于用边界调用换收益。
- 只有目标 Chromium 的 `nextInto` P99 接近切换预算，或单次批量生成数千棋盘，才重新评估 WASM。
