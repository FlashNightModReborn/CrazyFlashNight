# 弹壳与枪火资源派生

`build.py` 从 `flashswf/arts/原版素材库-子弹` 的 XFL 行为定义和对应已发布 SWF
生成 `data/combat_visuals/effects.v1.json`、`effects-atlas.png`。编辑源仍是原 XFL，
不要手改图集、裁切偏移或帧序列。没有修改美术时不需要重编素材库 SWF。

```powershell
python -B -X utf8 tools/combat-fx-assets/build.py
python -B -X utf8 tools/combat-fx-assets/build.py --check
```

依赖 Python/Pillow、现有 `tools/ffdec` 和 Java JDK。优先使用 PATH/JAVA_HOME 中的
`java`、`javac`，否则查找已安装 Adobe Animate 的 JRE/JDK；工具不会下载安装。
Java 导出器只读 SWF，显式选择零基帧，不执行 ActionScript，也不修改发布产物。

范围由生成器配方固定：弹壳目录的 18 个静态导出、10 个常用枪火，以及 7 个同源命中特效。
枪火的 `removeMovieClip` 转为有界序列终点；通用 `枪火` 的 `random(3)` 转为
创建时选择 a0/a1/a2 的三个预设。源中 a0/a2 的选中画面为空，当前如实保留；
Y=0 的移除条件保留为 `skipOriginYZero`。新增脚本或弹壳动画会使生成失败，必须先审查适配。
Barrett 的嵌套图形/渐变由 FFDec 光栅化，不将它简化成另画的火焰。
命中特效采用同一严格随机选择适配器，接受已识别的直接/局部变量跳转与停止/删除终点；
嵌套素材存在脚本时拒绝生成。最终导出保留 461 个逻辑帧，精确相同的 RGBA 像素只存储一次，
各帧仍保留自己的注册点偏移，不能因像素复用而丢掉位姿或时长。

每帧保留源帧号、注册点裁切偏移和原始单位尺寸；2 像素对应 1 个 Flash 单位，
动画按 30 个游戏 tick/秒。透明图集带 2 像素外边和帧间隔，行高按 8 对齐，
D3D11 使用线性采样和预乘 alpha。运行时不重新解析矢量或逐实例解码 PNG。

清单绑定 XFL 依赖、SWF、生成器、Java 导出器、FFDec 主包及 classpath JAR、PNG 的 SHA-256，
并记录 Pillow 版本。受摘要保护的源码/清单由 `.gitattributes` 固定 LF。
`--check` 仅需标准库，检查来源/配方/帧序列/PNG 头/矩形/体积和 `local_lights.v1.json`，
不执行 Java，也不代表重新光栅化后的像素比对。
Runtime 另核对目录 schema、SWF/PNG 哈希、尺寸、样式和帧索引；失败则不宣布接管能力。
PNG 上限 4 MiB、纹理每边上限 4096；实际体积与尺寸读取清单和 `--check` 输出。
纹理、Host 像素缓存和 native 上传副本各自占内存，不能把 PNG 压缩大小当作显存大小。

AS2 的落地印章独立按需烘焙小型弹壳位图，不加载整张枪火图集。第一次落稳才短暂
`attachMovie`、`BitmapData.draw`、移除源 MC；以后复用缓存。帧尾队列是有界的多次
`BitmapData.draw`，不承诺 Flash 会合成一个 GPU draw call。

`local_lights.v1.json` 为可编辑的视觉参数，不是导出图集的第二美术源。
更改半径/能量/寿命/颜色或 `maximumResponse` 后运行 `--check` 并重启消费者即可，不需要重编 SWF。
初版不自动给命中火花配置光源；发布输入与检查已进入 `runtime-inputs.v2.json` 的 policy 域和 production policy。

验证入口：`scripts/run-combat-fx-tests.ps1`、Launcher `CombatFxTests` 和
[实际 GPU 夹具](../../launcher/perf/combat-fx/README.md)。候选/人验边界见
[迁移探索及施工记录](../../docs/reports/弹壳与枪火迁移-前期探索-2026-09-26.md)。
