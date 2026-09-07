# 武器分件射击动画

把已装好的静态分件变成由射击事件驱动的有限动画。首个样例为 QJZ171；方法入口见 [美术资产装配](../../agentsDoc/art-asset-assembly.md)，实枪资料、GM6 对照和本次验证见 [QJZ171 动画案例](../../docs/QJZ171-枪管动画与可复用制作流程-2026-09-06.md)。

## 真源与消费关系

| 内容 | 真源 / 用途 |
| --- | --- |
| 分件、材质、注册点、遮挡层序 | 素材库 XFL；QJZ171 的 `00_总装` 保持静态，继续供两帧图标使用 |
| 运动分组与逐帧位移 | `profiles/qjz171.json`；偏移是静态总装的局部像素，落在 0.05 px 网格 |
| 游戏动画时间轴 | `xfl_recoil.py build` 从静态总装和 profile 生成既有 `动画` MovieClip；每个分件仍引用原图形元件 |
| 射击与复位 | `scripts/逻辑/装备函数/枪械射击动画.as`，经 `frame37.as` 注入 asLoader；由物品 XML 的 lifecycle 绑定 |
| Flash 产物 | CS6 发布 profile 声明的独立 SWF；不能用主文件发布替代 |
| 画面审阅与证据 | `tmp/weapon-animation/` 下的 SWF 导出帧、GIF、HTML、编译和原生检查日志 |

制作需要 Python 3.11+；渲染复用素材工作台的 Pillow / Java / FFDec 环境解析和有界子进程。下面的 `python` 可替换成本机已有 Python 的完整路径；PowerShell 发布入口接受 `-PythonExe`。

## 复用步骤

`profiles/qjz171.json` 绑定原型 `QJZ171`，`profiles/qjz171-ti61.json` 绑定独立物品 `钛合金QJZ171`。后者从前者的轨迹和外壳复用，但保留独立美术引用。制作阶段尚未绑定物品时可省略 `runtime`；已绑定后必须与 XML 一致。此前皮肤借用已结束，默认 TestLoader 夹具恢复原型；具体记录见 [身份拆分与评估](../../docs/QJZ171-钛合金版身份与同套武器加权评估-2026-09-06.md)。

1. **先确定运动部件。** 查实枪影像和可信原理资料，区分实测事实、推断和美术取值。记录外层镜像/倍率；QJZ171 原稿朝左，局部正 X 经外壳镜像成为画面后坐。不能直接复制另一武器的行程、携行展开或击发时序。
2. **检查既有样例。** `inspect` 列出层、关键帧、实例矩阵和脚本；经典补间只报告原有关键帧，不声称解出了中间帧。
3. **写 profile 和 lifecycle。** 指向已有静态总装与 MovieClip 动画目标，列明可动分件和逐帧偏移。第一帧、击发帧和末帧均为零偏移，保留原枪口发射接口。已绑定物品的 `fireStart/fireEnd`、装扮链接、动画目标必须与 profile 一致；检查器拒绝漂移。
4. **生成并复核。** 工具保留静态层与原分件矩阵的线性部分，位移始终相对静态原值计算。脚本、遮罩、已有总装动画、缺失引用及多轨重复部件均拒绝猜测。
5. **原生保存并发布。** `publish.ps1` 在现有 Flash 编译互斥锁内调用 JSFL，核对每一帧的全部分件矩阵，原生保存，再执行现役 `compile_test.ps1` 的完整发布门；保存后另做 XML/profile 严格语义比较。
6. **验证触发并看实际导出。** AS2 聚焦测试覆盖成功/拒绝发射、连发、姿态、stale holder 和退订；另以 `MovieClipLoader` 加载真实 QJZ171 SWF，在原生 `MovieClip` 上验证位移、回位和固定枪口接口。`render_review.py` 从 SWF 导出链接解析命名实例，检查实际帧数、首末 stop、可见运动与首/击发/末帧一致。
7. **刷新消费者。** 用素材工作台共享 CLI 生成并应用目标物品。静态 UI 图标和默认装扮维持待机画面；本工具的逐帧审阅页用于看射击动作。最后在游戏里确认真实握持、枪口火光和连发观感。

```powershell
python -X utf8 -B tools/weapon-animation/xfl_recoil.py inspect --xfl flashswf/arts/new/fs配置素材/fs配置素材.xfl --symbol "长枪/GM6_LYNX/GM6_LYNX"
python -X utf8 -B tools/weapon-animation/xfl_recoil.py build --profile tools/weapon-animation/profiles/qjz171.json
python -X utf8 -B tools/weapon-animation/xfl_recoil.py build --profile tools/weapon-animation/profiles/qjz171.json --check
powershell -ExecutionPolicy Bypass -File tools/weapon-animation/publish.ps1 -Profile tools/weapon-animation/profiles/qjz171.json -PythonExe python
python -X utf8 -B tools/weapon-animation/render_review.py --profile tools/weapon-animation/profiles/qjz171.json --output-dir tmp/weapon-animation/qjz171/review
python -X utf8 -B tools/asset-workbench/cli.py bake --item QJZ171 --kind all
# 检查候选后，使用上条命令实际返回的 jobId：
python -X utf8 -B tools/asset-workbench/cli.py apply --job <jobId>
```

HTML 审阅页可直接在浏览器打开；需 HTTP 时用 `python -m http.server 18768 --bind 127.0.0.1 --directory tmp/weapon-animation/qjz171/review`。页内可单发、连发、复位和逐帧查看；GIF 为放慢间歇的动作展示，不是实枪射速测量。

`previewShotIntervalMs` 与物品 XML 的基础 `interval` 同步。审阅页按 `EnhancedCooldownWheel.addTask` 的向上取整方式，把基础间隔换算为 profile FPS 下的整数帧，再安排连发；例如 30 FPS 的 270 ms 对应 9 帧 / 300 ms。降低射速不会自动延长动画，必须同时修改逐帧轨迹、`frameCount` 和 lifecycle 的 `fireEnd`。连发窗口内优先保留快速后坐与明确的终点停留，再安排复进；实际加速配件下每次成功射击仍从击发帧重新同步。

## 原生脚本与验证边界

CS6 的管理员兼容运行方式可能令普通窗口输入失效。发布包装复用已配置的 `CompileTriggerTask`，在仓库编译互斥锁内临时加入固定的原生检查调用，并在 `finally` 逐字节恢复 `compile_action.jsfl`；每次的原始备份保存在本次输出目录。没有创建新的提权任务、修改计划任务权限或跳过编译器诊断。遇到编译不确定 marker 时按 [CS6 编译指南](../../scripts/FlashCS6自动化编译.md) 恢复，不能删闸重试。

原生 JSFL 可能把 XML 的 `ty=-94.5` 读成 `-94.499`。检查按平移 twip 与线性部分 16 位小数的存储网格比较；**保存后的 XML 仍须与 profile 严格一致**。这只消除原生读取接口的亚 twip 偏差，不放宽保存后的位置或轨迹要求。

动画不订阅尚未成功发射的旧时间轴意图。成功 `processShot` 从击发帧重新对齐；周期用 `_root.帧计时器.当前帧数` 推进，placement 回调只写画面。非长枪姿态回位，换装/版本失配拒绝旧 ref，卸载按 callback + scope 精确退订。它没有复制 GM6 的展开、收起或击杀奖励机制。

游戏内看不到动作时，先在该物品 `initParam` 临时加 `<debug>true</debug>`，重启并复现，检索 `logs/launcher.log` 中的 `[枪械射击动画]`。日志直接来自初始化、射击回调、周期开始、视觉写入和卸载，每个 ref 最多 120 行；默认关闭。重点比较下一次「周期开始」的「实际帧」与「上次写入」，并同时看「引用相同」、可见状态、版本和装备引用。仅在 `gotoAndStop()` 后立即读回正确帧号，不足以排除后续被覆盖。确认运行后移除 `debug`，再讨论尺度、火光遮挡或动作节奏。

```powershell
python -X utf8 -B tools/weapon-animation/test_xfl_recoil.py
powershell -ExecutionPolicy Bypass -File scripts/run-weapon-animation-tests.ps1
node tools/validate-equip-fn-coverage.js
node tools/validate-doc-governance.js
```

`-SkipCompile` 仅检查聚焦测试入口和恢复链。当前原生测试由 `ShotTimelineTest` 的 37 项逻辑检查与 `Qjz171LiveAnimationTest` 的 15 项真实素材集成检查组成；后者加载实际物品 XML、构造原生 `MovieClip` 角色与 `BaseItem`，通过生产生命周期装载和卸载入口驱动已发布 QJZ171，调度器由夹具捕获回调。AS2 测试、CS6 逐帧矩阵、实际 SWF 图像和游戏内人工体验是各自独立的证据，不互相代替。新增生命周期脚本时仍须同步 frame37、重生成 collapsed frame、保持 BOM 并发布 asLoader；数据源变更按材料目录规则 derive/check。PowerShell 入口也保留 UTF-8 BOM，避免 Windows PowerShell 5 将中文路径按 ANSI 误读。

真实素材测试的 `configure(spec)` 从专用 `scripts/test-runners/weapon-animation/TestLoader.as.template` 接收 `itemName`、`itemXml`、`swf`、`linkage`，随后由同一模板调用无参 `runAllTests()`，沿用聚焦 runner 的入口契约。测试类复用生产装卸与动画检查，样例身份由测试入口明确列出；该模板仅由聚焦 runner 临时安装到 TestLoader，不进入 asLoader 启动。复用时修改样例参数并保留路径与导出的一致性，不把测试物品构造当作正式游戏获取入口。

若异步素材加载的完成标记晚于 `compile_test.ps1` 的 trace 副本，focused runner 会因缺少完整起止块失败。先按同一 runId 检查原始 Flash 日志及实际产物，再记录补充行为证据；不得把 runner 的非零退出改记为通过，也不因日志截取偏早重写生产动画控制器。
