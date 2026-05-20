# tools/swf-audit — SWF / 地图层审计工具

纯 Python 的 SWF 静态分析工具，无需 ffdec / JVM，毫秒级解析单个 SWF。
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
