# 军阀 vNext Slice 3 单一真人验收单

状态：`SLICE_3_1_DISTANCE_MACHINE_VERIFIED / candidate_executed / HUMAN_SLICE_3_DISTANCE_ACCEPTANCE_PASSED / NOT_DEPLOYED`。

2026-09-01 维护者完成自然游玩并确认“玩法有效”。这项真人结论覆盖 180/360/650 三档距离投入后的整体玩法有效性，也覆盖此前已确认的编组、排版和 Formation 实际投影；不外推为 Slice 4～6、Demo 2 大地图或正式部署验收。后续不再要求重复游玩 Demo 1，下一次真人玩法验收统一后移至 Slice 6 的四阵营大地图候选。

这是 Slice 0～3 已关闭的人类验收记录。维护者已经确认编组可用、排版调整有效、五阵型会改变 AS2 实际出生形状、距离功能跑通且整体玩法有效；这些结论不要求重复刷局。突击兵、弹药兵与狙击兵的长期平衡仍可在后续大地图自然游玩中继续观察，但不再阻塞 Slice 4～6 机器施工。

## 候选绑定

只启动下面的隔离 candidate，不使用正式根 EXE，也不把本候选称为已部署：

```text
candidate_exe=tmp/runtime-candidates/v2/warlord-s3-range-r2-0901/CRAZYFLASHER7MercenaryEmpire.exe
candidateBootstrapSha256=55EABB5C3280FDFEE8302843D969C6B6354808F1AF4DC24DB5E2397AA80499D8
candidateCoreSha256=4CCB701103D5AFA1AC6AA7F57989938820708E3EFBD60554CBD0B3E1C69F2E1C
buildIdentity=B00A72E44111A5B40BB2937F11471CE2DF614A0CFCC99B08667BC6D31F0A55CC
payloadClosure=5310297410C83DB903F63C6DF542A536B70822E3501856B5B2B90FE256D9F81B
webRuntimeManifestSha256=F8546167436EB0F7BDC2D0FFFC58B4B0008DA2AD9F6D58301EB362468D0DDCC3
asLoaderSwfSha256=5C9E9FE639403C906E2CFA0FD96C3EC884C65DE08BB2164841971AA8DFAD5A87
organizationConfigDigest=sha256:8A0DB331DD938022CF624DE57B84A64DAADF7A46469E899613FE2B63A437F28A
encounterConfigDigest=sha256:6D94E0ABCA11BE5AE1574219D30E4E8E1E3890293496FB2192E081AB24DFE29E
```

候选已由自身 bootstrap 通过 `--verify-runtime-only`，闭合 `integrity-only / 33 files`；随后从精确 Core 路径启动 Guardian、Flash Player 和 WebView2 运行时，状态为 `candidate_executed / NOT_DEPLOYED`。自动窗口控制桥当前不可用，现役安全控制面的 `panel.open` 白名单也不包含 `warlord`，因此没有绕过权限强开面板。维护者当时通过现役测试入口完成玩法感知；该入口尚未走 GameStage，因此 Slice 3 结论不能代签普通选关或 GameStage 产品旅程。native 身份与 closure、Web runtime manifest、Encounter digest 和 fresh `asLoader.swf` 分开绑定；任一值不符就停止。正式 Core、正式 runtime 与部署状态均未改变。

上一版距离候选曾收集到 4 次 `R-Economy → R-HQ` 战斗请求，目标均精确为当时的 `near/360`，4 次 AS2 回包均为 `success=true / status=finished`；维护者也确认距离功能链跑通。该证据只证明功能链，不证明数值合适：维护者随后判定 360 仍未达到短兵相接，因此旧“近”已上调为 `medium/360`，新 `near/180` 尚待本次自然游玩判断。

旧 `warlord-slice3-0901` 固定保留“版面不足、阵型未投影”的失败证据；旧 `warlord-slice3-r2-0901` 固定保留“排版和阵型有效、固定远距离导致兵种就业单一”的诊断证据；旧 `warlord-slice3-distance-0901` 固定保留“距离功能链有效、360 近档仍过远”的调优证据。三者都不再是验收目标。

## 一次自然游玩

维护者当时从现役 `其他 → 测试 → 军阀演习测试` 直接入口进入“军阀战术演习”，按自己的方式完成自然游玩，没有为测试强行重复阵型或重开战斗。该历史步骤只记录玩法感知；Slice 6 新增的测试专用 Stage Select 才用于验证真实 GameStage 进入链。旅程中自然经过以下三类目标：

1. 中央三节点在据点摘要显示“接敌：远”，双方补给/经济显示“接敌：中”，两个总部显示“接敌：近”；进攻预览保留完整战术说明，档位说法应一致，不再另占一行编组空间。
2. 观察动作战斗的实际接敌时机是否随目标从远 `650` → 中 `360` → 近 `180` 明显缩短。若自然方便，可尽量沿用相同阵型或相近编组比较，但不为造对照局打断正常游玩。
3. 重点判断中、近距离下突击兵能否在战斗结束前稳定接敌，弹药兵能否获得有意义的持续供弹/作战时间；同时留意近距离是否贴得过近、远中近差异是否过小。
4. 若自然打到终局，顺带确认每次 AS2 战斗返回同一战略会话、最终只结算和返回一次。没有自然走到终局就记“未观察”，不需要额外刷局。

排版、编组、拆分和五阵型坐标已各自由真人或机器覆盖；只有在自然游玩中再次出问题时才记录，不单独复验。手工关闭、恢复按钮和故障重试也不是本次必测项。

## 最短回报

不填写 receipt 或长表，直接说第一处真实问题即可。没有阻断时，一句话回答：

```text
远/中/近差异是否明显；突击兵是否开始有用；弹药兵是否开始有用；近距离是否过近。
```

全部主观判断通过后，当前工作树才能提升为 `HUMAN_SLICE_3_DISTANCE_ACCEPTANCE_PASSED`；它仍然是 `NOT_DEPLOYED`，也不代签 Slice 4～7、EncounterBudget、完整逐成员 DeploymentPlan、Demo 2 大地图或正式入口发布。
