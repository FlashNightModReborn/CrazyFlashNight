# 项目长期记忆

## 怎么编译（Flash CS6 自动化）

**本质**：脚本通过计划任务拉起 `Flash.exe` 跑 JSFL 自动执行 `doc.publish()` / `testMovie()`。省的是手动点击，**Flash CS6 仍在链路上**，没有脱离 CS6 的独立编译器。

### 命令

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 180
```

Git Bash 等价：`bash scripts/compile_test.sh -Target publish -TimeoutSeconds 180`

### 目标选择（改了哪层就编哪个）

| 改动位置                                                                        | 命令                |
| ------------------------------------------------------------------------------- | ------------------- |
| `scripts/类定义/`、\*`_WebView.as`、\*`PanelService.as`（注入 `_root`） | `-Target publish` |
| `scripts/TestLoader.as`、测试 class / fixture（要跑 trace 断言）              | `-Target test`    |
| `CRAZYFLASHER7MercenaryEmpire/`、`LIBRARY/*`、主时间轴、主文件 linkage      | `-Target main`    |
| `flashswf/UI                                                                    | levels              |

- `publish` / `main` 别名已隐含 publish-only 与自动 `-VerifySwf`，无需再写 `-PublishOnly`
- `-Target main` **不会**更新 `scripts/asLoader.swf`；改注入层逻辑必须用 `publish`
- 不用手动预先打开 XFL：`-Target` 会自己 close+reopen 从磁盘重读
- `scripts/类定义/` 下的类走 classpath 自动编译，不在 `asLoaderManifest` 里，新增类 import 即可，不需注册清单

### 成功判据（两条同时成立才算过）

1. `scripts/compiler_errors.txt` 属于本轮、内容严格 `0 个错误 / 0 个警告`
2. 目标 SWF 已刷新（asLoader 即 `scripts/asLoader.swf`）

`publish_done.marker` 单独出现不算通过。publish-only 不产行为 trace，`flashlog.txt` 不刷新属正常。

### 前提条件

- 以管理员身份跑过 `scripts/setup_compile_env.bat`（注册 `CompileTriggerTask` / `FlashCS6Task`，必须 `RunLevel=Highest`）
- Flash CS6 可启动；换机器或改过编译脚本后重跑一次 setup
- Node.js 在 PATH（TestLoader 目标是硬门，缺 `node` 直接不触发 Flash）
- 唯一受支持入口是 `compile_test.ps1` / `compile_test.sh`；不要单独执行 `compile_action.jsfl`

### 注意

- 被 `#include` 的 `.as` 丢 UTF-8 BOM 时 CS6 静默跳过内容：Compiler 报 0/0、marker 正常，但帧脚本 0 字节，smoke 抓不到。新增/重建 `.as` 必须保留 BOM
- `[TIMEOUT]` 会留 `scripts/compile_state_uncertain.marker` 卡住后续编译；需人工确认 Flash / 计划任务已静止、`TestLoader.as` 已恢复后再删
- 现在编译环境没好，除非用户要求，否则不必编译

## 用户约定

- **不要擅自改 `flashswf/` 下的 XFL/XML**。需要改 NPC 帧脚本这类资产时，先在 `scripts/`（AS2 注入层）找能绕开的办法，改资产前先问过用户
- **不要往 `_root` 一级塞新属性**（_root 已经太臃肿）。新状态统一放二级容器，如作弊开关全部收在 `_root.cheatFlags.*` 下
- **作弊码不进存档**，只在本次游戏内有效
- **别乱改 `tools/` 下已有脚本、也别乱加参数**。一次性/补跑类需求写成 `tmp/` 下的一次性脚本，用完删掉；已有脚本只保留用户明确要的那项改动（如"外部超采样"）

### 现有作弊开关（_root.cheatFlags）

- `强制显示NPC`：true 时 `_root.初始化NPC` 不再用 `任务需求` / `任务需求支线` 挡人
- 命令：`shownpc`（toggle，切换场景生效）。各 NPC 帧脚本里的"任务完成后消失"上界判定不归它管，需单独在 XFL 里改

### Web 设置面板"作弊码帮助"的三处位置

1. **数据生成（AS2，唯一数据源）**：`scripts/类定义/org/flashNight/arki/ui/GameSettingsPanelService.as` → `buildCheatHelp()`（约 747 行），硬编码 `{command, description, effectScope}` 数组。挑战模式下只返回 3 条模式切换命令
2. **校验转发（C#）**：`launcher/src/Tasks/SettingsTask.cs` 的 `IsValidCheatHelp()`，只校验不生产
3. **渲染（Web）**：`launcher/web/modules/settings-runtime.js`（接收 `cheatHelp`）+ `launcher/web/modules/settings-panel.js` 的 `cheatCommandForm()` / `openCheatHelp()` / `renderCheatHelpDocument()`

`classifyCheat()`（同文件约 766 行）决定每条命令的 effectScope（read / session / save）。不在 read/save 白名单里的 `cheatFunction` 命令默认落 `session`，即"本次运行有效"

### 作弊码执行链路（**执行仍在 AS2，没迁到 Web**）

Web 输入框 → C# `SettingsTask` → AS2 `GameSettingsPanelService`，三段职责：

1. **Web**（`settings-panel.js`）：只管输入、二次确认 UI、帮助弹窗渲染，不做命令校验
2. **C#**（`SettingsTask.NormalizeCheat`）：校验 payload 形状（v/command/confirmed）、command ≤240 字符、无控制字符，转成 action `settingsCheat` 转发给 Flash
3. **AS2**（`GameSettingsPanelService`）：“settingsCheat” 入口（约 40 行）→ `executeCheat()`（约 283 行）→ `classifyCheat()` 定 effectScope（返回 null 就报 `unknown_command`，web 显示"无法识别该作弊码"）→ `_root.cheatCode(command)` → `_root.cheatFunction[命令]()`

**排查要点**：新增作弊码后 web 上提示"无法识别该作弊码"，几乎都是 `scripts/asLoader.swf` 没重新 publish，`_root.cheatFunction` 里还没有这个命令。可用已有命令（如 `status`）对照验证

### 编辑 XFL 的坑

Flash CS6 若正开着同项目，外部改 XFL 会触发它自动保存，顺带重写 `META-INF/metadata.xml`、`bin/SymDepend.cache` 和部分元件 xml（Edge 路径重排，几何等价但 diff 巨大）。看到非预期 diff 先查 `xmp:CreatorTool` / `MetadataDate` 判断是不是 CS6 写的，别误判成自己的改动

### 深度管理器与 swapDepths 接管的坑（2026-09-09）

- Twip Trick 后单位都在 0~1048575 高深度带；authored 元件 native `swapDepths(this._y)` 只落几百的低带 → 永远被玩家压住。凡遇"地图元件/NPC 不再和玩家交换层级"，先查它有没有被 DepthManager 接管
- authored 子级的 onClipEvent(load)（含 初始化NPC）在 attachMovie 时同步执行，**早于** initGameWorld 创建本场景 DepthManager（此时 instance=null，AVM1 静默空操作）→ 初始化NPC 里的注册/劫持在场景加载时序下不可靠。兜底：SceneManager.initGameWorld → hijackAuthoredChildren（续38）
- 素材库出生点的 `swapDepths(-this._y)` = "永远在最底"；劫持后被钳到 yMin 桶，语义保持

## 对话立绘管线

`tools/bake-dialogue-portraits.py` → `launcher/web/assets/dialogue-portraits/`（`external/` 外部 SWF 立绘、
`internal/` 对话框界面.swf 内置矢量肖像，同目录带 manifest.json / report.json）。

- 外部立绘走 3x 超采样：`--supersample 3`（FFDec 按 zoom×ss 渲染，再用 LANCZOS 降回，产物几何尺寸不变）
- **内置 sprite 不能超采样**：FFDec 在 zoom>1 渲染它必抛 `InternalError: Odd number of new curves!`，只有 1x 能跑
- **`--semantic-baseline-dir` 默认等于输出目录，必须指向含旧产物的目录**：23 个内置空肖像靠它做
  alpha 等价复用（保住 775 宽）；输出到全新空目录会让它们被重导成 851 宽，属回归
- 补跑/增量应用写成 `tmp/` 下一次性脚本（读已有导出目录 → 只重建 external 条目 → 写回 manifest），不要动原脚本

## 图标管线（SWF 是唯一真源）

**双通道**：Flash 内 HUD/tooltip 直接 `attachMovie("图标-" + itemData.icon)` 读
`flashswf/arts/素材库-物品技能图标.swf`；Web/Launcher 面板读 `launcher/web/icons/manifest.json`
+ `*.webp`，由 `tools/bake-icons-offline.py` 用 `tools/ffdec/ffdec-cli.exe` **离线**从 SWF 扒出。
`Icons.resolve()` 只查 manifest，**无 AS2 动态采样回退**，缺条目就是空图。

**加图标的完整链路**：
1. SVG → CS6 导入 XFL，元件勾"为 ActionScript 导出"，linkage 填 `图标-XXX`
2. publish 出 `素材库-物品技能图标.swf`
3. 重跑 `python tools/linkage_scanner/scan_linkage.py`（纯解析 XFL/FLA；冷启 ~3.5 分钟，
   文件缓存热时 24 秒）。**这步不做，bake 会报 `unresolved=missing_asset`**——map 里没有新元件
4. `python tools/bake-icons-offline.py --name XXX,YYY`（逗号分隔）

**自查捷径**：`grep -l 'linkageExportForAS="true"' <元件>.xml` 查 XFL；
`ffdec-cli.exe -export symbolClass <out> <swf>` 拿到 `symbols.csv`（char id;linkageId，1.5 秒）
即可确认 SWF 符号表，不必跑整条 bake。

**跑 bake 的环境**：managed 3.13 **没 Pillow**，沙箱内 pip 装不上；**系统 Python 3.10 自带
Pillow**，用它：`C:/Users/Akatosh/AppData/Local/Programs/Python/Python310/python.exe`。

**耗时**：基本被 FFDec `-swf2xml` 吃掉（图标库 4.8MB → 254MB XML、191 秒，**必然超过默认
120s timeout**）。超时只是 `spriteGraphErrors=swf_xml_timeout`，sprite_graph 退化成空、
nested audit 归零 → 静态首帧，对静态图标无害。9 个图标的完整 `--name` 烘焙 ≈ **2 分钟**
（`--ffdec-timeout-seconds 300` 则 ~3.5 分钟）。

**跳过行为（默认安全）**：不带 `--force-overwrite-existing` 时，渲染结果与磁盘一致 → `unchanged`；
有差异 → `layout_protected`（**保留旧图**，只记 report）；只有缺文件才 `created`。
另有 source-aware refresh：既有图标 provenance 可信且源 SWF 与渲染像素都变了才允许自动覆盖。

**`data/items/asset_source_map.xml` 是 auto-generated，禁止手改**；它是手工重跑的，容易过期
（曾发现 HEAD 版里某背景 SWF 出现 0 次，重跑后冒出 33 条 conflict）。

### 给 CS6 画 SVG 只能用保守子集

CS6 老导入器不支持 `<linearGradient>` + `fill="url(#id)"`、`<clipPath>`、`opacity`；
Animate 支持，所以只有 CS6 会"丢色"。规则：只用字面 `#RRGGBB` 填充/描边，渐变拆成 2~3 段
实色色带，半透明预先混色成实色，最外层描边放到最后画来盖色带毛边。
描边重量对齐素材库既有图标约 **2.3% 画布**（64 画布 → 主体 1.5）；中央标签别太大，
否则 32px 下糊成黑块。参考 `tmp/gen_potion_icons.py` 脚本头。

#### 逐帧动效 SVG（Python 脚本生成）的成套约束

参考实现 `tmp/天启大封印-特效/gen_shu_effects.py`（41KB）+ 配套 `_verify.py` 自检：

- **非零环绕规则**：同一 `<polygon>` 里拼多根小图形会把圆盘填实 → 每根各自成多边形
- **挖空环形/扇环**：外圈正走 + 内圈倒走一个多边形即可，**不需要 clipPath**
- **循环无缝**：周期量必须走整数周期；验收 = `build(0)` 与 `build(N)` 逐坐标比对 = 0 差异
- **分段序列接缝**：爆发段相位用 `(i - (N-1)) / LOOP_N`（负相位），使末帧与循环首帧逐点相同
- **子段边界防顿帧**：消散段若用 `u=(i-9)/5`，i=9 的 u=0 会与上一段收尾完全重合 → 用
  `u=(i-8)/6`。自检里加"与上一帧参数完全相同"检测能提前抓到这类顿帧
- **消散语义**：用户要的是"碎开飞散"而非"缩回"，别只用宽度/长度收到 0 表达
- **碎片基准半径要独立常量**（如 `ORB_SHARD_R = 1.42`），共用底图半径会让碎片跟着缩成环
- **碎片采样密度按 span 折算**（`fsteps = max(6, int(STEPS * span))`），否则体积翻 6 倍
- **碎片夹画布内**（`lim = min(cy, H-cy, cx, W-cx) - 40`），否则朝上碎片被上沿硬切直边
- **画布加高必须同步放大**边缘毛边频率、采样段数、光丝/浮尘数量，否则纹理变稀、边缘成
  一节节长直线
- 一次性段 + 循环段的混排：SVG 只出两条序列，**循环由用户代码侧控制**
- 半透明要出**两套配色**（不透明色 + CS6 手设不透明度 / 极暗色 + CS6「叠加」混合），
  因为脚本无法预知用户选哪种混合模式

### 战技/技能的三层结构 · 元件里只写一行调用

用户明确要求：**元件的帧脚本里只写「一行函数调用」，实现放 AS2 侧**，方便后续改而不用回 CS6。

- **路由层**：`_root.主动战技函数[攻击模式][技能名]` = `{初始化, 释放许可判定, 释放}`
  （`单位函数_雾人_aka_fs_主动战技.as`）。消费方只按**具名键**读这三个，**往同一对象上
  多挂键不冲突**（没有 `for in` 遍历）——所以技能自己的接口函数可以直接挂在条目对象上。
- **实现层**：类放 `scripts/类定义/`（走 classpath 自动编译，**不用注册 asLoaderManifest**）；
  过程式实现放 `scripts/逻辑/单位函数/`。
- **元件层**：`战技容器-<技能名>`（linkage 是硬绑定，`ContainerSpec.LINKAGE_PREFIX_BATTLE_SKILL`）
  + 子弹/视觉元件。

**既有惯例**：`_root.技能函数.XXX = function(){...}`（144 条，在 `单位函数_lsy_主角技能.as`），
容器里写 `掌炮攻击();` 这种一行调用。**容器挂在 unit 下** → 容器帧脚本里
`this` = 容器、`this._parent` = 施术者。要把单位/容器引用传给函数就这么取。

`scripts/逻辑/单位函数/*.as` 由 `scripts/asLoaderManifest/frame36.as` `#include`，
**改完必须保留 UTF-8 BOM**，否则 CS6 静默跳过内容。
