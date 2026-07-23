# 武器加权旧工作流（迁移提示）

> **历史文件，禁止作为现行平衡判据或施工入口。**

本文件原先记录 `weightlevel`、简化 DPS 公式和经验系数。该体系与当前权威工作簿及 `<balance>` schema 不一致，正文已移除，避免形成第二套可执行规则。

当前入口：

- schema、落盘流程与验证契约：[`tools/cf7-balance-tool/docs/agent-balance-record-design.md`](../../tools/cf7-balance-tool/docs/agent-balance-record-design.md)
- 业务判据与稳定条款 ID：[`tools/cf7-balance-tool/docs/weapon-balance-rulebook.md`](../../tools/cf7-balance-tool/docs/weapon-balance-rulebook.md)
- 公式最高权威：`0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx`
- 旧计算记录：[`weapon_weighting_log.md`](weapon_weighting_log.md)（历史日志，不能证明当前参数正确）

历史背景：该旧流程创建于 2025-08-29，曾把加权等级写成 `<data><weightlevel>`，并使用无法覆盖现行工作簿的简化估算。需要追溯旧结论时请查看 Git 历史；不得从旧结论直接迁移 `<balance>`。
