# CF6 僵尸重绘资产原生装配与数值接入 (`tools/cf6-zombie-assets`)

**文档角色**：`flashswf/arts/new/Antigravity专用素材/` 独立 XFL 库中两只《闪客快打 6》重绘僵尸（`敌人-CF6普通男僵尸`、`敌人-CF6女僵尸`）的确定性装配、阶段 6 数值配表与专项验证说明。

## 1. 单位注册与阶段 6 数值

两只重绘僵尸分别继承原版《闪客快打 7》黄衣男僵尸（`敌人-黄色衣服男僵尸1`）与金发红衣女僵尸（`敌人-金发红衣服女僵尸1`）的 9 项非阶段标识系数、移速、躲闪率、重量、韧性系数与抗性，并将 `<阶段>` 设为 `6`，由官方怪物公式 `tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts` 正算 8 项面板整数值：

| 兵种 ID | 内部 Linkage | 显示名 (`displayname`) | 模板继承源 | 阶段 | 经验值 (`min..max`) | 生命 (`hp_min..max`) | 空手攻击 (`atk_min..max`) | 基本防御 (`def_min..max`) | 速度 (`min..max`) | 重量 / 韧性 |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| `461` | `敌人-CF6普通男僵尸` | `CF6黄衣僵尸` | `敌人-黄色衣服男僵尸1` | `6` | `126..1696` | `1345..5682` | `70..306` | `87..443` | `15..25` | `60` / `0.6` |
| `462` | `敌人-CF6女僵尸` | `CF6红衣僵尸` | `敌人-金发红衣服女僵尸1` | `6` | `112..1707` | `1097..5425` | `66..332` | `79..445` | `10..15` | `50` / `0.5` |

- **敌人属性表**：`data/enemy_properties/CF6重制敌人.xml`（已登记入 `data/enemy_properties/list.xml`）
- **单位注册表**：`data/units/units.json`（`id: 461`、`id: 462`）
- **标识账本**：`tools/cf7-balance-tool/data/monster-flag-ledger.json`（`claims` 登记两单位完整 10 项标识）
- **公式核对账本**：`tools/cf6-zombie-assets/balance-inputs.json`

## 2. 源稿归档与目标工作区

| 角色 | 路径 | 说明 |
|---|---|---|
| 源稿归档（只读） | `flashswf/arts/new/Antigravity素材源稿/CF6普通男僵尸-R5/`<br>`flashswf/arts/new/Antigravity素材源稿/CF6女僵尸-R2/` | 保存来自 R5 / R2 交付包的 SVG 矢量分件、碎尸 SVG、时间轴与图集偏移 JSON、交接文档；不含预览 PNG/GIF 与原始位图图集 |
| 原生工作区 XFL | `flashswf/arts/new/Antigravity专用素材/Antigravity专用素材.xfl` | Antigravity 独立作者空间 XFL 库，成为导入后的唯一美术编辑源 |
| 发布产物 SWF | `flashswf/arts/new/Antigravity专用素材.swf` | 由 Flash CS6 从 `Antigravity专用素材.xfl` 真实编译产出，并通过 `flashswf/arts/things-new.fla` (`things-new.swf`) 挂入运行时共享库链 |
| 导入清单 | `tools/cf6-zombie-assets/native-manifest.json` | v2 清单分别记录元件 `outputs` 与四个工程文件 `projectFiles` 的 SHA-256、字节数，并校验 LIBRARY 文件集合；各角色与总元件数以该清单为准 |

重新导入前检查元件、`DOMDocument.xml`（含时间轴、Include 和媒体登记）、XFL 入口、`PublishSettings.xml`、`MobileSettings.xml`，以及库文件的新增和删除；生成完成后、开始写入前再次检查。缺失清单或只有旧版元件清单的已有工程拒绝覆盖，空目录允许首次导入。`--force` 明确放弃这些覆盖保护，仅在确认放弃对应人工编辑后使用；它不会删除额外库文件，检查仍会报告这些文件。正常美术编辑继续使用原生 XFL；不要用重新导入来“修复”人工编辑产生的清单差异。

## 3. 元件结构、零重复混合碎尸与 CF7 动作适配

### 3.1 导出链接（Linkage）
- 共享导出锚点：`Antigravity专用素材`（`linkageExportForAS="true"`、`linkageExportForRS="true"`、`linkageURL="flashswf/arts/new/Antigravity专用素材.swf"`）；两只敌人根元件显式设置 `linkageExportInFirstFrame="true"`，things-new 的导入锚点放在第 4 帧。
- 男僵尸根元件：`Antigravity/CF6普通男僵尸/敌人-CF6普通男僵尸`（linkage: `敌人-CF6普通男僵尸`）
- 女僵尸根元件：`Antigravity/CF6女僵尸/敌人-CF6女僵尸`（linkage: `敌人-CF6女僵尸`）

### 3.2 纯矢量分件与零重复碎尸引用
1. **共用模板辅助件（`Antigravity/共用/...`）**：
   - 从 `flashswf/arts/things1/LIBRARY/` 克隆 14 个纯矢量敌人模板组件（血槽、人物文字信息、思考标签、攻击判定盒、接地阴影、停止器等），全部重写为内部无冲突路径，零位图依赖。
2. **CF6 普通男僵尸（`Antigravity/CF6普通男僵尸/...`）**：
   - **活体分件（10 个）**：`393-脚靴` .. `402-垂指手`，由 R5 源稿 `inputs/live/{393..402}.svg` 转为 Flash 原生二次贝塞尔矢量形状，所有嵌套 `clip-path` 转为静态遮罩层（`layerType="mask"` / `parentLayerIndex`）。
   - **碎尸分件（67 个，`409..475`）**：R5 `death-parts/{409..475}.svg` 中引用原版 `392` 图集的裁切块通过 `death-mapping.json` 与 `shape-manifest.json` 精确反映射到单一活体元件（`401-头部`、`394-小腿` 或 `393-脚靴`）加图集偏移矩阵 `(1, 0, 0, 1, -tx_i, -ty_i)`，由静态遮罩层裁切活体元件实例，**不复制任何活体矢量形状，也不生成复合全图集**；血迹、断骨、裂口与脑浆保持原生矢量。
3. **CF6 女僵尸（`Antigravity/CF6女僵尸/...`）**：
   - **共享头部母版（1 个）**：`1627-头部母版`，直接取自 `source/core-art.json` 中 `1627` 的原始 `1618` 图集空间绘制数据，并保留 `femaleHeadSourceSilhouette` 外轮廓遮罩；活体和碎尸的局部裁切在消费者外层完成。
   - **活体分件（10 个）**：`1619-脚靴` .. `1628-垂指手`。其中 `1627-头部` 通过静态遮罩层引用 `1627-头部母版`。
   - **碎尸分件（58 个，`1635..1692`）**：其中半头碎块 `1635`、`1637`、`1639` 同样通过各自断面遮罩层 + `femaleHeadSourceSilhouette` 遮罩直接引用同一个 `1627-头部母版` 实例；其余 55 个碎尸件（裙摆残片、手脚残肢、血雾等）均为原生矢量。

### 3.3 CF7 敌人模板时间轴与行为协议
- **根元件第 1 帧脚本**：调用 `_root.初始化敌人模板()` 后执行 `if(this.配置音效){ this.配置音效("僵尸", this); }`（显式传入 `this` 作为第二参数，规避 `_root.敌人函数.配置音效` 中 `traget = this` 的历史拼写问题）。
- **状态帧段**：首帧初始化；`空手站立` 标签从第 2 帧开始，站立画面覆盖 1..9；其后为 `空手行走` (10..19)、`空手跑` (20..29)、`空手跳` (30..41)、`空手攻击` (42..51)、`拾取` (52..61)、`躲闪` (62..71)、`被击` (72..79)、`击倒` (80..88)、`倒地` (89..95)、`被投` (96..104)、`血腥死` (105..120)、`消失` (121..127)。跳和拾取为沿用模板的空帧占位，不提供对应动作。
- **攻击动作（`动作/攻击`，完整时间轴 87 帧，第 35 帧回调结束）**：第 1 帧定义 `攻击时移动(慢速度, 快速度)`，第 6..7 帧（0-based `5..6`）挂 `_parent.攻击时移动(5, 25)` 突进触发器，第 9、11 帧（0-based `8, 10`）挂近战判定盒 `攻击点`（共发射 2 次近战判定，`子弹威力=空手攻击力`、`击倒率=10`、`Z轴攻击范围=30`），第 35 帧调用 `_parent.动画完毕()`；正常状态切换后不会继续播放余下帧。
- **受击 / 倒地 / 血腥死**：
  - `动作/被击`：`a0`、`a1` 两分支分别在男僵尸第 15 / 37 帧、女僵尸第 19 / 41 帧调用 `_parent.动画完毕()`。
  - `动作/倒地`：第 9、13 帧（0-based `8, 12`）调用 `_parent.死亡检测()`，末帧调用 `_parent.动画完毕()`。
  - `动作/血腥死`：`a0`、`a1`、`a2` 三分支末帧（从 1 计数：男僵尸 `77 / 130 / 173`，女僵尸 `79 / 148 / 191`）均调用 `_parent.死亡检测()`；真实敌人函数在死亡条件成立时停止动画、结算并清理单位。

## 4. 常用命令与验证

```powershell
chcp.com 65001 > $null

# 1. 从认可源稿重新生成原生 XFL 并确保 things-new.fla 挂载（若检测到人工 CS6 修改则拒绝覆盖，需显式加 --force）
python -X utf8 tools/cf6-zombie-assets/build.py --import-approved

# 2. 只读校验现有原生 XFL 与已编译 SWF（无位图、无断链、导出符号完整）
python -X utf8 tools/cf6-zombie-assets/build.py

# 3. 校验单位注册、阶段 6 公式面板、linkage 映射与测试文件 BOM
python -X utf8 tools/cf6-zombie-assets/verify.py
python -X utf8 -B tools/cf6-zombie-assets/test_import_guard.py

# 4. XFL 结构审计与全仓 linkage 扫描
python scripts/tools/xfl/audit.py "flashswf/arts/new/Antigravity专用素材"
python tools/linkage_scanner/scan_linkage.py --xml-only

# 5. Flash CS6 真实发布验证（独立素材库 + things-new 共享库路由）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/arts/new/Antigravity专用素材/Antigravity专用素材.xfl" -PublishOnly -VerifySwf "flashswf/arts/new/Antigravity专用素材.swf"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/arts/things-new.fla" -PublishOnly -VerifySwf "flashswf/arts/things-new.swf"

# 6. 原生时间轴、攻击判定与血腥死三分支专项 TestLoader 验证（28 个时间轴组合）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-zombie-asset-tests.ps1
```

## 5. 验证覆盖与实机回归

`build.py` 和 `verify.py` 校验原生源身份、引用、矢量与注册数值；`test_import_guard.py` 在临时目录验证人工编辑、新增/删除文件、缺失/旧版清单和生成期间改动均在写入前被拒绝。

TestLoader 加载实际发布的素材 SWF，运行男女、左右朝向的攻击、两受击分支、倒地和三死亡分支，共 28 个时间轴组合。初始化、伤害出口、状态切换和死亡处理使用内存替身；站立有 Flash 像素检查，其余状态检查回调和元件边界。它证明素材时间轴能执行，不证明真实伤害、状态打断、掉落结算或清尸已完成实机验收。

真实游戏仍需回归：男女僵尸左右朝向的攻击命中与受击打断、击飞后倒地及起身、三种死亡分支的末姿与清尸，以及同屏多只时的表现。离线导帧可补查缺件和遮罩，但不执行 AS2。仅修改本工具的保护逻辑或文档、原生源与 SWF 字节不变时，无需重新发布素材库。
