# 两犬 V6 原生装配

制式军警犬和盗贼撕咬犬使用美术机交付的 V6 矢量分件，装入现有 Codex 素材库。军警犬尾巴延长为连续下垂轮廓；两犬口腔按侧面结构分为后方颊壁、上腭、口底和收回的舌头，前部保留张口空隙，覆盖站立、跑动、撕咬、受击、倒地和死亡起始姿势。

| 单位 | unitId | AS2 linkage |
|---|---|---|
| 制式军警犬 | 475 | `敌人-制式军警犬` |
| 盗贼撕咬犬 | 476 | `敌人-盗贼撕咬犬` |

两项单位配置均复制 `units.json` 的原野狗（13），敌人属性逐项复制 `原版敌人 2011-2012.xml` 的 `敌人-僵尸1-狗`，只改显示名、链接与新 ID。等级 5、随机身高、血量、攻击、防御、速度、经验、抗性、重量、韧性及阶段标识均继承；原犬、宠物和召唤引用保留。没有增加关卡投放或调整平衡。

## 源与装配

- 唯一原生编辑源：`flashswf/arts/new/Codex专用素材/`，命名空间 `Codex/两犬/`，合计 98 个独立元件。
- 冻结的 V6 画稿依据：`flashswf/arts/new/Codex素材源稿/两犬-V6/`，保存 76 个原交付运行 SVG、历史几何合同与 ZIP 哈希。
- 首次收尾输入：`refinements/military-tail.svg` 与 `build.py` 的双颌口腔生成；后续原生美术修改以 XFL 为准。
- 每犬替换 13 个正常分件、12 个带犬种特征的死亡碎块，原有纯血迹保留。死亡 a2 的原始空体阶段保留，不补造尸体或修改清理回调。
- 所有继承 AS2 和动作/攻击点矩阵均保留；只增加视觉层。导入器检测既有原生编辑，拒绝覆盖与上次导入不一致的源。
- 口腔修正只更新已有 14 个动作元件的口腔视觉层、86 个关键姿势，不覆盖其他原生修改。`refine-mouth.py --apply` 执行修正，普通调用检查口腔层是否与本轮结构一致。原 `native-manifest.json` 保留初次导入身份，不冒充最新原生编辑哈希。

```powershell
python -X utf8 tools/two-dogs-assets/build.py --import-approved
python -X utf8 tools/two-dogs-assets/build.py
python -X utf8 tools/two-dogs-assets/refine-mouth.py
python -X utf8 tools/two-dogs-assets/verify.py
python -X utf8 scripts/tools/xfl/audit.py flashswf/arts/new/Codex专用素材
python -X utf8 tools/two-dogs-assets/update-source-map.py
python -X utf8 tools/two-dogs-assets/update-source-map.py --check
```

`verify.py` 比较 48 个继承时间轴、106 段原 AS2 脚本和全部配置字段。通用 XFL audit 在本基线将前治安官两项已声明的 DOMBitmapItem 引用报作 missing；新增两犬没有位图与失效引用。不得为此修改共享的前治安官资源。

资产表更新复用通用扫描器与输出器，重扫改动所属的 Codex 库，并逐项验证其他映射不变。需要刷新其他库时使用全量入口 `python -X utf8 tools/linkage_scanner/scan_linkage.py --xml-only`。

原生发布使用 `scripts/compile_test.ps1` 的显式目标，分别发布 `Codex专用素材.xfl` 与 `things-new.fla`，核对新鲜 0/0、对应 SWF 刷新和导出读取。无需重编 main 或 asLoader。

```powershell
python -X utf8 tools/two-dogs-assets/readback.py
python -X utf8 tools/two-dogs-assets/build-test-host.py --check
powershell -File scripts/run-two-dogs-asset-tests.ps1
```

## 原生专项的边界

`TwoDogsNativeHost` 用显式共享导入，将原犬和两犬放入同一 AVM1 字典；并列 `MovieClipLoader.loadClip` 不提供这个作用域，不能用来断言共享库装配失败。

专项直接运行已发布资源，比较原犬与两犬的左右朝向、3 次原生攻击发射的帧/位置/参数、三个死亡分支及终止回调，并导出 18 张 Flash BitmapData 关键帧，覆盖两犬全部七类动作时间轴，含张口与咬合的口部特写。原生像素分别检查前部开口透明、后方颊壁不透明、舌面可见和原死亡空体阶段，不再把整块三角形不透明作为正确标准。初始化、移动与子弹接收器为内存夹具，结果只证明原生素材与继承行为，不代替真实游戏 AI、物理战斗、标准入口或真人观感验收。原 XFL 第 8 帧仅移动第 7 帧的现有判定实例，不会再次触发 onClipEvent(load)；实际发射为第 7、13、16 帧，由原犬与两犬的 SWF 读回和原生对照共同验证。专项通过状态以本轮新鲜回执为准，单有此源文件不代表已经通过。

图像导出逐图重置颜色缓存，并将无损 RLE 行合并为不超过 12,000 字符的日志批次。为控制 CS6 日志成本，14 张全身/死亡图读回为 180×140，4 张口部特写为 240×186；原矢量资产的精度不变。可见面积阈值按读回像素面积缩放，口腔采样放在两犬的张口特写第 4 帧；解码仍要求完整行数和完整 18 帧。高清 XFL 源稿预览与这些原生像素证据分别标识。

`things-new.swf` 保持已有共享锚点。`readback.py` 检查实际导入 URL、新增两个 121 帧单位导出及原 96 项导出完整性。正式 runtime 发布、提交与推送需另行授权。

## 验证记录

首次装配的 [历史记录](evidence/20261021-native.json) 为 277 项检查、32 张实际 Flash 帧；其中整口不透明的旧美术判据已经弃用，不能用这份历史记录验收当前口腔。

本次口腔结构修正的运行资源身份、实际通过数、18 帧导出、trace 哈希及夹具边界见 [口腔修正原生记录](evidence/20261021-oral.json)。两犬攻击仍在第 7、13、16 帧发射，左右位置、判定参数及三个死亡回调需与原犬对照。该专项不代替标准游戏入口、真实 AI/物理战斗或真人观感验收。
