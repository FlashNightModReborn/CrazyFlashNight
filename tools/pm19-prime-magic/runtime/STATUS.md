# 阶段记录：TypeScript Runtime

## 当前已证明的结论

- `πR=Rπ` 的同步行列置换保持两条对角线；加入单轴反转会交换两条对角线；transpose 仍保持它们。
- `n=19` 的反转中心化子是 `9!·2^9=185,794,560`；本引擎完整坐标群为其 4 倍。
- 对全局互异 seed，稳定子平凡，因此单 seed 轨道恰为 `743,178,240`。
- 实现的变换复合封闭、存在逆和单位元；性质测试已覆盖。

## 当前仅有实验支持的结论

- xoshiro/Fisher–Yates 实现的统计行为通过 `n=5` 卡方测试与 `n=19` 重复率检查；这不是 PRNG 的形式随机性证明。
- 当前 Node/V8 热路径约 1 µs；不能直接外推目标 Chromium/GPU。

## 当前最好结果

- 真实 seed00 上 1,000,000 次随机合法变换压力测试通过，两次运行约 1.39–1.44 s。
- 最终 CPU Node 单 seed 基准 Median 1.091 µs、P99 1.572 µs；8-seed bank Median 1.172 µs、P99 1.612 µs。
- 可运行 WebGL2 instancing demo、Chromium benchmark 与 SharedArrayBuffer Worker 骨架。
- 8 个 seed 已逐一复核 binary/canonical SHA-256、361 质数、互异、所有行列和与双对角线；中心值两两不同，合计 5,945,425,920 个不相交状态。

## 当前主要阻塞

- 云端 Chromium 的安全策略拒绝容器 localhost；当前没有目标 Chromium/GPU 实测数据，但已交付可一键运行的基准页。

## 下一步实验

- 在用户实际 Chrome/GPU 上跑 browser benchmark 和 Performance/Memory trace。
- 若未来继续扩 seed，先用中心值等群不变量分桶，再做轨道同构去重。

## 放弃路线的证据

- 当前没有引入 Rust/WASM：TypeScript CPU 成本比 30 Hz 预算低约五个数量级，缺乏收益证据。
- 默认不启用 Worker：单次计算远小于消息/调度成本；仅保留 SharedArrayBuffer 隔离方案。
