# 弹药图标 r06 装配

本工具将已验收的 22 张 SVG 转为可编辑的 XFL 原生形状，装入现役图标元件。输入保存在 `flashswf/arts/new/Codex素材源稿/弹药图标r06/`；逐项来源、SHA256、元件名及适配尺寸见 `assembly.json`。

## 源稿与元件

- 01–21 属于 `flashswf/arts/素材库-物品技能图标/素材库-物品技能图标.xfl`。
- 22 属于 `flashswf/arts/new/偷吃屑鱼坟头贡品/偷吃屑鱼坟头贡品.xfl`。
- 每项新增 `Codex/弹药r06/编号-名称` 单帧 Graphic；外层 MovieClip 保留原 linkage 和注册点。新图按可见轮廓等比适配原最长边及中心。
- 06「高温自锐式针弹」新增独立导出及物品 icon 字段，结束与 14「机枪贫铀穿甲弹」共图。
- 22 保留原两帧、第一帧 `stop()`、遮罩和底影，分别替换两帧图像。两帧不应作为自动播放动画。

06 仍随现有「素材库-物品技能图标」共享库锚点载入。主文件已经直接导入并放置该锚点，导入表不逐个枚举弹药图标；本次在库内增加导出，不需要重编主文件或修改 things-new/things0。

转换复用 `tools/tesla-map-assets/native_vector/vector_shapes.py` 的 `ShapeConverter`，尊重 SVG 的 nonzero/evenodd 填充规则。使用居中的 128px 母版减小 twip 舍入误差；不嵌入位图、不增加图稿脚本。不能直接改用 legacy Writer 绕过填充规则归一化。

## 重建与检查

需要 Python 3、项目矢量转换器的依赖；本次验证使用 NumPy 2.3.5、Shapely 2.1.2、skia-pathops 0.9.2。依赖可装在隔离环境，无需修改系统 Python。

在仓库根目录运行：

```powershell
python -B -X utf8 tools/ammo-icon-assets/build.py --check
python -B -X utf8 tools/ammo-icon-assets/build.py --report tmp/ammo-r06-build.json
```

`--check` 比较生成结果与现有编辑源，不写源文件。普通模式会替换这批元件的图稿，运行前应保存需要保留的人工修改。输入 SHA 不一致即停止；更换已验收版本时须明确更新输入和配置。

工具仅生成 XFL 和 06 的物品映射，不写 SWF。用仓库 `scripts/compile_test.ps1` 分别对上述两个 XFL 执行 `-PublishOnly -VerifySwf <对应同名SWF> -TimeoutSeconds 180`；遵循 `AGENTS.md` 的 CS6 发布与新鲜编译日志要求。

## 刷新派生图标

新增 linkage 后，用 `tools/linkage_scanner/scan_linkage.py --xml-only` 重建 `data/items/asset_source_map.xml`，审查整份生成差异。

然后用 `tools/bake-icons-offline.py` 对 `assembly.json` 对应的 **22 个不同裸 icon 名** 定向刷新，参数为 `--scope items --asset-map data/items/asset_source_map.xml --image-format webp --icon-size 128 --export-animated-frames --force-overwrite-existing --strict`，逐项添加 `--name`。使用已验证的 FFDec 入口和 `repo/tmp` 下专用临时目录，保存报告。先 `--resolve-only`，再实际烘焙，最后 `--dry-run` 检查幂等。

须核对目标数和处理数都是 22；`--strict` 本身不能发现过滤时遗漏的名称。检查无解析/导出/保护错误、非目标 manifest 条目保持、来源 SHA 绑定本次 SWF、22 的第二帧非空且与第一帧不同，并人工看实际导出的深浅底小图。不能把源稿 PNG 直接复制为 Web 派生物来代替 SWF 回读。

现有 Web 图标使用稳定 URL 和内存缓存。完成刷新后完整退出并重启游戏，再从背包、商店等实际入口验收。离线回读和编译通过不等于游戏内观感验收。
