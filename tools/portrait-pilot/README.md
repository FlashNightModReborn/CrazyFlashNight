# 怪物头像代表集与特征精修 Pilot

本目录只负责隔离的 `consumer inventory → FFDec → 候选帧 → Luna A/B → 确定性渲染 → Edge 人工审阅 → 人工反馈约束的语义特征精修`，以及 duplicate/conflict 的独立人工选源队列。它不写正式头像目录、production manifest、consumer resolver、敌人/战宠协议或 Flash 资产。

跨批次复用时以 [`怪物头像生产管线：可复用运行手册`](../../docs/怪物头像生产管线-可复用运行手册-2026-08-09.md) 为规范入口；本 README 保留具体脚本、命令和批次实现细节，长篇决策证据与失败经过继续归档在 [`路线评估备忘`](../../docs/怪物头像统一资产与Luna-CLI-Worker路线评估备忘-2026-08-05.md)，三者不得互相冒充当前生产状态。

## 已冻结边界

- 审核键：`portraitRef + variantKey`。
- 代表集：14 个 identity / 15 个审核单元，其中 12 个可解析、3 个来源阻断。
- 来源分类：`unique` 才能自动导出；`duplicate/conflict/missing` 默认进入异常队列。duplicate/conflict 由 [`prepare_source_choices.py`](prepare_source_choices.py) 为每条来源生成稳定 `sourceCandidateKey`，可定位项仍优先渲染内部 `man`，再由独立 Edge 页面人工选择；选中后仍产出同一 `portraitRef + default`。只有存在明确运行时状态选择器时才升级为正式 `variantKey`。无 symbolName 的 orphan 只允许转人工维护，missing 保持阻断。
- 渲染目标：从 linkage 根首帧解析命名实例 `man`，直接导出该内部 Sprite；找不到唯一 `man` 时显式回退并记录警告，不静默猜测。
- 武装 JK：`man` 时间线同时包含 orange / white 可见帧，A/B 负责视觉提案，人工负责最终变体确认。旧图对应关系为 `pet_78.png=white`、`pet_78_1.png=orange`。
- 首轮模型只选择白名单 frame、focal point 与 crop；PNG/WebP 像素由 Pillow 确定性派生。
- 特征精修不再把“主体几何中心”当头像焦点：人形默认锁定头、脸、发型和必要肩颈；非人单位必须推理身份特征，可选择单一特征、多特征组合或完整轮廓。最长肢体、尾巴、武器和特效不能仅因面积大而成为焦点。
- 当模型连续误解一条明确人工构图要求时，允许在 [`fixtures/feature-refinement.v1.json`](fixtures/feature-refinement.v1.json) 的 `reviewKeyOverrides` 按稳定 `reviewKey` 人工维护 `requiredFeatureRegion` / `requiredMustIncludeRegion`。两个区域使用候选 PNG 的归一化 `0..1` 坐标；模型输出阶段与高分辨率渲染阶段都必须证明相应方框完整包含它们。该机制只约束构图锚点，不补画像素、不绕过人审，也不能把来源冲突伪装成视觉裁切问题。
- 特征精修模型看到带 `0..1` 坐标网格的候选图，只输出白名单 frame、`featureBox`、`mustIncludeBox` 和构图模式。FFDec `sprite:svg` 只绑定画布和坐标，不作为最终像素：JK 诊断证明 SVG 会漏掉帧级颜色变换。最终像素由 [`SelectedSpriteFrameExporter.java`](SelectedSpriteFrameExporter.java) 调 FFDec `FrameExporter` API，只导出所选 `man` 精确帧的自适应高倍 PNG；renderer 保留不超过 4096 的最大真实裁切母版，再用 Lanczos 向下派生 512/80/48/32，禁止放大首轮候选。
- 每个高倍帧必须先回缩到绑定候选并通过预乘 alpha RGBA MAE 门；透明 GIF 调色板残留 RGB 不计，真实颜色、半透明边缘和轮廓仍计。若二值透明 GIF 无法表示精确选帧 PNG 的源半透明，只有 [`render-feature-fidelity-v2.py`](render-feature-fidelity-v2.py) 中逐 `reviewKey + candidateId + frame + role` 冻结的身份才可改用 alpha≥128 实体核心 IoU 与归一化重心距离双门；报告必须保留真实超限 MAE，禁止提高全局阈值或把例外外推到其他身份。渲染失败自动使用新的 `vN` 目录，禁止覆盖前一尝试证据。
- 人工决定不直接改生产资产；后续 promotion 必须是单独 phase。

## 已回收的人工结论

P2 的 15/15 行已完整导出并经 [`verify-review-decisions.js`](verify-review-decisions.js) 验证：12 个可解析对象全部为 `adjustment`，3 个来源阻断对象全部为 `source`，因此状态是 `human_reviewed_refinement_required`，不是艺术通过。冻结回执位于 `tmp/portrait-pilot/p2-batched-final-20260805T150000Z/human-review-receipt.json`，receipt digest 为 `CC27338E9E659A2BF0C6BFCF21F1C92951E6E727DD13FF532D2F405C5D66AAC5`。

这轮反馈冻结了两项必须修正的问题：头像必须抓住可辨识的角色特征并给特写；最终像素必须从 Flash 精确选帧高分辨率重渲染，不能依赖清晰度低于素材资产截图的候选图，也不能把仅适合几何映射的 SVG 当成像素真源。

P3 r7 的 15/15 行也已冻结：10 个 `pass`、R06/R08 两个 `adjustment`、3 个 `source`，receipt digest `6AF3DE119BD3010EF09368ED8743AB47C4680852CABED26C4E40CF02A9CEEDE6`。当前 decision schema 中 `pass` 的明确语义是“接受 Luna A proposal”；Luna B 只作独立审计，不是隐式二选一。选择性精修只重跑非通过 eligible 行，已通过项和来源阻断项通过父 receipt 继承，不重复消耗模型配额。

选择性 r8 的 2/2 决定已冻结：R08 `pass`、R06 `adjustment`，decision SHA-256 `C2817F53E581C193D0302356375688D7E090FBF09899A8380679AE185FE8002D`，receipt digest `E1E5DA72167F95B0D445E26AA8E008D710DDD598C6266A5D8D033654D42CD663`。R06 备注要求沿用 Luna B 的低分辨率尺度倾向，但继续平移并完整保留三颗机械头。r9 暴露出仅靠自然语言仍会漏掉最右头，因此没有送人重复审阅；r10 改为上述身份级几何锚点双重门控。

r10 的单项决定也已冻结为 `adjustment`：维护者确认 Luna B 构图更好，但希望适当放大；decision SHA-256 `B6776E9D8B3679CB36AFD7E46CA2566061EBEED0F58939FCCBF0596B15ACF71B`，receipt digest `37DD19F1646989B884B363DAB240DDD6EC3D1D76FAF0E1D2633674DCDE2564CD`。该案例不再进入 Luna r11：改由人工选择 A/B 帧、直接框选像素正方形并查看绑定高分辨率帧的实时 80px 预览。

r11 的真实框选已冻结：维护者选择 Luna B `e05-c01/f1` 并收紧到三颗机械头，guidance receipt digest `8CE26419A92D6D8F6E5CB653C0FB8163AD7A9FD7C870C893464D6CC598F59D5B`。r12 直接消费约 `2169×2169` 个真实来源像素，无放大、无模型重跑，派生 512/80/48/32 PNG 与 80px lossless WebP；最大预乘 RGBA MAE `2.2229`，render report digest `AE71414F6490534AFBAE25740CA9476D667566B3CD87859BEE2A8A4B690AF82A`。

## 执行顺序

以下 `<batch>` 必须是 `tmp/portrait-pilot/` 下的新目录；所有证据文件都拒绝覆盖。

```powershell
python tools/portrait-pilot/prepare_pilot.py prepare --output <batch>

node tools/portrait-pilot/run-visual-pilot.js `
  --manifest <batch>/candidate-manifest.json `
  --codex-exe <显式绝对路径> `
  --timeout-ms 600000 `
  --max-concurrency 6 `
  --service-tier standard

python tools/portrait-pilot/prepare_pilot.py render `
  --manifest <batch>/candidate-manifest.json `
  --model-report <batch>/model-report.json

node tools/portrait-pilot/build-review.js --batch <batch>
node tools/portrait-pilot/build-review.js --batch <batch> --check
node tools/portrait-pilot/test-review.js --batch <batch>
node tools/portrait-pilot/open-review.js --batch <batch> --check
node tools/portrait-pilot/open-review.js --batch <batch>
```

模型输入每 1–4 个审核单元拆一个小批次。A/B 使用不同角色提示和不同 PID；controller 用全局有界队列运行分片，不设批次栅栏，只在所有审核键和 artifact 闭包成立后写 `model-report.json`。`--max-concurrency` 范围 1–12；代表集已实测 Standard 6 路无 429，选择性 r8 又以 Fast 跑通两个独立进程。`--service-tier fast` 会把 `service_tier="fast"` 与 `features.fast_mode=true` 传给忽略用户配置的 CLI；并发与 Fast 收益仍须分开记录。

首轮人审要求精修后，从冻结 P2 批次创建一个全新目录，不能覆盖原批次：

```powershell
python tools/portrait-pilot/prepare_pilot.py refine `
  --source-batch <已验证 human-review-receipt 的 P2/P3 batch> `
  --output <fresh-feature-batch> `
  --batch-id <fresh-ascii-batch-id>

node tools/portrait-pilot/run-visual-pilot.js `
  --manifest <fresh-feature-batch>/candidate-manifest.json `
  --codex-exe <显式绝对路径> `
  --timeout-ms 600000 `
  --max-concurrency 6 `
  --service-tier fast

python tools/portrait-pilot/prepare_pilot.py render `
  --manifest <fresh-feature-batch>/candidate-manifest.json `
  --model-report <fresh-feature-batch>/model-report.json

node tools/portrait-pilot/build-review.js --batch <fresh-feature-batch>
node tools/portrait-pilot/build-review.js --batch <fresh-feature-batch> --check
node tools/portrait-pilot/test-review.js --batch <fresh-feature-batch>
node tools/portrait-pilot/open-review.js --batch <fresh-feature-batch> --check
node tools/portrait-pilot/open-review.js --batch <fresh-feature-batch>
```

`refine` 会验证并绑定父 manifest、review-data、完整 decisions 和人工回执；只把 `adjustment` 行写入新 manifest。`pass` 作为父链已通过项继承，`source` 保持异常队列，其他失败状态须转对应来源/姿态队列，禁止混进语义裁切重试。每次模型运行仍是独立 PID / prompt / artifact 闭包；格式、占比或人工维护区域遗漏最多三次有界尝试，后续尝试会收到精确 controller 反馈。`reviewKeyOverrides` 会连同 profile hash 进入 source closure；A/B 分歧原样进入 reviewer。

若 `adjustment` 已经明确到“选 A/B 中哪一帧，以及如何移动/缩放”，不要再消耗模型轮次。从冻结人审批次建立全新人工框选批：

```powershell
node tools/portrait-pilot/build-framing-guidance.js `
  --source-batch <已验证 human-review-receipt 的 P3 batch> `
  --output <fresh-guidance-batch> `
  --batch-id <fresh-ascii-batch-id>

node tools/portrait-pilot/build-framing-guidance.js `
  --output <fresh-guidance-batch> `
  --batch-id <fresh-ascii-batch-id> `
  --check
node tools/portrait-pilot/test-framing-guidance.js --batch <fresh-guidance-batch>
node tools/portrait-pilot/open-framing-guidance.js --batch <fresh-guidance-batch> --check
node tools/portrait-pilot/open-framing-guidance.js --batch <fresh-guidance-batch>
```

页面只列父回执中的 `adjustment` 行。人类必须显式选 `proposal / independent_review`，在完整候选上拖动或缩放像素正方形；允许最多半幅归一化透明越界。右侧 256/80px 实时预览直接读取该选择所绑定的 FFDec 高分辨率精确帧，不是放大低清候选。候选 hash、最小 1024 真实来源像素、可见面积、正方形、逐项确认、digest 隔离和重复保存均 fail-closed。

导出后冻结框选回执，并直接确定性重渲染；这里不再调用 Luna：

```powershell
node tools/portrait-pilot/verify-framing-guidance.js --batch <fresh-guidance-batch>
node tools/portrait-pilot/verify-framing-guidance.js --batch <fresh-guidance-batch> --check

python tools/portrait-pilot/render-framing-guidance.py render `
  --guidance-batch <fresh-guidance-batch> `
  --output <fresh-render-batch> `
  --batch-id <fresh-ascii-batch-id>
python tools/portrait-pilot/render-framing-guidance.py check --output <fresh-render-batch>
```

`render-framing-guidance.py` 复用已绑定的 `sourceHighResolution`，重新执行候选回缩预乘 RGBA MAE、像素正方形、透明越界、最小真实来源裁切与 4096 上限，再派生 512/80/48/32 PNG 和 80px lossless WebP。自动 E2E 已证明“框选导出 → 回执 → 直接高分辨率渲染”闭合且 `modelRerun=false`。

若人工框选所绑定的精确 PNG 超过 Pillow 默认像素阈值，但仍位于 manifest 的 `maximumSourceFrameDimension²` 内，使用版本化 [`render-framing-guidance-large-frame-v1.py`](render-framing-guidance-large-frame-v1.py)；若同一行还实际命中已证明的 GIF 二值 alpha 表示差，改用 [`render-framing-guidance-large-frame-fidelity-v1.py`](render-framing-guidance-large-frame-fidelity-v1.py)。两者都必须 `render/check`，只允许 manifest 有界解码；后者还须精确绑定身份、角色、候选和 frame，不能提高全局 MAE。

若冻结的 `source` 人审项后来被维护者确认与另一已通过人工框选的身份是同一单位换皮，可用 [`freeze-portrait-alias-decision.js`](freeze-portrait-alias-decision.js) 绑定来源人审、目标框选/渲染和最终产物，生成非生产 `portrait-alias-receipt.json`。该回执只授权未来 consumer `portraitRef` 映射，不会写 XML，也不能顺带吞并未被人类点名的来源异常。

真实结果位于 `tmp/portrait-pilot/p3-human-guided-r12-20260806T025309Z`。代表集汇总 `tmp/portrait-pilot/representative-closure-r13-20260806T031054Z/representative-closure.json` 已闭合 12/12 eligible，保留 3 个来源阻断，report digest `7B552BD531A775A80669365E8737357807824E9A9D0A87E48C59681ACD814639`。r7 Standard 并发 6、r8/r10 Fast 与零模型人工框选不是同输入基准，不外推严格 Fast 倍率。

duplicate/conflict 选源使用单独批次，不调用 Luna：

```powershell
python tools/portrait-pilot/prepare_source_choices.py prepare `
  --output <fresh-source-choice-batch> `
  --batch-id <fresh-ascii-batch-id>
python tools/portrait-pilot/prepare_source_choices.py check --output <fresh-source-choice-batch>
node tools/portrait-pilot/test-source-choice.js --batch <fresh-source-choice-batch>
node tools/portrait-pilot/open-source-choice.js --batch <fresh-source-choice-batch> --check
node tools/portrait-pilot/open-source-choice.js --batch <fresh-source-choice-batch>
```

当前真实选源批 `tmp/portrait-pilot/source-choice-r1-20260806T030347Z` 覆盖 1 duplicate + 2 conflict、3 个身份 / 6 个来源：5 个来源精确命中首帧内部 `man`，唐头肌肉男的无名 orphan 明确为 1 个 manual-only 来源。manifest digest `87DB71EF09AB659FCA7491C4E6EF96ECE45527B5125C0FABACDAD19AB803FA64`。页面必须逐身份选择一个可渲染来源，或填写原因转人工维护；导出后运行：

```powershell
node tools/portrait-pilot/verify-source-choice-decisions.js --batch <source-choice-batch>
node tools/portrait-pilot/verify-source-choice-decisions.js --batch <source-choice-batch> --check
```

选源决定、回执与后续生成仍保持 `variantKey=default`。`selected` 必须精确绑定可渲染 `sourceCandidateKey`；`manual_maintenance` 必须不绑定来源并写备注。stale digest、选用不可定位 orphan、漏项、重复并发保存和浏览器下载旁路均由 verifier/Edge 测试拒绝。

## 全量 campaign 的有界 shard

选源回执 `FE00136CF1589649DF327AAACDB1CFAA5654D577057FD8ECD9BC93D48E78B803` 已冻结 3/3 `selected`、0 `manual_maintenance`。全量入口先冻结 enemy + pet consumer 并集，再准备小 shard；禁止把当前统计写死成长期发布常量：

```powershell
python tools/portrait-pilot/prepare_campaign.py inventory `
  --output <fresh-inventory-batch> `
  --batch-id <fresh-ascii-batch-id> `
  --source-choice-batch <verified-source-choice-batch> `
  --representative-closure <verified-representative-closure-batch>
python tools/portrait-pilot/prepare_campaign.py check-inventory `
  --inventory <fresh-inventory-batch>/portrait-inventory.json

python tools/portrait-pilot/prepare_campaign.py prepare-shard `
  --inventory <fresh-inventory-batch>/portrait-inventory.json `
  --output <fresh-campaign-shard> `
  --batch-id <fresh-ascii-batch-id> `
  --representative-closure <verified-representative-closure-batch> `
  --shard-size 12 `
  --source-groups 3
python tools/portrait-pilot/prepare_campaign.py check-shard `
  --manifest <fresh-campaign-shard>/candidate-manifest.json
```

默认 shard 是 3 个 source SWF × 每组 4 个身份，正好形成 3 个模型小批次 × A/B = 6 个独立作业。选择顺序固定为剩余身份数降序的 SWF、再按 `portraitRef`；后续批可重复传 `--exclude-manifest <prior-candidate-manifest.json>`，同时排除既有审核项与既有 `resolutionAnomalies`。代表集始终排除。campaign 对每个 linkage 根只接受首帧唯一命名 `man`；缺失、不唯一或漂移一律写异常记录，禁止回退根 MovieClip，因此外层血条、等级和名字不能进入模型候选。

campaign 使用独立 `fixtures/campaign-feature-inference.v*.json`。v5 绑定四轮 48 条原始人审标签、36 个真实框选、两类方向输出和累计几何统计；联系表下方的视觉对照只作 in-context 构图偏好，不是候选或模型训练。模型必须先在 `featureLabel` 中命名真正决定可识别度的重点，再画框：头是最常见主焦点；若头部辨识较弱，可把标志性武器结构、核心或身体特质作为受控复合焦点。80px 主焦点必须位于甜区并留足安全范围，低辨识度的次要肢体、武器末端或装饰必要时允许在顶边/侧边受控裁切。累计倍率只用于反证，不机械放大或缩小。高分辨率合同保持最小 1024 真源裁切和最多 4096 保留母版，并允许 FFDec 中间全帧最大 16384px；这是为大画布小特写保留真实像素，不是放大低清候选。

当前冻结 inventory 位于 `tmp/portrait-pilot/campaign-inventory-r2-20260806T035243Z/portrait-inventory.json`，digest `DC2637DCBAFA28D20091799D58E012CA20F6D2035DB7B090ECC159CC53E5A6FF`：215 条 enemy record 投影为 214 个 enemy identity，111 条 pet record 含 98 个非占位 Identifier，最终 union 221 个 identity / 222 个 review unit；211 unique + 3 人工选源 = 214 可解析，7 missing，0 待选源，0 人工维护。

有界首 shard 位于 `tmp/portrait-pilot/campaign-shard-r2-fast6-20260806T035300Z`：12 个全新身份全部精确渲染内部 `man`，2 个无命名 `man` 的火精灵被隔离；manifest/source/model/render/review digest 分别为 `C8848F60…EFC25 / 8E5E9056…446A / F3A75BD9…9CA2 / 0F09FE46…B03 / 17C1660F…49C3`。Fast 6 的墙钟为 443.8 秒，实际 8 个有界 attempts（2 个首输出被门控后用新 PID 修复），6 个最终作业全部接受，0 429、timeout、orphan、survivor；一条修复 attempt 有可恢复 TLS 重连。24 条高倍 A/B 渲染最大预乘 RGBA MAE `5.5505`，渲染容量最大需求约 14564px，低于 16384px。该结果支持继续以 Fast 6 收集人审通过率，不支持提高并发，也不证明艺术通过。

r2 与文字校准后的 r6 都由维护者冻结为 3/12 `pass`、9/12 `adjustment`；视觉校准后的 r16 为 4/12 `pass`、7/12 `adjustment`、1/12 `source`。r16 的 7 个框选又证明不能机械收紧：5 个框选放宽到原初框的约 `1/0.860708`，1 个因帽子完整性放宽到约 `1/0.637628`，1 个不变。累计 24 个真实框选的中位倍率为 `1.1665925×`、范围 `0.637628–2.345799×`。自适应扩容不限制单页行数，优先减少页面切换；只在 `候选下一批身份数 × 估计失败率 ≤ 6` 时翻倍，模型小批仍不超过 4 身份、Fast 全局并发上限仍为 6。当前 `24 × 0.666667 = 16.000008 > 6`，所以下一批仍保持 12 身份。

视觉校准批 `tmp/portrait-pilot/campaign-shard-r16-visualcal-fast6-20260806T055055Z` 通过 [`attach-feedback-atlas.py`](attach-feedback-atlas.py) 把前两轮 24 条标签做成 6 个 pass 锚点、17 个“模型初稿→人类框选”对照和 1 个朝向对照。其人审 receipt `A44E72EE…E7E1` 已冻结为 4 pass、7 adjustment、1 source；7 个框选的 receipt `692FDB37…E3CD` 与无模型高分辨率重渲染 `AEB72A4E…7605` 均已闭合。`拟态投影` 的 source 备注要求拒绝多人重叠帧、先选单人帧再只框完整头部，继续作为异常队列与后续模型负例，不冒充已解决的构图。

三轮视觉校准批 `tmp/portrait-pilot/campaign-shard-r22-v4-feedback-fast6-20260806T080559Z` 由 [`attach-feedback-atlas-v2.py`](attach-feedback-atlas-v2.py) 动态覆盖 36/36 条标签：10 个 pass 锚点、24 个真实框选、1 个朝向修正和 1 个 source 负例；manifest/source/atlas digest 为 `1334E2DD…0A9A / 4EBA8248…9ABE / B487DADD…4817`。Luna Max Fast 6 共 7 次尝试完成 6 个 A/B 作业，只有 batch-03 proposal 因特征占比过小受控修复一次；墙钟约 385 秒、最长单作业 344.5 秒，0 429/timeout/orphan，A/B 同候选 6/12。24 路高分辨率渲染全部直接通过 MAE≤8，最大 `5.9191`，无需半透明例外；model/render/review digest 为 `EDD0B99A…A88E / 6D0CC3C8…6809 / 6E47FD1E…29F`。维护者随后将 12/12 全部标为 adjustment，receipt `F0AF2B5B…5AB0`：3 项明确偏好 Luna B，多项继续要求头部特写/安全区，T800 还要求最终水平翻转。单页 guidance `campaign-guidance-r24-r22-all-adjustments-20260806T082340Z` 已冻结 receipt `6CE05FF6…7034`；12 个框选经无模型高分辨率直渲染形成 report `59895BCF…526F`，T800 再由 [`render-guided-orientation-adjustment.py`](render-guided-orientation-adjustment.py) 对人工框选母版执行精确水平翻转，report `6F2E167E…8FE`、镜像 MAE `0`。

四轮校准批 `tmp/portrait-pilot/campaign-shard-r29-v5-feedback-fast6-20260806T085057Z` 由 [`attach-feedback-atlas-v3.py`](attach-feedback-atlas-v3.py) 覆盖 48/48 条标签：10 pass、36 guided correction、1 orientation-only、1 source anomaly；T800 的 guided orientation 替换其 guided master 而不重复计标签。累计 feedback `6B258CAA…F48B` 的 36 个框选中位倍率 `1.349859×`、范围 `0.637628–4.474963×`；上一轮 0/12 通过使 `24 × 1 = 24 > 6`，因此本轮仍为 12 身份 / 3 source group / Fast 6。manifest/source/atlas digest 为 `6B18D88D…D9E7 / D42CB984…821F / 6AD5ECDA…E0A7`。Luna Max Fast 6 的 6 个 A/B 作业全部首次接受，墙钟约 `257.8s`、最长 `257.2s`，0 repair/429/timeout/orphan/survivor，A/B 同候选 4/12；model digest `32FAE269…DEB8`。24 路标准高分辨率渲染全由主 MAE 门通过，最大 `6.7576≤8`、render digest `0F3D266D…42C0`，不调用历史半透明例外。review digest `30488E36…0148` 已通过 Edge harness 与 open preflight；维护者随后冻结 2 pass、10 adjustment，receipt `15EE7AF1…8882`。10 个 adjustment 已在单页 `campaign-guidance-r31-r29-all-adjustments-20260806T091916Z` 完成，guidance/receipt/render digest 为 `47847745…C39 / 0A212268…835A / 00D0C11B…E558`；累计标签现为 12 pass、47 adjustment、1 source，46 个真实框选的中位倍率仍为 `1.349859×`、范围 `0.637628–4.474963×`。feedback `00BD6B05…A7CD` 以本轮失败率 `0.833333` 判定 `24 × 0.833333 = 19.999992 > 6`，所以下一 shard 仍推荐 12 身份。

五轮反馈批 `tmp/portrait-pilot/campaign-shard-r35-v6-feedback-fast6-20260806T093839Z` 使用 [`campaign-feature-inference.v6.json`](fixtures/campaign-feature-inference.v6.json) 与 [`attach-feedback-atlas-v3.py`](attach-feedback-atlas-v3.py) 覆盖 60/60 标签：12 pass、46 guided correction、1 orientation-only、1 source anomaly，atlas SHA `D4B94AB3…F616`；manifest/source digest 为 `30FFBB2F…9B93 / DC6A669EC9BD4DAC60B73CDED4B958BEAB7A198F7569973DEC93ECDF370F53A4`。v6 将第五轮的 3 项右侧空白、3 项顶部安全不足、头部特写不足、非人尾部抢焦及 2 项 B 偏好写入显式推理规则。Luna Max Fast 6 最终 6/6 接受，但共 10 次尝试、墙钟 `825.169s`：1 次值非法、2 次特征占比过小、1 次 timeout，0 orphan/survivor，A/B 同候选 6/12；model digest `2DE2F6B2…8167`。标准 renderer 先暴露 179,763,336px 精确帧超过 Pillow 默认硬阈值但仍低于 16384² 合同，[`render-feature-large-frame-fidelity-v1.py`](render-feature-large-frame-fidelity-v1.py) 随后将解码上限精确绑定为 16384²，并只允许方舟妖姬 proposal `e10-c03/f25` 使用逐角色二值 GIF alpha 表示例外；23/24 行通过主 MAE，该行真实 MAE `11.4235`、半透明占比 `0.131379`、核心 IoU `0.867360`、重心差 `0.008625`，render digest `255C5723…A8DF`。review digest `353F0C13…DEA2` 已通过 12 行/352 artifact 的 Edge harness 与 open preflight。维护者随后冻结 0 pass、12 adjustment，receipt `7CA7FF3A…23D2`；12 项在单页框选批 `tmp/portrait-pilot/campaign-guidance-r37-r35-all-adjustments-20260806T102030Z` 冻结，guidance/receipt/render digest 为 `F1C857C5…0A07 / C6301D7D…E86D / 14D48C31…807B`。方舟妖姬按更晚的人类选择保留 `e10-c03/f25`，4 项明确朝右要求经框选后翻转均为 MAE 0。累计 feedback `BC4D213E…70B0` 含 58 个真实框选；r35 失败率 1 令 `24 × 1 = 24 > 6`，下一 shard 不翻倍。

六轮反馈批 `tmp/portrait-pilot/campaign-shard-r42-v7-feedback-fast6-20260806T104026Z` 使用 [`campaign-feature-inference.v7.json`](fixtures/campaign-feature-inference.v7.json) 与 atlas v3 覆盖 72/72 标签：12 pass、58 guided correction、1 orientation-only、5 guided orientation、1 source anomaly，atlas SHA `6B5D2579…A6DE`；manifest/source digest 为 `8ADAB72B…4C17 / 3548E3BB…F539`。Fast 6 共 7 次尝试完成 6 个 A/B 作业，仅 1 次 `RESULT_FEATURE_TOO_SMALL` 修复，最长 `239.212s`，0 timeout/orphan/survivor，A/B 同候选 10/12；model digest `684BA9B8…CA79`。标准渲染对变异犬 proposal 以 MAE `9.1626` fail-closed；[`diagnose-feature-render-fidelity-v1.py`](diagnose-feature-render-fidelity-v1.py) 隔离诊断 24/24 行，证明只有 `敌人-变异犬/e06-c05/f64` 的 A/B 两路属于二值 GIF alpha 表示差，核心 IoU `0.969183`、重心差 `0.005252`。[`render-feature-large-frame-fidelity-v2.py`](render-feature-large-frame-fidelity-v2.py) 将例外精确绑定诊断摘要，22 路主门 + 2 路例外，render digest `9F64A19E…C179`。review digest `7EBCF7DC…AF00` 已通过 12 行/355 artifact Edge harness/open preflight；维护者随后冻结 2 pass、10 adjustment，receipt `E71AE9BE…235E`。10 项在单页 `campaign-guidance-r45-r42-all-adjustments-20260806T110457Z` 冻结，guidance/receipt/render digest 为 `96F6765B…675F / 9E47E1E9…AA34 / C8607A32…F4AE4`；变异犬使用 Luna B，其余 9 项使用 A。标准人工框选 renderer 只在该行复现 MAE `9.1626`，[`render-framing-guidance-large-frame-fidelity-v2.py`](render-framing-guidance-large-frame-fidelity-v2.py) 将例外精确绑定既有 24 路诊断；9 个 primary + 1 个例外，无模型重跑。累计 feedback `77432F24…770F` 现含 84 条标签、68 个真实框选；本轮首过率 2/12 令 `24 × 0.833333 = 19.999992 > 6`，下一 shard 仍为 12 身份 / 3 source group / Fast 6。

七轮数据首次生成的 v8 profile 同时设置 `mustIncludeSafeMargin=0.10` 与 head long-axis hard floor `0.86`，而包含关系决定任一轴的可实现上限只有 `1−2×0.10=0.80`。失败批 `campaign-shard-r49-v8-feedback-fast6-20260806T112708Z` 的 6 个角色共保留 18 个 rejected attempt、0 accepted job，最终 `RUN_RETRIES_EXHAUSTED`，没有 model report，也未进入渲染或人审。[`test-feature-profile-feasibility.py`](test-feature-profile-feasibility.py) 与 campaign profile validator 现固定拒绝此类不可实现合同；v9 保留 10% 安全区，把 hard floor 调回可实现范围，并在 repair feedback 写明 `mustIncludeBox` 必须是外框的精确不等式。

`tmp/portrait-pilot/campaign-shard-r52-v9-feedback-fast6-20260806T115116Z` 重新覆盖同一 12 个身份，atlas 完整绑定当时 84/84 人类标签；manifest/source digest 为 `54580B47…96BD / 59DEA70A…E4EE`。Luna Max Fast 6 用 13 次 attempt 完成 6 个作业：5 次 `RESULT_FEATURE_TOO_SMALL`、2 次 300 秒 timeout，0 orphan/survivor，A/B 同候选 7/12、12/12 高亮人审，model report digest `A947A9BA…D06F`。标准 renderer 因 225,442,672px 精确帧触发 Pillow 硬阈值；有界 [`render-feature-large-frame-v1.py`](render-feature-large-frame-v1.py) 随后完成 24/24 primary MAE，最大 `6.2292≤8`、render digest `B8B89800…03A5`，无需 alpha 例外。review digest `BC62C754…27D4` 已通过 12 行/349 artifact Edge harness/open preflight；维护者随后冻结 2 pass、10 adjustment，receipt `78A15343…B97`。失败备注高度集中于未锁定头部或未把头放进视觉甜区，只有蓝色铁血战士与铁血小飞机直接通过。10 项 adjustment 已在单页 `campaign-guidance-r53-r52-all-adjustments-20260806T122503Z` 完成，guidance/receipt/render digest 为 `F4CAA48E…0A79 / 2800BCBC…615C / 767F6A20…197C`；累计 feedback `4210F393…6FC` 现闭合 96 条标签、78 个真实框选、1 个 orientation-only 与 5 个 guided orientation。

完整 96 标签 atlas 与当前候选分成两张附件后，v10/r57、v11/r59 仍暴露超长视觉上下文与严格几何门的组合问题：r59 的 full-atlas 单次布局为 16,992 个 32×32 patch，两次 300 秒 timeout 后虽正确识别盗贼枪手的红发、圆形护目镜和呼吸面罩，仍因短轴 `0.518136<0.54` 被拒绝，没有生成 model report，也没有进入人审。v12 只把 `head_closeup` 短轴门降到 `0.50`；[`derive-compact-model-atlas-v1.py`](derive-compact-model-atlas-v1.py) 同时保留完整 raw receipt/full atlas/source closure，把每次发送的偏好图确定性压到全部 16 pass、最新 10 adjustment、全部 1 anomaly 与全量统计。偏好图 patch 从 `14,691` 降到 `4,720`（`−67.8715%`），当前候选仍是独立的 1,885×1,228 附件，不裁碎单个角色。

`tmp/portrait-pilot/campaign-shard-r62-v12-feedback-retrieved-fast6-20260806T133249Z` 的 manifest/source/model/render/review digest 为 `F52067D2…47B0 / 9ED1651C…6241 / 64B896A5…DE67 / 763FD489…14E7 / 6483A638…4974`。Luna Max Fast 6 在 `771.745s` 内以 12 次 attempt 闭合 6/6 作业：4 次 `RESULT_FEATURE_TOO_SMALL`、2 次 300 秒 timeout，0 orphan/survivor，A/B 同候选 6/12、9/12 高亮人审；标准 4096px renderer 直接完成 24/24 主 MAE，最大 `5.4067≤8`，无需 fidelity 例外。12 行/352 artifact 的 build/check/Edge harness/open preflight 全部通过，维护者随后冻结 3 pass、9 adjustment、0 source，receipt `A2A99F57…A4BE5`。9 项均可在已有 A/B 帧上处理：7 项要求进一步放大头部，黑铁武士收回右侧空白，黑铁精英流锤兵补顶部安全区；因此不重复调用 Luna。单页 `campaign-guidance-r63-r62-all-adjustments-20260806T135712Z` 已通过 9 行/123 artifact build/check/Edge harness/open preflight，guidance digest `26C093C5…BB720`、真实 Edge marker `2026-08-06T13:57:59.600Z`。严格状态是 `human_reviewed_refinement_required / HUMAN_FRAMING_GUIDANCE_PENDING / productionReady=false`；完整框选回执前不得准备下一 shard 或 promotion。

r63 在机器重启前后的导出已证明持久化：9/9 框选回执 digest `D02908F2…2B4`，r64 无模型高分辨率 render digest `D6B91445…DFF8`；r65 累计反馈 `007E0CBF…B6D0` 现闭合 108 条真人决定与 87 个真实框选。离线回放器 [`evaluate-human-alignment.js`](evaluate-human-alignment.js) 对冻结 r62 开发集做同输入评分：旧单阶段 proposal 仅 3/12 接近真人目标；锁定候选后使用逐行 2048px 原生高分辨率网格图的 r70 达到 7/12，median zoom correction `1.002463`、mean center distance `0.113354`、mean crop IoU `0.663848`。该结果只属于开发集，不替代新身份人审。

v13 因而冻结“两阶段、真人目标坐标隔离”的执行合同：第一阶段只在当前候选 + 由完整 108 标签闭包确定性检索出的 29 个偏好示例上选帧；[`build-selection-lock.js`](build-selection-lock.js) 以“非 `none` 风险标记更少 → confidence 更高 → proposal 稳定并列规则”逐行锁帧；[`build-localization-views.py`](build-localization-views.py) 再从绑定的 `sourceHighResolution` 生成最多 2048px 的 `0.1` 网格图；第二阶段只看锁定图并输出特征框，candidateId 不可改变。selection lock 与 localization view manifest 都绑定候选 hash、父报告、controller 和 `productionWrites=false`，不接收当前留出集真人目标坐标。

首个时间顺序留出批已推进到真人页：r77 inventory digest `1ACD1BC9…B3B` 仍为 221 identity / 214 resolved / 7 missing；r79 第一阶段 model digest `276D82B9…B60D`，Fast3 在 `585.2s` 完成 6/6、0 timeout，A/B 同帧 4/12；selection lock `0934B488…C837` 各锁 proposal/independent-review 6 行。r80 第二阶段 model digest `ED90FF17…2EC`，Fast3 在 `975.9s` 完成 6/6：4 个作业首试接受、2 个因 `featureBox` 单轴小于 `0.02` 有界修复、0 timeout，12/12 保持锁定候选。最大精确帧为 `14486×16233=235,151,238px`；[`render-feature-large-frame-v1.py`](render-feature-large-frame-v1.py) 只把本进程 Pillow 上限提到 manifest 的 `16384²`，以 `renderer.boundedLargeFrameDecode.unboundedDecode=false` 留证，完成 24/24 高分辨率渲染，digest `6AC462E3…FB22`。最终 review digest `1A1A6DF1…FF57` 已通过 12 行/330 artifact build/check、Edge 保存回归与 open preflight，并于 `2026-08-07` 打开真人页面。该状态仍是 `reviewer_ready / productionReady=false`，完整人审回执前不得准备下一 shard 或 promotion。

r80 真人导出已冻结为 5 pass / 7 adjustment，human-review receipt `36DED9ED…26EA`；0 wrong-pose、wrong-subject、source 或 variant-mismatch。7 项备注中四项是明确水平反转，一项要求放大飞行机体前端，一项要求反转并重新锁定头部，一项明确采用 Luna B。它们已在 `campaign-guidance-r82-r80-adjustments-20260807T075500Z` 完成 7/7 真人框选，guidance receipt `9C9AEE87…1404`；r83 有界大帧无模型直渲染为 7 行/57 artifact、最大 MAE `4.215684`，digest `70DE1A58…2886`。黄金/铁凤凰、重装盾牌骑士、锡蒙利与铠甲勇士骑马版的人工“反转”再由 v2 orientation controller 精确消费人类 supersample，五份报告均为镜像 MAE `0`。r85 累计 feedback `DE3E682B…227A` 现闭合 120 条真人决定、94 个真实框选，最近一轮 5 pass / 7 adjustment；`24 × 0.583333 = 13.999992 > 6`，所以下一 shard 仍保持 12 身份。

r86 首次准备暴露 `--exclude-manifest` 只读取直接 reviewItems、没有传递 `campaign.excludedPriorRefs` 的缺口；[`prepare-campaign-shard-v2.py`](prepare-campaign-shard-v2.py) 现将既有排除集合传递闭合并证明新 shard 与 132 个既有 ref 的交集为 0。剩余来源池无法满足 3 source × 4 identity，故改为 4 source × 3 identity，模型仍是 3 个四行小批、身份总量与 Fast3 并发不变。有效基批 `campaign-shard-r86-v14-base-transitive-v3-20260807T094000Z` manifest digest `6978DBFB…F96B`，包含武士大僵尸、波斯弓兵/步兵、方舟卫士/护士/无人机、防爆服僵尸、黑铁弓箭手/长枪兵、ArmsArchai、ArmsArius 素体和 ArmsMalakim；Surveyor 与闪流步兵因命名 `man` 缺失继续进入异常队列。

r87 由 [`attach-feedback-atlas-v4.py`](attach-feedback-atlas-v4.py) 闭合 120/120 标签：24 pass、94 guided correction、1 orientation-only、10 guided orientation、1 anomaly，atlas digest `70DE35AA…8509`；v4 同时冻结 Luna Max / Fast / concurrency 3 / timeout 600。r88 再由 [`derive-compact-model-atlas-v2.py`](derive-compact-model-atlas-v2.py) 动态写入 120 标签计数，确定性检索 32 个视觉示例，将 atlas patch `17,287→4,661`（`−73.0375%`），manifest digest `94C6EA99…EA88`。

r88 也给出了选帧阶段的关键工程负例：旧 `run-visual-pilot.js` 仍要求即将丢弃的 feature geometry 通过最终占比门，6 个 A/B 首答全部因几何被拒（5 个 `RESULT_FEATURE_TOO_SMALL`、1 个 featureBox value invalid），16 次 attempt 后只有 2/6 作业通过严格门，失败报告 `D2E38155…97C4`。[`derive-selection-only-report-v1.js`](derive-selection-only-report-v1.js) 不放宽第二阶段，而是绑定该失败报告与全部首答 artifact，按“每 role/batch 最早 transport-complete、schema-valid 首答”确定性只验身份/候选，禁止 outcome cherry-pick；selection-only report `B728A395…2995` 复用 6/6 首答且零新增模型调用，selection lock `7C419920…C8BD` 锁 proposal 5 行、independent-review 7 行，A/B 同候选 6/12。

[`build-selection-localization-views-v2.py`](build-selection-localization-views-v2.py) 随后直接从 selection lock + 精确 SWF 帧导出 12 张 2048px 网格图，不消费首阶段 featureBox，也不需要为了取得 `sourceHighResolution` 先渲染伪几何；它只在 prompt experiment 显式绑定父 manifest、候选像素 hash 不变时允许父 selection lock。r91 source/view digest 为 `E0B01F1C…3C64 / 88617002…0296`。r90 第二阶段 Luna Max Fast3 的 6/6 作业全部首答通过、0 repair/timeout/orphan，墙钟约 `638.5s`，12/12 保持锁帧、A/B 同候选 12/12、5/12 高亮；model digest `FB2B85F7…C9E7`。24 路有界大帧高分辨率渲染最大 MAE `4.160353≤8`，render digest `F84B3099…36A1`；最终 review digest `9AE465D9…6DE` 已通过 12 行/339 artifact build/check、真实 Edge 保存回归、open preflight 与可见页面检查，页面于 `2026-08-07T10:00:52.186Z` 打开。严格状态仍是 `reviewer_ready / productionReady=false`。

当前 campaign 默认执行参数仍为 **Luna Max + Fast + 全局并发 3 + 每进程 600 秒**。r103 真人回执冻结为 7 pass / 4 adjustment / 1 wrong_pose，首轮通过率 `0.583333`；两项纯翻转已确定性修正，两项诺亚兵构图已完成真人框选和无模型重渲染。维护者随后明确要求下一身份批翻倍，故 [`build-feedback-calibration-v4.js`](build-feedback-calibration-v4.js) 把 `24 × 0.416667 = 10.000008` 保留为复议遥测，但不再作为扩容硬门；r109 回执固定 `recommendedNextShardSize=24 / recommendedSourceGroups=6 / humanReviewPageLimit=null`。身份批翻倍不等于模型并发翻倍：每个模型小批仍最多 4 行，Fast3 与 600 秒超时保持不变。

历史人审中共检出 14 条明确方向备注；能判定目标方向的样本全部要求主体朝右，没有朝左反例。后续锁帧定位改用 [`run-localization-pilot-v2.js`](run-localization-pilot-v2.js) 和 `cf7.portrait-pilot-feature-selection-orientation.v2`：Luna A/B 除原始 feature 几何外，还必须输出 `orientationAction=keep|flip_x`、可见地标理由与方向置信度。默认规则是人脸、视线、口鼻、喙、头部前端或非人单位的主运动/感觉轴朝头像右侧；正面、对称或无方向主体保持 `keep`。[`render-feature-orientation-v1.py`](render-feature-orientation-v1.py) 在原始候选坐标完成裁切后、派生 512/80/48/32/WebP 前执行水平翻转，因而模型不得自行镜像 box 坐标；A/B 方向不一致会继续高亮真人复核。历史模型/renderer 文件不改写，所有新报告同时绑定基础与版本化控制器。

`敌人-拟态投影::default` 的历史 source 备注经维护者确认属于方舟妖姬同单位换皮；非生产 alias receipt `1B28306B…7DBC` 将其指向已接受的方舟妖姬 `e10-c03/f25` 头像。`敌人-黑无常索命::default` 被回执显式排除，继续单独处理，不允许 root fallback。

后续 shard 默认走两阶段：完整 feedback atlas v4 → compact retrieval v2 → selection-only 首答闭包 → selection lock → direct locked-frame localization views v2 → `run-localization-pilot-v2.js --localization-views ... --service-tier fast --max-concurrency 3 --timeout-ms 600000` → `render-feature-orientation-v1.py render/check` → `build-review.js` build/check → `test-review.js` → `open-review.js --check` → 打开页面。selection-only 只授权候选/帧，任何 featureBox/mustIncludeBox 都不得跨过 lock；最终几何与方向仍必须在第二阶段通过严格门。必须先看到 `review_open_preflight_verified`；页面导出并经 `verify-review-decisions.js` 冻结前，不准备下一个 shard。若人类将某行标为 `adjustment` 且能明确 A/B frame/crop，转既有 framing-guidance 支路，不再重复调用 Luna。

若 FFDec 为带 linkage 的导出目录生成 `DefineSprite_<id>_<linkageName>`，不得修改历史 [`prepare_pilot.py`](prepare_pilot.py) 或 [`render-feature-orientation-v1.py`](render-feature-orientation-v1.py) 以免破坏既有报告复验；改用 [`render-feature-orientation-linkage-v2.py`](render-feature-orientation-linkage-v2.py)。该包装器精确绑定历史 renderer hash，只接受同一 characterId 的唯一裸目录或唯一 linkage 后缀目录，拒绝任意目录 fallback，并把兼容控制器、策略和 gate 追加到新 render report。若精确高倍帧同时超过 Pillow 默认像素阈值，只允许用它的 `render-bounded` 在 fresh 输出目录重试：进程级上限绑定 manifest 的 `maximumSourceFrameDimension²`（当前最大 `16384²`），固定 `unboundedDecode=false`，并证明复制输入字节一致、来源输入未改写。

`wrong_pose` 不能用人工 crop 强行修补错误状态。固定使用 [`build-frame-reselection.js`](build-frame-reselection.js) build/check → [`test-frame-reselection.js`](test-frame-reselection.js) → [`open-frame-reselection.js`](open-frame-reselection.js) `--check`/可见页 → [`verify-frame-reselection.js`](verify-frame-reselection.js) build/check。页面大尺寸显示每个候选的 SVG 原帧和 PNG 参考，父轮已否决 candidate 必须禁选；人类可选替代帧，或显式要求扩大抽帧。若 `expand_search` 后维护者指定了动作状态，改用 [`prepare_action_frame_reselection.py`](prepare_action_frame_reselection.py)：它同时解析 FLA 标签层与人物层的同帧关系，再在 SWF XML 中复核 `actionLabel → named man → DefineSprite`，只导出该内部时间轴；不得退回首帧 `man` 或 linkage root。新批必须绑定扩帧回执、FLA/SWF/XML、FFDec 命令与全部旧候选，并把所有被维护者否决的旧 candidateId 禁选。回执仍只冻结 frame/hash，旧模型几何必须丢弃，随后用 [`prepare_frame_reselection_localization_v1.py`](prepare_frame_reselection_localization_v1.py) 从真人所选 SVG/精确帧生成单行 P3 manifest 与高分辨率 localization view；该适配器必须绑定重选回执、保留累计人类偏好校准，并证明 `oldModelGeometryConsumed=false`。

诺亚虔信者 r111 已冻结 `expand_search`；r112 由 `空手攻击 → 双枪狂徒/sprite/平a → man/DefineSprite 1062` 提供 12 个新帧并禁用旧 6 帧，真人已选择 `e09p-c06 / frame 22`，回执 `4463ACED…B35C`。r113 重新导出的 2048px 网格 view digest 为 `7B247CA5…228D`；Luna Max Fast A/B 对头部框与必保留框分别达到 IoU `0.906593 / 0.941734`，均判断 `keep`，model digest `8A57D332…CF84A`。12× 精确帧渲染未放大候选，最大预乘 RGBA MAE `2.319056≤8`，render/review digest 为 `4DE3C153…7C9F / FE01432A…C58D`。维护者随后将该行标为 `pass`，r113 human-review receipt `483883F2…62BFE` 达到 `human_reviewed_approved`。

r114 用 `human-review-supersession-report.json` 将 r103 的诺亚虔信者 `wrong_pose` 与更晚的 r113 `pass` 明确建模为“旧决定被新决定取代”，而不是同时计入累计偏好；report digest `5B1388DD…1592`，重建快照为 12 个当前决定 / 24 个 render row。r115 feedback calibration digest `BED54362…D25E` 保留 7 pass / 4 adjustment / 1 non-adjustment failure，并冻结人工扩容覆盖：下一批 24 identity、6 个请求 source group、单页优先、Luna Max Fast3、每模型小批最多 4 行、单进程 600 秒；预计复议 `10.000008` 只作遥测，不是阻断门。

24 身份基批 `campaign-shard-r116-v16-base-24-sparse-20260807T133411Z` 因剩余来源稀疏，将“请求 6 组”实现为 17 个实际 SWF 的不均匀布局，但仍保持 24/24 identity、6 个四行模型批和首帧唯一命名 `man`；manifest/source digest 为 `69FD564B…FB71 / 178BF325…AE7B`。r117 atlas v5 绑定 144/144 当前人类标签，并把被取代的诺亚负例单独可视化；完整 atlas SHA `44FAD051…A743`。r118-v2 compact retrieval v3 保留全部回执闭包，从 20,709 个 32px patch 减到 6,313（`−69.5157%`），确定性检索 45 个视觉身份示例；manifest/source digest 为 `C6A827BC…9FF4 / EA4F0654…06DD`。

selection-only 的一次首答只把相邻 prompt digest 两个字符转置，候选、角色、批次、source 与 artifact 均闭合；[`recover-selection-adjacent-digest-v1.js`](recover-selection-adjacent-digest-v1.js) 只允许该精确转置并写不可覆盖证据，r119 recovery/model/lock digest 为 `E93596CE…3B67 / 41B93B7D…E08A / 1E62DBE2…8C8F5`。lock 含 24 行，A/B 候选一致 13 行，最终 proposal/independent-review lock 为 6/18。r122 从锁帧导出 24 张原生高分辨率定位 view，digest `E1A8956E…B61C`。

r121 第二阶段的 12 个首答全部 transport-complete、schema-valid，24/24 保持锁定候选、23/24 方向一致；但严格运行中仅 6 个作业首答通过，另 6 个只因最终特征占比门失败，且 3/12 缺少完整进程退出证据。[`derive-localization-first-answer-report-v1.js`](derive-localization-first-answer-report-v1.js) 因此保留 `strictFeatureOccupancyAccepted=false / fullProcessExitAndOrphanEvidenceAvailable=false`，只将 7 个 role-row 的原始几何转入真人判断，model digest `66F03685…606F`；它不声称严格模型运行成功，也不授权艺术接受。

r123 全量 48 路诊断证明 46 路仍通过全局预乘 RGBA MAE≤8，只有 `敌人-独狼/e22-c01/frame 1` 的 A/B 两路为 `8.214529`；diagnostic digest `A0FE0C33…890`。这不是历史二值 GIF alpha 例外。r124 用 alpha MAE `1.850344`、实体核心 IoU `0.985041`、重心差 `0.001401`、双向 1px edge recall `0.993615 / 0.992822` 和 alpha bbox 最大 1px 差证明该精确帧的矢量/栅格形状对应，evidence digest `CB533EA5…A17`；适用上限仅 `8.25` 且只绑定该 identity/candidate/frame/两角色。最终 fresh r125 由 [`render-feature-orientation-human-review-fidelity-v1.py`](render-feature-orientation-human-review-fidelity-v1.py) 合并有界大帧、7 行精确 occupancy 人审例外、方向变换和上述 2 行对应证据，48/48 闭合，5 个 `flip_x`，render digest `8E531D95…2F46`。24 行 review digest `4BC613FF…2832` 已通过 build/check、真实 Edge 保存回归和 open preflight，并于 `2026-08-07T23:59:00.889Z` 打开可见页面。严格状态是 `reviewer_ready / productionReady=false`；完整真人决定导出前不得启动下一 shard、promotion 或 consumer 写入。

r125 真人回执 `106A8816…EAFE` 冻结 16 pass / 6 adjustment / 2 wrong_pose。6 条 adjustment 已在 fresh r127 guidance `72842662…EC85` 完成人工框选，receipt `47042E62…44F6`；r126 曾正确暴露汽车炸弹旧初框超过交互上限约 6 个源像素，页面现于 initial state 使用同一 `[-0.5,1.5]` / 最大 2× candidate 安全夹取，r127 的 6 行/85 artifact Edge 回归通过。r128 有界大帧无模型重渲染 6/6，最大 MAE `4.161664≤8`，report `479AF12F…1580`。汽车炸弹的最终人工焦点是**车尾发动机**，用于避免横向整车/车头排版问题；后续 atlas/prompt 必须以该更晚语义覆盖父决定里“强调车头”的旧备注。

ArmsArius 是方向模型的明确负例：原始 `e19-c01/f1` 已朝 canonical 右侧，但 r121 proposal/independent-review 都以 `flip_x`（confidence `0.90 / 0.88`）错误翻成朝左；人类“反转后可用”是要求再翻一次恢复原方向，不是说原图方向错。[`render-guided-orientation-adjustment-synonym-v1.py`](render-guided-orientation-adjustment-synonym-v1.py) 精确 pin 冻结 v1 controller，只把明确同义词“反转”加入授权词表；r129 在人工框选母版上恢复朝右，镜像 MAE `0`，report `51AB99AF…A355`。后续方向提示必须把它计为 `model_flip_false_positive`，不得从最终 flip 次数反推源图本来朝左。

两条 `wrong_pose` 已按人类备注语义拆开。黑白无常 r130 的 6 帧页因双人头距仍过大，由维护者导出 `expand_search`，回执 `7A8D173C…4BC`。随后维护者给出精确指令：外层动作 `血腥死`（XFL/SWF action frame 105）→ `个人编辑单位/浮士德的一堆相关或是不相关/Symbol 597` → SWF `DefineSprite 591` → 内部 frame 249，并要求裁切后 `flip_x`。版本化 [`prepare_exact_action_frame_directive_v1.py`](prepare_exact_action_frame_directive_v1.py) 同时验证 XFL 目录工程、root linkage、动作标签、库元件映射、XFL/SWF 动作起帧、内部时间轴总帧数与精确 frame，r131 选择回执 `C70F62DE…905C`；旧候选整组保留为已否决证据。

r132 首次定位调用因 WindowsApps `codex.exe` 在模型调用前 `spawn EPERM`，空 model artifact 与隔离 cwd 保留为失败证据。r133 改用已验证的 plugin appserver CLI 后，Luna Max Fast A/B 首答均锁定最右侧相邻双脸与最少拥抱上下文，feature/must-include IoU 为 `0.966149 / 0.948909`，并一致服从人类 `flip_x`，model digest `28924F52…739A`。标准 renderer 只因精确帧 `196,528,804` 像素超过 Pillow 默认阈值而 fail-closed；[`render_feature_orientation_large_frame_retry_v1.py`](render_feature_orientation_large_frame_retry_v1.py) 在 fresh r134 将进程级解码上限绑定 manifest 的 `16384²`，保持 `unbounded=false`，裁切后再反转，render digest `B7BFC006…4CD`。维护者最终导出 `pass`，人审回执 `01F0D648…B458`；[`verify_human_orientation_conformance_v1.py`](verify_human_orientation_conformance_v1.py) 另以回执 `38042FCC…535` 证明人类方向指令、A/B 与两路 render 一致。该回执是并行 provenance，不冒充页面曾审核该回执本身。

迷你黑洞明确“当前 frame 10 可用”，禁止重选帧。版本化 [`prepare_black_matte_review_v1.py`](prepare_black_matte_review_v1.py) 从 r125 的 proposal / independent-review 两个 4096px `sourceSupersample` 各派生 gamma `0.50 / 0.75 / 1.00` 三档，共 6 个候选；固定公式为 `v=max(R,G,B)/255; m=v^gamma; A'=A*m; RGB'=RGB/m`，在 4096px 层执行后再生成 512/80/48/32 PNG。该变换在黑底上的预乘 RGB 保持不变，r136 六项实测最大误差均不超过 `1/255`。r135 因 Pillow `mode` 参数弃用警告后 controller source closure 被主动废弃；fresh r136 dataset digest `3266ABA3…A8FE` 闭合 65 个 artifact。真实 Edge 回归已验证 2 个原构图、6 个候选、18 个小尺寸预览、localStorage 隔离、stale/hash 漂移拒绝、原生保存与重复点击抑制；open preflight 通过，可见页面已于 `2026-08-08T01:23:20.280Z` 打开。当前严格状态为 `review_open_preflight_verified / productionReady=false`，正在等待真人选择。

r136 最终真人选择 `independent_review-g075 / gamma 0.75`，human black-matte receipt digest `7A2EEC23…C43C`。[`build-human-review-resolution-snapshot-v1.py`](build-human-review-resolution-snapshot-v1.py) 在 r140 将黑白无常与迷你黑洞两条旧 `wrong_pose` 同时保留为负例，并以更晚的 pass/像素作为当前状态；resolution/snapshot receipt/render digest 为 `751C6AA3…0D9 / 66D49B4E…49EE / 96722123…D9B`。累计反馈随后不再只替换当前六行：[`build-feedback-calibration-v6.js`](build-feedback-calibration-v6.js) 将 r115 的 99 条历史框选与 r139 的 6 条新增框选去重合并为 105 条，同时继承 Luna Max / Fast6 / Fast3 fallback / 600 秒执行合同，digest `121110C7…B733`。

48 identity 扩容目标在 campaign 尾部被真实可用量钳制，而不是降低目标：[`prepare-campaign-shard-v5.py`](prepare-campaign-shard-v5.py) 证明传递排除后只剩 13 个首帧唯一命名 `man` 可运行、6 个 consumer identity 缺来源，r142 manifest digest `C696AEC1…BD09`，历史回流为 0。atlas v6 / compact v4 分别绑定 168 条当前标签（58 pass / 109 adjustment / 1 source）、105 条几何与 3 条 superseded negative；r144 atlas SHA `A93D4846…C29B`，r145 将视觉 patch 从 24,721 降到 9,499（`−61.5752%`），manifest digest `7EBDC98F…DD1`。

并发不再使用单一全链路值。r145 selection-only 的 Fast6 实测 8/8 首答单消息闭合、8/8 exit 0、0 timeout/orphan/survivor，墙钟 `504.4s`，selection report `647B0264…A80B`；因此选帧可保留 Fast6。相同 Fast6 用于精确 localization 时，7/8 作业最终闭合但多项进入 2–3 次修复，最后一项仍因 short-axis occupancy 失败，且出现 WebSocket timeout → HTTP fallback，failure digest `CCCECC32…C3E`；它命中回落条件。r149 以 Fast3 和显式 structural floor `long=0.74 / short=0.35` 重跑后严格通过，8 个作业共 11 次尝试、13/13 candidate 与 orientation 一致、两路各 3 个 `flip_x`，model digest `BEAF4154…D43`。标准 render 只因超大帧超过 Pillow 默认阈值失败；r151 在 manifest 绑定的 `16384²` 上限内闭合 26 行，render/review digest `23B9A6A1…4B51 / AFE58534…85C4`。13 行 Edge 回归与 open preflight 已通过，可见页面已打开；当前仍是 `review_open_preflight_verified / productionReady=false`，必须等待真人导出。

r151 已取得真人回执 `89C2157B…165B`：12 pass / 1 adjustment。齐天大圣的唯一 adjustment 由 r152 真人收紧框选并在 r153 确定性无模型重渲染，guided receipt/report digest 为 `DCE8E52C…66949 / 1EBE51FF…EA71`；累计校准 r157 因而闭合 181 条人类偏好与 106 条几何。该结果取代上一段“等待真人导出”的运行状态。

最后五个暴走系身份没有 ExportAssets linkage，但 `prepare-campaign-xfl-embedded-rescue-v1.py` 从 `加载mc库-黑铁会` 的 XFL 帧号和精确 twip 平移映射到 SWF `PlaceObject`，再分别锁定根首帧唯一命名 `man`；外层怪物根、血条/等级层和 root fallback 均未渲染。r158 selection Fast6 四个作业 4/4 首答正常，report `6E4052B3…EB2A`；r160 localization Fast3 四个作业同样 4/4 首答正常，5/5 candidate/orientation 一致，report `2B2E0DEE…368E`。r162 有界大帧 render/review digest `BD9CA3B9…17A7 / 7EE8BAB8…446`，真人回执 `F1F5AC41…4FEE0` 冻结 5/5 pass。

`build-feedback-calibration-v8.js` 与 `attach-feedback-atlas-v8.py` 已把这五条正样本追加到累计 186 标签 / 106 几何，feedback/manifest digest 为 `26C89B40…FCC0E / F7CE505E…A6CB`。最近 18 行为 17 pass / 1 revision，所以“规模 × 失败率≤6”允许未来同类 identity 批从 48 翻倍到 96（预计复议 `5.333333`）；模型执行仍是 selection Fast6 / localization Fast3 / timeout 600 秒，并发 8 仍未授权。

`build-campaign-source-exclusion-closure-v1.py` 最终对账 221 个 consumer identity：219 个 source-resolved，2 个是已验证非运行时排除项，actionable missing=0，closure digest `A99E0181…DD49`。`敌人-Serpent` 只有 enemy property 与 save-repair allowlist；`units.json`、asset map、FLA/SWF export 均没有可实例化敌人根，FLA 的 `Serpent/*` 只是 ArmsArius 内部肢体零件，禁止复用 ArmsArius 头像。`敌人-不知火舞` 有“不考虑实装”注释且命名 FLA 只在 `flashswf/unused`。两者未来若实装，必须重新进入来源解析和真人验收。P4 候选/人审/来源闭包完成不等于 promotion；当前继续保持 `productionReady=false / productionWrites=false`。

生产写入分三层：`promote-team-portraits-v1.py check` 保留为 98 identity Team 子集门；`promote-enemy-portraits-v1.py promote --replace-existing` 是消费者无关的全量原子重建入口；`promote-arena-portrait-supplement-v1.py preflight/promote/check` 只允许在精确基础 manifest digest 上追加已冻结的 Arena 尾批，并采用 staging、版本化 backup、原子替换和 shared manifest 复验，失败自动恢复旧包。当前 `cf7.enemy-portrait-manifest.v1` 为 226 identity / 227 variant / 222 human-accepted variant / 2 pending / 1 excluded / 2 aliases，manifest digest `33E1FABF…9961`；`check` 同时验证 444 个 SVG/PNG 绑定（442 个唯一文件）、Team 子集、JK 双变体、方向来源、alias target 与 supplemental closure `4B85A8E7…9AA4`。

Arena supplement 的唯一非主体项是 `敌人-锡蒙利范围光环发生器`。维护者批准复用后，先用 `freeze-arena-portrait-alias-v1.py build/check` 把单位 ID、57×3 退化逻辑帧证据和目标 `敌人-锡蒙利::default` 的不可变 SVG/PNG 绑定为非生产回执；再由 supplement controller 把 identity alias 写入 manifest。不得手改 manifest、复制目标主体，或仅凭相邻 ID 自动代签。

增量后不得继续对 r210 运行 `--current`：它绑定的是增量前 controller/manifest，保留为 217 项历史基线。当前方向门使用 `audit-portrait-orientation-propagation-v1.py` 的 supplemental-aware 全量重建；r220 从原始 217 项来源重新计算，再消费 r219 五项人审选择，闭合 222/222、0 action/SVG/PNG mismatch、0 legacy，report digest `1A10ECD4…DC2A`。

## 缺失 `man` 的内部主体救援

`man` 缺失默认视为素材命名/封装约定缺失，不等价于角色图形不存在。救援入口 [`prepare-internal-subject-rescue-v1.py`](prepare-internal-subject-rescue-v1.py) 会遍历怪物根时间轴及最多三层内部 `DefineSprite`，按结构复杂度分为 high / medium / low 并保留根时间轴直连候选；复杂度只作召回先验，不能选定生产主体。已知 `area`、人物文字信息、血条、等级、名字、碰撞框等路径先硬排除，预览每个 sprite 最多均匀采样五帧，并以单帧 64,000,000px 为安全上限。任何根 MovieClip fallback、SVG 提前导出和生产写入都被禁止。

通用来源解析顺序冻结为：先渲染带血条/等级等外围组件的怪物根帧作为**只读身份参考**；再按复杂度分层召回内部 MovieClip，并用多模态视觉逐项判断“与根帧主体对应、形成连贯单位、看起来确实是怪物/兵种”，排除武器、特效、阴影、色块和 UI。只有全部 MovieClip 都失败时才进入 Graphic fallback；Graphic 必须能从参考根帧的实际 `PlaceObject/DOMSymbolInstance` 放置关系回溯，优先使用根帧中真实放置的 Graphic，禁止遍历库中无关 Shape 猜主体。Graphic 仍需通过连通轮廓与参考主体的视觉闭合并进入真人验收，不得自动推广。异形蛋 `敌人-异形蛋 → 异形蛋/Symbol 7 → Shape 1` 是首个双重验证样例：XFL 放置矩阵、SWF twip 矩阵及根帧最大连通主体与编译 Shape 均闭合，外层 UI 仅作参照并从输出裁掉。

真人点击仍是主体权威，但进入昂贵定位前有一个极窄的客观语义门：近乎纯色、接近 100% 填充的实心矩形不能作为可识别主体。该门不按复杂度、模型置信度或美术偏好自动改选，只失败关闭并打开 [`open-internal-subject-reconfirm-v1.js`](open-internal-subject-reconfirm-v1.js) 的单项复核；页面预填其余决定、只显示冲突行，并要求真人重新点击后才可保存完整回执。

当前 Arena 17 个 `named_man_missing_root_fallback_forbidden` 身份的候选包为 `tmp/portrait-pilot/internal-subject-rescue-r180-final-candidate-pack-20260808T112500Z`，manifest digest `D3D561F1…A76F`：17 个身份、113 个可审候选、103 个已知 UI 排除项、17 个不安全/空白/过大预览排除项和 5 张模型联系表。执行顺序为：

```powershell
python tools/portrait-pilot/prepare-internal-subject-rescue-v1.py check `
  --output tmp/portrait-pilot/internal-subject-rescue-r180-final-candidate-pack-20260808T112500Z

node tools/portrait-pilot/run-internal-subject-rescue-v1.js `
  --manifest tmp/portrait-pilot/internal-subject-rescue-r180-final-candidate-pack-20260808T112500Z/internal-subject-rescue-manifest.json `
  --codex-exe <verified-absolute-codex-cli> `
  --service-tier fast `
  --max-concurrency 6 `
  --timeout-ms 600000

node tools/portrait-pilot/build-internal-subject-review-v1.js `
  --batch tmp/portrait-pilot/internal-subject-rescue-r180-final-candidate-pack-20260808T112500Z
node tools/portrait-pilot/test-internal-subject-review-v1.js `
  tmp/portrait-pilot/internal-subject-rescue-r180-final-candidate-pack-20260808T112500Z
node tools/portrait-pilot/open-internal-subject-review-v1.js `
  --batch tmp/portrait-pilot/internal-subject-rescue-r180-final-candidate-pack-20260808T112500Z

node tools/portrait-pilot/open-internal-subject-reconfirm-v1.js `
  --batch tmp/portrait-pilot/internal-subject-rescue-r180-final-candidate-pack-20260808T112500Z `
  --review-key '敌人-闪流步兵::default'

# 维护者已在当前任务明确给出候选时，可用同一 verifier 记录并归档，不依赖浏览器下载按钮：
node tools/portrait-pilot/record-internal-subject-reconfirmation-v1.js `
  --batch tmp/portrait-pilot/internal-subject-rescue-r180-final-candidate-pack-20260808T112500Z `
  --review-key '敌人-闪流步兵::default' `
  --candidate-id isr17-c03-s26-f21 `
  --note '维护者明确选择 C03；纠正旧的纯青色矩形误选。' `
  --apply
```

[`run-internal-subject-rescue-v1.js`](run-internal-subject-rescue-v1.js) 要求 Luna Max A/B 独立查看每个复杂度层，逐行返回 `select | none`、主体相似度、连贯单位、UI/特效/武器否定标记、可见身份特征、置信度与理由；候选白名单、prompt/source/role 闭包、不同 PID、超时与孤儿进程均 fail-closed。本轮 Fast6 的 10/10 作业均首试接受、10 个不同 PID、模型墙钟 `312.224s`，报告 digest `2EB883F9…BD94F2`；17/17 均认为存在有效主体，16/17 具体候选一致，唯一分歧为 `敌人-闪6特工` 的 `sprite 343/frame 37` 与根直连 `sprite 288/frame 5`。

人审页 digest `109C2FE3…375FE` 展示全部 113 个候选和 A/B 理由，但**不预选** 16 个共识项；每个身份都必须真实点击候选或“没有有效主体”。点击与备注按 review digest 自动暂存在专用浏览器 profile，17/17 完整后才允许保存 canonical 决策与版本归档。浏览器 harness 已验证 17 卡 / 113 候选、0 模型静默预选、重载恢复和非空保存 payload。人工回执前严格状态仍是 `awaiting_human_subject_selection / productionReady=false`；只有主体选择冻结后，才能按精确 sprite/frame 导出矢量并重新进入既有选帧、特征定位与头像人审管线。

## 状态语义

```text
frames_extracted
→ candidate_proposed
→ automated_checked
→ human_reviewed_refinement_required
→ frame_candidates_ready（仅 wrong_pose）
→ human_frame_reselection_verified | human_frame_search_expansion_required
→ human_exact_action_frame_verified
→ feature_refinement_proposed
→ high_resolution_refinement_checked
→ human_orientation_directive_conformance_verified
→ black_matte_candidates_ready（仅明确要求黑底转 alpha 的后处理行）
→ human_black_matte_candidate_verified | human_black_matte_refinement_required
→ human_framing_guidance_verified（仅明确 frame/crop adjustment 时）
→ human_guided_automated_checked
→ representative_visuals_resolved_source_choices_pending
→ source_candidates_extracted
→ human_source_choice_verified | human_source_choice_manual_maintenance_required
→ campaign_inventory_frozen
→ campaign_shard_prepared
→ internal_subject_candidates_ready（仅缺失命名 man 的来源救援）
→ subject_candidates_proposed
→ awaiting_human_subject_selection
→ human_decisions_verified
→ candidate_proposed
→ automated_checked
→ review_open_preflight_verified
```

- `frames_extracted`：FFDec 产物和候选 hash 闭合，不代表帧适合作头像。
- `candidate_proposed`：A/B 结构化结果闭合，不代表两路一致或艺术合格。
- `automated_checked`：512/80/48/32 PNG 与 80px lossless WebP 已按白名单 crop 派生并验 hash，不代表人类通过。
- `human_reviewed_refinement_required`：当前 `sourceDigest + reviewDigest` 的全部行已由人导出并验证，且至少一个 eligible 行不是 `pass`；下一轮只重跑可精修的非通过项。
- `feature_refinement_proposed`：A/B 已分别给出语义特征与安全上下文，不代表选框或构图正确。
- `high_resolution_refinement_checked`：SVG 几何映射、FFDec 精确选帧、高倍 PNG、最高 4096 真实裁切母版、预乘 RGBA 保真度、派生尺寸和摘要闭合，不代表人类通过。
- `human_exact_action_frame_verified`：维护者给出的动作、内部库元件和精确帧已被 XFL/SWF 双证据验证；只接受该精确人类指令，不把“未命名内部时间轴”放宽成一般 root fallback。
- `human_orientation_directive_conformance_verified`：人类方向指令是权威，模型两角色与 renderer 两角色均与之相符，且方向只在原空间裁切后应用；它是 provenance 门，不替代艺术人审。
- `black_matte_candidates_ready`：冻结帧和构图不变，在 4096px 超采样层按记录公式生成黑底转 alpha 候选并闭合 512/80/48/32；尚未由人选择。
- `human_black_matte_candidate_verified / human_black_matte_refinement_required`：人类已选择精确 4096px 候选及其 hash，或明确要求继续调参；两者都固定 `productionWrites=false`。
- `human_framing_guidance_verified`：人类已在绑定高分辨率帧的实时 80px 预览上确认来源角色与像素正方形；接受范围仅是该 frame/crop，不外推为来源、变体或生产 promotion。
- `human_guided_automated_checked`：确定性 renderer 已逐字节消费冻结框选并通过高分辨率/保真度/派生门；没有新模型调用，也仍未写生产资产。
- `representative_visuals_resolved_source_choices_pending`：代表集 12 个 eligible 的视觉结果已闭合，来源阻断仍不可签名；该状态允许准备异常队列，不等于授权全量 campaign 或 promotion。
- `source_candidates_extracted`：敌人 duplicate/conflict 的来源、内部 `man` 帧、hash 与页面闭包已生成；尚无人类选择。
- `human_source_choice_verified / human_source_choice_manual_maintenance_required`：人类已逐身份选择可渲染来源，或明确转人工维护；两者都不把来源候选升级成产品变体，也不写生产资产。
- `campaign_inventory_frozen`：当前 consumer union、选源回执和来源分类已按 hash 冻结；不代表每个已映射来源都有可用内部 `man`。
- `campaign_shard_prepared`：有界 shard 的唯一 `man`、候选、SVG 几何与模型分片已闭合；不代表 Luna 已运行或构图正确。
- `internal_subject_candidates_ready`：缺失命名 `man` 的根已完成内部 sprite 分层召回和 UI 硬排除；复杂度不构成主体判断，且未导出矢量。
- `subject_candidates_proposed`：Luna A/B 已在白名单内分别判断连贯主体并留下可见特征与理由；一致结果仍不能替代真人点击。
- `awaiting_human_subject_selection / human_decisions_verified`：人审页已就绪，或全部身份的精确 sprite/frame 决策已通过 digest/白名单验证；后一状态才允许延迟导出所选矢量，但仍不代表头像构图或 production 通过。
- `review_open_preflight_verified`：当前 shard 的 manifest/model/render/review 与浏览器入口可复核；仍停在真实人类艺术评价前。

审阅状态固定为 `pass / adjustment / wrong_pose / wrong_subject / source / variant_mismatch`。`pass` 接受 Luna A proposal，Luna B 只作独立复核；非 `pass` 必须备注。本地进度按 `reviewDigest` 隔离，旧批或 partial 决定导入时 fail-closed。由 [`open-review.js`](open-review.js) 打开的页面优先走受验证的原生保存函数，同时写 canonical decisions 与版本化 `review-exports/`；保存期间按钮锁定，完成后按钮和 sticky 状态条显示精确 canonical/归档路径，重复点击不会并发写多份。普通浏览器环境才回退下载。
