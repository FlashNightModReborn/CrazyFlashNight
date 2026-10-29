# tools/cf6-tutorial — CF6 教学关（K3 maps）装配线

## 当前入口：R7 较重边线（2026-10-27）

用户已选择 R7 较重边线。`layout.json` 的 `artRevision=r7-bold` 让同一 `assemble.py` 入口转交 `r7.py`；下文 R10/R12 内容是此前的装配历史。当前可编辑画稿与原始交付 ZIP 保存在 `flashswf/arts/new/Codex素材源稿/CF6地图/教程-R7/`。ZIP 为不可改写的来源快照，所选完整 SVG 是本轮画面输入。

R7 保留矢量形状、渐变、组与遮罩。原稿三处 image 去重为两张原始纹理；墙面和地板图像大于各自重复单元，因此用原生图像实例、每格遮罩及整面遮罩复现裁切，不能改成拉伸贴图或整景截图。根视口显式裁到 1000×450；128/75 的游戏倍率仍只由 `Cf6MapPresentation` 施加一次。

`r7/native-media/` 是真实 CS6 导入后冻结的纹理字节与原生缓存闭包。常规生成只消费该闭包，不需要再次导入；改变纹理时须通过受控 CS6 导入取得新缓存，不能自行制造 `.dat`。`r7/conversion.json` 和 `provenance.json` 绑定输入、输出、体积及原生源，`assemble.py --check` 验证确定性、媒体引用和出生到门前的通路。旧 R12 库符号保留在工程中但不再被 DOMDocument Include 引用，不进入当前 SWF。

`layout.json/r7Geometry` 按新画稿声明墙面、家具脚底与门前触发区；章节生成器再统一换算背景、碰撞、出口和引导点。更新顺序为 `assemble.py` → `cf6-prototype/build-chapter.py` → `cf6-type61/build-route.py` → `build-book-definition.py`，各工具随后执行 `--check`。真正发布目标仍是 `CF6_Tutorial_BG/CF6_Tutorial_BG.xfl` 和旁边的 `CF6_Tutorial_BG.swf`。

本次问题、实机范围和失败原件见[教程修复与 R7 接入记录](../../docs/闪客快打6肉鸽-61路线教程修复与R7地图接入-2026-10-27.md)。

r10 起接管原 `tools/cf6-map-runtime/build-tutorial.py` 的职责：用**现役矢量素材**（宿舍房间壳、高架床、基地工作台、门灯、门）近似重组闪 6 教学关环境，装配出独立背景 XFL 源 `flashswf/backgrounds/cf6/CF6_Tutorial_BG/`，并产出环境/地图片段与溯源清单，供主控审查后集成与 CS6 编译。

r9 的占位方案（借 `gk1_1_BG.swf` + 两只 2 级僵尸）已废止，旧生成器与产物原样归档在 `archive/r9-placeholder/`（含 `hashes.json` 校验值），仅作历史证据，不再参与构建。

## 命令

```bash
# 装配（重写本工具全部产物；不触碰任何库源/章节/generated 产物）
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-tutorial/assemble.py

# 确定性自检：源 SHA、布局连通、闭包白名单、全部产物字节级一致
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-tutorial/assemble.py --check

# 根代理入口（薄封装，等价于调用 assemble.py）
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/build-tutorial.py --check
```

成功输出一行 JSON，含 `outputs`、`librarySymbols`、`freeGridCells`/`reachableCells`（布局连通）、`collisions`、`exit`。

## 输入（canonical）

| 文件 | 作用 |
| --- | --- |
| `layout.json` | 教学室 canonical 布局：世界尺寸/walkBounds、宿舍→世界映射比例、出生点、出口与门锚点、各摆件角色与源引用（xfl + item）、对白/补给/波次参数 |
| `original-tutorial-geometry.json` | 原作教学关只读提取几何（主时间轴第 58 帧 gameworld：碰撞多边形、出生点、门位置、灯组），由 r10 探针从反编译源固化，SHA 记入 provenance |

源素材只读引用：`flashswf/levels/基地场景合集/LIBRARY/地图/宿舍房间.xml`、`房间摆件/摆件初始床.xml`、`摆件初始梯子.xml`、`flashswf/arts/new/素材库-地图元件/LIBRARY/门灯光+排气扇.xml`、`门2.xml`。

位图媒体（r12 起）：闭包内 7 处 `BitmapFill/bitmapPath` 引用 5 张纹理（`image/bitmap2252/2255/2259.jpg`、`image/bitmap2261/2321.png`）。原库对应 `DOMBitmapItem` 登记的 href 文件本就不存在（旧 XFL 现实格式），现役源是原库 `bin/M 2..6 1736924415.dat` 原生缓存（合计 28,869 字节）。装配逐字复制缓存与原 `DOMBitmapItem` 元数据（去掉失效 `sourceExternalFilepath`），不生成/解码/重编码图像字节；钉值（SHA-256/字节数）在 `assemble.py` 的 `MEDIA_CACHE_PIN`，路线经 root 探针 `tmp/cf6-roguelike-20261021/validation/tutorial-cache-probe-r1/` 真实 CS6 Compiler 0/0 验证。

## 产物

| 产物 | 说明 |
| --- | --- |
| `flashswf/backgrounds/cf6/CF6_Tutorial_BG/` | 原生 XFL 背景源（27 个符号、5 张位图纹理由原库原生 bin 缓存逐字闭合 [native-cache-only，28,869 字节]、复制的视觉元件零业务脚本、无 linkage；两帧合同照 CF6_A01_BG：第 2 帧唯一脚本为 ownership+active 守卫的 `_root.贴背景图(true)`）。**本线不编译、不生成 SWF** |
| `environment.fragment.xml` | 独立环境片段：walkBounds / 14 个凸碰撞多边形 / 出口 Door 区 / playerSpawn / 左右 SpawnLine |
| `tutorial-map.fragment.json` | 教学地图片段：空波次清关开出口、初始装备、两个补给、3 句 Andy 对白、"战斗教学由 A01 承担" |
| `provenance.json` | 溯源清单（schema `cf6-tutorial-assembly.v2`）：源 SHA、符号映射、脚本白名单处置、近似声明、待主控集成项、验收边界 |

## 验证边界

- `assemble.py --check` 只证明：源未改（SHA 比对）、闭包内无业务脚本/无 linkage、位图引用与媒体声明一一闭合并与原生缓存钉板一致（缺缓存/字节被改/未声明引用均拒绝，负例见 `result-r12.md`）、点网格连通及入口/出口几何成立（不代替真实角色通行）、产物与生成器输出字节一致。
- **不证明**：CS6 编译通过、游戏内实机表现、美术验收。这些是主控集成项，见 `result-r12.md` 与 `provenance.json` 的 `pendingIntegration` / `acceptanceBoundary`。
- r10 原件（零位图结论已被 root 拒绝）逐 SHA 归档在 `archive/r10-before-texture-fix/`，`--check` 同时校验该归档完好。

## 主控集成状态

教学室已独立编译，修订掉首版床上缘裁切、独立储物箱误作工作台及门的摆放问题；床、门与灯具使用 `layout.json` 的世界锚点/比例，门支持侧墙仿射矩阵，房间壳保留原有桌面。前两版 SWF、原生源和实际播放器截图均保留于本轮 validation 目录。

当前修订已合入历史章节和环境独占块，并在隔离候选内实际显示。当前仅可确认资源编译与进场，首段通行/射击、完整20图和美术体验仍由实际试玩验证。r12 原交接中的 `candidate_built，未编译` 是状态用词错误：该交接当时只到源准备；后续 `compiled` 以主控独立编译回执为准。
