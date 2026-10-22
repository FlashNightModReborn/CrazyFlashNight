# CF6 固定等级生产入口回归

`TestLoader.as.template` 先调用 `Cf6LevelCapTest.captureRoot()` 保存根变量与函数，再真正 `#include "引擎/引擎_lsy_等级与经验值.as"`，最后调用 suite。没有复制经验公式或以外部模型替代 AVM1。runner 检查这三步的顺序，并把生产经验引擎与 `BookRunService.as` 纳入本轮源身份。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-level-cap-tests.ps1
```

真实 CS6 编译、共享 GUI 所有权和 scratch 恢复沿统一 focused TestLoader 协议与 `scripts/FlashCS6自动化编译.md`；其他任务占用编译环境时不要启动。

验证真实普通升级、健身升级、击杀经验三个根入口；覆盖 CF6 historical 当前槽位的 60 级高经验、59→60 循环边界，以及校园书、李氏试炼、普通角色、错槽、错路线和已脱离旧 run 的既有成长行为。玩家满级不改变既有宠物独立经验行为。所有根变量、根函数、原属性是否存在以及替换的类函数在 finally 中恢复。

仅外围的 `TargetCacheManager.findHero`、`EffectSystem.Effect`、`PlayerAssetTransaction.requestStrongSave` 使用内存桩，避免查找真实角色、播放效果或写真实存档；生产升级逻辑、经验公式和 `LevelUpRecovery.refresh` 仍真实执行。断言中的保存次数表示生产入口提出保存请求，不表示磁盘写入完成。本 suite 不证明持久化、实际章节入口或玩家体验。
