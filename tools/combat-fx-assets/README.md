# 弹壳与枪火资源派生

`build.py` 从三个明确来源的 XFL 行为定义和对应已发布 SWF
生成 `data/combat_visuals/effects.v1.json`、`effects-atlas.png` 及
`sounds/export/特效/cfnfx-stock-<soundId>.wav`：原版素材库-子弹、
`new/雾人整合特效` 和 `new/fs配置素材`。来源映射与有限行为适配归 `source_recipes.py`。
编辑源仍是各自原 XFL，
不要手改图集、裁切偏移或帧序列。没有修改美术时不需要重编素材库 SWF。

```powershell
python -B -X utf8 tools/combat-fx-assets/build.py
python -B -X utf8 tools/combat-fx-assets/build.py --check
python -B -X utf8 -m unittest discover -s tools/combat-fx-assets -p test_source_recipes.py
```

依赖 Python/Pillow、现有 `tools/ffdec` 和 Java JDK。优先使用 PATH/JAVA_HOME 中的
`java`、`javac`，否则查找已安装 Adobe Animate 的 JRE/JDK；工具不会下载安装。
Java 导出器只读 SWF，显式选择零基帧/声音 ID，不执行 ActionScript、不播放音频，也不修改发布产物。

范围由生成器配方固定。原有 18 个弹壳、10 个枪火和 7 个命中特效保留索引 0–34，
随后追加冰汽、烈焰火花、能量火花、空手攻击火花、铁枪能量弹枪火、普通飙血及普通飞血。
枪火的 `removeMovieClip` 转为有界序列终点；通用 `枪火` 的 `random(3)` 转为
创建时选择 a0/a1/a2 的三个预设。源中 a0/a2 的选中画面为空，当前如实保留；
Y=0 的移除条件保留为 `skipOriginYZero`。新增脚本或弹壳动画会使生成失败，必须先审查适配。
Barrett 的嵌套图形/渐变由 FFDec 光栅化，不将它简化成另画的火焰。
命中特效采用同一严格随机选择适配器，接受已识别的直接/局部变量跳转与停止/删除终点；
未适配的嵌套脚本拒绝生成。原有 461 个逻辑帧继续使用原光栅化路径；
精确相同的 RGBA 像素只存储一次，
各帧仍保留自己的注册点偏移，不能因像素复用而丢掉位姿或时长。

`sourceLibraries` 是三个受控来源的 SWF/库目录映射，各样式的 `sourceKey/sourceSymbol`
绑定实际导出源，`sources` 包括全部 XFL 依赖、原版素材库的声音媒体表 `DOMDocument.xml`
和三个 SWF 的 SHA-256。
Java 每个来源独立读取 SWF；血滴从外层命名实例“飞血”找到未导出的子元件，
只导出其五个静态变体，外层运动/随机脚本也进入来源闭包并要求与已审核适配一致。
`kind:blood` 的运动、终止及落地交接由配套消费者处理，Java 不运行其脚本。

`variantSounds` 与分支一一对应，`soundAtBirth:true` 表示必须在出生相位按同一分支播放，
不以像素预算是否接收精灵为准，也不等待 Host 绘制回传。当前只有火花、击中金属、拼刀火花、
战术巴雷特击中特效、屎花和普通飙血有此标志。
前五种包含 20 个 XFL `DOMFrame.soundName` 事件声音；全部发生在变体首帧，
Barrett 的公共 frame 0 声音适用于其全部分支。导出器核对已发布 SWF 的 `StartSound`、
声音编号、单次播放及包络，拒绝未审查的流声音、延迟事件或嵌套声音，不能只扫描 ActionScript。

`CombatSoundExporter.java` 用现有 FFDec 的 WAV 解码路径从真实 `DefineSound` 导出 PCM。
该路径按原始 MP3 `SeekSamples` 裁去编码延迟，再按发布的 `soundSampleCount` 裁去编码尾部；
不直接剥出会遗失起始裁剪语义的 MP3，也不补写源 SWF。固定命名的 20 个 WAV 通过现有
“特效” SFX 包自动发现；七个没有 AS linkage 的声音同样按真实声音 ID 导出。
根 `soundAssets` 绑定 `id/path/sha256/bytes/sourceKey/sourceSoundId`，并记录
`sourceSeekSamples/sampleRate/sampleFrames/channels/pcmBits`。
每声上限 256 KiB、总量上限 2 MiB；`--check` 校验字节摘要、PCM 格式/长度、来源 ID、
精确派生文件集合和每个 cue 的实际 SFX 完整文件名。
稀疏发布树可只物化本次实际使用的“特效”包；与 AudioCoordinator 一致，未存在的
“武器”或“人物”包目录会跳过。实际引用的 27 个 cue 及 20 个派生 WAV 仍须全部存在并通过校验。

普通飙血保留七个分支帧序列和出生声音；源脚本仍是 `blood1.wav` 至 `blood7.wav`。
其中 1/3/4 的实际 SFX 文件扩展名为 `.mp3`，资源配方显式规范为
`blood1.mp3,blood2.wav,blood3.mp3,blood4.mp3,blood5.wav,blood6.wav,blood7.wav`，
不依赖不存在的扩展名别名。现有七个音频文件保留原字节。
源时间轴的删除帧不计作额外可见 tick；冰汽/烈焰/能量分别为 7/9/9 个可见帧，
铁枪三个分支为 5/3/4 个可见帧。

空手采用专用 `nested-spin` 适配：只在内存渲染视图中把子实例平移归零，
保留固定等比缩放和 SWF 原 GlowFilter，导出外层删除前的三个帧。
`sourceNestedTransform` 记录原矩阵；固定缩放已烘入纹理，运行时
`nestedTransform=[1,0,0,1,-1.2,-1.7]` 只应用子平移与随机旋转。
`unitScaleXOnly` 限定首批仅接管父 X 缩放绝对值为 100 的调用，其他倍率保持原路径，
避免把非等比父缩放误当成可交换的旋转。该内存适配不保存或改写 SWF。
冰汽与空手使用扩展 32 源像素的滤镜视口，非透明外沿使生成失败，不静默裁切滤镜。

每帧保留源帧号、注册点裁切偏移和原始单位尺寸；2 像素对应 1 个 Flash 单位，
动画按 30 个游戏 tick/秒。透明图集带 2 像素外边和帧间隔，行高按 8 对齐，
D3D11 使用线性采样和预乘 alpha。运行时不重新解析矢量或逐实例解码 PNG。

清单绑定 XFL 依赖、SWF、生成器/配方、Java 导出器、FFDec 主包及 classpath JAR、PNG 的 SHA-256，
并记录 Pillow 版本。受摘要保护的源码/清单由 `.gitattributes` 固定 LF。
`--check` 仅需标准库，检查来源/配方/帧序列/PNG 头/矩形/体积、声音与 `local_lights.v1.json`，
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
