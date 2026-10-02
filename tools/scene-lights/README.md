# 场景光源检查

运行时预设的唯一编辑源是 [scene_lights.v1.json](../../data/environment/scene_lights.v1.json)。场景和子图的 `Lights/Light` 保存覆盖值，实例的 `LightKey` 提供稳定绑定身份。字段、状态 API 与人工验收顺序见 [场景光源配置与验收](../../docs/场景光源-配置与开发验收-2026-10-01.md)。

```powershell
python -X utf8 tools/scene-lights/validate.py --check
python -X utf8 -m unittest discover -s tools/scene-lights -p test_validate.py
powershell -File scripts/run-scene-lighting-tests.ps1 -TimeoutSeconds 240
```

检查器只读所有环境与关卡 XML，验证预设、字段、有限数值、稳定键、绑定、继承覆盖、曲线和容量。它不改关卡、存档、素材或运行库。Flash suite 验证真实 MovieClip 的坐标、镜像、显隐、替换与三种现役外部 SWF 的异步装载。

GPU 夹具在自己的来源窗口中验证 32 个缓存灯、像素复用、平移缩放、实时光变化隔离、夜视色向和清理：

```powershell
dotnet run --project launcher/perf/combat-fx/CombatFxProbe.csproj -- <仓库绝对路径> <配套原生DLL绝对路径> <输出目录> --scene-lights
```

实际执行使用仓库 `launcher/resolve-dotnet.ps1` 指定的 SDK。夹具不启动游戏或读取存档，报告绑定原生 DLL SHA；材料网格像素不能代签游戏场景观感、输入或弱机帧率。
