# 猛虎 G05 静态地图装配

G05 交接包中的最终画稿为 G04 Final。接入后，唯一静态编辑源是 `flashswf/levels/地图-军阀基地/LIBRARY/Codex/猛虎G05/`；其他背景只复制使用中的元件闭包。原生色面、渐变和近侧轮组遮罩保留，轮纹固定第一帧，炮组固定10°俯仰，移除全部 AS3 脚本。没有新的帧更新、开火演出、全局 linkage 或独立运行时素材库。

## 比例与摆放

参数真源为 [placements.json](placements.json)。猛虎车体1377.448px，犀牛车体1293.8px；两者同倍率时长比1.064653。同平面45%得到猛虎619.852px、犀牛582.21px，按既有人物根空间82.9673px/m约为7.47m和7.02m。该量是共同视角下的车体投影长度，不是炮管总长或俯视占地面积。保留等比缩放，不能另乘1.06或压扁轮胎来制造瘦弱外形。

| 地点 | 猛虎车号 | 世界接地点 | 显示倍率 |
|---|---|---|---|
| 外交军阀基地中间后景，替换26号犀牛 | 41 | (1070,185) | 23% |
| 防御地带高地，替换解放卡车 | 42 | (400,340) | 45%，右向，顺坡-2° |
| 军阀前线基地第二张图，三组帐篷后 | 43、44、45 | (250,200)、(860,205)、(1650,205) | 24%、25%、24% |

外交基地保留25/27号犀牛；前线第三张图22/23/28号犀牛的位置和遮挡维持既有结果。高地29号犀牛向右移至(990,320)，给猛虎留出间距。所有车辆仍位于行走区后方，不增加碰撞或改变关卡脚本。

原稿原点不在接地位置，外层平移(36.924,-78)以车体中心和近轮接地中点注册。背景继承偏移：外交(-25,-80)，前线(937.7,245.1)；高地按原点对齐。两个基地放在帐篷之后、地面之前，并使用RGB乘数0.86。

## 编辑与发布

```powershell
python -B -X utf8 tools/rhino-map-assets/build.py
python -B -X utf8 tools/tigr-map-assets/build.py
python -B -X utf8 tools/rhino-map-assets/build.py --check
python -B -X utf8 tools/tigr-map-assets/build.py --check
```

先同步犀牛，再同步猛虎；外交两种车辆的图层相邻。猛虎工具复用犀牛工具的 XML/闭包/摆放函数，分别限定命名空间。车号41–45是矢量笔画，右向包装局部反射，整车镜像后仍正读。日常修改基础分件后同步，不要重复 `--import-xfl` 覆盖已有改稿；该开关只用于首次读取外部原生 XFL。

前线第二图原仓库只有 `gk22_2_BG.swf`；从该现役文件导出可编辑副本，再由 CS6 原生保存为完整 `flashswf/backgrounds/gk22_2_BG/`。29个原有服装导出只调整库名为原 linkageIdentifier，不改运行时导出名称。完整 XFL 需包括 bin 位图数据；入口小文件不能单独交付。

对三个目标运行 XFL audit、rename_a_class、fix_includes；不需要修复时使用 dry-run。随后分别执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/levels/地图-军阀基地/地图-军阀基地.xfl" -PublishOnly -VerifySwf "flashswf/levels/地图-军阀基地.swf" -TimeoutSeconds 180
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/backgrounds/防御地带高地/防御地带高地.xfl" -PublishOnly -VerifySwf "flashswf/backgrounds/防御地带高地.swf" -TimeoutSeconds 180
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/backgrounds/gk22_2_BG/gk22_2_BG.xfl" -PublishOnly -VerifySwf "flashswf/backgrounds/gk22_2_BG.swf" -TimeoutSeconds 180
```

只发布这些地图，不编 main/asLoader，不涉及 Launcher runtime。核对新鲜 Compiler Errors、SWF刷新、原有导出集合和脚本数量、原生重开后轮腔/炮组/遮挡。离线整图预览不代表正式游戏镜头、天气与通行的人眼验收。CS6批量保存的无关改写按任务前快照还原，保留本次新增分件、摆放、Include和必需位图数据。

## 本轮验证（2026-09-14）

三目标已完成CS6原生保存/重开/整图PNG核对及独立发布，Compiler Errors均为0错误/0警告。导出名称集合分别维持1/0/29，脚本标签数量维持13/1/2，时间轴均1帧，MovieClip数量也维持34/0/54。SWF体积为外交1,605,559字节、高地589,109字节、前线第二图211,251字节。XFL三件套全部CLEAN；使用linkage scanner对三目标定向重扫，无新增载具导出。用户实机反馈高地和前线布置无问题；外交基地轮胎/履带穿帮已按截图修正，并获用户确认可行。本记录不外推天气、所有镜头或性能的完整验收。

本轮修正共用生成器的CS6 itemID兼容问题：第二段限制为有符号31位，否则CS6会将超范围值截成同一个`7fffffff`，导致保存时目录和引用串位。485个犀牛/猛虎元件的生成ID已核对互异；失败保存已撤销，最终保存后的引用与派生检查通过。CS6会合并/细分矢量边并量化颜色，因此以原生保存后的外交静态分件为真源同步消费者；保留原场景无关素材的任务前字节。

2026-09-14实机反馈修正：外交基地25号犀牛改为世界(640,165)、24%景深倍率；41号猛虎改为(1070,185)、23%，将履带/轮胎收进帐篷遮挡范围，避开帐篷下沿与阴影区。27号及其他地图位置不变，仅重发外交基地SWF。
