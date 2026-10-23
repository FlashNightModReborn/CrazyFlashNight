# CF6 异常精英武器真实资源夹具

`prepare.py` 只创建本工具的独立 XFL、BOM 测试类和模板，不编辑共享 ActorAppearance/field/body/traversal 宿主、不改物品映射、不编译或修改 SWF。先保全的生产输入位于 `tmp/cf6-roguelike-20261023/validation/item-visuals-r1/before/`；机器来源与输出身份见本目录 `source-manifest.json`。

当前 native-r7 已在合入上游 things0 特效更新后真实通过 **54/54**，本轮 fresh Compiler **0/0**、32K retry **0**。证据目录为 `tmp/cf6-fieldfix3-20261023/item/native-r7/`，`flashlog.txt` 的唯一 runId `9e130832808b4b32823db75dc3372f95` 有 Start、54通过/0失败和 Complete；`runner.log` 已给出本轮 OK。测试逻辑与r6相同，source-manifest重新绑定当前共享SWF。这是独立原生夹具的实际AVM1执行结果。

```powershell
python -X utf8 -B tools/cf6-item-visuals/prepare.py
python -X utf8 -B tools/cf6-item-visuals/prepare.py --check
powershell -NoProfile -ExecutionPolicy Bypass -File tools/cf6-item-visuals/run-tests.ps1
```

最后一条只由持有 CS6 队列的主控串行执行，沿用现役 focused runner 的 scratch 备份/恢复、exact runId、新鲜 Compiler 0/0 与行为门。精确目标是 `tmp-cf6-item-visuals-host/Cf6ItemVisualNativeHost.xfl`，输出 `Cf6ItemVisualNativeHost.swf`；不使用活动文档或 main 兜底。保持独立宿主目录与原 RSL 路径不变，目标 SWF 位于仓库根，因此实际 XML URL 与 RSL URL 均从仓库根解析。

预期 `Cf6ItemVisualTest Tests Passed: 54`、`Tests Failed: 0` 和本轮唯一闭合 `FocusedTestRunId cf6-item-visuals`。XML 异步加载或链接缺失必须失败，不能降低断言数后收口。

夹具通过实际 XMLParser 读取现役步枪 XML 的 SAI 身份和 CAR 兼容映射，直接从原 `3102&Leave.swf` RSL 导入 `枪-长枪-CAR` 与 `图标-CAR`；经 things0 原生主角、DressupReferenceManager、当前枪架的站立/行走左右四姿态检验挂装。逐案记录武器 alpha 像素与“隐藏枪前后”的角色像素差，防止仅凭角色身体或字符串判成功。图标第1帧和地面第2帧分别等待真实帧并统计非透明像素；空元件负对照必须为0。

这是现役主角枪架与原 RSL 的可见性专项，不能代签兵种466/467完整初始化、真实地面掉落交互、开火命中、声音或人类观感。工具不会写入背包或真实存档。

native-r6 保留原滤镜与cache设置，从world真实合成采样完整枪架外框＋四边8px，并逐例断言外框包含全部CAR skin。仅停住上身子时间轴，原作两条腿的 `onClipEvent(enterFrame)` 和原生上身矩阵变化继续运行。prepare绑定主角原作长枪行走主帧index151、`长枪-手枪2行走右腿` 与 `长枪-手枪行走左腿` 的各22帧源时间轴；运行时要求恰好两个对应总帧数的直接子剪辑。

站姿显隐对照每次等待两真实帧；行走每次至少跨两帧，并须两腿帧号与man六项矩阵完全回到基线相位，超过实际最长周期的四倍仍不匹配即失败。r6实际两侧行走均在两腿 **9/22** 帧取样，stable/hidden/restored间隔各 **22** 帧且矩阵完全一致；其stableDelta/restoreDelta均为 **0**，隐藏枪差分分别 **1549/1554**。站姿两侧同样稳定与恢复零差分，隐藏差分 **1544/1555**；图标第1/2帧分别 **546/1987** 非透明像素。这里证明保留原腿动画时该同相位下枪身确实参与合成；不扩大为全部22帧逐帧可见性验证。

此前失败原件全部保留于 `tmp/cf6-fieldfix3-20261023/item/native-r1/` 至 `native-r5/`，未用本轮通过覆盖：

- r1：宿主输出路径多退一级，实际SWF未产出；只修本线输出路径，未改原RSL URL。
- r2 38/40、r3 36/40：同帧隐藏子剪辑未等待带滤镜祖先缓存提交，显隐差分出现0；r3完整迟到trace另保存在 `native-r3/flashlog-late.txt`。
- r4 44/48、r5 48/52：站姿通过；行走原生handler重新播放腿动画并驱动man位移，异相位stable/restore差分失败。r6以真实周期同相位对照解决取样污染，未删除姿态、改映射、放宽零差分或枪差分大于20的判据。
