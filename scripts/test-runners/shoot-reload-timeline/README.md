# 装填打断射速回归

唯一入口：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-shoot-reload-timeline-tests.ps1 -TimeoutSeconds 300`。

测试由真实 CS6 `testMovie()` 执行，不读取玩家槽位。`ShootReloadNativeHost` 的 XFL 真源位于 `scripts/ShootReloadNativeHost/`；runner 将其确定性复制到根目录下被忽略的 `tmp-shoot-reload-native-host/`，产出根目录被忽略的 `ShootReloadNativeHost.swf`。这是测试宿主，不属于生产 SWF 或正式 runtime。

根目录执行是必要的：现役 `things0.swf` 还导入 `flashswf/arts/新版人物文字信息.swf`，必须沿用游戏的相对 URL 基准。不得修改生产资源的 RSL URL，也不能用嵌套 `loadMovie` 的空附件结果冒充角色验证。代理 `.xfl` 内容相同时不重复覆盖，避免覆盖 CS6 持有的同名文件锁；每次编译仍由现役两阶段关闭/重开事务从盘读取目标。

`ShootReloadTimelineTest` 使用现役 `主角-男`、长枪上身及其换弹标签时间轴，并从物品 XML 读取逐发装填的 53 式步骑枪和整匣装填的战术巴雷特。后者覆盖交替 R/J、按住 J 点 R、按住 R 点 J，以及一发后点 R 再按住 J；既检查最小间隔，也检查不能靠 R 重新武装持续按住的普通半自动。单位基础字段、动作标志、库存与弹体出口是隔离夹具；射击、换弹、`processShot` 和弹药消耗走生产实现。输入经 `man.开始射击/开始换弹`，不把该夹具称作真实键盘或完整游戏状态机验收。

帧戳来自真实 `CooldownWheel.tick` 调用的观察包装，结束时恢复原方法；不会额外推进时间轮。另有 `ShootReloadCadenceTest` 在真实 AVM1 中手动推进同一时间轮，精确检查最小间隔、暂停拒绝、无库存拒绝、迟到解锁、卸载清理和持续点射。所有观察包装仅存在于测试源。

`GunslingerDualCadenceTest` 在真实 AVM1 中手动推进时间轮，覆盖枪械师 1／5／10 级、主副手、连续点按、点按转按住、按住转点按，以及半自动/全自动混持和技能关闭。它使用生产双枪绑定、弹体提交与弹药消费，独立期望表核对提交 tick 和间隔戳；动画、库存与弹体出口为隔离夹具，不能称为完整游戏输入或双枪角色动画验收。

同一 focused 事务还运行现役弹药、长枪副武器、双枪后摇、手动技能冷却、药剂输入与键位 suite。完整集合与判据只维护在 runner；独立 `run-player-manual-input-tests.ps1` 保持可用。

scratch 安装、备份、mutex、fresh Compiler 0/0、唯一 runId、失败哨兵、异步闭合与恢复均复用 `run-focused-testloader.ps1`。不绕过未知 marker；失败宿主先通过现役 `-StopTestPlayers` 双 nonce 回执确认停止，核对迟到产物稳定与原始 scratch 哈希后才恢复本轮状态。

机器通过后保留一次短人力检查：原武器物理点 R→攻击的响应、连续点射节奏和装入一发后取消的手感。测试宿主通过不证明当前游戏入口已装入修复。
