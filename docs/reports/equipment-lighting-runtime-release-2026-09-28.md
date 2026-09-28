# 装备照明与功能插件：正式 runtime 发布记录

**文档角色**：2026-09-28 本批发布的历史证据与验收边界。现役身份仍以 [runtime 共识记录](../../config/build/runtime-release-consensus.json) 和 [runtime manifest](../../runtime/cf7-runtime-manifest.tsv) 为准。

## 发布结果

维护者明确授权“走发布列车”。手电/镭射、战术手电防御插件、生命周期战技隔离、蓝晶防具与发光兵器、常驻灯归并和装备注释已合入 main，并完成正式 promotion。没有新增稳定整包或改动版本号。

| 项目 | 本次证据 |
|---|---|
| 功能提交 | `31fab290b96c1af886598639e019f092dc85cae4` |
| 最终冻结源 | `94d5872e5d7775facf200020677c9910f493496f` |
| 冻结树 | `e7a047863345656adbdbaedd0cfe0ca4ad3ca429` |
| 受保护标签 | `runtime-build-v2/20260928-equipment-lighting-v2` |
| immutable request | `E48D0C3A79B243AFAF2B22548DEF449C4BE3096DC8B4BCAEAD11D80A8A07F7AC` |
| build identity | `B03921EDF979E8738CB59C98348583B9E120DE9165EDBE04ECFA270A513AE6D7` |
| payload closure | `2DA661018248FDC632DAF48AD304A0E709EA49A7CCF2C8BA48BDDDA7DCC97DAE` |
| policy hash | `9CF6EB22E11570FAA0E38AD9C44560485CE4E848BF34920EA04F79E4CD61A332` |
| 部署提交 | `143d8c2878b7ceb9665d8d44c74a5fa268ae5269` |
| 本地证明 | 已注册 `builder-local-c` / `physical-host-c`，X509 签名；政策修正后复用同一构建身份的已签名 payload |
| 独立云端证明 | [GitHub run 36436503777](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/36436503777)，Windows 2022、OIDC/Sigstore，精确绑定最终冻结源 |
| 正式政策门 | production 42/42；旧失败收据未用于 promotion |
| 原子写入与回验 | 唯一 `promote-runtime-bundle.ps1` 成功；strict v2 验证 36 个 payload 文件、2 signer / 2 faultDomain；根 bootstrap `--verify-only` 通过 |

部署后 CI：[run 36438460369](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/36438460369) 已成功，独立重放正式部署的证明与闭包。

## 实际验证范围

- 最终配套 asLoader 由真实 CS6 从隔离发布目录编译，Compiler 0/0，1402819 B，SHA-256 `D52C8456AD8D1D42425A927BA13CB8141034686939D3E691CE3161B6235C3608`。主文件 0 工程类、asLoader 682 类、交集 0；最大函数体 50959 B。已纳入当时 main 的佣兵修复后补编译。
- canonical Host 回归 6065 passed、5 skipped；155 条生命周期标记和 30 件自发光装备检查通过。材料目录与存档修复字典已同步，主目录更新后材料目录和商店头像完整性再验通过。
- promotion 后，以正式 `runtime/FlashCompositorNative.dll` 执行 WGC/D3D11 GPU 夹具并通过；主目录与隔离发布目录的 DLL SHA-256 均为 `87A37F70F9A46D94D92E9A2E27AA66B89FD55C726538FE552DDAC80EAC33B0C2`。覆盖手电、细镭射、身体/兵器径向光、近身衰减、镜头、上限、清理和实际 XML 快照。蓝晶同色组合 1 灯、峰值 1.5；蓝晶与血剑 2 灯、峰值约 1.492。像素夹具不等于实战观感或游戏 FPS。
- 主目录无参数 `automation/start.ps1` 成功，实际进程 PID 24696；确认 `formal_runtime`、正式 Core 路径、Core SHA-256 `3F9389FF592DF7858183F074124FA6CA8EC12C817070D7327288940476BF5D12`、identity 和 closure 全部吻合。随后通过正常关窗退出，本次 Guardian、hotkey guard 和 ports 文件均已结束/清理。
- 正式入口核对限于启动身份和正常关窗，未执行装备照明的实战旅程或持久写测试，不能据此标记完整业务 `standard_entry_verified`。维护者已决定把完整战斗帧耗、弱机评估与未来场景光源一起做性能专项；本次保留该边界。

## 首轮阻断与工作区保护

首次冻结 `31fab290b9` 的政策门为 41/42：新增战术手电商品后，商店头像来源记录仍绑定“迷之盔甲君”旧目录字节。通过现有 `refresh-shop-portrait-sources.py` 刷新来源和配套收据，再用完整校验器验证；36 张头像与运行 manifest 字节未变。旧 v1 标签、request 和失败收据保留，新建 v2 标签/request、最终云端证明与 42/42 政策收据后才部署。

施工从独立工作树冻结；主目录随后快进到部署提交。原有 35 项佣兵/地图文档工作状态按原字节还原，未混入本批发布；其中佣兵草稿与已提交主线存在重叠，本次没有替其他任务裁决草稿。原始完整快照保存在 stash `9793a6f7896b4484f8c8eaabd448ea7aaa4f1b0d`，逐文件备份和核验记录在本机 `tmp/equipment-light-release-20260928/primary-sync-state.json`。正式验证绑定上述冻结源及已编译 asLoader，不代签这些未提交草稿。

本机证据位于 `tmp/equipment-light-release-20260928/`：最终 policy receipt、promotion 日志、正式 DLL GPU 结果、入口 smoke、双构建证明与失败历史；受跟踪的共识记录保留签名与政策收据。实现和前轮专项行为证据见[装备照明](equipment-lighting-implementation-2026-09-28.md)、[防具/兵器扩展](equipment-emissive-expansion-implementation-2026-09-28.md)及[生命周期打标](lifecycle-skill-metadata-2026-09-28.md)。
