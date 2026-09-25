# 环境与世界表现数据

本目录按场景与关卡作者的工作范围集中环境数据：`scene_environment.xml` 和 `stage_environment.xml` 选择场景、天气、氛围及关卡环境；`color_engine_preset.xml` 定义光照调色；`presentation_presets.v1.json` 定义天气粒子与命名氛围的视觉参数。每份数据由自己的消费者读取，放在一起便于核对场景引用及调色关系。

## 世界表现预设

`presentation_presets.v1.json` 是可编辑的视觉参数真源，由 C# Host 读取并传给原生合成器。场景 XML 仍选择天气类型、强度和氛围名称；AS2 保留天气与玩法权威。原生合成器只实现有限的画法类型和安全上限，不保存命名氛围的色值、强度、速度或天气的常用美术参数。

## 编辑边界

- `atmosphere[]`：`name` 是场景 `<Preset>` 的精确名称，`family` 是已实现的画法类型。可以用同一 `family` 新增名称；AS2 不维护氛围名白名单。`primary` / `secondary` 是 0–1 RGB；`base` / `edge` / `motion` 是合成强度；`rate` 是每秒相位速度；`frequency`、`focus`、`falloff`、`mix` 控制各画法的空间分布。
- `weather`：固定 `rain/snow/dust/fog/slash` 五类。`count` 是强度阈值筛选前的最大粒子数，原生安全上限 512；`size/alpha/speed/wind` 是视觉倍率。`primary/secondary` 是 0–1 RGB。雨花另用 `splashSize/splashAlpha/splashStart/edgeFade` 控制大小、透明度、周期起点与视口边缘淡出。非雨类的雨花字段仍须填写，当前不参与其绘制。
- 场景直接写 `<Overlay>` 时选择原生自定义叠加，仍从该 XML 读取 RGB、Alpha、Mode 与 Pulse。命名氛围要做变体时新增一个目录名称并在场景 `<Preset>` 中引用；不要同时给命名预设写 `<Overlay>`，后者会明确选择自定义画法。
- `color_engine_preset.xml` 管光照颜色矩阵，职责不同；本文件只管天气与氛围绘制参数。

## 数据改动验证

```powershell
node tools/validate-world-presentation-presets.js --check
```

该工具检查字段、范围、天气类型和场景 XML 的名称引用；Host 在启动时用同一版本合同重新严格解析并拒绝缺项、重复键和非法数值。原生接口也验证范围。预设文件缺失或无效时明确失败；天气和氛围均不恢复 AS2 绘制。

改动数值后重启开发候选即可生效，`event=world_presentation_catalog` 日志记录文件 SHA-256；可用 `launcher/perf/flash-compositor/run.ps1 -VisualPresets <路径>` 在隔离夹具预览候选文件。数据改动仍需内容交付和实际画面验收，但不改变 Core/原生 DLL。新增画法类型、改着色器公式或修雨花等算法错误仍须构建配对二进制候选并遵循独立的正式 runtime 发布流程。

本目录的 `.gitattributes` 将预设 JSON 固定为 LF 检出，因为 Host 记录的是文件原始字节 SHA-256。已有 Windows 工作树在拉取属性文件后，可重新检出该 JSON 以得到与新克隆一致的字节；无需改变视觉数值。
