# CF6 教学关 K3 施工线 — r10 结果回执

日期：2026-10-21。本轮回合成果：**用现役矢量素材近似重组的教学室背景 XFL 源已装配完成并通过全部静态自检**。候选源状态（candidate source prepared），未编译、未实机、无美术验收。

## 1. 原作教学关事实表（只读提取，不启动运行器）

来源：原作 SWF SHA256 `b52af10e…589b01`（identity 见 `tools/cf6-soldier-assets/evidence/20261016-threat/original/source-identity.json`）；反编译源 `tmp/cf6-soldier-20261016/knife-audit/deobfuscated-export/scripts/`；几何固化于 `tools/cf6-tutorial/original-tutorial-geometry.json`。

| 事实 | 值 |
| --- | --- |
| 入口 | `DefineButton2_1190` on(release) → 根标签 `教学关` = 主时间轴第 58 帧 |
| world sprite | `DefineSprite_1499` gameworld；背景 = `DefineSprite_1419` |
| walkBounds | Xmin/Ymin/Xmax/Ymax = [50, 150, 1000, 500]（根帧 58 gameworld load 脚本原值） |
| 出生点 | man1 时间轴放置点 (347.5, 270.5) |
| 行走带 | 后缘 y≈204（含 x182..507 家具凹口）、前缘 y≈449.95、右墙斜边 (716.5,204)→(1020.8,448.95) |
| 碰撞 | shape 1431 两个 solidPolygons：实心外墙 + 行走带孔洞（偶奇填充） |
| 出口 | 门1430 世界右侧 (853.6, 225.9) → 切镜 → 根标签 s1 → a1（原作第一关） |
| 灯组 | 灯管+光晕两组，世界 x≈43..181 与 x≈430..630 |
| 教学对话首句 | "操作方法：WSAD控制移动，J为射击，K为换弹夹。空格为跳过对话。" |
| **原教学美术** | **不在 21 图源包内（artAvailable=false），不可复用；本作为近似重组，不声称等价** |

## 2. 组件映射（源元件 → Tutorial 冻结件 → 摆放）

统一映射：现役宿舍行走区（scene_environment.xml 房间 X150..880/Y310..488，730×178）→ 原作行走带（1010.85×245.95），统一比例 s=1.383、tx=-207.45、ty=-224.73（横 1.3847/纵 1.3817 近似等比），家具相对布局保持宿舍原样。

| 角色 | 源（只读引用） | 冻结件 `Tutorial/…` | 世界摆放（px） | 世界尺寸 | 证据 |
| --- | --- | --- | --- | --- | --- |
| 房间壳 | 基地场景合集 `sprite/Symbol 2577`（20 件子闭包） | `房间壳-*` ×20 | x-205..1411 / y-457..621 | 1616×1078 | 宿舍房间.xml 背景层原样摆放（含滤镜） |
| 高架床 | 房间摆件/生活设施（含初始床+初始梯子） | `高架床-*` ×3 | x372..827 / y-70..194 | 455×264 | 宿舍"睡觉-普通床"按钮内生活设施 (-79.9,-207.7)；只取视觉，不带睡觉业务 |
| 工作台 | 基地场景合集 `button/Symbol 2588`（宿舍"仓库"库存工作台视觉） | `工作台-*` ×7 | x231..359 / y109..205 | 128×96 | 宿舍房间.xml 仓库按钮原样摆放；按钮转 Graphic、去脚本 |
| 门灯×2 | 素材库-地图元件 `门灯光+排气扇` | `门灯-门灯光+排气扇` | (43,25) 与 (430,25) | 140×58.5 每个 | 原作两组灯管位 x≈43..181 / 430..630 |
| 出口门 | `门2` | `门-门2` | x800..1005 / y182..450（右下对齐行走带前缘右端） | 205×268 | 原作门在右侧 (853.6,225.9) 斜置；本作直立近似，门口与 env Door 区重叠已断言 |

体量参照：CF7 持枪站姿约 138.38px；worldScale=1。层序（后→前）：门灯×2、门、工作台、高架床、房间壳。

## 3. 脚本白名单与闭包处置

- 闭包 34 符号（`LIBRARY/Tutorial/`），**纯矢量 11799 边段、0 位图字节、无 bin/ 依赖、无 linkage 导出**。
- 复制件脚本剥离 0（源本无脚本）、按钮转 Graphic 1 件（工作台）、移除空层 3、重命名可追溯（`Tutorial/<组>-<原叶名>`）。
- 全 XFL 唯一允许脚本 = 根时间轴第 2 帧 `stop()` + ownership/active guard（与已运行的 CF6_A01_BG 逐字一致，guard SHA256 `c807faba…170a8`），仅当本背景是活跃 cf6-sting 世界的背景且 `bookRun.outcome=="active"` 时调 `_root.贴背景图(true)`；独立预览播放不烘焙任何世界。
- PublishSettings 裸发布名 `CF6_Tutorial_BG.swf`；.xfl 仅 `PROXY-CS5`。
- `scripts/tools/xfl/audit.py flashswf/backgrounds/cf6/CF6_Tutorial_BG` → **CLEAN（exit 0）**。

## 4. 环境与地图片段

- `environment.fragment.xml`：walkBounds [50,150,1000,500]；碰撞 = 原作偶奇填充按 walkBounds 裁剪分解的 **14 个无孔凸多边形**（filled_trapezoids 管线，不在 paths 上另加矩形）；playerSpawn (347.5,270.5)（safe_spawn 校验未调整）；出口 Door 右 [940,425]-[990,445]（prototypeDerived CF7 手动出口，**不宣称原作自动转场**）；LeftSpawnLine [59,210,61,440]、RightSpawnLine [979,430,981,440]。
- `tutorial-map.fragment.json`：初始装备、**空波次**（Duration 0 / FinishRequirement 0 / Enemy=[]）、mechanism {kind:exit,layers:[]}、补给两份（战场长枪弹药包 431,360；战场复合急救包 626,409，均在可行走区断言）、3 句 Andy 对白（移动/切枪/补给说明）、Start/Clear 事件写明"战斗教学由 A01 承担"、BGM Moan。无强制按键任务系统、无额外敌人。

## 5. 自检结果（本轮工作树实测）

```
assemble.py            → {"built":"ok",  outputs:40, librarySymbols:34, freeGridCells:7767, reachableCells:7767, collisions:14, exit:[940,425,990,445]}
assemble.py --check    → {"check":"ok",  …同上}（源SHA/布局连通/闭包白名单/40产物字节级一致）
build-tutorial.py --check → {"check":"ok", …同上}
xfl audit              → CLEAN exit 0
```

freeGridCells == reachableCells（7767/7767）即行走带全连通、门可达、出生点在自由区。旧 r9 占位（build-tutorial.py + 两产物）归档于 `archive/r9-placeholder/` 并记 hash，由 --check 校验未被改动。本轮未写 `tools/cf6-map-runtime/generated/tutorial-map.json` / `tutorial.manifest.json`，未生成任何 SWF，未触碰库源/AS2/章节/共享环境 XML。

## 6. 主控集成项（精确接续）

1. **CS6 编译**（要求本轮新鲜 Compiler 0/0，marker 不算证据）：
   `scripts/compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_Tutorial_BG/CF6_Tutorial_BG.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_Tutorial_BG.swf'`
2. `BookDefinition.validCf6`（BookDefinition.as 约 113 行）对 TUTORIAL 硬编码 `gk1_1_BG.swf`，需裁决改为 `cf6/CF6_Tutorial_BG.swf`（AS2 改动不在本线范围）。
3. 合并 `environment.fragment.xml` → `data/environment/stage_environment.xml`；`tutorial-map.fragment.json` → cf6-sting 章节第 0 项（替换现役带兵种2/兵种6 的旧 TUTORIAL 项）；runtime-index.json 加 TUTORIAL 项。
4. 实机对照：角色体量/行走带/门口与画面一致、空波次清关开放出口（根代理已修复并真实通过空波次早清关竞争）、撤退回包。

## 7. 近似声明与验收边界

近似项（不声称与原画面等价）：原教学美术缺失，房间壳/高架床/工作台取自现役宿舍、门灯取素材库、门取门2；原作墙照片（1443×2）与排气扇动画（1448×2）未复刻；原作三补给箱改标准地面拾取物两份；原作屏外弃枪/敌人生成器不进入本作；门直立近似原作斜置门。**已知待试玩项：出口区 [940,425,990,445] 仅底部 20px 高走廊（受右墙斜边限制），主控可按实机试玩加宽。**

acceptanceBoundary：`data/source prepared only; deterministic assembly; no CS6 compile, no in-game or art acceptance claimed; approximate recombination, not original artwork`。

本线职责到此完成，退出。
