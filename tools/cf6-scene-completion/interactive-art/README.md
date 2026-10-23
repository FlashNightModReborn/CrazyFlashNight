# CF6 交互油桶与培养皿原生美术

唯一生成入口为 `../build_interactive_art.py`，身份、输入、24 个原作实例与触发矩形见 `../interactive-art-manifest.json`。生成器只写 XFL 源，不写 SWF、不启动 Flash、不携带原作业务动作。

- 油桶 1736 / 1838 / 1976 使用完整 16 帧新绘形状；服务在第 7 帧执行伤害。
- 培养皿 1939 使用完整 25 帧新绘形状，包括 1906 内部克隆人装饰；服务在第 24 帧通过既有敌人权威消耗原预算。该装饰不是玩家人物替身。
- 每帧生成 `stop()`，末尾空帧完整保留；不能用“每帧非空”作为验收条件。
- 删除 277 / 359 / 360 / 1433 逻辑标记，不复制原作攻击、奖励、切图、产怪或玩家控制脚本。SVG 原生局部透明遮罩保留生成的缓存遮罩动作。
- 保留原符号注册 `(0,0)` 及各帧局部矩阵，不做全帧归一化或偏移补偿。世界锚点、脚点深度及视觉倍率由场景装配统一处理。
- 小块内嵌纹理由 SVG 原始 data URI 提取，4 个 SHA 身份与尺寸在 manifest 中；不是整帧贴图。

## 受控生成

1. 在具备现有原生矢量依赖的 Python 中运行 `build_interactive_art.py` 生成 fragments。
2. 根执行者通过仓库受控 CS6 队列执行 `import-textures.jsfl`，创建独立 `CF6_InteractiveTextureSeed`。不得手造 `bin` 缓存。
3. 运行 `build_interactive_art.py --assemble`，再运行 `build_interactive_art.py --assemble --check`；真实导入媒体与缓存经 `native_xfl.audit` 校验。
4. 根执行者对 manifest 中 4 个独立 XFL 分别执行真实 CS6 `-PublishOnly -VerifySwf`。输出 SWF 位于 preparation 目录，其编译回执与运行验收另行保存。

已有受管输出身份变化时生成器拒绝覆盖。未完成真实编译与运行验证前，manifest 的 source 状态不代表可交互或体验通过。
