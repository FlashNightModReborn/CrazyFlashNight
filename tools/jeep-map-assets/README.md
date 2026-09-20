# 战斗吉普 P13 静态地图装配

本工具只把归档 XFL 的 `Jeep/G01/DamagedRetained` 冻结为单帧 Graphic 闭包，补两级柔和接地影，派生到 `废城环线地图3` 的 `Codex/战斗吉普P13/` 命名空间。吉普停在右上路肩和破损围栏旁，车头朝右、车尾朝左对着仪器，表现受损后撞断围栏停车并从后部卸载仪器。`data/environment/stage_environment.xml` 只在可见车辆占区登记独立矩形碰撞，阻止玩家和 AI 站进车体；道路下半部保持完整通行，不用从地图上界延伸出的空气墙补偿背景烘焙。阴影与碰撞彼此独立。工具不执行外部交接包脚本、不导入 AS3、不产生 linkage，也不处理 70002 的动态状态。

```powershell
python -B -X utf8 tools/jeep-map-assets/build.py
python -B -X utf8 tools/jeep-map-assets/build.py --check
```

目标 XFL 首次由历史 `flashswf/backgrounds/废城环线地图3.fla` 展开得到；2026-09-19 经游戏内人验确认路肩位置、朝向和碰撞方案后，旧 FLA 退出编辑链，完整 `flashswf/backgrounds/废城环线地图3/` XFL 成为唯一编辑源。发布：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/backgrounds/废城环线地图3/废城环线地图3.xfl" -PublishOnly -VerifySwf "flashswf/backgrounds/废城环线地图3.swf" -TimeoutSeconds 180
```

机器门只证明结构和发布。实际比例、阴影、遮挡、仪器可见性、玩家/AI 绕行及通路由废城环线第三段人眼验收。
