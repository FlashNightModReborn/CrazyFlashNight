# 动态根层级压力回归

仅在改动根层级分配、启动器模块挂载或 S1 初始化后按需运行。夹具在独立的 Flash Player 20 中创建 31,744 个空剪辑，会占用一段 CPU 时间。常规主动计时回归独立运行。

从本目录打开 Windows PowerShell。仓内可直接使用第一条命令。检查其他安装目录或候选三包时传入相应路径。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Run-DepthStress.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Run-DepthStress.ps1 -Resources "D:\SteamLibrary\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources" -ModuleDirectory "D:\候选\scripts"
```

执行器从游戏目录取播放器和注释框，从指定代码目录取 resident、shared、logic 三个 SWF，复制到本次测试的临时目录。夹具在真实 BootSequencer 进入启动步骤时调用生产 S1 函数。所有受试分配都由三个实际 SWF 内的代码执行。帧脚本仅布置占用、发起请求和观察结果。每次启动使用独立的测试 SharedObject 记录测量，读回后清理临时副本。

19 项检查覆盖以下行为。

- 键盘与时间轮在根深度 1024、1025 建立，模块容器保持 65531。两次不挂接的相邻查询返回 1026、1027。S1 保留同一管理器和游标。
- 穿过 32767 后跳过仍存活的系统剪辑。连续 16 层碰撞后测试重名剪辑、名称被根属性遮蔽的不可枚举剪辑、文本域、被覆盖的 getDepth 方法与非直属别名。记录哪些层实际经过播放器的原生查询。
- 分 62 个帧批次填满动态范围，验证全满时报错且游标保持原值。下一帧释放一个位置后应能找到空孔，尚未挂接剪辑时再次绕一圈可返回同一空孔。

默认将每次运行的 `checks.json` 和 `trace.txt` 写入 `%LOCALAPPDATA%\CF7DepthProbeEvidence` 下的独立子目录。可用 `-EvidenceDirectory` 指定证据父目录，`-TimeoutSeconds` 设置整次运行时限，默认 240 秒。退出码 0 表示 19 项全部通过，2 表示断言回归，1 表示执行或取证失败。满载、单孔与再次绕回的耗时分别写入记录。耗时随机器和负载变化。

`source/frame_1/DoAction.as` 是本夹具的完整观测脚本。附带的 `DepthProbe.swf` 以同级常规夹具的 CS6 时间轴为模板，仅替换测试片首帧。需要重建时，从本目录使用仓内 FFDec，随后重跑压力测试。

```powershell
java -jar ..\..\ffdec\ffdec.jar -importScript ..\WheelProbe.swf DepthProbe.swf source
```
