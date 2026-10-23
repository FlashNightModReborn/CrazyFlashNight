# 地图资产规范

**文档角色**：本批次地图资产的 canonical 制作与交付规范。任务定义见 `map-production/tasks.json`，关卡清单见 `map-production/stage-inventory.md`。

**本阶段边界**：只做地图资产，不新建或修改关卡 XML，不写 `data/environment/stage_environment.xml`，不挂正式选关，不做任务。每个地图组附独立环境建议片段，后续由脚本一键实装。

## 1. 一个任务是什么

一个任务只负责一个关卡的地图组：

- 主线关：默认 5 张主图。
- 支线长关：默认 5 张主图。
- 剧情短关卡、枢纽、擂台、过场：允许 3 图起；直升机前置允许 2 图。
- 同一个任务内不要混入第二个关卡。

任务包放在：

```text
map-production/packages/<task-id>/
  design.md                     # 5 图设计思路，开工前先写
  install.json                  # 任务、关卡、图序、安装方式
  manifest.json                 # 每张图的尺寸、地标、出口、审阅图
  environment.proposal.xml      # 独立环境条目，不合并进总表
  maps/
    <map-name>/
      <map-name>.xfl            # Flash CS6 XFL 工程
      <map-name>.svg            # 矢量源稿（推荐与 XFL 同批提交）
    <map-name>.swf              # 发布产物，与 XFL 同级
  review/                       # 裁边预览、接触表，gitignore
```

地图名统一使用小写 ASCII 和短前缀，避免中文路径预算和工具差异。建议：

```text
mp_noah_hq_01
mp_noah_hq_02
mp_snow_out_01
mp_snow_in_01
mp_univ_01
mp_ember_01
```

同一个关卡组的 5 张图使用同一前缀连续编号。安装后再映射到 `flashswf/backgrounds/<map-name>.swf` 和 `flashswf/backgrounds/<map-name>/<map-name>.xfl`。

## 2. 设计说明必须先写

`design.md` 至少包含：

- 关卡名、任务 id、在剧情中的位置。
- 5 图顺序和每图一句话场景目标。
- 左出生、右出口的衔接；例外时写清方向。
- 每图的地标、色彩、战斗节奏和遮挡关系。
- 参考关和参考图；没有设计文档的支线，先基于旧图写一致的空间与视觉语言。
- 状态变体说明：哪些图层变化、哪些碰撞/出口保持不变。
- 不能解决的设计问题，明确写“待定”，不要靠地图猜剧情。

主线旧图只作为空间尺度、地平线、碰撞和出生点参考，不整图照搬。支线没有现成关卡时，先写设计说明再开画。

## 3. 地图硬要求

- 背景是静态地图，首帧必须有且只有一条帧脚本：`_root.贴背景图();`。
- 不导出 linkage，不写 AS3/JavaScript，不手工修改 SWF。
- 默认画布 1750×600；允许 1400–1800 宽、500–900 高，但必须在 manifest 和环境片段中写明实际宽高。
- 每张图必须有可读的可行走地面层、明确的左/右出口和前景遮挡层；不要把敌人、玩家、UI、碰撞线画进背景。
- 同一关卡组内，出口高度和地面线要能对上；下一图入口位置必须与上一图出口逻辑一致。
- 5 图默认从左到右推进；特殊方向（上下、返程）必须在 design.md 写明理由。
- 每张图至少有一个可辨认地标；不允许 5 张图只是同一走廊换色/换贴图。
- 允许复用单个道具、材质、灯带、标志和构件；不允许整图复制，不允许只做滤镜/换色就称新图。
- 状态变体共享 XFL 母版时，只改叙事层和遮挡层；碰撞、出口、地面线保持可对齐，不覆盖原图。

## 4. 图层与 XFL

XFL 工程目录是 `maps/<map-name>/`，CS6 入口标记文件是 `maps/<map-name>/<map-name>.xfl`，`DOMDocument.xml` 与标记同目录（CS6 的 XFL 就是“目录 + 同名标记文件”）。最低图层职责：

```text
background-bake     # 首帧 _root.贴背景图(); 只放这一条脚本
sky-far             # 远景、天光、远景剪影
mid                 # 中景建筑、地形、主要道具
gameplay            # 玩家可行走区域和可读的战斗空间
foreground          # 前景遮挡、近景构件
```

图层名可以更具体，但必须保留上述职责。不要在 `gameplay` 层放会遮挡角色的整块前景。XFL 的 `PublishSettings.xml` 输出到 `maps/<map-name>.swf`；发布设置不输出 HTML/PNG 包装。

## 5. 环境建议片段

`environment.proposal.xml` 使用独立 wrapper，内部每个 `<Environment>` 必须和 `data/environment/stage_environment.xml` 的字段一致，方便脚本原样插入：

```xml
<EnvironmentProposal task="ML-NOAH-005" stage="指挥部大厅" stageXml="data/stages/诺亚前线基地深处/指挥部大厅.xml">
  <Environment>
    <BackgroundURL>mp_noah_hq_01.swf</BackgroundURL>
    <Alignment>true</Alignment>
    <Xmin>50</Xmin>
    <Xmax>1750</Xmax>
    <Ymin>330</Ymin>
    <Ymax>600</Ymax>
    <Width>1750</Width>
    <Height>600</Height>
    <Door>
      <Index>1</Index>
      <Direction>右</Direction>
      <x0>1700</x0>
      <y0>330</y0>
      <x1>1750</x1>
      <y1>600</y1>
    </Door>
    <Collision>
      <Point>0,330</Point>
      <Point>1700,330</Point>
      <Point>1700,600</Point>
      <Point>0,600</Point>
    </Collision>
    <LeftSpawnLine>
      <x0>50</x0>
      <y0>600</y0>
      <x1>300</x1>
      <y1>600</y1>
    </LeftSpawnLine>
    <RightSpawnLine>
      <x0>1450</x0>
      <y0>600</y0>
      <x1>1750</x1>
      <y1>600</y1>
    </RightSpawnLine>
  </Environment>
  <!-- 其余 4 张图同样各一条 -->
</EnvironmentProposal>
```

要求：

- 每张图一条 `<Environment>`，`BackgroundURL` 与 SWF 文件名一致。
- 碰撞、门、刷怪线按实际构图填写；无法确定时在 `design.md` 标记待校准，不要编造精确坐标。
- 不复制无关环境字段；需要 `Skybox`、`Instances`、`Preset`、`Lights` 时写明来源和用途。
- 本文件只是建议，不合并进总表。安装脚本必须保留总表现有同名条目，冲突时报告，不静默覆盖。

## 6. `install.json` 与 `manifest.json`

`install.json` 描述这个包属于哪个任务、按什么顺序装：

```json
{
  "taskId": "ML-NOAH-005",
  "stage": "指挥部大厅",
  "area": "诺亚前线基地深处",
  "stageXml": "data/stages/诺亚前线基地深处/指挥部大厅.xml",
  "installMode": "replace_existing_backgrounds",
  "mapOrder": ["mp_noah_hq_01.swf", "mp_noah_hq_02.swf", "mp_noah_hq_03.swf", "mp_noah_hq_04.swf", "mp_noah_hq_05.swf"],
  "requiresStageXmlEdit": true,
  "notes": "地图组完成后由人工复核，再决定是否替换旧背景引用。"
}
```

`manifest.json` 记录每张图的实际交付信息：

```json
{
  "schemaVersion": 1,
  "taskId": "ML-NOAH-005",
  "stage": "指挥部大厅",
  "maps": [
    {
      "order": 1,
      "name": "mp_noah_hq_01",
      "swf": "mp_noah_hq_01.swf",
      "xfl": "maps/mp_noah_hq_01/mp_noah_hq_01.xfl",
      "width": 1750,
      "height": 600,
      "exit": "right",
      "landmark": "前厅与安检闸机",
      "review": "review/mp_noah_hq_01.png"
    }
  ]
}
```

`installMode` 只允许：

- `replace_existing_backgrounds`：主线旧关替换背景；本阶段只写建议，不改 XML。
- `new_stage_maps`：支线未来新关卡；本阶段只交地图包。
- `state_variant`：状态变体；必须写清母版和变化层。

## 7. 审阅与证据

每个任务必须产出：

- 5 张裁掉透明边的 PNG 预览；FFDec 导出后按 alpha 包围盒裁切。
- 一张按地图顺序排列的接触表，标出地图名、尺寸和出口方向。
- `design.md` 与实际图的对照说明。
- 发布日志和 SWF 检查记录。

证据边界：

- `compiled`：XFL 已由真实 CS6 发布，SWF 存在，首帧脚本正确。
- `reviewed`：预览图和接触表已生成，设计说明逐图对上。
- `runtime_verified`：人工把地图装进实际关卡并走通；本阶段不声称达到。
- 没有 CS6 的组员只能交 XFL 和 `pending_publish`，不能标“完成”。
- 发布模式没有 trace 属正常；不要把 Output Panel 副本当成本轮证据。

## 8. 一键实装契约

后续安装脚本只做以下事情：

1. 读取 `install.json` 和 `environment.proposal.xml`。
2. 复制 SWF/XFL 到 `flashswf/backgrounds` 的正式位置。
3. 将环境条目合并进 `stage_environment.xml`；同名条目冲突时保留双方并报错，不静默覆盖。
4. 仅在明确授权时，按 `mapOrder` 修改指定关卡 XML 的 Background 引用。
5. 重新跑 XML 解析、环境唯一性、SWF 首帧和路径预算检查。

本阶段不实现安装脚本，也不提前修改关卡；脚本契约先固定，等人工复核后再接。

## 9. 矢量地图制作路线

本批正式地图只用 Flash CS6/XFL 的矢量绘制或拼装，不使用 ImageGen 或第三方生图工具，也不生成 AI 概念图。

已经验证过的链路：

```text
手写/脚本生成 SVG（1750×600，命名分组即图层）
  → tools/map-production/svg_to_xfl_map.py
  → XFL（background-bake 层自动注入 _root.贴背景图();，frameRate=30）
  → scripts/compile_test.ps1 -Target <xfl> -PublishOnly -VerifySwf <swf>
  → FFDec 导出 PNG 自审
```

`svg_to_xfl_map.py` 的输出目录传 `maps/<map-name>/`；XFL 内容（`DOMDocument.xml`、`LIBRARY/`、同名 `.xfl` 入口标记）写在该目录，SWF 按发布设置写到上一级的 `maps/<map-name>.swf`。

2026-10-23 的隔离探针已跑通：1750×600 SVG 转成 42 个原生 shape、172 段 edge，真实 CS6 发布 Compiler 0/0，SWF 2,652 字节，首帧脚本存在。这个探针只证明链路成立，不代表美术质量验收。

SVG 约束：

- 顶层 `<g id="...">` 会变成 XFL 图层；必须有 `background-bake` 组。
- 渐变使用 `gradientUnits="userSpaceOnUse"`；不要用外部 `<use>`、滤镜、位图或未转曲文本。
- 圆弧先用 Q/C 曲线展开；转换器会拒绝不支持的 path 命令。
- 复用现有地图的单个矢量构件、材质和摆件；不把整张旧图或整层位图塞进新图。
- 地图必须仍是可编辑矢量源；不要用一张生成图或整层栅格化代替绘制。

高质量地图需要多轮“SVG → 发布 → FFDec 预览 → 改构图/材质/遮挡”，不能只靠一次转换。组员没有 CS6 时仍可交 SVG 和 XFL，标 `pending_publish`。

## 10. 禁止项

- 不使用 ImageGen 或任何第三方生图工具生成正式地图或概念图。
- 不新建或修改 `data/stages/**`、`data/stages/list.xml`、`__list__.xml`。
- 不修改 `data/environment/stage_environment.xml`。
- 不挂 `launcher/web/modules/stage-select-data.js`。
- 不提交截图、FFDec 导出、`review/` 中间图、FLA、临时 SWF。
- 不手工改 SWF，不用整图贴图冒充重制。
- 不把已有任务关、已重置关、二层、地下2层、旧副本重新纳入。
- 不在未写 `design.md` 时直接开画。

## 11. 完成定义

一个地图组算完成，需要同时满足：

- `design.md` 完成，5 图顺序和出入口逻辑成立。
- 每张图有可编辑的 SVG/XFL 矢量源，没有使用生图或整层栅格化。
- 5 张 SWF 已发布，首帧脚本正确，尺寸与 manifest 一致。
- 5 张预览已裁边，接触表可读，地标和战斗空间有区分度。
- `install.json`、`manifest.json` 和 `environment.proposal.xml` 齐全，字段可被后续脚本解析。
- 没有改动任何关卡、环境总表、选关清单或任务数据。
- 人工复核前，状态只写 `reviewed`，不写“已实装”。
