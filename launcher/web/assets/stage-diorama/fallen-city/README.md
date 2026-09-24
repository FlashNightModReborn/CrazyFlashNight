# 堕落城 P8-H1 运行候选

用于“基地车库”选关。模型、独立选择、语义数据和回退图一起采用，不能仅替换主 GLB。

- 可编辑真源：`堕落城-P8-H1-完整工程与经验-20260924.zip` 内 `P8工程/工程/model/fallen-city-p8.blend`；ZIP 身份在 manifest 中固定。
- 运行导入：[import-fallen-city-diorama.py](../../../../../tools/import-fallen-city-diorama.py)，生成配置、运行文件和完整性/体积清单；`--check` 校验已导入闭包。
- 接入与验收：[P8 游戏集成候选](../../../../../docs/堕落城P8游戏集成候选-2026-09-24.md)。
- 主体和选择 GLB 保持回包字节，使用已有 Three.js r180 与总部后处理依赖。geometry、纹理和帧循环由场景适配器持有并释放。
- AS01 必须按 `selectionPartitions` 区分 assembly/residential；关卡的活动关系与常驻归属独立。

这里不保存美术机完整历史、Blender 中间模型或玩家状态。既有源 ZIP/完整工程继续作为精修来源，运行合批模型不替代编辑源。

导入的 JSON 统一为 LF 行尾，语义不变；GLB/图像保留回包原字节。manifest 绑定运行派生物，源 ZIP 哈希另存用于追溯。
