# Launcher 音频迁移期存档编辑器事件记录

**文档角色**：2026-04-28 静音事件、当前迁移补偿与退出条件的历史/治理记录。当前 Audio 架构以 [Audio Platform v2 ADR](原生音频平台-v2-格式能力桥接契约与可观测性-ADR-2026-08-09.md)为准，Launcher 入口以 [launcher README](../launcher/README.md)为准。

**最后核对代码基线**：commit `04718fa57afb64836e95893f0c4ff821d25ca043`（2026-08-16）。

## 事件与原因

2026-04-28 的“听不到音效”反馈最终定位到存档设置：Flash 拉档后把 `others.设置.setGlobalVolume=0` 和极低 BGM 音量推给 Host。旧 Flash 设置入口迁移期间缺少等价可见入口，玩家一旦保存静音值便难以自行恢复。

这是一条可发现性与迁移完整性问题，不证明原生音频引擎、设备路由或格式 bridge 故障。

## 当前补偿

- `launcher/web/modules/archive-editor.js` 的简易模式仍提供 `system` 卡片，并明确标记“迁移期临时入口”。
- `launcher/data/save_schema.json` 是可编辑字段、默认值、范围和分类的权威；当前包含 `setGlobalVolume` 等系统设置。
- `audio_preview` 由 Host handler 校验并应用预览音量；编辑器不得绕过存档写入与 repair 策略。
- 存档编辑器可以导出诊断包；它是排障和恢复工具，不是 Audio H2 验收界面。
- `AudioTask.SetToastSink` 当前只是兼容 no-op。`Program.cs` 仍保留调用点，但不能据此声称 launcher 会弹出一次性音量提示。

## 权威与风险边界

- 存档中的设置值由 AS2 `SaveManager.packSettings/applySettings` 定义；Web schema 是受控投影，不获得新业务权威。
- 原生 Audio v2 的实时 gain、endpoint、generation 与恢复状态由 Host audio coordinator/bridge 管理。
- 简易编辑器能恢复错误设置值，但不能证明真实端点播放、sleep/resume、蓝牙/HDMI 或听感质量。
- raw/tree 模式必须继续遵守类型、危险字段解锁、备份、revision 和写后读取边界。

## 退出条件

只有同时满足以下条件，才能撤销“迁移期临时入口”标记或删除补偿：

1. 标准游戏入口存在可发现的正式音频设置 UI，覆盖 master、BGM、SFX 及当前偏好语义；
2. 正式 UI 与 AS2 存档字段、Host 实时 gain 和写后持久化形成单一权威闭环；
3. 自动回归覆盖零值、边界值、非法值、预览、保存、重启回读和旧档迁移；
4. 冻结 runtime 身份下完成对应 feature-specific 标准入口旅程；
5. 删除或重新定义 `AudioTask.SetToastSink` 兼容 no-op，并同步清理 `Program.cs` 调用和注释；
6. 更新 launcher README、测试矩阵和本记录，不保留“临时入口仍是唯一恢复路径”的过时叙述。

达到这些条件前，存档编辑器可以继续承担恢复入口，但不得被称为完整音频设置产品或 Audio H2 证据。
