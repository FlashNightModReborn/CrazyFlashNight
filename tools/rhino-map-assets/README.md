# 犀牛 R09 静态地图摆件

三处地图共用原生矢量分件：两个基地各三辆后景坦克，防御地带首图一辆抬炮坦克。采用固定车号、单帧 Graphic 和既有背景烘焙，没有 AS3 控制器、轮履循环、开炮演出或新增运行时类。具体摆放参数由 [placements.json](placements.json) 维护。

## 编辑真源与消费者

- 静态分件唯一编辑源：`flashswf/levels/地图-军阀基地/LIBRARY/Codex/犀牛R09/`，在该地图 XFL 的库面板内编辑。平射和 15°端点保留独立原生分件，外层以近侧履带接地点为原点。
- `Parts/turret-tactical-mark` 保留原始 27 号及军阀圆徽；22/23/25/26/28/29 沿用其原生笔画生成，不依赖系统字体。右向包装反射编号与徽记，外层整车镜像后仍可正读。
- 带车号的炮塔、总成、摆件和编号变体由工具派生；在平射/抬炮基础分件上改稿，再同步，避免三份地图单独漂移。
- 前线第三图 `flashswf/backgrounds/gk22_3_BG/` 与防御地带第一图 `flashswf/backgrounds/防御地带高地/` 仅内嵌各自需要的静态闭包。
- 实际消费者是三张现役地图 SWF。没有增加独立运行时素材库、全局 linkage 或 things-new 挂载；地图本地 Graphic 不需要主文件或 asLoader 重编。
- 外部交付来源和原生元件哈希见 [来源.json](../../flashswf/arts/new/Codex素材源稿/犀牛坦克R09/来源.json)。原始 Animate/AS3 动画包不作为游戏依赖，也不能覆盖接入后的静态真源。

## 比例与坐标

175 cm 男模当前根空间为 82.967294567 px/m；坦克车体原始宽 1293.8 px，含炮管宽 1548.25 px。45% 等比缩放对应约 7.02 m 车体、8.40 m 含炮全长。此处使用人物根空间，不使用武器/肢体内部的 300/350 px/m。

两个基地采用 24%–27% 的后景显示倍率（相对同平面 45% 基准约 0.53–0.60），RGB 乘数0.86使背景车辆略暗。物理体量基准不变；景深缩小与真实帐篷遮挡共同降低视觉权重。摆件图层放在全部帐篷/物资图层之后、原有地面底图之前，不靠把前景大车强行挤到帐篷上。

| 地点 | 车号 | 地面世界坐标 | 姿态 |
|---|---:|---|---|
| 外交军阀基地帐篷后 | 25、26、27 | (615,190)、(1170,175)、(1780,185) | 左向平射，前排帐篷遮挡 |
| 军阀前线基地第三张战斗图帐篷后 | 22、23、28 | (650,175)、(1060,165)、(1740,175) | 左向平射，前排帐篷遮挡 |
| 防御地带第一图原牵引炮位置 | 29 | (850, 320) | 右向，主炮相对车体抬升15°，整车随坡度旋转-4° |

外交场景背景实例有 (-25,-80) 偏移；前线背景继承 `wuxianguotu_1` 的 (937.7,245.1) 偏移；防御地带配置 `Alignment=true`，背景按世界原点对齐。工具保存局部与世界坐标，不能把截图像素直接写成地图坐标。

所有坦克都在可行走区域后方；不增加坦克碰撞区，不改变原有入口或通道。

## 同步与检查

依赖仓库使用的 Python 与 `lxml`。命令在仓库根运行：

```powershell
chcp.com 65001 | Out-Null
python -X utf8 tools/rhino-map-assets/build.py
python -X utf8 tools/rhino-map-assets/build.py --check
```

默认命令同步派生分件和摆放；只读检查核对 Include、分件引用、几何一致性、七个互异车号、摆放矩阵、后景层次/色调、火炮替换以及所有坦克元件均单帧 Graphic / 无脚本 / 无位图实例。仅清理工具拥有的 `Codex/犀牛R09/` 中退出目标闭包的派生 XML，不清理其他库项。

首次外部导入使用 `--import-xfl <完整Rhino-R09-XFL目录>`；它会重建静态真源，因此不是日常同步命令。没有自动双向同步，已有原生手改后不要重新导入覆盖。

三张 XFL 依次跑 `scripts/tools/xfl/` 的 audit / rename_a_class / fix_includes；无需改名或修引用时用 `--dry-run`。然后使用正式 CS6 入口逐个发布：

2026-09-09 的全仓 linkage scanner 已运行；它因 FLA→XFL 原生规范化重新识别了前线旧背景的服装导出。与施工前 SWF 比较，三张图的导出名称集合完全不变（37/0/1），犀牛没有新增 linkage。因此保留原全局资产映射，不把旧服装的重复导出重分类混入本次摆件改动；完整扫描结果留作本轮临时证据。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/levels/地图-军阀基地/地图-军阀基地.xfl" -PublishOnly -VerifySwf "flashswf/levels/地图-军阀基地.swf" -TimeoutSeconds 180
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/backgrounds/gk22_3_BG/gk22_3_BG.xfl" -PublishOnly -VerifySwf "flashswf/backgrounds/gk22_3_BG.swf" -TimeoutSeconds 180
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/backgrounds/防御地带高地/防御地带高地.xfl" -PublishOnly -VerifySwf "flashswf/backgrounds/防御地带高地.swf" -TimeoutSeconds 180
```

XFL 的发布路径按 CS6 项目规则指向其目录外同名 SWF。每张都需要新鲜 Compiler Errors `0/0` 与目标 SWF 刷新；publish-only 不产生游戏行为 trace。检查原生整图、编号正读、履带接地、NPC/入口遮挡与已发布 SWF。新进入游戏后核对实际镜头、天气光照、前线通行；离线预览不代签正式入口人眼验收。

后续若恢复动画，必须将动态部分移出会被烘焙/卸载的背景层，并另做生命周期和性能验证。
