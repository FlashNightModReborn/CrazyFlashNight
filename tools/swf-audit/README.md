# tools/swf-audit — SWF / 地图层审计工具

基础 SWF 扫描为纯 Python，无需 ffdec / JVM。ScreenShake 发布后门另用 FFDec 导出 AVM1。
首次产出于 2026-05-20「背景层卡顿审计」（commit `0f6c8c4ac` 后续）。

## swfscan.py — 通用 SWF 扫描器（核心工具，可复用）

直接解析 SWF 二进制：FWS/CWS/ZWS 解压 → RECT 尺寸 → 标签遍历 →
`DefineShape*` / `DefineBits*` / `DefineSprite` 等直方图 → 递归提取
`PlaceObject2/3` 的**实例名**（含 PlaceObject3 ClassName/Filter 标志位的正确处理）。

```bash
# 扫描目录或单文件，输出 UTF-8 JSON
python tools/swf-audit/swfscan.py -o out.json flashswf/levels flashswf/backgrounds
python tools/swf-audit/swfscan.py flashswf/levels/地图-靶场.swf      # 不带 -o 则打 stdout
```

每个 SWF 产出：`bytes sig ver w h frames fps shapes bitmaps sprites actions names[]`。
典型用途：查某地图是否含某命名实例、统计矢量/位图占比、批量取尺寸。
注意：`print()` 在 GBK 控制台会炸，务必用 `-o` 写文件，再用 Python 读 JSON。

## ScreenShake 源码门与发布后 SWF 门

使用 Python 3.11+ 和 lxml。把 `AUDIT_OUT` 设为仓库外的绝对目录。

```bash
python tools/swf-audit/camera_write_scan.py --repo . --out "$AUDIT_OUT"
python tools/swf-audit/camera_write_gate.py --inventory "$AUDIT_OUT/source-writes.json" \
  --mode new --report "$AUDIT_OUT/new-gate.json"
python tools/swf-audit/verify_published_swfs.py --repo . --out "$AUDIT_OUT/published"
python -m unittest discover -s tools/swf-audit -p "test_*.py" -v
```

全量源码扫描读取当前工作树的 Git 跟踪文件和未忽略的新文件，覆盖 AS2、含脚本的 XFL XML 和 ZIP FLA 源稿。
`--paths <file> ...` 可做局部诊断。全仓门要求与 inventory 同批生成的 coverage JSON，默认从同目录读取，也可显式传入 `--coverage`。
`new` 和 `live-clean` 都检查 30 条已删指纹、11 个 XML 的现役源码闭包和全仓新增写入，并逐条列出 26 条历史债。
`clean` 额外拒绝任何剩余历史债。写入违规退出 2，指定 `--require-complete-coverage` 时，写入检查通过但覆盖未决退出 3。
JSON 保留解析失败、动态审阅项、非 ZIP FLA 和扫描分母。

六库实际发布后运行 SWF 门。Java 默认从 `JAVA_HOME`、PATH、Adobe Animate 2024 的 JRE 依次查找，可用 `--java` 指定。
工具为六个目标各导出 AS2 和 P-code，核对原始 AVM1 动作数、Import/Export 名称、11 个导出锚点和源稿新鲜度。
每个导出进程使用 768 MiB heap，动作超时 15 秒，导出超时 100 秒，墙钟上限 120 秒，最多并行四个进程。
每次运行生成新目录及 `published-swf-receipt.json`，记录 XML、SWF、策略、FFDec JAR、脚本导出的 SHA-256 和验证结果。
两道门均为有界静态检查，动态行为、实际加载和游戏体验仍需按专项验收。

## audit_levels.sh — levels 背景实例覆盖度审计

对 `flashswf/levels` 每张地图（dir / FLA-zip / ffdec 反编译纯 SWF）检查是否含
实例名「背景」「deadbody」的 `DOMSymbolInstance`，判定能否被 `_root.贴背景图()` 烤位图。
依赖 `tools/ffdec/`（仅用于无 FLA 的纯 SWF）。

## analyze.py — 汇总报告

读 `swfscan.py` 的 JSON + `data/environment/*.xml`，交叉核对背景实例覆盖度、
环境 XML 一致性（重复单值标签 / 几何字段 / Skybox 文件存在性）、backgrounds 体量与孤儿。
输出 `tmp/bg-audit/REPORT.txt`。

## 复跑流程

```bash
python tools/swf-audit/swfscan.py -o tmp/bg-audit/scan_levels.json flashswf/levels
python tools/swf-audit/swfscan.py -o tmp/bg-audit/scan_bg.json flashswf/backgrounds flashswf/backgrounds/elements
grep -rhoE "[A-Za-z0-9_一-龥]+\.swf" data/ scripts/ flashswf/levels/*/DOMDocument.xml \
  | sort | uniq -c | sort -rn > tmp/bg-audit/swf_refs.txt
python tools/swf-audit/analyze.py
```
