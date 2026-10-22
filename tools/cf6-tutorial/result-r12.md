# CF6 教学室修复 — result-r12（freeze）

日期：2026-10-21。范围：仅 `tools/cf6-tutorial/`、`flashswf/backgrounds/cf6/CF6_Tutorial_BG/`、`tools/cf6-map-runtime/build-tutorial.py`；测试临时文件仅 `tmp/cf6-roguelike-20261021/validation/tutorial-cache-r12/`（全部保留不清理）。

## 历史结论

- **r10 审核失败（root 拒绝）**：所谓"闭包零位图/CLEAN"不成立——审计用了错误 tag（`DOMBitmapFill`），实际 7 处 `BitmapFill/bitmapPath` 引用 5 张纹理，而新 XFL 无 media/LIBRARY 图片/bin；对白首条照抄旧 J/K/空格按键；provenance 未绑生成器依赖。r10 原件（代码/XFL/manifest/result）逐 SHA 归档在 `archive/r10-before-texture-fix/`（45 文件，本轮开改前已全量校验通过），原报告保持原貌不覆盖。
- **r11 监督停止**：主控在零 pending 工具、无活动子命令时停止（非额度耗尽）；期间发生过错误相对归档路径写到仓库外的事故。r11 仅在 assemble.py 留下未接线常量/注释，本轮已拆除。
- **r12 修复**：按 root 已证明的 native-cache-only 路线（探针 `tmp/cf6-roguelike-20261021/validation/tutorial-cache-probe-r1/`：真实 CS6 Compiler 0/0，SWF SHA `5cf7a9648b2e4ede4c2094f51c80ee739fa7b01784ecffa66d2d1048bbb19828`，JPEXS 读编译产物 5 纹理完整并目视确认）把媒体闭包装回教学源。

## 本轮修改

1. `assemble.py` 遍历正确 tag（`BitmapFill/bitmapPath`、`DOMBitmapInstance/libraryItemName`）收集闭包实际媒体依赖；复制原库 `DOMBitmapItem`（保留 name/href/bitmapDataHRef/framebounds/压缩字段，删除失效 `sourceExternalFilepath`）入新 DOMDocument.media，对应 bin 缓存逐字复制。provenance 每项显式 `mediaSourceKind='native-cache-only-existing-xfl'`、`originalHrefPresent=false`、source+cacheSHA/大小、输出 binSHA/大小；`bitmapBytes=0` 结论已移除。未改全局 `native_xfl.py`，未放宽其他项目规则。
2. 审计：引用==声明==钉板三者精确闭合；缓存存在/非空/裸文件名（路径在自身 bin 内）/SHA 与钉板一致；缺缓存、字节被改、未声明引用均拒绝；href 缺失只接受钉板内且原库同条 DOMBitmapItem 本就不存在 href 文件的 5 项，不笼统忽略 missing。源 33 元件不变（逐 SHA 与 r10 归档一致）。原生缓存是已有数据，本工具不制作 .dat。
3. `layout.json` 第一条对白改为"先确认移动、切换武器、射击和换弹的操作。按键沿用你当前的设置，可在设置里查看。"（当前默认 R 换弹；旧 K/空格提示不进成品）。无敌教学、无重复发枪、A01 首战保留。
4. `provenance.sources` 增加 assemble.py、build-tutorial.py、`tools/rhino-map-assets/build.py`、`tools/asset-metrology/xfl_geometry.py`、`tools/cf6-map-runtime/geometry.py`（geometry.py 无仓内依赖；xfl_geometry 仅 stdlib；rhino build.py 直接依赖 xfl_geometry——有限依赖已核），加 5 缓存与原库 DOMDocument。`pendingIntegration` 只列真实 CS6/视觉/实机项；BookDefinition 白名单 root 已 579/579 通过、root 装配器已接两个 fragment、runtime-index 20 图集合不变，均记入 `integratedByRoot`。
5. README 媒体说明已修正为 5 纹理 native-cache 闭合；r10 报告原样保留。

## 验证（本轮实际执行）

- `assemble.py`（重装）：`{"built": "ok", "outputs": 45, "librarySymbols": 34, "bitmaps": 5, "bitmapBytes": 28869, "freeGridCells": 7767, "reachableCells": 7767, "collisions": 14, "exit": {"direction": "右", "rect": [940, 425, 990, 445]}}`
- `assemble.py --check`：同上 `check: ok`（含 r9/r10 归档完好校验）。
- `build-tutorial.py --check`：同上 `check: ok`。
- 负例（隔离临时副本，全部保留）：`tutorial-cache-r12/negative-results.json` → `allRejected: true`
  - `case-missing-cache/`（新目录从一开始少复制 M 6）→ 拒绝："源原生缓存缺失"
  - `case-tampered-cache/`（副本内 M 6 翻转 1 字节）→ 拒绝："源原生缓存与钉板不一致"
  - `case-undeclared-ref/`（内存注入 `BitmapFill image/bitmap9999.jpg`，篡改件落盘留证）→ 拒绝："未声明的位图引用"；正例对照真实源接受。

## 关键 SHA-256（全量 55 项见 `tutorial-cache-r12/freeze-shas.json`）

输入（钉值，与探针 inputs.json 一致）：

- 原库 DOM `flashswf/levels/基地场景合集/DOMDocument.xml` = `16b3870ec1d12d7244d9b661a9836b5d6f90719b360423e1f05c9b5a676a86fd`（186,968 B）
- `bin/M 6 1736924415.dat` = `744350422af43c01d69336cb74711982697c0cd5638415f6b64c796fda8f5471`（18,486 B，bitmap2252.jpg）
- `bin/M 5 1736924415.dat` = `ec588f8252952296b3b833d752788adc12c9a04903403011a6e919d6b527ddb7`（1,932 B，bitmap2255.jpg）
- `bin/M 4 1736924415.dat` = `19eee04b09e08c97ed65e9500d90731701c6c2c5dccafc81a35e2db397ee91ef`（1,754 B，bitmap2259.jpg）
- `bin/M 3 1736924415.dat` = `bc66b70bd4c3de8ccd054f815d6394f068af65382381b862e92510294ed03959`（3,090 B，bitmap2261.png）
- `bin/M 2 1736924415.dat` = `55ee411f10aab46351f23d4abbba9c95f82701954fae52a0e1cf51608f48fc59`（3,607 B，bitmap2321.png）
- 媒体缓存合计 **28,869 B**；产物 bin 与源逐 SHA 相同（逐字复制）。

产物（主要）：

- `CF6_Tutorial_BG/DOMDocument.xml` = `5f45cb34ff091c5b80c81d426ca0dfe2ee3ab0c671d772a3bc98ba5ee8cfdbe4`（6,760 B，含 5 个 DOMBitmapItem，无 sourceExternalFilepath）
- `tools/cf6-tutorial/provenance.json` = `7c796f0f5f2a13a7c1f14100978a3a5599a588cf17f05b873585a2269c419072`
- `tools/cf6-tutorial/tutorial-map.fragment.json` = `8524116e1be310261d246d6c8ea1895a610e706e624f1451b5d9554b4c14b3ec`（新对白）
- `tools/cf6-tutorial/environment.fragment.xml` = `626115e1f6459f640fc44d26d4fe64e859e8c666b8876c1aa0d36d3dff175883`（未变）
- `tools/cf6-tutorial/assemble.py` = `607aad96185161f1524562c2fa7e1becf38cb341e8c77f896e51494d692bef46`
- `tools/cf6-tutorial/layout.json` = `05e1fdc4ac49492ce22c906707e89f0d54e5f43870c4a9f4fe488301329dd9cf`
- `tools/cf6-map-runtime/build-tutorial.py` = `25a60606cc1d6bfa09adfe075b2639d1608bf4a6dcb139da51405bd3603a8fba`（未变）

## 待 root 编译状态

**candidate_built，未编译。** 本线不调 CS6、不生成 SWF（`CF6_Tutorial_BG.swf` 不存在为断言项）。待 root：

1. 真实 CS6 编译：`scripts/compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_Tutorial_BG/CF6_Tutorial_BG.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_Tutorial_BG.swf'`
2. 编译产物 5 纹理视觉检查（探针同装配已 0/0 + 目视通过）。
3. 实机：角色体量/行走带/门口、空波次清关开出口、撤退回包。
