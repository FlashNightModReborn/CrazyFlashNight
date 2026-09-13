# 项目长期记忆（索引 + 高频约定）

细节存档（按需再读）：[topics/封印领域-天启大封印.md](topics/封印领域-天启大封印.md) · [topics/战技与装备插件.md](topics/战技与装备插件.md) · [topics/手写XFL-格式与踩坑.md](topics/手写XFL-格式与踩坑.md)（+ `topics/xfl-参考脚本/`）

## 编译（Flash CS6 自动化）
计划任务拉起 `Flash.exe` 跑 JSFL（`publish()`/`testMovie()`）；CS6 仍在链路上。唯一入口：
`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target <目标> -TimeoutSeconds 180`（Git Bash 用 `.sh`），别单独跑 `compile_action.jsfl`。

| 改动位置 | Target |
| --- | --- |
| `scripts/类定义/`、`*_WebView.as`、`*PanelService.as` | `publish` |
| `TestLoader.as`、测试 class / fixture | `test` |
| `CRAZYFLASHER7MercenaryEmpire/`、`LIBRARY/*`、主时间轴、主文件 linkage | `main`（不更新 asLoader.swf） |
| `flashswf/UI levels` | `levels` |
| 独立资源 XFL（`flashswf/arts/*`、独立 `UI/*`） | 该 XFL 路径 + `-PublishOnly -VerifySwf <对应.swf>` |

- `publish`/`main` 隐含 publish-only + 自动 `-VerifySwf`；`-Target` 自己 close+reopen 从磁盘重读，不用预先开 XFL
- `scripts/类定义/` 走 classpath 自动编译，不在 `asLoaderManifest` 里，新类 import 即可
- 编译环境没好时不要编，除非用户要求；前提：管理员跑过 `setup_compile_env.bat`（两个计划任务须 `RunLevel=Highest`）、Node.js 在 PATH
- 成功判据（两条同时成立）：① `scripts/compiler_errors.txt` 属本轮且严格 0 错 0 警 ② 目标 SWF 已刷新。`publish_done.marker` 单独出现不算；publish-only 不产 trace，`flashlog.txt` 不刷新正常
- 被 `#include` 的 `.as` 丢 BOM → CS6 静默跳过（报 0/0、marker 正常但帧脚本 0 字节）；新增/重建必须保 BOM
- `[TIMEOUT]` 留 `compile_state_uncertain.marker` 卡后续编译；确认 Flash/任务静止后再删

## 用户约定
- 不擅自改 `flashswf/` 下 XFL/XML；NPC 帧脚本这类资产先在 `scripts/`（AS2 注入层）找绕开办法，改资产前先问
- 不往 `_root` 一级塞新属性，新状态放二级容器（如 `_root.cheatFlags.*`）；作弊码不进存档
- 不乱改 `tools/` 已有脚本、不加参数；一次性/补跑写 `tmp/` 一次性脚本，用完删
- 提方案给最小可用实现，可选增强另列让用户选；不顺手扩大改动范围

## XFL / 深度的坑
- **手写 XFL（不开 CS6 直接改文件）**：完整实操指引见 `topics/手写XFL-格式与踩坑.md`（结构登记 / Edge 编码 / 三次→二次解析误差上界 / 图层承载顺序 / CRLF / **CS6 保存后的结构重组** / 验证清单 / 参考样本路径索引）；参考脚本归档在 `topics/xfl-参考脚本/`。**改完必跑 `python -X utf8 -B scripts/tools/xfl/audit.py <XFL根>`**（Layer 0 体检，全绿才算结构通过）。先例：足球手雷 4 个元件，最终落点 `flashswf/arts/new/瓦巴杰克/LIBRARY/武器/足球/`（2026-09-14，**CS6 原生打开+保存往返已验证**）
- CS6 开着同项目时改 XFL 会触发自动保存，顺带重写 `META-INF/metadata.xml`、`bin/SymDepend.cache` 和部分元件 xml（Edge 路径重排，几何等价但 diff 巨大）。看到非预期 diff 先查 `xmp:CreatorTool`/`MetadataDate`
- Twip Trick 后单位在 0~1048575 高深度带；authored 元件 native `swapDepths(this._y)` 只落几百的低带 → 永远被玩家压住。遇"地图元件/NPC 不再交换层级"先查有没有被 DepthManager 接管
- authored 子级的 `onClipEvent(load)`（含 `初始化NPC`）在 attachMovie 时同步执行，早于 initGameWorld 建本场景 DepthManager（instance=null，AVM1 静默空操作）→ 注册/劫持不可靠，兜底走 `SceneManager.initGameWorld → hijackAuthoredChildren`
- 素材库出生点 `swapDepths(-this._y)` = "永远在最底"，劫持后钳到 yMin 桶，语义保持

## 物品数据与素材映射（加物品/素材时必看）
- 物品定义在 `data/items/*.xml`，由 `data/items/list.xml` 的 `<items>` 逐个登记；`<item>` 无 `<id>`（ID 自动生成），查找走 `_root.getItemData(名称)` → `ItemUtil.getItemData`，**按名称取值，条目顺序无影响**
- 消耗品（含手雷）必须 `<use>手雷</use>` 才进手雷装备格；字段见 `消耗品_手雷.xml`：level/weight/dressup/capacity/split/diffusion/interval/velocity/bullet/sound/muzzle/bullethit/clipname/bulletsize/power/impact（+ 可选 damagetype/magictype）
- `icon` 只写裸名（运行时拼 `图标-`）；`dressup` = 手持/装备外观元件、`bullet` = 投掷物元件、`clipname` = 弹夹名（手雷用不到，随 bullet 写）
- 投掷物骨架参考 `flashswf/arts/new/公共素材位0/LIBRARY/其他武器/`：`砖.xml`（Labels 层第 3 帧标签 `消失` + Script 层 `stop()`/`removeMovieClip()` + 名为 `area` 的实例带重力落地 `gotoAndPlay("消失")` + 画层 `_rotation += 7`）、`手雷-砖.xml`（含 `枪口位置` 标记）、`图标-砖.xml`；图标也可照瓦巴杰克 `武器/刀剑/图标-舞.xml`（第 1 帧遮罩特写 + `图标阴影`，第 2 帧完整展示，Script 层 `stop()`）。**2026-09-14 的足球手雷已照这套骨架纯文本写进瓦巴杰克 XFL，可直接当模板**：`LIBRARY/武器/足球/{足球图,足球,手雷-足球,图标-足球}.xml`（CS6 保存后由用户从 `特效与子弹/` 移来，路径以磁盘为准）；`area` 宿主要用透明元件（如 `area40X40`），别拿图形元件顶替
- 元件放 `flashswf/arts/**` 的 XFL 里，新增后必须：publish 该 SWF → 重跑 `python tools/linkage_scanner/scan_linkage.py` 让 `data/items/asset_source_map.xml` 收录，否则运行时 `attachMovie` 找不到符号
- 没进 `data/shops/npcs/*.json`（商人货架）和掉落表的物品，游戏内拿不到

## 图标管线（SWF 是唯一真源）
双通道：Flash 内 `attachMovie("图标-" + itemData.icon)` 读 `flashswf/arts/素材库-物品技能图标.swf`；Web/Launcher 读 `launcher/web/icons/manifest.json` + `*.webp`，由 `tools/bake-icons-offline.py` + `tools/ffdec/ffdec-cli.exe` 离线扒出。`Icons.resolve()` 只查 manifest，无 AS2 动态采样回退。
加图标：① SVG → CS6 导入 XFL（勾"为 ActionScript 导出"，linkage `图标-XXX`）② publish 图标库 SWF ③ 重跑 `scan_linkage.py`（冷启 ~3.5 分钟，缓存热 24 秒；不做这步 bake 报 `unresolved=missing_asset`）④ `python tools/bake-icons-offline.py --name XXX,YYY`
- 环境：managed 3.13 没 Pillow，用系统 `C:/Users/Akatosh/AppData/Local/Programs/Python/Python310/python.exe`
- 耗时被 FFDec `-swf2xml` 吃掉（4.8MB → 254MB XML、191 秒，必然超默认 120s）；超时只让 sprite_graph 退化成空 → 静态首帧，无害。9 个图标 ≈ 2 分钟
- 跳过行为（无 `--force-overwrite-existing`）：一致 → `unchanged`；有差异 → `layout_protected`（保留旧图）；只有缺文件才 `created` → 增量加图标天然安全。`--name` 收裸名（不带 `图标-` 前缀），逗号分隔或重复多次都行；`--dry-run` 只跑不写
- 成功判据 `tmp/icon-bake-offline-report.json`：`created=1 / processed=1`、`unresolvedSummary` 空、`protectExistingLayout: true`；自查符号表用 `grep -l 'linkageExportForAS="true"' <元件>.xml` 或 `ffdec-cli.exe -export symbolClass <out> <swf>`（1.5 秒）
- ⚠ 启动清空 `tmp/icon-bake-offline` 被安全钩子拦成 `[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]` 时**脚本只打一行就退出、什么都没跑**（曾误记为"无害噪声"，2026-09-14 实证纠正）→ 先 `rm -rf tmp/icon-bake-offline` 再重跑
- 重扫脚本在 `tools/linkage_scanner/scan_linkage.py`（不在 `scripts/tools/`）；**不认 `--help`**，挂了也会立刻执行全量扫描 + 重写 map
- `data/items/asset_source_map.xml` auto-generated，禁止手改，且常落后于库里实际元件（新增元件不重扫就不进表）→ 看到"少条目"先重扫；重扫后必做差分核对：备份旧 map → 按 `<asset id= swf= symbolName=>` 解析成 dict → 比新增/消失/改指向，正常是"纯新增、消失 0、改指向 0"；`grep -c '<asset '` 与正则计数口径不同，别拿两个数相减

## 立绘管线
`tools/bake-dialogue-portraits.py` → `launcher/web/assets/dialogue-portraits/`（`external/` 外部 SWF、`internal/` 内置矢量肖像，带 manifest.json/report.json）
- 外部立绘 3x 超采样 `--supersample 3`（FFDec 按 zoom×ss 渲染再 LANCZOS 降回，几何尺寸不变）；内置 sprite 不能超采样：zoom>1 必抛 `InternalError: Odd number of new curves!`，只有 1x 能跑
- `--semantic-baseline-dir` 默认等于输出目录，必须指向含旧产物的目录：23 个内置空肖像靠它做 alpha 等价复用（保住 775 宽）；指向空目录会重导成 851 宽 = 回归
- 补跑/增量写 `tmp/` 一次性脚本（读已有导出 → 只重建 external → 写回 manifest），不动原脚本

## 给 CS6 画 SVG 只能用保守子集
CS6 老导入器不支持 `<linearGradient>`+`fill="url(#id)"`、`<clipPath>`、`opacity`（Animate 支持，所以只有 CS6 丢色），也不支持 transform。只用字面 `#RRGGBB`，渐变拆 2~3 段实色，半透明预先混色，最外层描边最后画来盖毛边；一切"淡入淡出"用几何量（宽度/半径/长度收到 0）表达，别用深色冒充。描边重量约 2.3% 画布（64 画布 → 主体 1.5）；中央标签别太大，否则 32px 糊成黑块。参考 `tmp/gen_potion_icons.py` 脚本头。
- 交付给 CS6 的 SVG 放 `素材/svg-待导入/`（或对应 XFL 旁的 `svg-待导入/`）；导入前去掉 `<!DOCTYPE>`、`pt`→`px`、无意义的 `opacity="1.00"`
- 位图自动描出的 SVG（上千条 path、上千种颜色）当 24×24 图标会糊成一团，图标帧应另出简化版

逐帧动效 SVG（Python 生成）成套约束，参考 `tmp/天启大封印-特效/gen_shu_effects.py`（头注释）+ `_verify.py`：
- **非零环绕**：同一 `<polygon>` 拼多根小图形会把圆盘填实 → 每根各自成多边形；挖空环形/扇环 = 外圈正走 + 内圈倒走一个多边形，不需 clipPath
- **循环无缝**：周期量走整数周期；验收 = `build(0)` 与 `build(N)` 逐坐标 0 差异。分段接缝：爆发段相位用 `(i-(N-1))/LOOP_N`（负相位）使末帧与循环首帧逐点相同
- **防顿帧**：消散段用 `u=(i-8)/6` 而非 `(i-9)/5`，否则与上一帧参数完全相同
- **消散是"碎开飞散"不是"缩回"**；碎片基准半径用独立常量（如 `ORB_SHARD_R=1.42`），共用底图半径会跟着缩成环；碎片夹画布内（`lim = min(cy,H-cy,cx,W-cx)-40`）
- 画布加高须同步放大毛边频率、采样段数、光丝/浮尘数量，否则纹理变稀、边缘成节状直线
- 一次性段 + 循环段混排：SVG 只出两条序列，循环由用户代码侧控制；半透明出两套配色（不透明色 + CS6 手设不透明度 / 极暗色 + CS6「叠加」混合）

## 作弊码
- 开关 `_root.cheatFlags.强制显示NPC`（true 时 `初始化NPC` 不再被 `任务需求`/`任务需求支线` 挡）；命令 `shownpc`（toggle，切场景生效）。NPC 帧脚本里"任务完成后消失"的上界判定不归它管
- 帮助三处：① 数据源 `GameSettingsPanelService.as` 的 `buildCheatHelp()`（≈747 行硬编码数组，挑战模式只返 3 条）② C# `SettingsTask.IsValidCheatHelp()` 只校验 ③ Web `settings-runtime.js`/`settings-panel.js` 的 `cheatCommandForm()`/`openCheatHelp()`/`renderCheatHelpDocument()`
- `classifyCheat()`（≈766）定 effectScope（read/session/save），不在 read/save 白名单的默认 `session`
- 链路（仍在 AS2，没迁 Web）：Web 输入与确认 UI → C# `NormalizeCheat`（校验 payload、command ≤240 字、无控制字符）转 action `settingsCheat` → AS2 `GameSettingsPanelService.settingsCheat` → `executeCheat()` → `classifyCheat()`（null 报 `unknown_command`）→ `_root.cheatCode()` → `_root.cheatFunction[命令]()`
- 新作弊码提示"无法识别"几乎都是 `asLoader.swf` 没重新 publish

## 装备/敌人数值口径（做数值分析时必查）
- 敌人 `hp满血值`/`空手攻击力` = `根据等级计算值(min,max,等级) × _root.难度等级`；基本防御力不乘难度
- `根据等级计算值(min,max,等级)` = `min + (max-min)/(_root.最大等级-1) × 等级`，`_root.最大等级 = 60`，默认 floor（第4参 允许小数、第5参 禁止超出最大等级）
- `_root.难度等级`：简单 1 / 冒险 1.5 / 修罗 2 / 地狱 2.5（`通信_鸡蛋_任务系统.as` 的 `_root.计算难度等级`；`StageSelectPanelService.difficultyRank` 的 fallback 4 不一致但走不到）
- 敌人等级 = 关卡兵种配置的 `Level`（`WaveSpawner.spawn` 里 `enemyPara.等级`），缺省 1；不是玩家等级
- 敌人数值表在 `data/enemy_properties/*.xml`；`units.json` 的 `level` 是兵种表基础值
- 无精英/BOSS 血量倍率；`韧性系数` 只影响受击硬直，不进任何额度公式
