# 书架 v4 维护源文件补充包

本包与先前的 `bookshelf-interactive-v4-light.zip` 配合使用。补齐可编辑 Blender 场景、建模生成脚本、26 张完整 PNG 贴图及 v4 离线参考脚本；不重复打包运行代码与大幅渲染图片。

## 与轻量包合并

1. 先解压轻量包，得到 `bookshelf-interactive-v4-light/`。
2. 把本 ZIP 解压到相同的父目录，将同名文件夹合并。不要额外嵌套一层同名目录。
3. 合并后，`serve.py`、`web/`、`model-source/`、`render-reference.py`、本说明应处于同一目录。补充包不覆盖轻量包中的已有文件。
4. Web 预览仍运行 `python3 serve.py`；使用预览不需要 Blender。

## 哪些文件是维护依据

- **实体资产**：`model-source/bookshelf-v3.blend` 是当前交付的可编辑场景，包含书本、合集/单代盒、档案及旧版固定柜体，已内嵌全部 26 张贴图。它与 v4 完整包中的基础模型逐字节一致。
- **程序化模型生成**：`model-source/build.py`、`states.py` 和 `textures/` 是重建该 v3 资产的来源。`make_labels.py` 可重新排版通用中文档案标签和 CF 盒脊。`layout.json` 为 v3 布局描述/校验资料，`build.py` 的尺寸和位置仍写在脚本中，修改 JSON 不会自动改变模型。
- **v4 实际布局**：轻量包的 `web/modules/layout-core.mjs` 定义 wide / medium / narrow 的柜体尺寸与内容位置；`layout-three.js` 在运行时停用 v3 固定结构并程序化创建新柜体、重排实体。这两份代码才是 v4 自适应布局的依据。三个 v4 布局并未全部保存到 `.blend` 里。
- **v4 交互**：以轻量包的 `preview-shelf-scene.js`、`interaction-core.mjs`、`bookshelf-panel.js` 等活跃模块为准；详见 `web/modules/LAYOUT-MODULES.md`。Blender 的 `states.py` 仅是离线姿态辅助，不含网页交互状态机。
- **离线效果参考**：`render-reference.py` 从真实 `layoutFor()` 输出取得布局，再使用 Blender 渲染与 Pillow 合成面板；它不是浏览器截图工具。`references/actual-layouts.json` 是派生快照，修改布局后应重新生成，不要把它作为另一份独立布局源。

`.blend` 与生成脚本的角色不同：直接编辑 `.blend` 后，要把需要长期保留的程序化变更同步回 `build.py`，否则再次运行生成脚本会覆盖这些手工修改。先在副本上操作。

## 编辑和重建

已验证工具：Blender 4.3.2、Node.js 24.19.0；Pillow 12.3.0 已安装。核心建模只需 Blender 和本包自带 PNG。

从合并后的根目录执行以下命令，仅重建模型与元数据，不渲染：

```sh
blender -b -t 2 --python model-source/build.py -- --no-render
```

输出写入 `model-source/`，包括覆盖 `bookshelf-v3.blend`、生成 `bookshelf-v3.glb`、刷新语义节点与模型统计。当前 v4 活跃模型是 `web/assets/bookshelf/shelf/v3.glb`；确认新导出保留语义节点、材质、坐标约定和贴图，并复验后再手动替换。仅改 `.blend` 不会更新 Web 端 GLB。

书本、合集、单盒、档案根节点名和 `entryKey` 是交互/布局接口，不能随意改名。Blender 为 Z-up，正面 -Y；glTF 为 Y-up，正面 +Z，勿直接混用坐标。

重新生成标签是可选步骤：

```sh
python3 model-source/make_labels.py
```

需 Python 3、Pillow 和 Noto Sans CJK Regular/Bold。字体未随包分发，脚本默认 Linux 字体路径为 `/usr/share/fonts/opentype/noto/` 下的 `NotoSansCJK-Regular.ttc` 与 `NotoSansCJK-Bold.ttc`；其他平台请改为自己机器上的相应字体路径。已有 PNG 可直接用于建模，无需先生成标签。

## 重现 v4 离线参考（按需执行，耗时）

从合并后的根目录依次执行：

```sh
python3 render-reference.py --snapshot
blender -b model-source/bookshelf-v3.blend -t 8 --python render-reference.py
python3 render-reference.py --compose
```

第一步需要 Node.js，直接调用轻量包的布局代码；第二步生成 5 组离线画布；第三步需要 Pillow 和上述两种字体，字体路径在 `render-reference.py` 的 `compose()` 中。输出写入 `references/`。这三步不保存/改写基础 `.blend`，但会覆盖相同名称的参考输出。当前补充包未附渲染 PNG，因此不能跳过第二步直接合成。

这些图不证明网页真实点击、触摸、WebGL 光照、帧率或生产游戏集成；相关验收边界仍以轻量包的 README 和 QA 为准。

## 本包验证

- Blender 4.3.2 非交互打开成功；26 张纹理全部内嵌、可解码，且内嵌字节与外置 PNG 一致；无链接外部 `.blend` 库，必需语义节点齐全。
- 在独立临时目录用所附脚本与贴图执行 `--no-render`，导出的 GLB 与轻量包活跃 `v3.glb` SHA256 一致。
- 检查了与轻量包的文件合并关系、布局快照和源码哈希、ZIP CRC；详见 `source-qa/` 与 `source-package-manifest.json`。
- 本次没有重跑参考渲染，没有改原始包、正式仓库或用户电脑，没有做新的浏览器验收。

只读场景检查可重跑：

```sh
blender -b model-source/bookshelf-v3.blend --python source-qa/verify-blend.py
```

它只写 `source-qa/blend-dependencies.json`，不保存场景。

`model-source/README-v3-original.md` 为历史来源说明，其中提及的旧预览图片、GLB 与旧 QA 目录未在此补充包重复附带；请优先按本说明使用。原素材来源和已知 CF5 封面文字异常保留在该说明及 `model-source/source-manifest.json` 中。
