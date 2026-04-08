# Linkage Scanner - Flash 资产溯源工具

扫描 `flashswf/` 下所有 XFL 目录和 FLA 文件，提取 `linkageExportForAS` 导出符号，生成 linkageIdentifier -> 源 SWF 的映射表，并检测同名 ID 冲突。

---

## 解决的问题

游戏运行时通过 `attachMovie(linkageId)` 使用资产，但完全无法溯源该符号来自哪个 SWF 文件。当多个 SWF 导出同名符号时，后加载的会静默覆盖先加载的，造成难以排查的 bug。

## 快速开始

```bash
# 从项目根目录运行（默认排除归档目录）
python tools/linkage_scanner/scan_linkage.py
```

## 命令行参数

| 参数 | 说明 |
|------|------|
| (无参数) | 扫描生产源，输出 XML + 控制台报告 |
| `--include-all` | 包含默认排除的归档目录（`unused/`、`renew/`） |
| `--xml-only` | 只生成 XML，不打印控制台报告 |

默认排除的目录（非生产源）：`unused/`（废弃归档）、`renew/`（翻新对照）。

## 输出产物

### `data/items/asset_source_map.xml`

```xml
<!-- 无冲突条目 -->
<asset id="图标-方舟碎片" swf="flashswf/arts/素材库-物品技能图标.swf" />

<!-- 冲突条目（同一 linkageId 出现在多个 SWF 中） -->
<conflict id="近战子弹">
  <source swf="flashswf/arts/things0.swf" />
  <source swf="flashswf/arts/原版素材库-子弹.swf" />
</conflict>
```

### 控制台报告（省略 `--xml-only` 时）

- 唯一 linkageIdentifier 总数
- 冲突列表（每个冲突 ID 及其所有来源）
- 各源文件导出数量排行

## 工作原理

1. **XFL 目录**：直接读取 `LIBRARY/**/*.xml`，正则匹配 `linkageExportForAS="true"` + `linkageIdentifier`
2. **FLA 文件**：FLA 本质是 ZIP，按 local file header 逐条解析（支持 store/deflate 及 data descriptor 标志位 0x08），提取 LIBRARY XML 内容，无需解压到磁盘
3. **去重规则**：同一源内的重复 ID 只算一次（`seen_in_source` set，`source_counts` 取 `len()`）；XFL 目录存在时跳过同名 FLA
4. **XML 安全**：输出属性值过滤 XML 1.0 非法字符（U+FFFE/U+FFFF、控制字符等），确保标准解析器可正常读取

## 典型工作流

1. 新增/修改了 FLA 或 XFL 后，运行一次脚本刷新映射
2. 检查控制台输出的 CONFLICTS 部分，确认无意外冲突
3. `asset_source_map.xml` 可被其他工具或运行时代码引用，实现资产溯源

## 统计数据（2026-04-08）

| 指标 | 值 |
|------|-----|
| 唯一 linkageIdentifier | ~5624 |
| 来源文件 | ~146 |
| 冲突（排除 unused） | ~1879 |

## 文件说明

| 文件 | 说明 |
|------|------|
| `scan_linkage.py` | 扫描主脚本 |
| `README.md` | 本文档 |
