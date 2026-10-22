# CF6 Boss 有限增援验证

`Cf6BossEncounter.as` 只负责史实路线 Boss 场的有限增援；原生主波保留一个 Boss。内容入口是 `maps[].bossEncounter`，生成门禁在 `tools/build-book-definition.py::validate_cf6_boss`，运行时文件检查在 `tools/book-definition-runtime.as.inc::validCf6Boss`。不得以普通主波的全歼条件替代原作的 Boss 死亡条件。

控制器在 `BookRunService.presentChapter` 的 CF6 分支接线，绑定 run 对象、书籍、路线、槽位、世界普通对象身份、StageManager/currentStage 与 WaveSpawner。已发出但未初始化的增援也占用总数与远程上限；Quantity 展开为只消费一次的有限队列。Boss 必须先绑定有效存活演员，之后才接受该演员的有限数值 HP ≤ 0；undefined、NaN、同名替身与伪造死亡事件不能结束本场。

Boss 死亡取消未发出的增援、无奖励退场本场存活增援，并调用原生 clearStage。普通击杀的经验和地面掉落保留。469 的变身父体与 phase.child 后继共享一个逻辑位置；身份来自已绑定父体的普通 phase 对象与后继 attach 初始化参数，不能只凭后继名称认领。场景或其他绑定失效只取消，不算胜利。清场仍经过 Cf6MapMechanism 的既有转场/动画合同。

执行真实 CS6/AVM1 夹具：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-boss-encounter-tests.ps1
```

runner 使用统一 focused TestLoader 协议，处理 scratch 备份/恢复和本轮 trace 身份。先遵循 `scripts/FlashCS6自动化编译.md` 的共享 GUI 所有权要求；不得在另一任务占用 CS6、TestLoader 或测试播放器时启动。`-SkipCompile` 只用于统一 runner 允许且身份匹配的既有本轮构建，不证明改过的源码。

本 suite 使用真实 MovieClip、事件分发和 StageEvent，但以内存夹具替代演员资源与 StageManager/WaveSpawner 外围；它不证明 Guard SWF 本身、实际战斗节奏、完整章节、正式发布或标准入口。章节接线还需运行书架套件；内容门禁用 `python -X utf8 tools/test-book-definition.py` 与生成器 `--check`。实际章节应通过绑定 asLoader、候选身份、资源和存档保护的 live runner 独立取证。
