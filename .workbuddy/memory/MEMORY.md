# 项目长期记忆

## 编译（Flash CS6 自动化）

计划任务拉起 `Flash.exe` 跑 JSFL 自动 `publish()`/`testMovie()`；省的是手动点击，**CS6 仍在链路上**。
`powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 180`（Git Bash 用 `.sh`）。唯一入口，别单独跑 `compile_action.jsfl`。

| 改动位置 | Target |
| --- | --- |
| `scripts/类定义/`、`*_WebView.as`、`*PanelService.as`（注入 `_root`） | `publish` |
| `TestLoader.as`、测试 class / fixture（要 trace 断言） | `test` |
| `CRAZYFLASHER7MercenaryEmpire/`、`LIBRARY/*`、主时间轴、主文件 linkage | `main`（**不更新 asLoader.swf**） |
| `flashswf/UI levels` | levels |

- `publish`/`main` 别名隐含 publish-only + 自动 `-VerifySwf`；`-Target` 自己 close+reopen 从磁盘重读，不用预先开 XFL
- `scripts/类定义/` 走 classpath 自动编译，不在 `asLoaderManifest` 里，新类 import 即可
- **编译环境没好时不要编，除非用户要求**。前提：管理员跑过 `setup_compile_env.bat`（两个计划任务须 `RunLevel=Highest`）、Node.js 在 PATH
- 成功判据（两条同时成立）：① `scripts/compiler_errors.txt` 属本轮且严格 0 错 0 警；② 目标 SWF 已刷新。`publish_done.marker` 单独出现不算；publish-only 不产 trace，`flashlog.txt` 不刷新正常
- 被 `#include` 的 `.as` 丢 BOM → CS6 静默跳过（报 0/0、marker 正常但帧脚本 0 字节）；新增/重建必须保 BOM
- `[TIMEOUT]` 留 `compile_state_uncertain.marker` 卡后续编译；确认 Flash/任务静止后再删

## 用户约定

- **不擅自改 `flashswf/` 下的 XFL/XML**；要改 NPC 帧脚本这类资产先在 `scripts/`（AS2 注入层）找绕开办法，改资产前先问
- **不往 `_root` 一级塞新属性**，新状态放二级容器（如 `_root.cheatFlags.*`）
- **作弊码不进存档**，只在本次游戏内有效
- **不乱改 `tools/` 已有脚本、不加参数**；一次性/补跑写 `tmp/` 一次性脚本，用完删

## 作弊码

- 开关 `_root.cheatFlags.强制显示NPC`（true 时 `初始化NPC` 不再被 `任务需求`/`任务需求支线` 挡）；命令 `shownpc`（toggle，切场景生效）。NPC 帧脚本里"任务完成后消失"的上界判定不归它管
- 帮助三处：① 数据源 `GameSettingsPanelService.as` 的 `buildCheatHelp()`（≈747 行硬编码数组，挑战模式只返 3 条）② C# `SettingsTask.IsValidCheatHelp()` 只校验 ③ Web `settings-runtime.js`/`settings-panel.js` 的 `cheatCommandForm()`/`openCheatHelp()`/`renderCheatHelpDocument()`
- `classifyCheat()`（≈766）定 effectScope（read/session/save），不在 read/save 白名单的默认 `session`
- 链路（**仍在 AS2，没迁 Web**）：Web 输入与确认 UI → C# `NormalizeCheat`（校验 payload、command ≤240 字、无控制字符）转 action `settingsCheat` → AS2 `GameSettingsPanelService.settingsCheat` → `executeCheat()` → `classifyCheat()`（null 报 `unknown_command`）→ `_root.cheatCode()` → `_root.cheatFunction[命令]()`
- 新作弊码提示"无法识别"几乎都是 `asLoader.swf` 没重新 publish

## XFL / 深度的坑

- CS6 开着同项目时改 XFL 会触发自动保存，顺带重写 `META-INF/metadata.xml`、`bin/SymDepend.cache` 和部分元件 xml（Edge 路径重排，几何等价但 diff 巨大）。看到非预期 diff 先查 `xmp:CreatorTool`/`MetadataDate`
- Twip Trick 后单位在 0~1048575 高深度带；authored 元件 native `swapDepths(this._y)` 只落几百的低带 → 永远被玩家压住。遇"地图元件/NPC 不再交换层级"先查有没有被 DepthManager 接管
- authored 子级的 `onClipEvent(load)`（含 `初始化NPC`）在 attachMovie 时同步执行，**早于** initGameWorld 建本场景 DepthManager（instance=null，AVM1 静默空操作）→ 注册/劫持不可靠，兜底走 `SceneManager.initGameWorld → hijackAuthoredChildren`
- 素材库出生点 `swapDepths(-this._y)` = "永远在最底"，劫持后钳到 yMin 桶，语义保持

## 立绘管线

`tools/bake-dialogue-portraits.py` → `launcher/web/assets/dialogue-portraits/`（`external/` 外部 SWF、`internal/` 内置矢量肖像，带 manifest.json/report.json）

- 外部立绘 3x 超采样 `--supersample 3`（FFDec 按 zoom×ss 渲染再 LANCZOS 降回，几何尺寸不变）；**内置 sprite 不能超采样**：zoom>1 必抛 `InternalError: Odd number of new curves!`，只有 1x 能跑
- **`--semantic-baseline-dir` 默认等于输出目录，必须指向含旧产物的目录**：23 个内置空肖像靠它做 alpha 等价复用（保住 775 宽）；指向空目录会重导成 851 宽 = 回归
- 补跑/增量写 `tmp/` 一次性脚本（读已有导出 → 只重建 external → 写回 manifest），不动原脚本

## 图标管线（SWF 是唯一真源）

双通道：Flash 内 `attachMovie("图标-" + itemData.icon)` 读 `flashswf/arts/素材库-物品技能图标.swf`；Web/Launcher 读 `launcher/web/icons/manifest.json` + `*.webp`，由 `tools/bake-icons-offline.py` + `tools/ffdec/ffdec-cli.exe` **离线**扒出。`Icons.resolve()` 只查 manifest，**无 AS2 动态采样回退**。

加图标：① SVG → CS6 导入 XFL（勾"为 ActionScript 导出"，linkage `图标-XXX`）② publish 图标库 SWF ③ 重跑 `python tools/linkage_scanner/scan_linkage.py`（冷启 ~3.5 分钟，缓存热 24 秒；**不做这步 bake 报 `unresolved=missing_asset`**）④ `python tools/bake-icons-offline.py --name XXX,YYY`

- 环境：managed 3.13 **没 Pillow**，用系统 `C:/Users/Akatosh/AppData/Local/Programs/Python/Python310/python.exe`
- 耗时被 FFDec `-swf2xml` 吃掉（4.8MB → 254MB XML、191 秒，**必然超默认 120s**）；超时只让 sprite_graph 退化成空 → 静态首帧，无害。9 个图标 ≈ 2 分钟
- 跳过行为（无 `--force-overwrite-existing`）：一致 → `unchanged`；有差异 → `layout_protected`（**保留旧图**）；只有缺文件才 `created` → **增量加图标天然安全**。`--name` 收**裸名**（不带 `图标-` 前缀），逗号分隔或重复多次都行；`--dry-run` 只跑不写
- 成功判据 `tmp/icon-bake-offline-report.json`：`created=1 / processed=1`、`unresolvedSummary` 空、`protectExistingLayout: true`；自查符号表用 `grep -l 'linkageExportForAS="true"' <元件>.xml` 或 `ffdec-cli.exe -export symbolClass <out> <swf>`（1.5 秒）
- ⚠ 启动清空 `tmp/icon-bake-offline` 时可能被拦成 `[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]` 打一行就退出——**无害噪声，产物已落盘**（对照 manifest 与 `ls -lat launcher/web/icons/*.webp` 确认）
- **`data/items/asset_source_map.xml` auto-generated，禁止手改**，且常落后于库里实际元件（新增元件不重扫就不进表）→ 看到"少条目"先重扫；**重扫后必做差分核对**：备份旧 map → 按 `<asset id=... swf=... symbolName=...>` 解析成 dict → 比 `新增/消失/改指向`，正常是"纯新增、消失 0、改指向 0"；`grep -c '<asset '` 与正则计数口径不同，别拿两个数相减

## 给 CS6 画 SVG 只能用保守子集

CS6 老导入器不支持 `<linearGradient>`+`fill="url(#id)"`、`<clipPath>`、`opacity`（Animate 支持，所以只有 CS6 丢色）。只用字面 `#RRGGBB`，渐变拆 2~3 段实色，半透明预先混色，最外层描边最后画来盖毛边。描边重量约 **2.3% 画布**（64 画布 → 主体 1.5）；中央标签别太大，否则 32px 糊成黑块。参考 `tmp/gen_potion_icons.py` 脚本头。

逐帧动效 SVG（Python 生成）成套约束，参考 `tmp/天启大封印-特效/gen_shu_effects.py` + `_verify.py`：

- **非零环绕**：同一 `<polygon>` 拼多根小图形会把圆盘填实 → 每根各自成多边形；**挖空环形/扇环** = 外圈正走 + 内圈倒走一个多边形，不需 clipPath
- **循环无缝**：周期量走整数周期；验收 = `build(0)` 与 `build(N)` 逐坐标 0 差异。**分段接缝**：爆发段相位用 `(i-(N-1))/LOOP_N`（负相位）使末帧与循环首帧逐点相同
- **子段边界防顿帧**：消散段用 `u=(i-8)/6` 而非 `(i-9)/5`，否则与上一帧参数完全相同 = 顿帧
- **消散是"碎开飞散"不是"缩回"**；碎片基准半径独立常量（如 `ORB_SHARD_R=1.42`），共用底图半径会跟着缩成环；碎片夹画布内（`lim = min(cy,H-cy,cx,W-cx)-40`、`fsteps = max(6, int(STEPS*span))`）
- **画布加高须同步放大**毛边频率、采样段数、光丝/浮尘数量，否则纹理变稀、边缘成节状直线
- 一次性段 + 循环段混排：SVG 只出两条序列，**循环由用户代码侧控制**；半透明出**两套配色**（不透明色 + CS6 手设不透明度 / 极暗色 + CS6「叠加」混合）

## 战技/技能的三层结构 · 元件里只写一行调用

用户要求：**元件帧脚本里只写一行函数调用，实现放 AS2 侧**，改逻辑不用回 CS6。

- **路由层**：`_root.主动战技函数[攻击模式][技能名]` = `{初始化, 释放许可判定, 释放}`（`单位函数_雾人_aka_fs_主动战技.as`）。按**具名键**读取，多挂键不冲突。攻击模式由 `获取装备主动战技种类(槽位, use)` 映射：刀→兵器、长枪→长枪、手部装备→空手、手枪→手枪/手枪2
- **实现层**：类放 `scripts/类定义/`（classpath 自动编译）；过程式放 `scripts/逻辑/单位函数/`。**元件层**：`战技容器-<技能名>`（linkage 硬绑定，`ContainerSpec.LINKAGE_PREFIX_BATTLE_SKILL`）+ 子弹/视觉元件
- **惯例**：`_root.技能函数.XXX`（144 条，`单位函数_lsy_主角技能.as`），容器里写 `掌炮攻击();`。**容器挂在 unit 下** → 帧脚本里 `this` = 容器、`this._parent` = 施术者
- `scripts/逻辑/单位函数/*.as` 由 `frame36.as` `#include`；`scripts/逻辑/装备函数/*.as` 由 `frame37.as`（f37_1..8 chunk）`#include`——两处**改完必须保留 UTF-8 BOM**

### 战技数据字段与 tooltip

字段：`skillname`/`description`/`cd`(毫秒)/`hp`/`mp`/`sp`/`level`。

- **`<skill>` 两种语义**：有 `<skillname>` = 真战技；只有文本 = **说明文本**（防具【喷气背包】、镰刀【地面战技】之类），`装载主动战技` 因缺 skillname 直接置 null → 判类型看 `skill.skillname`
- 战技也可声明在 `<lifecycle><attr_N><skill>` 或 `<initParam><skill_N>`（装备初始化函数自己读），此时**根层没有 `itemData.skill`**
- `sp` = 技能点消耗，在 `单位函数_fs_aka_玩家模板迁移.as:1851` 读成 `当前战技.消耗sp`（余额校验与扣除在「释放主动战技」里）
- **【战技信息】行拼装在 `TooltipTextBuilder.buildSkillInfo`，两条分支改一处必须同步另一处**：① `skill.description` 存在 ② 只有 `skillname` 的结构化对象。都走「冷却 → 消耗HP → 消耗MP → 消耗SP」，后缀常量 `TooltipConstants.SUF_*`（`SUF_SP="SP"`），`sp` 缺省或 0 不显示。物料走 `ModStatBuilder.buildSkillInfo(modData.skill)`，取 `item.skill` 原始对象 → XML 加字段即可显示
- 同名的 `_root.技能栏技能图标注释`/`_root.学习界面技能图标注释` 读的是**另一套数据**（`_root.技能表对象`/`_root.技能表`，用 `MP`/`UnlockSP` 大写键），与战技无关

## 装备插件的安装校验（战技插件 / 下挂武器）

单一入口 `EquipmentUtil.isModMaterialAvailable` → **`TagManager.checkModAvailability(item, itemData, modName)`**（`.../arki/item/equipment/TagManager.as`）。安装、原子替换、属性试算三条路都走它；状态码文案表在 `EquipmentUtil.modAvailabilityResults`（-4 = "配件无法覆盖装备原本的主动战技"），经 `EquipmentTuningService.modAvailabilityReason()` 投影给 Web。

- 特殊槽：`主动战技[攻击模式]` 一个槽，普通战技与**长枪副武器**（`<subweapon>` / 下挂武器插件）共用
- `EquipmentCalculator.calculateInPlace` 收尾：`modifiers.subweapon` 优先，**else if** `modifiers.skill` 覆盖 `itemData.skill`。即战技插件是**替换**本体战技（可撤回），副武器插件**不清**本体战技 → 有战技的装备装下挂武器会双占用，必须继续拒绝
- **2026-09-13 起**：装备自带战技**默认允许被战技插件覆盖**（原来一律 -4）。仍 -4 只有三种：① `itemData.subweapon` ② 声明战技处写了 `<skillLocked>true</skillLocked>`（专属/定制/生命周期绑定的战技；**缺省 = 可更换**）③ 根层 `<skill>` 无 skillname（说明文本）
- 标记**跟着战技走**：作为**子元素**写在声明该战技的 `<skill>` / `<skill_N>` 元素内（用户要求，**既不要放 `<item>` 根层、也不要写成属性**）。**正向命名 `skillLocked`（值 `true`）**，不用反向的 `skillReplaceable=false` —— 用户："很明显这个语义才适合可选参数"。判定入口 `TagManager.isSkillReplaceableLocked()`：先看根 `itemData.skill.skillLocked`，再扫 `lifecycle.attr_N.skill` 与 `lifecycle.attr_N.init.initParam.skill_M`，三处都是严格 `=== true`
- **属性 vs 单文本子元素在 AS2 侧完全等价**：XMLParser `parseXMLNodeInner` 对属性走 `result[attr]=convertDataTypeFast(attrs[attr])`，对「单文本子节点」走 `childValue=convertDataTypeFast(cChildren[0].nodeValue)`，同一函数 → `"false"` 都变布尔 false。**唯一差别**是属性在子节点循环之前写入，若属性与子元素撞名会被数组提升成 `[属性值,子元素值]`；空元素写法会解析成 `""` 而非布尔。工具侧（`tools/cf7-balance-tool`）两种写法都会多出一个未注册字段，等价
- 当时口径：含真实战技 217 件（刀 183/手部装备 22/长枪 12）→ **锁定 46 件（52 处标记）**、可换 171；另 10 件根层 `<skill>` 是说明文本、11 件带 `<subweapon>`。其中 5 件根层没有带 skillname 的 `<skill>`，标记落在 lifecycle：远古诛神剑（initParam.skill_0）、龙破军霜（attr_0/skill）、炎魔斩new（skill_0/1）、键盘镰刀（skill_0/1）、吉他喷火器（skill_0）。共用技能名的"凑数战技"全部保持可换（弧光斩/滑步/凶斩/追踪五连/回旋斩击/回旋裂地/狼跳/突刺/破坏殆尽/旋风腿/黑刀斩术/深冲利刺/瞬步斩/飞身踢/震地/旋转抡枪），它们本就是插件可授予的（护手→弧光斩、配重坠→回旋裂地、手柄皮→凶斩、环格护手→追踪五连、震动吸收器→破坏殆尽、燕归沉→一文字落雷、三蝶手稿→天启大封印（刀/手部装备/长枪）、骨誓铭牌→黑刀斩术|震地、骨芯颅印→滑步、骨约晨星→闪现、绳扣穿孔片→长枪旋转抡枪）
- **改完必做「应锁集合独立重算」**：全库扫出「含真战技 且（带 lifecycle 或 战技名全局唯一）」的应锁名单，与实际标记逐名**双向**比对（漏标 + 多标）。此前就是靠这步发现 `杀戮风暴`（镰刀，lifecycle 自转机制）漏标 —— 早期迁移脚本的遗留
- 改造人巨拳的「血肉洪流」description 自己写着「暂未实装」，全仓仅 XML 一处出现、`_root.主动战技函数` 无此键 → 该战技实际是死的（锁着等于白锁，待用户定夺）
- 回归测试在 `EquipmentTestSuite.as`（`testTagManager_StatusCode_SkillReplaceable`/`_SkillLocked`/`_SkillLockedWithoutRootSkill`；原 `_SkillConflict` 的 fixture skill 无 skillname，仍是 -4）

## 封印领域（天启大封印）的 Z 轴口径

`SealDomain.as` 两套坐标并存：

- **起手选目标**：`按距离索敌`（`单位函数_fs_aka_玩家模板迁移.as`）双方都读 `Z轴坐标`，圆形欧氏距离
- **封印收押**：单位侧读 `单位.Z轴坐标`；中心侧只能读 `宿主._y`（宿主是 attachMovie 的子弹元件，没有 `Z轴坐标`），偏移换算全在中心侧做
- **判定圆心 = 视觉中心**：光柱元件为配合 Z 排序把**原点画在形状下端**，所以 `中心Z = 宿主._y - 宿主Y偏移(SealDomain) = 宿主._y - 法阵Y偏移(主动战技.as)`。两处偏移常量**必须同步**（现 80）；法阵"贴敌人脚下"的跟随带同一偏移（目标 `_y + 80`）
- **Z 判定（对称椭圆）**：`dz = 单位.Z轴坐标 - 中心Z`，`dx²/300² + dz²/80² ≤ 1`，无上下不对称。落到宿主坐标 = `单位.Z轴坐标 ∈ [宿主._y-160, 宿主._y]`：比宿主原点更靠下（Z 更大）的**一律收不到**
- 放逐 = 并集（带 `魔法抗性.凡俗` 标签收押当帧即逐，其余攒强度达标才逐）
- **⚠ for in 递归单位必须验 `子._parent === 节点`**：引用型动态属性（敌人身上存的攻击目标/技能元件引用等指向玩家的 clip）typeof 也是 "movieclip"，裸递归会把玩家当子元件 stop/play——"封印/时停偶尔冻住玩家、控制结束才恢复"的根因（停时间轴 已加守卫；旧 时间停止.xml 的 for in stop 同病）
