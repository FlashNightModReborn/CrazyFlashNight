# AK47 火麒麟美术装配

`submission (2).zip` 的 SVG 原稿归档于 [Codex 源稿目录](../../flashswf/arts/new/Codex素材源稿/AK47火麒麟/weapon.svg)。唯一运行时编辑源为 [Codex 专用素材 XFL](../../flashswf/arts/new/Codex专用素材/Codex专用素材.xfl) 内的 `Codex/AK47火麒麟/`，原稿中的检查工具和构建脚本不属于交付包，不执行包内说明中的命令。

`assembly.json` 维护握持点、枪口、沿用旧枪体量的倍率、24 像素兽首特写与完整掉落图比例。只切换原物品的 icon/dressup 映射，物品名、数值、音效和存档身份保持原值。

源稿目录的 `.gitattributes` 对 `weapon.svg` 禁用文本换行转换，保留投稿原始字节；`assembly.json` 的 SHA-256 因而不受 Windows `core.autocrlf` 设置影响。

## 原生矢量与眼焰

`build.py` 复用现有原生矢量写入器，对本稿补齐 use、原生木纹遮罩、渐变坐标与偏心径向眼光。枪身、弹匣、枪托、兽首、刺刀保留独立 Graphic；外层武器提供 MovieClip `动画` 和 `枪口位置`。`动画.眼焰` 为 30 fps、8 帧的 MovieClip，一轮为 8/30 秒。五层透明度均匀采样原稿完整的 1.2 秒 SMIL 周期，四个主要相位保留，实际时间缩短至原来的 2/9；不增加帧停留时间或逐帧计时脚本。父级 stop 不冻结这个子 MovieClip。

图标第 1 帧为 24×24 遮罩内的兽首特写和底影；第 2 帧为无遮罩整枪，比例取纸娃娃倍率乘原 holder 倍率。两帧都使用相同的八帧眼焰相位，外层两帧仍是可显式选择的展示语义，不作为轮播动画。图标首帧将带遮罩的 `图标眼焰` MovieClip 直接挂在根部，旋转矩阵写入其内部；静态枪身另用相同的内置遮罩。此结构符合现有 Web 分层导出器的直接子层、正向无旋转挂载和不交错的绘制顺序要求。

```powershell
chcp.com 65001
python -B -X utf8 tools/ak47-fire-kylin-assets/build.py
python -B -X utf8 tools/ak47-fire-kylin-assets/build.py --check
```

`--check` 对照重建结果，检查形状、分组、填充、描边、引用和全部眼焰帧；允许 CS6 合并同样式 Edge、循环改变轮廓起点、移除无填充绕数的往返直线默认填色，以及原生定点矩阵、8 位渐变和百分比透明度量化。未改变语义时保留原生保存后的 XML，不反复覆盖它。元件 itemID 的后半段限定为较小的正整数，避免 CS6 对过大的哈希编号截断。

## 发布与预览

`publish.ps1` 沿已有武器动画发布器模式持有仓库编译互斥锁。`prepare_native.py` 先复制本件素材和必要依赖到临时小工程，挂接 `native_check.jsfl` 核对并原生保存，再只回装本件命名空间的元件；文件精确集合与生成器对照。两阶段均调用唯一 `compile_test.ps1` 入口：小工程完成原生保存验证，随后发布现役 Codex 素材库。原始编译脚本和本轮证据存入 `tmp/ak47-fire-kylin/`，finally 只在脚本仍与本轮一致时恢复；超时保留编译未知状态，先核对迟到产物，不能盲重试。

原生保存只作用于临时小工程，现役库的其他元件不经过这一保存过程。

`make_preview.py` 生成 `tmp/ak47-fire-kylin/NativePreview/` 下的独立只读 Flash 场景，加载实际发布的 SWF，检查链接、两帧图标、枪口、8 帧循环和实际像素变化。加载后先预热一轮，再从同一种帧回调建立基线，检查武器和图标的连续两轮闭合；不把 onLoadInit 到第一个帧回调之间的启动差异算作循环长度。此场景不读写玩家槽位，不代表正式入口完整战斗验收。

派生物继续使用项目的 `bake-icons-offline.py` 与 `bake-dressup-offline.py`，只导出 `Codex-AK47火麒麟` / `枪-长枪-Codex-AK47火麒麟`。图标先正常导出静态两帧，再传 `--export-animated-frames --animation-fps 30 --nested-frame1-viewport`，核对眼焰子动画和独立的 f2 都保留。这个显式取景选项只作用于首帧 stop、保留语义 f2、直接单动层的图标：从首帧可见区域固定裁切范围，通过父图与去除动层的差异恢复子层原点，再共同缩放底图和八帧眼焰，避免第二帧整枪的外框使动图缩小；其他图标仍沿用原来的画布规则。纸娃娃导出显式传 `--fps 30`，使 Web 与原生时间轴同速。
