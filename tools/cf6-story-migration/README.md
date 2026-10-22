# CF6 原作漫画/剧情过场迁移工具链

从原作 `crazyflasher6-cn.swf`（SHA256
`b52af10e…589b01`，30fps，主时间轴 221 帧）可追溯地索引并提取 7 段漫画过场
（主标签 s1–s7）、A21 引擎内演出（sprite 2008）与 end 制作名单（sprite 2034），
并装配 `comic-story.fragment.json` 供主控集成。

**证据边界**：AS2 故事接线已取得 171 项真实 CS6/AVM1 回归，详见下文；Web 静态检查与静音、音频 mock 的
无界面浏览器检查不能替代游戏、真实播放或听感。SWF 侧只做只读解析与提取，
不手改/不外部生成 SWF。

## 文件

- `cf6swf.py` — 只读 SWF 解析库（tag 遍历、DefineSprite 递归、PlaceObject2/3
  MSB-first 标志位、DefineEditText 原文、SoundStreamHead 参数、原字节 SHA 钉）。
  注意：PlaceObject2 位域为 MSB-first（0x02=hasCharacter, 0x04=hasMatrix）；
  ExportAssets=tag 56。MATRIX 位流在本文件个别实例上未完全对齐，**布局坐标一律以
  FFDec SVG 渲染为准**（见下），索引中的 matrix 仅作参考。
- `index_cf6_story.py` — 生成 `generated/cf6-story-index.json`：逐漫画的外层/条带
  sprite、页推进帧、平移目标、音乐、跳过按钮、目标帧、素材闭包与逐 tag 原字节 SHA。
- `extract_assets.py` — 提取素材到 `flashswf/arts/new/Codex素材源稿/CF6漫画过场/`：
  页艺术图原 JPEG 字节、旁白 MP3（流头按 SWF 规范剥离、载荷原字节不变）、
  raw 流拼接、音乐 music01–04 原 MP3、A21 事件音效、逐页 FFDec 帧 SVG
  （原矢量/文本渲染，非重绘）、名单文本（FFDec formatted text）、MANIFEST.json
  （全文件 SHA256）。断点续传：页首帧 SVG 齐全才跳过该 strip。
- `build_comic_story_fragment.py` — 装配/校验 `generated/comic-story.fragment.json`
  （closed schema `cf6-comic-story.fragment.v1`）；`--check` 复核页数=原推进帧数、
  视口 rect 合法、全部资产 SHA 与 MANIFEST 一致。
- `build_cf6_web_content.py` — 从 fragment 和已提取素材生成独立 CF6 Web 内容、
  素材镜像及完整性清单；`--check` 逐字节核对派生物，source binding 包含 SWF 解析器。
- `ensure-bom.ps1` — 字节级保证 .as UTF-8 BOM（PS5.1 安全写法）。
- `ffdec-work/` — FFDec 中间产物（可删可重建，非交付物）。

## 运行

```bash
python tools/cf6-story-migration/index_cf6_story.py
python tools/cf6-story-migration/extract_assets.py     # 需 Java；自动用 Adobe Animate 2024 自带 JRE + 仓内 tools/ffdec/ffdec-cli.jar
python tools/cf6-story-migration/build_comic_story_fragment.py          # 装配+自检
python tools/cf6-story-migration/build_comic_story_fragment.py --check  # 仅校验
python tools/cf6-story-migration/build_cf6_web_content.py
python tools/cf6-story-migration/build_cf6_web_content.py --check
python tools/cf6-story-migration/test_cf6_web_content.py
node tools/cf6-story-migration/test_cf6_web_browser.js
```

## 原作机制（迁移语义来源）

- 主时间轴 sN 帧放外层漫画 sprite（内含条带 strip + 跳过按钮 DefineButton2_1291）。
- strip 是大时间轴：页内 DoAction `_parent.nextFrame()` 在旁白流驱动下自动翻页；
  外层逐页 DoAction 设 `myx/myy` 平移目标，子 MC enterFrame 以 1/3 缓动追随。
- 跳过：`on(keyPress "<Space>")` → `_root.切镜.gotoAndPlay(2)` 并把 `目标帧` 交给切镜。
  看完末页走同一切镜路径——**跳过与看完等价**。
- 切镜 = sprite 1281（主帧 30 深度 1297 常驻），其第 21 帧 `_root.自动存盘();
  _root.gotoAndStop(目标帧)`。迁移后持久化归现役 AS2 权威，过场本身零持久写。
- 触发：教学/A01/A02 由过关计数器（1430/1587/1617）进 s1/s2/s3；A06/A17/A22 由
  boss 监视 1766（hp<=0）进 s4/s6/s7；s5 由 A07 车辆段内撞击触发；A20→a21（演出）
  →a22。
- 文本：条带内 DefineEditText（HTML，宋体 12），为原文真实文本；原作无说话人标记。
- 音频：条带内 SoundStreamHead+逐帧 SoundStreamBlock（MP3 流），即旁白；
  音乐 music01–04 = DefineSound 1110–1113（MP3 44.1kHz）。

## 接线（主控）

见 `generated/comic-story.fragment.json` 的 `integrationNotes`。要点：
Host `BookComicTask.cs` Pages 白名单 + Web 独立懒加载 `book-comic-cf6-content.js` +
AS2 章节边界调 `Cf6StoryService.beginChapter`，胜利后经 `beginFinal` 串联 s7 与 credits。

Host 的漫画串联必须等待前驱 exact close 实际成功及原暂停释放：仅已确认 continue/skip 的
S4→S5、S7→片尾可保留一个同 slot/scene 后继，并绑定前驱实例；失败、断连、过期或其他面板抢入不放行。
2026-10-22 现场出现过“前驱开始关闭后，后继立即到达被拒绝，AS2 从前驱重试”的循环；
修复的真实生产接线测试位于 `BookComicCloseTests`，连同 `BookComicTaskTests` 定向 58/58 通过。
这不是固定一帧延迟，也没有放宽普通漫画打开条件；仍需最新隔离候选的实际串联复验。

## 原始时序与保留的适配

索引按原始 SWF tag 顺序保留同帧 remove/place；s1 的四页分别消费文本
1285–1288，不能先集中 place 再 remove。旁白首个有样本的流块帧进入 fragment 的
`firstAudioFrame/startSec` 与 Web 的 `narrationStartSec`。s3 从第 110 帧开始，
因此前 109/30 秒保持旁白静音；暂停不消耗此偏移，跳页后按漫画时钟减去偏移定位。
MP3 不补静音、不转码；重复提取遇到相同字节不重写原始素材。

原作音乐播放器会循环曲目。CF6 各段及手动 credits 的面板自有音乐保持循环，
s7 不再在 music03 首轮结束后缺失后续音乐；旁白不循环。Web 使用连续循环，
没有模拟原作至多约 29 帧的轮询重启间隙，也没有复制原作跨关卡继续播放的全局所有权。
关板后仍释放现役 BGM lease。末页保留旁白尾部、s4/s5 串联、credits 手动继续和
Web 时钟仍是现有适配；MP3 `latencySeek` 的细微播放器差异与实际听感尚待实机核对。

## 剧情服务测试与当前状态

r16 修复了连续段落复用 prepared 队列的源码缺陷，并准备独立 focused TestLoader 入口。
r17 增加 `Cf6BookRunStoryTest`，经真实 `BookRunService` watcher、`Cf6StoryService` 与
`BookComicService` 覆盖 s4/s5 prepared+finish 后的 A08 续行，以及 victory → s7 → credits →
现有 outcome/markDirty 屏障；另覆盖 pending reward、closed/failed 重试、旧 world/slot/run 拒绝和
campus/Lee 非 CF6 路径。credits 后的 CF6 `persistOutcome` 现在先复核原 world/run/slot，再等待
既有 reward commit pending；不会清除未知写锁或重放奖励。所有 SaveManager、markDirty、transport、
音频与房间边界均为内存夹具并恢复，不装载地图资源或物理存档。
2026-10-22 已取得真实 CS6/AVM1 回执：`story-avm1-r3` 为171/171，`audio-avm1-r3` 为212/212，
均为 fresh Compiler 0/0、唯一闭合 runId、32K retry 0，目录位于本轮 `tmp/cf6-roguelike-20261021/validation/`。
这些是逻辑夹具证据；主逻辑包仍须按当前源码重新编译，真实游戏、漫画听感与标准入口验收分别记录。

白天在仓库根目录执行两条真实 CS6 runner：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-story-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-audio-v2-tests.ps1
```

第一条依次调用 `BookComicServiceTest`、`Cf6StoryServiceTest` 与 `Cf6BookRunStoryTest`，
使用隔离 transport fixture，不读写物理存档、不播放真实音频；AudioBridge 自身的 wire/lease
回归由第二条独立入口覆盖。两条 runner 都复用统一编译 mutex、scratch 持久备份/inflight marker、
fresh evidence 与字节恢复合同。

这两轮实际 trace 分别确认如下结果；以后源码变化须取得新回执：

```text
BookComicServiceTest Tests Passed: 45
BookComicServiceTest Tests Failed: 0
Cf6StoryServiceTest Tests Passed: 94
Cf6StoryServiceTest Tests Failed: 0
Cf6BookRunStoryTest Tests Passed: 32
Cf6BookRunStoryTest Tests Failed: 0
AudioBridgeV2Test Tests Passed: 212
AudioBridgeV2Test Tests Failed: 0
```

音频源码含205个断言调用点，其中非法 lease 身份循环执行8种输入，实际产生212项断言。
静态计数与运行计数分别由 runner 校验；数字不能代替新鲜行为证据，也不构成真实听感或标准入口验收。
