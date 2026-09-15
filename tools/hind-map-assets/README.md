# 雌鹿 G04 静态地图装配

G04 交接包当前成品为 G03R1 A 兵团重损坠毁静态终版。接入后唯一静态编辑源是 `flashswf/backgrounds/gk1_4_BG_坠毁/LIBRARY/Codex/雌鹿G04/`（authority 即唯一消费者自身，不为单消费者素材在无关地图间搬运闭包——这是与犀牛/猛虎「真源集中外交基地」的有意偏离）。FactionSlot 冻结 A 帧，原生遮罩与渐变保留，全单帧 Graphic，零脚本零位图零 linkage。

**时间线纪律**：坠毁残骸属于主线 #34 剧情节点，**不得烘焙回公共原图**。`gk1_4_BG`（新手练习场图4）保持原样；残骸只进变体背景 `gk1_4_BG_坠毁.swf`（原图的完整 XFL 副本加残骸闭包），前置关图 1 引用变体，原图玩家旅程不变。前置关图序按维护者 2026-09-16 裁定将错就错：图 1＝练习场图 4 变体，其余两关顺延练习场图 3／图 2 变体，设计文档 §4.1 的 3→2→1 逆序待下次修订同步。

## 比例与摆放

参数真源为 [placements.json](placements.json)。G03R1 总成实测包围盒 x 113.5–1085.5、y 99.5–454 作者单位（自交接包 3200×1440 舞台导出 alpha 换算）。0.75 倍显示 729px 散布；机头朝左指向玩家入场 (77,389)，接地线 y=258 压在行走区上缘 y≥274 之后，右缘断尾至 x≈859。残骸自带接地关系，不另加接地阴影，不用 0.86 压暗（近景叙事主体）。

| 地点 | 摆件 | 世界原点 | 显示倍率 |
|---|---|---|---|
| gk1_4_BG_坠毁（练习场图4变体，主线34前置关图1） | 坠毁 | (44.9,-82.5) | 75%，无旋转，无车号 |

`insertBeforeLayer: Layer 6`：残骸位于全部 12 块地砖之上、顶部装饰条（Symbol 7/9/11）之下；不增加碰撞，不改变关卡脚本与刷怪。

## 编辑与发布

```powershell
python -B -X utf8 tools/hind-map-assets/build.py
python -B -X utf8 tools/hind-map-assets/build.py --check
```

日常修改基础分件后同步；`--import-xfl` 只用于首次读取交接 XFL，不要用它覆盖已有改稿。发布：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/backgrounds/gk1_4_BG_坠毁/gk1_4_BG_坠毁.xfl" -PublishOnly -VerifySwf "flashswf/backgrounds/gk1_4_BG_坠毁.swf" -TimeoutSeconds 240
```

只发布这张背景，不编 main/asLoader，不涉及 Launcher runtime。发布后核对新鲜 Compiler Errors、SWF 刷新、导出集合仍为 0、帧脚本 `_root.贴背景图()` 仍在（FFDec `-dumpSWF` 比对 DoAction）。整图预览与观感由 CS6 放大的临时副本或测试员实机验收，离线渲染不代签。

首次接入记录（2026-09-16）：86 元件闭包（85 真源 + 1 坠毁摆件包装）入变体库并发布 `gk1_4_BG_坠毁.swf`（136957 字节），原图 `gk1_4_BG.swf` 字节还原不动；变体 DoAction 字节一致、导出集合 0、FFDec 视口渲染与原方案一致；`--check`、XFL audit、linkage scanner 无新增问题。
