# 美术资产装配

**文档角色**：现实原型导入、装备缩放与分件装配的 canonical 操作入口；按需路由到已有工具和专项规则。<br>
**最后核对代码基线**：commit `948acc4c8481c6eb28b1a8931043508fc761621b`（2026-09-05）。

## 1. 什么时候读

涉及外部画稿 / 现实原型导入、装备体量校准、人体分件换皮、注册点或素材库装配时读取本文。纯物品数值和文案调整按 [data-schemas.md](data-schemas.md) 与平衡工具入口处理。

本文把已经存在的度量衡、换皮预览和 XFL 治理串起来，使装配时能直接找到计算与校验入口；不引入新的验收单或发布流程。

## 2. 先确认坐标层与目标资产

装配前从原元件和 [asset_source_map.xml](../data/items/asset_source_map.xml) 确认：

| 要确认的量 | 用途 |
|---|---|
| 目标 XFL、完整库元件名、linkage ID | 决定编辑和发布归属；三者不能混用 |
| 运行时直接挂载的外层、当前编辑的内层 | 确定是否还需要除去嵌套倍率 |
| 原型已知长度，以及画稿中对应的线段长度 | 建立现实尺寸与内容像素的对应关系 |
| 注册点、握持点 / 肢体关节、枪口 / 刀口 | 总长度变化时仍能维持装配接口 |
| 性别、动作、身高假设、是否沿用旧装备的夸张比例 | 判断默认人体标尺是否适用，美术倍率应单独记录 |

缺少依赖路径时用 [前向依赖追踪](../tools/monster-reskin-pipeline/README.md)；没有路径疑问就直接使用已知元件，不必先扫描全仓。

## 3. 尺度换算与装配顺序

1. **选标尺。** 当前常规男模的制作档位由 [profiles.json](../tools/asset-metrology/profiles.json) 维护：武器选 `weapon`，身体 / 四肢选 `body`，脸型 / 面具选 `head`。配置明确限定 175 cm 放松站姿，不按当前持枪姿势的包围盒重定身高；非人形和未标定姿势不能直接套用。
2. **量对应内容。** 已有 XFL 用 `symbol` 测局部轮廓；图片测原型已知长度对应的内容，排除留白、透明边框、披风外沿和逻辑标记。透视照片或旋转元件用对应端点，不直接用横向外框代替实际全长。
3. **算目标尺寸。** 用 [度量衡工具](../tools/asset-metrology/README.md) 的 `convert` 输入现实长度和源图内容像素。当前编辑层还会被等比缩放时，传 `--nested-scale`；沿用美术夸张时另传 `--style-factor`，保持米制基准独立。
4. **保持装配接口。** 在目标元件副本中调整画稿，以握持点 / 关节注册点为基准。枪口、刀口另行与实际端点对齐；身体件沿用原视角、左右复用关系和接口余量。默认尺只解决总体量，不保证固定双手间距或非等比姿势变形自动吻合。
5. **预览后回填。** 人形分件用已有 battle rig 多姿势重组；怪物用既有动作 / 关键姿势参考。详细的共享件、遮挡面、语义复核和回装要求统一见 [换皮参考管线](../tools/monster-reskin-pipeline/README.md)。纯静态测量无需启动整套换皮验收。
6. **按实际归属发布。** 改回 XFL 后按 [XFL 校准工具](../scripts/tools/xfl/README.md) 检查，再执行该目标的独立发布与受影响消费者验证；新增库的 things-new 挂载和 SWF 约束遵循 [AGENTS.md](../AGENTS.md)。选择 `main` 必须有主 XFL 改动依据。

换算结果可随既有候选记录保存原型长度、所选 profile、内层倍率、美术倍率和注册点说明；JSON / SVG 放任务自己的 `tmp/asset-metrology/<项目>/`。不用为每件资产另造一套 receipt 或审批步骤。

## 4. 工具按问题选用

| 当前问题 | 入口 |
|---|---|
| 现实厘米换成局部像素、当前画稿该缩到多少 | [asset-metrology：convert](../tools/asset-metrology/README.md#换算现实长度) |
| 原元件多宽多高、枪口标记是否撑大外框 | [asset-metrology：symbol](../tools/asset-metrology/README.md#测量已有元件) |
| 人模或挂载缩放变了，默认尺是否仍成立 | [asset-metrology：calibrate](../tools/asset-metrology/README.md#复算人模基准) |
| 动作、子元件、局部原点与换皮后拼装 | [monster-reskin-pipeline](../tools/monster-reskin-pipeline/README.md) |
| 重名、linkage 冲突、Include / 引用一致性 | [scripts/tools/xfl](../scripts/tools/xfl/README.md) |
| 装备运行时逻辑、特效或生命周期接线 | [装备函数 README](../scripts/逻辑/装备函数/README.md) |
| Flash 编译目标、静态与实际运行验证边界 | [testing-guide.md](testing-guide.md) |

## 5. 知识放在哪里

| 层级 | 维护职责 |
|---|---|
| `AGENTS.md` | 装配任务应该先读本文；只放触发条件和入口 |
| 本文 | 跨工具装配顺序、坐标 / 注册点判断、何时调用哪条工具链 |
| `tools/asset-metrology/README.md` | 可复制命令、参数、输出、依赖和定向验证 |
| `tools/asset-metrology/profiles.json` | 程序读取的制作档位；更新必须带对应标定依据 |
| [175 cm 首轮调查](../docs/装备素材度量衡-175cm人模标尺-2026-09-05.md) | 当次源矩阵、测量读数、推导和样本；作为历史证据保留 |
| `tmp/asset-metrology/<项目>/` | 可重建的 JSON、轮廓 SVG 与项目临时诊断；复用代码不留在这里 |

改骨架、holder、裸体基准或身高约定时重算标尺，确认采用后维护配置与证据；改命令或输出时维护工具 README 与 [验证矩阵](testing-guide.md)。本入口只引用数值真源，历史报告不作为另一份现役配置。
