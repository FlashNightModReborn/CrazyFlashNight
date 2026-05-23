# XFL 命名 / 引用治理工具（XFL 工具栈 Layer 0 · 校准层）

> **本目录定位**：[docs/xfl-agent-工具栈-长期路线-2026-05-24.md](../../../docs/xfl-agent-工具栈-长期路线-2026-05-24.md) 中的 **Layer 0 校准层**。
> 角色：每次 FLA 施工后跑一遍，做内部一致性体检 + 明确无歧义的修复。不做创造性操作。Layer 1+ 见路线图，未到触发条件不建。
>
> 一次性脚手架不进这里。这里只放每次 FLA 施工后能直接跑、跑了不会出错的工具。
> 治理对象：任意 XFL 目录（`flashswf/arts/things/`、`flashswf/arts/things2/`、`flashswf/arts/new/<某目录>/` 等），即任何含 `DOMDocument.xml` + `LIBRARY/` 的目录。

## 标准流程

每次在 Flash CS6 里改 FLA 后（保存为 XFL 后）：

```bash
ROOT=flashswf/arts/things   # 改成本次施工的 XFL 目录

# ① 跑前体检：看有没有重名 / linkageId 撞车 / 失效 include / 残留 Symbol NNN
python scripts/tools/xfl/audit.py $ROOT

# ② 如果 audit 报告 [3] 有 linkageId 撞车 → 必须先回 CS6 手工修，工具不动它
#    （历史上的 copy-paste 错误，自动改会丢内容；典型例：M134 / M202火箭发射器）

# ③ 把仍叫 "Symbol NNN" 的 A 类符号改成 linkageIdentifier 名
python scripts/tools/xfl/rename_a_class.py $ROOT          # 真改
python scripts/tools/xfl/rename_a_class.py $ROOT --dry-run # 预览

# ④ 如果手工 CS6 里挪过 LIBRARY/ 下文件位置 → 修 DOMDocument.xml 的 Include href
python scripts/tools/xfl/fix_includes.py $ROOT

# ⑤ 复检 + 重扫资产表
python scripts/tools/xfl/audit.py $ROOT
python tools/linkage_scanner/scan_linkage.py --xml-only   # 重写 data/items/asset_source_map.xml
```

退出码：所有脚本在「干净」时返回 0，「需要后续处理」时返回非 0；CI / agent 都可以靠 `$?` 判定。

## 三个脚本

| 脚本 | 改文件？ | 用途 |
|---|---|---|
| [audit.py](audit.py) | 否 | 只读检查 7 项：残留 Symbol NNN / 重名 / linkageId 撞车 / 失效 Include / Include↔itemID 错配 / 失效 libraryItemName / 孤儿 LIBRARY 文件 |
| [rename_a_class.py](rename_a_class.py) | 是 | A 类符号 `Symbol NNN` → `linkageIdentifier`；同步 DOMSymbolItem.name、DOMTimeline.name、文件路径、全部 libraryItemName 引用；自动跳过冲突 |
| [fix_includes.py](fix_includes.py) | 是 | 按 itemID 把 DOMDocument.xml 中失效的 `<Include href=...>` 重映射到当前文件位置 |

支持 `--help`；写操作脚本支持 `--dry-run`；位置参数 = XFL 根目录（也可以传 `LIBRARY/` 或 `DOMDocument.xml`，自动归一）。

## 设计原则

1. **不擅自解 linkageId 冲突**：两个 A 类符号声明同一个 `linkageIdentifier` 时，`audit` 只报告，`rename_a_class` 跳过——必须人工去 CS6 改。理由：这通常是历史 copy-paste，自动改会把美术内容关联错。
2. **itemID 是唯一稳定锚**：CS6 给每个 symbol 分配的 itemID 在 rename / 移动后不变；`fix_includes` 完全靠它兜底。
3. **不缓存、不跨调用持久化**：每次跑都从磁盘重新扫——FLA 状态变化大，靠缓存反而容易出错。
4. **共享逻辑放 [_common.py](_common.py)**：三个脚本都是薄壳；新增脚本继续放这里、复用 `_common`。

## 已知不足

- 不识别 `linkageImportForRS` / 共享库符号（项目里没用到）。
- 不动 `Layer 1` / `图层 1` 一类的中文图层名规范化（目前没需求）。
- 多 XFL 一次扫还没做（每次只针对一个根目录）。如果需要，写个 shell wrapper 比改脚本干净。
