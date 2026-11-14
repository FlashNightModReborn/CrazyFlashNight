# 项目记忆导航

**文档角色**：受限导航与术语提示；工程权威和操作权限见 [AGENTS.md](../../AGENTS.md)。
**核对基线**：`c475797b8afaf37e9b5fe7d805ca932a668d4ed8`（2026-11-14）。

## 按任务定位

| 任务 | 当前依据 |
| --- | --- |
| 编译目标、环境、异常恢复 | [验证选择矩阵](../../agentsDoc/testing-guide.md#as2)、[CS6 操作合同](../../scripts/FlashCS6自动化编译.md)、[CS6 4G 地址墙取证](../../docs/flash-cs6-va-exhaustion-and-host-profile-2026-11-14.md) |
| AS2 语义、BOM、跨 SWF 生命周期 | [反幻觉约束](../../agentsDoc/as2-anti-hallucination.md)、[加载时序](../../agentsDoc/as2-load-timing.md) |
| 数据、数值与派生物 | [数据归属](../../agentsDoc/data-schemas.md#data-entry)、[游戏设计](../../agentsDoc/game-design.md) |
| XFL、linkage、图标 | [美术装配](../../agentsDoc/art-asset-assembly.md)、[Linkage Scanner](../../tools/linkage_scanner/README.md) |
| Host / Web / 原生对话 | [源码地图](../../launcher/README.md#source-map)、[本地开发入口](../../automation/README.md) |
| 协作、范围与经验归属 | [Agent harness](../../agentsDoc/agent-harness.md)、[记忆治理](../../agentsDoc/documentation-governance.md#agent-memory) |

本入口只提供定位信息。执行依据从当前源码、对应合同和当前任务授权取得；
日期日志、历史实测、旧机器路径和过去用户要求不能替代这些依据。

## 术语提示

2026-09-26 的[会话记录](2026-09-26.md)中，“暂存”指 Git 暂存区，不指 stash。
这条提示只消除词义歧义，不授予暂存、提交或其他 Git 操作权限。

## 历史调查索引

以下资料保留探索过程和复现线索，正文均按历史材料使用；先看页首裁决，再核现役源码。
需要调查对应问题时才读取，不作为日常全量预读内容。

- [封印领域](topics/封印领域-天启大封印.md)、[战技与装备插件](topics/战技与装备插件.md)
- [技能注册](topics/技能注册清单.md)、[物品与素材映射](topics/物品数据与素材映射.md)
- [手写 XFL](topics/手写XFL-格式与踩坑.md)、[素材与图标管线](topics/素材与图标管线.md)
- [足球手雷历史接入说明](topics/xfl-参考脚本/足球手雷-接入说明（历史）.md)
- [整理前完整原文](../../docs/裁决存档/workbuddy-memory-cfb1952e-2026-11-03.txt)（含原始 BOM，原字节保存）
- [本轮可信度审计与裁决](../../docs/agent-memory-trust-audit-2026-11-03.md)
