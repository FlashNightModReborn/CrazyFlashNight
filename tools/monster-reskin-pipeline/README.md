# Monster Reskin Reference Pipeline

只读导出 Flash 怪物的整套动作、关键姿势和叶子零件，组装成人类重绘 / img2img 参考包。工具不会写 XFL、FLA 或 SWF，也不会代替 Flash CS6 发布。

## 边界

- 输入：现有 XFL/SWF、linkage 对应的 SWF character ID、待导出的叶子 shape ID。
- 输出：`tmp/monster-reskin/<怪物>/reference-package/` 下的 PNG、SVG、清单和绘制护栏。
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

导出器默认调用仓库内 `tools/ffdec/ffdec-cli.exe`。配置中的路径均相对仓库根目录；实际导出路径会写进 staging 目录的 `export-manifest.json`，组包器优先消费该清单。

## 配置要点

- `source.rootCharacterId`：根怪物 Sprite 的 SWF character ID。
- `keyposes[].frame`：FFDec 导出的 1-based 根时间轴帧号。
- `parts[].characterId`：可复用叶子 Shape ID；`group` 可区分常规骨架件和死亡专用件。
- `ignoreTopFraction`：根 Sprite 同时含血条/名字时，组包前从画布顶部清掉的比例。
- `heroFrame`：整机主参考帧。
- `variants`：把“纯换皮可行度”和不可越过的比例边界随参考包交给画师。
- `tailPlans` / `warlordRecognitionYoke` / `vectorRedrawGuardrails`：把长度倍率、世界观设备和矢量复杂度预算一并写入生成清单与包内说明。
- `componentConcepts`：登记每种换皮的 13 件组件参考图、外观简报和装备应烘入的既有叶子件。
- `componentConcepts[].splitDir`：指定 4×4 组件参考板切成 13 个逐件参考图后的目录。
- `componentSheetOrder` / `componentRedrawCaveats`：固定分件格序、上下颌归属、原点和死亡专用件等回填约束。
- `componentImagegenPromptTemplate`：保存以原分件板为几何约束、以整犬概念图为外观参考的精确编辑提示词模板。

FFDec 的 SVG 会保存局部坐标到画布的变换。导出器从该变换恢复红色原点十字；如果自动恢复失败，可在零件配置里显式写 `localOriginPx`。

组包只会重建 `whole/`、`keyposes/`、`parts/`、`sheets/` 以及生成清单；人工筛选的 `imagegen/` 目录会被保留，因此可反复重跑导出与组包而不丢失已冻结的概念图。

## 僵尸狗当前结论

`敌人-僵尸1-狗` 位于 `flashswf/arts/things1/things1.xfl`，根 SWF character 为 `1377`。常规动作复用 `Symbol 726`—`Symbol 738`，编译后为 Shape `1331`—`1343`；`血腥死` 还使用 25 个逐阶段合成的专用 Shape `1351`—`1375`。后者不是 25 块独立肢体，而是必须随皮肤复核的死亡帧图形。

| 选型 | 只换皮可行度 | 设计边界 |
|---|---:|---|
| 牧羊犬 / 军警犬 | 高 | 原骨架本来就是长腿、尖耳、长吻的轻型工作犬比例。 |
| 斗牛梗 / 盗贼撕咬犬 | 中高 | 可改蛋形头、粗颈和前胸，但应保留腿长、肩胯关节和咬合端点；更准确地说是“斗牛梗型混种工作犬”。 |
| 獒犬 / 军阀重型护卫犬 | 低（真重獒）/ 中（装甲化混种） | 真正短腿、巨头、宽胸重獒会导致脚滑、咬点漂移和翻滚失重；若坚持纯换皮，应做成保持骨架比例的獒系混种，以护甲、厚颈圈和背负件表达“重型”。 |

若第三种必须只换皮且要一眼显得更重，罗威纳型或“装甲獒系混种”比真正獒犬更适配现有动画。

## 验证

```powershell
chcp.com 65001 | Out-Null
python -m py_compile `
  tools/monster-reskin-pipeline/export_ffdec_assets.py `
  tools/monster-reskin-pipeline/build_reference_package.py `
  tools/monster-reskin-pipeline/split_component_concepts.py `
  tools/monster-reskin-pipeline/trace_xfl_dependencies.py `
  tools/monster-reskin-pipeline/smoke_test.py
python tools/monster-reskin-pipeline/smoke_test.py
```

真实素材验证还应执行示例配置的 FFDec 导出、组包和组件板切分，并人工查看关键姿势表、常规零件表、三套逐件参考图与死亡专用零件表。
