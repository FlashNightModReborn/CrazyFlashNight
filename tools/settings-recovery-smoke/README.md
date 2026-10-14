# Settings 候选冷恢复探针

在独立进程加载指定候选的真实 Core 和 Rust SOL parser，读取本轮 `cf7_env_set_<20位nonce>` 原生测试槽并执行其 Settings recovery gate。只写传入的隔离 journal 副本和证据目录；不启动游戏，不发送 apply/save，不改原始 SOL，也不代表完整 UI 回滚或所有旧 writer 均受门控制。

先用候选自身入口验证完整 runtime，再用仓库锁定 SDK 构建本工具，传入 `-p:CandidateRoot=<绝对候选路径>`。运行参数依次是候选根、`prepare-settings-sol-fixture.js` 生成的 `fixture.json`、该 fixture 证据目录内的独立 journal 副本、尚不存在的输出目录。

每个旧／新候选和状态组合使用新进程。报告记录实际 Core 路径、MVID、Core/parser SHA、候选 identity/closure、原始 SOL 前后 SHA、receipt、journal 状态和准入结果。`status=observed` 只说明观测完成；调用方必须按 unknown、exact proof、future schema 等具体合同判断 allowed/mayWrite，不把进程退出 0 当兼容通过。保留全部失败和不兼容报告。

`node tools/settings-recovery-smoke/run-compatibility.js <锁定dotnet路径> <fixture.json> <新候选> <待核旧候选>` 运行五组新→旧→新原生冷恢复，并补充两组带原始未决 journal 直接进入旧候选的向量。每组仅改独立 journal 副本，原生 SOL 和原 fixture journal 不变。

第八组把真实 Rust 解析结果深复制后，在内存中派生“未来 receipt schema + 无法规范化的设置正文”，交给各候选的真实 raw reader/recovery gate。它明确标为 parser 边界注入，保留派生 JSON 与源 SHA，不改原 SOL、不冒充真实 flush。发现旧候选错误放行时矩阵返回 `incompatible`；该旧候选不可用于业务回滚。全部向量均不代签完整 UI 回滚。
