# 项目长期记忆

## 编译（Flash CS6 自动化）

本质：计划任务拉起 `Flash.exe` 跑 JSFL 自动 `doc.publish()` / `testMovie()`。省的是手动点击，**CS6 仍在链路上**。

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 180
```

Git Bash：`bash scripts/compile_test.sh -Target publish -TimeoutSeconds 180`

| 改动位置 | 命令 |
| --- | --- |
| `scripts/类定义/`、`*_WebView.as`、`*PanelService.as`（注入 `_root`） | `-Target publish` |
| `scripts/TestLoader.as`、测试 class / fixture（要跑 trace 断言） | `-Target test` |
| `CRAZYFLASHER7MercenaryEmpire/`、`LIBRARY/*`、主时间轴、主文件 linkage | `-Target main` |
| `flashswf/UI levels` | levels |

- `publish` / `main` 别名已隐含 publish-only 与自动 `-VerifySwf`
- `-Target main` **不会**更新 `scripts/asLoader.swf`，改注入层必须用 `publish`
- 不用预先打开 XFL：`-Target` 自己 close+reopen 从磁盘重读
- `scripts/类定义/` 走 classpath 自动编译，不在 `asLoaderManifest` 里，新增类 import 即可
- 现在编译环境没好，除非用户要求否则不编译

成功判据（两条同时成立）：① `scripts/compiler_errors.txt` 属本轮且严格 `0 个错误 / 0 个警告`；② 目标 SWF 已刷新（asLoader = `scripts/asLoader.swf`）。`publish_done.marker` 单独出现不算；publish-only 不产行为 trace，`flashlog.txt` 不刷新属正常。

前提：管理员跑过 `scripts/setup_compile_env.bat`（`CompileTriggerTask` / `FlashCS6Task`，必须 `RunLevel=Highest`）；Node.js 在 PATH（TestLoader 硬门）；唯一入口是 `compile_test.ps1` / `.sh`，不要单独执行 `compile_action.jsfl`。

注意：

- 被 `#include` 的 `.as` 丢 UTF-8 BOM 时 CS6 静默跳过内容（报 0/0、marker 正常但帧脚本 0 字节）。新增/重建 `.as` 必须保留 BOM
- `[TIMEOUT]` 会留 `scripts/compile_state_uncertain.marker` 卡住后续编译；人工确认 Flash / 计划任务已静止、`TestLoader.as` 已恢复后再删

## 用户约定

- **不擅自改 `flashswf/` 下的 XFL/XML**。要改 NPC 帧脚本这类资产，先在 `scripts/`（AS2 注入层）找绕开办法，改资产前先问
- **不往 `_root` 一级塞新属性**。新状态放二级容器，如作弊开关收在 `_root.cheatFlags.*`
- **作弊码不进存档**，只在本次游戏内有效
- **不乱改 `tools/` 已有脚本、不加参数**。一次性/补跑需求写 `tmp/` 下的一次性脚本，用完删

## 作弊码

- 开关：`_root.cheatFlags.强制显示NPC`（true 时 `初始化NPC` 不再用 `任务需求`/`任务需求支线` 挡人）；命令 `shownpc`（toggle，切换场景生效）。NPC 帧脚本里的"任务完成后消失"上界判定不归它管，需单独改 XFL
- 帮助三处：① 数据源 `GameSettingsPanelService.as` 的 `buildCheatHelp()`（≈747 行，硬编码数组，挑战模式只返回 3 条）；② C# `SettingsTask.IsValidCheatHelp()` 只校验；③ Web `settings-runtime.js` + `settings-panel.js` 的 `cheatCommandForm()` / `openCheatHelp()` / `renderCheatHelpDocument()`
- `classifyCheat()`（≈766 行）定 effectScope（read / session / save），不在 read/save 白名单的默认 `session`
- 执行链路（**仍在 AS2，没迁 Web**）：Web 只管输入与确认 UI → C# `NormalizeCheat`（校验 payload、command ≤240 字符、无控制字符）转 action `settingsCheat` → AS2 `GameSettingsPanelService` 的 `settingsCheat` 入口 → `executeCheat()` → `classifyCheat()`（null 报 `unknown_command`）→ `_root.cheatCode()` → `_root.cheatFunction[命令]()`
- 排查：新作弊码提示"无法识别"，几乎都是 `asLoader.swf` 没重新 publish。用 `status` 对照验证

## XFL / 深度的坑

- CS6 开着同项目时改 XFL 会触发它自动保存，顺带重写 `META-INF/metadata.xml`、`bin/SymDepend.cache` 和部分元件 xml（Edge 路径重排，几何等价但 diff 巨大）。看到非预期 diff 先查 `xmp:CreatorTool` / `MetadataDate`
- Twip Trick 后单位在 0~1048575 高深度带；authored 元件 native `swapDepths(this._y)` 只落几百的低带 → 永远被玩家压住。遇"地图元件/NPC 不再交换层级"先查有没有被 DepthManager 接管
- authored 子级的 onClipEvent(load)（含 `初始化NPC`）在 attachMovie 时同步执行，**早于** initGameWorld 建本场景 DepthManager（instance=null，AVM1 静默空操作）→ 其中的注册/劫持不可靠。兜底走 `SceneManager.initGameWorld → hijackAuthoredChildren`
- 素材库出生点 `swapDepths(-this._y)` = "永远在最底"，劫持后钳到 yMin 桶，语义保持

## 立绘管线

`tools/bake-dialogue-portraits.py` → `launcher/web/assets/dialogue-portraits/`（`external/` 外部 SWF 立绘、`internal/` 内置矢量肖像，带 manifest.json / report.json）。

- 外部立绘 3x 超采样 `--supersample 3`（FFDec 按 zoom×ss 渲染再 LANCZOS 降回，几何尺寸不变）
- **内置 sprite 不能超采样**：zoom>1 必抛 `InternalError: Odd number of new curves!`，只有 1x 能跑
- **`--semantic-baseline-dir` 默认等于输出目录，必须指向含旧产物的目录**：23 个内置空肖像靠它做 alpha 等价复用（保住 775 宽）；指向空目录会重导成 851 宽 = 回归
- 补跑/增量写 `tmp/` 下一次脚本（读已有导出 → 只重建 external → 写回 manifest），不动原脚本

## 图标管线（SWF 是唯一真源）

双通道：Flash 内 `attachMovie("图标-" + itemData.icon)` 读 `flashswf/arts/素材库-物品技能图标.swf`；Web/Launcher 读 `launcher/web/icons/manifest.json` + `*.webp`，由 `tools/bake-icons-offline.py` + `tools/ffdec/ffdec-cli.exe` **离线**扒出。`Icons.resolve()` 只查 manifest，**无 AS2 动态采样回退**。

加图标链路：① SVG → CS6 导入 XFL，勾"为 ActionScript 导出"，linkage 填 `图标-XXX`；② publish 图标库 SWF；③ 重跑 `python tools/linkage_scanner/scan_linkage.py`（冷启 ~3.5 分钟，缓存热 24 秒）——**不做这步 bake 报 `unresolved=missing_asset`**；④ `python tools/bake-icons-offline.py --name XXX,YYY`。

- 自查：`grep -l 'linkageExportForAS="true"' <元件>.xml`；`ffdec-cli.exe -export symbolClass <out> <swf>` 拿 `symbols.csv`（1.5 秒）确认符号表
- 环境：managed 3.13 **没 Pillow**，用系统 `C:/Users/Akatosh/AppData/Local/Programs/Python/Python310/python.exe`
- 耗时被 FFDec `-swf2xml` 吃掉（4.8MB → 254MB XML、191 秒，**必然超默认 120s**）；超时只让 sprite_graph 退化成空 → 静态首帧，对静态图标无害。9 个图标 ≈ 2 分钟
- 跳过行为：无 `--force-overwrite-existing` 时，一致 → `unchanged`；有差异 → `layout_protected`（**保留旧图**）；只有缺文件才 `created`
- **`data/items/asset_source_map.xml` 是 auto-generated，禁止手改**；易过期（曾发现 HEAD 版某背景 SWF 出现 0 次，重跑后冒出 33 条 conflict）

## 给 CS6 画 SVG 只能用保守子集

CS6 老导入器不支持 `<linearGradient>` + `fill="url(#id)"`、`<clipPath>`、`opacity`（Animate 支持，所以只有 CS6 丢色）。只用字面 `#RRGGBB`，渐变拆 2~3 段实色，半透明预先混色，最外层描边最后画来盖毛边。描边重量约 **2.3% 画布**（64 画布 → 主体 1.5）；中央标签别太大，否则 32px 糊成黑块。参考 `tmp/gen_potion_icons.py` 脚本头。

逐帧动效 SVG（Python 生成）的成套约束，参考 `tmp/天启大封印-特效/gen_shu_effects.py` + `_verify.py`：

- **非零环绕**：同一 `<polygon>` 拼多根小图形会把圆盘填实 → 每根各自成多边形
- **挖空环形/扇环**：外圈正走 + 内圈倒走一个多边形即可，不需 clipPath
- **循环无缝**：周期量走整数周期；验收 = `build(0)` 与 `build(N)` 逐坐标 0 差异
- **分段接缝**：爆发段相位用 `(i - (N-1)) / LOOP_N`（负相位）使末帧与循环首帧逐点相同
- **子段边界防顿帧**：消散段用 `u=(i-8)/6` 而非 `(i-9)/5`，否则与上一帧参数完全相同 = 顿帧
- **消散是"碎开飞散"不是"缩回"**；碎片基准半径独立常量（如 `ORB_SHARD_R=1.42`），共用底图半径会跟着缩成环
- 碎片采样密度按 span 折算（`fsteps = max(6, int(STEPS*span))`）；碎片夹画布内（`lim = min(cy,H-cy,cx,W-cx)-40`）
- **画布加高须同步放大**毛边频率、采样段数、光丝/浮尘数量，否则纹理变稀、边缘成节状直线
- 一次性段 + 循环段混排：SVG 只出两条序列，**循环由用户代码侧控制**
- 半透明出**两套配色**（不透明色 + CS6 手设不透明度 / 极暗色 + CS6「叠加」混合）

## 战技/技能的三层结构 · 元件里只写一行调用

用户要求：**元件帧脚本里只写一行函数调用，实现放 AS2 侧**，改逻辑不用回 CS6。

- **路由层**：`_root.主动战技函数[攻击模式][技能名]` = `{初始化, 释放许可判定, 释放}`（`单位函数_雾人_aka_fs_主动战技.as`）。按**具名键**读取，多挂键不冲突（没有 `for in` 遍历），技能接口函数可直接挂在条目对象上
- **实现层**：类放 `scripts/类定义/`（classpath 自动编译，不用注册 asLoaderManifest）；过程式放 `scripts/逻辑/单位函数/`
- **元件层**：`战技容器-<技能名>`（linkage 硬绑定，`ContainerSpec.LINKAGE_PREFIX_BATTLE_SKILL`）+ 子弹/视觉元件
- **既有惯例**：`_root.技能函数.XXX = function(){}`（144 条，`单位函数_lsy_主角技能.as`），容器里写 `掌炮攻击();`。**容器挂在 unit 下** → 帧脚本里 `this` = 容器、`this._parent` = 施术者

`scripts/逻辑/单位函数/*.as` 由 `scripts/asLoaderManifest/frame36.as` `#include`，**改完必须保留 UTF-8 BOM**。

## 封印领域（天启大封印）的 Z 轴口径

`SealDomain.as` 两套坐标并存，别混用：

- **起手选目标**：`按距离索敌`（`单位函数_fs_aka_玩家模板迁移.as`）双方都读 `Z轴坐标`，圆形欧氏距离
- **封印收押**：单位侧读 `单位.Z轴坐标`；中心侧只能读 `宿主._y`（宿主是 attachMovie 的子弹元件，没有 `Z轴坐标`），所以偏移换算全在中心侧做
- **判定圆心 = 视觉中心**：光柱元件为配合 Z 轴排序把**原点画在形状下端**，所以判定不能直接用 `宿主._y`，要 `中心Z = 宿主._y - 宿主Y偏移(SealDomain)= 宿主._y - 法阵Y偏移(主动战技.as)`。两处偏移常量**必须同步**（现为 80）；法阵元件里"贴着敌人脚下"的跟随也要带同一偏移（目标 `_y + 80`）
- **Z 判定现状（对称椭圆）**：`dz = 单位.Z轴坐标 - 中心Z`，`dx²/300² + dz²/80² ≤ 1`，无上下不对称、无 `下方容差Z`。落到宿主坐标 = `单位.Z轴坐标 ∈ [宿主._y - 160, 宿主._y]`：比宿主原点更靠下（Z 更大）的**一律收不到**
- 放逐 = 并集（带 `魔法抗性.凡俗` 标签收押当帧即逐，其余攒强度达标才逐）
- **⚠ for in 递归单位必须验 `子._parent === 节点`**：引用型动态属性（敌人身上存的攻击目标/技能元件引用等指向玩家的 clip）typeof 也是 "movieclip"，裸递归会把玩家当子元件 stop/play——这就是"封印/时停偶尔冻住玩家、控制结束才恢复"的根因（停时间轴 已加守卫；旧 时间停止.xml 的 for in stop 同病，迁移时若复用该模式要先修）
