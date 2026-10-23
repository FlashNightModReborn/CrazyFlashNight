# CF6 局部摆件校准

地图世界换算仍由 `tools/cf6-prototype/viewport-assembly.py` 执行一次；本工具只改明确实例的原生 XFL 矩阵。地图全局 actorScale 与基础镜头保持 1，墙、地板、天空、地形和建筑开口不套用家具倍率。原始 SVG、子元件画稿与纹理不改。

## 构建

先运行对应源装配器，再运行：

```text
python tools/cf6-prop-layout/calibrate.py --apply
python tools/cf6-prop-layout/calibrate.py --check
python tools/cf6-prop-layout/audit_route.py
python tools/cf6-prop-layout/audit_route.py --check
python tools/cf6-prop-layout/test_calibrate.py
```

源装配器可用 `overlay_outputs(outputs)` 在写盘/比较前校准内存中的输出；键为最终 canonical 文件的绝对 `Path`，值为原始或已经校准的 XML 字节。它不读目标文件、不运行几何测量、不写盘；遇到既不是 pinned 原始内容也不是本轮期望的内容即拒绝。staging 装配以 canonical 路径调用后映回 staging。`baselines/` 仅保存精确认领父容器原始字节，是配方输入，不是独立美术编辑源。更新母版须显式重新测量并更新相应配方，不能从未知内容自动吸收。

`derive_laboratory.py` 根据原作 source depth、1901/1906配对和6项完整矩阵重建实验室配方；原作人像与舱壳的 `[36.4,19.1]` 相对放置必须精确匹配。A15车体、车头与三轮使用同一组接地点。A14叠桶也绕整堆共同脚点缩放，不让上层浮空。

## 数据接口

`generated/instance-layout.json` 是源→完整实例链→现尺寸→目标尺寸→消费者映射。`parentLocalBefore/After` 只用于底图父实例；`nativeWorldPivot` 已包含地图原点还原，`worldPivot/holderWorldXY/sortY` 为最终 CF7 世界坐标。`artMatrixSpace=holder-local` 的 `artMatrix` 已包含唯一地图倍率，且将 `pivotNative` 映到 `[0,0]`；holder 只平移一次，不能再乘 `128/75` 或再叠加世界偏移。配对部件按 `assemblyId` 共用脚点。

`localVisualScale` 是相对现有地图倍率的局部校准因子；通行服务的绝对 `visualScale` 应为 `mapScale * localVisualScale`。带剪切/翻转实例消费完整矩阵，不取轴平均数。工具拒绝父子实例同时独立缩放，避免同件被乘两次。

`generated/route-audit.json` 覆盖现有20张正式背景及教学，列明逐图保留/校准原因与准确独立 CS6 编译目标。`route-review.png` 仅是原输入缩略总览，未用于生产资源。

## 验证边界

`scale-policy.json` 是局部人体/家具/培养舱标尺输入。教学右桌的桌面、桶盖、桶身、台灯四个精确实例绕共同桌脚点去掉房壳1.383与地图128/75倍率。五张海报按共同墙面锚点恢复纸张尺寸；灭火器瓶体、原阴影及挂放投影一起校准，瓶体约60cm、手柄约143cm高。`derive_tutorial.py --check` 校验这十二个明确子实例；墙、柜门、地面与玩家不改，当前配方共169个实例。

`build_unit_scale.py` / `--check` 先验证七个人形链接的原生站姿 XML 身份，再生成 UTF-8 BOM 的 `Cf6BodyScaleRules.as`。敌人模板只在身高换算入口调用；175cm 对应 145.192765px 身体，Wings 按 190cm 换算，其余链接、玩家、完全体克隆兽与大型体型沿用旧规则。重复调用从身高参数重新计算，不累乘。外层比例同时影响碰撞与枪口，真实战斗回归仍必需。

女僵尸、Wings和两类特种兵的初始静态轮廓估值经真实alpha像素测量校准；`scale-policy.json` 自包含原估值、测量比例、实际角色RSL/测试产物/源码/trace身份及误差预算。原XML输入身份、配置身高和目标体高不变。方向函数读写单位自己的 `this.myxscale`，避免同场另一种体型覆盖其镜像基准。

`Cf6BodyScaleRulesTest.runAllTests()` 包含真实 MovieClip 变换的合成矩形验证，不能代替美术。[真实 RSL 独立入口](../cf6-body-scale/README.md)准备七个生产初始化的独立测试单位，按 `generated/body-scale-probe-inputs.json` 的站姿停帧并等待两帧，再调用 `Cf6BodyScaleLiveProbe.measure(units)`。该文件是本轮 SWF 身份快照，执行前重新验证 SHA。夹具临时隐藏具名武器并原样恢复，探针保持只读，按完整man矩阵与遮罩绘制4倍栅格，再以alpha≥128测量身体像素高度；不把遮罩包围盒当可见轮廓。禁止把真实玩家场景用作 fixture。

静态 66 组舱壳/人像恢复为与现役 230cm 克隆兽相称的工业大舱；壳体约 366.28px，初始体态身体约 187.26px。动态 1939 由 `../cf6-scene-completion/pod_scale.py` 分别处理人体和壳碎片：腿部矩阵去除原作从小变大的缩放，壳体倍率 1.8841491959；脚在第 1–7 帧保持舱内位置，第 7–23 帧随 smoothstep 下落至真实克隆兽脚点，第 7 帧开始原完整底座已消失。25 帧总时长、空尾帧和第 24 帧生成事件不变。静态舱与动态第 1 帧保持相同位置，不使用会把脚下移穿入完整底座的早期候选方案。离线 SVG 预览只证明源几何，须真实 CS6 与消费者复验。

尺寸以原生轮廓与完整放置矩阵测量；bitmap 使用声明矩形，`setMask` 使用包围盒交集，报告逐项标明此静态近似，不冒称像素可见面积。175cm裸模145.19px用于人体尺度；持枪/披风外框不作为身高。家具、雕像、油桶、舱体和完整车辆分别校准，不把所有物体统一缩小。

完成静态检查后仍须由根队列用真实 CS6 编译对应独立 XFL，再在游戏消费者核对。本工具只校准比例；普通装饰桶与静态舱保留底图，原作可爆桶及1939活体培养皿的独立伤害、破碎和出生链由[场景交互装配](../cf6-scene-completion/README.md)接入。比例校准不等于碰撞、交互或可绕行交错验收。
## 前后深度的最小提取

`audit_depth.py` 读取现役最终world环境碰撞与章节出生点，按16px四连通网格、12px脚部净空、前后24/40/64px、横向中心/四分位/内缩边缘取样。当前只有A06两尊雕像满足两侧连通；教学床、油桶、培养舱等后侧未证实可达，仅表示此穿行判据未要求深度提取。交互、破坏、触发和生成需求未由此探针评估，不能据此决定保留为静态底图。此探针是前后穿行候选选择依据，不代替真人穿行。

`build_depth_props.py` / `--check` 生成两份独立原生XFL及 `generated/depth-props.fragment.json`。每份包含原始symbol/纹理/bin闭包，实例完整颜色/滤镜属性保留；遇到需要累积祖先颜色/滤镜的情况显式拒绝。`depth-recipe.json` 启用后，`calibrate.py` 和纯字节 `overlay_outputs` 会移除底图同一实例，避免双画。root接入角色 `depth-prop` 的world holder后，资源内已经是脚点局部矩阵，因此绝对visualScale=1、pivot=0，x/y/sortY来自fragment。独立源的发布目标在 `flashswf/backgrounds/cf6/props`，不得直接复制旧SWF。

新增/更新提取时先保证比例报告和reachability输入一致，再执行 `build_depth_props.py`，最后 `calibrate.py --apply/--check`。编译清单包含9背景和2独立摆件；native_xfl.audit识别DOMBitmapItem，通用xfl audit的bitmap-as-symbol误报不当作真实缺引用。
