# 启动卡顿 输入钩子与统一呈现优化

## 2026-10-10 共享 HUD 成本优化候选

已完成静止、仅 HUD 动画、混合呈现三组成本分解，并在隔离候选实现主 HUD 脏区域重绘与有界像素缓冲复用。最终交叉对照中主 HUD 绘制 CPU 用时下降约 35%–36%，提交下降约 62%–64%；像素上传量和 GPU 合成没有证明下降。完整方法、候选绑定、逐像素验证和实际游戏转场取样缺口归[专项记录](shared-hud-render-cost-2026-10-10.md)。本次没有正式 promotion，不继承下节 v5 的部署结论。

## 2026-10-09 战斗 HUD 不透明输出迁移

**当前完整主 HUD 包（v5 已正式提升，部署推送及远端 Audit 通过）：** 用户已授权完整主 HUD，并指定“排查手枪射击后K键失效”会话处理外部射击反馈。2026-10-09 用户完成联合候选粗测，未见明确阻断，明确要求核对日志后走发布列车；本轮已完成源码提交、双构建共识与正式 promotion，部署推送与远端 Audit 状态归[联合发布证据](evidence/main-hud-runtime-release-2026-10-09.json)。主 HUD 包持有 Host/native、相关 C# 回归及本节；射击会话持有 AS2 射击核心、对应测试/编译与 asLoader，交接文件归 `tmp/hud-main-unit/pistol-fix-handoff.json`。两边源码和产物均稳定后才冻结候选，避免构建中修改输入。

完整主 HUD 复用全部 10 类 widget 的现役绘制器，增加第五个 native 图面槽，顺序为伤害数字 → 底栏 → 资源 → Buff → 主 HUD；槽内各 widget 的绘制顺序不变。资源/底栏/Buff/主 HUD 按完整显示单元切换，任何成员必须回退时一并恢复原窗口层序，不能把仍在世界图面内的主 HUD 压到旧底栏窗口下面。显隐、暂停/恢复、会话死亡及未知写权威仍归原 controller/task；不靠换呈现后端清除业务状态或重放操作。此前修复的 DRS 等待期保留输出归属同样覆盖第五槽。

主 HUD 输入沿现有世界窗口的鼠标队列接入，以绘制层序先命中主 HUD、再命中玩家底栏。排队事件封存 widget、业务动作/会话/修订及输出几何；分发前重新核对。Notch 按钮、RightContext 的结果/返回/交付、SafeExit 的 armed/保存状态、NPC 会话与行、pinned tooltip 文档、对话帧和引导页分别提供自身目标快照。跨域松键取消原手势，不能在另一 HUD 合成 Click；多按钮仍保持归属直到释放。对话拖动柄可从按下快照保留捕获，即使 Down/Move/Up 都尚未进入 UI 分发，也不在跨区域时转交底栏或 Flash。Up 已执行动作的组件不再额外合成一次 Click。浮动注释的 inspection 滚轮继续由既有控制器裁定，未将其扩大为整个世界的消费区域；对话历史滚轮走其原 widget 的滚动实现。

机器门分为原有消费者回归、实际队列与真实 widget 的输入用例、完整生产绘制器的 GPU 像素/层序/恢复检查，以及主 HUD 增量提交对照。对照两边都保留已经迁入的 PlayerInfo，仅比较主 HUD 的旧 layered 窗口与新槽，避免重复计算上一包收益；回放不包含实时 painter 成本，不冒称实战 FPS。主 HUD 普通输入测试不发真实系统输入或业务写。原 `NativeHud` 自动化窗口端点保留既有可见性拒绝，隐藏期间不能观察/注入；本包没有把整幅世界窗口冒充该旧 HUD 端点，也不声明新的 agent 输入资格。

工程日只是前期未校准的复杂度估计。按本轮已建公共基础，后续改用“数小时内达到机器检查通过的可试玩候选”描述工作目标；人验、现场返修与正式发布分别记账，时间预算不作为测试或发布资格。当前机器结果、候选和共享文件边界统一归 `tmp/hud-main-unit/state.json`，完成状态以该次真实结果更新。

定向验证已通过：原有相关消费者 287 项、新队列与真实 widget 29 项，以及 NPC 动作值变化补测。完整主 HUD 的隔离 GPU 像素用例已通过，注册 10 类组件，资源/底栏/Buff/主 HUD 四层与独立 alpha 参考匹配，旧窗口隐藏且旧提交为零；层序反例、源无回灌、完整回退及面板恢复均覆盖。测试 Core 与隔离候选 Core 字节一致。早期测试中的事件订阅写法、仍在折叠态显示的 F 工具按钮假设、带边框 Form 冒充生产 Panel 的坐标假设均已修正，失败记录保留；没有放宽产品保护断言。最终合并候选、全量及配套 GPU 结果以 `state.json` 的实际身份和日志为准。

主 HUD 增量回放采用 1024×576 的真实冻结图面、8 阶段 ABBA，共取得 35 组 GPU 样本，查询错误为 0。动态提交阶段，测试进程 CPU 单核口径均值 11.54% → 7.05%，DWM 同一 3D 引擎 12.4% → 7.6%；测试进程该引擎 5.0% → 7.3%，native 提交采样 p95 0.638 → 0.906ms。工作确有移入应用 GPU，不能只引用 DWM 下降。两边测量期 Present 约 188.5 → 193.5 次，只有相同刺激频率；静态旧路径有一个阶段缺失 GPU 样本，不作静态 GPU 收益结论。短窗口、桌面其他负载与 CPU 阶段波动仍限制外推；结果归 `tmp/hud-main-unit/main-hud-review-result.json`，不是实战帧率、功耗或 MPO 证明。

射击会话交付的 7 个文件已按哈希复核。真实 CS6 TestLoader 的同一新鲜 run 共 670 项通过、0 失败（双枪后摇 30、长枪副武器 511、手动冷却 57、药剂输入 58、键位迁移 14），Compiler 0/0；交付 asLoader 另经真实 publish 0/0，测试类未进入交付物。每条射击通道使用独立普通对象持有后摇任务，取消/换装/同路径 MovieClip 重建的迟到回调受 owner 身份约束，汇总后摇保留其他通道状态。原冷启动触发超时证据保留，恢复过程未修改调度任务权限或策略。未取得外部附件和反馈者确切配装，故仍需实际 J/K 交错射击与停火转向复核；没有真实存档试写或自动游戏操作。
联合候选最终机器门为 Host 6845 通过 / 19 条件跳过 / 0 失败、绑定同一 Core/native 的 GPU 8/8、输入分类 94 项；AS2 670 项与 publish Compiler 0/0 分别绑定独立 asLoader。15:32–15:37 的用户试玩日志中，三次实际 DRS 缩放均未撤回共享 HUD，没有 compositor/fallback/reject/未确认关闭事件；13 次 Flash flush 与 shadow confirm 为成功。结算面板与窗口还原交界仍记录一次 UI timer 最大间隔 4484ms、Flash 单帧 4684ms，随后恢复；无栈证据，保留为未定位性能项，不宣布全程流畅或根因已修。输入桥过期包 11 项为 epoch gate 拒绝，invalid=0，目标退出后 broker 正常关闭；序号差不是业务写 ACK。粗测不代替完整枪械配装/物理输入矩阵，也不代替正式入口专项复验。

发布前政策门另补三项已确认问题：此前 `ced8e4e1e3` 新增“酿酒配方”时引用了 Flash/Web 均不存在的同名图标，改为复用已发布的“烹饪指南”并机械派生任务目录；调酒新增两处 9px 玩家文字改为 10px，债务 ceiling 不变；UI auditor 的正则起始判别改为等价的反向末尾 token 扫描，消除压缩第三方 JS 上重复扫描整个前缀的高耗时。新长文本回归仍检测真实构造器、缺 profile 负例并屏蔽字符串/正则假调用，子进程硬限 5 秒，ratchet 68/68。真实浏览器加载生产调酒模块及完整 CSS，1024×576 下五个库存标签和摇壶提示均为 10px、无横向溢出，只请求隔离模拟读，没有真实交易。v1 部分失败日志及不可变 tag/request 保留，未 dispatch 云构建；v2 使用新请求和完整政策回执，不沿用失败结果。

v2 完整政策门保留 45/47 失败回执：材料 sidecar 尚未随枪械 XML / 情报图标变化刷新，商店头像集合尚缺新增“调酒师”。材料生成器已更新来源摘要并通过 `--check`，字典主体字节不变。商店头像按 exact shopId 从现有 `调酒师.swf` 的普通帧完整重烘焙，保留原 supersample=1；既有来源与 alpha 边界未变，7 幅旧图有少量可见像素差异，最多一图 300 像素、预乘通道最大差 14，旧闭包及逐图差异已保留。当前环境第二次完整 `--check` 与隔离产物逐字节一致，再由原 baker 的 subjects-first/manifest-last writer 接入，生产树与重放树一致；最终 38 家活动商店 / 37 份图像 / 1,962,209B 闭包、消费者和懒加载门通过。没有改原画，也没有把重烘焙说成真人视觉验收。v3 重新冻结请求及全量政策门，两轮旧请求/标签/失败证据均保留且未 dispatch 云构建。

v3 source `5a1c92bec573ba660bfe36720f57b7e9b73ff193` 已完成本地 X509 / 独立 GitHub OIDC 双故障域共识、47/47 production policy 与唯一 promotion writer 的完整安装校验。云端 [run 37911235276](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/37911235276) 始终为 attempt 1；API 断连后接续同一运行并使用既有代理取回证明，未重复 dispatch。该轮正式 runtime 的 Core/native 与用户粗测候选逐字节一致，asLoader 独立哈希匹配当轮联合交付。旧运行包、失败请求/回执、头像原件与探针失败都已保留。

部署推送时远端先行推进，普通推送被拒后保留本地部署与上游历史，正常合并数值登记、成品酒暴击率包装及后续敌人标签/药剂草案。本批不改上游数值设计；防具重复记录断言对齐现行 `sourceFile + itemName` 身份，数值工具 861/861、枪械 365、药剂 106、防具 655、近战 231、爆炸物 39 条及派生同步检查通过，原有已登记 DPS 偏差不被改写为全量校准完成。合并后的 AS2 由射击会话重新执行真实 CS6：玩家输入 670/670、钛合金 241/241、隔离暴击包装探针 18/18；新 publish Compiler 0/0，710 个 loader 类与 main 交集为 0，测试实现未进入生产 SWF。新 asLoader 为 `A689480F6F6A3D16B729BB4F20BBDEE87D6CA59438CB714B6EFAF52AA226F232`，scratch/cfg 恢复且文件独占打开成功；CS6 留有响应正常的 TestLoader 窗口，并未冒称进程已退出。旧 asLoader 不覆盖上游。Host/native 输入未变，但政策域已变，v4 已据此重新使用新不可变请求、全量政策回执、独立云端证明与唯一 promotion writer，未让 v3 成功代签合并后的最终树。源冻结、AS2 哈希与最终推广结果仍以联合发布证据为准；用户此前粗测不覆盖新合入的暴击率、数值或敌人标签业务体验。

v3 时，无 candidate selector 的正式前门确认同一 `formal_runtime` identity/closure，未选择玩家槽位；受控 Flash 预热到期退回 Idle，再普通关闭，持有 OS 进程句柄取得 exit 0，11 份存档 JSON 前后哈希一致（正常启动版本标记单列排除）。首轮探针曾把预热误判为选槽，后续退出码采集也缺少持有句柄；两项探针失败原样保留，不当作游戏故障或成功回执，最终新鲜运行单独闭合。这里只覆盖正式前门与生命周期，不称完整 HUD、外部枪械配装或性能业务 `standard_entry_verified`。部署提交/远端 Audit 的最终结果以联合发布证据为准。

v4 source `f7d86a57b43177acb4896263f9324823bf2808ba` 与 tag `runtime-build-v2/20261009-main-hud-pistol-v4` 已完成 47/47 政策、双 signer / 双 faultDomain 共识及唯一 writer 正式提升。独立[云端 run 37920684182](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/37920684182) 为同一 attempt 1，首次状态查询 EOF 后接续原运行；本地 producer 只因前三域相同而复用，新请求与新政策回执均重新绑定。Core/native 与粗测候选同字节，合并后的 asLoader 使用上述 A689 哈希。v4 正式前门重新核对运行路径、identity/closure、未选槽预热退回 Idle、普通关闭 exit 0；11 份存档 JSON 前后哈希相同，没有强制终止。它没有执行正式游戏业务或新酒水/暴击体验。旧包、v3 记录和所有负例均保留；部署提交及远端 Audit 状态以联合发布证据为准。

v4 部署推送再次遇到上游 `ed52834315` 的食物/饮品数据及药剂定价公式更新，普通推送拒绝后正常合并，保留作者的设计与工作簿权威。Host/native 与全部已验 AS2 输入、A689 asLoader 未变；数值工具重新 typecheck、861/861、药剂 106/106 和材料 sidecar 检查通过。药剂 CLI 的 `sync --check` 实际执行同步、并非只读模式；本次同步未产生受跟踪物品/账本差异，随后正确的 `check` 再次通过，原调用与观察均保留。用户已协调暂停其他 main 推送，v5 从最终合并树重新冻结请求、政策和云端证明，未覆盖上游或沿用旧树回执。

v5 source `b13cea03affcdb2050a3b51eba09cc969b75687b` 与 tag `runtime-build-v2/20261009-main-hud-pistol-v5` 已完成最终树的 47/47 政策、双 signer / 双 faultDomain 共识及唯一 writer 正式提升。独立[云端 run 37924290619](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/37924290619) 绑定本轮 source/tree，本地与云端 build identity 和完整 payload closure 全等；本地 producer 与 CAS 仅因前三域不变而复用，旧云端证明未代签新树。正式 bootstrap 完整安装核验通过，previous 回滚包和此前各轮证据保留。本轮正式前门重新确认实际运行路径、identity/closure 和 A689 asLoader；未选玩家槽位，预热退回 Idle 后普通关闭 exit 0，11 份存档 JSON 哈希未变。该结果不代签完整枪械配装、上游食物/酒水/药剂业务或结算/窗口还原约 4.5 秒停顿的根因验收；部署提交 `d6ce570f8b033b0d55ddf00a0c1225f5ac67413f` 已正常快进推送 main；[远端 Audit 37926078825](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/37926078825) 成功，`state=promoted`、`deploymentChanged=true`、双 signer / 双 faultDomain 均由该提交的审计日志确认。

以下保留先前资源/底栏/Buff 包、现场反馈及追加授权前的投入评估，旧计数和候选不代签完整主 HUD 包。

最后核对代码基线：主工作区 commit `668961af03513647ea664c13f8ad6337419c857a` 加本批未提交增量；原隔离试点从 `ced8e4e1e34f4b09456ed0d064c68f9f2e495e30` 开始。用户先授权真实伤害数字与 PlayerInfo 资源图面的有限试点，确认底栏遮挡依赖后追加授权“资源＋底栏完整迁移，再接入 Buff”；其余 HUD/Web 留待后续决定。本批包含自动验证、隔离候选和性能对照，不含提交、推送、正式部署或真实玩家存档试写。

首轮双图面试点在精确绑定候选的自建窗口中运行。扩面源码在普通游戏装配中接入伤害数字、资源、底栏和 Buff 四个有界槽；专用 PlayerInfo 资格夹具保持其原承载。本批只交付 `isolated_candidate`，现役正式运行文件未写入；源码不依赖候选身份改变功能，未来正式部署仍需独立授权。世界仍走原 WGC/裁切/调色和战斗效果链，HUD 在 native backbuffer 最后混合后统一 Present。Web、其他主 HUD 和桌面光标保持各自现役承载；它不宣称整应用已成为单一输出，也不证明 MPO 根因。

资源、底栏与 Buff 按完整单元切换和恢复；绘制顺序为世界/伤害数字 → 底栏 → 资源 → Buff，其上仍是原主 HUD。各图面保留独立缓存和局部上传，旧 Form 在共享承载期间隐藏且不提交 layered bitmap。世界输出在既有鼠标入口中先固定手势归属，底栏事件有界排队后再分发给原 widget/controller；输入封存原目标身份与几何，跨目标、跨代次、拖出、挂起或取消不得形成新业务动作。业务协议、AS2 权威和未知写锁不变。玩家信息上传失败时先清除全部 native 成员，再整体恢复现有承载；若清除本身失败，则沿既有世界渲染失败合同退出，不能叠出两套输入/显示。扩面初次自动验证完成后，用户已完成两圈候选粗测，并反馈全画面连同 UI 多次缩放重组；连续性验收尚未通过，跟进见下文。

初次交付候选 `hupm2` 的主工作区 Host 全量为 6830 通过 / 16 条件跳过 / 0 失败，串行 marker 恰好一次；配套 GPU 专项 6/6 通过，测试 Core 与候选 Core 字节一致。交付前另复核旧 HUD 按住期间切入共享输出的边界：仅在旧 HUD 确实持有手势时转移松开屏障，不吞掉由 Flash 持有的释放。输入分类 94 项和文档巡检通过；当前候选身份读取 `tmp/runtime-dev/active.v1.json` 及对应候选的 metadata/manifest，配套检查结果归 `tmp/hud-opaque-pilot/state.json`。机器检查仅运行自建窗口模块；随后用户实际运行了 `hupm2`，但两圈粗测不等于完整视觉/物理输入通过，更不是 `e2e_verified` / `promoted` / `standard_entry_verified`。后续人验沿用根目录 `本地开发启动.cmd`，集中确认战斗 HUD 显示、技能普通格按住拖出取消（不点卸载角标）、面板返回及缩放/切后台后的连续性；物资写操作仍需其测试范围授权。

**11:32—11:41 候选试玩反馈与交接修复：** 已保留两次运行的启动日志、游戏日志和第二次性能记录，归 `tmp/hud-opaque-pilot/field-20261009-1141/`。两次请求分别为 69 / 63 次，但实际源尺寸切换各 3 次，均为 100% → 85% → 75% → 67%，期间另有 75% MEDIUM → LOW 的质量变化；未观察到来回升降。不能把效果预算请求计为重建或缩放。六次实际缩放都伴随 PlayerInfo `shared=False → True`，间隔 33–73ms；第二次还有真实输出窗口的移动/尺寸变化。面板和场景遮挡期间的较长退出单列，不能全算故障。

源码确认 `ready` 同时被用于“新源帧已满足尺寸/fence”和“HUD 输出载体可用”。DRS 交接保留了原世界输出及最后合成画面，却因新帧暂未就绪而撤掉四个 HUD presenter，触发资源/底栏/Buff 整组退回旧窗口。修复将载体资格绑定到已出过有效帧、输出仍可见、会话有效；调度和世界新帧资格仍要求当前 `ready`。窗口移动立即刷新 HUD 的物理输出坐标，不等待 WGC 旧尺寸消失；首次无帧、隐藏、会话退休和真实故障仍撤回。42 项 focused 回归通过，包括完整生产 PlayerInfo 消费者在等待期保持共享、移动不转回旧提交，以及隐藏/重接/退休；后续全量与新候选绑定结果归该目录和 `state.json`。

新增 native 源尺寸夹具在固定输出上切换 100/85/75/67% 源画面，核对世界标记位置、HUD 像素尺寸、旧图保留和纹理无重复上传。模块检查通过；初版夹具因最终构图相同而误接收旧帧，被原始裁切尺寸断言拒绝，已增加精确尺寸、时间 fence 与新 Present 的等待，失败记录保留。夹具源同步绘制新几何，不是 Flash 的异步重绘语义证明。用户反馈涉及整幅画面，不能把上述 HUD 回退定为全部缩放异常的唯一原因；现有日志没有过渡期连续像素，也不足以排除 Flash 新尺寸内容与捕获帧交接的问题。修复后的真实连续性仍待复核，不改 DRS 升降策略或 AS2 协议来掩盖未定位部分。

**其余原生 UI 投入评估（未授权扩面施工）：** `Program` 将 RightContext（含地图）、SafeExit、Combo、Toast、LootFeed、Notch、Tooltip、NPC、Guidance、Dialogue 共 10 类顶层 widget 接入同一个 `NativeHudOverlay`。本次第二段 324.8 秒记录含启动/面板：Notch 绘制 2445 次、RightContext 2171 次，旧提交计数 2505 次；后者还包含迁移单元的临时回退，不能全部归主 HUD。这些是活动计数，不是 CPU/DWM 耗时或收益证据。当前容器按可见组件外包矩形绘制和提交，大范围稀疏布局仍可能复制较大透明区域。

| 选择 | 可兑现的呈现收益 | 成本与建议 |
|---|---|---|
| 先稳住现有交接 | 消除已确认的短暂回退和重复窗口交接 | 本轮窄修已实施并补门；先完成现场连续性复核 |
| 主 NativeHud 整个容器迁入 | 战斗中再退休 1 个频繁更新的独立 HWND；复用现有绘制器 | 粗估 3–6 个有效工程日，非排期承诺。重点是地图/退出/NPC/对话/引导/固定提示框的输入、滚轮、捕获、身份和面板恢复；保留原命令权威。先比较真实大图面的上传成本，再决定是否需要分块 |
| 先迁 Combo/Toast/Loot 等只读组件 | 可减轻旧容器部分绘制/上传，通常不能退休主 HUD 窗口 | 粗估 1–2 个有效工程日，终局价值较低；拆分还需复核跨组件层序，不将每个 widget 算成一层 DWM |
| 桌面光标并入世界 | 最多再减少一个小图面窗口 | 优先级低。当前独立光标有更新节奏价值；世界等待/降帧不能冻结光标或增加手感延迟。没有证据支持为追求单窗口而迁移 |

主 HUD 并入后仍需在世界隐藏、面板或启动阶段保留适当显示归属，不能将战斗期窗口减少夸为全应用只剩一个输出。现有底栏输入适配器不能直接覆盖主 HUD 的异构交互；通用手势队列可复用，业务目标识别和恢复逐域验证。Web 保持用户此前确认的健康范围；本轮只作评估，未开始主 HUD、光标或 Web 施工。

完整单元的实际资源/底栏/Buff 绘制已进入 GPU 像素夹具：1024×576 全画面与独立预乘 alpha 参考逐通道容差 2 对比，反转底栏/资源层序必须失败；MP 区域有 1360 个像素保留了资源贡献。三个旧窗口隐藏且 layered 提交为零，Buff 清空、整体挂起/恢复、单成员不可用后的整体回退与重新接入均覆盖。Buff 清空后的迟到重绘曾重建透明图块，已修为零可见 widget 时保持槽清除；专门回归保留该反例。模块探索阶段分别记录测试 Core 和冻结 native 候选的哈希；最终装配复核必须二者与最终候选一致，不以探索阶段混合身份代签。

三块真实图面回放对照保持世界刺激 30Hz、资源/底栏更新 30Hz、Buff 更新 5Hz，ABBA 每阶段预热 2 秒、测量 6 秒。动态阶段 CPU 单核口径均值约 4.05% → 2.22%，DWM 同一 3D 引擎约 28.1% → 12.1%；测试进程该引擎约 4.0% → 4.8%，部分工作移入应用 GPU。静态 DWM 33.4% → 32.8%，没有明确收益。各条件只有两个短阶段，CPU 和桌面负载存在波动，且新路径测量期 Present 为约 187 次、旧路径约 178 次；这只是相同刺激频率的提交回放，不含实时绘制成本，不是实战 FPS/尾延迟或 MPO 资格。原始 39 组 GPU 样本和逐阶段结果归 `tmp/hud-opaque-pilot/player-info-review-result.json`；首次对照在隐藏 owned 窗口后未通过屏幕像素校验，固定输出与源窗口的次序后校验通过；不把窗口遮挡推断当作 DWM/MPO 根因，失败日志保留。

HUD 提交同步复制有效 BGRA 行，原生工作线程持有有界的四槽最新快照并独占 D3D 对象。透明图面使用预乘 alpha，不接受世界调色；清除、更新、源退休分别按槽处理。静态 HUD 不要求重复上传，无新世界帧时 HUD 变更仍能唤醒绘制；持续动画保留独立提交节奏。渲染器拒绝超过现有 extent 上限的图面，消费者明确记录 legacy fallback；失败证据不能降级为通过。

普通门包含真实 PlayerInfo 光栅缓存的提交/挂起/恢复/关闭回归；GPU 门复用 `CF7_TEST_SHARED_WORLD_CANDIDATE` 与精确候选清单，运行 `OpaqueHudGpuTests`，覆盖双层混合、调用方缓冲释放、原图无回灌、缩小/移动/清除及静态世界的 HUD 更新。需要亮屏，不自动唤醒、不注入输入。GPU backbuffer/自建窗口和生产消费者接线分别记证据，不能当作完整游戏、人类视觉/手感或弱机收益。

本批状态、实际候选身份与原始失败统一保存在 `tmp/hud-opaque-pilot/`；收口沿用主工作区现有开发入口，不新建快捷方式。

双层像素、独立清除、调用方缓冲释放后安全、原图无回灌和静止世界的 HUD 更新已在绑定候选的 GPU 用例通过；真实 PlayerInfo 缓存的托管提交/挂起/恢复回归也通过。受控 960×540、30Hz 图块负载采用 ABBA 顺序，保留原路径和新路径的实际桌面像素等价检查。初版比较夹具误套普通游戏的前台隐藏规则，导致原路径没有显示资源层；像素门正确拒绝。修正为非激活自建窗口承载同一生产 ULW executor 后才进行采样，未放宽像素断言。合成图块不是实战指标，原始结果见同目录 `perf-comparison.json` 与 `perf-gpu-samples.json`。

**首轮发现与范围决定：** `PlayerHudBottomWidget` 的不透明底座覆盖逻辑 MP 区域（中心像素 alpha=255），现行层序要求 resources 位于 bottom 上方。把完整资源图面单独压到世界 backbuffer 后，未迁移的 bottom 顶层窗口会遮住 MP。真实底栏绘制回归 `ResourceOnlyFlatteningWouldPutMpUnderUnmigratedOpaqueBottomChrome` 已证明该覆盖，不以几何矩形相交代替实际像素。首轮因此撤去临时的普通候选自动接线，未交付双层正常游戏人验。随后用户明确授权资源＋底栏完整迁移及 Buff；当前四槽实现与底栏手势归属验证承接这一决定，不能用首轮双图块结果代签完整单元。

本机受控对照的动态图块阶段，测试进程 CPU 按单核口径约 7.83% → 1.96%，DWM 同一 3D 引擎样本约 14.2% → 11.7%；测试进程该引擎约 5.0% → 5.1%。静态图块 DWM 为 13.68% → 14.8%，没有支持静态收益。共 39 组 GPU 采样，保留零值；整数计数器、桌面其他负载、短窗口与合成图块限制归同目录 `review-result.json`。新路径动态相位的 native Present 次数略增，因此只称同刺激频率对照，不冒称同提交次数或实战净收益。

首轮冻结候选 `hop3` 绑定的双层 GPU 正确性 2 项及 ABBA 比较 1 项通过，候选 Core 与当轮测试 Core 字节一致；实际像素检查只覆盖自建窗口。随后撤销游戏自动接线、补上真实底栏遮挡反例的首轮源码全量为 6816 通过 / 14 条件跳过 / 0 失败，串行 marker 恰好一次；输入分类 94 项和文档巡检通过。`hop1` 的导出名称错误、`hop2` 构建期间测试输入变化、前两轮无效比较均保留。旧候选是冻结试验凭据，不能冒称扩面后的正常游戏候选。首轮成果保留在独立工作树；后续授权扩面已按文件核对并集成主工作区，保留覆盖前副本和全部失败记录，未提交/推送/正式部署。

**文档角色**：本批启动、输入与呈现优化的源码结论、候选验证和后续边界。既有统一输入阶段合同仍归[分阶段施工计划](统一合成与输入归属-分阶段施工计划-2026-09-22.md)。
**最后核对代码基线**：commit `37552a5974f714a528d0eb9844c3b4e80c2ed307` 加 `main` 未提交集成（2026-10-08）；原隔离阶段基线为 `2331d4a2492af2837614f2c603bf1fe7c2a18439`。
**授权范围**：用户已明确主工作区让出，授权仅集成本批改动并在 main 继续施工、自动测试及候选构建。不含 commit/push、正式 runtime 部署、真实存档试写或外部付费服务。历史会话与本文件不新增授权。

## 结论与优先级

测试员已确认使用固态硬盘，不能继续用机械盘假设解释卡顿。启动重复读取、低级鼠标钩子与 UI 线程耦合、未完成的呈现统一都值得高优先级处理，但目前不能把同一次事故直接归因为 MPO。平均 FPS、捕获帧率和最终提交节奏不是同一个指标。

| 优先级 | 工作 | 本批范围与后续边界 |
|---|---|---|
| P0 | 放轻启动校验 | 消除重复遍历，复用已验证且本次不消费的分块准入，保留实际执行/加载文件的完整性；SSD/HDD 冷热启动体验单独验收 |
| P0 | 明确鼠标钩子与系统输入风险 | 延后安装到消息泵已处理队列、隔离回调异常、拆分本地/下游耗时；专用线程迁移仍需输入归属合同和物理回归 |
| P1 | 统一呈现减少独立输出 | 先迁移非交互伤害数字并隐藏旧输出；HUD、PlayerInfo、光标与 Web 逐域迁移，不一次替换整套输入 |
| P1 | 启动任务错峰 | 帮助预热让出 Bootstrap 首次导航；后续按实测拆分任务初始化与资源准备，不在 UI 上堆积同步工作 |
| P1 | 端到端诊断与样本新鲜度 | 启动观察、旧 FPS 显示拒绝、256 次呈现环与性能日志归档；统计不充当物理显示回执 |
| P1 | 输入桥启动与窗口生命周期 | 分开记录本轮源窗口、宿主、root 和 broker 退出；嵌入失败与迟到回调的成功判定另行补门，不按同名进程自动清扫 |
| P2 | DRS/resize 尾延迟与回压 | 先对齐 HoldViewport、AS2 applied、重绘 fence、捕获与原生提交；有证据后再调整节拍或缓冲，不盲改 Forms.Timer |

AS2 GC、V8、资源首次加载、驱动首次着色器处理、温度/电源与安全软件仍是可能的独立因素。没有现场数据前不一起大改，也不把离线 HLSL 编译当作已经排除驱动开销。

## 启动校验

日常已安装 .NET 且固定 WebView2 缓存有效时，旧链为 Bootstrap 两轮 manifest、Core 独立一轮 manifest、固定引擎分块与完整解包树校验。基线 manifest 共 43 项、370841329 字节，分块 307996323 字节，解包树 701143409 字节。逻辑校验量约从 2121663719 降至 1442826067 字节，减少 678837652 字节，即 32.0%。这是文件字节遍历推导，不是 SSD 物理读取量或启动提速比例；OS 页缓存会改变实际 I/O。

- [bootstrap.cpp](../launcher/native/bootstrap/bootstrap.cpp)：已具备 .NET 时保留启动 Core 前的完整检查；需安装 .NET 时先检查再执行 installer/UAC；完整检查仍在 crash-dump 注册表配置之前。
- [FixedWebViewRuntime.cs](../launcher/src/FixedWebViewRuntime.cs)：仅从本进程实际 runtime 目录的 native 校验成功路径接收准入，并逐项比对嵌入 lock 的分块路径、大小、哈希和重复项。热缓存仍全量验证实际引擎；冷缓存或损坏缓存重新检查源分块后展开。开发直启没有准入时仍验证分块。
- 哈希采用顺序读取和复用 256 KiB 缓冲；不缓存文件 mtime、不改为抽样、不用大小代替哈希，不接受“上次通过”。损坏缓存仍保留隔离副本。
- `webview2.verify_tree`、`webview2.prepare_mutex`、`webview2.cache_verified` 分开记录扫描、互斥等待和准入复用。帮助预热推迟到 Bootstrap 首次成功导航后排队，不承担启动资格判定。

## 钩子调查与边界

[WebOverlayForm](../launcher/src/Guardian/WebOverlayForm.cs) 的 `WH_MOUSE_LL` 仍由主 UI 线程拥有；键盘钩子是另一条独立线程链，不能混称已经隔离。旧构造路径在消息泵开始之前安装鼠标钩子，本机旧日志可见约 2.49 至 3.23 秒窗口，这构成系统输入风险，但不证明测试员整段冻结全由它导致。

本批改为先排一个 UI 回调，实际泵到它后才安装；构造后直接 Dispose 不会安装。回调异常不逃入非托管 hook；错误计数有界，文件日志移到定时器合并写。开启有界诊断后分开 `hook_delivery`、`hook_callback`、`hook_chain`，避免把下游钩子耗时算成我方工作。

这不消除运行中主 UI 阻塞。Microsoft 说明低级 hook 回调投递到安装线程，超时可能被静默摘除，Windows 10 1709 以后最大超时为 1000ms，并建议专用线程或 Raw Input。不能靠非零 HHOOK 证明仍活跃，也不靠周期重装伪装恢复。[LowLevelMouseProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelmouseproc)

当前源码的钩子范围还包括：

| 入口 | 所有权与需要保留的边界 |
|---|---|
| `WebOverlayForm.CursorHookCallback` | 主 UI 泵；光标观察、菜单外点、tooltip 移动/滚轮与世界指针共同经过这里；滚轮和世界按钮有同步消费返回值 |
| `InputShieldForm.EnterTelemetryMode` | 原面板期独立鼠标 hook 已撤除；现复用关联 WebOverlay 的按下观察，仍仅统计，不声明消费；活性依赖同一 UI 鼠标 hook |
| `KeyboardHook.Install` | 独立线程消息泵；这不隔离主 UI 鼠标 hook，也不以线程独立证明从不超时 |
| `HotkeyGuard.Run` | 匹配父进程路径/MVID 的独立进程消息泵；不是主 UI 鼠标路径 |
| `Win32NativeInputFacade` | Agent native-input 子系统自己的观测线程和许可边界；本批未启动 actor，不拿其观察/重装能力替换普通游戏输入 |

消费委托并非都只是读取：菜单外点会立即 dismiss/cancel，pinned/dense 滚轮可能滚动并触发 repaint，tooltip 移动会启动 Forms.Timer；世界路径读 `WindowFromPoint`/前台并修改手势队列、geometry 与 epoch。现有“同步 O(1)”注释不是回调预算证明。这些调用不能原样搬到工作线程，也不能简单延后后再决定是否吞掉已经进入系统的事件。

下一阶段须把“同步消费判定”和“UI 执行”拆开：只向专用泵发布不可变的 exact owner/几何/代次快照，按钮边沿有界且不合并，移动 latest-wins；UI 不得被同步等待。世界拖拽、前台丢失、held button、tooltip pinned/dense 滚轮、HUD 透明孔洞、旧手势取消和队列溢出都要同时覆盖。直接把现有 UI 委托搬到后台线程不满足合同。本批没有重写业务输入、合成点击或盲重放未知投递。

## 输入桥启动故障跟进

用户另指定 Kimi Code 会话 `session_9b6040ae-b62d-481e-8c14-21328b13ee05` 后，读取原会话工具输出与当前源码，未执行该会话中的进程结束建议。原始证据可确认：2026-10-08 16:25:50 出现 `Broker exited before READY`，该会话观察到 PID 11976 的 `Flash.exe` 起于 09:28:26，查询路径为空，两种终止尝试均被拒绝。它没有采到该次 broker 退出码、实际 source HWND/PID/root 或进程完整性级别，因而不能把“提权 TestLoader 残留被误选”写成高置信根因。

当前 [ProcessManager](../launcher/src/Guardian/ProcessManager.cs) 保留本轮 `Process.Start` 返回的对象，经 GameLaunchFlow 交给 [WindowManager](../launcher/src/Guardian/WindowManager.cs)；后者在该对象上 Refresh 并读 `MainWindowHandle`，GuardianForm 与世界合成器复用同一 FlashHwnd。不是按名称全局挑任意 Flash 窗口。[Microsoft 的属性合同](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.mainwindowhandle?view=net-10.0)也将此句柄限定于关联进程。这反驳了原会话所假定的查找机制，但原故障装配与源码没有精确绑定，仍不据此宣称所有句柄复用、嵌入竞态或装配差异都已排除。

另外，`compile_test.ps1` 的 native 任务本就要求 CS6 编辑器 `Flash.exe`，冷启动可复用 `Highest` 的编辑器任务；名称、启动时间和访问拒绝均不足以判定测试播放器残留、确认其提权或授权结束它。当前只读查询已不见旧 PID，这也不是受控的“清除后故障消失”实验。

该 broker 是指定 Flash 线程的 `WH_GETMESSAGE`，不是前述主 UI 的 `WH_MOUSE_LL`；协议使用共享映射与窗口消息，不是 VSTest 的 TCP 回环。静默提前退出可以来自多条分支：code 3 为身份条件组，4 为进程打开，5/6 为映射或属性准备，7 **合并了 DLL 加载、导出查找和 hook 安装**，8/9/12 还有其他前置拒绝。无 stdout 不能推出 code 3，更不能推出唯一的 root 不匹配。[GetAncestor 的 GA_ROOT](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getancestor)沿 parent 链查根，并非进程身份或提权检测。

世界控制器在此桥 READY 后才创建世界 scene 与呈现会话。故此事故值得并入启动/输入生命周期治理，但目前不是 MPO 证据，也不能与 testhost 的 Winsock 10013 或测试员 SSD 卡顿直接合并归因。后续日志的另一会话存在 READY，仅证明那次成功，不代签原故障根因或“代码一定无关”。

本轮先补 [NativePointerBridge](../launcher/src/Guardian/WorldCompositor/NativePointerBridge.cs) 的实际消费者诊断：每次启动仅记录一次 source HWND/PID/TID、owner/PID、root、session 与解析后的 broker 路径，明确 `observationOnly=1`；退出时记录一次真实退出码、是否见 stdout 和 READY 行。未知退出码保留 `unknown`，不借哨兵 `-1` 假定 Windows 错误；READY 行不等于 shared mapping 校验或完整游戏验收。记录失败不改变准入、12 秒 deadline、取消、恢复/释放、投递或业务语义，不新增重试、哈希扫描、自动清扫或进程终止。

新增 21 个纯格式断言用例覆盖身份原值、未知/负值/各分支退出码和独立 stdout/READY 状态。最初仅以 exact SDK 10.0.300 编译通过、0 错误，不算通过回归；用户随后打开执行权限后，该组已真实通过，并纳入下文 main 全量回归。证据提取、编译和执行日志与 SHA-256 保存在 main 的 `tmp/startup-input-presentation/`，未更换正式 runtime；权限未变化期间未重复已知失败。

还发现相邻待修风险：`SetParentLogged` 仅落日志，调用方可继续走到 `FireEmbedResult(true)`；排入 UI 的最终嵌入回调也应重新核对 exact attempt/目标身份，而非只靠排队前状态。现阶段只记录源码风险，未证明原事故触发，待当前 main 执行门恢复后用失败与迟到回调夹具修补。诊断补齐不能冒称专用鼠标泵或交互统一已完成。

## 统一呈现不等于消除 MPO

现役世界粒子/天气/光照共享世界输出，不代表 Native HUD、PlayerInfo、伤害数字、光标及全部 Web 面板已经只剩一个呈现根。帮助与部分过场的统一宿主也只是各自试点。DirectComposition 的树仍进入 DWM；单 HWND 多 visual 减少窗口协调，不保证单一交换链、独立翻转或 MPO 消失。这是架构边界，不是对本次事故的 MPO 诊断。[DirectComposition 架构](https://learn.microsoft.com/en-us/windows/win32/directcomp/architecture-and-components)、[呈现与 MPO 术语](https://learn.microsoft.com/en-us/windows/win32/comp_swapchain/comp-swapchain-glossary)

本批在同一世界 HWND 建立 `CompositionSceneHost`，经新增 `ProbeStartWorldVisual` 绑定原生世界 visual，再接入非交互伤害数字。既有 ABI 12 记录和 scene ABI 1 不变。数字只上传可见实际区域，保留原始 DIB stride 和量化增长容量，缩小以 clip 排除旧像素，不构造整屏 CPU 合成。共享路径可用时旧数字窗口不显示；超过原生 extent 上限时有明确 legacy fallback 日志。数字不接受世界调色，AS2 玩法、数值与存档权威不变。

场景释放前先撤数字所有权，停止原生工作线程后释放 scene。清除失败的重入回调不能重新采用已退休场景。原生绑定首次就绪提交一次 scene；数字更新自行提交，空闲 UI tick 不重复提交无变化的树。后续交互 HUD/Web 扩面仍走各域 hit-test、输入和生命周期合同，不能据此宣称全应用统一完成。

后续收紧了原生模块归属：`CompositionSceneHost` 不再按 DLL 基名隐式查找，而是实例持有绝对路径模块及其导出；世界与夹具传同一精确路径，帮助默认使用 app-local 模块，C1 捕获的三个委托也从该 scene 所持模块取得。相对路径、缺失模块、缺少导出均拒绝，不向别处借同名 DLL；先停止捕获、销毁 scene，再释放模块，销毁失败不卸载仍可能拥有对象的代码。已有线程所有权不变。这是加载与生命周期防护，不作为卡顿或 MPO 根因结论。

该跟进的 focused 回归为 17 项通过、1 项亮屏资格跳过，包含同名模块不可借用、错误线程拒绝、快照/呈现委托参数及释放后的调用拒绝。一次扩展夹具误把 `ProbeStartVisual` 的异步构造句柄当作同步出帧资格，失败保留；修正为无论源有效与否都先停止返回的句柄，再释放 visual/scene。该轮使用新 Host 测试装配与旧 `sip3` 原生模块，只证明对应接口；新的 Host 必须另建候选，不能继续把 `sip3` 标成当前源码构建。

模块绑定跟进的普通 Release 全量回归为 6742 项通过、11 项条件跳过、0 失败，串行 runner 标记已核对。其新候选按独立 leaf 构建，不能覆写旧 `sip3` 或由这项防护外推鼠标专用泵、MPO 或完整 C1 旅程已经验收。

跟进候选 `tmp/runtime-candidates/v2/sip4` 已完成构建、43 项 integrity-only 核验、原件/改坏 Core 副本/原件复验，以及同候选原生模块的 17 项 focused 检查；持续资格 1 项仍因熄屏跳过。该阶段收口时运行源码 identity 与候选一致，policy hash 也一致，但没有签名共识或 strict 发布回执。C1 薄外壳 `C1IslandHost.csproj` 另行编译通过（0 错误），未运行 Flash actor 或真实输入。随后输入夹具依赖修补改变了 Core 装配输入，`sip4` 保留为上一阶段证据，不再声称它对应当前源码。

## 输入夹具依赖跟进

准备后续输入施工时重新编译 G1 与 Flash hover，两个旧的生产源码逐文件链接清单均报依赖缺失，包括 `BulletVisualCatalog`、`RayVisualDrawFrame`、`WorldRasterPresentation` 与 `SceneLightSnapshot`。失败日志保留，不用历史成功回执填补。

两工程现改为直接引用当前 Core，与 C1 的薄外壳方式一致；Core 仅授予确切的夹具程序集 internal 访问。G1 runner 同时由筛选少量文件改为复制完整托管输出，避免编译成功却遗漏 Core DLL。两入口新增显式 `ManagedBuildOnly`，使用 exact SDK、每轮唯一目录，并在启动 actor、复制输入代理或改变运行环境之前退出。hover 的该模式不要求 SWF，不触发 CS6。

两个只构建入口均为 0 错误，依赖清单指向 `CRAZYFLASHER7MercenaryEmpire.Core` project，实际 Core 文件哈希相同，未暂存 `FlashInputBroker.exe`。项目引用与精确 friend assembly 新增普通回归。这只恢复了编译和托管依赖基础，不证明 G1/Flash actor、物理输入、专用鼠标泵或现役游戏通过；本轮未执行 actor、注入输入或修改真实存档。

本阶段 focused 为 11 项通过、1 项候选模块条件跳过；普通 Release 全量为 6746 项通过、11 项条件跳过、0 失败，实际串行 marker 已核对。新增 4 项普通回归检查三工程的确切 Core 项目引用、禁止重新链接生产源码和三份精确 friend assembly；只构建 runner 另经 PowerShell 语法解析和实际隔离输出检查。失败原件、编译日志和依赖哈希都留在同一接续目录。

源码冻结后另建 `tmp/runtime-candidates/v2/sip5`，没有覆写 `sip4`。`sip5` 为 `candidate_built`，43 项 integrity-only 核验通过，原件/改坏 Core 副本/原件复验的退出码为 0/2/0；未启动完整游戏。该阶段源码 identity、候选 build identity 与 payload closure 已核对；测试、G1、hover 及候选的 Core 字节哈希均为 `B5A6D2DB7ECD440794959890E3A7C38C383A907197FBA11599C0F6DD30E4C87A`。同候选原生模块的绑定、像素及相关 focused 为 17 项通过、1 项持续资格因 session display Off 跳过，未修改阈值；policy hash 对照一致，runtime 输入分类 94 项通过，但没有 strict 签名共识或部署结论。后续以接续记录的 `continuationCandidate` 和该目录机器 metadata 为准，身份未变化时不重复构建或重跑同一熄屏实验。

## 共享鼠标观察跟进

输入夹具阶段之后，先在未改源码的 `sip5` 上完成亮屏持续资格，结果见下节。随后将 InputShield 的纯观测统计接入既有 `WebOverlayForm.SetInputShield` 所关联实例，撤除第二个 `WH_MOUSE_LL` 的安装、回调、解包和摘除；不新增观察服务或另一条工作线程。原 foreground 精确 HWND/子窗口过滤、anchor/panel 边界及四类 button-down 判定不变；移动、Up 与滚轮不计入。刷新保留本轮计数，退出后不再计数，重新进入清零；已销毁对象不能重开观察。

观察调用在 NativeInteraction 按下回调和世界路由之前，独立隔离异常，不声明消费，不替换滚轮或世界的同步返回值。关闭面板的 mask/capture 清理和原业务输入权威不变。生命周期日志以 `source=shared_cursor_hook` 标识新来源；观察现在依附主鼠标 hook 的注册次序和活性，不保证与历史独立 hook 取得相同事件集合，零计数仍不能证明没有外点或钩子活跃。

新增 8 项普通回归直接调用托管回调，不安装未泵 hook、不移动光标或向 OS 注入输入；覆盖四类按下、非按下拒绝、刷新/退出/重开/解绑、销毁后拒绝和 NativeInteraction 异常不阻断世界路由。结合既有滤镜、tooltip、NativeInteraction、世界指针及 panel close focused 共 182 项通过。主鼠标 hook 仍归 UI 泵，专用泵尚未实施；本次减少重复全局 hook，不宣称运行中 UI 阻塞风险已消失。此阶段改变了运行源码，`sip5` 的持续资格保留为它自身的证据，后续冻结后须另建候选。

该阶段普通 Release 全量回归为 6754 项通过、11 项条件跳过、0 失败，实际串行 marker 已核对。冻结后独立构建 `tmp/runtime-candidates/v2/sip6`，43 项 integrity-only 与原件/改坏副本/原件复验的 0/2/0 正负控通过；测试、G1、hover 与候选 Core 字节一致，当前源码/build identity/policy 对照一致，runtime 输入分类 94 项通过。两个输入夹具仍只运行 `ManagedBuildOnly`，未执行 actor 或注入输入。

`sip6` 精确原生路径的绑定、像素、持续资格及共享观察相关 focused 为 26 项通过、0 跳过、0 失败。资格前后均只读观测 On，原断言未改；UI 停泵期间原生线程继续推进，最终 Presented 275、计时环 Count/IntervalCount 256、FreshCount 205，间隔 P50/P95/P99 为 31.87/45.72/48.07ms，Present 调用 P95 约 0.195ms。实际模块、identity/closure 和 Host 装配路径绑定于 `sip6-qualified-focused.log`。这是同候选的有限原生窗口实验，不是物理 scanout、面板手感、长时战斗、完整游戏或正式 runtime 验收。

## 观测与验证

`InputLatencyProbe` 沿用 `CF7_INPUT_LATENCY=1` 加焦点录制的精确开关，启动窗口至多 30 秒，转场保留既有上限和 2 秒尾窗。UI ping 始终最多单飞，每窗最多 64 条尖刺，其余计数/峰值汇总；不注入输入或自动修复。FPS 样本超过 2 秒或场景重置后，Notch 显示 `--`，历史缓冲不抹掉。

原生 `ProbeGetTimingStats` 是独立可选诊断扩展，固定保留最近 256 次成功提交。连续帧间隔、submit、Present 调用和 fresh-source age 分别统计，主动静止/停捕获/hold 断开连续间隔，不把合法静态画面算作卡死。焦点录制开启时每秒采样一次，附场景、源帧龄、最后提交龄和数字上传量；不触发 GPU 回读。Present 调用返回与 DWM/显示器实际呈现保持区分。

退出冻结快照现在包含 `perf-latest.jsonl`，立即重开不能用新运行覆盖旧包。字段和冻结行为与实际 profiler/ETW 互补；现有采样脚本若只在起点枚举 PID，不能用于证明后启动子进程没有负载。

候选检查必须记录实际 native 模块路径/哈希、Host 测试装配、identity 与 closure。共享 GPU 夹具只创建自己的窗口，像素资格、旧/共享静态源观测、亮屏动态源与计时环资格分别记录；入口见[开发 README](../launcher/perf/flash-compositor/README.md#共享数字层与呈现诊断)。第一次夹具 DPI 不一致及第二次对静态源的错误预期保留为失败记录，修正条件后通过不覆盖失败原件。

2026-10-08 的 `sip3` 已完成候选构建、原生 verifier 正例、独立副本改坏 Core 的拒绝负例和原件复验；正式 runtime 的 45 项快照未变。UHD 630 上共享像素检查通过，原画与清除后的回读哈希一致。扩展持续帧测试曾失败：静态与动态源均观测到约 200 至 250ms 的 Present 等待；停用额外 WGC 观察器、窗口置顶、逐次 scene Commit 都未消除。旧独立世界路径与新共享路径的同条件对照也均出现该等待，不能据此裁定共享回归或 MPO 根因。

随后只读 Windows 电源通知明确给出当前 session 和 console 显示状态均为 Off，未注入输入或唤醒屏幕。持续呈现资格现要求显式 On，像素测试仍可独立运行；本轮为像素/静态观测 2 项通过、持续资格 1 项因熄屏跳过。该条件不把先前失败改写为通过，亦不证明熄屏是全部等待的唯一原因；须亮屏后在同一候选复跑 UI 停泵、动态源及 256 项绕回检查。后续调度保留原始失败和负控，不改变系统电源设置。

显示状态枚举与注册后立即返回当前值的语义分别依据 Microsoft 的[电源设置 GUID](https://learn.microsoft.com/en-us/windows/win32/power/power-setting-guids)与[通知注册 API](https://learn.microsoft.com/en-us/windows/win32/api/powersetting/nf-powersetting-powersettingregisternotification)。未知状态不当作 On，亦不以耗时大推断显示状态。

2026-10-08 08:34 UTC，Windows 只读通知明确返回 session/console display On；未亮屏或注入输入。先复核未改动的 `sip5` 源码 identity、metadata、Core 哈希和 integrity-only，再原样运行 `SharedRoot_AnimatedTimingRingWrapsWithoutUiPresentationPolling`，1 项通过、0 跳过。UI 停泵期间原生线程推进断言通过，动态源 270 轮完成，最终 Presented 275、计时环 Count/IntervalCount 均为 256、FreshCount 224。该样本间隔 P50/P95/P99 为 34.26/42.80/47.39ms，Present 调用 P95 约 0.213ms；不是物理显示延迟或游戏帧率承诺。

同一候选的旧/共享静态对照随后各观察 6 次，均推进；本轮 Present 调用范围分别为 0.107–0.236ms 与 0.100–0.364ms，后续只读观察仍为 On。旧熄屏失败与负控全部保留，亮屏通过不抹除它们，也不把本机条件差异外推为测试员的 MPO 根因。证据为 `sip5-sustained-display-on-01.log` 与 `sip5-legacy-shared-display-on-01.log`；实际模块、identity/closure 与 Host 装配路径均在日志中绑定。没有完整游戏、物理输入或 scanout 验收。

首批普通 Release 回归为 6738 项通过、10 项条件跳过、0 失败，runner 的串行标记已核对；runtime 输入分类 94 项通过且未创建签名或证书。文档巡检通过，历史链接债务和 README 行预算仍为非阻断提示。候选 `tmp/runtime-candidates/v2/sip3` 的运行源码 identity 在该批收口时与构建一致；测试补充改变了 policy hash，不冒认候选已通过当前 strict 发布政策。后续模块绑定改动另建候选，不沿用这一源码一致结论。详细日志、identity 对照和原始失败统一保留于独立 worktree 的 `tmp/startup-input-presentation/`。

本批自动验证不能代签测试员机器、SSD/HDD 冷热启动体验、真实拖拽与滚轮、视觉接受、多显示器/不同 DPI/弱 GPU、驱动 MPO 路径或完整游戏旅程。构建属于 `candidate_built`；隔离 native 夹具不升级为整套游戏 `candidate_executed` 或 `e2e_verified`。没有 `promoted` 或 `standard_entry_verified` 结论。

## 主线集成

用户明确反馈“工作区已经让出，可以迁移到main继续施工了”后，重新读取 main：HEAD 已前进至 `37552a5974f714a528d0eb9844c3b4e80c2ed307`，包含漫画、礼包配给、书架与执行总控四个提交，工作区当时干净。释放依据是这条直接授权，不是干净状态或聊天 idle。

对比原基线、隔离工作树增量与新 main，43 个任务路径中仅 Program、WebOverlay 和 README 与新提交重叠。前两处任务修改不覆盖新加入的 `reducedPresentation` 偏好及其推送接线；README 将启动/呈现诊断说明与新偏好注册表手工合并。其余任务增量按原包应用，应用前文件及三方身份留存在 main 的 `tmp/startup-input-presentation/main-integration-preflight.json` 和同目录备份，未复制整份 Program/WebOverlay 覆盖新提交。

当前 main 集成后的交叉回归与候选资格需重新取得，不能借原 worktree 的 `sip6` 代签新源码。原 worktree、失败记录与候选继续保留，未归档或删除；接续记录迁至 main 的同名 `tmp/startup-input-presentation/`，旧目录是历史源，不再作为当前施工位置。不自动 commit/push 或部署。

迁移后的独立三方重建与实际结果逐文件一致，43 个任务路径之外无修改，index 未暂存。第一次临时比对混用 Git 导出的 LF 与工作区 CRLF，误报冲突；仅将临时输入规范化后，Program、WebOverlay、README 三项重建均为 0 冲突并与实际集成一致，原失败和输入副本保留，未为此重写生产文件的换行。

漫画 player、书架 runtime/original、物品使用、奖励包与 panel contracts 六组脚本交叉检查通过，文档巡检及 whitespace 检查通过。受限执行环境将 `LOCALAPPDATA` 重定向，默认 resolver 仅找到 .NET 8；既有 `C:/Users/fs/AppData/Local/Microsoft/dotnet/dotnet.exe` 实测为 10.0.300，仅对验证进程 PATH/运行时根绑定后，原 exact resolver 与当前源码编译通过，未改 `global.json` 或安装 SDK。

C# 执行门最初未通过：定向回归在测试宿主连接阶段按原 90 秒超时中止，未进入测试执行；保留日志后另做最小诊断，testhost 记录本机 `127.0.0.1` 通信的 `SocketException (10013)` 访问拒绝。这不是某条测试断言失败，也不以增大超时、换测试框架或旧 worktree 绿灯代替当前 full Host。当时自动续接提示的迁移更新也被工具策略拒绝，主接续文件已在 main；用户随后打开权限后，主线回归及提示迁移均已恢复，结果见下一节，旧失败不删除。

`sip7-main` 的首次仅构建尝试在 `sol_parser` 原生阶段失败，保留失败目录及 `candidate-sip7-main.log`，没有完成 metadata/closure，不属于 `candidate_built`。原 producer 会清理临时 job，外层未留下该阶段完整输出；另以相同 pinned 环境单跑失败组件收集输出，捕获 Cargo 创建其临时 target 目录时 `os error 5` 拒绝访问，记录于 `main-sol-stage-diagnostic.log`。该补充诊断不冒认原尝试的全部根因，也未改源码、缓存路径规则或正式 runtime。随后权限恢复后另建新 leaf，没有覆写失败 leaf 或转用旧 `sip6` 代签。runtime 输入分类仍为 94 项通过，未创建签名/证书；主线集成包及其后加入 broker 诊断的增量包均保留，当前范围与哈希读 main 的 integration manifest，未暂存或提交。

## 测试环境恢复与人工准备

用户明确要求先打通测试、推进到人工可测阶段，并打开当前聊天执行权限。只读观察显示命令已从 Low Mandatory Level 与沙盒 TEMP 重定向切换到 Medium Mandatory Level 和正常用户 TEMP；未关闭防火墙、修改 ACL、安装服务或改变全局 SDK 配置。使用原 exact SDK、原 runner 与原 deadline，最小 broker/FPS 回归 23 项真实通过；main canonical 全量为 6792 项通过、11 项条件跳过、0 失败，实际 `parallel test collections = off` marker 恰好一次。日志为 `main-host-unrestricted-focused.log` 与 `main-unrestricted-full-host.log`，旧 10013/90 秒中止记录继续保留。

这是当前执行环境恢复的对照，不是精确指认某条 Windows 防火墙规则、Cargo 原失败的唯一原因或测试员机器根因。新的 native 候选必须独立构建，不能覆写 `sip7-main`、借 `sip6` 或只拷新 Core 到旧 runtime。配套原生构建、identity/closure、完整性正负控、精确模块及显示状态合格的持续资格，以 main 接续记录和该候选 metadata 的实际结果为准；这些门未完成前不报告人工可测。

本阶段的新隔离候选已达到本批人工可测条件：既有开发入口 `BuildOnly` 完成配套原生与 Core 构建、43 项 integrity-only，原件/改坏 Core 副本/原件复验退出码为 0/2/0；源码及 policy identity 与 metadata 一致，测试、G1/hover 只构建输出与候选的 Core 字节一致。精确模块、像素与持续资格为 8 项通过、0 跳过、0 失败，前后只读显示状态均为 On，原断言未改。动态源原生 Presented 275、计时环 Count/IntervalCount 均为 256，像素清除后的哈希回到原画；旧与共享静态对照各 6 次推进。当前候选名和身份归 `state.continuationCandidate` 与 metadata，具体结果见 `human-test-ready.json` 和 `sip8-main-module-pixel-sustained.log`，不作为固定入口配置。

根开发入口的 `-Status` 已实际报告 `ready`，选中该候选且同身份 payload closure 唯一；正式 runtime 未修改。没有启动完整游戏、Flash actor 或注入物理输入，没有真实存档试写，未完成 strict 签名/推广。`candidate_built` 加有限窗口专项资格，只表示可以开始本批人工验收，不升级为完整游戏 `candidate_executed` / `e2e_verified` 或 MPO 已解决。

机器门完成后的人工入口沿用主工作区根 [本地开发启动.cmd](../本地开发启动.cmd)，交付前用同一入口的 `-Status` 核对当前身份与选中候选。需要有界启动/转场输入计时时，复用既有 [diagnose-input.ps1](../automation/diagnose-input.ps1) 的 Native 模式临时启用诊断；不改 `config.toml` 默认值，不新增专用快捷方式，不由 Agent 启动真实存档旅程。

首轮人工只合并为三个短检查：

1. 正常退出旧游戏，再从开发入口启动并进入世界，留意启动时系统鼠标是否卡住、首次画面是否正常；有条件再重复一次热启动，不要求清空引擎缓存制造冷启动。
2. 在世界进行连续点击、按住/释放和滚轮操作，打开/关闭一个常用 HUD/Web 面板并切出切回，检查外点、滚轮、焦点与取消没有错投或卡住。
3. 观察有伤害数字的场景，确认无旧像素残留、数字遮挡或画面停住；正常退出。异常时保留时间点及既有日志，可用根 [收集焦点诊断日志.cmd](../收集焦点诊断日志.cmd) 取包，不反复重放失败业务动作。

这轮验收范围是已有启动减负、hook 安装时序/重复观测治理、共享伤害数字与诊断，不是专用鼠标泵、全部 HUD/Web 统一、MPO 根因或消除保证。真实玩家是否进行存档/战斗由其人工操作决定；Agent 不试写真实槽位，机器资格也不代签人类手感、视觉、多显示器或弱机器接受。

## 首次人验日志复核

用户反馈“稍微玩了一圈，未发现明显问题”后，只读核对 2026-10-08 22:03:30 至 22:08:22 的本轮日志，约 4 分 52 秒。实际 Core 和 broker 路径均为当前新候选，原始 launcher/bootstrap/perf 日志已按 SHA-256 稳定复制到 main 的 `tmp/startup-input-presentation/human-smoke-20261008-220330/`；分析结果为同目录 `review.json`。没有再次启动游戏、试写真实存档、修改运行代码或重建候选。

启动、输入桥、呈现与退出链没有失败终态：broker 在约 100ms 内 READY，观测的 sourceRoot 与 owner 同为 `0x4088A`；7 次转场都有 revealed，79 个 render command 均找到对应 applied。Flash 正常退出 code 0，broker code 0、`confirmed=True`。退出时 `returned=0/unhooked=0` 与 `targetExited=1` 同时出现，按现有 exact-target-exit 合同完成关闭，不按两个零值误报残留。最后 consumedSeq/completedSeq 同为 1184，只是序号水位一致，不等于全输入链零丢失；`stale=13/invalid=0` 也不能在没有逐包 trace 时逐项代签。

发现一项明确的展示契约缺口：22:07:27 的 3 条开箱装备播报使用 `source=map_chest`，22:08:13 的 1 条结算材料播报使用 `source=stage_settlement`，均被 [LootFeedTask](../launcher/src/Tasks/LootFeedTask.cs) 的 v1 source 白名单拒收，日志为 `invalid v1 source, dropped`。这两个真实生产来源未列入 `AllowedSources`。该消费者只投影已提交事实到 NativeHud，与地图 `loot_response`/资产写入域不同，合同见[物资事务 ADR](玩家物资事务与双向播报-ADR-2026-08-22.md)；对应业务有 commit/shadow 日志，但本次没有读取或试写 SOL 来代签耐久。不能据播报丢弃推断奖励丢失，也不能盲目补发奖励。该问题未在本轮修复，应以精确来源合同及生产 payload 回归单独处理，不通过接受任意来源或 legacy 降级掩盖。

仍应保留的非阻断性能观察：

- 热引擎全量核验 257 文件/701143409 字节耗时约 2007ms，仍是启动减负空间；没有同条件 A/B，不能据本轮数值宣称确定提速比例。
- 10 次面板关闭最长约 503ms，map/stage-select/tasks 的较慢个例约 442–503ms；27 次焦点恢复最长约 390ms，是后续 UI/输入交接的实际热点，不把嵌套 scope 耗时相加。
- 可调度 `gate=ready` 样本的最大 AS2 帧间隔为 529ms；7 次转场约 2.2–5.7 秒，末次为 5696ms，其间有 `gate=surface` 的 2844ms 帧间隔。记录为尾延迟与转场优化线索，不仅因用户未感知就删除，也不将暂停/载入一律算战斗 FPS 或 MPO。
- 原生世界日志共 227 个抽样，Present 调用 P95 约 0.314ms、最大 1.55ms；未看到先前实验的 200–250ms 级 Present 等待。它不是全帧分布、物理 scanout 延迟或排除 MPO 的证据。源静止/暂停时的 `stalled` 和较大源帧龄需结合场景，不直接判 GPU 卡死。

`cursor.hook_start_queue` 约 1934ms 是安装前等待 UI 消息泵的时长，不是已安装 hook 回调阻塞 1.9 秒。普通 `UiFreezeProbe` 仅记录了启动，没有告警；其 stale 阈值为 2000ms，并不能排除上述亚秒尾延迟。本轮没有详细 FocusTrace/InputLatency 数据，属于用户短实玩正向反馈加日志复核，不替代完整物理输入矩阵、跨显示器/弱机或根因验收。当前候选继续保留，不由这条反馈自动授权发布或额外功能施工。

## 合并发布授权

用户随后明确要求无人值守完成拾取播报，并与完整的云端共识、构建、部署、推送发布列车合并执行。本阶段授权包含本批启动、输入、共享伤害数字及精确 `map_chest` / `stage_settlement` 来源兼容的提交与正式发布；此前各阶段的无提交、无部署记录仍是当时事实。先保留已验证增量，再合并最新远端主线，重新验证最终树并创建新 immutable request，不能借旧候选代签。

授权不包括奖励补发、真实玩家存档试写、凭据导出或安全策略调整。发布和云端共识仍不代签专用鼠标泵、完整 HUD/Web 统一、物理输入矩阵、弱机器体验或 MPO 根因；当前正式列车的身份、请求、失败及晋级状态以 main 的 `tmp/startup-input-presentation/state.json` 和相应机器材料为准。

已验证的 45 路径增量以 `60c3d33b98` 保留，再合入远端装备与资源更新 `d3c4d3d410`，无路径重叠或冲突，既有 AS2/SWF 保留。随后只在 Host 补齐两个真实来源，并统一使用开箱奖励的 guaranteed 保留策略；没有改资产权威、AS2 或真实存档。生产形状的 4 条 payload、精确来源负例、重复/冲突重放与饱和排队纳入回归，修复前 12 条失败，修复后播报相关 162 条全部通过；首轮夹具误用不存在的模型方法导致的编译失败也保留，未用它冒称行为负控。

新源码已超出首次人验候选，后续正式产物须取得本轮请求和共识。发布前只读观察显示屏幕 Off，不自动唤醒、不改原持续资格断言；旧候选的持续资格继续是其自身证据，不改签给新 identity/closure。完整机器供应链与政策验证可继续无人值守，玩家播报视觉、物理矩阵和 MPO 仍保留人验边界。

合并与修复后的 canonical 全量 Host 为 6810 项通过、11 项条件跳过、0 失败，真实 serial marker 一次。首轮 release prepare 重新派生全部资产后，仅 `launcher/data/save_repair_dict.json` 因远端新增装备/发型而与旧 tree 不符，按原门禁失败关闭；将生成器的语义增量纳入本批，再对最终提交树复跑，不手工改字典或读取玩家存档。prepare 的 npm 审计提示保留，不自动升级依赖或执行强制修复。

首趟 v1 已推送源码 `682c01bef3` 与一次性 tag，取得本地 X509 candidate；final-tree Host 仍为 6810/11/0，测试与候选 Core 字节一致。production policy 47 项中有两项真实失败：材料索引 sidecar 仍绑定旧的 items/crafting list 字节，商店头像凭据仍绑定 CRLF shop list，而 Git canonical source 为 LF。未触发云端、未替换正式 runtime。v1 tag/request/candidate/失败 receipt 与源副本保留，不能覆写或转称成功。

材料 sidecar 由原生成器重生，运行字典 XML 字节未变。商店清单由当前 LF 精确还原 CRLF 后，大小 1519 与旧 SHA-256 完全吻合；新增显式 opt-in 只允许这种逐字节等价证明，默认仍拒绝 list 漂移，身份/顺序/数量/排除项/路径/内容/其他空白/反向与混合换行负例均保留。刷新仍复用完整渲染输入、工具、图片与 receipt validator，按原生成器更新商品来源与凭据，不改验证器或放宽断言。7 组纯字节回归通过，首次夹具将“未变 CRLF”误当成逆向转换的失败记录保留；37 个画像入口/36 个 subject 文件及 runtime manifest 均通过现有资产门，36 张图片和 manifest 的逐项哈希与原件一致。后续使用全新的 v2 tag/request 和政策回执，不借 v1 失败列车代签。

字典构建工具的锁定开发依赖审计另保留 9 项告警（含 2 项 critical），不新增游戏运行依赖；本轮未启测试 UI/dev server，也没有强制依赖升级。该维护债不以本轮供应链门通过宣称已解决。

## 本批正式部署

2026-10-09，本批 `map_chest` / `stage_settlement` 播报兼容与已有启动、输入观测、共享伤害呈现优化已由唯一 promotion writer 正式安装。冻结 source 为 `58324fa0724ff279fb0dc72bbca3d67e027ad14a`，一次性 tag 为 `runtime-build-v2/20261008-startup-input-lootfeed-v2`；request、release tree、build identity、payload closure 和内嵌证明以当前 signed consensus 为机器真源。

v2 final-tree Host 为 6810 项通过、11 项条件跳过、0 失败，serial marker 一次，测试 Core 与候选 Core 字节一致。新 production receipt 47/47 通过。v1 到 v2 只有 policy 域变化，artifact/recipe/toolchain 三域与 build identity 不变，因此按现行协议复用有效的本地 X509 producer result 与 CAS 字节，重新绑定新 request 和政策回执；不复用失败的 v1 policy receipt。云端从 v2 tag 独立构建并签名，[本次唯一云端 run](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/37803316026) 的 build identity 和完整 payload closure 与本地全等。

GitHub API 的临时 EOF 使首次监控客户端中止，后续只观察并 Resume 同一 run/attempt 1，没有重复 dispatch。规范 helper 已完成证明验真；临时接续脚本曾误要求 CAS 中存在 producer metadata，按协议 CAS 只保留 payload，最终改读真实 producer result 完成比对，没有补造 metadata 或修改正式验证器。所有中断日志、v1 失败 receipt、两个不可变 tag/request 和原字节副本继续保留。

promotion 完成双 signer/双 faultDomain 的 strict replay、staged/live payload 复核及正式 bootstrap `--verify-only` 完整安装核验，保留可恢复 previous bundle。实际更新仅根 bootstrap、Core、世界呈现 native DLL、runtime manifest 和 signed consensus 五个部署路径，没有手工把开发候选拷入正式目录。部署提交、推送与远端 Audit 结果由本节后续记录及 main 接续文件保存。

该状态是 `promoted`，不是新发布程序的完整 `standard_entry_verified`：Agent 没有启动游戏/Flash actor、回放奖励或试写真实存档。新播报的实际视觉、物理输入与弱机器/MPO 专项仍待人验；专用鼠标泵、全部交互 HUD/Web 统一及嵌入迟到回调等后续风险未被本批冒称完成。旧候选的持续资格不转签给新 identity/closure，夜间未唤醒屏幕或放宽断言。

部署提交 `0a2c92671f04aa980f2c7782df23715a114295a0` 已正常推送 main；提交后的本机 standalone strict replay 通过。[首次远端 Audit](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/37806299272) 成功，日志明确为 `state=promoted`、`deploymentChanged=true`、`signers=2 faultDomains=2`，不是仅 source-ahead 或跳过检查的绿灯。最终提交树、远端 HEAD、正式 Core 和保留回滚位置记录于 main 的 `tmp/startup-input-presentation/release-final-result.json`；后续只读核对真实新增日志，未收到下一阶段反馈前不继续扩功能或重建不变产物。
