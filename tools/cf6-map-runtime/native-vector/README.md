# CF6 原生矢量候选

此目录按“尽可能保留矢量 → 原生 XFL → 运行时贴背景图”的方向装配地图与动态部件。转换器只写 XFL 源；主控完成原生导入后，通过 `assemble-canonical.py` 安装规范名称的源工程，再由真实 CS6 编译对应 SWF。旧位图候选按原字节归档，候选 SWF 不复制为规范产物。逐项源身份与装配记录位于 `canonical/`，编译和实际消费者证据另行记录。

## 当前状态（2026-10-21 回执核对）

- 全部 20 张 canonical 背景与配套动态件已由真实 CS6 编译，Compiler 0/0，逐目标 receipt 在 `tmp/cf6-roguelike-20261021/validation/`：`canonical-native-batch-r1`（A09–A17 共 13 目标，含 A10/A13 电梯滚动与前景）、`canonical-pattern-batch-r1`（A18/A19/A20/A22）、`sky-canonical-r1`（A02/A06 天空）、更早 `canonical-vector-r1/r2/r3`（A01–A06/A08 底图、三种门、A03/A04/A05 前景、A02 城市、A21 演出）。回执均注明无候选 SWF 复制、无正式 runtime 发布、无全游戏验收。
- 机关 suite 现为 142 项（旧 79 + 天空/城市 26 + 空波次早清关保持身份与一次性交付 37），真实 TestLoader 579/579（`prototype-combined-r6`，Compiler 0/0、新鲜 trace）。下文中“预计专项105项”“主控须跑真实 TestLoader 105项”等表述为历史计划，已被该回执取代。
- 尚未完成的边界：全游戏 20 图尚未走通；天空/城市/云层噪声、A08 噪声浓度、吊灯高光、模糊区域裁切等局部近似仍以实机画面为准；A14 培养舱小人缩小时描边变暗的独立视觉差异仍在（诊断 01 编译失败原件保留、02 成功，canonical 未改）。不能宣称全部画面已经人眼验收。

下文各表的“进入 CS6 前的步骤”“当前缺口”列保留为历史施工记录；与当前状态的矛盾以本节为准。

## A01 支持边界

底图 `background-1581.svg` 有 9,897 个 path、5,549 个 ellipse、1 个 rect、6 个顶层组、18 个渐变定义、3 个 clipPath、2 个灰阶渐变 mask、4 个文本与 1 张内嵌程序土纹理；无 filter、pattern 或弧线命令。独立黄灯 1410 与光晕 1411 另按当前地图输入的原注册矩阵加入。

| SVG 内容 | XFL 候选实现 | 尚待验证 |
| --- | --- | --- |
| path/rect/ellipse/circle/polygon/polyline/line | 原生 DOMShape / Edge；复用仓库已使用的 legacy writer | CS6 编译与实际像素、填充绕向 |
| 线性/居中径向渐变 | 原生 LinearGradient / RadialGradient；显式展开 objectBoundingBox 坐标 | 实际渐变方向、椭圆径向形变 |
| 组、矩阵、透明度 | 独立原生元件与完整仿射实例矩阵；有透明度的组显式 blendMode=layer | 组重叠合成与实际性能 |
| 本地 use | 解析本文件 ID，复用原生子元件 | 不支持外部 URL |
| 几何 clipPath | 原生 mask/content 元件，setMask | AVM1 实际裁剪 |
| 灰阶 mask | 灰阶 stop 转 alpha；原生矢量遮罩，Flash 运行时 cacheAsBitmap + setMask | 保留矢量编辑源，运行时局部缓存；真实透明遮罩画质 |
| 原稿内嵌 PNG | 仅 base64 解码原字节，由 CS6 原生导入生成 bin | 不新增整层栅格化，缓存闭包由 native_xfl 检查 |
| DejaVu Sans Bold 文本 | 绑定归档字体 SHA，字形转原生路径，文本留在报告 | 字距/视觉对照；XFL 中为轮廓而非可编辑文字 |
| filter、外部 use、彩色 luminance mask、非中心径向渐变等 | 显式拒绝或需新增实现 | 不静默丢弃，也不自动整层转 PNG |

原稿的程序纹理不冒称矢量。Cubic→quadratic 沿既有工具的 0.06 源像素容差，原生坐标量化为 twip。静态生成和源闭包检查不等于实际 Flash 渲染通过。

## 构建

本轮隔离的 `tmp/cf6-py312/Scripts/python.exe` 提供 fontTools/Pillow，不修改全局解释器。`texture-manifest.json` 绑定原 SVG 与解码纹理。主控先通过受控原生导入事务执行 `import-texture.jsfl`，得到独立的 `CF6_A01_VectorCandidate01` 原生工程，然后执行：

```powershell
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/build-a01.py --assemble
```

不带 `--assemble` 只写此目录的矢量派生与报告。`--assemble` 先验证原生纹理闭包，再写此候选独占的元件和时间轴，最终核验所有 Include、symbol/media 引用、纹理源 SHA 与 bin 缓存。详细源身份和数量在 `generated/report.json`。

顶层可视层保持两帧；第一帧子元件初始化 mask/filter，第二帧停止。只有当前实例本身或其父级是当前 `gameworld.背景`、且当前局为 CF6/historical/active，才调用 `_root.贴背景图(true)`。即使 A01 宽度只有 800，也不绕过复杂矢量的运行时烘焙。脱离游戏的独立 SWF 预览不调用游戏背景函数。这里的 `true` 是现有背景函数的强制参数；共享背景函数与机关凭据由各自拥有者接线。

由主控完成独立目标 CS6 发布、新鲜 Compiler 0/0、原生元件/渐变/mask/字体对照和真实消费者确认后，才讨论正名替换。当前原位图 XFL/SWF、99 张门帧 PNG 与来源包全部保留为对照；后续门动画应复用矢量门叶与原帧矩阵，不继续扩大逐帧 PNG 链。

## 早期样板编译队列（2026-10-21 参数示例）

下表为早期候选队列的历史记录；各目标 canonical 编译已全部完成，见顶部当前状态。下表均为独立候选，不是正式 runtime 发布。XFL 根目录固定 `flashswf/backgrounds/cf6/`，SWF 同样位于该根；不能把 SWF 发布到候选工程目录内。每个名称都直接对应 `<名称>/<名称>.xfl` 与 `<名称>.swf`。源码/未编译/已运行按主控新鲜回执区分；文件存在不视为执行通过。

| 精确名称 | 进入 CS6 前的步骤 | 当前边界 |
| --- | --- | --- |
| `CF6_A01_VectorCandidate01` | 已装配；不再导入纹理 | r1 已有真实编译/独立 Player 画面对照；新归属+active guard 源需重编；r1 归档在 `archive/a01-r1/` |
| `CF6_A02_city-parallax_VectorCandidate01` | 已装配；零纹理 | 独立城市层；未合入底图 |
| `CF6_A03_foreground_VectorCandidate01` | 已装配；零纹理 | 吊灯原生描边渐变，见下文局部兼容项 |
| `CF6_DoorWood1714_VectorCandidate01` | 已装配；零纹理 | 原 9 帧，保留门叶矩阵与 clipDepth |
| `CF6_DoorExit1720_VectorCandidate01` | 已装配；零纹理 | 原前 50 帧中的环境白名单，排除角色与切图动作 |
| `CF6_DoorGrand1750_VectorCandidate01` | 已装配；零纹理 | 原 40 帧环境白名单 |
| `CF6_A02_BG_VectorCandidate01` | `layers/CF6_A02_BG_VectorCandidate01/import-textures.jsfl` → `build-layer.py --map A02 --assemble` | 1 张原稿纹理；城市另层 |
| `CF6_A03_BG_VectorCandidate01` | `layers/CF6_A03_BG_VectorCandidate01/import-textures.jsfl` → `build-layer.py --map A03 --assemble` | 2 张原稿纹理 |
| `CF6_A04_BG_VectorCandidate01` | `layers/CF6_A04_BG_VectorCandidate01/import-textures.jsfl` → `build-layer.py --map A04 --assemble` | 2 张原稿纹理 |
| `CF6_A05_BG_VectorCandidate01` | `layers/CF6_A05_BG_VectorCandidate01/import-textures.jsfl` → `build-layer.py --map A05 --assemble` | 30 张去重原稿内嵌纹理，含 16 张原有 JPEG |
| `CF6_A06_BG_VectorCandidate01` | `layers/CF6_A06_BG_VectorCandidate01/import-textures.jsfl` → `build-layer.py --map A06 --assemble` | 复用同组 30 张内嵌纹理；独立天空另接 |

前六个目标由主控串行编译；不在主控打开/编译时重新生成这些源。后五图的精确调用以 A02 为例，其余仅替换表中的明确 A 编号：

```powershell
& .\tmp\cf6-roguelike-20261021\orchestration\import-native.ps1 -Recipe CF6_A02_BG_VectorCandidate01 -RecipeRelativePath tools/cf6-map-runtime/native-vector/layers/CF6_A02_BG_VectorCandidate01/import-textures.jsfl
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/build-layer.py --map A02 --assemble
& .\scripts\compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_A02_BG_VectorCandidate01/CF6_A02_BG_VectorCandidate01.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_A02_BG_VectorCandidate01.swf'
```

模板中仍保留拒绝覆盖已有 XFL、精确源字节/PNG或JPEG/bin/Include 闭包和裸 SWF 发布名校验。原生导入 recipe 只导入已存在源文件的纹理字节，不渲染 SVG；主控确认导入结束后才能合并矢量与发布。每图的 `layers/<名称>/texture-manifest.json`、`report.json` 和源脚本快照是详细输入与兼容记录。

### 已实现的限定扩展与局部差异

- sRGB `feColorMatrix` 与线性 `feComponentTransfer` 转为原生 ColorMatrixFilter；偏移从 SVG 0–1 换为 Flash 0–255。非线性、分支滤镜与没有确认色域的颜色处理拒绝，不猜测替换。
- `feGaussianBlur` 使用原生三遍 BlurFilter，blurX/Y=`2×stdDeviation`。这是局部近似，不是像素等价；源滤镜区域裁切尚未复现，报告逐条保留 sourceRegion，须比较阴影/远景边缘是否溢出。
- 吊灯原稿存在零宽或零高的 objectBoundingBox 渐变描边。仅该退化维度扩至原描边宽度，保留原生描边；每条记录在 `gradientFallbacks`，需观察垂直吊杆高光。
- 单纹理、userSpaceOnUse 的 SVG pattern 转原生重复 BitmapFill，矩阵线性项按 XFL 的 twip/pixel 单位转换。多内容 pattern、错误比例的贴图 pattern 显式拒绝。
- SVG 内嵌 PNG/JPEG 仅解码原字节；JPEG 不重压缩，导入后仍要求原生 lossless 发布。普通 image 保留 none/meet/slice 及锚点，不能把不等比例图片强制拉伸。
- 原图 white+alpha 遮罩先检查每个可见像素确为白色，再直接保留 alpha；颜色输入经过明确输出白色的原始 ColorMatrix 生成 matte 时，保留该矩阵与 alpha，不把整张花瓶或墙面烘成新图。
- `feTurbulence` / `feDisplacementMap` 等仍需独立的局部程序纹理方案；未因该局部能力缺口把整景扁平化。

### A08 局部噪声候选与 A05/A06 viewport 诊断

A08 使用独立 `build-a08.py` 适配器，冻结的批量转换器不变。它仅接受原稿八处通风口磨损的 `feTurbulence → feColorMatrix → SourceGraphic in` 图；矢量轮廓保留，约 137×14 的局部噪声在运行时用 `BitmapData.perlinNoise` 建立，卸载时释放。Flash 与 SVG 噪声不是像素等价，须检查纹理浓度。未生成新 PNG。精确顺序为 `layers/CF6_A08_BG_VectorCandidate01/import-textures.jsfl` 原生导入 → `build-a08.py --assemble` → 独立 CS6 编译 `CF6_A08_BG_VectorCandidate01`；不能用普通 `build-layer.py --map A08` 代替。该链已执行完成，canonical `CF6_A08_BG.swf` 真实编译 0/0（`validation/canonical-vector-r2`）；噪声浓度的实机画面检查边界不变。

`diagnostic-a05-parts02.py` 复用 A05 已导入的纹理缓存，建立 `CF6_A05_PartsDiagnostic02` 四栏对照。独立 `viewport_adapter.py` 修复原转换器将嵌套 SVG 当普通组而遗漏视口缩放的问题，并保留已实现的 multiply。输入普查仅 A05/A06 使用该结构（14/42 处，均 `preserveAspectRatio=none`、`overflow=visible`）；适配器拒绝其他视口策略。修正尚未并入冻结的批量核心，真实诊断结果与主图重建仍由主控分别记录。

### A05/A06 修复交付（2026-10-21）

主控已完成诊断02的真实 CS6 Compiler 0/0 与 FP11 四栏对照：雕像灰石材质和壁画花束、花瓶、框饰恢复，与相邻源 PNG 同构。此结论限定于独立部件小样；不升级为整图、消费者或标准入口验收。光晕没有确认成转换缺陷，不纳入本次修复结论。

`build-viewport-layer.py --map A05|A06 --assemble` 将适配器仅注入当前 Python 进程，K3 的 r1b 六项依赖保持原 SHA。每次构建先逐 SHA 核验冻结输入，再将旧候选 XFL、派生物和已有 SWF 压缩归档并逐文件核验，最后复用原生纹理缓存装配。旧版位于 `archive/viewport-pre-adapter/`。报告保存适配器/入口源码快照、SHA、14/42 处视口矩阵和归档收据。不要用不含适配器的普通 `build-layer.py` 重建这两个底图。

两候选均已重装；canonical 装配与真实编译已完成（`validation/canonical-vector-r3`，Compiler 0/0）。每次 `compile_test.ps1` 均须取得本轮新鲜 Compiler 0/0 和相符 SWF 身份后才继续；canonical 装配只复制原生源闭包并归档旧版，不复制候选 SWF，也不是正式 runtime 发布。以下命令保留为当时执行记录：

```powershell
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/assemble-canonical.py --map A05 --apply
& .\scripts\compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_A05_BG/CF6_A05_BG.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_A05_BG.swf'
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/assemble-canonical.py --map A06 --apply
& .\scripts\compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_A06_BG/CF6_A06_BG.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_A06_BG.swf'
```

机器交接为 `diagnostics/viewport-handoff-r1.json`。既有 `diagnostics/nested-svg-impact-r1.json` 绑定20图/30层源 SHA，K3 全部17项没有嵌套 SVG；其结论只证明本视口分支无影响，不能泛化为其他转换器修改免验。

### A02/A06 天空和 A02 城市：专项接线交付

主控随后授权了以下有界接线。已新增独立 sky wrapper、`sky-parallax.fragment.json`，并修改自身 Cf6MapMechanism/Test 及模板；冻结的 runtime/build.py、map-input 和 K3 converter 未改。该专项已由主控完成：天空 canonical 真实编译（`validation/sky-canonical-r1`，A02/A06，Compiler 0/0），机关 suite 扩至 142 项并真实运行 579/579（`prototype-combined-r6`）。下文保留施工当时的合同与历史计划，编译/测试状态以本段与顶部当前状态为准。

| 对象 | 独立资源/坐标合同 | 当前缺口 |
| --- | --- | --- |
| A02 天空 | 源 `A02-R3/cf6-stage2-redraw-r3/parts/bitmap-1595.svg`，固定根坐标 `(0,0)`，源尺寸600×187；独立 `CF6_A02_sky.swf` 已真实编译（sky-canonical-r1） | 原生候选已装配，130形状/29符号/零纹理；云层以局部运行时 Perlin→Displacement→Blur，薄雾以 Perlin→ColorMatrix 呈现，其余保留矢量；噪声/位移/模糊属于声明近似，实机画面对照仍待验收 |
| A06 天空 | 源 `A06-R2/cf6-stage6-redraw-r2/parts/bitmap-1753.svg`，固定根坐标 `(0,-20)`，800×187；独立 `CF6_A06_sky.swf` 已真实编译（sky-canonical-r1） | 1形状/4符号/1张原内嵌PNG，未新增整图光栅化。1753 是天空，1740 是雕像 |
| A02 城市 | 已有 `CF6_A02_city-parallax.swf` 原生资源。原 shape 的 viewBox 顶端109已在独立 SWF 中归零；初始可见放置 `(-0.75,108)`，原 enterFrame 接管后为 `(gameworld._x/2, gameworld._y+109)` | `map-input` 将其标为 `role=background`，runtime `build.py` 会在动态层遍历中跳过；新底图没有重复压入城市，独立 fragment 负责注册该消费者，章节组装由主控负责 |

已新增角色为 `screen-fixed` 与 `city-parallax`，明确根坐标，不经过走区 `coordinates(m)` 再变换。把两个天空与城市写入唯一 runtime 配置入口，再生成 index/environment/chapter，保持天空先于城市、两者均位于世界后面。不能把它们放进当前默认的 `world.效果` 前景容器。

实现复用 `_root.天空盒` 的既有后景深度，并验证其实际深度小于当前 world，但仅新增本局独占子容器，不改其共享相机属性、不加入 `bgParallaxList`。现有后景会把天空盒 `_y` 绑定世界Y、缩放随镜头，且 `SpeedRate=0` 仍发生除零；当前实现通过专属子容器反向缩放/平移，将目标根坐标/尺寸转换回天空盒局部空间，抵消父级平移和缩放。必须验证相机更新顺序，避免补偿晚一帧。源天空宽度与当前可见画布不一致时的露边仍需明确覆盖策略；本方案不擅自拉伸或新增天空画面。

`Cf6MapMechanism.loadLayers` 已按新角色选择后景容器并验证有限坐标/范围、重复角色和A02/A06必需层；沿用现有异步 pending、错误、超时门，缺资源不能静默放行。`render` 分别计算固定天空和横向半速城市的位置。`teardown` 额外清理世界卸载后仍存在的根后景子容器及监听器，使用本局普通对象身份/唯一容器名验证所有权，避免旧 MovieClip 路径别名删除新局资源。旧环境仍保留 `DisableSky=true` 隐藏默认天空，本局天空独立显示。

以上已修改原79项测试对应的机关源码，`.as` 保留 UTF-8 BOM 并与模板一致；新增26项覆盖真实 MovieClip 坐标变换、层级、重复加载、屏幕固定、城市稳态、暂停与转场、同路径换世界、迟到加载、失败/超时、归属清理及退化zoom。资源回调使用显式 stub，不能当作真实SWF加载证明；105 项计划已由主控真实运行并再度扩充（现 142 项，579/579，见顶部当前状态）。消费者实机还需验证 A02→A06→其他图无残留、层序无重复城市、天空无黑块或露边；canonical 资源编译完成不称为天空/视差实机画面已验收。


天空交付的精确主控顺序如下（已执行，回执 `validation/sky-canonical-r1`）。A02已装配、零纹理；A06只等待原生纹理导入，随后复用同一 wrapper。可直接编 canonical，不需要先发布候选 SWF。

```powershell
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/assemble-sky-canonical.py --map A02 --apply
& .\scripts\compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_A02_sky/CF6_A02_sky.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_A02_sky.swf'
& .\tmp\cf6-roguelike-20261021\orchestration\import-native.ps1 -Recipe CF6_A06_sky_VectorCandidate01 -RecipeRelativePath tools/cf6-map-runtime/native-vector/layers/CF6_A06_sky_VectorCandidate01/import-textures.jsfl
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/build-sky.py --map A06 --assemble
tmp/cf6-py312/Scripts/python.exe -X utf8 -B tools/cf6-map-runtime/native-vector/assemble-sky-canonical.py --map A06 --apply
& .\scripts\compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_A06_sky/CF6_A06_sky.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_A06_sky.swf'
```

`diagnostics/sky-parallax-handoff-r1.json` 绑定本轮源/适配器/fragment/AS2 SHA、逐条命令和剩余验收边界；`sky-parallax-source-before.json` 保留修改前79项基线源码身份。源后景尺寸保留600/800×187，当前画布更宽时的覆盖与镜头同帧补偿仍需实际游戏核验。

## 仅更新关卡几何/注册元数据

在矢量源准备期间可独立补齐 20 图的 index/environment，不写旧 PNG 导入配方：

```powershell
python -X utf8 -B tools/cf6-map-runtime/build.py --input tools/cf6-map-source/generated/map-input.json --overrides tools/cf6-map-runtime/route-geometry-overrides.json --metadata-only
python -X utf8 -B tools/cf6-map-runtime/build.py --input tools/cf6-map-source/generated/map-input.json --overrides tools/cf6-map-runtime/route-geometry-overrides.json --metadata-only --check
```
