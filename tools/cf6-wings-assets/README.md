# Wings 原生素材与战斗接入

**文档角色**：Wings 的源文件归属、确定性装配、验证入口和本轮证据边界。
**代码起点**：`8a0e79a1b3b09e3c7320f88fbc0b96dc804479d6`；本轮新增工作尚未提交。

Wings 使用兵种 `464`，按用户指定的阶段 `7`、档次 `8` 从怪物公式生成属性。显示名为 `Wings`，linkage 为 `敌人-CF6Wings`，写入共同属性表 [CF6重制敌人.xml](../../data/enemy_properties/CF6重制敌人.xml)。原版 `兵种373 / 敌人-闪6特工` 保持独立。

## 编辑源与运行链

- 原始交付为 `cf6-wings-redraw-r3`；十二个身体／枪刃 SVG、动作数据和审阅元数据保存在 [CF6Wings-R3](../../flashswf/arts/new/Codex素材源稿/CF6Wings-R3/)。`archive-origin.json` 记录原 ZIP 与逐文件 SHA-256；原 ZIP 未改写。
- R3 是材质重绘，提供的原 CF6 动作时间轴没有新增动画优化。CF7 已增强的行走、跑步、连斩、后空翻、射击和受击框架来自 `素材库-诺亚新敌人/LIBRARY/闪6特工`，不覆盖该供体。
- 本地唯一原生编辑源为 [CodexWings素材](../../flashswf/arts/new/CodexWings素材/)。[build.py](build.py) 装配原生 Shape／Graphic／MovieClip；[native-manifest.json](native-manifest.json) 绑定输入、供体、六十个库元件及四个工程文件。未匹配已有 manifest 的人工编辑会阻止覆盖。
- 发布目标为 `CodexWings素材.swf`，只导出单位与独立库锚点。`things-new.fla` 第四帧引入锚点，`things-new.swf` 与 `asset_source_map.xml` 承接运行加载；不需要为该私有帧脚本重编 `asLoader.swf`。

[vector.py](vector.py) 局部扩展已有矢量转换器，支持 R3 使用的 `objectBoundingBox` 线性／径向渐变、SVG 默认圆心半径、仿射椭圆和描边渐变；不改变其他单位的生成器。`test_vector.py` 对独立矩阵、默认值、透明度及不支持的偏心焦点拒绝行为作回归，再转换全部十二件真实输入。身体和双枪刃均为原生矢量，本库不嵌位图；这不代表原始交付整个素材集没有位图。

## 动作与私有 AI

站立保留 R3 的十五帧。CF7 的二十六帧行走、二十四帧跑步、四十九帧推进连斩、八十三帧技能组合及受击／倒地接入继续使用原有骨架与伤害时点。技能保留四发射击，以及后空翻六段近战、五发不同角度射击和后续斩击／射击；普通连斩保留十四段近战与六次推进。近战仍以空手攻击力结算、击倒率 `2`、不硬直；射击仍为穿刺子弹、速度 `25`、击倒率 `10`。没有追加蛮蛮的击溃机制或新的全程霸体。

[WingsAI.as](WingsAI.as) 是单位首帧的私有脚本，不扩展引擎类权威：

- 根据水平距离、纵深、目标高度、动作冷却选择连斩、翻转、斩击或射击；远处接近，纵深不齐时先对齐。
- 每次动作持有自己的 token；受击换状态、死亡、换动作及暂停后，旧动作不能继续出伤害或位移。动画完成只由当前 owner 收尾。
- 后空翻接招重新核对目标存活、纵深和距离；不满足时结束动作。
- 枪口来自真实枪刃元件的嵌套矩阵。静态翻转姿势首帧尚未执行子层脚本时，复用同一单帧枪刃的已观测局部注册点，再应用当前实例矩阵；不缓存旧实例或世界坐标。找不到有效枪口时不发弹并留下计数。
- `baseline` 仅在 `_arenaCalibrationUnit === true` 的实验单位上允许；普通单位固定 `enhanced`。对照保留供体传感器／通用 AI，材质、动作、面板和伤害时点与候选相同。

死亡使用 CF6 的完整一百三十二帧，分支起点为 `a0=1 / a1=59 / a2=96`。以髋部对齐 CF7 站姿坐标，整个死亡动作应用同一父层矩阵；不逐个缩放身体部件。左右朝向均以同一父坐标系检查宽高、落点和水平位置。原 CF6 血液辅助素材不重复导入，死亡结算和血液入口仍归 CF7。

接地影子由根单位直接持有 `wingsShadow`，覆盖初始化到死亡的全部状态，在“消失”帧结束。原供体只覆盖前七十九帧，并把直接子层误按两级父层登记，初次接入未纠正这一点。当前副本保留原椭圆材质和尺寸，以单位的 `Z轴坐标` 投影地面，抵消腾空与根旋转，并动态跟随阴影开关；不把这件根层影子交给假定 `233.05` 基线的玩家飞行脚本。只在数值变化时写显示属性。

## 生成与验证

```powershell
python -X utf8 -B tools/cf6-wings-assets/test_vector.py
python -X utf8 -B tools/cf6-wings-assets/build.py --check
python -X utf8 -B tools/cf6-wings-assets/balance.py
python -X utf8 -B tools/cf6-wings-assets/verify.py
```

确实修改编辑源／配方后，先执行受保护生成：

```powershell
python -X utf8 -B tools/cf6-wings-assets/build.py --import-approved
python -X utf8 -B tools/cf6-wings-assets/balance.py --write
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/arts/new/CodexWings素材/CodexWings素材.xfl" -PublishOnly -VerifySwf "flashswf/arts/new/CodexWings素材.swf" -TimeoutSeconds 300
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/arts/things-new.fla" -PublishOnly -VerifySwf "flashswf/arts/things-new.swf" -TimeoutSeconds 300
python tools/linkage_scanner/scan_linkage.py --xml-only
node tools/derive-arena-unit-catalog.js
node tools/derive-arena-unit-catalog.js --check
```

原生素材必须由真实 CS6 编译，要求本轮目标 SWF 刷新与 Compiler `0/0`。`verify.py` 另核对独立库 export、共享库 import、FLA 锚点、零位图、单位登记、公式及 AS2 单一权威。只改属性 XML 不要求重编 SWF。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run-cf6-wings-asset-tests.ps1
powershell -ExecutionPolicy Bypass -File scripts/run-cf6-wings-asset-tests.ps1 -Capture
powershell -ExecutionPolicy Bypass -File scripts/run-cf6-wings-asset-tests.ps1 -ShadowCapture
python tools/cf6-wings-assets/decode-native-capture.py <本轮完整trace> <新的图像目录>
python tools/cf6-wings-assets/decode-native-capture.py <影子专项trace> <新的影子图像目录> --shadows-only
```

三十二个实际时间轴用例覆盖左右朝向的连斩、射击、斩击、后空翻与两种接招、受击、倒地、三种死亡和中断。检查每个伤害时点、枪口镜像及首次静态姿势装入，不把模拟子弹接收器当作真实伤害证明。另检查十四种状态的左右影子、开关重启，以及三十二个动作运行中的连续影子和腾空／镜像／旋转／缩放后的接地。

身体八图固定 `2×` 比例，带动作父层矩阵；影子整单位图按原生比例绘制，右下角单元另施加 `1.6×`、镜像、旋转和腾空压力条件，保留地面线并隐藏测试名称占位。黄色条为夹具内的旧血条，不是游戏界面验收。禁止逐姿态自动适配画布。`-Capture` 输出九图，`-ShadowCapture` 只输出整单位影子图，两者默认等待 `600` 秒；超时、迟到完成和恢复记录分别保留。

## 隔离实战

[arena-plan.js](arena-plan.js) 接受 JSON 配置，必须显式提供新 `experimentId`、`mode`、绝对 `projectRoot`、`candidateRoot` 和只读测试 `seedPath`。运行根应为本任务独占 Git 工作树，候选先通过正常开发构建与身份验证。Worker 运行期间冻结数据与 SWF。

`spawnDistance` 默认 `650`，允许 `360..1000`，遵循斗兽 manifest 的最小间距。本轮另用 `360` 的新计划缩短开场距离；更小间距被 schema 拒绝，不改规则绕过。贴身逐帧交锋仍需真人对战复核。改变开场条件必须使用新 experimentId，不改写已冻结 manifest。

- `pilot`：30 级同 Wings 面板、不同 AI 的换边对照，以及与原版闪6特工换边比较。
- `ai`：指定 `levels` 的同 Wings AI 换边对照；双方实际 `startMaxHp` 必须相等。
- `integration`：指定等级与原版特工比较，另有双方各一名 Wings 加一名原版特工的纵深错位混战。

```powershell
node tools/cf6-wings-assets/arena-plan.js <explicit-config.json>
node tools/arena-calibration/run-worker-experiment.js --plan <experiment-plan.json>
python -X utf8 -B tools/cf6-wings-assets/verify.py --runtime-root <本任务资源工作树>
```

计划绑定 Wings SWF、AI 与属性表 SHA-256；协调器绑定实际候选 identity／closure、主 SWF、asLoader 与资源闭包，保护主工作区及 Worker 存档和真实 SharedObjects。每组结束核对独占进程回收和非目标存档；超时保留为超时，不重抽胜负。原版特工比较包含阶段／档次与素材差异，不能用于声称纯 AI 增益。小样本胜率不构成强度认证。

本轮证据集中于 [evidence/20261015](evidence/20261015/)；原始失败、迟到截图与私有运行材料另原样保存在本机 `tmp/cf6-wings-20261015`。动作测试、候选实战、人类画面／对战手感和正式 runtime 部署分别陈述；机器测试不代替人类验收。

2026-10-15 初次接入的 [动作与装配记录](evidence/20261015/summary.json) 为真实 CS6 三十二个时间轴用例、二百一十六项断言全部通过，八张身体截图齐全；它没有检查根层影子，不能据此称影子完整。[实战记录](evidence/20261015/combat-summary.json) 包含十六场自然结束：八场同面板 AI 换边、六场原版特工比较和两场混战；四个隔离实验全部通过身份、资源、进程回收和存档保护核验。候选一侧十六场均胜，较短间距的同面板场剩余约 79%～89% 血量，混战最低剩余约 7%。远程先手较强，不能把这一小样本写成玩家难度或整体平衡已验收。影子修复保留独立前后证据，旧实战仍绑定修复前的 SWF，不改写为新版实测。

[影子修复记录](evidence/20261015-shadow/summary.json) 保留旧二进制上 `224 passed / 165 failed` 的复现及新版 `389 passed / 0 failed` 的完整 CS6 运行。新版只改变根层影子覆盖和影子自身脚本两个元件，战斗 AI 源码及属性不变；附完整单位截图，避免再次因只截 `man` 而漏检根层表现。
