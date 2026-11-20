# CF6 大型历史证据归档收口与双端验证记录

本轮针对 [#287](https://github.com/FlashNightModReborn/CrazyFlashNight/issues/287) 完成后续批次的正式迁出与结项收口，来源基线冻结在主仓提交 `e4846cb1b69e974ac80f3793c618c06fd4110386`。连同试迁阶段的 `e/l18/`，#287 原卡点名的三处 CF6 历史证据根（原计约 1.55 GiB）已全部按需外置至独立归档仓 `FlashNightModReborn/cf7-evidence`。

## 全部已归档批次汇总

| 逻辑前缀 | 来源提交 | 文件数 | 原始字节 | ZIP 字节 | ZIP SHA-256 | Release |
|---|---|---:|---:|---:|---|---|
| `tools/cf6-elder-assets/e/l18` | `9f1192f1aa932eeac152f98e00882926e3dc3d65` | 309 | 48,465,246 | 19,154,370 | `1898d1f8d02829c57f1b91ceac7615def24f72f38cd8a65a280b15031b9edefb` | [cf6-elder-loader-l18-v1](https://github.com/FlashNightModReborn/cf7-evidence/releases/tag/cf6-elder-loader-l18-v1) |
| `tools/cf6-elder-assets/e/c17` | `e4846cb1b69e974ac80f3793c618c06fd4110386` | 4,774 | 865,113,281 | 506,354,595 | `1d4970eb42778e47f4a4bac5e294f336eadbf48d06d65a38d1c5606a06a7e87d` | [cf6-elder-calibration-c17-v1](https://github.com/FlashNightModReborn/cf7-evidence/releases/tag/cf6-elder-calibration-c17-v1) |
| `tools/cf6-elder-assets/evidence/20261017` | `e4846cb1b69e974ac80f3793c618c06fd4110386` | 1,987 | 419,380,588 | 201,896,020 | `b116801ef2ce44cbce20be6832570c7531210c0e513504f96ee5bf7bf1b129d7` | [cf6-elder-delivery-20261017-v1](https://github.com/FlashNightModReborn/cf7-evidence/releases/tag/cf6-elder-delivery-20261017-v1) |
| `tools/cf6-elder-assets/evidence/20261017-playtest` | `e4846cb1b69e974ac80f3793c618c06fd4110386` | 492 | 101,337,385 | 57,487,974 | `4229317b4b16b3ed71af0f9b9743f6caf639dcc9558b5e8539b0cabd3694f008` | [cf6-elder-playtest-20261017-v1](https://github.com/FlashNightModReborn/cf7-evidence/releases/tag/cf6-elder-playtest-20261017-v1) |
| `tools/cf6-audio/evidence/20261017-combat-audio` | `e4846cb1b69e974ac80f3793c618c06fd4110386` | 1,099 | 232,901,561 | 175,237,679 | `76ca5bb5f2cb4bac5d3ad25e069963abbeaa22cdcd9717171b8a0054dee4709f` | [cf6-combat-audio-20261017-v1](https://github.com/FlashNightModReborn/cf7-evidence/releases/tag/cf6-combat-audio-20261017-v1) |

- 统一归档索引：[归档索引](../../tools/cf6-elder-assets/evidence-archive-index.json)；路径解析与防回流守卫：[evidence_paths.py](../../tools/cf6-elder-assets/evidence_paths.py)、[evidence-paths.js](../../tools/cf6-elder-assets/evidence-paths.js)；恢复工具：[restore_evidence.py](../../tools/cf6-elder-assets/restore_evidence.py)。
- 历史别名保留：旧长路径 `20261017-calibration/*` 与逻辑路径 `e/c17/*` 共 4,774 条映射、连同 `e/l18/*` 309 条映射合计 5,083 条保留在 `evidence-path-map.json`，`resolve` 与 `restore_evidence.py` 均可原样解析。
- 伴生轻量摘要原地保留：`tools/cf6-elder-assets/evidence/20261017-playtest-closeout/` 与 `tools/cf6-audio/evidence/20261017-combat-audio-closeout/` 各自绑定对应归档 `integrity.json` 摘要，继续留在主仓供本地只读核对。

## 双平台干净检出与消费者复验

迁移前在 `cf7-evidence` 的 [双端验证 Run 44656647078](https://github.com/FlashNightModReborn/cf7-evidence/actions/runs/44656647078)（Windows Server 2022 耗时 1m55s，Ubuntu 24.04 耗时 10m33s）以不含上述任何被归档目录的稀疏检出执行完整恢复与只读消费者复验，永久证明已归入各 Release 资产 [cf6-issue287-replay-proof.json](https://github.com/FlashNightModReborn/cf7-evidence/releases/download/cf6-elder-calibration-c17-v1/cf6-issue287-replay-proof.json)（SHA-256 `7b876abce2d2a9bc6f87b5f42242e5f2418ec2609ac9b0661bb4233043442850`，9,077 B）：

- **全量 Git 对象与历史清单一致**：Windows 与 Ubuntu 两端均从 Release URL 下载恢复全部 5 批 8,661 个文件；`e/c17`（4,774 文件 / 4,773 条 `integrity.json`）、`evidence/20261017`（1,987 文件 / 1,986 条）、`evidence/20261017-playtest`（492 文件 / 491 条）、`20261017-combat-audio`（1,099 文件 / 1,098 条）及 `e/l18`（309 文件 / 308 条）逐件匹配。
- **`e/c17` 跨批绑定与 `analyze-arena.py`**：恢复后的 `e/c17/integrity.json` 摘要与 `e/l18/summary.json` 内 `priorC5Calibration.filesUnchanged.integritySha256` 一致；重组 `current-final-source.zip.gz.part001..003` 后结合主仓 5 个未修改文件运行现役 `analyze-arena.py`（`--expected-levels 60 80 100`），复现 `fullMatrix=True`、6 组共 36 场 R22 结果。
- **`evidence/20261017` 与 `20261017-playtest`**：两端均校验 `lossless-mapping.json` 全部分片重组（含 `frozen-inputs.zip` 508 项源码及 `current-source-and-assets.zip` 378 项）、从 `matrix/*.jsonl` 去重重算 R15 的 36 场与 6 组统计（`< 1e-9`），并与保留的 `20261017-playtest-closeout/summary.json` 摘要吻合。
- **`20261017-combat-audio` 与现役 `extract.py` / `audit.py`**：校验与 `20261017-combat-audio-closeout/primary-package-integrity.json` 一致；重组 `original-cf6.swf`（SHA-256 `b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01`）、`before-source.zip`（`845aec5bedc43a64721a7375b4e739dad9ebd202c6165bd26353d54a70f7171b`）与 `current-source.zip`（`fb588a4e9a3239896beea8c417ca82168ee607b12eaf1239ac4879ec2c84a4c7`）后，双平台实跑现役 `audit.py`（8 库 12 形态、45 处原作缺失位点归零、44 份音频解码通过）和 `extract.py --write`（41 份 MP3 与 3 份包络 WAV 均在 Windows ffmpeg 9.0.2 与 Ubuntu ffmpeg 6.1.1 上输出零样本差、逐字节一致）。
- **路径守卫与拒绝边界**：`test_evidence_paths.py` 通过；Python 与 Node 守卫均拒绝向全部 7 个退役前缀写入；损坏 ZIP 与指向仓库内部的 `--output` 均被安全拒绝且不残留目录。

## 治理范围收口裁决（#287 结项）

- **体量收口成果**：通过迁出 `e/l18` 与上述 4 个头部 CF6 历史证据批次（合计 8,661 个文件、约 1.55 GiB），主仓 `tools/` Git 跟踪检出体积由约 2.25 GiB 降至约 0.71 GiB，消除开发树与多工作树克隆的主要体积冗余，同时保持全部现役构建、CS6 编译、打包与发布入口未变。
- **剩余目录原地保留裁决**：除上述头部批次外，其余子目录散落的 `<70 MiB` 历史小证据（`bladebot`、`guard`、`headbot`、`soldier`、`portrait-pilot`、`player-info-hud` 等，合计约 292 MiB）以及现役构建/运行依赖目录（`rapfi`、`cf6-map-runtime`、`cf6-vehicle`、`cf6-scene-completion`、`dotnet-runtime`、`ffdec` 等）**明确原地保留**；其零散改造与文档链接维护成本高于外置收益。后续新增专项与大样本按 [研究工具与证据归属](../../agentsDoc/documentation-governance.md#optional-research-artifacts) 执行，不再重演大包直接入主仓历史。
- **历史不重写**：主仓保留完整 Git 提交历史，不做历史重写，避免破坏代码基线 SHA、发布共识 tag 与归档 `sourceCommit` 绑定。

## 恢复与回退

- 按需取回各批次请参见 [老头归档入口](../../tools/cf6-elder-assets/README.md#cf6-elder-archives) 与 [音效归档入口](../../tools/cf6-audio/README.md#combat-audio-archive)。
- 如需在主仓无损恢复上述 4 个目录及原文档链接，对本次迁出提交执行单次 `git revert <本提交>` 即可完整还原。
