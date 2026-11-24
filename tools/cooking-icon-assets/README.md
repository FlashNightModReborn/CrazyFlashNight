# 烹饪食材与料理图标装配

本工具将 62 张 128×128 透明背景烹饪位图（50 项食材与 12 项料理）装配进现役物品图标库 `flashswf/arts/素材库-物品技能图标/素材库-物品技能图标.xfl`，并绑定 4 项厨具料理的独立图标映射与双帧 Web 派生图标。逐项 SHA-256、CRC32、itemID 与 `.dat` 缓存编号见 `manifest.json`。

## 源稿与映射

- 62 张透明 RGBA PNG 原稿保存在 `flashswf/arts/素材库-物品技能图标/LIBRARY/食材相关/位图/<icon_key>.png`，`manifest.json` 校验其 `rgba_sha256` 与 `png_sha256`。
- 食材「鸡肉」沿用 `<icon>鸡腿</icon>`（对应 `图标-鸡腿`）；其余 49 项食材与 12 项料理均为同名映射。
- 4 项厨具料理「蒜蓉烤茄子」「蜜汁烤鸡」「酥炸大虾」「瑶柱蒸蛋」在 `data/items/消耗品_药剂_食品.xml` 中由原临时借用的食材图标改为各自独立 `<icon>`，并同步重算 `<sourceDigest>` 及 `tools/cf7-balance-tool/records/potion-balance-audit.xml`。
- 每个 `食材相关/图标-<icon_key>.xml` 保持 4 层 2 帧结构：第 1 帧包含 `stop();`、底板、红框与中心定位的 128×128 位图实例（`matrix a=d=0.1953125, tx=ty=-12.5`）；第 2 帧仅保留无框透明位图本体。
- 双帧底框参考位图保存在 `frames/food_bg.png` 与 `frames/food_border.png`。

## 重建与验证

需要 Python 3、Pillow 及项目图标烘焙/平衡校验工具（`tools/cf2-boss-assets/bitmap.py`、`tools/bake-icons-offline.py`、`tools/cf7-balance-tool/packages/cli/src/potion-balance.ts`）。在仓库根目录运行：

1. 写入 XFL 位图缓存、`DOMDocument.xml`、62 个图标包装元件与食品 XML/平衡审计：

```powershell
python -B -X utf8 tools/cooking-icon-assets/build.py --build-xfl
```

2. 使用真实 Flash CS6 GUI 发布共享库 SWF（遵循 `scripts/FlashCS6自动化编译.md`）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target "flashswf/arts/素材库-物品技能图标/素材库-物品技能图标.xfl" -PublishOnly -VerifySwf "flashswf/arts/素材库-物品技能图标.swf" -TimeoutSeconds 180
```

3. 新增 4 个料理 linkage 后刷新道具链接清单与材料字典派生物，并按编译后 SWF 生成 Web 双帧无损 `.webp`：

```powershell
python -B -X utf8 tools/linkage_scanner/scan_linkage.py --xml-only
python -B -X utf8 tools/derive-material-catalog.py derive
python -B -X utf8 tools/cooking-icon-assets/build.py --bake-web
```

4. 执行全链路只读校验（核对 XFL、XML、SWF `ExportAssets` + `DefineBitsLossless2` 像素一致性、材料字典派生闭环及 124 个 WebP 文件与 `launcher/web/icons/manifest.json`）：

```powershell
python -B -X utf8 tools/cooking-icon-assets/build.py --check
python -B -X utf8 tools/derive-material-catalog.py --check
python -B -X utf8 tools/test-material-catalog.py
```

由于离线回读与静态审计不能替代客户端实际渲染表现，刷新完成后需重启游戏并在背包、商店、地面掉落与烹饪面板中确认展示效果。
