# 子弹原生表现目录

`build.py` 保留普通、加强普通两种原有三角样式，并从现役
`flashswf/arts/原版素材库-子弹.swf` 导出穿刺、次级穿刺、无壳穿刺的飞行外观。
单发与联弹单元的注册点、嵌套矩阵、颜色和滤镜不同，分别占用目录中的样式，不能强行复用。
XFL 仍为唯一美术编辑源；图集和目录是派生物。

```powershell
python -B -X utf8 tools/combat-bullet-visuals/build.py
python -B -X utf8 tools/combat-bullet-visuals/build.py --check
```

完整生成复用战斗特效工具的导出 ID/JDK 定位，使用本目录的 `BulletSpriteExporter.java`、
已安装的 Java/FFDec 和 Python/Pillow；不执行帧脚本，不修改 SWF，不安装工具。只读取零基第 0 帧，保留原来的
渐变、注册点与透明度。`area` 的 Symbol 13 → Symbol 12 链必须是无可见修饰的全透明矩形，
否则拒绝生成。联弹内嵌的次级穿刺不会收到组命中回调，不能将单弹爆炸阶段套给视觉单元。

细长联弹单元没有碰撞 area 撑开外框，直接使用 FFDec `FrameExporter` 的几何边界会裁掉
原有 GlowFilter。专用导出器以明确的外扩画布调用同一 FFDec 渲染器，任何非透明像素触达
画布边缘即拒绝生成；外扩仅改变光栅视口，不修改源符号。生成后再按实际 alpha 裁切并保留偏移。

`bullet_styles.v1.json` 前两个索引保持不变；2–4 是三种单弹，5–7 是对应联弹单元。
无对应消费方的 `ordinaryLinkage` / `gunChainUnitLinkage` 为 `null`。
三角样式使用 `kind: triangle` 和原顶点；精细外观使用 `kind: sprite`、图集矩形、
裁切偏移和源单位尺寸。`bullets-atlas.png` 每两个像素对应一个 Flash 单位，带双线性采样隔离边。
目录绑定 XFL 依赖、源 SWF、生成器、FFDec 与复用导出器的摘要；运行时校验实际 SWF/PNG
摘要、图片尺寸、矩形、比例和映射唯一性后才允许能力接管。

`--check` 只检查配方、闭包、PNG 头/体积和派生元数据，不重绘，也不证明游戏观感。
实际尺寸与体积读取本轮输出，不复制成长期性能结论。GPU 只接管表现，AS2 的碰撞、预算、
命中和生命周期不由图集或视觉单元数量决定。

穿刺默认命中/地图行为由 `PierceBulletLifecycle` 和 `PierceBulletProfile` 统一。
本阶段保留真实 MovieClip 的 `area`、标签和 Flash 帧时钟：次级首次真实命中后的间歇碰撞，
以及真穿刺消失阶段的碰撞窗口仍由原时间轴提供。预算加载、结算段数累计和严格超预算删除
保留现有实现。本阶段不宣称完成穿刺 MC 去除。

定向验证：`scripts/run-pierce-bullet-tests.ps1` 使用真实发布素材的旧/新路径并排对照帧号、
碰撞区域、回调状态和销毁时点；`BulletVisualCatalogTests` 验证纹理、映射与拒绝畸形目录。
CS6 编译与实际 GPU 运行由主控排队，不并行争用同机测试资源。

## 穿刺等价适配核对（2026-09-28）

核对基线为 `28bfcd3f83` 加本轮穿刺适配工作区。真实 CS6 `TestLoader` 已完成本轮
341 项断言，Compiler Errors 为 `0 个错误, 0 个警告`，本轮 suite 为零失败。
其中三种穿刺各经真实 `BulletFactory.createBulletInstance` 创建；十五组原始 SWF 帧脚本与
新 profile 实例并排推进二十帧，比较帧号、`area` 实际矩形、命中钩子状态、预算累计和销毁时点。
此计数是本轮结果，不是未来修改可沿用的固定通过数。

关键轨迹：次级实际命中进入 Flash 第 2 帧，该帧无 `area`；第 3/6/9 帧恢复 `area`，
第 10 帧脚本移除。真穿刺在未触发消失前始终停在第 1 帧；消失序列保留第 3/5/11/15 帧的
不同碰撞矩形，第 17 帧移除。移除发生在连续两次 `onEnterFrame` 采样之间，因此本轮保留
Flash 帧时钟，不在子弹 `onEnterFrame` 内增加一个可能提前销毁已入队实例的计数器。
次级不存在的“消失”标签保持空转，没有顺手修正为新终止规则。

源码与实际轨迹交叉核对如下：

| 边界 | 处理与证据 |
|---|---|
| 默认 hook 是否被 XFL 覆盖 | Factory 在 `attachMovie` 的初始化对象中提供默认函数；原 XFL 第 1 帧仅在相应字段为假值时安装旧函数，因此保留新的函数。原 `已爆炸=false` 与 `stop()` 仍照常执行 |
| 自定义回调 | `prepareInit` 复制已有函数引用，不包裹、不提前调用，不回写发射模板。实际 custom-hit/custom-map 场景各只增加一次原计数，未额外触发爆炸或地图删除 |
| 次级联弹单元 | Factory 只为直接单弹选用 profile；联弹仍走组生命周期，单元挂载路径没有调用本适配器，也没有新增从组向内嵌单弹派发命中的通道。实际单元外层没有单发命中 hook |
| 穿刺预算 | `BulletInitializer` 与 `BulletQueueProcessor` 未改。次级 3、横向模板覆盖 2 仍乘原霰弹值；结算继续累计 `actualScatterUsed`，结算后严格超预算才删除，不新增同目标去重 |
| 图片注册点 | 从实际 SWF 矩阵导出，偏移为“外扩视口最小坐标 / 20 + alpha 裁切像素 / 2”。次级单元相对单弹仍保留 `(+6.75,+0.95)`；其他穿刺也保留各自原注册点 |
| alpha / tint / glow | 原 SWF 的色彩变换和滤镜由 FFDec 应用一次；RGBA 图集不叠加第二份 tint/glow。Host 解码为 BGRA 预乘 alpha，native 采样解回直通颜色后调色并保留图集 alpha 与实例 alpha 的乘积。专用外扩视口消除了细长单元 glow 被几何边界裁切的问题 |

完整光栅化连续两次得到相同目录与 PNG 字节，派生 `--check` 通过。SWE-2 Max 使用冻结的
只读源码包完成独立审计；其建议向联弹单元追加命中派发会改变既有行为，未采用。

`settleHit` 相关用例采用确定性 DamageResult 边界夹具，用来核对 actual-only hook 与记账顺序，
不覆盖完整伤害公式、游戏内敌群或玩家感官验收。真实 GPU、候选执行和标准入口验证由各自证据确认；
本轮穿刺逻辑没有移除 MovieClip/area 壳，也没有把 native 绘制或这些断言升级为完整实战验收。
