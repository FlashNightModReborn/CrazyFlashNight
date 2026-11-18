# CF6 历史证据读取点与 C6 归档试迁

本轮针对 [#287](https://github.com/FlashNightModReborn/CrazyFlashNight/issues/287)，读取点核对基于游戏仓 `9f1192f1aa932eeac152f98e00882926e3dc3d65`。首批只迁 `tools/cf6-elder-assets/e/l18/`，即 2026-10-18 C6 加载器补验。

## 仍在读取的脚本

| 读取入口 | 输入与归档边界 |
| --- | --- |
| [老头装配](../../tools/cf6-elder-assets/build.py)、[资源复验](../../tools/cf6-elder-assets/verify.py)、[注册](../../tools/cf6-elder-assets/register.py)、[试玩夹具](../../tools/cf6-elder-assets/build-playtest-fixture.py) | 使用现役原稿、XFL、发布 SWF、AS2、资源和清单。`run-cf6-elder-asset-tests.ps1`、大头、瞄准、压力和盾分离的回归脚本调用试玩夹具。固定输入没有指向三个历史证据根。 |
| [音频装配](../../tools/cf6-audio/build.py)、[现役](../../tools/cf6-audio/build-test-fixture.py)与[旧角色音效夹具](../../tools/cf6-audio/build-legacy-test-fixture.py)、`restore-legacy*.py` | 读取现役素材、SWF、音效清单、`asset_source_map.xml` 和 `sounds`。两个音频回归入口分别调用两类夹具。 |
| [音频提取](../../tools/cf6-audio/extract.py)、[音频审计](../../tools/cf6-audio/audit.py) | 原 CF6 SWF 由 `--source-swf` 提供，审计另需 `--baseline-zip`。历史音频包中的 `original-cf6`、批次快照和分片可作为离线来源，迁移该批之前需验证无损拼接与两种输入的哈希。 |
| [斗兽分析](../../tools/cf6-elder-assets/analyze-arena.py)、[目标裁决](../../tools/cf6-elder-assets/assess-arena-targets.py)、[原生采集解码](../../tools/cf6-elder-assets/decode-native-capture.py) | 读取调用者显式给出的结果、诊断/观测、源码根或 trace。`arena-plan.js` 读显式配置和现役清单，输出路径由现有检查器约束。还原相应批次后可向这些离线工具传入原件。 |
| [历史路径解析](../../tools/cf6-elder-assets/evidence_paths.py)、[路径映射](../../tools/cf6-elder-assets/evidence-path-map.json) | `resolve` 读精确别名并打印逻辑路径。`restore_evidence.py` 用同一别名和[归档索引](../../tools/cf6-elder-assets/evidence-archive-index.json)恢复实体。Python 和 Node 的新证据路径检查为 `e/l18` 保留归档用途。 |
| 各批次封存的 `verify-followup.py`、`verify-sealed-calibration.py`、`verify-final-package.py`、`verify-delivery.py` 及采集脚本 | 历史代码依赖原批次布局。C6 的 `verify-followup.py` 还核对历史 C5 校准清单，不能仅靠恢复 C6 就宣称该旧脚本能在当前主线上重跑。归档保留原文与原件，跨机验证使用现役只读工具。 |

在启动、编译、CI、构建身份和打包的脚本与配置中，未发现指向本次 `e/l18` 目录的输入。文档中 C6 的活跃链接集中于老头、大头和 asLoader 说明，现统一指向老头 README 的恢复入口。

## 首批归档和回读

- [独立归档](https://github.com/FlashNightModReborn/cf7-evidence/releases/tag/cf6-elder-loader-l18-v1)对应原树 309 个文件，共 48,465,246 字节；ZIP 为 19,154,370 字节。包内 manifest 绑定原相对路径、Git blob、mode、字节数和 SHA-256。309 个短路径与 309 个旧路径保持一对一。原 `integrity.json` 的 308 条成员逐件通过。
- [跨机回读](https://github.com/FlashNightModReborn/cf7-evidence/actions/runs/44206096199)从不含 `e/l18` 实体的干净检出出发。Windows Server 和 Ubuntu 通过旧路径查到归档并恢复，核对整批 Git 对象与历史清单。现役 `swf-function-sizes.js` 读取恢复后的 C6 SWF，测得最大函数体 **53,041 B**，通过 **60,000 B** 门槛。错误 ZIP 校验失败，目标目录未生成。
- 现役夹具基线另外保留三项前后对照。老头试玩夹具的 `单位函数_lsy_敌人模板迁移.as` 与来源清单哈希已不一致。音频的光头保安「击飞」元件只有一帧，现役夹具找不到空闲帧而报 `StopIteration`。旧角色音效夹具生成字节一致，来源清单校验有差异。这些状态在试迁前已存在，试迁后复验结果一致。

回读命令和本地 ZIP 用法见 [C6 归档入口](../../tools/cf6-elder-assets/README.md#c6-loader-archive)。如需回退主仓，使用 `git revert` 反转本次归档迁移提交即可恢复原 `e/l18` 树和原链接。冻结来源提交也可用于独立检出和逐件复核。

## 后续批次

- `e/c17/` 约 825 MiB，既是历史斗兽证据，也是 C6 历史 verifier 的依赖。先按 `integrity.json`、源码快照与 `--source-root` 建立一批跨批读取验证。
- 音频 `20261017-combat-audio/` 约 222 MiB。切换前验证 `original-cf6` 与 baseline 分片的重组，确认 `extract.py` 和 `audit.py` 收到原 SHA-256 的输入，以及 closeout 的旧链接仍可定位。
- 早期老头交付与试玩证据仍有各自的归档脚本与文档入口，本轮继续原地保留。
