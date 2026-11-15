# 主动计时回归夹具

在 Windows 上解压到可写目录，打开该目录的 PowerShell，将下面路径替换为游戏的 `resources` 目录。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Run-WheelProbe.ps1 -Resources "D:\SteamLibrary\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources"
```

比较另一个候选时，加上 `-ModuleDirectory "D:\候选\scripts"`。该目录可放原单包，或完整的入口、共享库、逻辑库三个文件。播放器和注释框始终取自 `-Resources`。脚本用游戏自带 Flash Player 20 的独立进程运行临时副本。在游戏源码仓的本目录运行时可省略 `-Resources`。默认将 `checks.json` 和 `trace.txt` 保存在 `%LOCALAPPDATA%\CF7WheelProbeEvidence\CF7WheelProbe-…`，也可传入 `-EvidenceDirectory` 指定证据父目录。退出码 0 表示通过，2 表示复现回归，1 表示执行环境或取证失败。环境失败时查看 `checks.json` 的 `error` 字段。

夹具加载实际 asLoader 和外部注释框，截取启动时的层级管理初始化、鼠标层和交接，再重放主片中注释框登场、下一帧离开时间轴的动作。枪械调用实际 `ShootCore.startShooting`，用小型测试单位接收发射调用。第 12 帧松开全自动按键，第 16 帧重新按下。半自动额外测试长按及两次松开重按。普通和叠加画布分别绘制三角形，并分别按 5 次和 3 次衰减回收。

| 检查 | 预期 |
| --- | --- |
| 注释框退场 | 65533 由注释框占用，`_root._cdWheel` 仍保留有效帧回调 |
| 全自动 | 第 16 帧前计 6 次发射，当时射击锁和任务已释放。第 24 帧累计 11 次 |
| 半自动 | 长按共 1 发，两次松开再按分别达到 2、3 发 |
| 普通和叠加刀光 | 初始是两个不同画布。普通完成 5 次衰减，叠加完成 3 次。随后都隐藏、图形宽度归零 |
| 时间轮 | 一次性任务调用 1 次，重复任务调用 3 次，驱动对象身份保持一致 |
| 300 毫秒存档防抖 | `SaveManager.saveAll()` 接受请求，最后由实际延迟调度回调命中计数器一次 |

存档检查在进入序列化或实际写入前把回调接到计数器。夹具仅在随机的临时命名空间写入自己的小型测量记录，读回后清理。测试覆盖的是射击调度、刀光画布和存档调度到期。角色贴图、弹丸命中、架势和完整游戏存档流程需通过游戏入口另行验收。

可以直接使用附带的小型 `WheelProbe.swf`。复查源代码时，帧脚本位于 `Source\Probe.as`，三帧的时间轴位于 `Source\WheelProbe\DOMDocument.xml`。通过 Flash Professional CS6 打开 `Source\WheelProbe\WheelProbe.xfl` 可查看和重新发布测试片。重新发布的文件位于 `Source\WheelProbe.swf`，用 `-FixtureFile ".\Source\WheelProbe.swf"` 可直接测试。脚本记录整文件 SHA-256，同时核对除 CS6 自动更新的 XMP 元数据及文件长度字段之外的完整字节。
