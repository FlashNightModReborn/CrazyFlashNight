# 交互书架 v4 的维护源

此目录保存用户交付的 Blender 场景、建模脚本、26 张贴图、配对 GLB 与定向检查。正式页面仍使用 `launcher/web/modules/bookshelf-panel.js`，阅读、原版游戏、角色切换和存档权威保持原有通道；不部署预览包的模拟 Bridge、Reader 或 PanelScale。

## 真源与导入

- `model-source/bookshelf-v3.blend`：实体模型的可编辑源，已内嵌贴图；v3 是基础资产版本，v4 的三个柜体布局由运行代码生成。
- `model-source/build.py`、`states.py`、`textures/`：程序化建模源。重建会覆盖同目录 `.blend`，手工修改应先备份并同步回生成脚本。
- `model-source/bookshelf-v3.glb`：交付的配对导出。本次装配核对了模型、贴图及语义节点，未在本机运行 Blender 重建；`source-qa/` 是交付方证据。
- [布局与交互模块](../../launcher/web/modules/bookshelf/shelf/)：`layout-core.mjs` 是三个布局的真源，`layout-three.js` 负责装配，`interaction-core.mjs` 负责机械交互。
- `references/actual-layouts.json`：从真实布局模块生成的参考快照；不作为另一份布局真源。
- `upstream-package-manifest.json` 和 `UPSTREAM-SOURCES_README.zh-CN.md`：原交付包的记录，路径、命令及旧预览描述只适用于原包。仓库维护以本文为准。

在仓库根目录执行；模型重建需要 Blender 4.3.2，布局与检查使用 Node.js 22 或更高版本：

```powershell
blender -b -t 2 --python tools/bookshelf-v4/model-source/build.py -- --no-render
python tools/bookshelf-v4/render-reference.py --snapshot
python tools/import-bookshelf-shelf.py
python tools/import-bookshelf-shelf.py --check
```

导入器从配对导出生成运行端 `v3.glb`、`v4-manifest.json` 与整体 `manifest.json`，复核语义节点、内嵌贴图、来源字节及尺寸预算。它同时保留藏书目录所需的书脊/封面纹理及旧提取溯源，不从 Blender 重建几何。正式场景在载入时验证模型指纹，失败时保留目录并提供重试。

`make_labels.py` 与离线参考图合成使用 Pillow 和 Linux Noto 字体路径；重新排版这些交付贴图前需配置本机字体。运行端角色档案标签从权威快照绘制，替换原模型的示例文字，不依赖这些演示贴图。

## 定向验证

```powershell
node launcher/web/modules/bookshelf/shelf/layout-core.test.mjs
node tools/bookshelf-v4/tests/test-scene.mjs
node tools/bookshelf-v4/tests/test-layout.mjs
node tools/bookshelf-v4/tests/test-camera.mjs
node tools/test-bookshelf-runtime.js
node tools/test-bookshelf-original.js
node tools/test-bookshelf-shelf.js
node tools/run-bookshelf-flow-harness.js
```

检查输出写入 `tmp/`。前三维检查使用真实模型与 Three 数学、模拟 DOM/renderer；浏览器 harness 使用生产页面和模拟 Host/AS2 回执，不读写真实存档。`--serve-only --port=8765` 可提供该浏览器验证页面；Playwright 可用 `CF7_PLAYWRIGHT_MODULE` 指向已有依赖。实际游戏旅程与 Blender 重新导出仍需分别验证。
