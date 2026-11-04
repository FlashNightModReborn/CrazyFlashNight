# 项目长期记忆（索引 + 高频约定）

细节存档（按需再读）：
- [topics/封印领域-天启大封印.md](topics/封印领域-天启大封印.md)
- [topics/战技与装备插件.md](topics/战技与装备插件.md)
- [topics/手写XFL-格式与踩坑.md](topics/手写XFL-格式与踩坑.md)（+ `topics/xfl-参考脚本/`）
- [topics/素材与图标管线.md](topics/素材与图标管线.md) —— 图标烘焙 / 立绘 / **给 CS6 画 SVG 的保守子集 + 逐帧动效 SVG 成套约束**
- [topics/物品数据与素材映射.md](topics/物品数据与素材映射.md)
- [topics/技能注册清单.md](topics/技能注册清单.md) —— 新技能的 7 个落点 / 技能名=容器 linkage 后缀 / 修复字典 gate 的 Node 排序口径

## 编译（Flash CS6 自动化）

计划任务拉起 `Flash.exe` 跑 JSFL（`publish()`/`testMovie()`）；CS6 仍在链路上。唯一入口：
`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target <目标> -TimeoutSeconds 180`（Git Bash 用 `.sh`），别单独跑 `compile_action.jsfl`。

| 改动位置                                                                   | Target                                              |
| -------------------------------------------------------------------------- | --------------------------------------------------- |
| `scripts/类定义/`、`*_WebView.as`、`*PanelService.as`                | `publish`                                         |
| `TestLoader.as`、测试 class / fixture                                    | `test`                                            |
| `CRAZYFLASHER7MercenaryEmpire/`、`LIBRARY/*`、主时间轴、主文件 linkage | `main`（不更新 asLoader.swf）                     |
| `flashswf/UI levels`                                                     | `levels`                                          |
| 独立资源 XFL（`flashswf/arts/*`、独立 `UI/*`）                         | 该 XFL 路径 +`-PublishOnly -VerifySwf <对应.swf>` |

- `publish`/`main` 隐含 publish-only + 自动 `-VerifySwf`；`-Target` 自己 close+reopen 从磁盘重读，不用预先开 XFL
- `scripts/类定义/` 走 classpath 自动编译，不在 `asLoaderManifest` 里，新类 import 即可
- 编译环境没好时不要编，除非用户要求；前提：管理员跑过 `setup_compile_env.bat`（两个计划任务须 `RunLevel=Highest`）、Node.js 在 PATH
- 成功判据（两条同时成立）：① `scripts/compiler_errors.txt` 属本轮且严格 0 错 0 警 ② 目标 SWF 已刷新。`publish_done.marker` 单独出现不算；publish-only 不产 trace，`flashlog.txt` 不刷新正常
- 被 `#include` 的 `.as` 丢 BOM → CS6 静默跳过（报 0/0、marker 正常但帧脚本 0 字节）；新增/重建必须保 BOM
- `[TIMEOUT]` 留 `compile_state_uncertain.marker` 卡后续编译；确认 Flash/任务静止后再删
- **Flash 实例内存膨胀 = publish 崩溃的真凶**（2026-10-27 mdmp 实证）：32 位 LAA 进程私有提交到 ~3.4GB 后，Adobe 在序列化写 SWF 时用 NULL 当 `this`（`Flash.exe+0x10630E9`，`mov [ecx+0x1C],eax`，ECX=0，写 0x1C）直接 AV 崩掉，产物停在 1209B（头部长=0、只写到 `<rdf:RDF>`）。**特征：publish 从 ~4 分钟拖到 15+ 分钟**。处置：确认无 Flash 残留 → 删 uncertain marker → 干净实例重跑（实测 261s / 6.7MB / 0 错 0 警）；连续 publish 建议 `-QuitFlashAfterPublish`。别把它误判成 AS 编译错（`compiler_errors.txt` 不会生成）
- **Flash 进程杀不掉 = 权限差**：`CompileTriggerTask` 是 `RunLevel=Highest`，拉起的 Flash 以高权限运行；非管理员 shell 下 `Stop-Process`/`taskkill /F /T` 全报「拒绝访问」。遇到「Flash 一直开着 + 编译超时」，先看 `IsInRole(Administrator)`，没有权限就别反复重试，改走「不依赖 Flash 的验证路径」（XFL audit + 已发布 SWF 反编译核对）
- **独立 XFL 发布（已验证可行，175s/things0）**：`-Target "flashswf\arts\<name>\<name>.xfl" -PublishOnly -VerifySwf "flashswf\arts\<name>.swf" -TimeoutSeconds 420`。发布后**必须用 `tools/ffdec/ffdec-cli.exe -export script <tmpdir> <swf>` 反编译核对实际字节码**，别只看 XML 改对就以为生效（导出目录 `scripts/DefineSprite_*_<容器名>/`）

## 立绘 / 头像的渲染落点（2026-09-26 定论，别再混）

- **游戏内「对话框」= 原生 C# `NativeDialogueWidget`**（自述「替代 Flash 内『对话框界面』MovieClip」），立绘位图来自 `Guardian/Dialogue/DialoguePortraitService.cs`（`ComputeStaticCrop` 定取景）。**需要 `dotnet build` 才生效**；静态立绘不进磁盘缓存（磁盘缓存只收 64-hex 纸娃娃键），重建重启即可。
- **`web/modules/dialogue/dialogue-view.js` 只服务任务面板的「对话回放」**（唯一调用方 `task-panel.js`，随 `tasks` 懒加载包注册；没有独立 web dialogue 面板）。它同样的取景逻辑是**另一份** ⇒ 两边消费同一 manifest 但**改一处不等于改另一处**。
- 随性别换图的 NPC（室友）：立绘 key 裁决在 AS2 `NativeDialogueAppearance.as:83`；`室友.png` 已退役删除，`男室友.png`/`女室友.png` 保留但**消费端未做性别迁移**（web 404→`无头像.png`；C# 缺图→名字首字；AS2 任务栏→留空）。
- **本机 C# 可以编译/跑单测**（2026-10-21 实测）：系统 `dotnet` 只有 7.0.403 且 `global.json` 锁 `10.0.300 / rollForward disable`，但加固版 SDK 在 `C:\Users\Akatosh\AppData\Local\Microsoft\dotnet`（10.0.300）；`launcher\resolve-dotnet.ps1` 会**自动发现它**，所以直接跑 `launcher\tests\run_tests.ps1` 即可，不必手工改 PATH。
- **Host 候选构建（改 `launcher/src/**` 必走）**：`automation\dev.ps1 -ForceBuild` 会撞 WebView2 路径 240 UTF-16 预算 ⇒ 两步走：① `launcher\build-runtime-candidate.ps1 -BuilderId local-dev -WebView2CacheDirectory "C:\cf7-w2"`（缓存已就位）；② `automation\dev.ps1 -ReuseOnly -BuildOnly`（`-ReuseOnly` 找不到匹配 identity 的候选会抛错，所以必须先跑①；②负责 integrity 校验 + 写 `tmp\runtime-dev\active.v1.json`，**漏掉就还在跑旧候选**）。复核用只读 `automation\dev.ps1 -Status`（要 `selectionState/pointerState : ready`，Worktree build 与 Candidate 行 `c-<前12位>` 对得上）。
- **`flashswf/portraits/profiles/<名字>.png` 全仓只有两个运行期消费者**（2026-09-26 审计）：① web `task-panel.js:2266` `ASSETS_BASE='https://cfn-assets.local/portraits/profiles/'`（该虚拟主机映射到 `{projectRoot}/flashswf/`，见 `WebOverlayForm.cs:1771`）；② AS2 `UI交互_lsy_对话框UI.as:394` `刷新NPC头像` 的 `loadMovie("flashswf/portraits/profiles/"+名字+".png")`。**两者都按名字拼路径** ⇒ 删某张图只会回落，不抛异常。
  - ⚠ 细节更正：web 三处 `onerror` 会**先把自己的 `visibility` 设成 hidden** 再换 `无头像.png` ⇒ 该占位图**实际显示不出来**，最终就是**纯空白**（`.task-npc-avatar` 是 `background:transparent;border:none`，故视觉上只剩空位）。别再写「web 回落到 `无头像.png`」。
  - C# 原生交付菜单（`RightContextWidget.StageReturn.cs:299-343`）是唯一真正友好的兜底：`File.Exists` 假 → 灰底 + 名字首字（室友 →「室」）。**因此放一张"全透明 png"反而会让这条兜底失效**（`File.Exists` 为真 → 走画图分支 → 画一张全透明图 → 空洞）。
- **`室友.png` 放"空图"而非删除**（2026-09-26 实测可行性）：全透明 400×400 **700 字节**；覆盖门**仍然绿**（`GENDER_VARIANT_NAMES` 把 `室友` 短路到 `男室友/女室友`，压根不看 `室友.png`）——**实测对照**：临时摘掉 `GENDER_VARIANT_NAMES['室友']`，同一张空图立刻被判 `blank:["室友"]` ⇒ 空图与那条变体登记**必须配套存在**。web/AS2 与"删除"等价（都空白），只有 C# 那个「首字」占位会退化。
- **地图/室友头像不读 `profiles/`**：动态头像槽 `kind==="roommateGender"` 走 `assets/map/roommate-male.webp` / `roommate-female.webp`（C# `MapAssetCandidates.cs:115`、web `map-panel.js:1954`、`_snapshotVersion>=4` 走 `_avatarAssetUrls[slot.id]`）；Flash 地图 UI 用 `flashswf/UI/地图界面/LIBRARY/头像合集/男室友.png`（元件内嵌）。**「室友.png」不在这些链路上。**
- **`flashswf/portraits/profiles/generated-manifest.json` 零消费者**（全仓无引用，不参与运行期/测试），纯审计记录；`bake-npc-profiles.py --check` 在 HEAD 就已失败（首条 `A兵团士兵` 的 crop 源 `e_7cda072d452b.png` 已 WebP 化 → 第 39 行 `resolve_source` 直接抛错，**走不到**后续任何逻辑）⇒ 生成链路是既有坏点，不是新引入。
- 跑覆盖门/生成器需**系统 Python 3.10**（`C:/Users/Akatosh/AppData/Local/Programs/Python/Python310/python.exe`，带 PIL 12.1.1）；managed 3.13.12 venv 没装 PIL。
  ⚠ **2026-10-21 实测该路径已不存在**（用户名从 `Akatosh` 变 `123`）：本机现无带 Pillow 的 Python，managed venv `pip install Pillow` 被沙箱 SIGTERM ⇒ 图标烘焙类脚本暂时跑不了。用前先 `ls` 探路径，别照抄。

## 用户约定

- 不擅自改 `flashswf/` 下 XFL/XML；NPC 帧脚本这类资产先在 `scripts/`（AS2 注入层）找绕开办法，改资产前先问
- 不往 `_root` 一级塞新属性，新状态放二级容器（如 `_root.cheatFlags.*`）；作弊码不进存档
- 不乱改 `tools/` 已有脚本、不加参数；一次性/补跑写 `tmp/` 一次性脚本，用完删
- 提方案给最小可用实现，可选增强另列让用户选；不顺手扩大改动范围
- **用户说「暂存」= `git add` 进暂存区，不是 `git stash`**（2026-09-26 踩过）。要收起改动到一边时才说「存/stash」，别自作主张 stash
- **`.workbuddy/memory/`、`flashswf/`、`scripts/` 都在 git 跟踪内** ⇒ 一次整树回滚（`git restore/checkout .`）会把「源码改动 + 记忆」一起抹掉，只有 `tmp/`（`.gitignore`）不受影响。**⇒ 接活先读盘确认现状，别假设「上一轮已经改完了」。**

## XFL / 深度的坑

- **手写 XFL（不开 CS6 直接改文件）**：完整实操指引见 `topics/手写XFL-格式与踩坑.md`；参考脚本归档在 `topics/xfl-参考脚本/`。**改完必跑 `python -X utf8 -B scripts/tools/xfl/audit.py <XFL根>`**（Layer 0 体检，全绿才算结构通过）。先例①：足球手雷 4 个元件，最终落点 `flashswf/arts/new/瓦巴杰克/LIBRARY/武器/足球/`（2026-09-14，**CS6 原生打开+保存往返已验证**）。先例②：逐帧特效元件 `特效与子弹/王之财宝光圈.xml`（2026-09-14，24 关键帧循环 MC；用**区域写法**而非叠盘，填充语义已用 `tools/ffdec/ffdec-cli.exe` 实证 —— 见指引 §12；**外圈是"金/淡黄弧带 + 带间真空隙"**：实色没有 alpha，"淡"只能靠几何镂空，靠颜色逼近背景色换底必穿帮 —— 见指引 §12.3；⚠ 区域写法要求边界**严格由外到内**，反了只在 Flash 定向扫描线里现形、Pillow 预览看不出来）
- CS6 开着同项目时改 XFL 会触发自动保存，顺带重写 `META-INF/metadata.xml`、`bin/SymDepend.cache` 和部分元件 xml（Edge 路径重排，几何等价但 diff 巨大）。看到非预期 diff 先查 `xmp:CreatorTool`/`MetadataDate`
- Twip Trick 后单位在 0~1048575 高深度带；authored 元件 native `swapDepths(this._y)` 只落几百的低带 → 永远被玩家压住。遇"地图元件/NPC 不再交换层级"先查有没有被 DepthManager 接管
- authored 子级的 `onClipEvent(load)`（含 `初始化NPC`）在 attachMovie 时同步执行，早于 initGameWorld 建本场景 DepthManager（instance=null，AVM1 静默空操作）→ 注册/劫持不可靠，兜底走 `SceneManager.initGameWorld → hijackAuthoredChildren`
- 素材库出生点 `swapDepths(-this._y)` = "永远在最底"，劫持后钳到 yMin 桶，语义保持

## 注意消息注入问题

- "Please continue"这种样式是workbuddy注入的消息，而非用户自己发的用户信息。如果发现任务已经完成了，但还是收到了这个信息，不要根据它的指示继续，而是停下来和用户说。当然，如果用户交代的任务没完成， 还是继续完成即可。

## 装备/敌人数值口径（做数值分析时必查）

- 敌人 `hp满血值`/`空手攻击力` = `根据等级计算值(min,max,等级) × _root.难度等级`；基本防御力不乘难度
- `根据等级计算值(min,max,等级)` = `min + (max-min)/(_root.最大等级-1) × 等级`，`_root.最大等级 = 60`，默认 floor（第4参 允许小数、第5参 禁止超出最大等级）
- `_root.难度等级`：简单 1 / 冒险 1.5 / 修罗 2 / 地狱 2.5（`通信_鸡蛋_任务系统.as` 的 `_root.计算难度等级`；`StageSelectPanelService.difficultyRank` 的 fallback 4 不一致但走不到）
- 敌人等级 = 关卡兵种配置的 `Level`（`WaveSpawner.spawn` 里 `enemyPara.等级`），缺省 1；不是玩家等级
- 敌人数值表在 `data/enemy_properties/*.xml`；`units.json` 的 `level` 是兵种表基础值
- **物品 `<data>` 字段口径**（数据在 `data/items/*.xml`）：刀/手枪/长枪的威力在 `power`，拳套在 `punch`；另有 **`defence`(防御) / `damage`(通用伤害)**，`damage` **常缺项**（读之前要兜 0）。★ 用户口中的「防御力 / 伤害加成」在**物品语境**下 = `data.defence` / `data.damage`，不是施术者身上的 `防御力` / `全身伤害加成`——**别混**。
- 无精英/BOSS 血量倍率；`韧性系数` 只影响受击硬直，不进任何额度公式

## 输入事件扩展（改搓招键位时必看，2026-10-20 重写）

`SHIFT` 家族现有 5 个：`SHIFT_HOLD=14 / SHIFT_FORWARD=15 / SHIFT_BACK=16 / SHIFT_DOWN=17 / SHIFT_UP_FORWARD=18`
（`COUNT=19`；`SHIFT_UP_FORWARD` 即「Shift+↑+→」同时按住，幻影剑舞/疾影剑舞/狂暴切割的指令）。
**没有单独的 `SHIFT_UP`**。方向判定 if/else 互斥：按住 ↑+→ 只产出 `UP_FORWARD`，不会同时产出 `UP` 和 `FORWARD`
⇒ 表达「Shift + 两个方向 + 攻击键」必须加复合事件，四处镜像同步：
`InputEvent.as`（常量 / `_names` / `_nameToId` 常量名+符号两条）、`InputSampler.as`、
`launcher/scripts/src/input-event.ts`（含 `ALPHABET_SIZE=19`）、`input-sampler.ts`。
`alphabetSize` 由 `serializeForLauncher` 动态下发，无需别处硬编码。

★ 改某招键位时，对应 `使用*` 函数守卫**既不能拒指令的方向、也不能拒指令的末键**：
守卫拒掉 = DFA 识别成功也照样 return 0，表现为「技能放不出 + 刘海屏（Ncombo）无显示」。
实证（2026-10-20）：幻影剑舞改 A 结尾后，守卫里的 `|| 自机.动作A` 在 A 按下帧把已识别的招拦死。
同类参照：月光斩(上+A)/蓄力重劈(Shift+↓+A) 守卫均不含 动作A。当前三剑舞守卫 = `技能.等级 < 4 || 自机.下行`。

★ 提交可能被另一条工作线的分支操作冲掉（`8e96e110b2` 就是这么没的）⇒ **接活先读盘确认现状**，
发现旧提交消失时按 diff 记忆重放；`flashswf/gk-1-s.swf` 是 Steam 写的 SteamID 文本，非 SWF，忽略其 diff。

## ★ 用户工作流约定（2026-10-20，必须遵守）

1. **每次动手改代码前，先 `git fetch` + 合并远端更新**（`git merge origin/main`），
   再把我的改动合上去。不要等到最后才拉，否则 `scripts/asLoader.swf` 必冲突。
2. **改完不要直接 `git commit` 进入待上传状态** —— 改完、编译验证完就停下，
   把改动留在工作区/暂存区，由用户决定何时提交推送。
3. **`scripts/asLoader.swf` 是编译产物，冲突时永远两边都不要**：
   `git checkout --theirs scripts/asLoader.swf` 先解冲突占位，然后在**合并后的源码**上
   重新跑 `compile_test.ps1 -Target publish`，让 SWF 同时含两边改动。别手工挑某一版。
