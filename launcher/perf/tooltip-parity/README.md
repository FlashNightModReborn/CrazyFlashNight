# tooltip-parity — Web vs Native 真实绘制对比 harness

Edge headless（冻结 baseline 生产 CSS/JS）× 生产 `NativeTooltipWidget`（离屏 Form
fixture）逐 case 渲染 → 几何/文本/滚动/像素判定 + side-by-side/overlay/diff 图。

## 运行（仓库根目录；PowerShell 先 `chcp.com 65001 | Out-Null`）

```
node launcher/perf/tooltip-parity/selfcheck.js
node launcher/perf/tooltip-parity/run.js \
  --samples <samples.json> --scenarios <scenarios.json> --out <dir> \
  --baseline <parity-web/baseline> --baseline <baseline-extra> \
  [--preset loose|acceptance] [--cases a,b,c] [--mode legacy|doc] \
  [--skip-web] [--skip-native] [--skip-compare]
node launcher/perf/tooltip-parity/filter-scenarios.js --in <scenarios.json> \
  --out <f> [--phase p90-first|matrix] [--viewport WxH,...] [--ids a,b] \
  [--dpi 1] [--placement auto|<side>]
```

dotnet 自动回退 `%LOCALAPPDATA%\Microsoft\dotnet\dotnet.exe`。

## 判定口径

- **文本**：web 端逐字符 `Range.getClientRects()` 聚合实际视觉行（多 span 同行合并，
  隐藏/测量元素排除），与 native `VisualLine` 同口径比行数（drift=warn）；
  缺内容判定用 squash 全文拼接（与折行无关），已可靠采集的全文缺失或 native 全空 = 硬失败；
  任一侧采集不可信 → `textUnknown:*` warn，不放绿不造假。
- **几何**：tooltip/placement/面板矩形、scrollable/reachBottom、视口闭包
  （任一边越界含部分裁剪 = 硬失败）。
- **像素**：并集区 diffRatio/meanAbs 仅软告警（AA 差异单列观察）。

### 阈值预设（`--preset`，记入 compare.json/summary.json）

| 项 | loose（测绘，≠一致） | acceptance（验收） |
|---|---|---|
| posTolWarn / posTolHard | 8px / 96px | 2px / 8px |
| sizeTol | 24px 或 15% | 3px 或 1% |
| panelSizeTol | 32px 或 25% | 3px 或 1% |
| lineCountWarn | 3 | 1 |

## 已知边界

- `scenario.viewport.w/h` 为物理像素，`dpi` 为设备缩放倍率。Web 采集器按
  `w/dpi × h/dpi` 创建 CSS 视口并校验真实 `devicePixelRatio` 与 PNG 尺寸；
  场景尺寸须能被倍率整除。输出同时保留 `cssGeometry`、`viewportProbe` 和
  换算为物理像素的 `geometry`，避免把相同 CSS 大小误当相同物理窗口。
  Native 必须注入同一倍率后才构成对应 DPI 的双端证据；旧 50 组仍仅覆盖 DPI=1。
- native fixture 视口用「固定小宿主 Form + 非 dock 子控件显式 Size」，
  绕过顶层窗口 OS 工作区钳制；`anchor.ClientSize` 硬断言等于请求值。
- `web-shoot --no-png` 仅重采 JSON 元数据（视觉行/几何），复用既有 web.png。
- 输出大目录属临时证据，按 lane 约定留 `tmp/`，不入库。

边缘夹取后，两端实际位置/尺寸都在既定容差内但候选方向标签不同，记 `placementLabelDrift` 告警；现役 CSS 不消费该标签且不绘制方向箭头。真实坐标偏差、尺寸偏差、缺内容、越界和滚动差异仍各自独立判硬失败。

普通提示样本可提供 `plainHTML`（经生产 `convertAS2Html` 后直接送入
`PanelTooltip.showAtMouse`），Native 一侧用相同内容的 simple document；
不套物品 rich 骨架，几何和文本采集以 tooltip 本体为唯一面板。
视觉 fixture 的 `scrollLines` 直接设置滚动位置，只证明绘制与可达性；
实际悬停晋级和滚轮归属由 `TooltipInspectionFeedbackTests` 的生产
widget/adapter/controller/route 联合回归单独验证，仍不代替物理鼠标人验。

非 16:9 场景的逻辑锚点按 `FlashCoordinateMapper` 的等比留边映射到
Web CSS 视口；不得独立拉伸 X/Y，否则居中样本会掩盖边缘样本的假位移。

定位行为回归：`NativeTooltipPlacementContractTests` 调用 `placement-oracle.js`，
直接抽取并执行现役 Web 定位函数，覆盖连续轨迹和锁边，再与 C# 本地求解对照。
这是双实现的漂移检测，不是生成 C# 或共享运行时算法。普通图片 fixture 以无 DOM
元素的鼠标点输入匹配 Native 点锚；不得用 1px 元素冒充零面积鼠标点。

可选 `scenario.anchorRect:{x,y,width,height}` 使用 Flash 逻辑坐标，两端均按同一留边映射生成真实元素矩形；`anchor` 仍为独立鼠标坐标。该输入用于图标范围避让，不能用矩形中心替代鼠标评分点。
