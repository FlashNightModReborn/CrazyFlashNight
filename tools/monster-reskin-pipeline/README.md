# Monster Reskin Reference Pipeline

只读导出 Flash 怪物的整套动作、关键姿势和叶子零件，组装成人类重绘 / img2img 参考包；已有 Web Dressup 纸娃娃可作为人形装备换皮的整机参考上游。工具不会写 XFL、FLA 或 SWF，也不会代替 Flash CS6 发布。

现实原型尺寸、装备缩放与注册点的前置判断见 [美术资产装配](../../agentsDoc/art-asset-assembly.md)；需要换算厘米、测量元件或复算人模时调用 [asset-metrology](../asset-metrology/README.md)，随后复用本文的逐件与整机预览流程。

## 边界

- 输入：现有 XFL/SWF、linkage 对应的 SWF character ID、待导出的叶子 shape ID。
- 输出：只允许写入 `tmp/monster-reskin/<项目>/` 下的 PNG、SVG、清单和绘制护栏；拒绝把仓库根目录或任意外部目录当成清理目标。
- FFDec 产物只作参考；最终矢量仍应在原叶子元件的副本中人工重绘。
- 保持局部原点、关节重叠区、装配矩阵、动作标签和碰撞/攻击点；新皮肤使用新 linkage，不覆盖原怪。
- 本工具属于只读参考层，不扩张为 XFL 自动写入器。

## 典型流程

```powershell
chcp.com 65001 | Out-Null
python tools/monster-reskin-pipeline/trace_xfl_dependencies.py `
  --xfl flashswf/arts/things1/things1.xfl `
  --symbol 敌人-僵尸1-狗 `
  --output tmp/monster-reskin/敌人-僵尸1-狗/xfl-dependencies.json

python tools/monster-reskin-pipeline/export_ffdec_assets.py `
  --config tools/monster-reskin-pipeline/examples/zombie-dog-family.json

python tools/monster-reskin-pipeline/build_reference_package.py `
  --config tools/monster-reskin-pipeline/examples/zombie-dog-family.json

python tools/monster-reskin-pipeline/split_component_concepts.py `
  --config tools/monster-reskin-pipeline/examples/zombie-dog-family.json
```

导出器默认调用仓库内 `tools/ffdec/ffdec-cli.exe`。配置中的路径均相对仓库根目录；实际导出路径会写进 staging 目录的 `export-manifest.json`。组包器会核对怪物名、SWF、根 character、动作 Sprite 和每个 Shape ID，拒绝消费同 slug 的旧怪物清单。

## 配置要点

- `source.rootCharacterId`：根怪物 Sprite 的 SWF character ID。
- `sequences[]`：不含血条/名字的动作子 Sprite；用 `slug + characterId + startFrame/endFrame` 声明需要的固定画布动作段。
- `keyposes[].sequence + frame`：FFDec 导出的 1-based 动作局部帧号。
- `parts[].characterId`：可复用叶子 Shape ID；`group` 可区分常规骨架件和死亡专用件。
- `ignoreTopFraction`：仅保留为旧配置兼容；截断行命中任何非透明像素时会失败。血条覆盖身体的根 Sprite 必须改用无 UI 动作子 Sprite，不能靠裁切恢复被遮挡像素。
- `heroPose`：整机主参考姿势的 `keyposes[].slug`。
- `variants`：把“纯换皮可行度”和不可越过的比例边界随参考包交给画师。
- `tailPlans` / `warlordRecognitionYoke` / `vectorRedrawGuardrails`：把长度倍率、世界观设备和矢量复杂度预算一并写入生成清单与包内说明。
- `componentConcepts`：登记每种换皮的 13 件组件参考图、外观简报和装备应烘入的既有叶子件。
- `componentConcepts[].splitDir`：指定 4×4 组件参考板切成 13 个逐件参考图后的目录。
- `componentSheetOrder` / `componentRedrawCaveats`：固定分件格序、上下颌归属、原点和死亡专用件等回填约束。
- `componentImagegenPromptTemplate`：保存以原分件板为几何约束、以整犬概念图为外观参考的精确编辑提示词模板。

FFDec 的 SVG 会保存局部坐标到画布的变换。导出器从该变换恢复红色原点十字；如果原点在紧画布外，组包器会扩展预览画布并记录 `originOverlayOffsetPx`，不会静默丢掉标记。自动恢复失败时可在零件配置里显式写 `localOriginPx`。

组包只会重建 `whole/`、`keyposes/`、`parts/`、`sheets/` 以及生成清单；人工筛选的 `imagegen/round-*` 目录会被保留，因此可反复重跑导出与组包而不丢失已冻结的概念图。`whole/full-sequence/<动作>/` 保留同一动作 Sprite 的固定画布；紧裁切只用于 `keyposes/` 和接触表。

## 僵尸狗当前结论

`敌人-僵尸1-狗` 位于 `flashswf/arts/things1/things1.xfl`，根 SWF character 为 `1377`，但根 Sprite 的人物文字和血条会遮住击倒/死亡姿势，不能作为干净参考源。当前配置直接导出 UI-free 动作 Sprite `1344/1345/1347/1348/1349/1350/1376`。常规动作复用 `Symbol 726`—`Symbol 738`，编译后为 Shape `1331`—`1343`；`血腥死` 还使用 25 个逐阶段合成的专用 Shape `1351`—`1375`。后者不是 25 块独立肢体，而是必须随皮肤复核的死亡帧图形。

| 选型 | 只换皮可行度 | 设计边界 |
|---|---:|---|
| 牧羊犬 / 军警犬 | 高 | 原骨架本来就是长腿、尖耳、长吻的轻型工作犬比例。 |
| 斗牛梗 / 盗贼撕咬犬 | 中高 | 可改蛋形头、粗颈和前胸，但应保留腿长、肩胯关节和咬合端点；更准确地说是“斗牛梗型混种工作犬”。 |
| 獒犬 / 军阀重型护卫犬 | 低（真重獒）/ 中（装甲化混种） | 真正短腿、巨头、宽胸重獒会导致脚滑、咬点漂移和翻滚失重；若坚持纯换皮，应做成保持骨架比例的獒系混种，以护甲、厚颈圈和背负件表达“重型”。 |

若第三种必须只换皮且要一眼显得更重，罗威纳型或“装甲獒系混种”比真正獒犬更适配现有动画。

## 人形装备：Web Dressup 上游

纸娃娃路线成立，但要把“整机定风格”和“逐件保几何”拆成两道门：

1. 用 `data/items/*.xml` 的五个装备名驱动 `launcher/web/assets/dressup/manifest.json`，按 dialogue/battle rig 合成完整人模。
2. 把固定姿态的透明 Canvas PNG 提交给 img2img，只冻结整套的轮廓语言、配色、材质和识别特征。
3. 定稿后逐个 skinKey 生成部件：每次以原透明部件 PNG 作为几何/注册点约束，以冻结整机图作为外观参考。不要把整机图机械网格切开后直接回填；遮挡面、左右件、关节余量和局部原点会丢失。
4. 每轮保存 `round-N/whole`、`round-N/components`、prompt、seed/模型信息和接受/拒绝清单。只有整机与全部原件对照均通过时才进入 Flash 人工矢量重绘。

钛合金61式套装已有可复跑 preset：

```powershell
chcp.com 65001 | Out-Null
node tools/run-dressup-harness.js `
  --browser edge `
  --init-file tools/monster-reskin-pipeline/examples/titanium-61-dressup.json `
  --canvas-shot "tmp/monster-reskin/钛合金61式套装/dressup-reference/battle-空手站立.png"
```

当前 manifest 中每个性别组装一套装备需要 12 个唯一静态 skinKey（头 1、手 2、胸 4、腿 4、鞋 1）；女模替换胸/腿 8 件，因此男女并集共有 20 个钛合金61相关 key。**12 个唯一素材不等于 12 个运行时 holder**：battle rig 每个姿势实际放置 15 次，其中 `上臂`、`小腿`、`脚`各把同一 skinKey 原向复用两次。

| 字段 | 唯一素材 | holder 放置 | 左右关系 | 设计约束 |
|---|---:|---:|---|---|
| `上臂` | 1 | 2 | 同图、非镜像 | 左右肩壳和上臂必须共用同一剪影；禁止单侧肩炮、编号、灯位或方向性徽记。 |
| `小腿` | 1 | 2 | 同图、非镜像 | 膝下纵筋、侧面节点和灯槽必须能在两腿原向复用。 |
| `脚` | 1 | 2 | 同图、非镜像 | 不存在独立左鞋/右鞋；鞋头与踝甲必须采用无左右脚版本。 |
| `左/右下臂` | 2 | 2 | 独立 | 允许轻微左右差异，但与共享上臂的肘部接口必须一致。 |
| `左/右手` | 2 | 2 | 独立 | 保持各自握持端点，不得把手甲烘进下臂。 |
| `左/右大腿` | 2 | 2 | 独立 | 允许髋裙侧片适配两侧，但与共享小腿的膝部接口必须兼容。 |

这里的“非镜像”来自 battle rig 六个站立状态的 holder 矩阵检查：复用件的变换行列式均为正，运行时只是旋转、缩放和平移同一张图。概念设计因此必须避免把世界空间的固定左/右光源、单侧管线、文字或不对称轮廓烘进共享件。逐件流程应先完成 `上臂`、`小腿`、`脚`三张复用母件，再同时装到双侧 holder，在全部参考姿势中检查穿插和关节余量。

preset 的 `rigReuseConstraints` 保存这组机器可读约束；默认使用 battle `空手站立` 并把动画时钟冻结到 0ms，确保多轮整机参考可重现；可用 `--state-label` 覆盖为长枪、手枪、双枪或兵器站立。

### Flash 人工矢量回填的细节预算

高分辨率 img2img 概念件通常包含拉丝、噪点、细铆钉、连续倒角和照片级反射；这些信息即使视觉漂亮，也会在 Flash 人工回填或自动描摹时膨胀为大量短曲线与碎色块。进入最终回装前应增加一轮“矢量细节预算”转换：以当前源视角分件为几何权威、原 Flash skin 为密度参考、先通过的一件大部件为低细节风格母版，逐件重新合并机械分区。

- 银色最多三档，黑色/红色最多两档；每块主板最多一个大高光面。
- 只保留外轮廓、关节接口、宏观板块、必要结构缝、少量大紧固件和识别灯。
- 禁止拉丝/噪点、细碎铆钉、连续多级倒角、同心微环、照片级反射与装饰性微面板。
- 低细节 PNG 仍只是人工重画参考，不应直接自动描摹后当成最终 Flash 矢量。

历史高漂移轮可以走同一预算作为**形态素材池支线**，但必须和当前 battle 几何分开保存。对比时记录“可借用的宏观分区”，再把它投影回当前源朝向件；禁止直接拼接不同视角的 PNG，也不得让参考支线冒充通过回装的主清单。主线 12 件完成语义检查后仍须执行下方六状态强制门。

### 逐件回装审计

生成的高分辨率逐件图不能直接覆盖 Web PNG：其画布、alpha 包围盒和局部比例通常已偏离原 skin。`audit_dressup_reskin.py` 会先生成两套临时 preview skin，再通过 Playwright 请求拦截回装到真实 battle rig；正式 manifest 与 `launcher/web/assets/dressup/skins/` 均不修改。

进入回装前必须先做**逐件人工语义门**：手部核对四指 + 拇指、左右与握持方向；鞋核对鞋身完整、短踝接口和不越权包含小腿；其余部件核对人体结构、部件归属及共享件的非镜像约束。manifest 必须显式记录 `semanticGate.passed=true`、非空 `reviewer`，以及至少一条全部通过的 `checks[]`；脚本会把结果写入 `gate.semanticComponentReviewPassed`，缺失或任一检查未通过时 battle rig 强制门失败。连通区域、画布占用和六态装配都无法自动证明手指数或机械零件语义正确。

```json
{
  "semanticGate": {
    "passed": true,
    "reviewer": "human-visual",
    "checks": [
      { "component": "左手", "passed": true, "finding": "四指 + 拇指，方向与腕口正确" },
      { "component": "脚", "passed": true, "finding": "鞋身完整，短踝接口，无小腿越权" }
    ]
  }
}
```

- `fit`：保持生成件自身长宽比，contain 到原画布，用于暴露关节缺口和轮廓缩水。
- `masked`：cover 原画布并恢复原 skin alpha，只用于检查合法分件边界内的颜色占用和裁切结果。它不会重新推理机械结构，alpha 差异恒为 0 也不代表接口连续；必须把它视为诊断投影，不能作为候选资产或接口连续性通过证据。
- 每个姿态输出原版 / `fit` / `masked` Canvas，并生成红色=仅原版、青色=仅生成版的 alpha 差异图。
- override JSON 只允许引用仓库内文件；runner 会确认每个声明的 skin 请求都实际命中，否则失败。

钛合金61当前工作流示例：

```powershell
chcp.com 65001 | Out-Null
python tools/monster-reskin-pipeline/audit_dressup_reskin.py `
  --component-manifest "tmp/monster-reskin/钛合金61式套装/components/round-05-male-skin-parts/component-manifest.json" `
  --dressup-preset tools/monster-reskin-pipeline/examples/titanium-61-dressup.json `
  --output "tmp/monster-reskin/钛合金61式套装/assembly-audit/round-06-preview" `
  --browser edge
```

正式验收固定覆盖空手、长枪、手枪、手枪2、双枪和兵器六态。重点查看 `audit.json`、`README.md` 与 `sheets/all-states-assembly-review.png`；高漂移组件完成修订且下述 battle rig 强制门通过后，才进入 Flash 叶子元件人工矢量回填。

默认命令现在是 **battle rig 强制验收门**，不是可选预览。返回码 0 必须同时满足：manifest 的人工语义门通过；preset 明确声明 `rig="battle"`；`verifiedStateLabels` 与固定六态完整且顺序一致；当前性别恰好闭包到 12 个唯一 skinKey / 15 次部件 holder 放置；baseline、`fit`、`masked` 三套 Canvas 在每个姿态都非空且 `missing=0`；两种回填的 12 个 override 在每个姿态全部实际命中；六张姿态审计图与总览图均成功落盘。结果写入 schema 2 的 `gate.semanticComponentReviewPassed`、`gate.battleRigReassemblyPassed` 与 `battleRigAcceptance`，只有前两者均为 `true` 才算通过该门；`technicalAssemblyPassed` 保留为较低层兼容信号，`geometryReviewRequired` 仍是独立的人工几何提醒。

`--state` 子集只允许显式搭配 `--diagnostic-only`，此时即使命令返回 0 也只代表所选姿态技术运行成功，报告会标记 `diagnosticOnly=true`，不得声称已通过 battle rig 验收。正式验收应去掉这两个参数，始终复跑完整六态。

### 原蒙版后的接口约束再生成

若 `masked` 回装出现肩—肘、腕、髋—膝、胫—踝等机械链断裂，不能继续靠 cover / crop 调参。正确流程是把六态 `masked` 整机重新提交给 img2img：先以空手站立生成结构连贯的身份母版，再让其余姿态同时参考各自姿势图与该母版，冻结轴套、环形关节、重叠护板和黑色软连接的共同接口语言。整机再生成图仍只是上下文锚点，不直接进游戏。

随后按依赖链重新生成分件：`身体/骨盆 → 共享上臂/共享小腿 → 左右下臂/左右大腿 → 左右手/共享鞋 → 头部`。每件必须同时参考相邻已冻结部件和至少两个能看到该接口的整机姿态；完成后再回到六态 battle rig 强制门。也就是说，`masked` 负责暴露问题，整机再生成负责建立连续结构，最终分件回装才负责验收，三者不能互相替代。

Web PNG/manifest 是参考派生产物，不是 Flash 美术源。钛合金61原 linkage 位于 `flashswf/arts/things/things.xfl` 的 `0.防具相关/92&61套装/`；替换原套装时在对应叶子元件中人工重绘，新增并存皮肤则按仓库治理通过 `flashswf/arts/things-new.fla` 挂载新 linkage。两种路线都要保留原注册点/holder 语义，并在 Flash 发布后重新烘焙 Dressup manifest 做整机回归。

## 验证

```powershell
chcp.com 65001 | Out-Null
python -m py_compile `
  tools/monster-reskin-pipeline/export_ffdec_assets.py `
  tools/monster-reskin-pipeline/build_reference_package.py `
  tools/monster-reskin-pipeline/split_component_concepts.py `
  tools/monster-reskin-pipeline/audit_dressup_reskin.py `
  tools/monster-reskin-pipeline/trace_xfl_dependencies.py `
  tools/monster-reskin-pipeline/smoke_test.py
python tools/monster-reskin-pipeline/smoke_test.py
node --check tools/run-dressup-harness.js
```

真实素材验证还应执行示例配置的 FFDec 导出、组包和组件板切分，并人工查看固定画布动作、关键姿势表、常规零件表、三套逐件参考图与死亡专用零件表。人形装备另跑 Dressup preset，要求 `missing=0`、keyMap 完整且 Canvas 非空。
