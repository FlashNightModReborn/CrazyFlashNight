# 世界光照捕获合成：开发入口与验证边界

当前范围：默认捕获合成、AS2 世界光照卸载与首版动态分辨率；字体外观获维护者确认，换档恢复/交接已完成本机开发构建回归。2026-09-22 已完成配套 runtime 发布，普通入口已覆盖现有角色进游戏、合成/输入桥启动、设置同步与 Esc 返回、窗口退出；实际部署身份与结果以 [发布记录](../../../docs/runtime-build-reproducibility.md#release-protocol) 和机器 manifest/consensus 为准。AS2/SWF 与 Host 必须配套使用；不要用旧 Core 验证新版 asLoader 的光照。其他机器的画质、输入与长时稳定性不能由本机结果代签。

2026-09-22 下一阶段顺序评估：保留当前成果，优先把统一显示与统一输入归属一起设计，再接入粒子并研究天空/地图拆分。增量成本、接口边界和人验节点见 [渲染 ADR §7.2](../../../docs/launcher-渲染架构-长期决策-2026-05-21.md#72-2026-09-22统一合成与输入优先的顺序评估)。这是后续提案；本原型仍有独立输出/HUD/WebView2 窗口，未实现统一焦点权威。

## 启动

### v4 输入会话开发候选

当前输入桥工作区支持有界会话与配对续接；这是未发布施工，不能继承页首既有 runtime 发布结论。
R4 配对 Host 另要求 native 的 `ProbeGetCaptureSize` 扩展（WGC 尺寸及 capture generation）；原 ABI 3 Stats 布局不变，但不能混用缺该导出的旧 DLL。非客户区状态变化只重建 WGC 会话，保留输出窗口和输入桥；`world_compositor_capture_generation` 包含初始创建/恢复/非客户区重建，不能当作输入会话续接次数。
原生夹具及边界验证见 [G1 入口](../../native/world-compositor/g1-fixture/README.md)，状态见[施工计划](../../../docs/统一合成与输入归属-分阶段施工计划-2026-09-22.md#11-续接记录当前唯一状态)。

带采集的普通上限验收入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/perf/flash-compositor/collect-game.ps1 -CandidatePath <repo下tmp内的配对候选目录>
node launcher/perf/flash-compositor/analyze-input-trace.cjs <launcher.log> <pointer-observed.json>
node --test launcher/perf/flash-compositor/analyze-input-trace.test.cjs
```

采集入口启用 FocusTrace，等待实际游戏退出，按精确候选路径及新鲜进程时间核对 recording-context 后才复制日志；每轮写入独立 `tmp/world-input-run-*`。本入口使用普通输入上限，小 cap 续接压力测试继续单独运行。诊断分析按 session/sequence 连接 Host 投递与端点进入/返回/拒绝，保留独立的 panel_request 列表；没有 AS2 释放目标的因果身份时不自动关联为按钮成功。

`build-game.ps1 -OutputRoot <仓库 tmp 内新目录> -NativeRoot <已构建的三模块目录>` 可保留旧候选并生成独立配对；省略参数保持原开发入口。
`run-game.ps1 -CandidatePath <该目录> -FocusTrace -InputSessionTestCap 8` 核验配对后启动、启用本进程焦点采集并加速输入续接。
`InputSessionTestCap` 默认 0（使用生产上限），非零须为 8…8388605；仅 `tmp/` 开发候选识别 `CF7_INPUT_SESSION_TEST_CAP`，正式 runtime 不采用此覆盖。
它不改 config.toml 或存档；环境值在脚本结束时恢复。小 cap 是实验刺激，不能把该模式下的次数写成默认生产频率。

### G2 内容证据补证入口

`powershell -NoProfile -ExecutionPolicy Bypass -File launcher/perf/flash-compositor/test-g2.ps1`
按已有默认 5 秒相位串行运行单适配器正例、F 冻结、全部源冻结、误捕获 P 和真实 Flash 素材；支持 `-Adapter intel|nvidia`、`-SkipBuild`。
它保留原计数门槛；旧 `test.ps1` 矩阵仍可使用。未测/没有内容变化证据不能算通过。
原生旧 ABI 3 结构保持不变，G2 开发探针额外要求配套的 `ProbeRequestContentProof` / `ProbeGetContentStats` 导出。

- `run.ps1 -Topology embeddedF -Auto -StallF`：仅冻结本轮 fixture F，S 状态栏与 P 继续刷新，再恢复 F；停推阶段必须判败，恢复阶段必须有内容与输出对应证据。
- `run.ps1 -Topology embeddedF -Auto -DebugHoldFrames`：冻结本轮 fixture F 与 S 标签更新；要求 captured=0、presented>0，识别重复呈现旧纹理。
- 两种冻结开关只允许探针自建 fixture，互斥且不能与 `-CaptureOutput` 合用；不暂停真实玩家 Flash 进程。
- covered 相位每轮最多 4 个显式内容 proof。原三像素 palette/marker oracle 保留；额外两次完整 ROI 回读计算所有 RGB 像素的 FNV-1a 摘要，逐像素核对 raw 1:1 输出，误差上限 2。
  Native 正常游戏路径不请求该诊断，不新增每帧 CPU 回读。证明的是离散样本之间的 F 内容变化与 Present 前 GPU 输出，不是 Flash 逻辑、屏幕扫描、输入延迟或性能收益。

单次运行含故意冻结时 exit 2 / success=false 是预期探针判败；套件还必须核对具体失败判据、刺激有效及恢复证据，不能只看到非零退出就宣称负控有效。
本入口仍是 ProbeForm / 素材播放器；真实 Guardian 装配与人类验收的出口见[分阶段计划](../../../docs/统一合成与输入归属-分阶段施工计划-2026-09-22.md#11-续接记录当前唯一状态)。

正式入口使用根游戏 EXE；下列脚本保留为开发/诊断入口，不作为玩家启动前置。正式 producer 从源码独立编译合成器和两个输入模块，经双故障域共识进入 runtime；不复用本节的临时二进制。

已生成配套开发构建后，从仓库根运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/perf/flash-compositor/run-game.ps1
```

正常选择角色并点击“确认”即可，游戏就绪后自动接管，没有“其他 → 测试”的合成/调色按钮。合成模式不绑定存档，所有角色均可使用。按维护者明确的本机开发测试偏好，后续直接使用现有高进度存档覆盖关卡与战斗，不再为该测试另建角色或把专用槽位作为门槛；历史记录中的“合成原型验收”仅说明此前实际使用的角色。脚本校验 Core、原生模块和 asLoader 的本地开发配对哈希；该记录不是正式 runtime identity/closure 或发布回执。

构建与启动还会执行 `fontctl generate --check`。字体源或投影过期时，先在仓库根运行 `node tools/fontctl/cli.js generate` 再重试，避免带着整套字体角色回退进入验收。

需要重建时：AS2 源码变化先走 `scripts/compile_test.ps1 -Target publish -TimeoutSeconds 240`；然后执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File launcher/perf/flash-compositor/build-game.ps1 -Run
```

要求已有 .NET SDK 10.0.300、MSVC x64、含 C++/WinRT 的 Windows SDK。脚本不安装依赖，不改正式 `runtime/`；输出为根 `tmp/flash-compositor/game`。使用 Core.exe apphost，并仅为该进程设置 `DOTNET_ROOT_X64`，保留既有热键守护链。

## 职责与协议

- `scripts/类定义/org/flashNight/arki/weather/WorldLightingBridge.as`：`world_lighting` v1 单向视觉投影。普通快照约 2 Hz，天气更新/场景事件立即发送；独立 sequence、scene 标识，不把 MovieClip 引用当跨场景身份。
- `WeatherSystem` 保留游戏时间、光照判定、夜视资格、奖励倍率、单位状态；原 `LightingEngine.applyLighting(gameworld/天空盒)` 已退出运行路径。桥只清除旧容器 ColorMatrixFilter 和 ColorTransform，每个场景/容器一次；天空渐变、粒子和环境叠层仍留 AS2。
- 视觉光照按 AS2 已推进的游戏帧计算，绕开 0.1 视觉阈值，不修改权威 clock/light/reward 字段。当前八项参数为 RGB/alpha 乘数、亮度、对比度、饱和度、色相；不传库存、存档或装备写指令。
- `launcher/src/Tasks/WorldLightingTask.cs`：校验协议与有限数字，连接断开使已排队快照失效。
- `launcher/src/Guardian/WorldCompositor/`：采用递增快照；普通昼夜使用 350 ms 矩阵插值，模式/跳时及暂停昼夜在同场景内立即采用。转场 `Ready=false` 期间保留最后有效调色并继续捕获，不撤掉合成层、不采用过渡报文中的临时中性色；新场景 Ready 后还需等到捕获时间不早于该次 Ready 接收时间的有效帧，再按近期等待时长的平滑估计，在 80–180 ms 内适应新矩阵。首次启动直接采用正确矩阵，不从白天色淡入。不从现实时间推算游戏昼夜。
- `launcher/native/world-compositor/`：WGC → GPU 区域复制 → 单次颜色矩阵/Gamma（legacy）或 3D LUT 三线性采样（lut-set-v1，mode=="光照"）→ DirectComposition 不透明输出，正常显示无 CPU 像素回读。游戏路径以 30 FPS 为节拍目标，取最新帧，空闲事件等待；面板/最小化时关闭捕获会话，恢复重建帧池并等待新帧。LUT 仅在变更时整块上传（32³ RGBA8），ClearLut 即回退矩阵路径。

输出仍是 Guardian 所有的 layered + noactivate tool window，在既有 HUD 下方。显示区保持原尺寸，Flash 子窗口可缩小；输出窗口按原生合成器的等比视口映射鼠标，键盘焦点仍归 Flash。复用 WebOverlay 已有鼠标钩子，物理移动不拦截，世界区域的按钮/滚轮由有序队列独占转交；鼠标移动按渲染节拍合并，按钮前先送最后位置，拖动期间暂缓改变源尺寸，失焦/隐藏取消未结束手势。它不代表 HUD/WebView2 已统一合成，也未证明桌面合成层数瓶颈彻底消失。

`FlashInputBroker.exe` / `FlashInputBridge.dll` 与本仓 x64 Flash projector 配对。broker 校验子窗口、所属 PID 和宿主根窗口后，只向该 Flash UI 线程安装 `WH_GETMESSAGE`，在目标进程内交付鼠标包，转换宿主物理像素与 Flash DPI 坐标，并统一该进程的鼠标状态/捕获查询。它不更改桌面鼠标位置，也不向其他应用装钩子；启动时核验所需导入，失败即停止该次渲染。退出恢复 WndProc 和导入；DLL 在目标进程内固定到进程退出，避免仍在执行的回调落入已卸载代码。跨显示器 DPI、第三方叠层与其他 Flash 二进制仍需各自运行验证，不能仅凭构建通过外推兼容性。

## 首版动态分辨率调度

`launcher/data/world-lighting/render-schedule.json` 是版本 1 的启动期配置。默认 `fixedStage=-1` 自动调度；非负值用于固定档位采样，按当前用户 quality 的档位表钳制，不是玩家必须设置的开关。MEDIUM 路径为 `100% MEDIUM → 85% MEDIUM → 75% MEDIUM → 75% LOW → 67% LOW`；HIGH/BEST 在顶部保留原画质 100% 档，LOW 用户只走 `100% → 85% → 75% → 67% LOW`。倍率只改变实际绘制视口；逻辑视野、输出窗口和 Native HUD 尺寸不变。

普通降级：约 1 秒窗口均值低于 23 FPS 持续 1.5 秒；严重卡顿：低于 12 FPS 持续 1 秒跳到 75% LOW，仍不足再到最低档。恢复要求高于 28 FPS、窗口没有超过 100 ms 的长帧，累计 6 秒才上一档；正常帧数窗口的小幅起伏不清零，短暂低于 28 FPS 按等时扣减进度，低于降级阈值或出现长帧才清零。每次换档静置 1 秒；恢复后 10 秒内再次降级，将恢复再推迟 20 秒。进入场景、数据间断、失焦、最小化、暂停、前馈 hold 和捕获尺寸未就绪期间清理观测，不把等待时间累计成降级确认。鼠标按住仍采样，实际改尺寸延后到松手，避免连续操作饿死恢复计时。转场保留当前档位。数字是首版起点，不是已标定的最优参数。

`IntervalSampler.observe` 用实际推进帧数/耗时组成约 500 ms 窗口，只汇总计数、超过 100 ms 的帧数与最长帧。FPS 载荷扩展为 `fps|hour|tier|scene|v2|frames|ms|longFrames|maxMs|preset|quality|held|paused|seq|appliedCommand`；`P{tier}|{softU100}|{quality}|{command}|{scene}` 带场景与单调命令号，AS2 拒绝迟到场景/命令。C# 看到采用回报后才安排源窗口缩放：先与原生 copy/Present 线程同步并冻结旧完整帧，再改 Flash 窗口尺寸；输入桥在 Flash UI 线程确认本次对应尺寸的 WM_PAINT 已完成并刷新 GDI 队列，返回重绘 QPC 时间；优先复用窗口缩放已完成的重绘，只有缺少有效完成记录时才补画，最后提交新裁剪并等待达到重绘时间门槛的捕获帧。旧帧不会在窗口已缩放时仍按旧裁剪更新，锐化也等有效尺寸就绪后才改变。这是重绘和捕获时间的交接，不是像素内容带语义 scene 标签的原子提交。旧两字段 P 指令保持兼容；本构建配置新调度器后不再让旧格式或合成器 FPS 同时驱动第二套策略。

GPU 使用双线性放大；仅缩放后的 LOW 默认叠加固定 0.15 强度、局部色值范围钳制的锐化，同一次 shader 绘制完成，配置为 0 可关闭。它不是 CAS，也不能恢复已丢失的抗锯齿或细节。原生 ABI 3 结构未变，开发 Host 额外要求 `ProbeHoldViewport` / `ProbeSetViewport` / `ProbeSetSharpness` 导出，仍须配套构建。

验证入口：`scripts/run-render-schedule-tests.ps1`（含既有远程/断连/hold 回归）、Host `RenderScheduleTests`。固定档与自动档的斗兽采样复用既有 `arena_calibration` 任务及 manifest 生成器：

```powershell
powershell -File launcher/perf/flash-compositor/run-game.ps1 -ArenaAutomation
# 正常进入已有角色，保持游戏前台；另一个终端运行：
node launcher/perf/flash-compositor/arena-sample.cjs fixed-low75 2
```

采样器核对本地开发配对哈希与实际 Core 进程路径，生成近战/远程/混合三组阵容，记录原始结果与渲染日志到 `tmp/flash-compositor/render-*`。它不创建存档、不改数值目录、不冒充斗兽平衡性资格；短逻辑帧预算下自然 `timeout` 是性能观察截止，`bridge_lost`/异常仍是失败。性能比较需相同前台尺寸，关闭其他编译/图形探针；没有新鲜 admitted 样本的后台区间不能作为性能收益证据。所有固定档实验完成后将配置恢复 `fixedStage=-1` 并重启。

### 2026-09-21 首版斗兽粗对照

同一开发配对（含 x64 输入桥）、现有角色 `fs`、1600×900 输出、Intel UHD 630 合成；近战/远程/混合各两场，所有批次均完成六次运行。以下是新鲜 admitted AS2 样本的推进帧数/耗时加权 FPS，长帧定义为超过 100 ms：

| 策略 | 平均游戏 FPS | 长帧计数 | 最长帧 ms |
|---|---:|---:|---:|
| 100% MEDIUM，固定 softU=0 | 17.36 | 39 | 444 |
| 75% MEDIUM，固定 softU=0 | 18.70 | 18 | 495 |
| 75% LOW，固定 softU=0，锐化 0.15 | 21.01 | 10 | 374 |
| 自动档，联动既有 softU 预算 | 23.01 | 8 | 467 |

这组短样本中，75% MEDIUM 比原尺寸约高 8%，75% LOW 约高 21%，自动档约高 33%。自动档还改变特效预算并降到 67% LOW，不能把全部差异归给分辨率。阵容相同，但战斗随机数和 CPU 动态频率未完全锁定；不作为硬件普遍收益、单核算力提升或最长卡顿已消除的证明。第一版只确认杠杆有效且调度真实生效，暂不据此精调阈值。

上述四组采样当时均处于字体目录回退状态。随后确认字体投影仍绑定 CRLF XML，而仓库源已是 LF，导致伤害数字从 Arial Black 进入微软雅黑应急回退；已通过生成器修正投影并在真实启动日志确认 `Gate E catalog ready assets=14 roles=30`。性能表保留为修复前的同条件对照，不冒充字体恢复后的重新测量。

字体修复后的 `RuntimeFontCatalogTests` 14/14 通过，Host 全量 5654 项中 5650 通过、4 项原有跳过、0 失败。实际重启使用原配套 Core，字体数据修复无需重编 AS2 或 C#；当前伤害数字观感交回维护者验收。定向与全量日志分别为根 `tmp/flash-compositor/font-fix-focused.log`、`font-fix-full-tests.log`，取代下文历史轮次的字体失败状态。

额外执行的 fontctl 工具套件为 31/33：一项仍断言 28 个角色，而现有 XML/Host 合同为 30；另一项 usage 审计发现既有 sleep-panel/blackmarket 字体字面量及嵌套 node_modules 样式。两项与本轮 XML 哈希修复分别记录于 `font-fix-fontctl-tests.log`、`font-fix-audit.json`，未据此宣称工具套件全绿。本次 `validate`、`generate --check` 与运行时字体加载均通过，总记录为 `font-fix-acceptance.json`。

原始四组为根 `tmp/flash-compositor/render-medium100-final-1789998802316`、`render-medium75-final-1789998538576`、`render-low75-final-1789999046648`、`render-auto-final-1789999380464`。各自包含 PID、六件配对哈希、启动配置、manifest、完整渲染日志与 arena 原始结果。此前没有 arena Ready 的早期样本无效；更早未含输入桥的 100% 数据不混入本表。

机器已跑通 75% 下普通窗口/最大化后的首次床铺点击、取消返回、拖出松手，以及 LOW 缩放下最小化恢复。完整连续移动、攻击和剩余 AS2 功能界面的拖拽手感，以及换档时细线闪烁、模糊/锐化接受度，仍属于下一人验节点。

自动档实战记录确认降到 67% LOW，负载结束后逐档回到 100% MEDIUM；当前配置已恢复 `fixedStage=-1`。本轮总证据为根 `tmp/flash-compositor/drs-acceptance.json`，恢复过程为 `drs-recovery.log`。AS2 focused 17/17、最终 publish Compiler 0/0、664 个类的 single-ownership 通过；Host 相关 25/25，全量 5654 项中 5639 通过、11 项既有字体域失败、4 跳过。原生 GPU 四组路径与五个非法 CLI 回归通过，输入 broker 的两个非法参数/窗口用例通过。文档巡检通过并保留既有告警；这些结果不替代上述人验或正式部署。

## 恢复等待与换档抖动修正（2026-09-21 人验反馈）

维护者已确认字体表现正常。本轮反馈的恢复过慢对应两处逻辑：约 30 FPS 的正常窗口波动会被旧“不得下降超过 0.25 FPS”条件反复清零，鼠标手势也会重置统计。现已改为上文的持续余量计时与短暂回落扣减，鼠标只延后真正的尺寸变化。最终游戏记录中，四次升档请求间隔约 7 秒，从 67% LOW 正常回到 100% MEDIUM；后台、暂停及实际长帧仍不会被当作恢复余量。

换档时先同步冻结 copy/Present，再由 Flash 重绘确认和捕获时间门槛交接裁剪，消除“已改变源尺寸却仍按旧裁剪更新输出”的竞争窗口。输入桥复用本轮同尺寸的 WM_PAINT 完成记录，避免无条件补画。曾尝试省略 Win32 自身重绘，但捕获恢复实测超时，已撤回；对应 `render-handoff-final-1790002619815` 记录无效并附 triage，不计入交付证据。采样器现在也会将任何 `world_compositor_failed` 判为无效，而非只看有多少 FPS 样本。

最终三场实战与恢复记录为根 `tmp/flash-compositor/render-paint-reuse-1790003508584` 和 `drs-handoff-fix/paint-reuse-runtime.log`，无捕获错误，已恢复 1600×900 源尺寸。源窗口及重绘确认阶段，恢复档约 9–32 ms，重负载降档约 115–140 ms；这些数值不包含后续取帧和屏幕扫描，不能视为端到端延迟或保证完全无停顿。抖动的实际观感仍待维护者醒后复验。

原生 `suite-20260921-224610-819` 四组源/适配器路径及五个非法 CLI 均通过，新增约 3 秒冻结期间零 Present、恢复后采用新裁剪的检查。新增的帧率抖动/短暂回落测试与既有合成测试共 27 项通过；最终 Host 全量 5652 通过、4 项原有跳过、0 失败。汇总为根 `tmp/flash-compositor/drs-handoff-fix/acceptance.json`。测试游戏已正常关闭，正式 runtime 未部署，使用本文配套开发入口继续人验。

## 颜色与预设

参数表仍来自现有 `data/environment/color_engine_preset.xml`。C# 保留 `ColorEngine.composeColorMatrix` 的组合顺序、色相系数和 0–255 偏移单位，最终转换到 shader 的 0–1 偏移。使用颜色矩阵滤镜的设计语义，不拟合旧基础颜色变换。

`launcher/data/world-lighting/preset.json` 是版本化的宿主预设入口。`version=1 / algorithm=legacy-matrix-v1` 为既有矩阵路径；`version=2 / algorithm=lut-set-v1`（2026-09-25 起，默认 hardlight-dusk-v4）加载同目录 CF7LUTSET v1 二进制（32³×10 档 + 内嵌 SHA-256 完整性字段，格式权威注释见 `tools/lut-lab/lib/lutset.js`），v2 的任何加载失败（文件缺失/格式/哈希不符/字段非法）都回退 legacy 矩阵并打警告日志，回退方法即改回 version 1。Gamma 范围 0.25–4（LUT 模式 gamma 语义已内嵌于 LUT，该字段仅服务 legacy 回退路径）。曲线、选择性饱和度尚未实现，后续工具仍编辑同一预设体系。

lut-set-v1 的宿主配对：原生按上游加性 ABI 3 惯例新增 `ProbeSetLut`/`ProbeClearLut` 导出（既有导出面与 ProbeStats 布局不变，ABI 号不升），配套 Host 以严格 Export 拒绝未配对旧 DLL（与 `ProbeGetCaptureSize` 同模式）；`ProbeGrabLatestFrame` 行为不变（合成套件 grab-check 阶段回归覆盖）。

捕获已经把天空、地图和角色合成；RGB 算法可对应，容器滤镜与最终图像后处理不承诺逐像素一致。输出保持不透明，不能复原已经混合掉的独立图层透明度。AS2 天空的旧整体光照同样卸载，天空自身渐变保留，避免重复压暗。设置页旧“滤镜渲染”控件退役，历史保存字段继续兼容读取，不再选择两套渲染器。

## 启动说明、权限与失败

启动页说明只在本机处理本游戏窗口、不录制或上传。进入启动流程时申请 Windows 官方无边框能力，再按结果设置 `IsBorderRequired`。本机 build 26200 的非打包 Win32 开发运行返回 Allowed，未额外弹窗，已观察到黄色边框消失；不外推所有系统都无提示。拒绝或不可用时保留系统边框，不绕过策略。

参考：[Win32 窗口捕获](https://learn.microsoft.com/en-us/windows/win32/api/windows.graphics.capture.interop/nf-windows-graphics-capture-interop-igraphicscaptureiteminterop-createforwindow)、[无边框授权](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscapturesession.isborderrequired)、[点击穿透](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features)。

捕获和有效 AS2 视觉状态是新显示链路的运行要求。启动超时/原生失败会隐藏游戏、给出明确错误并正常关闭该次运行，不静默回到全亮世界；设备丢失的自动重试尚未实现。面板/最小化恢复已经走重建路径，不把仍持有旧帧池当作恢复成功。

## 验证与人验

AS2 focused：`powershell -File scripts/run-world-lighting-tests.ps1`；Host focused：`WorldCompositorTests`；全量：`launcher/tests/run_tests.ps1`。独立 GPU 小样仍可用 `build.ps1 / run.ps1 / test.ps1` 排查捕获与设备，不是游戏的启动前置或玩家菜单。

机器已检查默认启动、真实 socket 光照快照、床铺 hover/click、休息面板取消与捕获恢复、最大化、最小化恢复。Computer Use 对 WebView2 子窗口的坐标点击存在目标进程限制，未以脚本绕过；休息确认、夜视装备切换和完整战斗手感不冒充已验收。

本轮人验集中在：连续移动/攻击手感；切屏、窗口移动和缩放有无明显闪烁/错位；室内外/昼夜/夜视是否存在无法游玩的可见度问题。允许色彩效果较大变化，预设美术精修留给后续工具。

## 转场连续性修正

用户人验报告转场瞬间丢失调色。已定位到 Host 把 `Ready=false` 同时用作停止捕获和隐藏输出的条件；这会露出已卸载 AS2 调色的原始窗口。修正将场景状态与显示层生命周期分开：保留有效调色，继续最新帧呈现，收到有效新场景状态后再做短暂适应。晚到的旧场景和旧 sequence 仍拒绝。

适应时长使用等待时长的指数平滑并钳在 80–180 ms；它仅控制颜色插值，不是保留旧调色的超时。Ready 状态先进入待交接槽，捕获帧的 QPC 时间达到首次 Ready 接收时间且裁剪尺寸有效后才采用；同场景心跳更新目标，不反复延后时间门槛，更晚场景会废弃旧目标。该检查证明帧的新鲜度，不能证明像素已经属于指定场景；目前没有随图像传递的 scene 标记，也没有状态与像素的原子提交。

本实现不增加固定画面队列、不推测新场景内容或夜视资格。等待超过 10 秒只记一次诊断，不因地图加载较慢自动关闭游戏。面板遮挡、最小化和实际窗口几何变化仍按原生命周期暂停/恢复，不把本次状态机回归当作这些路径的全部视觉验证。

加入捕获时间门槛后，Host 相关 13 项通过；全量 5642 项中 5627 通过、11 项既有字体失败、4 项跳过。配套开发构建已刷新，AS2/SWF 与原生源码未改；实际严重卡顿转场是否改善仍待玩家复验。新构建配对和源码证据为根 `tmp/flash-compositor/frame-fence-acceptance.json`；此前仅保留调色阶段的历史证据为 `transition-acceptance.json`。

## 第二阶段本机结果与人验交付

证据文件：根 `tmp/flash-compositor/world-acceptance.json`；开发配对哈希：`tmp/flash-compositor/game/development-pair.json`。实际运行是本轮 Core.exe apphost 与配套 asLoader，正常路径像素回读为 0。最后发布 asLoader 为 1,370,956 bytes，新鲜 Compiler 0/0；AS2 focused 12/12、strict single-ownership 通过。Host 全量 5635 项中 5620 通过、11 字体域失败、4 跳过；本轮相关 focused 44/44。Bootstrap Edge 27/27，设置页最终两尺寸 116/116；设置静态总入口停在既有 cheat-help 缺失 `shownpc` 文档断言。设置视觉首轮出现一次 1600 宽度测成 1592，原始基线与当前源码复跑均通过，保留首轮记录。

最终 GPU 回归为 `tmp/flash-compositor/suite-20260921-163421-486`，两种源 × Intel/NVIDIA 四组及五个非法 CLI 用例全部通过。游戏实际绘制适配器仍为 UHD 630，尚未验证独显游戏路径。

固定宿舍环境光照 2.5、同一专用角色、1600×900、静止约 30 FPS，各采样 20 秒：

| 进程 CPU 时间，换算成一个逻辑核的占用 | 旧正式 Core + 迁移前 asLoader | 本轮开发 Core + 新 asLoader |
|---|---:|---:|
| Flash Player | 38.8% | 44.3% |
| 主 Host | 56.8% | 60.3% |

这组短样本**没有证明 AS2 CPU 卸载收益，反而略高**。它是两条完整运行链的进程 CPU 对照，不是纯 AS2 脚本计时，未控制 CPU 动态频率，也没有测战斗慢帧分布；不能解释成单核吞吐提升或路线已失效。像素效果采用原滤镜矩阵，和旧基础颜色变换不要求相同。原始记录为 `world-baseline-night.json` 与 `world-native-night.json`，GPU 计数只采了单个瞬时点，不充当平均负载。

新版夜间游戏日志采样中，宿主取帧后提交复制/调色/绘制的中位数约 0.19 ms，Present 调用约 0.095 ms；这是 CPU 调用墙钟耗时，不能代替 GPU 执行时间、完整 WGC 成本或输入到显示延迟。修正节拍累积漂移后，实际连续捕获/呈现约 30 FPS。

测试临时修改的天气时间与宿舍光照配置均已按原始哈希恢复；五个原有玩家槽位的 JSON/SOL artifact-set 未变，原角色选择偏好已恢复。新建测试角色保留。机器检查不替代连续移动/攻击、完整 Alt-Tab/多屏 DPI、夜视装备切换和重战斗峰值的人验。

以下为第一阶段历史小样证据，不能用于代签当前 ABI、二进制、默认接管或卸载收益。

## 2026-09-21 独立小样历史结果

环境为 Windows 11 build 26200、i7-9750H、32 GB、UHD 630 + GTX 1650 4 GB；保持原驱动与系统显卡设置。最终串行报告位于根 `tmp/flash-compositor/suite-20260921-121801-262`，四组均通过；五个非法 CLI 拒绝用例也通过。

| 源 | 实际绘制适配器 | 捕获帧 | 呈现次数 | 三模式像素最大误差 |
|---|---|---:|---:|---:|
| 可控动画 | UHD 630 | 549 | 553 | 0/255 |
| 可控动画 | GTX 1650 | 554 | 557 | 0/255 |
| `bigmovie1.swf` / Flash Player 20 | UHD 630 | 544 | 550 | 0/255 |
| `bigmovie1.swf` / Flash Player 20 | GTX 1650 | 688 | 692 | 1/255 |

四组自动实验各有 18 次诊断单像素回读。另一次 Computer Use 交互检查真实 AS2 影片与三个按钮，报告为 `tmp/flash-compositor/visual-final.json`：1345 个捕获帧、1338 次呈现、0 次 CPU 像素回读，自有 Flash 正常关闭。Computer Use 目视检查不是用户手感或光照设计验收。

实际结论：被其他不透明窗口遮挡后仍有连续捕获；移出屏幕、隐藏及最小化会停止更新，切换时可能残留少量在途帧；恢复及源尺寸变化可以重新出帧。此结果否定本机“屏幕外源持续捕获”的旧前提。后续游戏版本据此选择源窗口留在可视屏幕范围内并被输出覆盖，验证见下一节。

验证只涉及窗口化小样与现有 AS2 影片，没有修改/编译 SWF，没有载入玩家存档，未证明真实战斗帧率收益、1080p 吞吐、输入到显示延迟或正式显示替换。报告内托管/原生哈希与本轮最终产物一致；重建后应重新绑定实测，不把历史计数当新构建结果。

附带回归：Launcher 全量 5629 项中 5614 通过、11 失败、4 显式跳过；失败均在本轮未改动的 `RuntimeFontCatalogTests`，单独运行该类仍为 3 通过/11 失败，包含 `host_not_allowed:github.com`、字体解析返回空及后续空引用。未据此修改字体域，也不声称全量通过。独立小样目录不在 Launcher 的 Compile items 中；后续新增的 `src/Guardian/ExperimentalCompositor` 则参与 Host 编译。文档治理通过，保留其既有非阻断警告。

## 2026-09-21 第一阶段实验开关历史实测

实际路径、进程与本轮开发二进制/关键源码哈希记录在根 `tmp/flash-compositor/game-evidence.json`，日志节选为 `game-observation.log`，不充当正式 runtime identity/closure。实际运行 `tmp/flash-compositor/game/CRAZYFLASHER7MercenaryEmpire.Core.exe`，专用槽位 `cf7_e560a141e8e74422b5be154ddd42`，未提升为正式 runtime。最终 DirectComposition 版本在 13:22:45–13:32:31 开启实验，日志最后一条采样有 16514 个捕获帧、16427 次成功呈现；这些是混合菜单/面板/窗口状态过程的累计计数，不是战斗性能基准。

- 实际菜单开启、原画/夜间/夜视切换、关闭恢复普通显示通过；HUD 保持原色，未出现递归捕获自身。
- 合成开启时床铺 hover 和点击打开休息面板通过，Escape 取消并恢复显示；最大化后同一路径再次通过，没有执行休息确认。
- 窗口化 1600×900、最大化对应 1920×991 捕获区域、返回窗口化与最小化恢复有本轮截图/日志；后者最小化期间停止出帧，恢复后重新更新。执行了标题栏拖动，最终画面贴合；不据此证明拖动全程无抖动。
- 五个原有槽位的 JSON/SOL artifact-set 与运行前一致，选择偏好仅恢复原 `lastPlayedSlot` 字段；新测试角色保留。证据在根 `tmp/flash-compositor/protected-saves-verified.json`。
- 第一阶段最终原生源码的小样回归位于 `tmp/flash-compositor/suite-20260921-133349-014`：两种源 × 两种 GPU 及五个 CLI 拒绝用例全部通过。该报告仅证明独立小样路径，游戏 DirectComposition 路径以本节真实运行观察为准。
- Host 开发构建通过。全量 5631 项：5616 通过、11 字体域失败、4 跳过；最终相关 222 项复跑全通过。第一次相关复跑还出现一次既有 `CharacterBuildPreparationArmTimeoutPreservesAnUnclosedExactBuild` 定时断言失败，关闭游戏后相同测试集复跑通过；没有修改该业务或掩盖失败记录。

未完成：真实战斗/长按键手感、端到端延迟测量、多显示器不同 DPI、独显游戏路径、设备丢失恢复，以及 Alt-Tab/任务栏/切屏等完整“单一应用”人验。当前仍保留既有 HUD 窗口并新增实验输出窗口，不能把一体化观感或合成层数瓶颈已解决写成结论。
