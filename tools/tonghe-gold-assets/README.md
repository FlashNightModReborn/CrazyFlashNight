# 统合金币：SVG → Flash → Web 图标

原始输入与配色位于 `flashswf/arts/new/Codex素材源稿/统合金币R4/`；模型投影规则位于 `coin_svg.py`。这是一套共享画稿，不维护网页专用的造型或侧纹版本。

```powershell
python -X utf8 -B tools/tonghe-gold-assets/build.py
python -X utf8 -B tools/tonghe-gold-assets/build.py --check
```

生成器更新归档中的 32 个 SVG 与清单，以及现有物品图标库中的两个元件：

- `消耗道具相关/图标-金钱`：保留导出 linkage 与中心注册点，单帧外壳挂载自播放子元件。
- `消耗道具相关/Symbol 4297`：32 帧连续角度、原生矢量遮罩、原徽记及模型 64 齿侧纹。

保留外壳是为了让可拾取物的 `gotoAndStop(2)` 不冻结内层旋转。内层使用 8 倍坐标、外壳精确缩放 0.125；最终画布仍为 28×28，内容约 24.77px，注册中心为 (0,0)。这一配置保留亚 twip 细节，也限制离线烘焙的中间图片尺寸。

SVG 的 `clipPath` 转成原生 XFL mask 层，曲线、渐变和侧纹色面均为矢量。SVG 用于隔离抗锯齿合成的 0.9999 opacity 只在外壳应用一次。构建不写 SWF；必须经真实 CS6 发布：

```powershell
powershell -NoProfile -File scripts/compile_test.ps1 -Target "flashswf/arts/素材库-物品技能图标/素材库-物品技能图标.xfl" -PublishOnly -VerifySwf "flashswf/arts/素材库-物品技能图标.swf" -TimeoutSeconds 240
```

本机缺少旧库里三个食材标签字体时，推荐改用带临时字体依赖的相同发布入口：

```powershell
python -X utf8 -B tools/tonghe-gold-assets/publish.py
```

它从 `compile-fonts/` 加载原 SWF 中的三个现有字形子集，只用于本次会话，发布完成后卸载；不写字体注册表，也不把其他物品标签替换成系统默认字体。字体来源与哈希见该目录清单。编译保护标记仍遵循仓库恢复流程，入口不会清理未决标记。

确认本轮 Compiler 0/0 与 SWF 刷新后，从实际发布 SWF 定向重新烘焙：

```powershell
python -X utf8 -B tools/bake-icons-offline.py --scope items --name 金钱 --export-animated-frames --animation-fps 30 --force-overwrite-existing --report tmp/tonghe-gold/rebake-report.json
```

先在 `--output-dir tmp/...` 生成候选并检查，再覆盖已有图标；强制覆盖仅限已确认的金钱图标。Java / FFDec 的当前环境和回退路径见 `tools/asset-workbench/README.md`，不要改全局 PATH。

Flash 发布、FFDec 候选、生产图标清单、浏览器实际播放分别验证。`--check` 只证明输入、SVG 和 XFL 派生一致，不替代 CS6、SWF 和真实消费者验收。

嵌套动画烘焙为 WebP 时，全周期采用同一取景与比例，避免静态首帧的紧裁切使旋转起点突然放大；静态封面仍保留现有紧裁切。成功迁移后会移除旧 PNG 序列的 `frames` / `timelineFrames` / `f2`，再写入本次实际生成的字段，防止预览回到旧图。

相关回归入口：`tools/test-icon-shared-animation-canvas.py`、`tools/test-icon-webp-migration.py`、`tools/test-icon-normalization.py`。发布后可运行 `python -X utf8 -B tools/tonghe-gold-assets/verify_swf.py` 检查真实 SWF 的 linkage、内外层帧数、遮罩与字体；该检查不代替播放器中的实际播放。
