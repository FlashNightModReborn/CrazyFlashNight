# 性能与渲染决策

## 本机实测（非浏览器）

运行时间：2026-08-05 UTC。环境：AMD EPYC 9V74、Linux x64、Node 24.14.0、V8 13.6.233.17；样本 250,000，预热 25,000。输入为真实完整质数幻方 seed00，canonical SHA-256 为 `a5e002e9047e02dba2608428ef7416493a0b1ce9148e6e77f3d57be04084413d`。

| 操作 | Median | P95 | P99 | Max | boards/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| 单 seed 随机合法 orbit + `Uint32Array` | 1.091 µs | 1.172 µs | 1.572 µs | 226.036 µs | 849,247 |
| 8-seed bank 均匀选择 + 随机 orbit | 1.172 µs | 1.252 µs | 1.612 µs | 354.156 µs | 775,469 |
| 固定置换 + `Uint32Array` | 0.530 µs | 0.531 µs | 0.551 µs | 112.958 µs | 1,752,240 |
| 固定置换 + packed `Array<number>` | 0.341 µs | 0.351 µs | 0.370 µs | 1,780.684 µs | 2,558,664 |

最大值主要是共享容器调度/停顿，不代表稳态算法成本。计时包含每次 `performance.now()` 开销。各项 `--expose-gc` 前后保留堆差都在数 KiB 内且不随迭代线性增长；它不能替代 Chrome allocation instrumentation。

普通 packed array 在该 V8 上复制更快，不应据此改接口：`Uint32Array` 提供确定宽度、无装箱、可传输/共享以及直接 `bufferSubData`/`writeBuffer`，省掉渲染边界转换才是主要收益。

真实 seed00 的百万次压力测试两次运行约 1.39–1.44 s；每次均检查变换合法性、两条对角线和一个轮换行列，每 4096 次做完整行列/对角线/互异检查，未发现错误。另有独立 seed-bank 测试重新核对 8 个二进制 hash、canonical hash、质数性、互异、全部行列和与两条对角线。

## 渲染路线

| 路线 | 适用场景 | 成本与风险 | 结论 |
| --- | --- | --- | --- |
| DOM 361 节点 | 低频调试/无 Canvas 环境 | 文本字符串、style/layout/paint、GC；高频 glow 更差 | 正式渲染拒绝 |
| Canvas2D | 兼容 fallback、静态或 ≤10 Hz 棋盘 | 启动期 glyph atlas；棋盘更新时离屏重绘，RAF 只合成。避免逐格 `fillText`/filter | 可用 fallback |
| WebGL2 instancing | 现代 Chromium、单/少量矩阵 | 361 instances、每棋盘 1,444-byte 上传、1 draw；GLSL 整数拆位 | 默认推荐 |
| WebGPU | 已有 WebGPU renderer、批量矩阵/复杂 compute | 初始化与管线成本高；对单张 19×19 没有可见 CPU收益 | 不为本功能单独引入 |

WebGL2 demo 每格一个 instance，fragment shader 从 uint32 中拆出可配置的 1–10 位数字并采 glyph atlas；当前约一千万量级 seed 使用 8 位。扫描线、脉冲与 cell noise 仅依赖时间 uniform，因此真实棋盘可保持 5–30 Hz，视觉仍按 60–144 Hz RAF 更新。

脉冲与 cell noise 在 vertex 阶段按 361 个 instance 计算后以 `flat` varying 传入，避免逐像素重复 `sin/hash`；fragment 仅保留扫描线。renderer 默认将 device-pixel-ratio 上限压到 1.5，144 Hz 或集显档可构造时进一步设为 1.0。

建议放 shader 的效果：扫描线、辉光/色偏、局部噪声、亮度脉冲、轻微 UV 抖动、FAULT 阶段的遮罩/残差染色。CPU 只负责状态机、低频选择合法棋盘、更新少量 uniform 与 1,444-byte integer buffer。

## Worker 与 WASM

本机 8-seed bank 中位 1.172 µs 意味着 30 Hz 真实切换只消耗约 35.2 µs/s；把这一步移入 Worker 通常比计算本身更贵。Worker 只在主线程已有明显渲染/布局尖峰、需要与其他电子战模拟隔离时启用。示例采用 `SharedArrayBuffer` 双缓冲和原子 front/version/reader pin，不做逐帧 transferable 往返。

WASM 没有工程依据：361 次非连续读写与 PRNG 的 TypeScript 成本远低于预算，WASM 边界反而可能主导。只有目标浏览器实测 `nextInto` P99 接近棋盘切换预算，或一次要批量生成数千棋盘时再复议。

## 必须在目标机补测

`web/benchmark.html` 会一键输出 UA、样本数、Median/P95/P99/Max，并覆盖 main/Worker、TypedArray/普通数组、361 DOM、Canvas2D glyph atlas、WebGL2 shader 开/关；WebGL 数据包含 `gl.finish`，是刻意悲观的端到端值。它还会在浏览器支持时记录 `performance.memory`、`measureUserAgentSpecificMemory()` 与 GC performance entries。最终上线前仍需在目标 Chromium 记录：

1. 主线程与 Shared Worker 的 5/10/30 Hz 对比；
2. 60/144 Hz RAF 下 CPU/GPU 占用；
3. Chrome Performance 的 Minor/Major GC 与 allocation bytes；
4. Canvas2D fallback 与 WebGL2 在开/关 shader 视觉效果时的 frame time；
5. 前后台切换、降频笔记本和集显上的 P99/Max。

本交付环境的云端 Chromium 安全策略拒绝访问容器 `localhost`，也禁止用 `data:` 注入绕过；因此没有产生浏览器/GPU 数字。没有目标 Chromium 采样前，不应伪造浏览器版本、GPU 或 GC 为零的结论。
