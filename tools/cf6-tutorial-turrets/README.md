# CF6 教学炮塔（A01）迁移工具链

本目录是 CF6 原作两门自动炮塔迁移 lane 的**事实提取 + 独立解码核对 + 确定性片段/
原生 XFL 源生成**工具链。两门炮塔**不在教学室**（教学关帧58/世界 sprite1499 已核对
无任何炮塔实例），而在 **A01**（主时间轴帧66 标签 a1，世界 sprite1592 首帧）。

## 硬边界

- 提取片段坐标保持 `native-original`（fps=30）；`build-chapter.py` 在装配边界乘 `128/75` 一次，本体与基础镜头保持 1。
- 本目录不编译 SWF/XFL、不开 GUI、不用外部工具生成/重写 SWF；资产编译与地图接线归主控。
- 源码消费者为 `Cf6MapMechanism`、`Cf6TutorialTurretService`、`BulletQueueProcessor` 与章节/schema 生成器；保存、奖励和出口结算仍由现役权威处理。

## 文件

- `scan-turret-facts.js` — SWF 结构扫描（r13）；输出 `evidence/scan-facts-r13.json`。
- `verify-native-decode.py` — **r14 独立位精确解码器**（不依赖 r13 解析器/ffdec）：
  逐位核对 5 个 DefineShape 的填充/edge（consumedExact=true）、PlaceObject3 filter-list、
  StartSound；输出 `evidence/verify-decode-r14.json`。
- `build-manifest.py` — 确定性重建素材源稿 `manifest.json`（schema v2，13 个真实闭包
  tag + r14 修正记录）与 `raw-tags/` 字节；`--check` 只读校验。
- `build-turret-xfl.py` — 确定性原生 XFL 构建：`--extract`（SWF→bitmaps/ +
  `generated/geometry-r14.json`）、`--jsfl`（生成 `generated/import-assets.jsfl`
  CS6 原生导入脚本）、`--assemble`（写 LIBRARY 符号 XML + splice DOMDocument +
  PublishSettings）、`--check`（装配树校验）。不运行 CS6、不写 SWF。
- `build-fragment.py` — 确定性生成 `tutorial-turrets.fragment.json`；`--check` 校验字节一致。
- `test-fragment.py` — 片段测试（schema/坐标/r14 解码事实/闭包字节 SHA/再生成一致）。
- `test-turret-xfl.py` — 解码、符号 XML、模拟装配与缺媒体/包络/滤镜/声音帧漂移拒绝测试；子进程固定 UTF-8，避免本地代码页改变错误分类。
- `extract-native-tags.js` — r13 提取器（**已被 build-manifest.py 取代**：其
  readMatrixEnd 位读取错误产生 1536 幻影引用，保留仅作历史证据，不要再运行）。
- `tutorial-turrets.fragment.json` — 交付片段（schema `cf6-tutorial-turrets.v1`）。
- `evidence/` — 反编译 dump、扫描事实 JSON、r14 独立解码证据。

## 运行

```bash
python -X utf8 -B tools/cf6-tutorial-turrets/verify-native-decode.py <swf> -o tools/cf6-tutorial-turrets/evidence/verify-decode-r14.json
python -X utf8 -B tools/cf6-tutorial-turrets/build-manifest.py --check
python -X utf8 -B tools/cf6-tutorial-turrets/build-fragment.py --check
python -X utf8 -B tools/cf6-tutorial-turrets/test-fragment.py
python -X utf8 -B tools/cf6-tutorial-turrets/test-turret-xfl.py
```

主控装配流水线（CS6 导入 → assemble → check → 编译）见
`flashswf/arts/new/Codex素材源稿/CF6教学炮塔/装配说明.md`。

原生导入脚本使用 UTF-8 BOM，保留直接书写的中文路径。CS6 对无 BOM 脚本可能按系统代码页解释，
使中文 URI 失真；生成器先创建 XFL 父目录和库文件夹，再通过明确的叶名称与目标文件夹导入资源。
时间轴取 `timeline.layers[timeline.currentLayer].frames`，不使用不存在的 `timeline.frames`。

## 原作核心事实（证据见 evidence/ 与 fragment）

- sprite1591 全 SWF 仅放置两次，均在 A01：depth152@(133.8,202.4)、depth160@(249.8,430.9)，
  单位矩阵朝右，无实例名/clipEvents/linkage。
- 18 帧循环；帧12 子件"枪口位置2"(359, 局部 105.25,-12.55) onClipEvent(load) 调
  `_root.汽车_子弹区域shoot("无",1,15,"无","普通可见子弹",10,20,"无声火花",...)` → 0.6s/发。
- 帧1包含 `swapDepths(this._y*100)`、增援生成与条件 `stop()`；增援由本版 WaveSpawner 承接。机身实例挂一个 ColorMatrixFilter，20 float 原值见 fragment。
- 帧12 StartSound → DefineSound 1169，包络 11022/9533。规范 MP3 帧载荷为 **2392B**，`fire-sound-1169.import.mp3` 与独立 FFDec 导出逐字节相同，并通过 FFmpeg 无声解码。旧 `fire-sound-1169.mp3` 的 2396B 原件保留，其多出的 4B 是误保留的 SWF 字段；JSFL 只导入 `.import.mp3`。音量、时钟、CS6 重发布和听感仍待实际验证。
- 机身 1589 位图填充引用 1588 + 927；枪口焰 503/504/505 真实渲染位图为 502，
  其 FillStyleArray 中的 0xFFFF 为死条目（无 edge 选用，按原语义不渲染不替代）。
- 子弹入友方池，不伤主角；仅 `aw-僵尸-可被炮台打`(sprite630) 自检友方池扣血(hp200，20发死)，
  死亡递增 `_root.电梯死亡敌人计数`；A01 出口(1587)需杀死数20→s2。
- 不可控制、无输入、无进入/离开、无教学触发、无回收（随房间卸载）。
- 子弹(普通可见子弹356)与效果(无声火花1108)**不提取**——CF7 已有等价 linkage
  "普通子弹"、"无声火花"（data/items/asset_source_map.xml）。

## CF7 运行时服务

`scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretService.as`（+Test）：
`beginRoom(world, identity, mapId, spec)` / `teardown()`；仅 A01；守卫同 Cf6MapMechanism；
spec.assetUrl 指定独立展示 SWF（默认 `flashswf/backgrounds/cf6/CF6_A01_Turret.swf`），
gameworld 直属 wrapper 在创建时保存普通 Object 归属凭据；每门炮塔有独立 loader/listener，
仅向 wrapper 的专用 payload 子剪辑载入资源。回调检查世界身份、wrapper 凭据、目标父级与一次性票据，
清理先捕获归属，再失效票据、摘监听器、卸载自有 payload 并删除自有 wrapper。
带凭据的收养实例保留原剪辑；无凭据或被替换的实例及其回调保持原状。

服务统一驱动 18 帧节拍，暂停时冻结，并在进入声音帧前检查发射能力。资源元件首帧自动停止，
由服务接管。`BulletQueueProcessor.targetFilterEnabled` 绑定真实主命中与 injectHit 守卫；
服务规格只接受普通子弹。源 `zombie_turret`（630）才取得目标标记，共用兵种461的普通僵尸不加标记。
CF7 机关发射者采用等级35、命中率100000、伤害加成0及自有 dispatcher，避免未定义数值；
`shootZ` 使用实际世界地面行，不能把离地高度0传给地面行碰撞合同。原作威力10、速度20保持不变。

CF7 兼容层采用原作枪口焰锚点 `(112.45,-70.5)` 作为实际发弹点，经展示元件的真实变换转换到世界坐标；
原作标记 `(105.25,-12.55)` 及其提取记录保持不变。开火时仅在当前世界中选择枪口前方、900px 世界 XZ
距离内的活敌方 630 标记目标，重新核对世界普通对象身份、实例凭据与目标资格；速度 X/Y 和 ZY 比例交给
现役 `LinearBulletMovement`，沿用战术目镜的普通子弹运动合同。无合法目标保持原节拍与散射，地图碰撞、
伤害及逐弹标记过滤均保留；这是 CF7 适配，不是原作已有自瞄的断言。

2026-10-22 现场修复：曲线控制点和端点按 SWF 相对增量累计，补独立原作 SVG 坐标基线；
DOMSymbolItem.name、libraryItemName 与 Include 文件名保持一致。后者不一致曾使 CS6 编出重复的机身、
标记与枪口焰，通用 XML 引用审核无法单独发现。43 项生成器检查通过；真实 CS6 Compiler 0/0，
实际 SWF 的唯一 linkage、18 帧及各一份机身/标记/枪口焰已复核，回执在
`tmp/cf6-roguelike-20261021/validation/turret-publish-r3/`，旧失败产物保留。

`scripts/run-cf6-tutorial-turret-tests.ps1` 为 120 项服务回归；整合入口
`scripts/run-cf6-field-repair-tests.ps1` 已取得 679/679 真实 AVM1、fresh Compiler 0/0、retry 0，
其中炮塔 120 项覆盖真实 MovieClip 变换、上下行运动、失效目标、暂停、同路径身份和下一帧卸载。
变换夹具使用独立父路径；专门同路径测试仍保留。真实运动终点按每步一 twip 的坐标量化上界核对，
不改变生产弹道或共享断言精度。完整失败与通过记录在 `validation/field-repair-avm1-r1` 至 `r3`。
以上不代签实际房间内的命中、枪声听感或玩家验收。
