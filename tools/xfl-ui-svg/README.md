# xfl-ui-svg

把 XFL（Flash CS6 解包格式）库元件某一帧的**可见装饰**保真导出为 SVG + 布局 JSON。
为 UI 迁移提供美术真源；纯 Python3 stdlib，只读，可复现。需 **Python ≥ 3.9**
（manifest/verify 使用 `Path.is_relative_to`）。

## 用法

```bash
python tools/xfl-ui-svg/xfl_to_svg.py \
  --library "flashswf/UI/对话框界面/LIBRARY" \
  --symbol "对话框界面" --frame 1 --stage 1024x576 \
  --out launcher/web/assets/dialogue-ui \
  --separate-buttons

python tools/xfl-ui-svg/xfl_to_svg.py --selftest   # 确定性自测
```

同一导出命令追加 `--verify` 时只读核验：生成器 SHA、全部真源 SHA、产物 SHA，
以及产物目录精确文件集合（缺/多文件均失败）。verify 还要求调用参数与
manifest 记录的配方一致（当前仅 `separateButtons`）——生成时用了
`--separate-buttons`，verify 也必须带同一开关；`--verify` 是哈希闭包核验，
不重跑生成器，不能发现非确定性回归。

参数：`--portrait-symbols a,b`（不展开、只记槽位/内部 mask 的巨型依赖）、
`--button-ids 层名:id,...`、`--separate-buttons`、
`--svg-name/--layout-name/--manifest-name`。

**注意**：`--portrait-symbols` 与 `--button-ids` 的默认值（`对话框肖像,外部立绘层`、
`关闭:close,移动:drag,按钮控制:next`）是对话框界面专用。迁移其它 UI 时必须按
对应真源显式给出这两个参数，否则巨型依赖不会被跳过、按钮 id 会退化为符号名 slug。

## 输出

- `source.svg` — 舞台 viewBox，源坐标/矩阵/图层名，装饰 +（默认配方下）按钮 up 态
- `buttons/<id>-<up|over|down>.svg` — 按钮分态，局部紧致 viewBox
- `layout.json` — 动态文本字段、按钮 stageRect/hitRect/热区、肖像槽、mask clip
- `manifest.json` — 源/工具/产物 SHA256、skipped、unsupported

## 按钮渲染合同（buttonRendering）

- `baked-up`（默认）：按钮 up 态美术烘焙在 source.svg 内，widget 仅在
  hover/press 时叠画 over/down 位图。**注意**：若某按钮 down/over 态几何与 up
  不同（本资产拖拽钮 down 态箭头旋转 90°），叠画会让底层 up 美术残影。
- `separate`（`--separate-buttons`）：source.svg 不含可见按钮美术，消费端必须
  常时按当前态绘制对应 `buttons/<id>-<state>.svg`（rest=up）。layout 顶层
  `buttonRendering` 记录取值；manifest `source.separateButtons` 为布尔。

## 按钮热区

`buttons[].stageRect` = up 态美术 bbox（向后兼容）；`buttons[].hitRect` =
帧 3（hit 帧）内容经实例矩阵的舞台外接框，帧 3 为空时回退 up bbox；
按 Flash hit 帧选取来源，消费端命中判定应优先用 hitRect。hitTest-only 按钮
（up 帧为空）两值同为帧 3 热区，不产 SVG。

bbox 为遮罩感知粗略包围盒：被遮罩层的 bbox 与其 mask 层（parentLayerIndex
指向）本帧几何外接框相交，mask 外美术不计入（递归生效于嵌套实例；不含描边
宽度、曲线按端点外接）。hitRect 保留作者 hit 帧的矩形范围，仍会包含轮廓内的
空白，不等同 Flash 的逐像素命中。关闭钮的 hit 帧来自回纹图层，红 X 的绘图路径
不单独作为命中范围来源；视觉矩阵保持不变。

## 肖像槽

`portraitSlots[]` 只记槽位矩阵，不展开人物依赖。对带内部 mask 层的 portrait
符号（当前为 `对话框肖像`）额外读取其当前帧 mask 几何（仅 DOMShape/Group，
不展开被遮罩内容），写入 `clips.internalPortraitClip`（已过实例矩阵的舞台
path），对应槽位 rec 的 `clip` 字段指向该键；该 XML 计入 manifest sources。
被父级 mask 层遮罩的槽位（当前为 `外部立绘层`）`clip` 仍指向 `clip:<被遮罩层名>`。

## 忠实度边界

- 不执行 AS / 不推进 MovieClip 时钟；graphic 用 `firstFrame`，MC 取 0 帧。
- shape tween 取该帧基准 DOMShape（MorphShape 段不插值）。
- mask 层→clipPath；fillStyle0 边自动反绕；`Edge@cubics` 冗余段忽略。
  fillStyle0==fillStyle1 同索引边为两侧同填充的内部边界，正/反两写抵消属正常语义。
- ColorTransform：纯 alphaMultiplier→组 `opacity`；带 offset/rgb 的折算进各
  fill/stop 与渐变 stop（逐通道精确、无渲染器依赖，但与"合成后整乘"在
  重叠半透明区有理论差异——本资产无此情形）。
- DropShadowFilter→feDropShadow（stdDeviation=blur/2 近似）；Bevel/ Glow 等
  记录 unsupported 不丢基础美术；blendMode 写 `mix-blend-mode` 并记录。
- 全透明(alpha=0)形状与空 up 态 hitTest-only 按钮不产图，记入 skipped；
  hitTestOnly 按钮的舞台热区仍在 layout.json 给出。
